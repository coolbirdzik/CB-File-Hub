import 'dart:io';

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
}
