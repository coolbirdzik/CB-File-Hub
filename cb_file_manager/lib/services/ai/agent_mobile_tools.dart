import 'dart:async';
import 'dart:io';

import 'package:cb_native/cb_native.dart';
import 'package:flutter/widgets.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../drive/drive_info.dart';
import '../drive/drive_inventory_service.dart';
import 'agent_file_tools.dart';
import 'agent_workspace.dart';

/// A storage volume as the mobile agent reports it.
class AgentStorageVolume {
  final String path;
  final String name;
  final String kind;
  final int totalBytes;
  final int freeBytes;

  const AgentStorageVolume({
    required this.path,
    required this.name,
    required this.kind,
    this.totalBytes = 0,
    this.freeBytes = 0,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'kind': kind,
    'type': 'directory',
    if (totalBytes > 0) ...{
      'total_bytes': totalBytes,
      'free_bytes': freeBytes,
      'used_bytes': totalBytes - freeBytes,
    },
  };
}

/// Tools the phone apps offer in place of a shell: Android and iOS cannot run
/// one for the agent, so what it would be used for (`df`, `du`, `find -size`,
/// `find -mtime`, opening and sending files) is done here directly.
class AgentMobileTools {
  static const names = {
    'list_storage',
    'folder_size',
    'find_large_files',
    'find_recent_files',
    'open_file',
    'share_files',
  };

  /// Folders worth naming to the agent when they exist on a volume.
  static const standardFolders = [
    'DCIM',
    'Pictures',
    'Download',
    'Documents',
    'Movies',
    'Music',
    'Recordings',
  ];

  static const _maxScanEntries = 100000;
  static const _scanTime = Duration(seconds: 30);

  final AgentFileTools _fileTools;
  final Future<List<AgentStorageVolume>> Function() _volumes;
  final Future<String?> Function(String path) _open;
  final Future<String?> Function(List<String> paths) _share;

  /// [volumes], [open] and [share] replace the platform calls in tests. The
  /// latter two return an error message, or null on success.
  AgentMobileTools(
    this._fileTools, {
    Future<List<AgentStorageVolume>> Function()? volumes,
    Future<String?> Function(String path)? open,
    Future<String?> Function(List<String> paths)? share,
  }) : _volumes = volumes ?? _deviceVolumes,
       _open = open ?? _openWithSystem,
       _share = share ?? _shareWithSystem;

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args, {
    required bool Function() isCancelled,
  }) async {
    void check() {
      if (isCancelled()) throw StateError('Operation stopped by user.');
    }

    check();
    if (args['cursor'] != null) return _fileTools.page(name, args, null);
    switch (name) {
      case 'list_storage':
        return _listStorage();
      case 'folder_size':
        return _folderSize(args['path'] as String, check);
      case 'find_large_files':
        final minBytes = (args['min_size_mb'] as int? ?? 0) * 1024 * 1024;
        return _findFiles(
          name,
          args,
          check,
          include: (stat) => stat.size >= minBytes,
          compare: (a, b) =>
              (b['size_bytes'] as int).compareTo(a['size_bytes'] as int),
        );
      case 'find_recent_files':
        final since = DateTime.now().subtract(
          Duration(days: args['days'] as int? ?? 7),
        );
        return _findFiles(
          name,
          args,
          check,
          include: (stat) => stat.modified.isAfter(since),
          compare: (a, b) =>
              (b['modified'] as String).compareTo(a['modified'] as String),
        );
      case 'open_file':
        final path = args['path'] as String;
        if (await FileSystemEntity.type(path) != FileSystemEntityType.file) {
          throw FileSystemException('File not found', path);
        }
        final error = await _open(path);
        if (error != null) throw StateError(error);
        return {'ok': true, 'opened': path};
      case 'share_files':
        final paths = (args['paths'] as List).cast<String>();
        final missing = [
          for (final path in paths)
            if (await FileSystemEntity.type(path) != FileSystemEntityType.file)
              path,
        ];
        if (missing.isNotEmpty) {
          throw ArgumentError(
            'Only existing files can be shared. Not files: ${missing.join(', ')}',
          );
        }
        final error = await _share(paths);
        if (error != null) throw StateError(error);
        return {
          'ok': true,
          'shared': paths,
          'note': 'The share sheet is open; the user chooses where to send.',
        };
    }
    throw ArgumentError('Unknown mobile tool "$name".');
  }

  /// Storage roots for `list_directory` with an empty path.
  Future<List<Map<String, dynamic>>> storageRoots() async => [
    for (final volume in await _volumes()) volume.toJson(),
  ];

  Future<Map<String, dynamic>> _listStorage() async {
    final volumes = await _volumes();
    return {
      'ok': true,
      'volumes': [
        for (final volume in volumes)
          {
            ...volume.toJson(),
            'folders': [
              for (final folder in standardFolders)
                if (await Directory(p.join(volume.path, folder)).exists())
                  p.join(volume.path, folder),
            ],
          },
      ],
      if (Platform.isIOS)
        'note':
            'iOS only lets CB File Hub read its own Documents folder and '
            'folders the user opened in the app.',
    };
  }

