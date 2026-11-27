import 'dart:io';

import 'package:cb_native/cb_native.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as win32;

import '../drive/windows_volume_probe.dart';
import 'app_leftover_finder.dart';
import 'app_leftover_scan_progress.dart';

/// Additional evidence of apps that do not appear in the uninstall registry.
/// Nothing found here becomes a cleanup candidate: runnable files only rule
/// out proposed candidates. No executable is opened or launched.
///
/// With [useNative] (and package:cb_native built) the large walks run on
/// Rust threads; the Dart walk stays as the fallback and gives the same
/// answer. Deep Scan then searches drives on different physical disks at the
/// same time, and reads a whole drive from its MFT when Windows allows it
/// (an elevated app). [groupByDisk] false treats every root as its own disk.
({List<AppLeftoverCandidate> candidates, bool isPartial})
verifyWindowsLeftoverPresence({
  required List<AppLeftoverCandidate> candidates,
  required Map<String, String> environment,
  required bool deepScan,
  List<String>? deepSearchRoots,
  int maxCandidateEntries = 10000,
  int maxDeepEntriesPerRoot = 5000000,
  void Function(AppLeftoverScanProgress progress)? onProgress,
  bool useNative = true,
  bool groupByDisk = true,
}) {
  var partial = false;
  final eligible = <AppLeftoverCandidate>[];
  // Even a normal scan must not offer an unregistered application directory
  // (for example a portable app in LocalAppData\Programs) for deletion.
  for (var i = 0; i < candidates.length; i++) {
    final candidate = candidates[i];
    final probe = _scanExecutables(
      root: candidate.path,
      maxEntries: maxCandidateEntries,
      onExecutable: (_) => true,
      // Deep Scan allows 500k entries per candidate; a normal scan's small
      // folders are listed faster in Dart than a native job starts.
      preferNative: useNative && deepScan,
      onDirectory: onProgress == null
          ? null
          : (directory, _) => onProgress(
              AppLeftoverScanProgress(
                stage: AppLeftoverScanStage.checkingCandidates,
                path: directory,
                done: i,
                total: candidates.length,
              ),
            ),
    );
    if (!probe.isComplete) partial = true;
    if (!probe.stopped && probe.isComplete) eligible.add(candidate);
  }
  if (!deepScan || eligible.isEmpty) {
    return (candidates: eligible, isPartial: partial);
  }

  // Index only names of candidate folders; executable paths are streamed
  // through this index and discarded instead of building a giant drive index.
  final index = _PresenceIndex(eligible);
  final env = <String, String>{
    for (final entry in environment.entries)
      entry.key.toUpperCase(): entry.value,
  };
  final volumes = deepSearchRoots ?? _fixedDriveRoots();
  if (volumes.isEmpty) partial = true;
  final systemPath = env['SYSTEMROOT'] ?? env['WINDIR'];
  final excludedSystemPath = systemPath == null ? null : _pathKey(systemPath);

  bool offer(String executable) {
    index.offer(executable);
    return index.allProtected;
  }

  // Check executable names on PATH first: they are strong evidence for
  // unregistered command-line tools and cheap to examine before a drive walk.
  final pathRoots = <String>{
    for (final raw in (env['PATH'] ?? '').split(';'))
      if (raw.trim().isNotEmpty) raw.trim().replaceAll('"', ''),
  };
  var pathIndex = 0;
  for (final root in pathRoots) {
    final position = pathIndex++;
    if (!volumes.any((volume) => _isWithin(root, volume))) continue;
    onProgress?.call(
      AppLeftoverScanProgress(
        stage: AppLeftoverScanStage.checkingPath,
        path: root,
        done: position,
        total: pathRoots.length,
      ),
    );
    final result = _scanExecutables(
      root: root,
      maxEntries: maxCandidateEntries,
      onExecutable: offer,
      recursive: false,
      missingIsComplete: true,
    );
    if (!result.isComplete) partial = true;
    if (result.stopped) break;
  }

  // Walk each fixed local volume once, including nonstandard application
  // locations and other drives. A budget is per-volume so a huge C: drive
  // cannot prevent checking D: or another fixed drive.
  final skipPathKeys = {?excludedSystemPath};
  var remaining = volumes;
  var finished = 0;
  var visitedBefore = 0;
  if (useNative && !index.allProtected) {
    final native = _searchVolumesNative(
      lanes: _diskLanes(volumes, groupByDisk: groupByDisk),
      totalVolumes: volumes.length,
      maxEntries: maxDeepEntriesPerRoot,
      offer: offer,
      skipPathKeys: skipPathKeys,
      onProgress: onProgress,
    );
    if (!native.isComplete) partial = true;
    remaining = native.fallback;
    finished = native.finished;
    visitedBefore = native.visited;
  }
  // The Dart walk: without the native library, and for any volume whose
  // native walk failed. One volume at a time.
  for (var v = 0; v < remaining.length; v++) {
    final root = remaining[v];
    if (index.allProtected) break;
    final done = finished + v;
    final result = _scanExecutables(
      root: root,
      maxEntries: maxDeepEntriesPerRoot,
      onExecutable: offer,
      onDirectory: onProgress == null
          ? null
          : (directory, visited) => onProgress(
              AppLeftoverScanProgress(
                stage: AppLeftoverScanStage.searchingDrive,
                path: directory,
                root: root,
                done: done,
                total: volumes.length,
                visited: visitedBefore + visited,
              ),
            ),
      skipNames: _systemDirectoryNames,
      skipPathKeys: skipPathKeys,
    );
    if (!result.isComplete) partial = true;
  }
  return (
    candidates: [
      for (final candidate in eligible)
        if (!index.protected.contains(candidate.path)) candidate,
    ],
    isPartial: partial,
  );
}

