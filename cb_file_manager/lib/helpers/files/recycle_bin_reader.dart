// Direct Windows Recycle Bin reader.
//
// Bypasses Shell.Application COM entirely. The Recycle Bin stores its
// contents in `C:\$Recycle.Bin\<SID>\` (one folder per user SID per
// drive). Each deleted item has two files in that folder:
//
//   $I<random>.<ext> — 544-byte (or larger) metadata file:
//                      header, file size, deletion FILETIME, and the
//                      original path string.
//   $R<random>.<ext> — the actual deleted bytes (or directory).
//
// PERF: the actual file I/O runs in a background isolate so the UI
// thread never has to walk thousands of $I files synchronously. The
// public API still exposes a `Stream<SystemTrashItem>` so callers can
// render entries as they arrive.
//
// Spec reference for the $I* format (Vista+):
//   Bytes 0-7   : Header / version (int64 little-endian; 1 = pre-Win10,
//                                   2 = Win10+ with variable path).
//   Bytes 8-15  : Original file size (int64 little-endian).
//   Bytes 16-23 : Deletion timestamp (Windows FILETIME, 100-ns ticks
//                                     since 1601-01-01 UTC).
//   Version 1:
//     Bytes 24-543 : Original path, UTF-16LE, null-terminated, fixed
//                    260 wchar buffer (Windows MAX_PATH).
//   Version 2:
//     Bytes 24-27 : Path length in WCHARs, including the trailing NUL.
//     Bytes 28-…  : Original path, UTF-16LE, null-terminated.

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as pathlib;

import 'trash_manager.dart' show SystemTrashItem;

/// Stream every Recycle Bin entry across every fixed drive on the
/// machine, yielding each entry as soon as its `$I` metadata file has
/// been parsed.
///
/// File I/O runs on a background isolate. The main isolate only
/// receives finished `SystemTrashItem` chunks via SendPort — so the UI
/// thread is free to render and scroll while thousands of `$I*` files
/// are being parsed.
Stream<SystemTrashItem> streamRecycleBinEntries() async* {
  if (!Platform.isWindows) return;

  final receivePort = ReceivePort();
  final exitPort = ReceivePort();
  final errorPort = ReceivePort();

  final isolate = await Isolate.spawn<SendPort>(
    _readerIsolateMain,
    receivePort.sendPort,
    onExit: exitPort.sendPort,
    onError: errorPort.sendPort,
    errorsAreFatal: true,
    debugName: 'recycle_bin_reader',
  );

  final controller = StreamController<SystemTrashItem>();

  receivePort.listen((dynamic msg) {
    if (msg is List) {
      // Chunk of items, encoded as List<List<dynamic>> for cheap
      // cross-isolate transfer.
      for (final encoded in msg) {
        if (encoded is List) {
          final item = _decodeItem(encoded);
          if (item != null) controller.add(item);
        }
      }
    } else if (msg == 'done') {
      if (!controller.isClosed) controller.close();
      receivePort.close();
      exitPort.close();
      errorPort.close();
    }
  });

  errorPort.listen((_) {
    if (!controller.isClosed) controller.close();
    receivePort.close();
    exitPort.close();
    errorPort.close();
    isolate.kill(priority: Isolate.immediate);
  });

  exitPort.listen((_) {
    if (!controller.isClosed) controller.close();
    receivePort.close();
    exitPort.close();
    errorPort.close();
  });

  yield* controller.stream;
}

// ---------------------------------------------------------------------------
// Isolate side
// ---------------------------------------------------------------------------

