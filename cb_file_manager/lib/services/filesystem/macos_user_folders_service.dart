import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

enum MacosUserFolderKind {
  applications,
  desktop,
  documents,
  downloads,
  home,
  pictures,
  music,
  movies,
}

class MacosUserFolder extends Equatable {
  final MacosUserFolderKind kind;
  final String path;

  const MacosUserFolder({required this.kind, required this.path});

  @override
  List<Object> get props => [kind, path];
}

/// Resolves Finder-style destinations through Foundation, including folders
/// whose location differs from a guessed path under the user's home.
class MacosUserFoldersService {
  final TargetPlatform platform;
  static const channel = MethodChannel('cb_file_manager/macos_window');

  MacosUserFoldersService({TargetPlatform? platform})
    : platform = platform ?? defaultTargetPlatform;

  Future<List<MacosUserFolder>> load() async {
    if (platform != TargetPlatform.macOS) return const [];
    final rows = await channel.invokeListMethod<Object?>(
      'getSidebarUserFolders',
    );
    final folders = <MacosUserFolder>[];
    final paths = <String>{};
    final kinds = <MacosUserFolderKind>{};
    for (final row in rows ?? const []) {
      if (row is! Map) continue;
      final kind = MacosUserFolderKind.values
          .where((value) => value.name == row['kind'])
          .firstOrNull;
      final rawPath = row['path'];
      if (kind == null || rawPath is! String || !p.posix.isAbsolute(rawPath)) {
        continue;
      }
      final path = p.posix.normalize(rawPath);
      if (kinds.contains(kind) || paths.contains(path)) continue;
      kinds.add(kind);
      paths.add(path);
      folders.add(MacosUserFolder(kind: kind, path: path));
    }
    return List.unmodifiable(folders);
  }
}
