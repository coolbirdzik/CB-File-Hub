import 'package:cb_file_manager/services/disk_cleaner/cleaner_categories.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_quick_clean.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 26, 12);
  const local = r'C:\Users\test\AppData\Local';
  const roaming = r'C:\Users\test\AppData\Roaming';

  JunkItem item(
    String categoryId,
    String path, {
    Duration age = const Duration(days: 30),
    bool recycleBin = false,
    bool userSelected = false,
    bool noTimestamp = false,
  }) => JunkItem(
    path: path,
    sizeBytes: 100,
    categoryId: categoryId,
    lastModified: noTimestamp ? null : now.subtract(age),
    isRecycleBinItem: recycleBin,
    isUserSelected: userSelected,
  );

  bool eligible(JunkItem item) => CleanerQuickClean.isEligible(item, now);

  test('scans only safe categories and never the Recycle Bin', () {
    expect(CleanerQuickClean.categoryIds(operatingSystem: 'windows'), [
      'windows_temp',
      'browser_cache',
      'thumbnail_cache',
      'app_cache',
      'crash_dumps_logs',
      'system_cache',
      'package_download_cache',
      'electron_cache',
      'developer_analysis_cache',
      'developer_download_cache',
      'electron_crash_reports',
    ]);
    // macOS app_cache covers all of ~/Library/Caches and is `careful`.
    expect(CleanerQuickClean.categoryIds(operatingSystem: 'macos'), [
      'browser_cache',
      'crash_dumps_logs',
      'package_download_cache',
      'electron_cache',
      'xcode_build_cache',
    ]);
    expect(
      eligible(item('recycle_bin', r'C:\$Recycle.Bin\S-1\$R1.txt')),
      isFalse,
    );
    expect(
      eligible(item('windows_temp', '$local\\Temp\\a.tmp', recycleBin: true)),
      isFalse,
    );
    expect(eligible(item('dev_cache', '$roaming\\npm-cache\\x')), isFalse);
  });

  test('skips the AppData-wide log rules but keeps crash dumps', () {
    final crash = CleanerCategories.all(
      operatingSystem: 'windows',
    ).firstWhere((c) => c.id == 'crash_dumps_logs');
    final kept = crash.rules
        .where((r) => CleanerQuickClean.includesRule(crash.id, r))
        .map((r) => r.source.relative)
        .toList();
    expect(kept, ['CrashDumps', r'Microsoft\Windows\WER']);

    expect(
      eligible(item('crash_dumps_logs', '$local\\CrashDumps\\a.dmp')),
      isTrue,
    );
    expect(
      eligible(item('crash_dumps_logs', '$roaming\\SomeApp\\old.log')),
      isFalse,
    );
  });

  test('leaves recent files alone, with a week margin for temp', () {
    const temp = '$local\\Temp\\setup.tmp';
    expect(
      eligible(item('windows_temp', temp, age: const Duration(days: 3))),
      isFalse,
    );
    expect(
      eligible(item('windows_temp', temp, age: const Duration(days: 8))),
      isTrue,
    );

    const cache = '$local\\Google\\Chrome\\User Data\\Default\\Cache\\f_01';
    expect(
      eligible(item('browser_cache', cache, age: const Duration(hours: 2))),
      isFalse,
    );
    expect(
      eligible(item('browser_cache', cache, age: const Duration(days: 2))),
      isTrue,
    );
    expect(eligible(item('browser_cache', cache, noTimestamp: true)), isFalse);
    // A clock skewed into the future must not make a file look old.
    expect(
      eligible(item('browser_cache', cache, age: const Duration(days: -3))),
      isFalse,
    );
  });

  test('app and browser items must be inside a cache folder', () {
    expect(
      CleanerQuickClean.includesRule(
        'app_cache',
        const CleanerPathRule(
          source: PathSource.env(
            'APPDATA',
            r'Microsoft\Teams\Service Worker\CacheStorage',
          ),
        ),
      ),
      isFalse,
    );
    for (final path in [
      '$roaming\\discord\\Cache\\Cache_Data\\data_1',
      '$roaming\\Code\\CachedData\\abc\\x.code',
      '$local\\Mozilla\\Firefox\\Profiles\\p.default\\cache2\\entries\\A1',
      '$local\\Mozilla\\Firefox\\Profiles\\p.default\\startupCache\\x.bin',
    ]) {
      final category = path.contains('Firefox') ? 'browser_cache' : 'app_cache';
      expect(eligible(item(category, path)), isTrue, reason: path);
    }
    for (final path in [
      '$local\\Spotify\\Storage\\offline.file',
      '$roaming\\Zoom\\data\\zoomus.enc.db',
      '$roaming\\Microsoft\\Teams\\Service Worker\\CacheStorage\\x',
      '$local\\Mozilla\\Firefox\\Profiles\\p.default\\settings\\data.safe.bin',
      // A user named "Cache" does not turn the whole profile into a cache.
      r'C:\Users\Cache\AppData\Roaming\Zoom\data\zoomus.enc.db',
    ]) {
      final category = path.contains('Firefox') ? 'browser_cache' : 'app_cache';
      expect(eligible(item(category, path)), isFalse, reason: path);
    }
  });

  test('never takes app databases or user-selected paths', () {
    expect(
      eligible(
        item(
          'browser_cache',
          '$local\\Google\\Chrome\\User Data\\Default\\Cache\\IndexedDB\\000003.log',
        ),
      ),
      isFalse,
    );
    expect(
      eligible(item('windows_temp', '$local\\Temp\\app\\leveldb\\000005.log')),
      isFalse,
    );
    expect(
      eligible(item('windows_temp', '$local\\Temp\\a.tmp', userSelected: true)),
      isFalse,
    );
  });

  test('select keeps eligible items and drops emptied categories', () {
    final report = ScanReport(
      drivesScanned: const [r'C:\'],
      itemsByCategory: {
        'windows_temp': [
          item('windows_temp', '$local\\Temp\\old.tmp'),
          item(
            'windows_temp',
            '$local\\Temp\\new.tmp',
            age: const Duration(hours: 1),
          ),
        ],
        'app_cache': [item('app_cache', '$local\\Spotify\\Storage\\x')],
      },
      warnings: const ['w'],
      scannedAt: now,
    );
    final selected = CleanerQuickClean.select(report, now: now);
    expect(selected.itemsByCategory.keys, ['windows_temp']);
    expect(selected.allItems.map((i) => i.path), ['$local\\Temp\\old.tmp']);
    expect(selected.warnings, ['w']);
  });

  test(
    'new caches need the right path and age; installed libraries stay out',
    () {
      final safe = {
        'system_cache': ['$local\\D3DSCache\\shader.bin'],
        'package_download_cache': [
          '$local\\npm-cache\\_cacache\\content-v2\\blob',
          '$local\\pip\\Cache\\wheels\\a.whl',
          r'C:\Users\test\.cargo\registry\cache\index\a.crate',
          '$local\\NuGet\\v3-cache\\package.dat',
          '$local\\Composer\\files\\vendor\\package.zip',
        ],
        'electron_cache': [
          '$roaming\\Notion\\Cache\\Cache_Data\\f_01',
          '$roaming\\Cursor\\Code Cache\\js\\f_01',
          '$roaming\\Cursor\\CachedData\\version\\f_01',
          '$roaming\\discord\\GPUCache\\data_0',
          '$roaming\\Figma\\DawnGraphiteCache\\data_1',
        ],
      };
      for (final entry in safe.entries) {
        for (final path in entry.value) {
          expect(eligible(item(entry.key, path)), isTrue, reason: path);
          expect(
            eligible(item(entry.key, path, age: const Duration(hours: 1))),
            isFalse,
          );
          expect(eligible(item(entry.key, path, noTimestamp: true)), isFalse);
        }
      }
      expect(
        eligible(
          item(
            'system_cache',
            '$local\\D3DSCache\\a',
            age: const Duration(days: 3),
          ),
        ),
        isFalse,
      );
      expect(
        eligible(
          item(
            'package_download_cache',
            '$local\\pip\\Cache\\a',
            age: const Duration(days: 3),
          ),
        ),
        isFalse,
      );
      for (final path in [
        r'C:\project\node_modules\a\index.js',
        r'C:\Users\test\.nuget\packages\a\a.dll',
        r'C:\Users\test\.pub-cache\hosted\a\lib\a.dart',
        r'C:\Users\test\.m2\repository\local-only.jar',
        r'C:\Users\test\.gradle\caches\a.jar',
        r'C:\Users\test\.cargo\registry\src\index\a\lib.rs',
        '$local\\npm-cache\\_npx\\a\\index.js',
        '$local\\pip\\Cache-old\\a.whl',
      ]) {
        expect(
          eligible(item('package_download_cache', path)),
          isFalse,
          reason: path,
        );
      }
      for (final path in [
        '$roaming\\Notion\\IndexedDB\\00001.log',
        '$roaming\\Notion\\Local Storage\\leveldb\\data',
        '$roaming\\Notion\\Service Worker\\CacheStorage\\blob',
        '$roaming\\Notion\\Cookies',
        '$roaming\\Notion\\Cache-backup\\personal.txt',
        '$roaming\\Notion\\GPUCache\\LOCK',
        '$roaming\\Notion\\GPUCache\\data.lock',
      ]) {
        expect(eligible(item('electron_cache', path)), isFalse, reason: path);
      }
    },
  );

  test('overlapping categories do not double count one file', () {
    const path = '$roaming\\Notion\\Cache\\data_1';
    final report = ScanReport(
      drivesScanned: const [],
      itemsByCategory: {
        'app_cache': [item('app_cache', path)],
        'electron_cache': [item('electron_cache', path)],
      },
      warnings: const [],
      scannedAt: now,
    );
    final selected = CleanerQuickClean.select(report, now: now);
    expect(selected.totalCount, 1);
    expect(selected.totalBytes, 100);
  });
}
