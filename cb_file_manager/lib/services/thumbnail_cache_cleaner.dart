import 'dart:io';
import 'dart:isolate';
import 'package:cb_native/cb_native.dart';
import 'package:path/path.dart' as p;

/// Plans one pass over this app's thumbnail cache. Deletion rechecks each
/// candidate, preserving thumbnails written/replaced while planning ran.
class ThumbnailCacheCleaner {
  static Future<List<NativeCacheEntry>> plan(
    String root, {
    required DateTime cutoff,
    required int maxCount,
    required int maxBytes,
    bool useNative = true,
  }) async {
    if (useNative) {
      final native = await NativeUiJobs.cachePlan(
        root,
        cutoffMs: cutoff.millisecondsSinceEpoch,
        maxCount: maxCount,
        maxBytes: maxBytes,
      );
      if (native != null) return native;
    }
    return Isolate.run(() {
      final entries = <NativeCacheEntry>[];
      for (final entry in Directory(root).listSync(followLinks: false)) {
        if (entry is! File) continue;
        try {
          final stat = entry.statSync();
          entries.add(
            NativeCacheEntry(
              entry.path,
              stat.size,
              stat.modified.millisecondsSinceEpoch,
            ),
          );
        } on FileSystemException {
          /* The cache may change while enumerating. */
        }
      }
      entries.sort((a, b) {
        final age = a.modifiedMs.compareTo(b.modifiedMs);
        return age != 0 ? age : a.path.compareTo(b.path);
      });
      var count = entries.length;
      var bytes = entries.fold(0, (sum, e) => sum + e.size);
      final selected = <NativeCacheEntry>[];
      for (final entry in entries) {
        if (entry.modifiedMs < cutoff.millisecondsSinceEpoch ||
            count > maxCount ||
            bytes > maxBytes) {
          selected.add(entry);
          count--;
          bytes -= entry.size;
        }
      }
      return selected;
    });
  }

  static Future<int> apply(String root, List<NativeCacheEntry> entries) async {
    var deleted = 0;
    final parent = p.normalize(p.absolute(root));
    for (final entry in entries) {
      if (!p.equals(p.dirname(p.normalize(p.absolute(entry.path))), parent)) {
        continue;
      }
      try {
        if (await FileSystemEntity.type(entry.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final file = File(entry.path);
        final stat = await file.stat();
        if (stat.size != entry.size ||
            stat.modified.millisecondsSinceEpoch != entry.modifiedMs) {
          continue;
        }
        await file.delete();
        deleted++;
      } on FileSystemException catch (e) {
        stderr.writeln('Thumbnail cache: ${entry.path}: $e');
      }
    }
    return deleted;
  }
}
