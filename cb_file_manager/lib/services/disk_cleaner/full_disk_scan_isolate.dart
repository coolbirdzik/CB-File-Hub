import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

import 'disk_tree_node.dart';

/// Spawns an isolate that recursively scans [drivePath] and builds a
/// [DiskTreeNode] tree with sizes for every directory.
///
/// Uses Win32 FindFirstFileW/FindNextFileW for maximum speed — each directory
/// entry returns name + size + attributes in a single syscall, eliminating the
/// need for separate stat() calls. ~5-10x faster than Dart's listSync+statSync.
Future<FullDiskScanHandle> spawnFullDiskScan({
  required String drivePath,
  int maxDepth = 20,
}) async {
  final receivePort = ReceivePort();
  final args = _FullScanArgs(
    sendPort: receivePort.sendPort,
    drivePath: drivePath,
    maxDepth: maxDepth,
  );

  final isolate = await Isolate.spawn(_fullDiskScanWorker, args);
  final handle = FullDiskScanHandle._(
    isolate: isolate,
    receivePort: receivePort,
    drivePath: drivePath,
  );

  receivePort.listen((dynamic msg) {
    if (handle._cancelled) return;
    if (msg is _ProgressMsg) {
      if (!handle._progress.isClosed) {
        handle._progress.add(FullDiskScanProgress(
          directoriesScanned: msg.dirs,
          filesScanned: msg.files,
          bytesScanned: msg.bytes,
          currentPath: msg.currentPath,
        ));
      }
    } else if (msg is _TreeMsg) {
      if (!handle._treeSnapshots.isClosed) {
        handle._treeSnapshots.add(msg.root);
      }
    } else if (msg is _DoneMsg) {
      receivePort.close();
      if (!handle._progress.isClosed) handle._progress.close();
      if (!handle._treeSnapshots.isClosed) handle._treeSnapshots.close();
      if (!handle._done.isCompleted) {
        handle._done.complete(FullDiskScanResult(
          root: msg.root,
          duration: DateTime.now().difference(handle._startedAt),
          inaccessible: msg.inaccessible,
        ));
      }
    }
  });

  return handle;
}

/// Handle for an in-flight full disk scan.
class FullDiskScanHandle {
  final Isolate _isolate;
  final ReceivePort _receivePort;
  final String drivePath;
  final StreamController<FullDiskScanProgress> _progress =
      StreamController<FullDiskScanProgress>.broadcast();
  final StreamController<DiskTreeNode> _treeSnapshots =
      StreamController<DiskTreeNode>.broadcast();
  final Completer<FullDiskScanResult> _done = Completer<FullDiskScanResult>();
  final DateTime _startedAt = DateTime.now();
  bool _cancelled = false;

  FullDiskScanHandle._({
    required Isolate isolate,
    required ReceivePort receivePort,
    required this.drivePath,
  })  : _isolate = isolate,
        _receivePort = receivePort;

  Stream<FullDiskScanProgress> get progress => _progress.stream;
  Stream<DiskTreeNode> get treeSnapshots => _treeSnapshots.stream;
  Future<FullDiskScanResult> get future => _done.future;
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    try {
      _isolate.kill(priority: Isolate.immediate);
    } catch (_) {}
    _receivePort.close();
    if (!_progress.isClosed) _progress.close();
    if (!_treeSnapshots.isClosed) _treeSnapshots.close();
    if (!_done.isCompleted) {
      _done.complete(FullDiskScanResult(
        root: DiskTreeNode(name: drivePath, fullPath: drivePath),
        duration: DateTime.now().difference(_startedAt),
        inaccessible: const ['cancelled'],
      ));
    }
  }
}

// ---------------------------------------------------------------------------
// Isolate worker — Win32 FindFirstFileW/FindNextFileW for fast scanning
// ---------------------------------------------------------------------------

/// FILE_ATTRIBUTE_DIRECTORY constant.
const int _fileAttributeDirectory = 0x10;

/// FILE_ATTRIBUTE_REPARSE_POINT — junctions, symlinks.
const int _fileAttributeReparsePoint = 0x400;

/// INVALID_HANDLE_VALUE.
const int _invalidHandleValue = -1;

