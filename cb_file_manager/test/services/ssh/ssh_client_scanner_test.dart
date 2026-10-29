import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cb_file_manager/services/ssh/chromium_indexed_db.dart';
import 'package:cb_file_manager/services/ssh/ssh_client_platform.dart';
import 'package:cb_file_manager/services/ssh/ssh_client_scanner.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/services/ssh/ssh_import.dart';
import 'package:cb_file_manager/services/ssh/termius_local_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pinenacl/x25519.dart' as nacl;

void main() {
  test(
    'Termius local tables decrypt and resolve host-config-identity-key with inherited groups',
    () {
      final localKey = Uint8List.fromList(List.generate(32, (i) => i));
      String encrypt(String value) {
        final encrypted = nacl.SecretBox(
          localKey,
        ).encrypt(Uint8List.fromList(utf8.encode(value)), nonce: Uint8List(24));
        return base64Encode([
          4,
          1,
          ...encrypted.nonce,
          ...encrypted.cipherText,
        ]);
      }

      final key = SshStoredKey.generate('Termius key');
      final raw = <String, List<Map<String, dynamic>>>{
        'keys': [
          {
            'id': 11,
            'label': encrypt('Work key'),
            'private_key': encrypt(key.pem),
          },
        ],
        'ssh_identities': [
          {
            'local_id': 20,
            'username': encrypt('deploy'),
            'password': encrypt('fixture-password'),
            'ssh_key': {'id': 11},
          },
        ],
        'ssh_configs': [
          {
            'id': 30,
            'identity': {'local_id': 20},
            'port': 2222,
          },
        ],
        'groups': [
          {
            'id': 40,
            'label': encrypt('Work'),
            'ssh_config': {'id': 30},
          },
        ],
        'hosts': [
          {
            'id': 50,
            'label': encrypt('Old name'),
            'address': encrypt('wrong.test'),
            'group': {'id': 40},
            'updated_at': '2024-01-01',
          },
          {
            'id': 50,
            'label': encrypt('Server'),
            'address': encrypt('3221225985'),
            'group': {'id': 40},
            'updated_at': '2026-01-01',
          },
          {
            'id': 51,
            'label': encrypt('Deleted'),
            'address': encrypt('deleted.test'),
            'is_deleted': true,
          },
        ],
      };
      expect(
        () => TermiusLocalReader.normalize(raw, [Uint8List(32)]),
        throwsFormatException,
      );
      final result = TermiusLocalReader.normalize(raw, [
        Uint8List(32),
        localKey,
      ]);
      final host = (result['hosts'] as List).single as Map;
      expect(host['label'], 'Server');
      expect(host['address'], '192.0.2.1');
      expect(host['username'], 'deploy');
      expect(host['password'], 'fixture-password');
      expect(host['group'], 'Work');
      expect(host['key_id'], '11');
      expect(host['port'], 2222);
      expect(((result['keys'] as List).single as Map)['private_key'], key.pem);
    },
  );

  test(
    'installed OpenSSH, Tabby and registry sessions scan without manual exports',
    () async {
      final root = await Directory.systemTemp.createTemp('cb-ssh-scan-');
      addTearDown(() => root.delete(recursive: true));
      final key = SshStoredKey.generate('Work');
      await Directory(p.join(root.path, '.ssh')).create();
      await File(p.join(root.path, '.ssh', 'id_work')).writeAsString(key.pem);
      await File(p.join(root.path, '.ssh', 'config')).writeAsString(
        'Host work\nHostName work.test\nUser deploy\nIdentityFile ~/.ssh/id_work\n',
      );
      final roaming = p.join(root.path, 'roaming');
      await Directory(p.join(roaming, 'tabby')).create(recursive: true);
      await File(p.join(roaming, 'tabby', 'config.yaml')).writeAsString(
        'profiles:\n  - type: ssh\n    name: Tabby host\n    options:\n      host: tabby.test\n      user: root\n',
      );
      final results = await SshClientScanner(
        home: root.path,
        roaming: roaming,
        local: '',
        operatingSystem: 'windows',
        readRegistry: (app) => app == 'PuTTY'
            ? [
                {
                  'name': 'Registry host',
                  'HostName': 'putty.test',
                  'UserName': 'root',
                  'PortNumber': '2222',
                  'Protocol': 'ssh',
                },
              ]
            : [],
        readLocalKeys: () async => [],
      ).scan();
      final ssh = results.singleWhere((r) => r.app == 'OpenSSH');
      expect(ssh.preview.hosts.single.host, 'work.test');
      expect(ssh.preview.hosts.single.keyId, ssh.preview.keys.single.id);
      expect(
        results.singleWhere((r) => r.app == 'Tabby').preview.hosts.single.host,
        'tabby.test',
      );
      expect(
        results.singleWhere((r) => r.app == 'PuTTY').preview.hosts.single.port,
        2222,
      );
      expect(
        results.singleWhere((r) => r.app == 'Termius').status,
        SshClientScanStatus.notFound,
      );
    },
  );

  test('Snappy handles overlapping copies and rejects corrupt lengths', () {
    expect(
      utf8.decode(decodeSnappy(Uint8List.fromList([8, 0, 97, 26, 1, 0]))),
      'aaaaaaaa',
    );
    expect(
      () => decodeSnappy(Uint8List.fromList([8, 26, 1, 0])),
      throwsFormatException,
    );
  });

  test(
    'live Termius read reports only counts and never persists credentials',
    () async {
      if (!const bool.fromEnvironment('CB_SSH_LOCAL_SCAN')) return;
      final directory = p.join(
        Platform.environment['APPDATA']!,
        'Termius',
        'IndexedDB',
        'file__0.indexeddb.leveldb',
      );
      final reader = ChromiumIndexedDb(directory);
      final tables = await reader.readTables({
        'hosts',
        'keys',
        'ssh_identities',
        'ssh_configs',
        'groups',
        'proxies',
        'ssh_config_identities',
        'ssh_config_identities_shared',
      });
      expect(reader.databaseNames, contains('hosts'));
      expect(reader.recordCount, greaterThan(0));
      print(
        'Termius local counts: ${tables.map((k, v) => MapEntry(k, v.length))}',
      );
      final document = TermiusLocalReader.normalize(
        tables,
        await readTermiusLocalKeys(),
      );
      final preview = SshImporter.parse([
        SshImportFile('Termius.json', jsonEncode(document)),
      ]);
      final counts = <String, int>{};
      for (final issue in preview.issues) {
        counts.update(issue.problem.name, (n) => n + 1, ifAbsent: () => 1);
      }
      print(
        'Termius validated preview: hosts=${preview.hosts.length}, keys=${preview.keys.length}, proxies=${preview.proxies.length}, issueCounts=$counts',
      );
      final scan = await Isolate.run(() => SshClientScanner().scan());
      final termius = scan
          .where(
            (r) => r.app == 'Termius' && r.status == SshClientScanStatus.ready,
          )
          .toList();
      expect(termius, isNotEmpty);
      print(
        'Installed client scan: ${[for (final source in scan) '${source.app}=${source.status.name}/${source.preview.hosts.length}hosts/${source.preview.keys.length}keys/${source.preview.proxies.length}proxies']}',
      );
    },
    skip: !const bool.fromEnvironment('CB_SSH_LOCAL_SCAN'),
  );
}
