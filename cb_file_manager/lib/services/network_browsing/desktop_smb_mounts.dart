import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// An existing OS mount. Its URI omits the account used to mount it.
class DesktopSmbMount {
  const DesktopSmbMount._(this.uri, this.directory);

  final Uri uri;
  final String directory;

  static bool get isSupported => Platform.isMacOS || Platform.isLinux;

  static Future<List<DesktopSmbMount>> list() async {
    if (Platform.isMacOS) {
      try {
        final result = await Process.run('/sbin/mount', [
          '-t',
          'smbfs',
        ]).timeout(const Duration(seconds: 3));
        if (result.exitCode == 0) {
          return parseMacMounts(result.stdout as String);
        }
      } on ProcessException {
        return const [];
      } on TimeoutException {
        return const [];
      }
    }
    if (Platform.isLinux) {
      try {
        final table = await File('/proc/self/mountinfo').readAsString();
        final mounts = parseLinuxMounts(table);
        for (final entry in _linuxMountEntries(table)) {
          if (entry.type != 'fuse.gvfsd-fuse') continue;
          try {
            await for (final folder in Directory(
              entry.directory,
            ).list(followLinks: false)) {
              if (folder is! Directory) continue;
              final mount = parseGvfsDirectory(folder.path);
              if (mount != null) mounts.add(mount);
            }
          } on FileSystemException {
            // A GVfs session can exit or belong to a different user.
          }
        }
        return mounts;
      } on FileSystemException {
        return const [];
      }
    }
    return const [];
  }

  static List<DesktopSmbMount> parseMacMounts(String table) {
    final mounts = <DesktopSmbMount>[];
    for (final line in const LineSplitter().convert(table)) {
      final separator = line.indexOf(' on /');
      final type = line.lastIndexOf(' (smbfs');
      if (!line.startsWith('//') || separator < 0 || type <= separator + 4) {
        continue;
      }
      final uri = Uri.tryParse('smb:${line.substring(0, separator)}');
      if (uri == null || uri.host.isEmpty) continue;
      try {
        final mount = _mount(uri, line.substring(separator + 4, type));
        if (mount != null) mounts.add(mount);
      } on FormatException {
        // A malformed mount name must not invalidate the other volumes.
      }
    }
    return mounts;
  }

  static List<DesktopSmbMount> parseLinuxMounts(String table) {
    final mounts = <DesktopSmbMount>[];
    for (final entry in _linuxMountEntries(table)) {
      if (entry.type != 'cifs' && entry.type != 'smb3') continue;
      if (!entry.source.startsWith('//') || entry.root != '/') continue;
      // CIFS reports literal path components, unlike the URL printed by macOS.
      final parts = entry.source.substring(2).split('/');
      if (parts.length < 2) continue;
      final server = Uri.tryParse('smb://${parts.first}');
      if (server == null ||
          server.host.isEmpty ||
          server.userInfo.isNotEmpty ||
          server.hasQuery ||
          server.hasFragment) {
        continue;
      }
      final mount = _mount(
        server.replace(pathSegments: parts.skip(1)),
        entry.directory,
      );
      if (mount != null) mounts.add(mount);
    }
    return mounts;
  }

  static DesktopSmbMount? parseGvfsDirectory(String directory) {
    const prefix = 'smb-share:';
    final name = p.posix.basename(directory);
    if (!name.startsWith(prefix)) return null;
    final fields = <String, String>{};
    try {
      for (final field in name.substring(prefix.length).split(',')) {
        final separator = field.indexOf('=');
        if (separator < 1) return null;
        fields[field.substring(0, separator)] = Uri.decodeComponent(
          field.substring(separator + 1),
        );
      }
      final host = fields['server'];
      final share = fields['share'];
      final port = fields['port'] == null ? null : int.parse(fields['port']!);
      if (host == null || host.isEmpty || share == null || share.isEmpty) {
        return null;
      }
      if (port != null && (port < 1 || port > 65535)) return null;
      final root = (fields['prefix'] ?? '/')
          .split('/')
          .where((part) => part.isNotEmpty);
      return _mount(
        Uri(
          scheme: 'smb',
          host: host,
          port: port,
          pathSegments: [share, ...root],
        ),
        directory,
      );
    } on FormatException {
      return null;
    }
  }

  // A credential-free SMB URL may use a matching OS session. An explicit
  // login or an ambiguous mount needs to go through the normal SMB resolver.
  static String? pathFor(Uri source, Iterable<DesktopSmbMount> mounts) {
    if (source.scheme != 'smb' ||
        source.userInfo.isNotEmpty ||
        source.hasQuery ||
        source.hasFragment) {
      return null;
    }
    final List<String> segments;
    try {
      segments = source.pathSegments;
    } on FormatException {
      return null;
    }
    if (!segments.every(_validSegment)) return null;
    String? match;
    for (final mount in mounts) {
      if (mount.uri.host != source.host || _port(mount.uri) != _port(source)) {
        continue;
      }
      final root = mount.uri.pathSegments;
      if (segments.length <= root.length) continue;
      final matchesShare =
          root.first.toLowerCase() == segments.first.toLowerCase();
      if (!matchesShare ||
          !root.indexed.skip(1).every((part) => part.$2 == segments[part.$1])) {
        continue;
      }
      if (match != null) return null;
      match = p.posix.joinAll([mount.directory, ...segments.skip(root.length)]);
    }
    return match;
  }

  static Future<String?> resolveFile(Uri source) async {
    if (!isSupported || source.userInfo.isNotEmpty) return null;
    final mounts = await list();
    final path = pathFor(source, mounts);
    if (path == null) return null;
    try {
      final resolved = await File(
        path,
      ).resolveSymbolicLinks().timeout(const Duration(seconds: 3));
      // A symlink must not redirect an SMB URL outside its mounted directory.
      if (resolved != path) return null;
      return await File(resolved).exists().timeout(const Duration(seconds: 3))
          ? resolved
          : null;
    } on FileSystemException {
      return null;
    } on TimeoutException {
      return null;
    }
  }

  static DesktopSmbMount? _mount(Uri uri, String directory) {
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (!p.posix.isAbsolute(directory) ||
        directory.contains('\u0000') ||
        segments.isEmpty ||
        !segments.every(_validSegment)) {
      return null;
    }
    return DesktopSmbMount._(
      Uri(
        scheme: 'smb',
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        pathSegments: segments,
      ),
      directory,
    );
  }

  static bool _validSegment(String segment) =>
      segment.isNotEmpty &&
      segment != '.' &&
      segment != '..' &&
      !segment.contains('/') &&
      !segment.contains('\\') &&
      !segment.contains('\u0000');

  static int _port(Uri uri) => uri.hasPort ? uri.port : 445;
}

typedef _LinuxMountEntry = ({
  String type,
  String source,
  String directory,
  String root,
});

Iterable<_LinuxMountEntry> _linuxMountEntries(String table) sync* {
  final escaped = RegExp(r'\\([0-7]{3})');
  String decode(String value) => value.replaceAllMapped(
    escaped,
    (match) => String.fromCharCode(int.parse(match[1]!, radix: 8)),
  );

  for (final line in const LineSplitter().convert(table)) {
    final fields = line.split(' ');
    final separator = fields.indexOf('-');
    if (separator < 6 || fields.length < separator + 4) continue;
    yield (
      type: fields[separator + 1],
      source: decode(fields[separator + 2]),
      directory: decode(fields[4]),
      root: decode(fields[3]),
    );
  }
}