/// Volumes grouped so that each group is one set of physical disks: groups
/// are searched at the same time, the volumes of one group one after
/// another. Two partitions of one hard disk read together would only make
/// its heads seek between them. A volume whose disks are unknown gets a
/// group of its own; if the query fails altogether, everything stays in one
/// group, as before.
List<List<String>> _diskLanes(
  List<String> volumes, {
  required bool groupByDisk,
}) {
  if (!groupByDisk) {
    return [
      for (final volume in volumes) [volume],
    ];
  }
  final info = NativeFs.volumeDisks(volumes);
  if (info == null || info.length != volumes.length) return [volumes];
  final lanes = <({Set<int> disks, List<String> volumes})>[];
  for (var i = 0; i < volumes.length; i++) {
    final disks = info[i].disks.toSet();
    final merged = (disks: disks, volumes: <String>[volumes[i]]);
    if (disks.isNotEmpty) {
      // A volume spanning several disks joins every group it touches.
      for (final lane in lanes.toList()) {
        if (lane.disks.intersection(disks).isEmpty) continue;
        lanes.remove(lane);
        merged.disks.addAll(lane.disks);
        merged.volumes.insertAll(0, lane.volumes);
      }
    }
    lanes.add(merged);
  }
  // Keep the drive order within a group and across groups.
  for (final lane in lanes) {
    lane.volumes.sort((a, b) => volumes.indexOf(a) - volumes.indexOf(b));
  }
  lanes.sort(
    (a, b) =>
        volumes.indexOf(a.volumes.first) - volumes.indexOf(b.volumes.first),
  );
  return [for (final lane in lanes) lane.volumes];
}

bool _isVolumeRoot(String root) => RegExp(r'^[A-Za-z]:[\\/]?$').hasMatch(root);

class _Lane {
  _Lane(this.volumes);

  final List<String> volumes;
  int next = 0;
  String? root;
  NativeExecutableWalk? walk;
  bool fromMft = false;
}

