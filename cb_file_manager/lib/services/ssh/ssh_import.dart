import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:yaml/yaml.dart';

import 'local_ssh_discovery.dart';
import 'ssh_profile_store.dart';

enum SshImportFormat { auto, termius, openSsh, putty, winScp, secureCrt, tabby }

enum SshImportProblem {
  format,
  invalidHost,
  invalidPort,
  key,
  missingKey,
  proxy,
  unsupported,
  password,
  limit,
}

class SshImportIssue {
  final String item;
  final SshImportProblem problem;
  const SshImportIssue(this.item, this.problem);
}

/// Only explicitly selected files are supplied here. References in an imported
/// document never cause arbitrary local files to be read or commands to run.
class SshImportFile {
  final String name, content;
  const SshImportFile(this.name, this.content);
}

class SshImportPreview {
  final List<SshProfile> hosts;
  final List<SshStoredKey> keys;
  final List<SshImportIssue> issues;
  final List<SshProxy> proxies;
  const SshImportPreview(
    this.hosts,
    this.keys,
    this.issues, {
    this.proxies = const [],
  });
}

class _Host {
  final Map<String, String> fields;
  _Host(this.fields);
}

/// Portable exports, not the encrypted private databases of other clients.
/// Parsing errors deliberately exclude source text, passwords and key material.
class SshImporter {
  /// Inspect references using the same parsers without opening those paths.
  static List<String> referencedKeyFiles(List<SshImportFile> files) {
    final parser = _Parser('', const [], '');
    for (final file in files) {
      try {
        switch (_detect(file.content.trim())) {
          case SshImportFormat.openSsh:
            parser.openSsh(file.content);
          case SshImportFormat.putty:
            parser.ini(file.content, putty: true);
          case SshImportFormat.winScp:
            parser.ini(file.content);
          case SshImportFormat.secureCrt:
            parser.secureCrt(file.content, file.name);
          case SshImportFormat.tabby:
            parser.tabby(loadYaml(file.content));
          default:
            continue;
        }
      } catch (_) {
        /* scan reports format issues through the normal parser */
      }
    }
    return parser.hosts
        .map((h) => h.fields['key'] ?? '')
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
  }

  static const maxFileBytes = 8 * 1024 * 1024;
  static const maxTotalBytes = 32 * 1024 * 1024;
  static const maxFiles = 128;
  static const maxItems = 2000;

  static SshImportPreview parse(
    List<SshImportFile> files, {
    SshImportFormat format = SshImportFormat.auto,
    String passphrase = '',
    List<SshStoredKey> existingKeys = const [],
    String defaultUsername = '',
  }) {
    final parser = _Parser(passphrase, existingKeys, defaultUsername);
    final keyFiles = <SshImportFile>[];
    var totalBytes = 0;
    for (final file in files.take(maxFiles)) {
      final length = utf8.encode(file.content).length;
      totalBytes += length;
      if (length > maxFileBytes || totalBytes > maxTotalBytes) {
        parser.issue(file.name, SshImportProblem.limit);
        continue;
      }
      final text = file.content.replaceFirst(RegExp('^\uFEFF'), '').trim();
      if (text.startsWith('-----BEGIN ') ||
          text.startsWith('PuTTY-User-Key-File-')) {
        keyFiles.add(SshImportFile(file.name, text));
        continue;
      }
      try {
        final detected =
            format == SshImportFormat.auto || format == SshImportFormat.termius
            ? _detect(text)
            : format;
        switch (detected) {
          case SshImportFormat.termius:
          case SshImportFormat.auto:
            if (text.startsWith('{') || text.startsWith('[')) {
              parser.json(jsonDecode(text));
            } else {
              parser.csv(text);
            }
          case SshImportFormat.openSsh:
            parser.openSsh(text);
          case SshImportFormat.putty:
            parser.ini(text, putty: true);
          case SshImportFormat.winScp:
            parser.ini(text);
          case SshImportFormat.secureCrt:
            parser.secureCrt(text, file.name);
          case SshImportFormat.tabby:
            parser.tabby(loadYaml(text));
        }
      } catch (_) {
        parser.issue(file.name, SshImportProblem.format);
      }
    }
    for (final file in keyFiles) {
      parser.fileKey(file);
    }
    if (files.length > maxFiles) parser.issue('', SshImportProblem.limit);
    return parser.finish();
  }

