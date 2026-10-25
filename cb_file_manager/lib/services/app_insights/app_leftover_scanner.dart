import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

import '../disk_cleaner/disk_tree_node.dart';
import 'app_insights_models.dart';
import 'app_leftover_finder.dart';
import 'posix_app_leftover_finder.dart';

/// Size and newest activity of one leftover folder.
class AppLeftoverMeasurement {
  final int sizeBytes;
  final int fileCount;

  /// The newest write or creation time of the folder itself or of any file
  /// or folder inside it, however deep.
  ///
  /// The folder's own time matters because it also moves when an entry is
  /// deleted or renamed, which leaves no newer file behind. Creation time
  /// matters because copied or extracted files keep their old write time.
  /// Last-access times are ignored: scanners, antivirus and the search
  /// indexer refresh them without the app running.
  final DateTime? lastModified;

  /// The entry behind [lastModified], relative to the folder. Null when the
  /// folder itself is the newest.
  final String? newestEntry;

  /// Every entry was visited. False when the entry budget ran out or a
  /// subfolder could not be read; [sizeBytes] is then a lower bound.
  final bool isComplete;

  const AppLeftoverMeasurement({
    required this.sizeBytes,
    required this.fileCount,
    this.lastModified,
    this.newestEntry,
    this.isComplete = true,
  });
}

/// Tracks the newest entry seen while walking one folder.
class _NewestActivity {
  int milliseconds = 0;
  String? _entryPath;

  void offer(int ms, String Function() entryPath) {
    if (ms <= milliseconds) return;
    milliseconds = ms;
    _entryPath = entryPath();
  }

  void offerRoot(int ms) {
    if (ms <= milliseconds) return;
    milliseconds = ms;
    _entryPath = null;
  }

  DateTime? get time => milliseconds <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

  String? relativeTo(String root, p.Context context) {
    final path = _entryPath;
    return path == null ? null : context.relative(path, from: root);
  }
}

/// Finds leftover folders without a full-disk scan.
///
/// Discovery only lists the app-data and program folders two levels deep,
/// which takes moments, and [measure] then walks each candidate on its own
/// isolate and streams one result per folder, so the list fills in while
/// the walk is still running.
class AppLeftoverScanner {
  static const int defaultMaxEntriesPerFolder = 500000;

  final int maxEntriesPerFolder;

  const AppLeftoverScanner({
    this.maxEntriesPerFolder = defaultMaxEntriesPerFolder,
  });

  /// Lists candidate folders for [operatingSystem] (defaults to the host).
  Future<AppLeftoverReport> discover({
    required AppLeftoverInventory inventory,
    required Map<String, String> environment,
    List<String> excludedPaths = const <String>[],
    String? operatingSystem,
  }) {
    final os = operatingSystem ?? Platform.operatingSystem;
    return Isolate.run(
      () => os == 'windows'
          ? discoverAppLeftoversSync(
              apps: inventory.apps,
              environment: environment,
              excludedPaths: excludedPaths,
              inventoryIsPartial: inventory.isPartial,
            )
          : discoverPosixAppLeftoversSync(
              inventory: inventory,
              environment: environment,
              excludedPaths: excludedPaths,
              operatingSystem: os,
            ),
    );
  }

  Future<AppLeftoverMeasureJob> measure(List<String> paths) {
    return AppLeftoverMeasureJob._start(paths, maxEntriesPerFolder);
  }
}

