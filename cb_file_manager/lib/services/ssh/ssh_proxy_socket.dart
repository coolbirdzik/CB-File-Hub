import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'ssh_proxy.dart';

/// Proxy negotiation stays on this TCP connection; failures never fall back to
/// direct TCP. Destination DNS is resolved by the proxy, not by this machine.
Future<SSHSocket> openSshTransport(
  String host,
  int port, {
  SshProxy? proxy,
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (proxy == null) return SSHSocket.connect(host, port, timeout: timeout);
  if (!proxy.isValid ||
      host.isEmpty ||
      host.contains(RegExp(r'[\s/@\\\x00-\x1f\x7f]')) ||
      port < 1 ||
      port > 65535) {
    throw const FormatException('Invalid SSH proxy configuration.');
  }
  Socket? socket;
  _ProxyInput? input;
  try {
    socket = await Socket.connect(proxy.host, proxy.port, timeout: timeout);
    // Observe sink errors even if the peer fails during negotiation.
    unawaited(socket.done.catchError((Object _) {}));
    input = _ProxyInput(socket);
    await _negotiate(socket, input, proxy, host, port).timeout(timeout);
    return _ProxySocket(socket, input);
  } catch (_) {
    socket?.destroy();
    if (input != null) unawaited(input.cancel());
    // Never include raw proxy responses, URLs, or credentials in UI errors.
    throw const SocketException(
      'SSH proxy connection or authentication failed.',
    );
  }
}

Future<void> _negotiate(
  Socket socket,
  _ProxyInput input,
  SshProxy proxy,
  String host,
  int port,
) async {
  final address = InternetAddress.tryParse(host);
  switch (proxy.type) {
    case SshProxyType.httpConnect:
      final authority = address?.type == InternetAddressType.IPv6
          ? '[$host]:$port'
          : '$host:$port';
      final auth = proxy.username.isEmpty && proxy.password.isEmpty
          ? ''
          : 'Proxy-Authorization: Basic ${base64Encode(utf8.encode('${proxy.username}:${proxy.password}'))}\r\n';
      socket.add(
        ascii.encode(
          'CONNECT $authority HTTP/1.1\r\nHost: $authority\r\n${auth}Proxy-Connection: Keep-Alive\r\n\r\n',
        ),
      );
      await socket.flush();
      final header = <int>[];
      while (header.length < 16384) {
        header.add((await input.read(1)).single);
        if (header.length >= 4 &&
            header[header.length - 4] == 13 &&
            header[header.length - 3] == 10 &&
            header[header.length - 2] == 13 &&
            header.last == 10) {
          break;
        }
      }
      if (header.length >= 16384 ||
          !RegExp(
            r'^HTTP/1\.[01] 2\d\d(?: |\r)',
          ).hasMatch(latin1.decode(header))) {
        throw const FormatException('Proxy rejected CONNECT');
      }
    case SshProxyType.socks5:
      final authenticated =
          proxy.username.isNotEmpty || proxy.password.isNotEmpty;
      socket.add([5, 1, authenticated ? 2 : 0]);
      await socket.flush();
      final method = await input.read(2);
      if (method[0] != 5 || method[1] != (authenticated ? 2 : 0)) {
        throw const FormatException('SOCKS5 method');
      }
      if (authenticated) {
        final user = utf8.encode(proxy.username),
            password = utf8.encode(proxy.password);
        if (user.isEmpty ||
            user.length > 255 ||
            password.isEmpty ||
            password.length > 255) {
          throw const FormatException('SOCKS5 credentials');
        }
        socket.add([1, user.length, ...user, password.length, ...password]);
        await socket.flush();
        final auth = await input.read(2);
        if (auth[0] != 1 || auth[1] != 0) {
          throw const FormatException('SOCKS5 authentication');
        }
      }
      final domain = utf8.encode(host);
      if (address == null && domain.length > 255) {
        throw const FormatException('SOCKS5 hostname');
      }
      socket.add([
        5,
        1,
        0,
        if (address == null) ...[
          3,
          domain.length,
          ...domain,
        ] else ...[
          address.type == InternetAddressType.IPv6 ? 4 : 1,
          ...address.rawAddress,
        ],
        port >> 8,
        port & 255,
      ]);
      await socket.flush();
      final reply = await input.read(4);
      if (reply[0] != 5 || reply[1] != 0 || reply[2] != 0) {
        throw const FormatException('SOCKS5 connection');
      }
      final size = switch (reply[3]) {
        1 => 4,
        4 => 16,
        3 => (await input.read(1)).single,
        _ => throw const FormatException('SOCKS5 address'),
      };
      await input.read(size + 2);
    case SshProxyType.socks4:
      if (address?.type == InternetAddressType.IPv6) {
        throw const FormatException('SOCKS4 IPv6');
      }
      socket.add([
        4,
        1,
        port >> 8,
        port & 255,
        ...address?.rawAddress ?? [0, 0, 0, 1],
        ...utf8.encode(proxy.username),
        0,
        if (address == null) ...[...utf8.encode(host), 0],
      ]);
      await socket.flush();
      final reply = await input.read(8);
      if (reply[0] != 0 || reply[1] != 90) {
        throw const FormatException('SOCKS4 connection');
      }
  }
}

/// Keeps any banner bytes coalesced with the final handshake response.
class _ProxyInput {
  final StreamIterator<Uint8List> iterator;
  Uint8List pending = Uint8List(0);
  int offset = 0;
  _ProxyInput(Socket socket) : iterator = StreamIterator(socket);
  Future<Uint8List> read(int count) async {
    final result = Uint8List(count);
    var at = 0;
    while (at < count) {
      if (offset == pending.length) {
        if (!await iterator.moveNext()) {
          throw const FormatException('Proxy closed');
        }
        pending = iterator.current;
        offset = 0;
      }
      final size = (count - at).clamp(0, pending.length - offset);
      result.setRange(at, at + size, pending, offset);
      at += size;
      offset += size;
    }
    return result;
  }

  Stream<Uint8List> get stream async* {
    if (offset < pending.length) yield Uint8List.sublistView(pending, offset);
    while (await iterator.moveNext()) {
      yield iterator.current;
    }
  }

  Future<void> cancel() => iterator.cancel();
}

class _ProxySocket implements SSHSocket {
  final Socket socket;
  final _ProxyInput input;
  _ProxySocket(this.socket, this.input);
  @override
  Stream<Uint8List> get stream => input.stream;
  @override
  StreamSink<List<int>> get sink => socket;
  @override
  Future<void> get done => socket.done;
  @override
  Future<void> close() async {
    socket.destroy();
    await input.cancel();
  }

  @override
  void destroy() {
    socket.destroy();
    unawaited(input.cancel());
  }

  @override
  Future<void> flush() => socket.flush();
}