  static SshImportFormat _detect(String text) {
    if (text.startsWith('Windows Registry Editor') ||
        text.startsWith('REGEDIT4')) {
      return SshImportFormat.putty;
    }
    if (RegExp(r'^\[Sessions\\', multiLine: true).hasMatch(text)) {
      return SshImportFormat.winScp;
    }
    if (RegExp(r'^[SDB]:"', multiLine: true).hasMatch(text)) {
      return SshImportFormat.secureCrt;
    }
    if (RegExp(
      r'^\s*(profiles:|-\s*type:\s*ssh)',
      multiLine: true,
    ).hasMatch(text)) {
      return SshImportFormat.tabby;
    }
    if (RegExp(
      r'^\s*Host[\s=]',
      multiLine: true,
      caseSensitive: false,
    ).hasMatch(text)) {
      return SshImportFormat.openSsh;
    }
    return SshImportFormat.termius;
  }
}

class _Parser {
  final String passphrase, defaultUsername;
  final List<SshStoredKey> existingKeys;
  final hosts = <_Host>[];
  final keys = <SshStoredKey>[];
  final issues = <SshImportIssue>[];
  final proxies = <SshProxy>[];
  final proxyRefs = <String, Set<String>>{};
  final refs = <String, Set<String>>{};
  final aliases = <String, Set<String>>{};
  final externalKeys = <({String path, String label, String password})>[];
  _Parser(this.passphrase, this.existingKeys, this.defaultUsername);

  void issue(String item, SshImportProblem problem) {
    if (issues.length < SshImporter.maxItems) {
      issues.add(SshImportIssue(item, problem));
    }
  }

  String value(Map m, List<String> names) {
    for (final name in names) {
      final v = m[name];
      if ((v is String || v is num) && '$v'.isNotEmpty) return '$v';
    }
    return '';
  }

  String ref(String name) => p.posix.normalize(name.replaceAll('\\', '/'));

  void reference(String name, String id) {
    if (name.isEmpty) return;
    refs.putIfAbsent(ref(name), () => {}).add(id);
    aliases.putIfAbsent(p.posix.basename(ref(name)), () => {}).add(id);
  }

  void addKey(
    String name,
    String pem, {
    List<String> references = const [],
    String? password,
  }) {
    if (keys.length >= SshImporter.maxItems) {
      issue(name, SshImportProblem.limit);
      return;
    }
    try {
      final key = SshStoredKey.import(
        name,
        pem,
        password?.isNotEmpty == true
            ? password
            : passphrase.isEmpty
            ? null
            : passphrase,
      );
      final saved =
          keys.where((k) => k.fingerprint == key.fingerprint).firstOrNull ??
          key;
      if (saved == key) keys.add(key);
      for (final name in [name, ...references]) {
        reference(name, saved.id);
      }
    } catch (_) {
      issue(name, SshImportProblem.key);
    }
  }

  void fileKey(SshImportFile file) {
    var metadata = externalKeys
        .where((k) => ref(k.path) == ref(file.name))
        .toList();
    if (metadata.isEmpty) {
      metadata = externalKeys
          .where(
            (k) =>
                p.posix.basename(ref(k.path)) ==
                p.posix.basename(ref(file.name)),
          )
          .toList();
    }
    final info = metadata.length == 1 ? metadata.single : null;
    addKey(
      info?.label.isNotEmpty == true
          ? info!.label
          : p.posix.basename(ref(file.name)),
      file.content,
      references: [file.name, if (info != null) info.path],
      password: info?.password == '<omitted>' ? null : info?.password,
    );
  }

  void host(Map<String, String> fields) {
    if (hosts.length >= SshImporter.maxItems) {
      issue(fields['name'] ?? '', SshImportProblem.limit);
    } else {
      hosts.add(_Host(fields));
    }
  }

