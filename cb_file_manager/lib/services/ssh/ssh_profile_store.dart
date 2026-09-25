import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/ed25519.dart' as nacl;
import 'package:uuid/uuid.dart';

class SshProfile {
  final String id, name, host, username, password, group;
  final int port;
  final String? keyId;
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.username,
    this.port = 22,
    this.password = '',
    this.keyId,
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
    final pairs = SSHKeyPair.fromPem(pem, passphrase);
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
  Map<String, String> _knownHosts = {};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  List<SshProfile> get profiles => List.unmodifiable(_profiles);
  List<SshStoredKey> get keys => List.unmodifiable(_keys);
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
      final oldHosts = Map<String, String>.of(_knownHosts);
      try {
        change();
        await storage.write(
          key: storageKey,
          value: jsonEncode({
            'profiles': _profiles.map((e) => e.toJson()).toList(),
            'keys': _keys.map((e) => e.toJson()).toList(),
            'knownHosts': _knownHosts,
          }),
        );
        notifyListeners();
      } catch (_) {
        _profiles = oldProfiles;
        _keys = oldKeys;
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
    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
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
