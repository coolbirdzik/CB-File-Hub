import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/x25519.dart' as nacl;

import 'chromium_indexed_db.dart';

class TermiusKeyUnavailable extends FormatException {
  const TermiusKeyUnavailable() : super('termius key unavailable');
}

class TermiusLocalReader {
  final String directory;
  const TermiusLocalReader(this.directory);

  /// Produces an in-memory portable document for the shared import validator.
  /// Nothing decrypted is written to disk or included in diagnostic messages.
  Future<Map<String, dynamic>> read(List<Uint8List> localKeys) async {
    final raw = await ChromiumIndexedDb(directory).readTables({
      'hosts',
      'keys',
      'ssh_identities',
      'ssh_configs',
      'groups',
      'proxies',
      'pf_rules',
      'ssh_config_identities',
      'ssh_config_identities_shared',
    });
    return normalize(raw, localKeys);
  }

  static Map<String, dynamic> normalize(
    Map<String, List<Map<String, dynamic>>> raw,
    List<Uint8List> localKeys,
  ) {
    final sample = _firstEncrypted(raw);
    Uint8List? selected;
    if (sample != null) {
      for (final key in localKeys) {
        try {
          _decrypt(sample, key);
          selected = key;
          break;
        } catch (_) {
          /* authenticate next candidate */
        }
      }
      if (selected == null) {
        throw const TermiusKeyUnavailable();
      }
    }
    final tables = <String, List<Map<String, dynamic>>>{};
    for (final entry in raw.entries) {
      final latest = <String, Map<String, dynamic>>{};
      for (final source in entry.value) {
        final row = _walk(source, selected, 0) as Map<String, dynamic>;
        final id = '${row['id'] ?? 'local:${row['local_id']}'}';
        final old = latest[id];
        if (old == null ||
            '${row['updated_at'] ?? ''}'.compareTo(
                  '${old['updated_at'] ?? ''}',
                ) >=
                0) {
          latest[id] = row;
        }
      }
      tables[entry.key] = latest.values
          .where(
            (r) =>
                r['is_deleted'] != true &&
                r['deleted'] != true &&
                r['deleted_at'] == null &&
                ![
                  'DELETED',
                  'DELETE_PENDING',
                  'DELETE_FAILED',
                ].contains(r['status']),
          )
          .toList();
    }
    Map<String, Map<String, dynamic>> index(String table) {
      final result = <String, Map<String, dynamic>>{};
      for (final r in tables[table] ?? <Map<String, dynamic>>[]) {
        if (r['id'] != null) result['id:${r['id']}'] = r;
        if (r['local_id'] != null) result['local:${r['local_id']}'] = r;
      }
      return result;
    }

    Map<String, dynamic> deref(
      dynamic ref,
      Map<String, Map<String, dynamic>> index,
    ) {
      if (ref is Map) {
        return index['id:${ref['id']}'] ??
            index['local:${ref['local_id']}'] ??
            {};
      }
      return index['id:$ref'] ?? index['local:$ref'] ?? {};
    }

    String id(Map r) => '${r['id'] ?? 'local:${r['local_id']}'}';
    bool hasRef(dynamic ref) => ref is Map
        ? ref['id'] != null || ref['local_id'] != null
        : ref != null && '$ref'.isNotEmpty;
    final configs = index('ssh_configs'),
        identities = index('ssh_identities'),
        groups = index('groups'),
        keys = index('keys'),
        proxies = index('proxies');
    final outputProxies = <Map<String, dynamic>>[];
    for (final proxy in tables['proxies'] ?? <Map<String, dynamic>>[]) {
      final auth = deref(proxy['identity'], identities);
      outputProxies.add({
        'id': id(proxy),
        'label': proxy['label'] ?? proxy['hostname'] ?? '',
        'type': proxy['type'] ?? '',
        'host': proxy['hostname'] ?? proxy['host'] ?? '',
        'port': proxy['port'],
        'username': auth['username'] ?? proxy['username'] ?? '',
        'password': auth['password'] ?? proxy['password'] ?? '',
      });
    }
    final outputKeys = <Map<String, dynamic>>[];
    final linkedIdentities = <String, List<dynamic>>{};
    for (final table in [
      'ssh_config_identities',
      'ssh_config_identities_shared',
    ]) {
      for (final link in tables[table] ?? <Map<String, dynamic>>[]) {
        final config = deref(link['ssh_config'], configs);
        if (config.isNotEmpty && link['identity'] != null) {
          linkedIdentities
              .putIfAbsent(id(config), () => [])
              .add(link['identity']);
        }
      }
    }
    for (final k in tables['keys'] ?? <Map<String, dynamic>>[]) {
      if ('${k['private_key'] ?? ''}'.isNotEmpty) {
        outputKeys.add({
          'id': id(k),
          'label': k['label'] ?? '',
          'private_key': k['private_key'],
          'passphrase': k['passphrase'] ?? '',
        });
      }
    }
    final hosts = <Map<String, dynamic>>[];
    for (final h in tables['hosts'] ?? <Map<String, dynamic>>[]) {
      final cfg = deref(h['ssh_config'], configs);
      final group = deref(h['group'], groups);
      final chain = <Map<String, dynamic>>[cfg];
      final labels = <String>[];
      var current = group;
      final seen = <String>{};
      while (current.isNotEmpty && seen.add(id(current)) && seen.length < 32) {
        labels.insert(0, '${current['label'] ?? ''}');
        chain.add(deref(current['ssh_config'], configs));
        current = deref(current['parent_group'], groups);
      }
      dynamic option(String field) {
        for (final item in chain) {
          if (item[field] != null) return item[field];
        }
        return null;
      }

      var identityRef = option('identity') ?? h['identity'];
      var multipleIdentities = false;
      if (deref(identityRef, identities).isEmpty) {
        for (final config in chain) {
          final links = linkedIdentities[id(config)];
          if (links != null && links.isNotEmpty) {
            identityRef = links.first;
            multipleIdentities = links.length > 1;
            break;
          }
        }
      }
      final identity = deref(identityRef, identities);
      final keyRef = identity['ssh_key'];
      final key = deref(keyRef, keys);
      var address = '${h['address'] ?? ''}';
      final packed = RegExp(r'^\d+$').hasMatch(address)
          ? int.tryParse(address)
          : null;
      if (packed != null && packed >= 0 && packed <= 0xffffffff) {
        address = [24, 16, 8, 0].map((n) => (packed >> n) & 255).join('.');
      }
      final host = <String, dynamic>{
        'label': h['label'] ?? '',
        'address': address,
        'port': option('port') ?? 22,
        'username': identity['username'] ?? '',
        'password': identity['password'] ?? '',
        'group': labels.where((v) => v.isNotEmpty).join('/'),
        if (hasRef(keyRef))
          'key_id': key.isEmpty ? 'missing-termius-key' : id(key),
      };
      final proxyRef = option('proxycommand');
      if (hasRef(proxyRef)) {
        final proxy = deref(proxyRef, proxies);
        host['proxy_id'] = proxy.isEmpty ? 'missing-termius-proxy' : id(proxy);
      }
      if (hasRef(identityRef) && identity.isEmpty) {
        host['key_id'] = 'missing-termius-identity';
      }
      if (hasRef(option('proxyjump')) ||
          multipleIdentities ||
          option('is_forward_ports') == true) {
        host['unsupported'] = true;
      }
      hosts.add(host);
    }
    return {'hosts': hosts, 'keys': outputKeys, 'proxies': outputProxies};
  }