/// Builds a shallow tree of the base folders from the filesystem and runs
/// [AppLeftoverFinder] on it. Sizes are left at zero for [measure] to fill.
AppLeftoverReport discoverAppLeftoversSync({
  required List<InstalledAppInfo> apps,
  required Map<String, String> environment,
  List<String> excludedPaths = const <String>[],
  bool inventoryIsPartial = false,
  DateTime? generatedAt,
}) {
  final roots = <String, DiskTreeNode>{};
  final listed = Set<DiskTreeNode>.identity();

  DiskTreeNode ensure(String path) {
    final drive = '${path.substring(0, 2).toUpperCase()}\\';
    var node = roots.putIfAbsent(
      drive,
      () => DiskTreeNode(name: drive, fullPath: drive),
    );
    var current = drive;
    for (final segment in path.substring(3).split(r'\')) {
      if (segment.isEmpty) continue;
      current = current.endsWith(r'\')
          ? '$current$segment'
          : '$current\\$segment';
      DiskTreeNode? next;
      for (final child in node.children) {
        if (child.name.toUpperCase() == segment.toUpperCase()) {
          next = child;
          break;
        }
      }
      if (next == null) {
        next = DiskTreeNode(name: segment, fullPath: current);
        node.addChild(next);
      }
      node = next;
    }
    return node;
  }

  void fill(DiskTreeNode node, int levels) {
    if (levels <= 0) return;
    if (listed.add(node)) {
      final existing = {
        for (final child in node.children) child.name.toUpperCase(),
      };
      try {
        for (final entity in Directory(
          node.fullPath,
        ).listSync(followLinks: false)) {
          // Junctions such as `Application Data` are links, not folders.
          if (entity is! Directory) continue;
          final name = entity.path.substring(entity.path.lastIndexOf(r'\') + 1);
          if (existing.add(name.toUpperCase())) {
            node.addChild(DiskTreeNode(name: name, fullPath: entity.path));
          }
        }
      } on FileSystemException {
        // An unreadable folder simply contributes no candidates.
      }
    }
    for (final child in node.children) {
      fill(child, levels - 1);
    }
  }

  for (final base in AppLeftoverFinder.baseDirectories(environment)) {
    if (base.length < 3 || base[1] != ':') continue;
    fill(ensure(base), 2);
  }

  const finder = AppLeftoverFinder();
  final generated = generatedAt ?? DateTime.now();
  final reports = [
    for (final root in roots.values)
      finder.find(
        root: root,
        apps: apps,
        environment: environment,
        excludedPaths: excludedPaths,
        inventoryIsPartial: inventoryIsPartial,
        minimumBytes: 0,
        generatedAt: generated,
      ),
  ];
  return AppLeftoverReport(
    drivePath: roots.keys.isEmpty ? '' : roots.keys.first,
    candidates: [for (final report in reports) ...report.candidates],
    generatedAt: generated,
    isPartial: inventoryIsPartial,
    inventoryUnavailable:
        reports.isEmpty || reports.any((report) => report.inventoryUnavailable),
  );
}

/// Lists each macOS/Linux base folder one level deep and runs
/// [PosixAppLeftoverFinder] on the names.
AppLeftoverReport discoverPosixAppLeftoversSync({
  required AppLeftoverInventory inventory,
  required Map<String, String> environment,
  required String operatingSystem,
  List<String> excludedPaths = const <String>[],
  DateTime? generatedAt,
}) {
  final listing = <(PosixLeftoverBase, List<String>)>[];
  for (final base in PosixAppLeftoverFinder.bases(
    environment,
    operatingSystem: operatingSystem,
  )) {
    final names = <String>[];
    try {
      for (final entity in Directory(base.path).listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        names.add(p.basename(entity.path));
      }
    } on FileSystemException {
      // A missing base (no Flatpak, no Group Containers) has no candidates.
    }
    listing.add((base, names));
  }
  return const PosixAppLeftoverFinder().find(
    listing: listing,
    inventory: inventory,
    excludedPaths: excludedPaths,
    generatedAt: generatedAt,
  );
}

/// One background walk over a list of folders. Results arrive in order on
/// [results]; [cancel] kills the isolate at once.
class AppLeftoverMeasureJob {
  final Isolate _isolate;
  final ReceivePort _port;
  final StreamController<(String, AppLeftoverMeasurement)> _controller;

  AppLeftoverMeasureJob._(this._isolate, this._port, this._controller);

  Stream<(String, AppLeftoverMeasurement)> get results => _controller.stream;

  static Future<AppLeftoverMeasureJob> _start(
    List<String> paths,
    int maxEntries,
  ) async {
    final port = ReceivePort();
    final controller = StreamController<(String, AppLeftoverMeasurement)>();
    final isolate = await Isolate.spawn(
      _measureEntry,
      <Object>[port.sendPort, paths, maxEntries],
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    final job = AppLeftoverMeasureJob._(isolate, port, controller);
    port.listen((message) {
      if (message is (String, AppLeftoverMeasurement)) {
        controller.add(message);
        return;
      }
      // Done marker, exit notice or an uncaught error: the walk is over.
      job._close();
    });
    return job;
  }

  void cancel() {
    _isolate.kill(priority: Isolate.immediate);
    _close();
  }

  void _close() {
    _port.close();
    if (!_controller.isClosed) _controller.close();
  }
}

void _measureEntry(List<Object> args) {
  final port = args[0] as SendPort;
  final paths = args[1] as List<String>;
  final maxEntries = args[2] as int;
  for (final path in paths) {
    port.send((path, measureAppLeftoverSync(path, maxEntries)));
  }
  port.send(null);
}

AppLeftoverMeasurement measureAppLeftoverSync(String path, int maxEntries) {
  return Platform.isWindows
      ? _measureWindows(path, maxEntries)
      : _measureDart(path, maxEntries);
}

AppLeftoverMeasurement _measureWindows(String root, int maxEntries) {
  const directoryAttribute = 0x10;
  const reparsePointAttribute = 0x400;
  const windowsToUnixEpochTicks = 116444736000000000;

  int toMs(win32.FILETIME time) {
    final ticks =
        ((time.dwHighDateTime & 0xffffffff) << 32) |
        (time.dwLowDateTime & 0xffffffff);
    return (ticks - windowsToUnixEpochTicks) ~/ 10000;
  }

  var size = 0;
  var files = 0;
  var visited = 0;
  var complete = true;
  final newest = _NewestActivity();
  _offerRootTimes(root, newest);
  final findData = calloc<win32.WIN32_FIND_DATA>();
  final stack = <String>[root];

  AppLeftoverMeasurement result({required bool isComplete}) =>
      AppLeftoverMeasurement(
        sizeBytes: size,
        fileCount: files,
        lastModified: newest.time,
        newestEntry: newest.relativeTo(root, p.windows),
        isComplete: isComplete,
      );

  try {
    while (stack.isNotEmpty) {
      final directory = stack.removeLast();
      final searchPath = '$directory\\*'.toNativeUtf16();
      try {
        final handle = win32.FindFirstFile(
          win32.PCWSTR(searchPath),
          findData,
        ).value;
        if (!handle.isValid) {
          complete = false;
          continue;
        }
        try {
          do {
            final name = findData.ref.cFileName;
            if (name == '.' || name == '..') continue;
            final data = findData.ref;
            final written = toMs(data.ftLastWriteTime);
            final created = toMs(data.ftCreationTime);
            newest.offer(
              written > created ? written : created,
              () => '$directory\\$name',
            );
            final attributes = data.dwFileAttributes;
            if (attributes & directoryAttribute != 0) {
              if (attributes & reparsePointAttribute == 0) {
                stack.add('$directory\\$name');
              }
            } else {
              size += (data.nFileSizeHigh << 32) | data.nFileSizeLow;
              files++;
            }
            if (++visited >= maxEntries) return result(isComplete: false);
          } while (win32.FindNextFile(handle, findData).value);
        } finally {
          win32.FindClose(handle);
        }
      } catch (_) {
        complete = false;
      } finally {
        calloc.free(searchPath);
      }
    }
  } finally {
    calloc.free(findData);
  }
  return result(isComplete: complete);
}

/// The folder's own times: they move when an entry is deleted or renamed.
void _offerRootTimes(String root, _NewestActivity newest) {
  final stat = FileStat.statSync(root);
  if (stat.type == FileSystemEntityType.notFound) return;
  newest.offerRoot(stat.modified.millisecondsSinceEpoch);
  // `changed` is the creation time on Windows and the inode change time
  // elsewhere; both move when files are copied or extracted into the folder.
  newest.offerRoot(stat.changed.millisecondsSinceEpoch);
}

AppLeftoverMeasurement _measureDart(String root, int maxEntries) {
  var size = 0;
  var files = 0;
  var visited = 0;
  var complete = true;
  final newest = _NewestActivity();
  _offerRootTimes(root, newest);
  final stack = <Directory>[Directory(root)];

  AppLeftoverMeasurement result({required bool isComplete}) =>
      AppLeftoverMeasurement(
        sizeBytes: size,
        fileCount: files,
        lastModified: newest.time,
        newestEntry: newest.relativeTo(root, p.context),
        isComplete: isComplete,
      );

  while (stack.isNotEmpty) {
    final directory = stack.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = directory.listSync(followLinks: false);
    } on FileSystemException {
      complete = false;
      continue;
    }
    for (final entity in entries) {
      if (entity is Link) continue;
      try {
        final stat = entity.statSync();
        final modified = stat.modified.millisecondsSinceEpoch;
        final changed = stat.changed.millisecondsSinceEpoch;
        newest.offer(
          modified > changed ? modified : changed,
          () => entity.path,
        );
        if (entity is File) {
          size += stat.size;
          files++;
        }
      } on FileSystemException {
        complete = false;
      }
      if (entity is Directory) stack.add(entity);
      if (++visited >= maxEntries) return result(isComplete: false);
    }
  }
  return result(isComplete: complete);
}
