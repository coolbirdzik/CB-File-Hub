import 'dart:convert';

enum SshProxyType { httpConnect, socks5, socks4 }

class SshProxy {
  final String id, name, host, username, password;
  final SshProxyType type;
  final int port;
  const SshProxy({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    required this.port,
    this.username = '',
    this.password = '',
  });

  static SshProxyType? parseType(String value) =>
      switch (value.toLowerCase().replaceAll(RegExp(r'[ _-]'), '')) {
        'http' || 'httpconnect' => SshProxyType.httpConnect,
        'socks' || 'socks5' => SshProxyType.socks5,
        'socks4' || 'socks4a' => SshProxyType.socks4,
        _ => null,
      };
  String get protocol => switch (type) {
    SshProxyType.httpConnect => 'HTTP CONNECT',
    SshProxyType.socks5 => 'SOCKS5',
    SshProxyType.socks4 => 'SOCKS4a',
  };
  bool get isValid =>
      host.isNotEmpty &&
      !host.contains(RegExp(r'[\s/@\\\x00-\x1f\x7f]')) &&
      port > 0 &&
      port <= 65535 &&
      !username.contains(RegExp(r'[\r\n\x00]')) &&
      (type != SshProxyType.httpConnect || !username.contains(':')) &&
      (type != SshProxyType.socks5 ||
          (username.isEmpty && password.isEmpty) ||
          (utf8.encode(username).isNotEmpty &&
              utf8.encode(username).length <= 255 &&
              utf8.encode(password).isNotEmpty &&
              utf8.encode(password).length <= 255)) &&
      (type != SshProxyType.socks4 || password.isEmpty);
  bool sameConnection(SshProxy other) =>
      type == other.type &&
      host.toLowerCase() == other.host.toLowerCase() &&
      port == other.port &&
      username == other.username &&
      password == other.password;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
  };
  factory SshProxy.fromJson(Map<String, dynamic> j) => SshProxy(
    id: j['id'],
    name: j['name'],
    type:
        parseType(j['type']) ??
        (throw const FormatException('Unsupported SSH proxy type')),
    host: j['host'],
    port: j['port'],
    username: j['username'] ?? '',
    password: j['password'] ?? '',
  );
}
