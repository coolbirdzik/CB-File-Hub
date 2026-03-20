class NetworkCredentials {
  int id = 0;
  String serviceType;
  String host;
  String username;
  String password;
  int? port;
  String? domain;
  String? additionalOptions;
  DateTime lastConnected;

  NetworkCredentials({
    required this.serviceType,
    required this.host,
    required this.username,
    required this.password,
    this.port,
    this.domain,
    this.additionalOptions,
    DateTime? lastConnected,
  }) : lastConnected = lastConnected ?? DateTime.now();

  factory NetworkCredentials.fromDatabaseMap(Map<String, Object?> map) {
    return NetworkCredentials(
      serviceType: map['service_type'] as String? ?? '',
      host: map['host'] as String? ?? '',
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      port: map['port'] as int?,
      domain: map['domain'] as String?,
      additionalOptions: map['additional_options'] as String?,
      lastConnected: DateTime.fromMillisecondsSinceEpoch(
        map['last_connected'] as int? ?? 0,
      ),
    )..id = map['id'] as int? ?? 0;
  }

  Map<String, Object?> toDatabaseMap() {
    return <String, Object?>{
      'id': id == 0 ? null : id,
      'service_type': serviceType,
      'host': host,
      'normalized_host': normalizedHost.toLowerCase(),
      'username': username,
      'password': password,
      'port': port,
      'domain': domain,
      'additional_options': additionalOptions,
      'last_connected': lastConnected.millisecondsSinceEpoch,
    };
  }

  String get normalizedHost {
    return host
        .replaceAll(RegExp(r'^[a-z]+://'), '')
        .replaceAll(RegExp(r':\d+$'), '');
  }

  String get uniqueKey =>
      '$serviceType:${normalizedHost.toLowerCase()}:$username';
}
