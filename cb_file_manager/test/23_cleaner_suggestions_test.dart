import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_suggestions.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_isolate.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _mb = 1024 * 1024;
const _gb = 1024 * _mb;

DiskTreeNode _node(
  String path, {
  int size = 0,
  bool file = false,
  List<DiskTreeNode> children = const [],
}) => DiskTreeNode(
  name: path.substring(path.lastIndexOf(r'\') + 1),
  fullPath: path,
  isFile: file,
  sizeBytes: file
      ? size
      : children.fold(0, (sum, child) => sum + child.sizeBytes),
  fileCount: file ? 1 : children.length,
  children: children,
);

ScanReport _junkReport() => ScanReport(
  drivesScanned: const [r'C:\'],
  itemsByCategory: {
    'windows_temp': [
      const JunkItem(
        path: r'C:\Users\Tester\AppData\Local\Temp\a.tmp',
        sizeBytes: 300 * _mb,
        categoryId: 'windows_temp',
      ),
    ],
    'recycle_bin': [
      const JunkItem(
        path: r'C:\$Recycle.Bin\S-1\$R1.zip',
        sizeBytes: 200 * _mb,
        categoryId: 'recycle_bin',
        isRecycleBinItem: true,
      ),
    ],
    'windows_update_cache': [
      const JunkItem(
        path: r'C:\Windows\SoftwareDistribution\Download\x.cab',
        sizeBytes: 900 * _mb,
        categoryId: 'windows_update_cache',
      ),
    ],
    'browser_cache': const [],
  },
  warnings: const [],
  scannedAt: DateTime.utc(2026, 10, 1),
);

void main() {
  test('junk categories become clean or review suggestions', () {
    final byId = {
      for (final s in CleanerSuggestionScanner.junkSuggestions(_junkReport()))
        s.id: s,
    };

    expect(byId.keys, isNot(contains('junk:browser_cache')));
    expect(byId['junk:windows_temp']!.tier, CleanerSuggestionTier.clean);
    expect(byId['junk:windows_temp']!.selectedByDefault, isTrue);
    // Emptying the bin is permanent, so it is never pre-checked.
    expect(byId['junk:recycle_bin']!.tier, CleanerSuggestionTier.clean);
    expect(byId['junk:recycle_bin']!.selectedByDefault, isFalse);
    expect(
      byId['junk:windows_update_cache']!.tier,
      CleanerSuggestionTier.review,
    );
    expect(byId['junk:windows_update_cache']!.selectedByDefault, isFalse);
  });

  group('Downloads leftovers', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('cb_suggest_'));
    tearDown(() => temp.deleteSync(recursive: true));

    File write(String relative, int bytes, DateTime modified) {
      final file = File(p.join(temp.path, relative))
        ..createSync(recursive: true);
      final raf = file.openSync(mode: FileMode.write);
      raf.truncateSync(bytes);
      raf.closeSync();
      file.setLastModifiedSync(modified);
      return file;
    }

    test('finds old, large installers and archives only', () {
      final old = DateTime.now().subtract(const Duration(days: 90));
      final recent = DateTime.now().subtract(const Duration(days: 2));
      write('setup.exe', 20 * _mb, old);
      write(p.join('tools', 'driver.zip'), 8 * _mb, old);
      write('fresh.iso', 50 * _mb, recent);
      write('tiny.msi', 1 * _mb, old);
      write('report.docx', 40 * _mb, old);
      write(p.join('a', 'b', 'deep.zip'), 40 * _mb, old);

      final items = CleanerSuggestionScanner.listDownloadsLeftovers(
        temp.path,
        DateTime.now().subtract(CleanerSuggestionScanner.downloadsMinAge),
      );
      final names = items.map((i) => p.basename(i.path)).toSet();

      expect(names, {'setup.exe', 'driver.zip'});
      expect(items.every((item) => item.isUserSelected), isTrue);

      final suggestion = CleanerSuggestionScanner.downloadsSuggestion(
        temp.path,
        items,
      )!;
      expect(suggestion.tier, CleanerSuggestionTier.review);
      expect(suggestion.selectedByDefault, isFalse);
      expect(suggestion.items.first.path, endsWith('setup.exe'));
      expect(suggestion.folderPath, temp.path);
    });
  });

  test('disk scan adds node_modules, guided causes and personal old files', () {
    final tree = _node(
      r'C:',
      children: [
        _node(
          r'C:\Users\Tester\AppData\Local\Packages\Ubuntu\LocalState\ext4.vhdx',
          size: 30 * _gb,
          file: true,
        ),
        _node(
          r'C:\Users\Tester\dev\site\node_modules',
          children: [
            _node(
              r'C:\Users\Tester\dev\site\node_modules\react.js',
              size: 600 * _mb,
              file: true,
            ),
          ],
        ),
      ],
    );
    FullDiskScanInsight insight(String path) => FullDiskScanInsight(
      name: path.split(r'\').last,
      path: path,
      isFile: true,
      sizeBytes: 2 * _gb,
      lastModified: DateTime.utc(2024, 1, 1),
    );

    final suggestions = CleanerSuggestionScanner.diskScanSuggestions(
      tree,
      [
        insight(r'C:\Users\Tester\Videos\trip.mp4'),
        insight(r'C:\Users\Tester\OneDrive\big.mov'),
        insight(r'C:\Users\Tester\AppData\Local\app.bin'),
        insight(r'C:\Users\Tester\Documents\mail.pst'),
        insight(r'C:\Users\Tester\Downloads\dup.iso'),
        insight(r'C:\Windows\big.log'),
      ],
      excludePaths: {r'C:\USERS\TESTER\DOWNLOADS\DUP.ISO'},
    );
    final byId = {for (final s in suggestions) s.id: s};

    expect(byId['node_modules']!.tier, CleanerSuggestionTier.review);
    expect(byId['node_modules']!.items.single.isUserSelected, isTrue);
    expect(byId['wsl_disk']!.tier, CleanerSuggestionTier.guided);
    expect(byId['wsl_disk']!.items, isEmpty);
    expect(byId['wsl_disk']!.command, 'wsl --shutdown');
    expect(byId['old_large_files']!.items.map((i) => i.path), [
      r'C:\Users\Tester\Videos\trip.mp4',
    ]);
  });

  test('scan merges sources, sorts by tier and skips missing checks', () async {
    final temp = Directory.systemTemp.createTempSync('cb_suggest_scan_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final updates = <CleanerSuggestionProgress>[];
    final scanner = CleanerSuggestionScanner(
      scanJunk: (drives, ids, onProgress) async {
        expect(drives, [r'C:\']);
        expect(ids, contains('recycle_bin'));
        // Two of four folders done; the 250 MB since the last report is
        // credited to the category of this report.
        onProgress(
          const ScanProgress(
            currentPath: r'C:\Users\Tester\AppData\Local\Temp\a.tmp',
            itemsFound: 3,
            bytesFound: 250 * _mb,
            categoryId: 'windows_temp',
            fraction: 0.5,
          ),
        );
        return _junkReport();
      },
      // Model a Windows profile on the scanned drive even on a Linux host.
      // This unique, missing profile has no Downloads folder; system checks
      // also avoid the host's real hiberfil.sys and Windows.old.
      environment: {
        'USERPROFILE': p.windows.join(r'C:\', p.basename(temp.path)),
        'SystemDrive': 'Z:',
      },
    );

    final report = await scanner.scan(
      drivePath: r'C:\',
      diskTree: _node(r'C:', children: [_node(r'C:\x.bin', file: true)]),
      onProgress: updates.add,
    );

    final live = updates.firstWhere((u) => u.itemsFound == 3);
    expect(live.activeSource, 'windows_temp');
    expect(live.sourceBytes['windows_temp'], 250 * _mb);
    expect(live.fraction, greaterThan(0.3));
    expect(live.fraction, lessThan(0.5));
    expect(live.currentPath, endsWith('a.tmp'));
    expect(
      updates.map((u) => u.step).toSet(),
      CleanerSuggestionStep.values.toSet(),
    );
    // Fractions only grow, and the scan ends complete with exact totals.
    for (var i = 1; i < updates.length; i++) {
      expect(
        updates[i].fraction,
        greaterThanOrEqualTo(updates[i - 1].fraction),
      );
    }
    final last = updates.last;
    expect(last.fraction, closeTo(1, 0.0001));
    expect(last.doneSources, containsAll(last.sources));
    expect(last.sourceBytes['windows_temp'], 300 * _mb);
    expect(last.sourceBytes['windows_update_cache'], 900 * _mb);
    expect(last.sources, contains(CleanerSuggestionSource.diskScan));
    expect(last.sources, contains(CleanerSuggestionSource.downloads));
    expect(last.sourceBytes[CleanerSuggestionSource.downloads], 0);
    expect(report.errors, isEmpty);
    expect(report.usedDiskScan, isTrue);
    expect(report.suggestions.first.tier, CleanerSuggestionTier.clean);
    expect(report.suggestions.last.tier, CleanerSuggestionTier.review);
    expect(report.reclaimableBytes, 1400 * _mb);
  });

  test(
    'scan skips Downloads when the profile belongs to another drive',
    () async {
      final updates = <CleanerSuggestionProgress>[];
      final scanner = CleanerSuggestionScanner(
        scanJunk: (_, _, _) async => _junkReport(),
        environment: {'USERPROFILE': r'Z:\Users\Tester', 'SystemDrive': 'Z:'},
      );
      final report = await scanner.scan(
        drivePath: r'C:\',
        diskTree: _node(r'C:'),
        onProgress: updates.add,
      );

      expect(updates.map((u) => u.step).toSet(), {
        CleanerSuggestionStep.junk,
        CleanerSuggestionStep.system,
        CleanerSuggestionStep.diskScan,
      });
      expect(
        updates.last.sources,
        isNot(contains(CleanerSuggestionSource.downloads)),
      );
      expect(updates.last.fraction, closeTo(1, 0.0001));
      expect(report.errors, isEmpty);
    },
  );

  test('disk-tree suggestions leave the UI event loop responsive', () async {
    final tree = _node(
      r'C:',
      children: [
        for (var i = 0; i < 30000; i++)
          _node('C:\\Data\\$i.bin', size: _mb, file: true),
        _node(
          r'C:\dev\site\node_modules',
          children: [
            _node(r'C:\dev\site\node_modules\x.js', size: _mb, file: true),
          ],
        ),
      ],
    );
    final scanner = CleanerSuggestionScanner(
      scanJunk: (_, _, _) async => _junkReport(),
      environment: {'SystemDrive': 'Z:'},
    );
    Timer? heartbeat;
    var ticks = 0;
    late CleanerSuggestionReport report;
    try {
      report = await scanner.scan(
        drivePath: r'C:\',
        diskTree: tree,
        onProgress: (progress) {
          if (progress.step == CleanerSuggestionStep.diskScan) {
            heartbeat ??= Timer.periodic(
              const Duration(milliseconds: 1),
              (_) => ticks++,
            );
          }
        },
      );
    } finally {
      heartbeat?.cancel();
    }
    expect(ticks, greaterThan(0));
    final modules = report.suggestions.singleWhere(
      (s) => s.id == 'node_modules',
    );
    expect(modules.items.single.path, r'C:\dev\site\node_modules');
    expect(modules.items.single.isUserSelected, isTrue);
    expect(modules.selectedByDefault, isFalse);
  });

  test('a junk scan failure is reported, not hidden', () async {
    Future<CleanerSuggestionReport> scanWith(Object error) =>
        CleanerSuggestionScanner(
          scanJunk: (_, _, _) async => throw error,
          environment: {'SystemDrive': 'Z:'},
        ).scan(drivePath: r'D:\', diskTree: _node(r'D:'));

    final busy = await scanWith(CleanerScanBusyError());
    expect(busy.suggestions, isEmpty);
    expect(busy.errors.single.kind, CleanerSuggestionErrorKind.junkScanBusy);

    final failed = await scanWith(StateError('disk gone'));
    expect(
      failed.errors.single.kind,
      CleanerSuggestionErrorKind.junkScanFailed,
    );
    expect(failed.errors.single.detail, contains('disk gone'));
  });

  test('junk scan fraction follows top-level folders and never drops', () {
    final children = {
      r'C:\USERS\T\APPDATA\LOCAL': ['Google', 'Microsoft', 'Temp'],
      r'C:\WINDOWS\TEMP': <String>[],
    };
    final fraction = JunkScanFraction([
      r'C:\Users\T\AppData\Local\',
      r'C:\Windows\Temp',
    ], listChildren: (root) => children[root]!);
    // Weights: 3 folders + 1 for root files, then 0 + 1 => total 5.
    fraction.startGroup(0);
    expect(fraction.at(r'C:\Users\T\AppData\Local\x.log'), 0);
    expect(
      fraction.at(r'C:\Users\T\AppData\Local\Microsoft\Edge\Cache\f_1'),
      closeTo(2 / 5, 1e-9),
    );
    // An earlier folder seen late never moves progress backwards.
    expect(
      fraction.at(r'C:\Users\T\AppData\Local\Google\x'),
      closeTo(2 / 5, 1e-9),
    );
    fraction.startGroup(1);
    expect(fraction.at(r'C:\Windows\Temp\a.tmp'), closeTo(4 / 5, 1e-9));
    fraction.finish();
    expect(fraction.at(''), 1);
  });
}
