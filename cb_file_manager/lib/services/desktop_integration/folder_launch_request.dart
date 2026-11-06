import 'dart:io';

import 'package:path/path.dart' as p;

import '../windowing/window_startup_payload.dart';

/// OS folder-open requests, distinct from file/video/torrent launches.
class FolderLaunchRequest {
  final List<WindowTabPayload> tabs;
  final List<String> rejected;
  final bool requested;

  const FolderLaunchRequest(this.tabs, this.rejected, this.requested);

  static Future<FolderLaunchRequest> takeArguments(
    List<String> arguments,
  ) async {
    final explicit = arguments.contains('--open-folder');
    final tabs = <WindowTabPayload>[];
    final rejected = <String>[];
    final remaining = <String>[];
    final seen = <String>{};
    for (final value in arguments) {
      if (value == '--open-folder') continue;
      String? directory;
      try {
        directory = normalizeLocation(value);
        if (directory != null && !await Directory(directory).exists()) {
          directory = null;
        }
      } catch (_) {
        directory = null;
      }
      if (directory != null) {
        final key = Platform.isWindows ? directory.toLowerCase() : directory;
        if (seen.add(key)) {
          final basename = p.basename(directory);
          tabs.add(
            WindowTabPayload(
              path: directory,
              name: basename.isEmpty ? directory : basename,
            ),
          );
        }
      } else if (explicit) {
        rejected.add(value);
      } else {
        remaining.add(value);
      }
    }
    arguments
      ..clear()
      ..addAll(remaining);
    if (explicit && tabs.isEmpty && rejected.isEmpty) {
      tabs.add(const WindowTabPayload(path: '#home'));
    }
    return FolderLaunchRequest(tabs, rejected, explicit || tabs.isNotEmpty);
  }

  static String? normalizeLocation(String value) {
    if (value.isEmpty || value.contains('\u0000')) return null;
    var location = value;
    if (value.toLowerCase().startsWith('file:')) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.hasQuery || uri.hasFragment) return null;
      if (!Platform.isWindows &&
          uri.host.isNotEmpty &&
          uri.host != 'localhost') {
        return null;
      }
      location = uri.toFilePath(windows: Platform.isWindows);
    }
    if (!p.isAbsolute(location)) return null;
    return p.normalize(location);
  }
}