  Future<Map<String, dynamic>> _folderSize(
    String path,
    void Function() check,
  ) async {
    if (!await Directory(path).exists()) {
      throw FileSystemException('Directory not found', path);
    }
    final deadline = DateTime.now().add(_scanTime);
    final children = <Map<String, dynamic>>[];
    final warnings = <String>[];
    var bytes = 0, files = 0, folders = 0;
    var complete = true;
    await for (final entity
        in Directory(path).list(followLinks: false).handleError((Object error) {
          if (_appPrivate(error)) return;
          complete = false;
          if (warnings.length < 5) warnings.add(error.toString());
        })) {
      check();
      if (entity is File) {
        final size = (await entity.stat()).size;
        bytes += size;
        files++;
        children.add({'path': entity.path, 'type': 'file', 'size_bytes': size});
      } else if (entity is Directory) {
        final size = await _directorySize(entity.path, check, deadline);
        bytes += size.bytes;
        files += size.files;
        folders += size.folders + 1;
        complete &= size.complete;
        children.add({
          'path': entity.path,
          'type': 'directory',
          'size_bytes': size.bytes,
          'files': size.files,
        });
      }
    }
    children.sort(
      (a, b) => (b['size_bytes'] as int).compareTo(a['size_bytes'] as int),
    );
    return {
      'ok': true,
      'path': path,
      'size_bytes': bytes,
      'files': files,
      'folders': folders,
      'largest_children': children.take(15).toList(),
      'scope_complete': complete,
      if (!complete)
        'warnings': [
          ...warnings,
          'Some folders could not be read or the scan hit its time limit; '
              'the real size can be larger.',
        ],
    };
  }

  static bool _appPrivate(Object error) =>
      error is FileSystemException && AgentWorkspace.isAppPrivate(error.path);

  /// Native walk when cb_native is built, else a bounded Dart walk.
  Future<_Size> _directorySize(
    String path,
    void Function() check,
    DateTime deadline,
  ) async {
    // The native walk counts Android/data and Android/obb as unreadable; the
    // Dart walk below skips them quietly, as everywhere else.
    if (!AgentWorkspace.isAppPrivate(p.join(path, 'data'))) {
      Object? stopped;
      try {
        final native = await NativeFs.directorySize(
          directories: [path],
          shouldContinue: () {
            try {
              check();
            } catch (e) {
              stopped = e;
              return false;
            }
            return DateTime.now().isBefore(deadline);
          },
        );
        if (stopped != null) throw stopped!;
        if (native != null) {
          return _Size(
            native.bytes,
            native.files,
            native.directories,
            complete: native.unreadable == 0,
          );
        }
      } on NativeJobException {
        // The Dart walk below reports what it can read.
      }
    }
    var bytes = 0, files = 0, folders = 0;
    var complete = true;
    await for (final entity
        in Directory(
          path,
        ).list(recursive: true, followLinks: false).handleError((Object error) {
          if (!_appPrivate(error)) complete = false;
        })) {
      check();
      if (DateTime.now().isAfter(deadline)) {
        complete = false;
        break;
      }
      if (entity is File) {
        try {
          bytes += (await entity.stat()).size;
          files++;
        } on FileSystemException {
          complete = false;
        }
      } else if (entity is Directory) {
        folders++;
      }
    }
    return _Size(bytes, files, folders, complete: complete);
  }

  Future<Map<String, dynamic>> _findFiles(
    String name,
    Map<String, dynamic> args,
    void Function() check, {
    required bool Function(FileStat stat) include,
    required int Function(Map<String, dynamic> a, Map<String, dynamic> b)
    compare,
  }) async {
    final path = args['path'] as String;
    if (!await Directory(path).exists()) {
      throw FileSystemException('Directory not found', path);
    }
    final ext = (args['extension'] as String? ?? '').toLowerCase();
    final suffix = ext.isEmpty || ext.startsWith('.') ? ext : '.$ext';
    final deadline = DateTime.now().add(_scanTime);
    final results = <Map<String, dynamic>>[];
    final warnings = <String>[];
    var visited = 0;
    var complete = true;
    await for (final entity
        in Directory(
          path,
        ).list(recursive: true, followLinks: false).handleError((Object error) {
          if (_appPrivate(error)) return;
          complete = false;
          if (warnings.length < 5) warnings.add(error.toString());
        })) {
      check();
      if (++visited > _maxScanEntries || DateTime.now().isAfter(deadline)) {
        complete = false;
        warnings.add(
          'Scan bounds reached. Narrow the folder for remaining results.',
        );
        break;
      }
      if (entity is! File) continue;
      if (suffix.isNotEmpty && !entity.path.toLowerCase().endsWith(suffix)) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (!include(stat)) continue;
        results.add({
          'path': entity.path,
          'name': p.basename(entity.path),
          'size_bytes': stat.size,
          'modified': stat.modified.toIso8601String(),
        });
      } on FileSystemException {
        complete = false;
      }
    }
    results.sort(compare);
    return _fileTools.page(
      name,
      args,
      results.take(500).toList(),
      complete: complete,
      warnings: warnings,
    );
  }

  static Future<List<AgentStorageVolume>> _deviceVolumes() async {
    final drives = await DriveInventoryService.load();
    return [
      for (final drive in drives)
        AgentStorageVolume(
          path: drive.path,
          name: drive.displayName,
          kind: switch (drive.kind) {
            DriveKind.internal => 'internal',
            DriveKind.removable => 'removable',
            DriveKind.network => 'network',
            _ => drive.isPrimary ? 'internal' : 'other',
          },
          totalBytes: drive.space.totalBytes,
          freeBytes: drive.space.freeBytes,
        ),
    ];
  }

  static Future<String?> _openWithSystem(String path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done ? null : result.message;
  }

  static Future<String?> _shareWithSystem(List<String> paths) async {
    // iPad anchors the share popover; a phone ignores it.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    await SharePlus.instance.share(
      ShareParams(
        files: [for (final path in paths) XFile(path)],
        sharePositionOrigin: Rect.fromLTWH(
          size.width / 2,
          size.height - 1,
          1,
          1,
        ),
      ),
    );
    return null;
  }
}

class _Size {
  final int bytes;
  final int files;
  final int folders;
  final bool complete;
  const _Size(this.bytes, this.files, this.folders, {required this.complete});
}