/// Searches [lanes] at the same time on Rust threads, polled from this
/// synchronous isolate. Each drive is read from its MFT when the process may
/// open the volume, otherwise walked folder by folder. Volumes the native
/// library could not search are returned in [fallback] for the Dart walk.
/// Stops everything as soon as [offer] says every candidate is protected;
/// drives cut short that way do not make the result partial, as drives the
/// sequential search never started did not.
({bool isComplete, List<String> fallback, int finished, int visited})
_searchVolumesNative({
  required List<List<String>> lanes,
  required int totalVolumes,
  required int maxEntries,
  required bool Function(String path) offer,
  required Set<String> skipPathKeys,
  void Function(AppLeftoverScanProgress progress)? onProgress,
}) {
  var complete = true;
  final fallback = <String>[];
  var finished = 0;
  var visitedDone = 0;

  NativeExecutableWalk? walkFolders(String root) =>
      NativeFs.startExecutableWalk(
        root: root,
        extensions: _launchableExtensions,
        maxEntries: maxEntries,
        skipNames: _systemDirectoryNames,
        skipPaths: skipPathKeys,
      );

  bool startNext(_Lane lane) {
    lane
      ..walk = null
      ..root = null;
    while (lane.next < lane.volumes.length) {
      final root = lane.volumes[lane.next++];
      var walk = _isVolumeRoot(root)
          ? NativeFs.startMftExecutables(
              root: root,
              extensions: _launchableExtensions,
              skipNames: _systemDirectoryNames,
              skipPaths: skipPathKeys,
            )
          : null;
      lane.fromMft = walk != null;
      walk ??= walkFolders(root);
      if (walk != null) {
        lane
          ..walk = walk
          ..root = root;
        return true;
      }
      fallback.add(root);
    }
    return false;
  }

  final all = [for (final volumes in lanes) _Lane(volumes)];
  final active = all.where(startNext).toList();
  var turn = 0;

  void report() {
    if (onProgress == null || active.isEmpty) return;
    // The drive set only changes when a drive finishes, so the throttle
    // keeps passing ticks at its usual rate; the path rotates through the
    // drives being read.
    final shown = active[turn++ % active.length];
    var visited = visitedDone;
    var path = shown.root!;
    for (final lane in active) {
      final progress = lane.walk!.progress();
      visited += progress.visited;
      if (identical(lane, shown) && progress.currentPath.isNotEmpty) {
        path = progress.currentPath;
      }
    }
    onProgress(
      AppLeftoverScanProgress(
        stage: AppLeftoverScanStage.searchingDrive,
        path: path,
        root: [for (final lane in active) lane.root!].join(', '),
        done: finished,
        total: totalVolumes,
        visited: visited,
      ),
    );
  }

  // Before the first poll: a small root can finish within it, and the
  // status line must still show the stage.
  report();
  var pause = 0;
  try {
    while (active.isNotEmpty) {
      var changed = false;
      for (final lane in active.toList()) {
        final walk = lane.walk!;
        // Read [ended] after poll: the poll that ends a walk carries its
        // last matches.
        for (final path in walk.poll()) {
          if (_looksRunnable(p.windows.basename(path)) && offer(path)) {
            return (
              isComplete: complete,
              fallback: const <String>[],
              finished: finished,
              visited: visitedDone,
            );
          }
        }
        if (!walk.ended) continue;
        changed = true;
        final progress = walk.progress();
        final root = lane.root!;
        walk.dispose();
        lane.walk = null;
        if (walk.failed && lane.fromMft) {
          // Usually "access denied": not elevated. Walk the folders.
          lane.fromMft = false;
          final folders = walkFolders(root);
          if (folders != null) {
            lane.walk = folders;
            continue;
          }
          fallback.add(root);
        } else if (walk.failed) {
          fallback.add(root);
        } else {
          if (progress.incomplete > 0) complete = false;
          finished++;
          visitedDone += progress.visited;
        }
        if (!startNext(lane)) active.remove(lane);
      }
      report();
      // 0, 1, 2, 4 ... 16 ms while nothing finishes.
      pause = changed ? 0 : (pause == 0 ? 1 : (pause * 2).clamp(1, 16).toInt());
      if (pause > 0) sleep(Duration(milliseconds: pause));
    }
  } finally {
    for (final lane in all) {
      lane.walk
        ?..cancel()
        ..dispose();
    }
  }
  return (
    isComplete: complete,
    fallback: fallback,
    finished: finished,
    visited: visitedDone,
  );
}

