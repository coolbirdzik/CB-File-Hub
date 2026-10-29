import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:uuid/uuid.dart';
import 'putty_private_key.dart';
import 'ssh_proxy.dart';
import 'ssh_proxy_socket.dart';
export 'ssh_proxy.dart';

class SshProfile {
  final String id, name, host, username, password, group;
  final int port;
  final String? keyId, proxyId;
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    this.port = 22,
    this.password = '',
    this.keyId,
    this.proxyId,
    this.group = '',
  });
  String get authority =>
      Uri(userInfo: username, host: host, port: port).authority;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'username': username,
    'port': port,
    'password': password,
    'keyId': keyId,
    'proxyId': proxyId,
    'group': group,
  };
  factory SshProfile.fromJson(Map<String, dynamic> j) => SshProfile(
    id: j['id'],
    name: j['name'],
    host: j['host'],
    username: j['username'],
    port: j['port'] ?? 22,
    password: j['password'] ?? '',
    keyId: j['keyId'],
    proxyId: j['proxyId'],
    group: j['group'] ?? '',
  );
}

class SshStoredKey {
  final String id, name, pem, publicKey, fingerprint;
  const SshStoredKey({
    required this.id,
    required this.name,
    required this.pem,
    required this.publicKey,
    required this.fingerprint,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pem': pem,
    'publicKey': publicKey,
    'fingerprint': fingerprint,
  };
  factory SshStoredKey.fromJson(Map<String, dynamic> j) => SshStoredKey(
    id: j['id'],
    name: j['name'],
    pem: j['pem'],
    publicKey: j['publicKey'],
    fingerprint: j['fingerprint'],
  );
  static SshStoredKey import(String name, String pem, [String? passphrase]) {
    final pairs = pem.trimLeft().startsWith('PuTTY-User-Key-File-')
        ? [decodePuttyPrivateKey(pem, passphrase)]
        : SSHKeyPair.fromPem(pem, passphrase);
    if (pairs.length != 1) throw const FormatException('Select one SSH key.');
    final pair = pairs.single;
    final bytes = pair.toPublicKey().encode();
    return SshStoredKey(
      id: const Uuid().v4(),
      name: name.trim(),
      // The OS credential vault protects the unlocked key at rest.
      pem: pair.toPem(),
      publicKey: '${pair.name} ${base64Encode(bytes)} ${name.trim()}',
      fingerprint:
          'SHA256:${base64Encode(sha256.convert(bytes).bytes).replaceAll('=', '')}',
    );
  }

  static SshStoredKey generate(String name) {
    final key = nacl.SigningKey.generate();
    final pair = OpenSSHEd25519KeyPair(
      Uint8List.fromList(key.verifyKey),
      Uint8List.fromList(key),
      name.trim(),
    );
    return SshStoredKey.import(name, pair.toPem());
  }
}

class SshImportSummary {
  final int hosts, keys, duplicates;
  final int proxies;
  const SshImportSummary(
    this.hosts,
    this.keys,
    this.duplicates, {
    this.proxies = 0,
  });
}

/// Profiles, passwords, private keys and trusted host fingerprints stay in the
/// OS credential vault. No private key is written to the app's SQLite database.
class SshProfileStore extends ChangeNotifier {
  static final instance = SshProfileStore();
  final FlutterSecureStorage storage;
  SshProfileStore({
    this.storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  });
  static const storageKey = 'cb.ssh.workspace.v1';
  List<SshProfile> _profiles = [];
  List<SshStoredKey> _keys = [];
  List<SshProxy> _proxies = [];
  Map<String, String> _knownHosts = {};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  List<SshProfile> get profiles => List.unmodifiable(_profiles);
  List<SshStoredKey> get keys => List.unmodifiable(_keys);
  List<SshProxy> get proxies => List.unmodifiable(_proxies);
  Map<String, String> get knownHosts => Map.unmodifiable(_knownHosts);
  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final raw = await storage.read(key: storageKey);
      if (raw == null) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _profiles = (j['profiles'] as List)
          .map((e) => SshProfile.fromJson(e))
          .toList();
      _keys = (j['keys'] as List).map((e) => SshStoredKey.fromJson(e)).toList();
      _proxies = (j['proxies'] as List? ?? [])
          .map((e) => SshProxy.fromJson(e))
          .toList();
      _knownHosts = Map<String, String>.from(j['knownHosts'] ?? {});
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> _change(void Function() change) {
    final operation = _writes.then((_) async {
      await load();
      final oldProfiles = List<SshProfile>.of(_profiles);
      final oldKeys = List<SshStoredKey>.of(_keys);
      final oldProxies = List<SshProxy>.of(_proxies);
      final oldHosts = Map<String, String>.of(_knownHosts);
      try {
        change();
        await storage.write(
          key: storageKey,
          value: jsonEncode({
            'profiles': _profiles.map((e) => e.toJson()).toList(),
            'keys': _keys.map((e) => e.toJson()).toList(),
            'proxies': _proxies.map((e) => e.toJson()).toList(),
            'knownHosts': _knownHosts,
          }),
        );
        notifyListeners();
      } catch (_) {
        _profiles = oldProfiles;
        _keys = oldKeys;
        _proxies = oldProxies;
        _knownHosts = oldHosts;
        rethrow;
      }
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> saveProfile(SshProfile p) => _change(() {
    _profiles.removeWhere((e) => e.id == p.id);
    _profiles.add(p);
  });
  Future<void> deleteProfile(String id) =>
      _change(() => _profiles.removeWhere((e) => e.id == id));
  Future<void> saveKey(SshStoredKey key) => _change(() => _keys.add(key));
  Future<void> saveProxy(SshProxy proxy) => _change(() {
    if (!proxy.isValid) {
      throw const FormatException('Invalid SSH proxy configuration.');
    }
    _proxies.removeWhere((p) => p.id == proxy.id);
    _proxies.add(proxy);
  });
  Future<void> deleteProxy(String id) => _change(() {
    if (_profiles.any((p) => p.proxyId == id)) {
      throw StateError('Proxy is used by a saved host.');
    }
    _proxies.removeWhere((p) => p.id == id);
  });

  /// Reuse the vault identity when the same local key is imported again.
  Future<SshStoredKey> importKey(SshStoredKey key) async {
    var selected = key;
    await _change(() {
      final existing = _keys.where((k) => k.fingerprint == key.fingerprint);
      if (existing.isNotEmpty) {
        selected = existing.first;
      } else {
        _keys.add(key);
      }
    });
    return selected;
  }

  /// One vault write: either every selected host/key is saved, or none is.
  /// Existing profiles and trust decisions are never replaced by an import.
  Future<SshImportSummary> importProfiles({
    required List<SshProfile> profiles,
    required List<SshStoredKey> keys,
    List<SshProxy> proxies = const [],
  }) async {
    var hostsAdded = 0, keysAdded = 0, proxiesAdded = 0, duplicates = 0;
    await _change(() {
      final routes = <String, String>{};
      for (final proxy in proxies) {
        if (!proxy.isValid) {
          throw const FormatException('Invalid SSH proxy configuration.');
        }
        final existing = _proxies
            .where((p) => p.sameConnection(proxy))
            .firstOrNull;
        if (existing != null) {
          routes[proxy.id] = existing.id;
          duplicates++;
        } else {
          final id = const Uuid().v4();
          routes[proxy.id] = id;
          _proxies.add(
            SshProxy(
              id: id,
              name: proxy.name,
              type: proxy.type,
              host: proxy.host,
              port: proxy.port,
              username: proxy.username,
              password: proxy.password,
            ),
          );
          proxiesAdded++;
        }
      }
      final identities = <String, String>{};
      for (final key in keys) {
        final existing = _keys.where((k) => k.fingerprint == key.fingerprint);
        if (existing.isNotEmpty) {
          identities[key.id] = existing.first.id;
          duplicates++;
        } else {
          final id = const Uuid().v4();
          identities[key.id] = id;
          _keys.add(
            SshStoredKey(
              id: id,
              name: key.name,
              pem: key.pem,
              publicKey: key.publicKey,
              fingerprint: key.fingerprint,
            ),
          );
          keysAdded++;
        }
      }
      for (final profile in profiles) {
        final keyId = identities[profile.keyId] ?? profile.keyId;
        final proxyId = routes[profile.proxyId] ?? profile.proxyId;
        if (proxyId != null && !_proxies.any((p) => p.id == proxyId)) {
          throw StateError('Import references an unavailable SSH proxy.');
        }
        if (keyId != null && !_keys.any((k) => k.id == keyId)) {
          throw StateError('Import references an unavailable SSH key.');
        }
        if (_profiles.any(
          (p) =>
              p.host.toLowerCase() == profile.host.toLowerCase() &&
              p.port == profile.port &&
              p.username == profile.username &&
              p.name == profile.name &&
              p.proxyId == proxyId &&
              p.group == profile.group,
        )) {
          duplicates++;
          continue;
        }
        _profiles.add(
          SshProfile(
            id: const Uuid().v4(),
            name: profile.name,
            host: profile.host,
            username: profile.username,
            port: profile.port,
            password: profile.password,
            group: profile.group,
            keyId: keyId,
            proxyId: proxyId,
          ),
        );
        hostsAdded++;
      }
    });
    return SshImportSummary(
      hostsAdded,
      keysAdded,
      duplicates,
      proxies: proxiesAdded,
    );
  }

  Future<void> deleteKey(String id) => _change(() {
    if (_profiles.any((p) => p.keyId == id)) {
      throw StateError('Key is used by a saved host.');
    }
    _keys.removeWhere((e) => e.id == id);
  });
  Future<void> trust(String host, int port, String fingerprint) =>
      _change(() => _knownHosts['${host.toLowerCase()}:$port'] = fingerprint);
  Future<void> forgetHost(String address) =>
      _change(() => _knownHosts.remove(address));
}

typedef SshTrustPrompt =
    Future<bool> Function(
      String host,
      int port,
      String type,
      String fingerprint,
      String? previous,
    );

class SshConnector {
  final SshProfileStore store;
  SshConnector([SshProfileStore? store])
    : store = store ?? SshProfileStore.instance;
  Future<SSHClient> connect(
    SshProfile profile, {
    SshTrustPrompt? trustPrompt,
    void Function(SSHClient)? onClientCreated,
  }) async {
    await store.load();
    final key = profile.keyId == null
        ? null
        : store.keys.where((k) => k.id == profile.keyId).firstOrNull;
    if (profile.keyId != null && key == null) {
      throw StateError('SSH key no longer exists.');
    }
    final identities = key == null ? null : SSHKeyPair.fromPem(key.pem);
    final proxy = profile.proxyId == null
        ? null
        : store.proxies.where((p) => p.id == profile.proxyId).firstOrNull;
    if (profile.proxyId != null && proxy == null) {
      throw StateError('SSH proxy no longer exists.');
    }
    final socket = await openSshTransport(
      profile.host,
      profile.port,
      proxy: proxy,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: profile.username,
      identities: identities,
      onPasswordRequest: key == null ? () => profile.password : null,
      onVerifyHostKey: (type, bytes) async {
        final fingerprint = utf8.decode(bytes);
        final previous =
            store.knownHosts['${profile.host.toLowerCase()}:${profile.port}'];
        if (previous == fingerprint) return true;
        if (trustPrompt == null ||
            !await trustPrompt(
              profile.host,
              profile.port,
              type,
              fingerprint,
              previous,
            )) {
          return false;
        }
        await store.trust(profile.host, profile.port, fingerprint);
        return true;
      },
      authTimeout: const Duration(seconds: 90),
    );
    onClientCreated?.call(client);
    try {
      await client.authenticated;
      return client;
    } catch (_) {
      client.close();
      rethrow;
    }
  }
}
