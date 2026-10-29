import 'dart:convert';

import 'package:cb_file_manager/services/ssh/ssh_import.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FailingVault extends FlutterSecureStorage {
  bool failWrites = false;
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failWrites) throw StateError('Fixture vault unavailable');
    return super.write(key: key, value: value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'Termius JSON imports identity credentials, attached and orphan keys',
    () async {
      final key = SshStoredKey.generate('Work');
      final orphan = SshStoredKey.generate('Unused');
      final preview = SshImporter.parse([
        SshImportFile(
          'termius.json',
          jsonEncode({
            'keys': [
              {'id': 'key1', 'label': 'Work', 'private_key': key.pem},
              {'id': 'key2', 'label': 'Unused', 'private_key': orphan.pem},
            ],
            'identities': [
              {
                'id': 'identity1',
                'username': 'deploy',
                'password': 'fixture-only',
                'ssh_key_id': 'key1',
              },
            ],
            'hosts': [
              {
                'label': 'Production',
                'address': 'example.test',
                'port': 2222,
                'group': 'Work/Prod',
                'identity_id': 'identity1',
              },
            ],
          }),
        ),
      ]);
      expect(preview.issues, isEmpty);
      expect(preview.hosts.single.username, 'deploy');
      expect(preview.hosts.single.password, 'fixture-only');
      expect(preview.hosts.single.group, 'Work/Prod');
      expect(preview.hosts.single.keyId, preview.keys.first.id);
      expect(preview.keys, hasLength(2));
      final store = SshProfileStore();
      final summary = await store.importProfiles(
        profiles: preview.hosts,
        keys: preview.keys,
      );
      expect(summary.hosts, 1);
      expect(summary.keys, 2);
      final restored = SshProfileStore();
      await restored.load();
      expect(restored.profiles.single.keyId, restored.keys.first.id);
      expect(
        restored.keys.map((k) => k.fingerprint),
        contains(orphan.fingerprint),
      );
    },
  );

  test(
    'Termius portable JSON resolves encrypted external keys and per-key passphrase',
    () {
      final key = SshStoredKey.generate('Work');
      final encrypted =
          (SSHKeyPair.fromPem(key.pem).single as OpenSSHEd25519KeyPair).toPem(
            passphrase: 'per-key-pass',
          );
      final preview = SshImporter.parse([
        SshImportFile('/selected/id_work.pem', encrypted),
        SshImportFile(
          'export.json',
          jsonEncode({
            'keys': [
              {
                'label': 'Work',
                'file': 'keys/id_work.pem',
                'passphrase': 'per-key-pass',
              },
            ],
            'hosts': [
              {
                'label': 'Host',
                'address': '::1',
                'username': 'root',
                'identity_file': 'keys/id_work.pem',
                'key': {'label': 'Work'},
              },
            ],
          }),
        ),
      ], passphrase: 'wrong-global-pass');
      expect(preview.issues, isEmpty);
      expect(preview.keys.single.fingerprint, key.fingerprint);
      expect(preview.hosts.single.keyId, preview.keys.single.id);
    },
  );

  test(
    'Termius CSV preserves quoted commas, newlines, credentials and group',
    () {
      final key = SshStoredKey.generate('work');
      final preview = SshImporter.parse([
        const SshImportFile(
          'hosts.csv',
          '\uFEFFGroups,Label,Hostname,Protocol,Port,Username,Password,IdentityFile,KeyLabel\r\n"Work/Prod","Web, primary",web.test,ssh,2200,deploy,"comma,quote""line\nnext",,work\r\nIgnored,FTP,ftp.test,ftp,21,ftp,,,\r\n',
        ),
        SshImportFile(
          'keys.json',
          jsonEncode({
            'keys': [
              {'label': 'work', 'pem': key.pem},
            ],
          }),
        ),
      ]);
      expect(preview.issues, isEmpty);
      expect(preview.hosts, hasLength(1));
      final host = preview.hosts.single;
      expect(host.name, 'Web, primary');
      expect(host.password, 'comma,quote"line\nnext');
      expect(host.group, 'Work/Prod');
      expect(host.port, 2200);
      expect(host.keyId, preview.keys.single.id);
    },
  );

  test(
    'OpenSSH first-value defaults and patterns; never expands Include or executes commands',
    () {
      final preview = SshImporter.parse([
        const SshImportFile(
          'config',
          'User global\nHost web db\n HostName %h.example.test\n Port 2222\nHost * !db\n User later\n ProxyCommand arbitrary-command\nInclude /must/not/be/read\nMatch exec arbitrary-command\n HostName ignored\n',
        ),
      ]);
      expect(preview.hosts.map((h) => h.host), [
        'web.example.test',
        'db.example.test',
      ]);
      expect(
        preview.hosts.every((h) => h.username == 'global' && h.port == 2222),
        isTrue,
      );
      expect(
        preview.issues.any((i) => i.problem == SshImportProblem.unsupported),
        isTrue,
      );
    },
  );

  test(
    'PuTTY registry export decodes names, escaped paths and DWORD ports',
    () {
      final key = SshStoredKey.generate('work');
      final preview = SshImporter.parse([
        const SshImportFile(
          'putty.reg',
          r'''Windows Registry Editor Version 5.00
[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Work%20server]
"HostName"="server.test"
"UserName"="root"
"Protocol"="ssh"
"PortNumber"=dword:000008ae
"PublicKeyFile"="C:\\keys\\work.pem"
[HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Telnet]
"HostName"="telnet.test"
"Protocol"="telnet"
''',
        ),
        SshImportFile('C:/keys/work.pem', key.pem),
      ]);
      expect(preview.issues, isEmpty);
      expect(preview.hosts.single.name, 'Work server');
      expect(preview.hosts.single.port, 2222);
      expect(preview.hosts.single.keyId, preview.keys.single.id);
    },
  );

  test(
    'WinSCP imports SFTP/SCP only and reports omitted passwords and proxies',
    () {
      final preview = SshImporter.parse([
        const SshImportFile(
          'WinSCP.ini',
          '[Sessions\\Work/Web%20server]\nHostName=web.test\nUserName=deploy\nPortNumber=2200\nFSProtocol=2\nPassword=encrypted-fixture\nProxyMethod=2\nProxyHost=proxy.test\nProxyPort=1080\n[Sessions\\FTP]\nHostName=ftp.test\nFSProtocol=5\n',
        ),
      ]);
      expect(preview.hosts, hasLength(1));
      expect(preview.hosts.single.name, 'Web server');
      expect(preview.hosts.single.proxyId, preview.proxies.single.id);
      expect(preview.proxies.single.host, 'proxy.test');
      expect(preview.hosts.single.group, 'Work');
      expect(preview.hosts.single.password, isEmpty);
      expect(
        preview.issues.map((i) => i.problem),
        contains(SshImportProblem.password),
      );
    },
  );

  test('SecureCRT and Tabby preserve SSH connection settings', () {
    final preview = SshImporter.parse([
      const SshImportFile(
        'securecrt.ini',
        'S:"Protocol Name"=SSH2\nS:"Hostname"=secure.test\nS:"Username"=user\nD:"[SSH2] Port"=000008ae\nS:"Password V2"=encrypted\n',
      ),
      const SshImportFile(
        'tabby.yaml',
        'profiles:\n  - type: ssh\n    name: Tabby host\n    group: Work\n    options:\n      host: tabby.test\n      user: deploy\n      port: 2200\n  - type: local\n    name: ignored\n',
      ),
    ]);
    expect(preview.hosts.map((h) => h.host), ['secure.test', 'tabby.test']);
    expect(preview.hosts.map((h) => h.port), [2222, 2200]);
    expect(preview.issues.single.problem, SshImportProblem.password);
  });

  test(
    'missing or ambiguous keys never downgrade hosts to password authentication',
    () {
      final a = SshStoredKey.generate('a'), b = SshStoredKey.generate('b');
      final preview = SshImporter.parse([
        const SshImportFile(
          'config',
          'Host one\nHostName one.test\nIdentityFile id_work\n',
        ),
        SshImportFile('/a/id_work', a.pem),
        SshImportFile('/b/id_work', b.pem),
      ]);
      expect(preview.hosts, isEmpty);
      expect(preview.keys, hasLength(2));
      expect(preview.issues.single.problem, SshImportProblem.missingKey);
    },
  );

  test(
    'invalid port, host, encrypted key and malformed export yield safe issues',
    () {
      final key = SshStoredKey.generate('encrypted');
      final preview = SshImporter.parse([
        const SshImportFile(
          'hosts.json',
          '{"hosts":[{"host":"bad host"},{"host":"ok.test","port":70000},{"host":"ok.test","key_id":"missing"}]}',
        ),
        const SshImportFile(
          'invalid.json',
          '{"password":"must-not-appear-in-error",broken}',
        ),
        SshImportFile(
          'encrypted.pem',
          (SSHKeyPair.fromPem(key.pem).single as OpenSSHEd25519KeyPair).toPem(
            passphrase: 'secret',
          ),
        ),
      ]);
      expect(preview.hosts, isEmpty);
      expect(preview.keys, isEmpty);
      expect(
        preview.issues.map((i) => i.problem),
        containsAll([
          SshImportProblem.format,
          SshImportProblem.invalidHost,
          SshImportProblem.invalidPort,
          SshImportProblem.missingKey,
          SshImportProblem.key,
        ]),
      );
      expect(
        preview.issues.map((i) => i.item).join(),
        isNot(contains('must-not-appear')),
      );
    },
  );

  test(
    'repeat imports reuse existing key identities and preserve host edits/trust',
    () async {
      final key = SshStoredKey.generate('key');
      final store = SshProfileStore();
      await store.importKey(key);
      await store.trust('server.test', 22, 'SHA256:trusted');
      final profiles = [
        SshProfile(
          id: 'untrusted-id',
          name: 'Host',
          host: 'server.test',
          username: 'deploy',
          password: 'original',
          keyId: key.id,
        ),
      ];
      await store.importProfiles(profiles: profiles, keys: [key]);
      final importedId = store.profiles.single.id;
      final summary = await store.importProfiles(
        profiles: [
          SshProfile(
            id: importedId,
            name: 'Host',
            host: 'server.test',
            username: 'deploy',
            password: 'changed',
            keyId: key.id,
          ),
        ],
        keys: [key],
      );
      expect(summary.hosts, 0);
      expect(summary.keys, 0);
      expect(summary.duplicates, 2);
      expect(store.profiles.single.password, 'original');
      expect(store.profiles.single.keyId, key.id);
      expect(store.keys, hasLength(1));
      expect(store.knownHosts['server.test:22'], 'SHA256:trusted');
    },
  );

  test('invalid batch rolls back imported keys and hosts', () async {
    final store = SshProfileStore();
    final key = SshStoredKey.generate('key');
    await expectLater(
      store.importProfiles(
        profiles: [
          const SshProfile(
            id: '1',
            name: 'Missing',
            host: 'test',
            username: 'root',
            keyId: 'absent',
          ),
        ],
        keys: [key],
      ),
      throwsStateError,
    );
    expect(store.keys, isEmpty);
    expect(store.profiles, isEmpty);
    final restored = SshProfileStore();
    await restored.load();
    expect(restored.keys, isEmpty);
  });

  test(
    'vault write failure rolls back all changes and permits a retry',
    () async {
      final vault = FailingVault();
      final store = SshProfileStore(storage: vault);
      await store.trust('keep.test', 22, 'SHA256:keep');
      final key = SshStoredKey.generate('key');
      final hosts = [
        SshProfile(
          id: '1',
          name: 'Host',
          host: 'host.test',
          username: 'deploy',
          keyId: key.id,
        ),
      ];
      vault.failWrites = true;
      await expectLater(
        store.importProfiles(profiles: hosts, keys: [key]),
        throwsStateError,
      );
      expect(store.profiles, isEmpty);
      expect(store.keys, isEmpty);
      expect(store.knownHosts['keep.test:22'], 'SHA256:keep');
      vault.failWrites = false;
      await store.importProfiles(profiles: hosts, keys: [key]);
      expect(store.profiles.single.keyId, store.keys.single.id);
    },
  );
}