List<String> _fixedDriveRoots() {
  if (!Platform.isWindows) return const <String>[];
  try {
    final mask = win32.GetLogicalDrives().value;
    final roots = <String>[];
    for (var i = 0; i < 26; i++) {
      if (mask & (1 << i) == 0) continue;
      final root = '${String.fromCharCode(65 + i)}:\\';
      if (windowsDriveType(root) == win32.DRIVE_FIXED) roots.add(root);
    }
    return roots;
  } catch (_) {
    return const <String>[];
  }
}

String _pathKey(String path) => p.windows.normalize(path).toUpperCase();

bool _isWithin(String path, String root) {
  final child = _pathKey(path);
  final parent = _pathKey(root);
  return child == parent || p.windows.isWithin(parent, child);
}

const _systemDirectoryNames = <String>{
  r'$RECYCLE.BIN',
  'SYSTEM VOLUME INFORMATION',
  r'$WINDOWS.~BT',
  r'$WINDOWS.~WS',
  r'$WINREAGENT',
  'WINDOWS.OLD',
};

bool _looksRunnable(String filename) {
  final extension = p.windows.extension(filename).toLowerCase();
  if (!_launchableExtensions.contains(extension)) return false;
  final stem = p.windows.basenameWithoutExtension(filename).toLowerCase();
  if (_helperNames.contains(stem)) return false;
  return !_installerName.hasMatch(stem);
}

const _launchableExtensions = <String>{'.exe', '.com', '.cmd', '.bat'};

const _helperNames = <String>{
  'setup',
  'install',
  'installer',
  'uninstall',
  'uninstaller',
  'update',
  'updater',
  'crashpad_handler',
  'crashreporter',
  'maintenancetool',
  'repair',
};

final _installerName = RegExp(
  r'^(?:unins\d+|uninstall(?:er)?(?:[-_. ]|\d).*)$|'
  r'(?:[-_. ](?:setup|installer|uninstaller|uninstall)(?:[-_. ].*)?)$',
);

bool _isReparseDirectory(String path) {
  if (!Platform.isWindows) return false;
  final ptr = path.toNativeUtf16();
  try {
    final attributes = win32.GetFileAttributes(win32.PCWSTR(ptr)).value;
    return attributes != 0xffffffff && attributes & 0x400 != 0;
  } finally {
    calloc.free(ptr);
  }
}

