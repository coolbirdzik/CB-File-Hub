import 'package:path/path.dart' as p;

class TorrentDownloadOptions {
  final String destination;
  final bool startImmediately;

  const TorrentDownloadOptions(this.destination, this.startImmediately);

  factory TorrentDownloadOptions.fromJson(Map<String, dynamic> json) {
    final destination = json['destination'];
    final start = json['startImmediately'];
    if (destination is! String ||
        destination.contains('\x00') ||
        !p.isAbsolute(destination) ||
        start is! bool) {
      throw const FormatException('Invalid torrent download options');
    }
    return TorrentDownloadOptions(p.normalize(destination), start);
  }

  Map<String, dynamic> toJson() => {
    'destination': destination,
    'startImmediately': startImmediately,
  };
}

class TorrentDownloadRequest {
  final String name;
  final String initialDestination;
  final bool startImmediately;
  final bool destinationLocked;
  final String language;
  final bool dark;
  final int accent;

  const TorrentDownloadRequest({
    required this.name,
    required this.initialDestination,
    this.startImmediately = true,
    this.destinationLocked = false,
    this.language = 'en',
    this.dark = false,
    this.accent = 0xFF0078D4,
  });

  factory TorrentDownloadRequest.fromJson(Map<String, dynamic> json) =>
      TorrentDownloadRequest(
        name: json['name'] as String,
        initialDestination: json['initialDestination'] as String,
        startImmediately: json['startImmediately'] as bool,
        destinationLocked: json['destinationLocked'] as bool,
        language: json['language'] as String,
        dark: json['dark'] as bool,
        accent: json['accent'] as int,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'initialDestination': initialDestination,
    'startImmediately': startImmediately,
    'destinationLocked': destinationLocked,
    'language': language,
    'dark': dark,
    'accent': accent,
  };
}
