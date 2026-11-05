import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/cleaner_categories.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_item_origin.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_quick_clean.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_xcode_cache.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_isolate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  for (final useNative in [true, false]) {
    test(
      'scoped Xcode scan keeps sources, package checkouts, symbols and recent builds (native: $useNative)',
      () async {
        final root = await Directory.systemTemp.createTemp('cb-xcode-scope-');
        addTearDown(() => root.delete(recursive: true));
        final derived = p.joinAll([
          root.path,
          ...CleanerXcodeCache.relativeRoot.split('/'),
        ]);
        final now = DateTime.now();
        final expected = <String>{};
        final kept = <String>{};
        Future<void> file(
          String relative, {
          bool eligible = false,
          bool recent = false,
        }) async {
          final entry = File(p.joinAll([derived, ...relative.split('/')]));
          await entry.parent.create(recursive: true);
          await entry.writeAsString(relative);
          await entry.setLastModified(
            now.subtract(
              recent ? const Duration(hours: 1) : const Duration(days: 30),
            ),
          );
          (eligible ? expected : kept).add(entry.path);
        }

        await file(
          'Project-hash/Build/Intermediates.noindex/App.build/object.o',
          eligible: true,
        );
        await file(
          'Project-hash/Build/Products/Debug/App.app/Contents/MacOS/App',
          eligible: true,
        );
        await file(
          'Project-hash/Index.noindex/DataStore/v5/records/item',
          eligible: true,
        );
        await file('ModuleCache.noindex/hash/Foundation.pcm', eligible: true);
        await file('CompilationCache.noindex/cache.bin', eligible: true);
        await file('SDKStatCaches.noindex/sdk.sdkstatcache', eligible: true);
        await file('SymbolCache.noindex/cache.bin', eligible: true);
        await file(
          'Project-hash/Build/Products/Debug/App.app.dSYM/Contents/Resources/DWARF/App',
        );
        await file(
          'Project-hash/Build/Products/Release/Keep.xcarchive/Products/App.app/App',
        );
        await file(
          'Project-hash/SourcePackages/checkouts/local-edits/Sources/App.swift',
        );
        await file('Project-hash/Sources/App.swift');
        await file('Project-hash/info.plist');
        await file('Project-hash/Logs/Build/old.xcactivitylog');
        await file('Project-hash/Build/Intermediates.noindex/LOCK');
        await file('Project-hash/Build/Intermediates.noindex/build.db.lock');
        await file(
          'Project-hash/Build/Products/Debug/Recent.app/App',
          recent: true,
        );

        final rule = CleanerXcodeCache.category.rules.single;
        final handle = await spawnScanWithResolvedRules(
          useNativeScanner: useNative,
          drivesScanned: [root.path],
          rules: [
            ResolvedRule(
              categoryId: CleanerXcodeCache.categoryId,
              basePath: derived,
              scope: rule.scope,
              excludeGlobs: rule.excludeGlobs,
              minAge: rule.minAge,
            ),
          ],
        );
        final report = await handle.future;
        expect(report.allItems.map((item) => item.path).toSet(), expected);
        expect(
          CleanerQuickClean.select(report, now: now).totalCount,
          expected.length,
        );
        for (final path in kept) {
          expect(await File(path).exists(), isTrue, reason: path);
        }
      },
    );
  }

  test(
    'unknown build folders and protected Xcode data cannot be quick-cleaned',
    () {
      const base = '/Users/test/Library/Developer/Xcode';
      for (final path in [
        '$base/Archives/2026-10-26/App.xcarchive/App',
        '$base/DerivedData/Project/SourcePackages/checkouts/edited.swift',
        '$base/DerivedData/Project/Build/Products/App.dSYM/Contents/Info.plist',
        '$base/DerivedData/Project/Build/Products/App.xcarchive/Info.plist',
        '$base/DerivedData/Project/Sources/App.swift',
        '$base/DerivedData/Project/Build/custom/keep.txt',
        '$base/DerivedData/Project/Build/Products/../../SourcePackages/code.swift',
        '/Users/test/Documents/build/output.o',
      ]) {
        expect(CleanerXcodeCache.isGeneratedFile(path), isFalse, reason: path);
        expect(
          CleanerQuickClean.isEligible(
            JunkItem(
              path: path,
              sizeBytes: 1,
              categoryId: CleanerXcodeCache.categoryId,
              lastModified: DateTime(2026, 1, 1),
            ),
            DateTime(2026, 10, 26),
          ),
          isFalse,
        );
      }
    },
  );

  test('discovery ignores symlinked project output directories', () async {
    final root = await Directory.systemTemp.createTemp('cb-xcode-links-');
    addTearDown(() => root.delete(recursive: true));
    final derived = Directory(p.join(root.path, 'DerivedData'))..createSync();
    final project = Directory(p.join(derived.path, 'App-hash'))..createSync();
    final outside = Directory(p.join(root.path, 'outside'))..createSync();
    Directory(p.join(outside.path, 'Products')).createSync();
    await Link(p.join(project.path, 'Build')).create(outside.path);
    expect(CleanerXcodeCache.discoverRoots(derived.path, []), isEmpty);
  }, skip: Platform.isWindows);

  group('Xcode caches and device symbols', () {
    const home = '/Users/test';
    final now = DateTime(2026, 10, 26);
    JunkItem junk(String path, {Duration age = const Duration(days: 120)}) =>
        JunkItem(
          path: path,
          sizeBytes: 1,
          categoryId: CleanerXcodeCache.junkCategoryId,
          lastModified: now.subtract(age),
        );

    test('is a safe macOS quick-clean category only', () {
      expect(
        CleanerCategories.all(operatingSystem: 'macos').map((c) => c.id),
        contains(CleanerXcodeCache.junkCategoryId),
      );
      expect(
        CleanerCategories.all(operatingSystem: 'windows').map((c) => c.id),
        isNot(contains(CleanerXcodeCache.junkCategoryId)),
      );
      expect(
        CleanerQuickClean.categoryIds(operatingSystem: 'macos'),
        contains(CleanerXcodeCache.junkCategoryId),
      );
    });

    test('accepts only caches, simulator logs and symbol folders', () {
      for (final path in [
        '$home/Library/Caches/com.apple.dt.Xcode/fsCachedData/ABC',
        '$home/Library/Developer/CoreSimulator/Caches/dyld/23A/sim/cache',
        '$home/Library/Logs/CoreSimulator/UDID/system.log',
        '$home/Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)/Info.plist',
        '$home/Library/Developer/Xcode/watchOS DeviceSupport/10.0 (21R5)/Symbols/usr/lib/dyld',
        // Symbol folders are taken whole, so name filters do not split them.
        '$home/Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)/Symbols/System/Library/Databases/x.db',
        '$home/Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)/LOCK',
      ]) {
        expect(CleanerXcodeCache.isJunkFile(path), isTrue, reason: path);
        expect(
          CleanerQuickClean.isEligible(junk(path), now),
          isTrue,
          reason: path,
        );
      }
      for (final path in [
        '$home/Library/Caches/com.apple.dt.Xcode/Cache.db',
        '$home/Library/Caches/com.apple.dt.Xcode/Cache.db-wal',
        '$home/Library/Caches/com.apple.dt.Xcode/LOCK',
        '$home/Library/Caches/com.apple.dt.Xcode.other/file',
        '$home/Library/Developer/CoreSimulator/Devices/UDID/data/app.sqlite',
        '$home/Library/Developer/Xcode/Archives/2026-10-26/App.xcarchive/App',
        '$home/Library/Developer/Xcode/iOS DeviceSupport/.DS_Store',
        '$home/Library/Developer/Xcode/iOS DeviceSupport/../Archives/App',
        '$home/Library/Developer/Xcode/macOS DeviceSupport/14.0/Info.plist',
      ]) {
        expect(CleanerXcodeCache.isJunkFile(path), isFalse, reason: path);
        expect(
          CleanerQuickClean.isEligible(junk(path), now),
          isFalse,
          reason: path,
        );
      }
      expect(
        CleanerQuickClean.isEligible(
          junk(
            '$home/Library/Logs/CoreSimulator/UDID/system.log',
            age: const Duration(days: 1),
          ),
          now,
        ),
        isFalse,
      );
    });

    test('names the app and kind of each item', () {
      CleanerItemOrigin origin(String path) =>
          CleanerItemOrigins.of(junk(path));
      expect(
        origin(
          '$home/Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)/Info.plist',
        ),
        const CleanerItemOrigin(
          app: 'Xcode',
          kind: CleanerItemKind.deviceSymbols,
        ),
      );
      expect(
        origin('$home/Library/Logs/CoreSimulator/UDID/system.log'),
        const CleanerItemOrigin(app: 'Simulator', kind: CleanerItemKind.log),
      );
      expect(
        origin('$home/Library/Developer/CoreSimulator/Caches/dyld/x'),
        const CleanerItemOrigin(
          app: 'Simulator',
          kind: CleanerItemKind.appCache,
        ),
      );
      expect(
        origin('$home/Library/Caches/com.apple.dt.Xcode/fsCachedData/A'),
        const CleanerItemOrigin(app: 'Xcode', kind: CleanerItemKind.appCache),
      );
    });

    test(
      'device support keeps the newest folder and folders changed recently',
      () async {
        final root = await Directory.systemTemp.createTemp('cb-xcode-ds-');
        addTearDown(() => root.delete(recursive: true));
        final created = DateTime.now();
        Future<void> folder(String name, {Duration? touchedAfter}) async {
          final entry = File(p.join(root.path, name, 'Symbols', 'lib.dylib'));
          await entry.parent.create(recursive: true);
          await entry.writeAsString(name);
          if (touchedAfter != null) {
            await entry.setLastModified(created.add(touchedAfter));
          }
        }

        await folder('16.0 (20A362)');
        // One file changed 80 days before "now" keeps its whole folder.
        await folder('16.4 (20E247)', touchedAfter: const Duration(days: 20));
        await folder('17.0 (21A329)');
        // Newest folder of the platform is always kept.
        await folder('17.5 (21F79)', touchedAfter: const Duration(days: 50));
        File(p.join(root.path, '.DS_Store')).writeAsStringSync('');

        final stale = CleanerXcodeCache.discoverStaleDeviceSupport(
          root.path,
          [],
          now: created.add(const Duration(days: 100)),
        ).map(p.basename).toSet();
        expect(stale, {'16.0 (20A362)', '17.0 (21A329)'});

        // A folder emptied by an earlier clean is newer than every real set
        // but must not take the "newest" slot from 17.5.
        await Directory(
          p.join(root.path, '18.0 (22A3354)', 'Symbols', 'usr'),
        ).create(recursive: true);
        expect(
          CleanerXcodeCache.discoverStaleDeviceSupport(
            root.path,
            [],
            now: created.add(const Duration(days: 200)),
          ).map(p.basename).toSet(),
          {'16.0 (20A362)', '16.4 (20E247)', '17.0 (21A329)'},
        );
        expect(
          CleanerXcodeCache.discoverStaleDeviceSupport(root.path, []),
          isEmpty,
          reason: 'nothing is 90 days old yet',
        );
      },
    );

    for (final useNative in [true, false]) {
      test(
        'scan takes whole stale symbol folders only (native: $useNative)',
        () async {
          final temp = await Directory.systemTemp.createTemp('cb-xcode-ds-');
          addTearDown(() => temp.delete(recursive: true));
          final root = await Directory(
            p.join(temp.path, 'Library/Developer/Xcode/iOS DeviceSupport'),
          ).create(recursive: true);
          final old = DateTime.now().subtract(const Duration(days: 120));
          final expected = <String>{};
          Future<void> file(String relative, {bool eligible = false}) async {
            final entry = File(p.joinAll([root.path, ...relative.split('/')]));
            await entry.parent.create(recursive: true);
            await entry.writeAsString(relative);
            await entry.setLastModified(old);
            if (eligible) expected.add(p.normalize(entry.path));
          }

          await file('16.0 (20A362)/Info.plist', eligible: true);
          await file('16.0 (20A362)/.finalized', eligible: true);
          await file('16.0 (20A362)/Symbols/usr/lib/dyld', eligible: true);
          await file('16.0 (20A362)/Symbols/LOCK', eligible: true);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          // Created last, so it is the newest folder and stays.
          await file('17.5 (21F79)/Info.plist');
          await file('17.5 (21F79)/Symbols/usr/lib/dyld');
          await file('.DS_Store');

          final rule = CleanerXcodeCache.junkCategory.rules.firstWhere(
            (rule) => rule.scope == CleanerRuleScope.xcodeDeviceSupport,
          );
          final handle = await spawnScanWithResolvedRules(
            useNativeScanner: useNative,
            drivesScanned: [root.path],
            rules: [
              ResolvedRule(
                categoryId: CleanerXcodeCache.junkCategoryId,
                basePath: root.path,
                scope: rule.scope,
                // Folder mtimes cannot be backdated here; age by order only.
                minAge: Duration.zero,
              ),
            ],
          );
          final report = await handle.future;
          expect(
            report.allItems.map((item) => p.normalize(item.path)).toSet(),
            expected,
          );
        },
      );
    }
  });
}
