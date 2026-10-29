import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/ssh/ssh_import.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/services/ssh/ssh_proxy_socket.dart';
import 'package:cb_file_manager/services/ssh/termius_local_reader.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class Peer {
  final Socket socket;
  late final input = StreamIterator(socket.expand((bytes) => bytes));
  Peer(this.socket);
  Future<List<int>> read(int count) async {
    final result = <int>[];
    for (var i = 0; i < count; i++) {
      if (!await input.moveNext()) throw StateError('fixture closed');
      result.add(input.current);
    }
    return result;
  }

  Future<String> until(List<int> terminator) async {
    final result = <int>[];
    while (result.length < 20000) {
      result.addAll(await read(1));
      if (result.length >= terminator.length &&
          result.skip(result.length - terminator.length).join(',') ==
              terminator.join(',')) {
        return utf8.decode(result);
      }
    }
    throw StateError('fixture overflow');
  }
}

Future<ServerSocket> proxyServer(Future<void> Function(Peer) handle) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  server.listen((socket) {
    addTearDown(socket.destroy);
    unawaited(handle(Peer(socket)));
  });
  return server;
}

SshProxy route(
  ServerSocket server,
  SshProxyType type, {
  String username = '',
  String password = '',
}) => SshProxy(
  id: 'route',
  name: 'Local proxy',
  type: type,
  host: '127.0.0.1',
  port: server.port,
  username: username,
  password: password,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'HTTP CONNECT sends proxy Basic credentials and preserves coalesced SSH banner',
    () async {
      final request = Completer<String>();
      final server = await proxyServer((peer) async {
        request.complete(await peer.until([13, 10, 13, 10]));
        peer.socket.add(
          ascii.encode(
            'HTTP/1.1 200 Connection established\r\n\r\nSSH-2.0-fixture\r\n',
          ),
        );
        await peer.socket.flush();
        expect(utf8.decode(await peer.read(4)), 'ping');
        peer.socket.add(utf8.encode('pong'));
        await peer.socket.flush();
      });
      final socket = await openSshTransport(
        'internal.example.test',
        2222,
        proxy: route(
          server,
          SshProxyType.httpConnect,
          username: 'proxy-user',
          password: 'fixture-password',
        ),
      );
      addTearDown(socket.destroy);
      final headers = await request.future;
      expect(
        headers,
        startsWith('CONNECT internal.example.test:2222 HTTP/1.1\r\n'),
      );
      expect(
        headers,
        contains(
          'Proxy-Authorization: Basic ${base64Encode(utf8.encode('proxy-user:fixture-password'))}',
        ),
      );
      final input = StreamIterator(socket.stream.expand((bytes) => bytes));
      Future<String> read(int count) async {
        final bytes = <int>[];
        for (var i = 0; i < count; i++) {
          expect(await input.moveNext(), isTrue);
          bytes.add(input.current);
        }
        return utf8.decode(bytes);
      }

      expect(await read(17), 'SSH-2.0-fixture\r\n');
      socket.sink.add(utf8.encode('ping'));
      await socket.flush();
      expect(await read(4), 'pong');
      await socket.close();
    },
  );

  for (final authenticated in [false, true]) {
    test(
      'SOCKS5 remote DNS and fragmented response auth=$authenticated',
      () async {
        final destination = Completer<String>();
        final server = await proxyServer((peer) async {
          expect(await peer.read(3), [5, 1, authenticated ? 2 : 0]);
          peer.socket.add([5]);
          await peer.socket.flush();
          peer.socket.add([authenticated ? 2 : 0]);
          await peer.socket.flush();
          if (authenticated) {
            expect((await peer.read(1)).single, 1);
            final user = utf8.decode(
              await peer.read((await peer.read(1)).single),
            );
            final password = utf8.decode(
              await peer.read((await peer.read(1)).single),
            );
            expect(user, 'deploy');
            expect(password, 'fixture-pass');
            peer.socket.add([1, 0]);
            await peer.socket.flush();
          }
          expect(await peer.read(4), [5, 1, 0, 3]);
          destination.complete(
            utf8.decode(await peer.read((await peer.read(1)).single)),
          );
          expect(await peer.read(2), [0, 22]);
          for (final byte in [5, 0, 0, 1, 127, 0, 0, 1, 0, 0]) {
            peer.socket.add([byte]);
            await peer.socket.flush();
          }
          peer.socket.add(utf8.encode('SSH'));
          await peer.socket.flush();
        });
        final socket = await openSshTransport(
          'only-proxy-can-resolve.invalid',
          22,
          proxy: route(
            server,
            SshProxyType.socks5,
            username: authenticated ? 'deploy' : '',
            password: authenticated ? 'fixture-pass' : '',
          ),
        );
        addTearDown(socket.destroy);
        expect(await destination.future, 'only-proxy-can-resolve.invalid');
        expect(
          utf8.decode(await socket.stream.expand((b) => b).take(3).toList()),
          'SSH',
        );
        await socket.close();
      },
    );
  }

  test('SOCKS4a forwards hostname and user ID without local DNS', () async {
    final target = Completer<String>();
    final server = await proxyServer((peer) async {
      expect(await peer.read(8), [4, 1, 0, 22, 0, 0, 0, 1]);
      expect(await peer.until([0]), 'user\u0000');
      target.complete(await peer.until([0]));
      peer.socket.add([0, 90, 0, 22, 127, 0, 0, 1, ...utf8.encode('SSH')]);
      await peer.socket.flush();
    });
    final socket = await openSshTransport(
      'private.invalid',
      22,
      proxy: route(server, SshProxyType.socks4, username: 'user'),
    );
    addTearDown(socket.destroy);
    expect(await target.future, 'private.invalid\u0000');
    expect(
      utf8.decode(await socket.stream.expand((b) => b).take(3).toList()),
      'SSH',
    );
  });

  test(
    'rejected/timeout proxy never connects directly and never leaks credentials',
    () async {
      final target = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(target.close);
      var directConnections = 0;
      target.listen((s) {
        directConnections++;
        s.destroy();
      });
      final server = await proxyServer((peer) async {
        await peer.until([13, 10, 13, 10]);
        peer.socket.add(
          ascii.encode('HTTP/1.1 407 secret-reflected-by-proxy\r\n\r\n'),
        );
        await peer.socket.flush();
      });
      final store = SshProfileStore();
      await store.saveProxy(
        route(
          server,
          SshProxyType.httpConnect,
          username: 'private-user',
          password: 'private-password',
        ),
      );
      Object? failure;
      try {
        await SshConnector(store).connect(
          SshProfile(
            id: 'host',
            name: 'Host',
            host: '127.0.0.1',
            port: target.port,
            username: 'deploy',
            proxyId: 'route',
          ),
        );
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<SocketException>());
      expect('$failure', isNot(contains('private-password')));
      expect('$failure', isNot(contains('secret-reflected')));
      expect(directConnections, 0);
      final hanging = await proxyServer((peer) async {
        await peer.read(3);
      });
      await expectLater(
        openSshTransport(
          '127.0.0.1',
          target.port,
          proxy: route(hanging, SshProxyType.socks5),
          timeout: const Duration(milliseconds: 80),
        ),
        throwsA(isA<SocketException>()),
      );
      expect(directConnections, 0);
      await expectLater(
        SshConnector(store).connect(
          const SshProfile(
            id: 'missing',
            name: 'Missing',
            host: '127.0.0.1',
            username: 'deploy',
            proxyId: 'absent',
          ),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'Termius decrypt-normalize-import preserves proxy identity, orphan proxies and host references',
    () async {
      final document = TermiusLocalReader.normalize({
        'ssh_identities': [
          {'id': 2, 'username': 'proxy-user', 'password': 'proxy-pass'},
          {'id': 3, 'username': 'root'},
        ],
        'proxies': [
          {
            'id': 8,
            'label': 'Office proxy',
            'type': 'SOCKS5',
            'hostname': 'proxy.test',
            'port': 1080,
            'identity': {'id': 2},
          },
          {
            'id': 9,
            'label': 'Unused',
            'type': 'HTTP',
            'hostname': 'unused.test',
            'port': 8080,
          },
        ],
        'ssh_configs': [
          {
            'id': 4,
            'identity': {'id': 3},
            'proxycommand': {'id': 8},
          },
        ],
        'hosts': [
          {
            'id': 5,
            'label': 'Server',
            'address': 'server.test',
            'ssh_config': {'id': 4},
          },
        ],
      }, []);
      final preview = SshImporter.parse([
        SshImportFile('Termius.json', jsonEncode(document)),
      ]);
      expect(preview.issues, isEmpty);
      expect(preview.proxies, hasLength(2));
      expect(preview.hosts.single.proxyId, preview.proxies.first.id);
      expect(preview.proxies.first.password, 'proxy-pass');
      final store = SshProfileStore();
      final summary = await store.importProfiles(
        profiles: preview.hosts,
        keys: preview.keys,
        proxies: preview.proxies,
      );
      expect(summary.proxies, 2);
      final restored = SshProfileStore();
      await restored.load();
      expect(restored.profiles.single.proxyId, restored.proxies.first.id);
      expect(restored.proxies.first.password, 'proxy-pass');
      await expectLater(
        restored.deleteProxy(restored.proxies.first.id),
        throwsStateError,
      );
      final again = await restored.importProfiles(
        profiles: preview.hosts,
        keys: [],
        proxies: preview.proxies,
      );
      expect(again.hosts, 0);
      expect(again.proxies, 0);
      expect(restored.proxies, hasLength(2));
    },
  );

  test(
    'invalid/missing proxy references are skipped and batch rollback includes proxies',
    () async {
      final preview = SshImporter.parse([
        const SshImportFile(
          'hosts.json',
          '{"hosts":[{"host":"server.test","proxy_id":"missing"}]}',
        ),
      ]);
      expect(preview.hosts, isEmpty);
      expect(preview.issues.single.problem, SshImportProblem.proxy);
      final store = SshProfileStore();
      await expectLater(
        store.importProfiles(
          profiles: [
            const SshProfile(
              id: 'host',
              name: 'Host',
              host: 'test',
              username: 'root',
              proxyId: 'missing',
            ),
          ],
          keys: [],
          proxies: [
            const SshProxy(
              id: 'proxy',
              name: 'New',
              type: SshProxyType.socks5,
              host: 'proxy.test',
              port: 1080,
            ),
          ],
        ),
        throwsStateError,
      );
      expect(store.proxies, isEmpty);
      expect(store.profiles, isEmpty);
    },
  );
}