  static Uint8List? _envelope(dynamic value) {
    if (value is! String || value.length < 56 || value.length % 4 != 0) {
      return null;
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(value);
    } catch (_) {
      return null;
    }
    if (bytes.length >= 42 && bytes[0] == 4 && bytes[1] != 1) {
      throw const FormatException('termius cipher version');
    }
    return bytes.length >= 42 && bytes[0] == 4 && bytes[1] == 1 ? bytes : null;
  }

  static String? _firstEncrypted(dynamic value, [int depth = 0]) {
    if (depth > 64) throw const FormatException('termius nesting');
    if (_envelope(value) != null) return value as String;
    final Iterable<dynamic> children = value is Map
        ? value.values
        : value is List
        ? value
        : [];
    for (final child in children) {
      final found = _firstEncrypted(child, depth + 1);
      if (found != null) return found;
    }
    return null;
  }

  static String _decrypt(String value, Uint8List key) {
    final bytes = _envelope(value)!;
    return utf8.decode(
      nacl.SecretBox(key).decrypt(
        nacl.ByteList(bytes.sublist(26)),
        nonce: Uint8List.sublistView(bytes, 2, 26),
      ),
    );
  }

  static dynamic _walk(dynamic value, Uint8List? key, int depth) {
    if (depth > 64) throw const FormatException('termius nesting');
    if (value is String) {
      return _envelope(value) == null ? value : _decrypt(value, key!);
    }
    if (value is List) {
      return value.map((v) => _walk(v, key, depth + 1)).toList();
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final e in value.entries)
          '${e.key}': _walk(e.value, key, depth + 1),
      };
    }
    return value;
  }
}
