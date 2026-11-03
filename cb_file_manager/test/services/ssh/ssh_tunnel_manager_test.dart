import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/services/ssh/ssh_tunnel_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_tunnel_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SshProfileStore store;
  late ServerSocket echo;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    store = SshProfileStore();
    await store.saveProfile(
      const SshProfile(
        id: 'host',
        name: 'Development server',
        host: 'dev.example.test',
        username: 'developer',
      ),
    );
    echo = await startEchoServer();
  });
  tearDown(() => echo.close());

  SshTunnelManager manager(FakeTunnelLink link) {
    final tunnels = SshTunnelManager(
      store,
      connect: (_, {trustPrompt, onCancelable}) async => link,
    );
    addTearDown(tunnels.dispose);
    return tunnels;
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  test('local forward carries bytes both ways and half-closes', () async {
    final link = FakeTunnelLink();
    final tunnels = manager(link);
    final forward = SshForward(
      id: 'l',
      profileId: 'host',
      type: SshForwardType.local,
      bindPort: await freePort(),
      targetHost: '127.0.0.1',
      targetPort: echo.port,
    );
    await store.saveForward(forward);
    await tunnels.start(forward);
    expect(tunnels.state('l').status, SshTunnelStatus.running);
    expect(tunnels.state('l').boundPort, forward.bindPort);
    expect(
      await roundTrip(forward.bindPort, 'ping through -L'),
      'ping through -L',
    );
    expect(link.dialed.single, ('127.0.0.1', echo.port));
    await until(() => tunnels.state('l').connections == 0);

    await tunnels.stop('l');
    expect(tunnels.state('l').status, SshTunnelStatus.stopped);
    expect(link.closed, isTrue);
    await expectLater(
      Socket.connect(InternetAddress.loopbackIPv4, forward.bindPort),
      throwsA(isA<SocketException>()),
    );
  });

  test('a refused destination drops that connection only', () async {
    final link = FakeTunnelLink(failDial: true);
    final tunnels = manager(link);
    final forward = SshForward(
      id: 'l',
      profileId: 'host',
      type: SshForwardType.local,
      bindPort: await freePort(),
      targetHost: 'db.internal',
      targetPort: 5432,
    );
    await tunnels.start(forward);
    expect(await roundTrip(forward.bindPort, 'x'), '');
    await until(() => tunnels.state('l').error != null);
    expect(tunnels.state('l').status, SshTunnelStatus.running);
    expect(tunnels.state('l').connections, 0);
  });

  test('remote forward delivers server connections to the target', () async {
    final link = FakeTunnelLink();
    final tunnels = manager(link);
    await tunnels.start(
      SshForward(
        id: 'r',
        profileId: 'host',
        type: SshForwardType.remote,
        bindPort: 9000,
        targetHost: '127.0.0.1',
        targetPort: echo.port,
      ),
    );
    final state = tunnels.state('r');
    expect(state.status, SshTunnelStatus.running);
    expect(state.boundPort, link.remoteServer!.port);
    expect(
      await roundTrip(state.boundPort!, 'back through -R'),
      'back through -R',
    );
  });

  test('a refused remote listen fails the tunnel', () async {
    final tunnels = manager(FakeTunnelLink(refuseRemote: true));
    await tunnels.start(
      const SshForward(
        id: 'r',
        profileId: 'host',
        type: SshForwardType.remote,
        bindPort: 9000,
        targetHost: 'localhost',
        targetPort: 3000,
      ),
    );
    expect(tunnels.state('r').status, SshTunnelStatus.failed);
    expect(tunnels.state('r').failure, SshTunnelFailure.refused);
  });

  test('a dropped transport fails the tunnel and frees the port', () async {
    final link = FakeTunnelLink();
    final tunnels = manager(link);
    final forward = SshForward(
      id: 'l',
      profileId: 'host',
      type: SshForwardType.local,
      bindPort: await freePort(),
      targetHost: '127.0.0.1',
      targetPort: echo.port,
    );
    await tunnels.start(forward);
    link.drop();
    await until(
      () => tunnels.state('l').failure == SshTunnelFailure.disconnected,
    );
    final rebound = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      forward.bindPort,
    );
    await rebound.close();
  });

  test('stop while connecting closes the late connection', () async {
    final link = FakeTunnelLink();
    final pending = Completer<SshTunnelLink>();
    var cancelled = false;
    final tunnels = SshTunnelManager(
      store,
      connect: (_, {trustPrompt, onCancelable}) {
        onCancelable?.call(() => cancelled = true);
        return pending.future;
      },
    );
    addTearDown(tunnels.dispose);
    final starting = tunnels.start(
      SshForward(
        id: 'l',
        profileId: 'host',
        type: SshForwardType.local,
        bindPort: await freePort(),
        targetHost: '127.0.0.1',
        targetPort: echo.port,
      ),
    );
    await until(() => tunnels.state('l').status == SshTunnelStatus.starting);
    await tunnels.stop('l');
    expect(cancelled, isTrue);
    pending.complete(link);
    await starting;
    expect(link.closed, isTrue);
    expect(tunnels.state('l').status, SshTunnelStatus.stopped);
  });

  test('stop while the listener is opening releases it', () async {
    final gate = Completer<void>();
    final link = FakeTunnelLink(remoteGate: gate);
    final tunnels = manager(link);
    final starting = tunnels.start(
      SshForward(
        id: 'r',
        profileId: 'host',
        type: SshForwardType.remote,
        bindPort: 9000,
        targetHost: '127.0.0.1',
        targetPort: echo.port,
      ),
    );
    await until(() => link.remoteServer != null);
    await tunnels.stop('r');
    gate.complete();
    await starting;
    expect(tunnels.state('r').status, SshTunnelStatus.stopped);
    // The listener that arrived after Stop must be closed, not left bound.
    var released = false;
    for (var i = 0; i < 50 && !released; i++) {
      try {
        final probe = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          link.remoteServer!.port,
        );
        await probe.close();
        released = true;
      } on SocketException {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    expect(released, isTrue);
  });

  test('deleting the host removes its rules and stops them', () async {
    final link = FakeTunnelLink();
    final tunnels = manager(link);
    final forward = SshForward(
      id: 'l',
      profileId: 'host',
      type: SshForwardType.local,
      bindPort: await freePort(),
      targetHost: '127.0.0.1',
      targetPort: echo.port,
    );
    await store.saveForward(forward);
    await tunnels.start(forward);
    await store.deleteProfile('host');
    expect(store.forwards, isEmpty);
    expect(tunnels.state('l').status, SshTunnelStatus.stopped);
    expect(link.closed, isTrue);
  });

  test('rules survive a reload of the vault', () async {
    await store.saveForward(
      const SshForward(
        id: 'd',
        name: 'Browser proxy',
        profileId: 'host',
        type: SshForwardType.dynamic,
        bindPort: 1080,
      ),
    );
    final reloaded = SshProfileStore();
    await reloaded.load();
    final rule = reloaded.forwards.single;
    expect(rule.name, 'Browser proxy');
    expect(rule.type, SshForwardType.dynamic);
    expect(rule.bindAddress, '127.0.0.1:1080');
    expect(rule.exposesNetwork, isFalse);
    expect(
      const SshForward(
        id: 'x',
        profileId: 'host',
        type: SshForwardType.local,
        bindHost: '0.0.0.0',
        bindPort: 8080,
        targetHost: 'localhost',
        targetPort: 80,
      ).exposesNetwork,
      isTrue,
    );
    await expectLater(
      store.saveForward(
        const SshForward(
          id: 'bad',
          profileId: 'host',
          type: SshForwardType.local,
          bindPort: 70000,
          targetHost: 'localhost',
          targetPort: 80,
        ),
      ),
      throwsFormatException,
    );
  });
}
