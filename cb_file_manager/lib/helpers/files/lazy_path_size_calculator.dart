import 'dart:io';

import 'package:cb_native/cb_native.dart';

/// Calculates file and directory sizes without blocking the first UI frame.
///
/// Directory traversal does not follow symbolic links. Individual paths that
/// disappear or cannot be read are skipped so one inaccessible child does not
/// prevent the remaining size from being reported.
///
/// The walk runs on Rust threads (package:cb_native) when the library is
/// built, so a grid of folders sizing themselves does not flood the UI
/// isolate's event loop with one `stat` per file; otherwise it runs here.
class LazyPathSizeCalculator {
  const LazyPathSizeCalculator._();

  static Future<int> calculate({
    Iterable<String> filePaths = const <String>[],
    Iterable<String> folderPaths = const <String>[],
    bool Function()? isCancelled,
    Duration initialDelay = const Duration(milliseconds: 150),
  }) async {
    if (initialDelay > Duration.zero) {
      await Future<void>.delayed(initialDelay);
    }
    if (isCancelled?.call() ?? false) return 0;

    final native = await NativeFs.directorySize(
      files: filePaths,
      directories: folderPaths,
      shouldContinue: () => !(isCancelled?.call() ?? false),
    );
    if (native != null) return native.bytes;
    if (isCancelled?.call() ?? false) return 0;

    var totalSize = 0;
    for (final filePath in filePaths) {
      if (isCancelled?.call() ?? false) return totalSize;
      try {
        final stat = await File(filePath).stat();
        if (stat.type == FileSystemEntityType.file) {
          totalSize += stat.size;
        }
      } on FileSystemException {
        // The selection can contain stale or inaccessible paths.
      }
    }

    for (final folderPath in folderPaths) {
      if (isCancelled?.call() ?? false) return totalSize;
      totalSize += await _dartDirectorySize(folderPath, isCancelled);
    }
    return totalSize;
  }

  static Future<int> calculateDirectory(
    String folderPath, {
    bool Function()? isCancelled,
    Duration initialDelay = const Duration(milliseconds: 150),
  }) => calculate(
    folderPaths: [folderPath],
    isCancelled: isCancelled,
    initialDelay: initialDelay,
  );

  static Future<int> _dartDirectorySize(
    String folderPath,
    bool Function()? isCancelled,
  ) async {
    var totalSize = 0;
    try {
      await for (final entity in Directory(
        folderPath,
      ).list(followLinks: false)) {
        if (isCancelled?.call() ?? false) return totalSize;
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.type == FileSystemEntityType.file) {
              totalSize += stat.size;
            }
          } on FileSystemException {
            // Continue with the remaining children.
          }
        } else if (entity is Directory) {
          totalSize += await _dartDirectorySize(entity.path, isCancelled);
        }
      }
    } on FileSystemException {
      // Missing and inaccessible directories contribute zero bytes.
    }
    return totalSize;
  }
}
