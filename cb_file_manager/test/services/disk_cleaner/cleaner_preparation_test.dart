import 'dart:io';

import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_safety.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Trash implements TrashManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
  final paths = <String>[];
  void Function()? beforeDelete;

  @override
  Future<Set<String>> deleteMultiplePermanently(
    List<String> filePaths, {
    int chunkSize = 200,
    void Function(String, int, int)? onChunkStart,
    void Function(int, int)? onChunkDone,
    void Function(String, Object)? onError,
    Duration? timeoutOverride,
    bool useNative = true,
  }) async {
    beforeDelete?.call();
    paths.addAll(filePaths);
    return filePaths.toSet();
  }
}

void main() {
  late Directory root;
  setUp(() async {
    // All desktop rule tables allow this npm download-cache root. System
    // temp is not a cleanable rule root on Linux/macOS.
    final home =
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']!;
    final cache = await Directory(
      p.join(home, '.npm', '_cacache'),
    ).create(recursive: true);
    root = await cache.createTemp('cb_cleaner_preparation_');
    for (var i = 0; i < 4; i++) {
      final dir = Directory(p.join(root.path, 'folder$i'))..createSync();
      for (var j = 0; j < 4; j++) {
        File(p.join(dir.path, 'file$j.tmp')).writeAsStringSync('cache');
      }
    }
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'preparation reports found files before deletion and preserves container folders',
    () async {
      final trash = _Trash();
      final events = <(int, int, String?)>[];
      trash.beforeDelete = () {
        final preparing = events.where((event) => event.$2 == 0).toList();
        expect(preparing.first.$1, 0);
        expect(preparing.last.$1, 16);
        expect(preparing.last.$3, root.path);
        expect(
          preparing.map((event) => event.$1),
          orderedEquals(preparing.map((event) => event.$1).toList()..sort()),
        );
      };
      final service = DiskCleanerService.forTesting(
        fullDiskScanSpawner: spawnFullDiskScan,
        trashManager: trash,
      );
      expect(
        CleanerPathSafety.isPathSafeToDelete(root.path),
        isTrue,
        reason: 'The fixture must be under an allowed cache root on this host',
      );
      final report = await service.cleanJunk(
        items: [
          JunkItem(
            path: root.path,
            sizeBytes: 80,
            categoryId: 'package_download_cache',
            isContainerOnly: true,
          ),
        ],
        permanent: true,
        onProgress: (done, total, path) => events.add((done, total, path)),
      );
      expect(report.skippedUnsafe, isEmpty);
      expect(report.succeeded, hasLength(16));
      expect(trash.paths.toSet(), report.succeeded.toSet());
      expect(trash.paths, isNot(contains(root.path)));
      expect(trash.paths.every((path) => p.isWithin(root.path, path)), isTrue);
      expect(events.firstWhere((event) => event.$2 > 0).$1, 0);
      expect(events.last.$1, events.last.$2);
      expect(root.existsSync(), isTrue);
    },
  );

  test(
    'parallel streamed Rust walk matches buffered paths, stats and timestamps',
    () async {
      final buffered = await NativeFs.walk(roots: [root.path], stats: true);
      expect(buffered, isNotNull);
      final streamed = <NativeWalkEntry>[];
      final output = await NativeFs.walk(
        roots: [root.path],
        stats: true,
        parallel: true,
        onEntries: streamed.addAll,
      );
      expect(output, isEmpty);
      expect(streamed, hasLength(16));
      expect(
        {for (final e in streamed) e.path: (e.size, e.modifiedMs)},
        {for (final e in buffered!) e.path: (e.size, e.modifiedMs)},
      );
    },
    skip: CbNative.isAvailable ? false : 'Rust library not built',
  );
}