/// Enumerate names, not file content. The caller may stop when it has enough
/// evidence. Missing PATH roots are normal (stale entries), while a candidate
/// or volume that cannot be checked is unknown and cannot prove absence.
///
/// Folders whose upper-cased name is in [skipNames] or whose [_pathKey] is in
/// [skipPathKeys] are not entered. [preferNative] runs the walk on Rust
/// threads when package:cb_native is built; the Dart walk below is the
/// fallback, including for a native walk that failed part-way.
({bool stopped, bool isComplete}) _scanExecutables({
  required String root,
  required int maxEntries,
  required bool Function(String path) onExecutable,
  bool recursive = true,
  bool missingIsComplete = false,
  Set<String> skipNames = const <String>{},
  Set<String> skipPathKeys = const <String>{},
  void Function(String directory, int visited)? onDirectory,
  bool preferNative = false,
}) {
  // A missing root is complete for PATH only; the native walk reports any
  // unreadable folder as incomplete, so it is not used there.
  if (preferNative && !missingIsComplete) {
    final native = _scanExecutablesNative(
      root: root,
      maxEntries: maxEntries,
      onExecutable: onExecutable,
      recursive: recursive,
      skipNames: skipNames,
      skipPathKeys: skipPathKeys,
      onDirectory: onDirectory,
    );
    if (native != null) return native;
  }
  bool skipDirectory(String path) {
    if (skipNames.isEmpty && skipPathKeys.isEmpty) return false;
    final key = _pathKey(path);
    return skipPathKeys.contains(key) ||
        skipNames.contains(p.windows.basename(key));
  }

  var visited = 0;
  var complete = true;
  final stack = <Directory>[Directory(root)];
  while (stack.isNotEmpty) {
    final directory = stack.removeLast();
    onDirectory?.call(directory.path, visited);
    try {
      if (_isReparseDirectory(directory.path)) {
        complete = false;
        continue;
      }
      for (final entry in directory.listSync(followLinks: false)) {
        if (++visited > maxEntries) {
          return (stopped: false, isComplete: false);
        }
        if (entry is Directory) {
          if (recursive && !skipDirectory(entry.path)) {
            stack.add(entry);
          }
        } else if (entry is File) {
          if (_looksRunnable(p.windows.basename(entry.path)) &&
              onExecutable(entry.path)) {
            return (stopped: true, isComplete: complete);
          }
        } else if (entry is Link) {
          // Don't follow a junction or dangling executable link to an
          // unknown volume. It is not evidence of a live executable.
          complete = false;
        }
      }
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (!missingIsComplete || (code != 2 && code != 3)) {
        complete = false;
      }
    }
  }
  return (stopped: false, isComplete: complete);
}

/// [_scanExecutables] on Rust threads, driven synchronously: the discovery
/// isolate runs plain synchronous code, so it polls and sleeps briefly
/// instead of awaiting. Null when the library is unavailable or the walk
/// failed, so the caller runs the Dart walk.
({bool stopped, bool isComplete})? _scanExecutablesNative({
  required String root,
  required int maxEntries,
  required bool Function(String path) onExecutable,
  required bool recursive,
  required Set<String> skipNames,
  required Set<String> skipPathKeys,
  void Function(String directory, int visited)? onDirectory,
}) {
  final walk = NativeFs.startExecutableWalk(
    root: root,
    extensions: _launchableExtensions,
    recursive: recursive,
    maxEntries: maxEntries,
    skipNames: skipNames,
    skipPaths: skipPathKeys,
  );
  if (walk == null) return null;
  // Like the Dart walk, report the root before reading it: a small folder
  // finishes before the first poll, and the status line must still show
  // the stage (checking candidates, searching drive X).
  onDirectory?.call(root, 0);
  try {
    var pause = 0;
    while (true) {
      // Read [ended] after poll: the poll that ends the walk carries the
      // last matches.
      for (final path in walk.poll()) {
        if (_looksRunnable(p.windows.basename(path)) && onExecutable(path)) {
          walk.cancel();
          return (stopped: true, isComplete: walk.progress().incomplete == 0);
        }
      }
      final progress = walk.progress();
      if (walk.ended) {
        if (walk.failed) return null;
        return (stopped: false, isComplete: progress.incomplete == 0);
      }
      if (progress.currentPath.isNotEmpty) {
        onDirectory?.call(progress.currentPath, progress.visited);
      }
      // 0, 1, 2, 4 ... 16 ms: small folders finish within the first polls.
      if (pause > 0) sleep(Duration(milliseconds: pause));
      pause = pause == 0 ? 1 : (pause * 2).clamp(1, 16).toInt();
    }
  } finally {
    walk.dispose();
  }
}

String _nameKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[\s._()\-]+'), '');

final _portableSuffix = RegExp(
  r'(?:[ ._(-]*(?:portable|standalone|x64|x86|amd64|arm64|win64|win32|'
  r'64[- ]?bit|32[- ]?bit|64|32)[ )]*)+$',
  caseSensitive: false,
);

final _versionSuffix = RegExp(
  r'(?:[ ._-]v?\d+(?:[._-]\d+)*|v\d+(?:[._-]\d+)+)$',
  caseSensitive: false,
);