  String addProxy(Map fields, {String fallbackName = 'Proxy'}) {
    final name = value(fields, ['label', 'name']);
    final type = SshProxy.parseType(
      value(fields, ['type', 'kind', 'protocol']),
    );
    final port = int.tryParse(value(fields, ['port']));
    final id = const Uuid().v4();
    final proxy = SshProxy(
      id: id,
      name: name.isEmpty ? fallbackName : name,
      type: type ?? SshProxyType.socks5,
      host: value(fields, ['host', 'hostname']).trim(),
      port: port ?? 0,
      username: value(fields, ['username', 'user']),
      password: value(fields, ['password']),
    );
    if (type == null ||
        !proxy.isValid ||
        proxies.length >= SshImporter.maxItems ||
        proxy.password == '<omitted>') {
      issue(proxy.name, SshImportProblem.proxy);
      return '!invalid-proxy:$id';
    }
    final existing = proxies.where((p) => p.sameConnection(proxy)).firstOrNull;
    final selected = existing ?? proxy;
    if (existing == null) proxies.add(proxy);
    for (final ref in [
      id,
      value(fields, ['id']),
      name,
    ]) {
      if (ref.isNotEmpty) proxyRefs.putIfAbsent(ref, () => {}).add(selected.id);
    }
    return selected.id;
  }

  void json(dynamic document) {
    if (document is List) document = <String, dynamic>{'hosts': document};
    if (document is! Map) throw const FormatException();
    if (document['profiles'] is List &&
        (document['profiles'] as List).any(
          (h) => h is Map && h['type'] == 'ssh' && h['options'] is Map,
        )) {
      tabby(document);
      return;
    }
    final keyRecords =
        document['keys'] ?? document['keychain'] ?? document['ssh_keys'] ?? [];
    if (keyRecords is! List) throw const FormatException();
    final proxyRecords = document['proxies'] ?? [];
    if (proxyRecords is! List) throw const FormatException();
    for (final proxy in proxyRecords.take(SshImporter.maxItems)) {
      if (proxy is Map) addProxy(proxy);
    }
    for (final k in keyRecords.take(SshImporter.maxItems)) {
      if (k is! Map) continue;
      final name = value(k, ['label', 'name', 'id']);
      final pem = value(k, ['private_key', 'privateKey', 'pem']);
      final path = value(k, ['file']);
      if (path.isNotEmpty) {
        externalKeys.add((
          path: path,
          label: name,
          password: value(k, ['passphrase']),
        ));
      }
      if (pem.isNotEmpty) {
        addKey(
          name,
          pem,
          references: [
            value(k, ['id']),
            value(k, ['file']),
          ],
          password: value(k, ['passphrase']),
        );
      }
    }
    final identities = <String, Map>{};
    for (final identity in document['identities'] as List? ?? []) {
      if (identity is Map) identities[value(identity, ['id'])] = identity;
    }
    final records = document['hosts'] ?? document['profiles'] ?? [];
    if (records is! List) throw const FormatException();
    for (final h in records.take(SshImporter.maxItems)) {
      if (h is! Map) continue;
      final identityValue = h['identity'] ?? h['identity_id'];
      final identity = identityValue is Map
          ? identityValue
          : identities['$identityValue'] ?? {};
      final credential = <dynamic, dynamic>{...identity, ...h};
      final name = value(h, ['label', 'name', 'alias', 'address', 'host']);
      final keyValue = credential['key'] ?? credential['ssh_key'];
      String keyRef = value(credential, [
        'keyId',
        'key_id',
        'ssh_key_id',
        'identity_file',
        'key_name',
      ]);
      if (keyValue is Map) {
        final pem = value(keyValue, ['private_key', 'privateKey', 'pem']);
        final keyName = value(keyValue, ['id', 'label', 'name']);
        if (pem.isNotEmpty) {
          addKey(keyName, pem, password: value(keyValue, ['passphrase']));
        }
        if (keyRef.isEmpty) keyRef = keyName;
      } else if (keyValue != null && keyRef.isEmpty) {
        keyRef = '$keyValue';
      }
      final inline = value(credential, ['private_key', 'privateKey']);
      var proxyRef = value(h, ['proxy_id', 'proxyId']);
      if (h['proxy'] is Map) {
        proxyRef = addProxy(h['proxy'] as Map, fallbackName: name);
      } else if (h['proxy'] != null && h['proxy'] != false) {
        proxyRef = '${h['proxy']}';
      }
      if (inline.isNotEmpty) {
        keyRef = const Uuid().v4();
        addKey(
          name,
          inline,
          references: [keyRef],
          password: value(credential, ['passphrase']),
        );
      }
      host({
        'name': name,
        'host': value(h, ['address', 'host', 'hostname']),
        'username': value(credential, ['username', 'user']),
        'port': value(h, ['port']),
        'password': value(credential, ['password']),
        'group': value(h, ['group', 'group_name']),
        'key': keyRef,
        'proxy': proxyRef,
      });
      if (h['unsupported'] == true ||
          h['jumpHost'] != null ||
          (h['forwards'] is List && (h['forwards'] as List).isNotEmpty)) {
        issue(name, SshImportProblem.unsupported);
      }
    }
    if (keyRecords.length > SshImporter.maxItems ||
        records.length > SshImporter.maxItems) {
      issue('', SshImportProblem.limit);
    }
    if (records.isEmpty && keyRecords.isEmpty && proxyRecords.isEmpty) {
      throw const FormatException();
    }
  }

