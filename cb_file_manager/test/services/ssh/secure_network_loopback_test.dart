import 'package:cb_file_manager/services/network_browsing/network_service_registry.dart';
import 'dart:convert';
import 'dart:io';
import 'package:cb_file_manager/services/network_browsing/ftp_client/ftp_client.dart';
import 'package:cb_file_manager/services/network_browsing/sftp_service.dart';
import 'package:cb_file_manager/services/ssh/sftp_transfer.dart';
import 'package:cb_file_manager/services/ssh/ssh_tunnel_manager.dart';
import 'dart:async';

import 'fake_tunnel_link.dart' show freePort, roundTrip, startEchoServer;
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Opt in: python -m pip install asyncssh pyftpdlib pyopenssl
// flutter test --dart-define=CB_SECURE_NETWORK_TEST=true test/services/ssh/secure_network_loopback_test.dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('CB_SECURE_NETWORK_TEST');
  late Process server;
  late Directory root;
  late Map<String, dynamic> config;
  setUpAll(() async {
    if (!enabled) return;
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('cb-secure-network-');
    server = await Process.start('python', [
      'test/support/secure_network_server.py',
      root.path,
    ]);
    server.stderr.transform(utf8.decoder).listen((_) {});
    final line = await server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 20));
    config = jsonDecode(line);
  });
  tearDownAll(() async {
    if (!enabled) return;
    server.stdin.writeln('stop');
    await server.stdin.flush();
    await server.exitCode.timeout(const Duration(seconds: 10));
    await root.delete(recursive: true);
  });
  for (final security in [
    FtpSecurity.none,
    FtpSecurity.explicitTls,
    FtpSecurity.implicitTls,
  ]) {
    test(
      '${security.name} encrypts login, listing, upload and download',
      () async {
        final ftp = FtpClient(
          host: '127.0.0.1',
          port: config[security.name],
          username: 'developer',
          password: 'fixture-password',
          security: security,
          trustedCertificatePath: config['certificate'],
        );
        addTearDown(ftp.disconnect);
        expect(await ftp.connect(), isTrue);
        expect(
          (await ftp.listDirectory()).any((f) => f.name == 'hello.txt'),
          isTrue,
        );
        expect(
          utf8.decode((await ftp.downloadFile('/hello.txt'))!),
          'secure network fixture',
        );
        final source = File('${root.path}/source.txt');
        await source.writeAsString('encrypted upload');
        expect(await ftp.uploadFile(source.path, '/uploaded.txt'), isTrue);
        expect(
          utf8.decode((await ftp.downloadFile('/uploaded.txt'))!),
          'encrypted upload',
        );
        expect(await ftp.rename('/uploaded.txt', '/renamed.txt'), isTrue);
        expect(await ftp.deleteFile('/renamed.txt'), isTrue);
        expect(
          await ftp.uploadFile(source.path, '/literal%20name.txt'),
          isTrue,
        );
        expect(
          utf8.decode((await ftp.downloadFile('/literal%20name.txt'))!),
          'encrypted upload',
        );
        expect(
          (await ftp.listDirectory()).any(
            (f) => f.name == 'literal%20name.txt',
          ),
          isTrue,
        );
        expect(await ftp.deleteFile('/literal%20name.txt'), isTrue);
        await expectLater(
          ftp.deleteFile('bad\r\nDELE hello.txt'),
          throwsArgumentError,
        );
      },
      skip: !enabled,
    );
  }
  test(
    'FTPS rejects untrusted certificates and never falls back to plaintext',
    () async {
      final ftp = FtpClient(
        host: '127.0.0.1',
        port: config['explicitTls'],
        username: 'developer',
        password: 'fixture-password',
        security: FtpSecurity.explicitTls,
      );
      addTearDown(ftp.disconnect);
      await expectLater(ftp.connect(), throwsA(anything));
      expect(ftp.isConnected, isFalse);
    },
    skip: !enabled,
  );
  test(
    'SFTP operations and SSH password/key authentication share verified hosts',
    () async {
      var prompts = 0;
      final service = SFTPService();
      addTearDown(service.disconnect);
      final connected = await service.connect(
        host: '127.0.0.1',
        username: 'developer',
        password: 'fixture-password',
        port: config['ssh'],
        additionalOptions: {
          'trustPrompt':
              (String h, int port, String type, String fp, String? old) async {
                prompts++;
                return true;
              },
        },
      );
      expect(connected.success, isTrue, reason: connected.errorMessage);
      expect(prompts, 1);
      final authority = Uri.encodeComponent(
        Uri.parse(service.basePath).authority,
      );
      final path = '#network/SFTP/$authority/';
      expect(
        (await service.listDirectory(
          path,
        )).any((f) => f.path.endsWith('/hello.txt')),
        isTrue,
      );
      await service.createDirectory('${path}folder one');
      final local = File('${root.path}/local.txt');
      await local.writeAsString('SFTP bytes');
      await service.putFile(local.path, '${path}folder one/a%.txt');
      expect(
        utf8.decode((await service.readFileData('${path}folder one/a%.txt'))!),
        'SFTP bytes',
      );
      await service.rename(
        '${path}folder one/a%.txt',
        '${path}folder one/b.txt',
      );
      await service.getFile(
        '${path}folder one/b.txt',
        '${root.path}/downloaded.txt',
      );
      expect(
        await File('${root.path}/downloaded.txt').readAsString(),
        'SFTP bytes',
      );
      await service.deleteFile('${path}folder one/b.txt');
      await service.deleteDirectory('${path}folder one');
      expect(
        () => service.resolveRemotePath('#network/SFTP/another-host/file'),
        throwsArgumentError,
      );
      final store = SshProfileStore.instance;
      final key = SshStoredKey.generate('test');
      await store.saveKey(key);
      await File('${root.path}/authorized_keys').writeAsString(key.publicKey);
      final ssh = await SshConnector().connect(
        SshProfile(
          id: 'test',
          name: 'test',
          host: '127.0.0.1',
          username: 'developer',
          port: config['ssh'],
          keyId: key.id,
        ),
      );
      addTearDown(ssh.close);
      final shell = await ssh.shell();
      final output = shell.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      shell.write(utf8.encode('developer test\nexit\n'));
      expect(
        await output.timeout(const Duration(seconds: 10)),
        contains('echo: developer test'),
      );
      await store.trust('127.0.0.1', config['ssh'], 'SHA256:changed');
      await expectLater(
        SshConnector().connect(
          SshProfile(
            id: '',
            name: '',
            host: '127.0.0.1',
            username: 'developer',
            password: 'fixture-password',
            port: config['ssh'],
          ),
        ),
        throwsA(anything),
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 45)),
  );
  test(
    'two-pane transfer round-trips a tree and cancels a multi-chunk upload',
    () async {
      final ssh = await SshConnector().connect(
        SshProfile(
          id: '',
          name: '',
          host: '127.0.0.1',
          username: 'developer',
          password: 'fixture-password',
          port: config['ssh'],
        ),
        trustPrompt: (_, _, _, _, _) async => true,
      );
      addTearDown(ssh.close);
      final sftp = await ssh.sftp();
      // Tear-downs run in reverse, so the subsystem closes before the client.
      addTearDown(sftp.close);
      final remote = SftpTransferFileSystem(sftp);
      final local = LocalTransferFileSystem();
      final out = Directory('${root.path}/transfer-out/tree');
      await Directory('${out.path}/nested').create(recursive: true);
      await File('${out.path}/a.txt').writeAsString('alpha');
      await File('${out.path}/nested/b.txt').writeAsString('bravo');
      await remote.createDirectory('/transfer');
      expect(await remote.kind('/transfer/missing'), isNull);
      final upload = await SftpTransferTask(
        from: local,
        to: remote,
        sources: await local.list(out.parent.path),
        destination: '/transfer',
      ).run();
      expect(upload.failures, isEmpty);
      expect(upload.transferred, 2);
      expect(await remote.kind('/transfer/tree/nested'), isTrue);
      final back = Directory('${root.path}/transfer-back');
      await back.create();
      final download = await SftpTransferTask(
        from: remote,
        to: local,
        sources: await remote.list('/transfer'),
        destination: back.path,
      ).run();
      expect(download.failures, isEmpty);
      expect(
        await File('${back.path}/tree/nested/b.txt').readAsString(),
        'bravo',
      );

      final big = File('${root.path}/transfer-out/big.bin');
      await big.writeAsBytes(List.filled(4 * 1024 * 1024, 7));
      late SftpTransferTask task;
      task = SftpTransferTask(
        from: local,
        to: remote,
        sources: (await local.list(
          big.parent.path,
        )).where((e) => e.name == 'big.bin').toList(),
        destination: '/transfer',
        progressInterval: Duration.zero,
        onProgress: (progress) {
          if (progress.bytesDone > 0) task.cancel();
        },
      );
      final cancelled = await task.run();
      expect(cancelled.cancelled, isTrue);
      expect(cancelled.transferred, 0);
      expect(await remote.kind('/transfer/big.bin'), isNull);
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 45)),
  );
  test(
    'port forwarding: -L, -R and SOCKS5 -D move bytes through a real server',
    () async {
      final echo = await startEchoServer();
      addTearDown(echo.close);
      final store = SshProfileStore.instance;
      await store.saveProfile(
        SshProfile(
          id: 'tunnel-host',
          name: 'Loopback',
          host: '127.0.0.1',
          username: 'developer',
          password: 'fixture-password',
          port: config['ssh'],
        ),
      );
      final tunnels = SshTunnelManager(store);
      addTearDown(tunnels.dispose);
      Future<bool> trust(
        String _,
        int _,
        String _,
        String _,
        String? _,
      ) async => true;

      final local = SshForward(
        id: 'tunnel-l',
        profileId: 'tunnel-host',
        type: SshForwardType.local,
        bindPort: await freePort(),
        targetHost: '127.0.0.1',
        targetPort: echo.port,
      );
      await store.saveForward(local);
      await tunnels.start(local, trustPrompt: trust);
      expect(
        tunnels.state(local.id).status,
        SshTunnelStatus.running,
        reason: tunnels.state(local.id).error,
      );
      expect(await roundTrip(local.bindPort, 'via -L'), 'via -L');

      final remote = SshForward(
        id: 'tunnel-r',
        profileId: 'tunnel-host',
        type: SshForwardType.remote,
        bindPort: await freePort(),
        targetHost: '127.0.0.1',
        targetPort: echo.port,
      );
      await store.saveForward(remote);
      await tunnels.start(remote, trustPrompt: trust);
      expect(
        tunnels.state(remote.id).status,
        SshTunnelStatus.running,
        reason: '${tunnels.state(remote.id).failure}',
      );
      expect(await roundTrip(remote.bindPort, 'via -R'), 'via -R');

      final socks = SshForward(
        id: 'tunnel-d',
        profileId: 'tunnel-host',
        type: SshForwardType.dynamic,
        bindPort: await freePort(),
      );
      await store.saveForward(socks);
      await tunnels.start(socks, trustPrompt: trust);
      expect(tunnels.state(socks.id).status, SshTunnelStatus.running);
      final client = await Socket.connect('127.0.0.1', socks.bindPort);
      final replies = StreamIterator(client);
      Future<List<int>> read(int count) async {
        final bytes = <int>[];
        while (bytes.length < count && await replies.moveNext()) {
          bytes.addAll(replies.current);
        }
        return bytes;
      }

      client.add([5, 1, 0]); // SOCKS5, one method: no authentication.
      expect(await read(2), [5, 0]);
      client.add([
        5, 1, 0, 1, 127, 0, 0, 1, //
        echo.port >> 8, echo.port & 0xff,
      ]);
      final reply = await read(10);
      expect(reply.take(2), [5, 0], reason: 'CONNECT succeeded');
      client.add(utf8.encode('via -D'));
      expect(utf8.decode(await read(6)), 'via -D');
      client.destroy();

      await tunnels.stop(local.id);
      await expectLater(
        Socket.connect('127.0.0.1', local.bindPort),
        throwsA(isA<SocketException>()),
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 45)),
  );
  test(
    'SSH answers keyboard-interactive password prompts and falls back from keys',
    () async {
      Future<bool> trust(
        String h,
        int p,
        String type,
        String fp,
        String? old,
      ) async => true;
      SshProfile profile(int port, String password, [String? keyId]) =>
          SshProfile(
            id: 'kbdint',
            name: 'kbdint',
            host: '127.0.0.1',
            username: 'developer',
            port: port,
            password: password,
            keyId: keyId,
          );
      final kbdint = await SshConnector().connect(
        profile(config['kbdint'], 'fixture-password'),
        trustPrompt: trust,
      );
      kbdint.close();
      await expectLater(
        SshConnector()
            .connect(profile(config['kbdint'], 'wrong'), trustPrompt: trust)
            .timeout(const Duration(seconds: 10)),
        throwsA(isA<SSHAuthFailError>()),
      );
      // A key the server does not accept must not block the saved password.
      final key = SshStoredKey.generate('unauthorized');
      await SshProfileStore.instance.saveKey(key);
      final fallback = await SshConnector().connect(
        profile(config['ssh2'], 'fixture-password', key.id),
        trustPrompt: trust,
      );
      fallback.close();
    },
    skip: !enabled,
    timeout: const Timeout(Duration(seconds: 45)),
  );
  test(
    'SFTP sessions on different ports stay isolated and disconnect independently',
    () async {
      final registry = NetworkServiceRegistry.withServices([SFTPService()]);
      addTearDown(registry.disconnectAll);
      final paths = <String>[];
      for (final port in [config['ssh'], config['ssh2']]) {
        final result = await registry.connect(
          serviceName: 'SFTP',
          host: '127.0.0.1',
          username: 'developer',
          password: 'fixture-password',
          port: port,
          additionalOptions: {
            'trustPrompt':
                (String h, int p, String type, String fp, String? old) async =>
                    true,
          },
        );
        expect(result.success, isTrue, reason: result.errorMessage);
        paths.add(result.connectedPath!);
      }
      final first = registry.getServiceForPath(paths[0]);
      final second = registry.getServiceForPath(paths[1]);
      expect(first, isNot(same(second)));
      expect(registry.getServiceForPath('#network/SFTP/127.0.0.1/'), isNull);
      await registry.disconnect(paths[0]);
      expect(first!.isConnected, isFalse);
      expect(second!.isConnected, isTrue);
      expect(await second.listDirectory(paths[1]), isNotEmpty);
    },
    skip: !enabled,
  );
}
