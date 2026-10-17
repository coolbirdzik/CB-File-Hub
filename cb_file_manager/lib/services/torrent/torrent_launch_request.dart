import 'package:path/path.dart' as p;

class TorrentLaunchRequest {
  final String source;

  TorrentLaunchRequest(this.source);

  static bool isSource(String value) {
    if (value.isEmpty ||
        value.length > 32768 ||
        value.contains(RegExp(r'[\x00-\x1f"]'))) {
      return false;
    }
    if (value.toLowerCase().startsWith('magnet:')) return true;
    return !value.startsWith('-') &&
        p.extension(value).toLowerCase() == '.torrent';
  }

  static List<String> takeArguments(List<String> arguments) {
    final sources = <String>[];
    arguments.removeWhere((argument) {
      if (argument == '--open-torrent') return true;
      if (!isSource(argument)) return false;
      sources.add(argument);
      return true;
    });
    return sources;
  }

  static String pathFor(String source) =>
      '#torrents?${Uri(queryParameters: {'open': source}).query}';
  static bool isPath(String path) =>
      path == '#torrents' || path.startsWith('#torrents?');
  static String? sourceFromPath(String path) {
    if (!path.startsWith('#torrents?')) return null;
    try {
      final source = Uri.splitQueryString(
        path.substring(path.indexOf('?') + 1),
      )['open'];
      return source != null && isSource(source) ? source : null;
    } on FormatException {
      return null;
    }
  }
}
