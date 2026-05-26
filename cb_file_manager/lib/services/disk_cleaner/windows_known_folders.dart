import 'dart:io';

import 'cleaner_models.dart';

/// Resolves [PathSource] values to absolute filesystem paths against the
/// current process's environment.
///
/// Returns `null` when the underlying environment variable is missing or empty
/// — callers should silently skip rules whose source cannot be resolved.
class WindowsKnownFolders {
  WindowsKnownFolders._();

  static String? resolve(PathSource source) {
    switch (source.kind) {
      case PathSourceKind.absolute:
        final abs = source.absolutePath;
        if (abs == null || abs.isEmpty) return null;
        return _normalize(abs);
      case PathSourceKind.env:
        final env = source.envVar;
        if (env == null || env.isEmpty) return null;
        final base = Platform.environment[env];
        if (base == null || base.isEmpty) return null;
        if (source.relative.isEmpty) return _normalize(base);
        final rel = source.relative.replaceAll('/', r'\');
        return _normalize('$base\\$rel');
      case PathSourceKind.recycleBin:
        // Recycle Bin items are enumerated through TrashManager, not via a
        // single resolved path. Return null so callers know to use the
        // Recycle Bin code path instead of plain directory walking.
        return null;
    }
  }

  /// Common Windows environment variable names used by the cleaner. Exposed
  /// so tests can verify everything resolves on the host.
  static const knownEnvVars = <String>[
    'TEMP',
    'TMP',
    'LOCALAPPDATA',
    'APPDATA',
    'USERPROFILE',
    'PROGRAMDATA',
    'WINDIR',
    'SYSTEMROOT',
  ];

  static String _normalize(String path) {
    // Collapse repeated backslashes and trailing slashes (except for the
    // drive root, which always needs the trailing slash).
    var normalized = path.replaceAll('/', r'\');
    while (normalized.contains(r'\\')) {
      normalized = normalized.replaceAll(r'\\', r'\');
    }
    if (normalized.length > 3 && normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}