Set<String> _nameAliases(String name) {
  final keys = <String>{_nameKey(name)};
  // Suffixes can be stacked, e.g. Example-v2.1-win64-portable.
  var current = name;
  while (true) {
    final next = current
        .replaceFirst(_portableSuffix, '')
        .replaceFirst(_versionSuffix, '');
    if (next == current) break;
    keys.add(_nameKey(next));
    current = next;
  }
  // Electron and some other apps use reverse-DNS data directory names.
  final segments = current.split('.');
  if (segments.length >= 3 &&
      _reverseDnsPrefixes.contains(segments.first.toLowerCase()) &&
      _nameKey(segments.last).length >= 4) {
    keys.add(_nameKey(segments.last));
  }
  return keys..removeWhere((key) => key.length < 3);
}

const _reverseDnsPrefixes = <String>{
  'com',
  'net',
  'org',
  'io',
  'app',
  'dev',
  'co',
  'ai',
};

final _versionedName = RegExp(
  r'^(.*?)(?:[ ._-]*v)?(\d+(?:[._-]\d+)+)$',
  caseSensitive: false,
);

({String product, List<int> version})? _versionIdentity(String name) {
  final match =
      _versionedName.firstMatch(name) ??
      _versionedName.firstMatch(name.replaceFirst(_portableSuffix, ''));
  if (match == null) return null;
  final product = _nameKey(match.group(1)!);
  if (product.length < 3) return null;
  final version = match
      .group(2)!
      .split(RegExp(r'[._-]'))
      .map(int.tryParse)
      .toList();
  if (version.any((part) => part == null)) return null;
  return (product: product, version: version.cast<int>());
}

class _PresenceIndex {
  final _exact = <String, Set<String>>{};
  final _flexible = <String, Set<String>>{};
  final _versioned = <String, List<(List<int>, String)>>{};
  final protected = <String>{};
  final int _candidateCount;

  _PresenceIndex(List<AppLeftoverCandidate> candidates)
    : _candidateCount = candidates.length {
    for (final candidate in candidates) {
      final name = p.windows.basename(candidate.path);
      if (candidate.reason == AppLeftoverReason.olderVersion) {
        // A current executable must not hide an unrelated older version.
        _add(_exact, _nameKey(name), candidate.path);
        final identity = _versionIdentity(name);
        if (identity != null) {
          _versioned.putIfAbsent(identity.product, () => []).add((
            identity.version,
            candidate.path,
          ));
        }
      } else {
        for (final key in _nameAliases(name)) {
          _add(_flexible, key, candidate.path);
        }
      }
    }
  }

  static void _add(Map<String, Set<String>> index, String key, String path) {
    if (key.length >= 3) index.putIfAbsent(key, () => <String>{}).add(path);
  }

  bool get allProtected => protected.length == _candidateCount;

  void offer(String executable) {
    final parts = p.windows.split(executable);
    // The executable basename finds a portable app stored in a renamed
    // directory. Ancestor names cover launchers with generic executable names.
    for (var i = 1; i < parts.length; i++) {
      final name = i == parts.length - 1
          ? p.windows.basenameWithoutExtension(parts[i])
          : parts[i];
      final exact = _exact[_nameKey(name)];
      if (exact != null) protected.addAll(exact);
      final identity = _versionIdentity(name);
      if (identity != null) {
        // An existing 2021.3.1 patch still owns a 2021.3 data folder; a
        // 2024.1 executable does not. Compare complete numeric segments.
        for (final (version, candidate)
            in _versioned[identity.product] ?? const <(List<int>, String)>[]) {
          if (version.length > identity.version.length) continue;
          var same = true;
          for (var i = 0; i < version.length; i++) {
            if (version[i] != identity.version[i]) {
              same = false;
              break;
            }
          }
          if (same) protected.add(candidate);
        }
      }
      for (final alias in _nameAliases(name)) {
        final matches = _flexible[alias];
        if (matches != null) protected.addAll(matches);
      }
    }
  }
}
