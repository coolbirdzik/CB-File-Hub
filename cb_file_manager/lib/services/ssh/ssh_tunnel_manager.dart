import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'ssh_profile_store.dart';

/// The SSH side of a tunnel. [SSHClient] is the real one; tests substitute a
/// link that dials plain TCP.
abstract class SshTunnelLink {
  /// Opens a `direct-tcpip` channel to [host]:[port] as seen by the server.
  Future<SSHSocket> dial(
    String host,
    int port, {
    String originHost = '127.0.0.1',
    int originPort = 0,
  });

  /// Asks the server to listen and send connections back (`tcpip-forward`).
  /// Null when the server refuses.
  Future<SshRemoteListener?> listenRemote(String host, int port);

  /// Starts a local SOCKS5 server whose connections go through the server.
  Future<SSHDynamicForward> listenDynamic(String host, int port);

  /// Completes when the transport closes.
  Future<void> get done;
  void close();
}

class SshRemoteListener {
  /// The port the server listens on.
  final int port;
  final Stream<SSHSocket> connections;
  final void Function() close;
  const SshRemoteListener({
    required this.port,
    required this.connections,
    required this.close,
  });
}

class _ClientLink implements SshTunnelLink {
  _ClientLink(this.client);
  final SSHClient client;

  @override
  Future<SSHSocket> dial(
    String host,
    int port, {
    String originHost = '127.0.0.1',
    int originPort = 0,
  }) => client.forwardLocal(
    host,
    port,
    localHost: originHost,
    localPort: originPort,
  );

  @override
  Future<SshRemoteListener?> listenRemote(String host, int port) async {
    final forward = await client.forwardRemote(host: host, port: port);
    if (forward == null) return null;
    return SshRemoteListener(
      port: forward.port,
      connections: forward.connections,
      // Not forward.close(): its unawaited cancel request fails with "client
      // closed" when the transport goes next, as it does on stop.
      close: () => unawaited(
        client.cancelForwardRemote(forward).then((_) {}, onError: (_) {}),
      ),
    );
  }

  @override
  Future<SSHDynamicForward> listenDynamic(String host, int port) =>
      client.forwardDynamic(bindHost: host, bindPort: port);

  @override
  Future<void> get done => client.done;

  @override
  void close() => client.close();
}

/// Opens the link for [profile]. [onCancelable] receives a callback that
/// aborts the connection while it is still authenticating.
typedef SshTunnelConnect =
    Future<SshTunnelLink> Function(
      SshProfile profile, {
      SshTrustPrompt? trustPrompt,
      void Function(void Function() cancel)? onCancelable,
    });

enum SshTunnelStatus { stopped, starting, running, failed }

enum SshTunnelFailure {
  /// The server declined `tcpip-forward` (AllowTcpForwarding, GatewayPorts,
  /// or a port already taken on the server).
  refused,

  /// The SSH transport closed while the tunnel ran.
  disconnected,

  /// See [SshTunnelState.error].
  error,
}

@immutable
class SshTunnelState {
  final SshTunnelStatus status;

  /// Open connections through a local or remote forward.
  final int connections;

  /// The port actually listened on.
  final int? boundPort;
  final SshTunnelFailure? failure;

  /// Why the tunnel failed, or the latest connection that could not be
  /// forwarded while it keeps running.
  final String? error;

  const SshTunnelState({
    this.status = SshTunnelStatus.stopped,
    this.connections = 0,
    this.boundPort,
    this.failure,
    this.error,
  });

  bool get isActive =>
      status == SshTunnelStatus.starting || status == SshTunnelStatus.running;
}

/// Runs saved [SshForward] rules app-wide, so tunnels survive tab changes.
/// Each tunnel has its own SSH connection. Rules removed from the store, or
/// whose host was deleted, stop on their own.
class SshTunnelManager extends ChangeNotifier {
  static final instance = SshTunnelManager(SshProfileStore.instance);

  SshTunnelManager(
    this.store, {
    SshTunnelConnect? connect,
    this.dialTimeout = const Duration(seconds: 15),
  }) : _connect = connect ?? _connectClient(store) {
    store.addListener(_storeChanged);
  }