void _readerIsolateMain(SendPort sendPort) async {
  try {
    final buffer = <List<dynamic>>[];
    const flushAt = 64;

    final driveLetters = await _enumerateFixedDrives();
    for (final drive in driveLetters) {
      final binDir = Directory('$drive\\\$Recycle.Bin');
      if (!binDir.existsSync()) continue;

      List<FileSystemEntity> sidEntries;
      try {
        sidEntries = binDir.listSync(followLinks: false);
      } catch (_) {
        continue;
      }

      for (final sidEntry in sidEntries) {
        if (sidEntry is! Directory) continue;

        List<FileSystemEntity> entries;
        try {
          entries = sidEntry.listSync(followLinks: false);
        } catch (_) {
          continue;
        }

        for (final entry in entries) {
          if (entry is! File) continue;
          final base = pathlib.basename(entry.path);
          if (!base.startsWith(r'$I')) continue;

          List<dynamic>? encoded;
          try {
            encoded = _parseAndEncode(entry, sidEntry);
          } catch (_) {
            // ignore parse failures, keep going
          }
          if (encoded != null) {
            buffer.add(encoded);
            if (buffer.length >= flushAt) {
              sendPort.send(List<List<dynamic>>.from(buffer));
              buffer.clear();
            }
          }
        }
      }
    }

    if (buffer.isNotEmpty) {
      sendPort.send(List<List<dynamic>>.from(buffer));
      buffer.clear();
    }
  } catch (_) {
    // best-effort: signal done so the main isolate stops waiting
  } finally {
    sendPort.send('done');
  }
}

List<dynamic>? _parseAndEncode(File metaFile, Directory sidDir) {
  final bytes = metaFile.readAsBytesSync();
  if (bytes.length < 24) return null;

  final byteData = ByteData.sublistView(bytes);
  final version = byteData.getInt64(0, Endian.little);
  final originalSize = byteData.getInt64(8, Endian.little);
  final deletedFiletime = byteData.getInt64(16, Endian.little);
  final deletedAtMs = _filetimeToUnixMs(deletedFiletime);

  String? originalPath;
  if (version == 2 && bytes.length >= 28) {
    final pathLenWchars = byteData.getInt32(24, Endian.little);
    final pathByteEnd = 28 + pathLenWchars * 2;
    if (pathByteEnd <= bytes.length) {
      originalPath = _decodeUtf16LeNullTerminated(bytes, 28, pathByteEnd);
    }
  } else if (bytes.length >= 24 + 520) {
    originalPath = _decodeUtf16LeNullTerminated(bytes, 24, 24 + 520);
  }

  if (originalPath == null || originalPath.isEmpty) return null;

  final base = pathlib.basename(metaFile.path);
  final companionName = '\$R${base.substring(2)}';
  final companionPath = pathlib.join(sidDir.path, companionName);
  final companionFile = File(companionPath);
  final companionDir = Directory(companionPath);
  final isFolder = !companionFile.existsSync() && companionDir.existsSync();

  // Encode as a positional list: [name, path, originalPath, size,
  // trashedDateMs, isFolder]. Cheaper to send across isolates than a
  // Map and decoded in the main isolate.
  return <dynamic>[
    pathlib.basename(originalPath),
    isFolder ? companionDir.path : companionFile.path,
    originalPath,
    originalSize >= 0 ? originalSize : 0,
    deletedAtMs,
    isFolder,
  ];
}

SystemTrashItem? _decodeItem(List<dynamic> raw) {
  if (raw.length < 6) return null;
  return SystemTrashItem(
    name: raw[0] as String,
    recycleBinPath: raw[1] as String,
    originalPath: raw[2] as String,
    size: raw[3] as int,
    trashedDate: DateTime.fromMillisecondsSinceEpoch(raw[4] as int),
    isSystemItem: true,
    isFolder: raw[5] as bool,
  );
}

int _filetimeToUnixMs(int filetime) {
  // FILETIME is 100-ns ticks since 1601-01-01 UTC.
  const filetimeToUnixOffsetMs = 11644473600000;
  if (filetime <= 0) return 0;
  return (filetime ~/ 10000) - filetimeToUnixOffsetMs;
}

String _decodeUtf16LeNullTerminated(Uint8List bytes, int start, int end) {
  final units = <int>[];
  for (var i = start; i + 1 < end; i += 2) {
    final lo = bytes[i];
    final hi = bytes[i + 1];
    final code = lo | (hi << 8);
    if (code == 0) break;
    units.add(code);
  }
  return String.fromCharCodes(units);
}

Future<List<String>> _enumerateFixedDrives() async {
  // dart:io has no "list drives" API on Windows, so probe each letter.
  final drives = <String>[];
  for (final letter in _driveLetters) {
    final root = '$letter:\\';
    if (Directory(root).existsSync()) {
      drives.add('$letter:');
    }
  }
  return drives;
}

const _driveLetters = [
  'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];
