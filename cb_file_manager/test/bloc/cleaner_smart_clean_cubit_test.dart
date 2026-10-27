import 'dart:async';

import 'package:cb_file_manager/bloc/cleaner_smart_clean/cleaner_smart_clean.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_item_origin.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:flutter_test/flutter_test.dart';

const String _local = r'C:\Users\me\AppData\Local';
const String _temp = '$_local\\Temp\\old.tmp';
const String _cache = '$_local\\Google\\Chrome\\User Data\\Default\\Cache\\f_1';
const String _bin = r'C:\$Recycle.Bin\S-1\$R1.txt';

final DateTime _now = DateTime(2026, 10, 26, 12);

JunkItem _item(String categoryId, String path, int size, {Duration? age}) =>
    JunkItem(
      path: path,
      sizeBytes: size,
      categoryId: categoryId,
      lastModified: _now.subtract(age ?? const Duration(days: 30)),
      isRecycleBinItem: categoryId == 'recycle_bin',
    );

ScanReport _report(Map<String, List<JunkItem>> items) => ScanReport(
  drivesScanned: const [r'C:\'],
  itemsByCategory: items,
  warnings: const [],
  scannedAt: _now,
);

CleanReport _cleanReport(List<String> succeeded) => CleanReport(
  freedBytes: 0,
  succeeded: succeeded,
  failed: const {},
  skippedUnsafe: const [],
  skippedInUse: const [],
  wasPermanent: false,
);

void main() {
  late List<List<JunkItem>> cleaned;

  CleanerSmartCleanCubit build({
    required Future<ScanReport> Function() scan,
    Future<CleanReport?> Function(List<JunkItem> items)? clean,
    void Function()? cancelScan,
  }) {
    cleaned = [];
    return CleanerSmartCleanCubit(
      scan: (_) => scan(),
      clean: (items, _) async {
        cleaned.add(items);
        return clean == null
            ? _cleanReport(items.map((i) => i.path).toList())
            : clean(items);
      },
      cancelScan: cancelScan,
      nowProvider: () => _now,
    );
  }

  test(
    'groups safe junk, largest first, with the Recycle Bin unchecked',
    () async {
      final cubit = build(
        scan: () async => _report({
          'windows_temp': [_item('windows_temp', _temp, 10)],
          'browser_cache': [_item('browser_cache', _cache, 500)],
          // Too new for quick clean.
          'app_cache': [
            _item(
              'app_cache',
              r'C:\Users\me\AppData\Roaming\discord\Cache\x',
              9,
              age: const Duration(hours: 1),
            ),
          ],
          'recycle_bin': [_item('recycle_bin', _bin, 7000)],
        }),
      );
      await cubit.scan();

      final state = cubit.state;
      expect(state.status, CleanerSmartCleanStatus.ready);
      expect(state.groups.map((g) => g.categoryId), [
        'browser_cache',
        'windows_temp',
        'recycle_bin',
      ]);
      expect(state.groups.last.isPermanent, isTrue);
      expect(state.groupSelection('recycle_bin'), isFalse);
      expect(state.groupSelection('browser_cache'), isTrue);
      expect(state.selectedBytes, 510);
      expect(state.selectedCount, 2);
      await cubit.close();
    },
  );

  test('toggles change the total and what clean receives', () async {
    final cubit = build(
      scan: () async => _report({
        'windows_temp': [_item('windows_temp', _temp, 10)],
        'browser_cache': [_item('browser_cache', _cache, 500)],
        'recycle_bin': [_item('recycle_bin', _bin, 7000)],
      }),
    );
    await cubit.scan();
    cubit.toggleGroup('browser_cache');
    cubit.toggleGroup('recycle_bin');
    expect(cubit.state.selectedBytes, 7010);
    expect(cubit.state.selectedIncludesPermanent, isTrue);

    await cubit.clean();
    expect(cleaned.single.map((i) => i.path), unorderedEquals([_temp, _bin]));
    final result = cubit.state.result!;
    expect(cubit.state.status, CleanerSmartCleanStatus.done);
    expect(result.movedBytes, 10);
    expect(result.permanentBytes, 7000);
    expect(result.skippedCount, 0);
    await cubit.close();
  });

  test(
    'review-only downloads never enter cleanup and remain visible after cleaning',
    () async {
      const download = r'C:\Users\me\Downloads\old.zip';
      final cubit = build(
        scan: () async => _report({
          'windows_temp': [_item('windows_temp', _temp, 10)],
          'old_downloads_review': [
            _item(
              'old_downloads_review',
              download,
              999,
              age: const Duration(days: 100),
            ),
          ],
        }),
      );
      addTearDown(cubit.close);
      await cubit.scan();
      expect(cubit.state.reviewCandidates.single.path, download);
      expect(cubit.state.selectedItems.map((item) => item.path), [_temp]);
      cubit.toggleGroup('old_downloads_review');
      expect(cubit.state.selectedBytes, 10);
      await cubit.clean();
      expect(cleaned.single.map((item) => item.path), [_temp]);
      expect(cubit.state.reviewCandidates.single.path, download);
    },
  );

  test('splits each group by app and kind, largest first', () async {
    const chrome = '$_local\\Google\\Chrome\\User Data\\Default';
    const edge = '$_local\\Microsoft\\Edge\\User Data\\Default';
    final cubit = build(
      scan: () async => _report({
        'browser_cache': [
          _item('browser_cache', _cache, 500),
          _item('browser_cache', '$chrome\\Cache\\f_2', 100),
          _item('browser_cache', '$chrome\\GPUCache\\data_1', 50),
          _item('browser_cache', '$edge\\Cache\\f_1', 300),
        ],
      }),
    );
    await cubit.scan();
    final group = cubit.state.groups.single;
    expect(group.sources.map((s) => (s.origin.app, s.origin.kind, s.bytes)), [
      ('Google Chrome', CleanerItemKind.webCache, 600),
      ('Microsoft Edge', CleanerItemKind.webCache, 300),
      ('Google Chrome', CleanerItemKind.gpuCache, 50),
    ]);
    expect(group.topApps(), ['Google Chrome', 'Microsoft Edge']);
    await cubit.close();
  });

  test('a source can be left out on its own', () async {
    const edge = '$_local\\Microsoft\\Edge\\User Data\\Default\\Cache\\f_1';
    final cubit = build(
      scan: () async => _report({
        'browser_cache': [
          _item('browser_cache', _cache, 500),
          _item('browser_cache', edge, 300),
        ],
      }),
    );
    await cubit.scan();
    final edgeKey = cubit.state.groups.single.sources
        .firstWhere((s) => s.origin.app == 'Microsoft Edge')
        .key;
    cubit.toggleSource('browser_cache', edgeKey);
    expect(cubit.state.groupSelection('browser_cache'), isNull);
    expect(cubit.state.selectedBytes, 500);

    // A partly checked group checks fully, then unchecks fully.
    cubit.toggleGroup('browser_cache');
    expect(cubit.state.groupSelection('browser_cache'), isTrue);
    cubit.toggleGroup('browser_cache');
    expect(cubit.state.groupSelection('browser_cache'), isFalse);
    expect(cubit.state.selectedCount, 0);

    cubit.toggleGroup('browser_cache');
    cubit.toggleSource('browser_cache', edgeKey);
    await cubit.clean();
    expect(cleaned.single.map((i) => i.path), [_cache]);
    expect(cubit.state.result!.movedBytes, 500);
    await cubit.close();
  });

  test('folds the smallest sources into one row', () {
    final items = [
      for (var i = 0; i < CleanerSmartCleanGroup.maxSources + 3; i++)
        _item('windows_temp', '$_local\\Temp\\Tool$i\\a.bin', 100 - i),
    ];
    final group = CleanerSmartCleanGroup(
      categoryId: 'windows_temp',
      items: items,
    );
    expect(group.sources, hasLength(CleanerSmartCleanGroup.maxSources));
    final other = group.sources.last;
    expect(other.key, CleanerSmartCleanGroup.otherSourcesKey);
    expect(other.mergedCount, 4);
    expect(other.origin.kind, CleanerItemKind.tempFile);
    expect(
      group.sources.fold<int>(0, (sum, s) => sum + s.items.length),
      items.length,
    );
  });

  group('installed apps', () {
    const warp = '$_local\\Temp\\Pkg\\.tmpv0.1-WarpSetup.exe';
    final warpApp = const InstalledAppInfo(
      id: 'warp',
      displayName: 'Warp',
      source: InstalledAppSource.win32,
    );

    Future<CleanerSmartCleanSource> scanWith(
      Future<List<InstalledAppInfo>> Function() apps, {
      Duration timeout = const Duration(seconds: 3),
    }) async {
      final cubit = CleanerSmartCleanCubit(
        scan: (_) async => _report({
          'windows_temp': [
            _item('windows_temp', '$_local\\Temp\\WarpSetup\\a.exe', 10),
            _item('windows_temp', warp, 20),
          ],
        }),
        clean: (_, _) async => null,
        nowProvider: () => _now,
        installedApps: apps,
        installedAppsTimeout: timeout,
      );
      await cubit.scan();
      await cubit.close();
      return cubit.state.groups.single.sources.first;
    }

    test('name the files and merge one app into one source', () async {
      final source = await scanWith(() async => [warpApp]);
      expect(source.origin.app, 'Warp');
      expect(source.origin.installedApp?.id, 'warp');
      expect(source.items, hasLength(2));
    });

    test('a slow or failing inventory falls back to folder names', () async {
      for (final load in <Future<List<InstalledAppInfo>> Function()>[
        () => Completer<List<InstalledAppInfo>>().future,
        () async => throw StateError('registry'),
      ]) {
        final source = await scanWith(
          load,
          timeout: const Duration(milliseconds: 50),
        );
        expect(source.origin.installedApp, isNull);
      }
    });
  });

  test('counts items the clean left in place as skipped', () async {
    final cubit = build(
      scan: () async => _report({
        'windows_temp': [_item('windows_temp', _temp, 10)],
        'browser_cache': [_item('browser_cache', _cache, 500)],
      }),
      clean: (_) async => _cleanReport(const [_temp]),
    );
    await cubit.scan();
    await cubit.clean();
    expect(cubit.state.result!.movedBytes, 10);
    expect(cubit.state.result!.skippedCount, 1);
    await cubit.close();
  });

  test('a clean that did not run keeps the results', () async {
    final cubit = build(
      scan: () async => _report({
        'windows_temp': [_item('windows_temp', _temp, 10)],
      }),
      clean: (_) async => null,
    );
    await cubit.scan();
    await cubit.clean();
    expect(cubit.state.status, CleanerSmartCleanStatus.ready);
    expect(cubit.state.groups, hasLength(1));
    await cubit.close();
  });

  test('a busy scanner becomes a failure, not a crash', () async {
    final cubit = build(scan: () async => throw CleanerScanBusyError());
    await cubit.scan();
    expect(cubit.state.status, CleanerSmartCleanStatus.failure);
    expect(cubit.state.error, CleanerSmartCleanError.busy);
    await cubit.close();
  });

  test('cancel drops the scan result that arrives afterwards', () async {
    final pending = Completer<ScanReport>();
    var cancelled = false;
    final cubit = build(
      scan: () => pending.future,
      cancelScan: () => cancelled = true,
    );
    final scan = cubit.scan();
    expect(cubit.state.status, CleanerSmartCleanStatus.scanning);
    cubit.cancelScan();
    pending.complete(
      _report({
        'windows_temp': [_item('windows_temp', _temp, 10)],
      }),
    );
    await scan;
    expect(cancelled, isTrue);
    expect(cubit.state.status, CleanerSmartCleanStatus.idle);
    expect(cubit.state.groups, isEmpty);
    await cubit.close();
  });
}
