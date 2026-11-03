import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cb_file_manager/services/ssh/ssh_tunnel_manager.dart';
import 'package:dartssh2/dartssh2.dart';

/// A plain TCP socket as an [SSHSocket].
class TcpSshSocket implements SSHSocket {
  TcpSshSocket(this.socket);
  final Socket socket;
  @override
  Stream<Uint8List> get stream => socket;
  @override
  StreamSink<List<int>> get sink => socket;
  @override
  Future<void> get done => socket.done;
  @override
  Future<void> close() => socket.close();
  @override
  void destroy() => socket.destroy();
  @override
  Future<void> flush() => socket.flush();
}

/// Stands in for an SSH server on loopback: `dial` opens plain TCP and a
/// remote listen binds a local port, so tunnels move real bytes.
class FakeTunnelLink implements SshTunnelLink {
  FakeTunnelLink({
    this.refuseRemote = false,
    this.failDial = false,
    this.remoteGate,
  });
  final bool refuseRemote, failDial;

  /// Holds a remote listen after it is bound, until completed.
  final Completer<void>? remoteGate;
  final _done = Completer<void>();
  final dialed = <(String, int)>[];
  ServerSocket? remoteServer;
  bool closed = false;

  @override
  Future<SSHSocket> dial(
    String host,
    int port, {
    String originHost = '127.0.0.1',
    int originPort = 0,
  }) async {
    dialed.add((host, port));
    if (failDial) throw const SocketException('open failed: unreachable');
    return TcpSshSocket(await Socket.connect(host, port));
  }

  @override
  Future<SshRemoteListener?> listenRemote(String host, int port) async {
    if (refuseRemote) return null;
    final server = remoteServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    await remoteGate?.future;
    return SshRemoteListener(
      port: server.port,
      connections: server.map<SSHSocket>(TcpSshSocket.new),
      close: () => unawaited(server.close()),
    );
  }

  @override
  Future<SSHDynamicForward> listenDynamic(String host, int port) =>
      throw UnsupportedError('Covered by the SSH loopback test');

  @override
  Future<void> get done => _done.future;

  /// Simulates the transport dropping.
  void drop() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  void close() {
    closed = true;
    drop();
  }
}

/// Answers every byte back, closing its side once the client stops sending.
Future<ServerSocket> startEchoServer() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) => socket.cast<List<int>>().pipe(socket));
  return server;
}

Future<int> freePort() async {
  final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = probe.port;
  await probe.close();
  return port;
}

/// Sends [text], half-closes, and returns everything read until the peer
/// closes.
Future<String> roundTrip(int port, String text) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.write(text);
  await socket.flush();
  await socket.close();
  final bytes = await socket.fold<List<int>>([], (all, b) => all..addAll(b));
  return String.fromCharCodes(bytes);
}