  final SshProfileStore store;
  final SshTunnelConnect _connect;

  /// Limits how long a remote forward waits for its local destination.
  final Duration dialTimeout;
  final _tunnels = <String, _Tunnel>{};
  bool _disposed = false;

  static SshTunnelConnect _connectClient(SshProfileStore store) =>
      (profile, {trustPrompt, onCancelable}) async => _ClientLink(
        await SshConnector(store).connect(
          profile,
          trustPrompt: trustPrompt,
          onClientCreated: (client) => onCancelable?.call(client.close),
        ),
      );

  SshTunnelState state(String id) =>
      _tunnels[id]?.state ?? const SshTunnelState();

  bool isActive(String id) => state(id).isActive;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _storeChanged() {
    final ids = {
      for (final f in store.forwards)
        if (store.profiles.any((p) => p.id == f.profileId)) f.id,
    };
    for (final id in _tunnels.keys.where((id) => !ids.contains(id)).toList()) {
      _tunnels.remove(id)?.shutdown();
    }
    _notify();
  }

  Future<void> start(SshForward forward, {SshTrustPrompt? trustPrompt}) async {
    if (isActive(forward.id)) return;
    _tunnels.remove(forward.id)?.shutdown();
    final tunnel = _Tunnel(forward, _notify, dialTimeout);
    _tunnels[forward.id] = tunnel;
    _notify();
    try {
      await store.load();
      if (tunnel.closed) return;
      final profile = store.profiles
          .where((p) => p.id == forward.profileId)
          .firstOrNull;
      if (profile == null) throw StateError('Saved SSH host no longer exists.');
      final link = await _connect(
        profile,
        trustPrompt: trustPrompt,
        onCancelable: (cancel) => tunnel.cancelPending = cancel,
      );
      tunnel.cancelPending = null;
      if (tunnel.closed) {
        link.close();
        return;
      }
      await tunnel.open(link);
    } on _Refused {
      tunnel.fail(SshTunnelFailure.refused);
    } catch (e) {
      tunnel.fail(SshTunnelFailure.error, e);
    }
  }

  Future<void> stop(String id) async {
    final tunnel = _tunnels.remove(id);
    if (tunnel == null) return;
    tunnel.shutdown();
    _notify();
  }

  void stopAll() {
    for (final tunnel in _tunnels.values) {
      tunnel.shutdown();
    }
    _tunnels.clear();
    _notify();
  }

  @override
  void dispose() {
    store.removeListener(_storeChanged);
    stopAll();
    _disposed = true;
    super.dispose();
  }
}

class _Refused implements Exception {
  const _Refused();
}

/// Lets a dart:io [Socket] stand where an [SSHSocket] goes.
class _TcpEndpoint implements SSHSocket {
  _TcpEndpoint(this.socket);
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

/// One forwarded connection: both ends, closed together exactly once.
class _Pair {
  _Pair(this.onClosed);
  final void Function(_Pair) onClosed;
  final ends = <SSHSocket>[];
  bool closed = false;

  void add(SSHSocket end) {
    if (closed) {
      end.destroy();
      return;
    }
    ends.add(end);
    end.done.catchError((_) {});
  }

  /// Copies each direction with backpressure. A side that finishes sending
  /// half-closes the other, so request/response protocols that shut down
  /// their write side still get an answer.
  void bridge() {
    if (ends.length != 2) return close();
    Future<void> pump(SSHSocket from, SSHSocket to) async {
      await to.sink.addStream(from.stream);
      await to.sink.close();
    }

    Future.wait([
      pump(ends[0], ends[1]),
      pump(ends[1], ends[0]),
    ]).then((_) => close(), onError: (Object _) => close());
  }

