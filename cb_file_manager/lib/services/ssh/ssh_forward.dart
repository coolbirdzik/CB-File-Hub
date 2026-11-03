/// `ssh -L`, `ssh -R` and `ssh -D`.
enum SshForwardType { local, remote, dynamic }

/// A saved port-forwarding rule. It holds no secret, but lives in the same
/// vault document as the host it routes through.
class SshForward {
  final String id, name, profileId;
  final SshForwardType type;

  /// Where the tunnel listens: on this computer for [SshForwardType.local]
  /// and [SshForwardType.dynamic], on the SSH server for
  /// [SshForwardType.remote].
  final String bindHost;
  final int bindPort;

  /// Where connections go: resolved by the SSH server for a local forward,
  /// by this computer for a remote one. Unused by a dynamic (SOCKS) forward.
  final String targetHost;
  final int targetPort;

  const SshForward({
    required this.id,
    required this.profileId,
    required this.type,
    required this.bindPort,
    this.name = '',
    this.bindHost = '127.0.0.1',
    this.targetHost = '',
    this.targetPort = 0,
  });

  static bool _validPort(int port) => port > 0 && port <= 65535;

  bool get isValid =>
      profileId.isNotEmpty &&
      bindHost.trim().isNotEmpty &&
      _validPort(bindPort) &&
      (type == SshForwardType.dynamic ||
          (targetHost.trim().isNotEmpty && _validPort(targetPort)));

  /// Other devices on the network can use the tunnel.
  bool get exposesNetwork => !const {
    '127.0.0.1',
    'localhost',
    '::1',
  }.contains(bindHost.trim().toLowerCase());

  static String address(String host, int port) =>
      host.contains(':') ? '[$host]:$port' : '$host:$port';

  String get bindAddress => address(bindHost, bindPort);
  String get targetAddress => address(targetHost, targetPort);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'profileId': profileId,
    'type': type.name,
    'bindHost': bindHost,
    'bindPort': bindPort,
    'targetHost': targetHost,
    'targetPort': targetPort,
  };

  factory SshForward.fromJson(Map<String, dynamic> j) => SshForward(
    id: j['id'],
    name: j['name'] ?? '',
    profileId: j['profileId'],
    type: SshForwardType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => SshForwardType.local,
    ),
    bindHost: j['bindHost'] ?? '127.0.0.1',
    bindPort: j['bindPort'] ?? 0,
    targetHost: j['targetHost'] ?? '',
    targetPort: j['targetPort'] ?? 0,
  );
}
