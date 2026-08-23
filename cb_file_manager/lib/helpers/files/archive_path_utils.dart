import 'dart:io';

import 'package:path/path.dart' as p;

/// Parsed location inside a browsable archive virtual path.
class ArchiveBrowseLocation {
  final String archiveFile;
  final String innerPath;

  const ArchiveBrowseLocation({
    required this.archiveFile,
    required this.innerPath,
  });

  bool get isAtArchiveRoot => innerPath.isEmpty;

  String get virtualPath => ArchivePathUtils.build(
        archiveFile: archiveFile,
        innerPath: innerPath,
      );
}

/// Breadcrumb segment for archive address bars.
class ArchiveBreadcrumb {
  final String label;
  final String virtualPath;

  const ArchiveBreadcrumb({
    required this.label,
    required this.virtualPath,
  });
}

/// Virtual paths for in-tab archive browsing (`#archive?file=…&inner=…`).
class ArchivePathUtils {
  ArchivePathUtils._();

  static const _prefix = '#archive';

  static bool isArchiveBrowsePath(String path) => path.startsWith('$_prefix?');

  static bool isArchiveEntryPath(String path) {
    final location = parse(path);
    return location != null && location.innerPath.isNotEmpty;
  }

  static ArchiveBrowseLocation? parse(String path) {
    if (!isArchiveBrowsePath(path)) return null;

    final query = path.substring('$_prefix?'.length);
    if (query.isEmpty) return null;

    final params = Uri.splitQueryString(query);
    final archiveFile = params['file'];
    if (archiveFile == null || archiveFile.isEmpty) return null;

    return ArchiveBrowseLocation(
      archiveFile: archiveFile,
      innerPath: _normalizeInner(params['inner'] ?? ''),
    );
  }

  static String build({
    required String archiveFile,
    String innerPath = '',
  }) {
    final params = <String, String>{'file': archiveFile};
    final inner = _normalizeInner(innerPath);
    if (inner.isNotEmpty) {
      params['inner'] = inner;
    }
    return '$_prefix?${Uri(queryParameters: params).query}';
  }

  static String buildChildPath({
    required ArchiveBrowseLocation location,
    required String entryName,
    required bool isDirectory,
  }) {
    final childInner = location.innerPath.isEmpty
        ? entryName
        : '${location.innerPath}/$entryName';
    return build(
      archiveFile: location.archiveFile,
      innerPath: isDirectory ? childInner : childInner,
    );
  }

  static String? parentBrowsePath(String path) {
    final location = parse(path);
    if (location == null) return null;

    if (location.innerPath.isNotEmpty) {
      final parts = location.innerPath.split('/');
      parts.removeLast();
      return build(
        archiveFile: location.archiveFile,
        innerPath: parts.join('/'),
      );
    }

    try {
      return Directory(location.archiveFile).parent.path;
    } catch (_) {
      return null;
    }
  }

  static String displayPath(String path) {
    final location = parse(path);
    if (location == null) return path;

    if (location.innerPath.isEmpty) {
      return location.archiveFile;
    }

    final inner = location.innerPath.replaceAll('/', Platform.pathSeparator);
    return p.join(location.archiveFile, inner);
  }

  /// Label to show for an archive virtual path: the entry name inside the
  /// archive, or the archive file name when the path points at its root.
  /// Returns null for paths that are not archive virtual paths, so call sites
  /// can fall back to normal filesystem basename resolution.
  static String? entryDisplayName(String path) {
    final location = parse(path);
    if (location == null) return null;
    if (location.innerPath.isEmpty) {
      return p.basename(location.archiveFile);
    }
    return location.innerPath.split('/').last;
  }

  static String tabTitle(String path) => entryDisplayName(path) ?? path;

  static String? entryFileName(String path) {
    final location = parse(path);
    if (location == null || location.innerPath.isEmpty) return null;
    return location.innerPath.split('/').last;
  }

  static List<ArchiveBreadcrumb> breadcrumbs(String path) {
    final location = parse(path);
    if (location == null) return const [];

    final crumbs = <ArchiveBreadcrumb>[
      ArchiveBreadcrumb(
        label: p.basename(location.archiveFile),
        virtualPath: build(archiveFile: location.archiveFile),
      ),
    ];

    if (location.innerPath.isEmpty) return crumbs;

    final parts = location.innerPath.split('/');
    var accumulated = '';
    for (final part in parts) {
      accumulated = accumulated.isEmpty ? part : '$accumulated/$part';
      crumbs.add(
        ArchiveBreadcrumb(
          label: part,
          virtualPath: build(
            archiveFile: location.archiveFile,
            innerPath: accumulated,
          ),
        ),
      );
    }
    return crumbs;
  }

  static String _normalizeInner(String innerPath) {
    return innerPath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .join('/');
  }
}