  void close() {
    if (closed) return;
    closed = true;
    for (final end in ends) {
      try {
        end.destroy();
      } catch (_) {}
    }
    onClosed(this);
  }
}

class _Tunnel {
  _Tunnel(this.forward, this.onChanged, this.dialTimeout);
  final SshForward forward;
  final void Function() onChanged;
  final Duration dialTimeout;
  SshTunnelState state = const SshTunnelState(status: SshTunnelStatus.starting);
  void Function()? cancelPending;
  SshTunnelLink? link;
  ServerSocket? _server;
  SshRemoteListener? _remote;
  SSHDynamicForward? _dynamic;
  StreamSubscription<Object>? _accepting;
  final _pairs = <_Pair>{};
  bool closed = false;

  void _set(SshTunnelState next) {
    if (closed) return;
    state = next;
    onChanged();
  }

  SshTunnelState _running({String? error}) => SshTunnelState(
    status: SshTunnelStatus.running,
    connections: _pairs.length,
    boundPort: state.boundPort,
    error: error ?? state.error,
  );

  Future<void> open(SshTunnelLink link) async {
    this.link = link;
    unawaited(
      link.done.then(
        (_) => fail(SshTunnelFailure.disconnected),
        onError: (Object e) => fail(SshTunnelFailure.disconnected, e),
      ),
    );
    final f = forward;
    final int port;
    // A Stop during any await below has already run _close(), before the new
    // listener existed, so each branch closes what it just opened.
    switch (f.type) {
      case SshForwardType.local:
        final server = _server = await ServerSocket.bind(
          f.bindHost,
          f.bindPort,
        );
        if (closed) return server.close().then((_) {});
        _accepting = server.listen(_acceptLocal);
        port = server.port;
      case SshForwardType.remote:
        final remote = _remote = await link.listenRemote(
          f.bindHost,
          f.bindPort,
        );
        if (remote == null) throw const _Refused();
        if (closed) return remote.close();
        _accepting = remote.connections.listen(_acceptRemote);
        port = remote.port;
      case SshForwardType.dynamic:
        final socks = _dynamic = await link.listenDynamic(
          f.bindHost,
          f.bindPort,
        );
        if (closed) return socks.close();
        port = socks.port;
    }
    _set(SshTunnelState(status: SshTunnelStatus.running, boundPort: port));
  }

  _Pair _newPair() {
    final pair = _Pair((pair) {
      if (_pairs.remove(pair)) _set(_running());
    });
    _pairs.add(pair);
    _set(_running());
    return pair;
  }

  Future<void> _acceptLocal(Socket socket) async {
    final pair = _newPair()..add(_TcpEndpoint(socket));
    try {
      final channel = await link!.dial(
        forward.targetHost,
        forward.targetPort,
        originHost: socket.remoteAddress.address,
        originPort: socket.remotePort,
      );
      pair
        ..add(channel)
        ..bridge();
    } catch (e) {
      // The server could not reach the destination; keep listening.
      _set(_running(error: '$e'));
      pair.close();
    }
  }

  Future<void> _acceptRemote(SSHSocket channel) async {
    final pair = _newPair()..add(channel);
    try {
      final socket = await Socket.connect(
        forward.targetHost,
        forward.targetPort,
        timeout: dialTimeout,
      );
      pair
        ..add(_TcpEndpoint(socket))
        ..bridge();
    } catch (e) {
      _set(_running(error: '$e'));
      pair.close();
    }
  }

  void fail(SshTunnelFailure failure, [Object? error]) {
    if (closed) return;
    final next = SshTunnelState(
      status: SshTunnelStatus.failed,
      failure: failure,
      error: error == null ? null : '$error',
    );
    _close();
    state = next;
    onChanged();
  }

  void shutdown() {
    if (closed) return;
    _close();
    state = const SshTunnelState();
  }

  /// Listener first, then live connections, then the transport: closing the
  /// client under open channels aborts the socket mid-write.
  void _close() {
    closed = true;
    cancelPending?.call();
    cancelPending = null;
    unawaited(_accepting?.cancel());
    try {
      unawaited(_server?.close().then<void>((_) {}, onError: (_) {}));
      _remote?.close();
      unawaited(_dynamic?.close().catchError((_) {}));
    } catch (_) {}
    for (final pair in _pairs.toList()) {
      pair.close();
    }
    _pairs.clear();
    link?.close();
  }
}