  void csv(String text) {
    final rows = _csvRows(text);
    if (rows.isEmpty) throw const FormatException();
    String normalize(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[ _-]'), '');
    final header = rows.first.map(normalize).toList();
    if (!header.any((v) => ['hostname', 'host', 'address'].contains(v))) {
      throw const FormatException();
    }
    for (final row in rows.skip(1)) {
      final m = <String, String>{
        for (var i = 0; i < header.length; i++)
          header[i]: i < row.length ? row[i] : '',
      };
      final protocol = m['protocol']?.toLowerCase() ?? '';
      if (protocol.isNotEmpty && protocol != 'ssh' && protocol != 'sftp') {
        continue;
      }
      final name = value(m, ['label', 'name', 'hostname', 'host']);
      final keyRef = value(m, [
        'identityfile',
        'key',
        'keyname',
        'keylabel',
        'sshkey',
      ]);
      if (keyRef.isNotEmpty && (m['keypassphrase'] ?? '').isNotEmpty) {
        externalKeys.add((
          path: keyRef,
          label: value(m, ['keylabel', 'keyname']),
          password: m['keypassphrase']!,
        ));
      }
      host({
        'name': name,
        'host': value(m, ['hostname', 'host', 'address']),
        'username': value(m, ['username', 'user']),
        'port': m['port'] ?? '',
        'password': m['password'] ?? '',
        'group': value(m, ['groups', 'group']),
        'key': keyRef,
        if (value(m, ['proxyhost', 'proxytype']).isNotEmpty)
          'proxy': addProxy({
            'type': m['proxytype'],
            'host': m['proxyhost'],
            'port': m['proxyport'],
            'username': m['proxyusername'],
            'password': m['proxypassword'],
          }, fallbackName: name),
      });
      if (value(m, ['jumphost']).isNotEmpty) {
        issue(name, SshImportProblem.unsupported);
      }
    }
  }

  void openSsh(String text) {
    final lines = const LineSplitter()
        .convert(text)
        .map(LocalSshDiscovery.tokenize)
        .where((v) => v.isNotEmpty)
        .toList();
    if (lines.length > 20000) throw const FormatException();
    final names = <String>{};
    for (final line in lines) {
      if (line.first.toLowerCase() == 'host') {
        names.addAll(line.skip(1).where((s) => !s.contains(RegExp(r'[!*?%]'))));
      }
      if (line.first.toLowerCase() == 'include') {
        issue('Include', SshImportProblem.unsupported);
      }
    }
    if (names.length > SshImporter.maxItems) issue('', SshImportProblem.limit);
    for (final name in names.take(SshImporter.maxItems)) {
      var active = true;
      final m = <String, String>{};
      for (final line in lines) {
        final option = line.first.toLowerCase();
        final args = line.skip(1).toList();
        if (option == 'host') {
          bool matches(String pattern) => RegExp(
            '^${pattern.split('').map((c) => c == '*'
                ? '.*'
                : c == '?'
                ? '.'
                : RegExp.escape(c)).join()}\$',
            caseSensitive: false,
          ).hasMatch(name);
          active =
              args.any((s) => !s.startsWith('!') && matches(s)) &&
              !args.any((s) => s.startsWith('!') && matches(s.substring(1)));
        } else if (option == 'match') {
          active = false;
          issue(name, SshImportProblem.unsupported);
        } else if (active && args.isNotEmpty) {
          if (option == 'identityfile' &&
              m[option] != null &&
              m[option] != args.first) {
            issue(name, SshImportProblem.unsupported);
          }
          m.putIfAbsent(option, () => args.first);
        }
      }
      host({
        'name': name,
        'host': (m['hostname'] ?? name).replaceAll('%h', name),
        'username': m['user'] ?? defaultUsername,
        'port': m['port'] ?? '',
        'key': m['identityfile'] == 'none' ? '' : m['identityfile'] ?? '',
      });
      if ([
        'proxyjump',
        'proxycommand',
        'certificatefile',
        'localforward',
        'remoteforward',
        'dynamicforward',
      ].any((k) => m[k] != null && m[k] != 'none')) {
        issue(name, SshImportProblem.unsupported);
      }
    }
    if (names.isEmpty) throw const FormatException();
  }

  void ini(String text, {bool putty = false}) {
    String? section;
    var fields = <String, String>{};
    var count = 0;
    void flush() {
      if (section == null) return;
      final m = fields;
      if (putty && m['Protocol'] != null && m['Protocol'] != 'ssh') return;
      if (!putty && !['', '0', '1', '2'].contains(m['FSProtocol'] ?? '')) {
        return;
      }
      if ((m['HostName'] ?? '').isEmpty) return;
      count++;
      final label = Uri.decodeComponent(section);
      final segments = label.split('/');
      host({
        'name': segments.last,
        'group': segments.take(segments.length - 1).join('/'),
        'host': m['HostName']!,
        'username': m['UserName'] ?? '',
        'port': m['PortNumber'] ?? '',
        'key': m['PublicKeyFile'] ?? '',
        'password': m['PasswordPlain'] ?? '',
        if (!['', '0'].contains(m['ProxyMethod'] ?? ''))
          'proxy': addProxy({
            'type': switch (m['ProxyMethod']) {
              '1' => 'socks4',
              '2' => 'socks5',
              '3' => 'http',
              _ => 'unsupported',
            },
            'host': m['ProxyHost'],
            'port': m['ProxyPort'],
            'username': m['ProxyUsername'],
            'password':
                m['ProxyPasswordPlain'] ?? (putty ? m['ProxyPassword'] : ''),
          }, fallbackName: label),
      });
      if ((m['Password'] ?? '').isNotEmpty) {
        issue(label, SshImportProblem.password);
      }
      if (!putty &&
          (m['ProxyPassword'] ?? '').isNotEmpty &&
          (m['ProxyPasswordPlain'] ?? '').isEmpty) {
        issue(label, SshImportProblem.password);
      }
      if (!['', '0'].contains(m['Tunnel'] ?? '')) {
        issue(label, SshImportProblem.unsupported);
      }
    }

    for (final line in const LineSplitter().convert(text)) {
      final header = RegExp(r'^\[(.+)\]$').firstMatch(line.trim());
      if (header != null) {
        flush();
        fields = {};
        final s = header[1]!;
        final prefix = putty
            ? r'HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\'
            : r'Sessions\';
        section = s.startsWith(prefix) ? s.substring(prefix.length) : null;
        continue;
      }
      if (section == null) continue;
      final equal = line.indexOf('=');
      if (equal < 0) continue;
      var key = line.substring(0, equal).trim();
      var v = line.substring(equal + 1).trim();
      if (putty) {
        key = _unquote(key);
        if (v.startsWith('dword:')) {
          v = '${int.parse(v.substring(6), radix: 16)}';
        } else if (v.startsWith('"')) {
          v = _unquote(v).replaceAllMapped(RegExp(r'\\([\\"])'), (m) => m[1]!);
        } else {
          continue;
        }
      }
      fields[key] = v;
    }
    flush();
    if (count == 0) throw const FormatException();
  }

  void secureCrt(String text, String file) {
    final m = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final match = RegExp(r'^[SDB]:"([^"]+)"=(.*)$').firstMatch(line);
      if (match != null) {
        m[match[1]!] = line.startsWith('D:')
            ? '${int.parse(match[2]!, radix: 16)}'
            : match[2]!;
      }
    }
    if (!(m['Protocol Name'] ?? '').startsWith('SSH') ||
        (m['Hostname'] ?? '').isEmpty) {
      throw const FormatException();
    }
    host({
      'name': p.basenameWithoutExtension(file),
      'host': m['Hostname']!,
      'username': m['Username'] ?? '',
      'port': m['[SSH2] Port'] ?? m['Port'] ?? '',
      'key': m['Identity Filename V2'] ?? '',
    });
    if ((m['Password V2'] ?? m['Password'] ?? '').isNotEmpty) {
      issue(file, SshImportProblem.password);
    }
    if ((m['Firewall Name'] ?? '').isNotEmpty && m['Firewall Name'] != 'None') {
      issue(file, SshImportProblem.unsupported);
    }
  }

  void tabby(dynamic doc) {
    final records = doc is Map ? doc['profiles'] : doc;
    if (records is! List) throw const FormatException();
    for (final h in records.take(SshImporter.maxItems)) {
      if (h is! Map || h['type'] != 'ssh' || h['options'] is! Map) continue;
      final m = h['options'] as Map;
      final name = value(h, ['name']);
      final keyPaths = m['privateKeys'] is List
          ? m['privateKeys'] as List
          : const [];
      host({
        'name': name,
        'group': value(h, ['group']),
        'host': value(m, ['host']),
        'username': value(m, ['user']),
        'port': value(m, ['port']),
        'key': keyPaths.isEmpty ? '' : '${keyPaths.first}',
        'password': value(m, ['password']),
        if (value(m, ['socksProxyHost', 'httpProxyHost']).isNotEmpty)
          'proxy': addProxy({
            'type': value(m, ['socksProxyHost']).isNotEmpty ? 'socks5' : 'http',
            'host': value(m, ['socksProxyHost', 'httpProxyHost']),
            'port': value(m, ['socksProxyPort', 'httpProxyPort']),
          }, fallbackName: name),
      });
      if (keyPaths.length > 1 ||
          m['jumpHost'] != null ||
          m['proxyCommand'] != null ||
          (m['forwardedPorts'] is List &&
              (m['forwardedPorts'] as List).isNotEmpty)) {
        issue(name, SshImportProblem.unsupported);
      }
    }
  }

  SshImportPreview finish() {
    final result = <SshProfile>[];
    for (final draft in hosts) {
      final m = draft.fields;
      final host = (m['host'] ?? '').trim();
      final name = (m['name'] ?? host).trim();
      if (host.isEmpty || host.contains(RegExp(r'[\s/@\\%\x00-\x1f]'))) {
        issue(name, SshImportProblem.invalidHost);
        continue;
      }
      final port = m['port']?.isNotEmpty == true
          ? int.tryParse(m['port']!)
          : 22;
      if (port == null || port < 1 || port > 65535) {
        issue(name, SshImportProblem.invalidPort);
        continue;
      }
      String? keyId;
      String? proxyId;
      final proxyRef = m['proxy'] ?? '';
      if (proxyRef.isNotEmpty) {
        final matches = proxyRefs[proxyRef] ?? {};
        proxyId = matches.length == 1
            ? matches.single
            : proxies.where((p) => p.id == proxyRef).firstOrNull?.id;
        if (proxyId == null) {
          issue(name, SshImportProblem.proxy);
          continue;
        }
      }
      final keyRef = m['key'] ?? '';
      if (keyRef.isNotEmpty) {
        final candidates =
            refs[ref(keyRef)] ?? aliases[p.posix.basename(ref(keyRef))] ?? {};
        if (candidates.length == 1) keyId = candidates.single;
        if (keyId == null) {
          final matches = existingKeys
              .where((k) => k.id == keyRef || k.fingerprint == keyRef)
              .toList();
          if (matches.length == 1) keyId = matches.single.id;
        }
        if (keyId == null) {
          issue(name, SshImportProblem.missingKey);
          continue;
        }
      }
      var password = m['password'] ?? '';
      if (password == '<omitted>') {
        password = '';
        issue(name, SshImportProblem.password);
      }
      result.add(
        SshProfile(
          id: const Uuid().v4(),
          name: name.isEmpty ? host : name,
          host: host,
          username: m['username'] ?? '',
          port: port,
          password: password,
          group: m['group'] ?? '',
          keyId: keyId,
          proxyId: proxyId,
        ),
      );
    }
    return SshImportPreview(result, keys, issues, proxies: proxies);
  }
}

String _unquote(String value) => value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;

/// RFC 4180 quoted fields, including newlines and escaped double quotes.
List<List<String>> _csvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '"') {
      if (quoted && i + 1 < text.length && text[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (quoted || field.isEmpty) {
        quoted = !quoted;
      } else {
        throw const FormatException();
      }
    } else if (c == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((c == '\n' || c == '\r') && !quoted) {
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((v) => v.isNotEmpty)) rows.add(row);
      row = [];
      if (rows.length > SshImporter.maxItems) throw const FormatException();
    } else {
      field.write(c);
    }
  }
  if (quoted) throw const FormatException();
  row.add(field.toString());
  if (row.any((v) => v.isNotEmpty)) rows.add(row);
  return rows;
}
