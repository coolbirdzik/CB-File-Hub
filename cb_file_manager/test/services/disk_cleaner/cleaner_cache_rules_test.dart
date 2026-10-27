import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/cleaner_cache_rules.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_categories.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_quick_clean.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_isolate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'new rule roots are narrow, age limited and never scan a whole profile',
    () {
      for (final os in ['windows', 'macos']) {
        final categories = CleanerCategories.all(operatingSystem: os);
        final quickIds = CleanerQuickClean.categoryIds(operatingSystem: os);
        final electronPaths = <String>{};
        for (final category in categories) {
          if (!const {
            'system_cache',
            'package_download_cache',
            'electron_cache',
          }.contains(category.id)) {
            continue;
          }
          expect(quickIds, contains(category.id));
          expect(category.safety, CleanerSafety.safe);
          expect(category.requiresAdmin, isFalse);
          for (final rule in category.rules) {
            expect(rule.source.kind, PathSourceKind.env);
            expect(rule.source.relative, isNotEmpty);
            expect(rule.minAge, isNotNull);
            expect(rule.excludeGlobs, contains('*.lock'));
            final relative = rule.source.relative
                .replaceAll(r'\', '/')
                .toLowerCase();
            expect(relative, isNot(contains('node_modules')));
            expect(relative, isNot(contains('indexeddb')));
            expect(relative, isNot(contains('service worker')));
            expect(relative, isNot(contains('cachestorage')));
            expect(relative, isNot(contains('.nuget/packages')));
            expect(relative, isNot(contains('.m2/repository')));
            expect(relative, isNot(contains('.gradle/caches')));
            if (category.id == 'electron_cache') {
              expect(electronPaths.add(relative), isTrue);
            }
          }
        }
        if (os == 'windows') {
          final appCache = categories.firstWhere((c) => c.id == 'app_cache');
          for (final rule in appCache.rules) {
            final relative = rule.source.relative
                .replaceAll(r'\', '/')
                .toLowerCase();
            expect(electronPaths, isNot(contains(relative)), reason: relative);
          }
        }
      }
    },
  );

  test(
    'real rule scan finds old cache files and excludes live libraries and storage',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'cb-regenerable-cache-',
      );
      addTearDown(() => root.delete(recursive: true));
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 30));
      final recent = now.subtract(const Duration(hours: 1));
      final expected = <String>{};
      final preserved = <String>{};

      Future<void> file(
        String relative, {
        bool eligible = false,
        bool isRecent = false,
      }) async {
        final path = p.joinAll([root.path, ...relative.split('/')]);
        final entry = File(path);
        await entry.parent.create(recursive: true);
        await entry.writeAsString(relative);
        await entry.setLastModified(isRecent ? recent : old);
        (eligible ? expected : preserved).add(path);
      }

      await file('LOCALAPPDATA/D3DSCache/shader.bin', eligible: true);
      await file(
        'LOCALAPPDATA/npm-cache/_cacache/content-v2/blob',
        eligible: true,
      );
      await file('LOCALAPPDATA/pip/Cache/wheels/package.whl', eligible: true);
      await file(
        'USERPROFILE/.cargo/registry/cache/index/a.crate',
        eligible: true,
      );
      await file('LOCALAPPDATA/NuGet/v3-cache/package.dat', eligible: true);
      await file('LOCALAPPDATA/Composer/files/vendor/a.zip', eligible: true);
      await file('APPDATA/Notion/Cache/Cache_Data/f_01', eligible: true);
      await file('APPDATA/Cursor/Code Cache/js/abc_0', eligible: true);
      await file('APPDATA/discord/GPUCache/data_1', eligible: true);
      await file('LOCALAPPDATA/D3DSCache/recent.bin', isRecent: true);
      await file('LOCALAPPDATA/npm-cache/_cacache/recent', isRecent: true);
      await file('APPDATA/Notion/Cache/recent', isRecent: true);
      await file('APPDATA/Notion/Cache/LOCK');
      await file('APPDATA/Notion/GPUCache/data.lock');
      await file('APPDATA/Notion/IndexedDB/00001.log');
      await file('APPDATA/Notion/Local Storage/leveldb/00001.log');
      await file('APPDATA/Notion/Service Worker/CacheStorage/offline');
      await file('APPDATA/Notion/Network/Cookies');
      await file('APPDATA/Notion/Preferences');
      await file('APPDATA/Notion/node_modules/electron/index.js');
      await file('LOCALAPPDATA/npm-cache/_npx/tool/index.js');
      await file('USERPROFILE/.nuget/packages/used/lib.dll');
      await file('USERPROFILE/.pub-cache/hosted/used/lib.dart');
      await file('USERPROFILE/.cargo/registry/src/index/used/lib.rs');
      await file('USERPROFILE/.m2/repository/local-only.jar');
      await file('USERPROFILE/.gradle/caches/in-use.jar');

      final rules = <ResolvedRule>[
        for (final category in CleanerCacheRules.windows)
          for (final rule in category.rules)
            if (CleanerQuickClean.includesRule(category.id, rule))
              ResolvedRule(
                categoryId: category.id,
                basePath: p.joinAll([
                  root.path,
                  rule.source.envVar!,
                  ...rule.source.relative.split('/'),
                ]),
                includeGlobs: rule.includeGlobs,
                excludeGlobs: rule.excludeGlobs,
                minAge: rule.minAge,
                recursive: rule.recursive,
                emptyOnly: rule.emptyOnly,
              ),
      ];
      final handle = await spawnScanWithResolvedRules(
        drivesScanned: [root.path],
        rules: rules,
      );
      final report = CleanerQuickClean.select(await handle.future, now: now);
      expect(report.allItems.map((i) => i.path).toSet(), expected);
      expect(report.totalCount, expected.length);
      for (final path in preserved) {
        expect(await File(path).exists(), isTrue, reason: path);
      }
    },
  );
}