void _fullDiskScanWorker(_FullScanArgs args) {
  final sendPort = args.sendPort;
  final inaccessible = <String>[];
  int totalDirs = 0;
  int totalFiles = 0;
  int totalBytes = 0;
  DateTime lastFlush = DateTime.now();
  DateTime lastTreeFlush = DateTime.now();
  DiskTreeNode? rootSnapshot;

  DiskTreeNode clonePreviewTree(
    DiskTreeNode node, {
    int depth = 0,
    int maxDepth = 3,
    int maxChildrenPerNode = 40,
  }) {
    final clone = DiskTreeNode(
      name: node.name,
      fullPath: node.fullPath,
      isFile: node.isFile,
      sizeBytes: node.sizeBytes,
      fileCount: node.fileCount,
      junkCategoryId: node.junkCategoryId,
      isExpanded: node.isExpanded,
    );
    if (depth >= maxDepth || node.children.isEmpty) return clone;

    // Keep insertion order during preview to avoid repeated O(n log n)
    // sorting on every snapshot flush.
    final children = node.children;
    final takeCount = children.length < maxChildrenPerNode
        ? children.length
        : maxChildrenPerNode;
    for (var i = 0; i < takeCount; i++) {
      final child = children[i];
      // At deeper levels, skip file leaves in preview payload to keep it fast;
      // users still get full file-level data when final scan completes.
      if (depth >= 2 && child.isFile) {
        continue;
      }
      clone.children.add(clonePreviewTree(
        child,
        depth: depth + 1,
        maxDepth: maxDepth,
        maxChildrenPerNode: maxChildrenPerNode,
      ));
    }
    return clone;
  }

  void maybeFlush(String path) {
    final now = DateTime.now();
    if (now.difference(lastFlush).inMilliseconds >= 120) {
      lastFlush = now;
      sendPort.send(_ProgressMsg(
        dirs: totalDirs,
        files: totalFiles,
        bytes: totalBytes,
        currentPath: path,
      ));
    }
    // Send a bounded preview tree every ~1400ms so UI can expand/collapse what
    // has been scanned so far without copying the entire deep graph.
    final root = rootSnapshot;
    if (root != null && now.difference(lastTreeFlush).inMilliseconds >= 1400) {
      lastTreeFlush = now;
      sendPort.send(_TreeMsg(root: clonePreviewTree(root)));
    }
  }

  /// Scans a directory using Win32 FindFirstFileW/FindNextFileW.
  /// Mutates [node] with children as they are discovered so partial snapshots
  /// can be streamed while the scan is still running.
  void scanInto(DiskTreeNode node, int depth) {
    final dirPath = node.fullPath;
    totalDirs++;
    maybeFlush(dirPath);

    if (depth >= args.maxDepth) return;

    // Prepare search pattern: "C:\path\*"
    final searchPath = dirPath.endsWith('\\')
        ? '$dirPath*'
        : '$dirPath\\*';
    final lpFileName = searchPath.toNativeUtf16();
    final findData = calloc<win32.WIN32_FIND_DATA>();

    try {
      final hFind = win32.FindFirstFile(lpFileName, findData);
      if (hFind == _invalidHandleValue) {
        inaccessible.add(dirPath);
        return;
      }

      try {
        do {
          final fileName = findData.ref.cFileName;
          // Skip . and ..
          if (fileName == '.' || fileName == '..') continue;

          final attrs = findData.ref.dwFileAttributes;

          // Skip reparse points (junctions/symlinks) to avoid infinite loops
          if (attrs & _fileAttributeReparsePoint != 0) continue;

          final isDir = attrs & _fileAttributeDirectory != 0;
          final fullPath = dirPath.endsWith('\\')
              ? '$dirPath$fileName'
              : '$dirPath\\$fileName';

          if (isDir) {
            // Skip known system directories that cause issues
            if (fileName == '\$RECYCLE.BIN' ||
                fileName == 'System Volume Information' ||
                fileName == '\$WinREAgent') {
              continue;
            }
            final child = DiskTreeNode(name: fileName, fullPath: fullPath);
            node.children.add(child);
            scanInto(child, depth + 1);
            node.sizeBytes += child.sizeBytes;
            node.fileCount += child.fileCount;
          } else {
            // File — extract size from high/low DWORDs
            final sizeHigh = findData.ref.nFileSizeHigh;
            final sizeLow = findData.ref.nFileSizeLow;
            final fileSize = (sizeHigh << 32) | sizeLow;

            node.children.add(DiskTreeNode(
              name: fileName,
              fullPath: fullPath,
              isFile: true,
              sizeBytes: fileSize,
              fileCount: 1,
            ));
            node.sizeBytes += fileSize;
            node.fileCount++;
            totalFiles++;
            totalBytes += fileSize;
          }
        } while (win32.FindNextFile(hFind, findData) != 0);
      } finally {
        win32.FindClose(hFind);
      }
    } catch (_) {
      inaccessible.add(dirPath);
    } finally {
      calloc.free(findData);
      calloc.free(lpFileName);
    }
  }

  final driveName = args.drivePath.endsWith('\\')
      ? args.drivePath
      : '${args.drivePath}\\';
  final root = DiskTreeNode(name: driveName, fullPath: driveName);
  rootSnapshot = root;
  scanInto(root, 0);

  // Sort by size descending
  root.sortBySize();

  sendPort.send(_DoneMsg(root: root, inaccessible: inaccessible));
}

// ---------------------------------------------------------------------------
// Message types
// ---------------------------------------------------------------------------

class _FullScanArgs {
  final SendPort sendPort;
  final String drivePath;
  final int maxDepth;
  const _FullScanArgs({
    required this.sendPort,
    required this.drivePath,
    this.maxDepth = 20,
  });
}

class _ProgressMsg {
  final int dirs;
  final int files;
  final int bytes;
  final String currentPath;
  const _ProgressMsg({
    required this.dirs,
    required this.files,
    required this.bytes,
    required this.currentPath,
  });
}

class _TreeMsg {
  final DiskTreeNode root;
  const _TreeMsg({required this.root});
}

class _DoneMsg {
  final DiskTreeNode root;
  final List<String> inaccessible;
  const _DoneMsg({required this.root, required this.inaccessible});
}
