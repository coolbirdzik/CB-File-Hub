import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_storage_analyzer.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:flutter_test/flutter_test.dart';

const _mib = 1024 * 1024;

DiskTreeNode _directory(
  String path,
  int sizeBytes, [
  List<DiskTreeNode> children = const <DiskTreeNode>[],
  String? junkCategoryId,
]) {
  return DiskTreeNode(
    name: path.split(r'\').last,
    fullPath: path,
    sizeBytes: sizeBytes,
    children: children,
    junkCategoryId: junkCategoryId,
  );
}

void main() {
  test('uses a Windows estimate when a partial path has no measured bytes', () {
    const profile = AppStorageProfile(
      app: InstalledAppInfo(
        id: 'estimated-partial',
        displayName: 'Estimated Partial App',
        source: InstalledAppSource.win32,
        estimatedSizeBytes: 2048,
      ),
      entries: <AppStorageEntry>[
        AppStorageEntry(
          path: r'C:\Apps\EstimatedPartial',
          kind: AppStorageKind.install,
          sizeBytes: 0,
          measurementQuality: MeasurementQuality.partial,
          attributionConfidence: AttributionConfidence.confirmed,
        ),
      ],
    );

    expect(profile.bestKnownSizeBytes, 2048);
    expect(profile.confirmedSizeBytes, 0);
    expect(profile.measurementQuality, MeasurementQuality.estimated);
  });

  group('Windows path matching', () {
    test('normalizes case, separators, device prefixes, and roots', () {
      expect(
        AppStorageAnalyzer.normalizeWindowsPath(
          r'\\?\c:/Program Files/Example/',
        ),
        r'C:\PROGRAM FILES\EXAMPLE',
      );
      expect(AppStorageAnalyzer.normalizeWindowsPath('c:'), r'C:\');
    });

    test('uses separator boundaries instead of string prefixes', () {
      expect(
        AppStorageAnalyzer.isSameOrDescendant(
          r'C:\Apps\Alpha\Cache',
          r'c:\apps\alpha',
        ),
        isTrue,
      );
      expect(
        AppStorageAnalyzer.isSameOrDescendant(
          r'C:\Apps\Alphabet',
          r'C:\Apps\Alpha',
        ),
        isFalse,
      );
    });
  });

  test('attributes measured roots without rescanning or double counting', () {
    final discordCache = _directory(
      r'C:\Users\me\AppData\Roaming\discord\Cache',
      100,
      const <DiskTreeNode>[],
      'app_cache',
    );
    final discord = _directory(
      r'C:\Users\me\AppData\Roaming\discord',
      1000,
      <DiskTreeNode>[
        discordCache,
        _directory(r'C:\Users\me\AppData\Roaming\discord\Data', 900),
      ],
    );
    final roaming = _directory(
      r'C:\Users\me\AppData\Roaming',
      1000,
      <DiskTreeNode>[discord],
    );
    final package = _directory(
      r'C:\Users\me\AppData\Local\Packages\Example.Store_123',
      300,
    );
    final packages = _directory(
      r'C:\Users\me\AppData\Local\Packages',
      300,
      <DiskTreeNode>[package],
    );
    final orphan = _directory(
      r'C:\Users\me\AppData\Local\OrphanHuge',
      500 * _mib,
    );
    final small = _directory(
      r'C:\Users\me\AppData\Local\Small',
      500 * _mib - 1,
    );
    final local = _directory(
      r'C:\Users\me\AppData\Local',
      package.sizeBytes + orphan.sizeBytes + small.sizeBytes,
      <DiskTreeNode>[packages, orphan, small],
    );
    final appData = _directory(
      r'C:\Users\me\AppData',
      roaming.sizeBytes + local.sizeBytes,
      <DiskTreeNode>[roaming, local],
    );
    final user = _directory(r'C:\Users\me', appData.sizeBytes, <DiskTreeNode>[
      appData,
    ]);
    final users = _directory(r'C:\Users', user.sizeBytes, <DiskTreeNode>[user]);

    final sharedSuite = _directory(r'C:\Program Files\SharedSuite', 600 * _mib);
    final partialApp = _directory(r'C:\Program Files\PartialApp', 1000);
    final iconApp = _directory(r'C:\Portable\IconApp', 400);
    final programFiles = _directory(
      r'C:\Program Files',
      sharedSuite.sizeBytes + partialApp.sizeBytes,
      <DiskTreeNode>[sharedSuite, partialApp],
    );
    final portable = _directory(
      r'C:\Portable',
      iconApp.sizeBytes,
      <DiskTreeNode>[iconApp],
    );
    final root = _directory(
      r'C:\',
      users.sizeBytes + programFiles.sizeBytes + portable.sizeBytes,
      <DiskTreeNode>[users, programFiles, portable],
    );

    const inventory = InstalledAppInventoryResult(
      apps: <InstalledAppInfo>[
        InstalledAppInfo(
          id: 'discord',
          displayName: 'Discord',
          source: InstalledAppSource.win32,
          installLocation: r'C:\Users\me\AppData\Roaming\discord',
        ),
        InstalledAppInfo(
          id: 'store',
          displayName: 'Example Store App',
          source: InstalledAppSource.msix,
          packageFamilyName: 'Example.Store_123',
        ),
        InstalledAppInfo(
          id: 'shared-a',
          displayName: 'Shared A',
          source: InstalledAppSource.win32,
          installLocation: r'C:\Program Files\SharedSuite',
        ),
        InstalledAppInfo(
          id: 'shared-b',
          displayName: 'Shared B',
          source: InstalledAppSource.win32,
          installLocation: r'c:\program files\sharedsuite\',
        ),
        InstalledAppInfo(
          id: 'partial',
          displayName: 'Partial App',
          source: InstalledAppSource.win32,
          installLocation: r'C:\Program Files\PartialApp',
        ),
        InstalledAppInfo(
          id: 'icon',
          displayName: 'Icon App',
          source: InstalledAppSource.win32,
          displayIconPath: r'"C:\Portable\IconApp\icon.exe",0',
        ),
        InstalledAppInfo(
          id: 'estimate',
          displayName: 'Estimated App',
          source: InstalledAppSource.win32,
          installLocation: r'C:\Missing\EstimatedApp',
          estimatedSizeBytes: 1234,
        ),
      ],
      warnings: <String>['MSIX inventory fallback was partial.'],
      isPartial: true,
    );
    final scanResult = FullDiskScanResult(
      root: root,
      duration: const Duration(seconds: 1),
      coverageIssues: const <FullDiskScanCoverageIssue>[
        FullDiskScanCoverageIssue(
          path: r'C:\Program Files\PartialApp\Restricted',
          reason: FullDiskScanCoverageIssueReason.reparsePoint,
        ),
      ],
    );
    const usage = AppUsageEvidence(
      lastOpenedAt: null,
      source: AppUsageSource.userAssist,
      confidence: UsageEvidenceConfidence.high,
    );

    final report = const AppStorageAnalyzer().analyzeInventory(
      scanResult: scanResult,
      inventory: inventory,
      usageByAppId: const <String, AppUsageEvidence>{'discord': usage},
      environment: const <String, String>{
        'SYSTEMDRIVE': r'C:',
        'APPDATA': r'C:\Users\me\AppData\Roaming',
        'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
        'PROGRAMDATA': r'C:\ProgramData',
      },
      generatedAt: DateTime(2026, 8, 1),
    );

    expect(report.isPartial, isTrue);
    expect(report.warnings, contains('MSIX inventory fallback was partial.'));

    final discordProfile = report.findApp('discord')!;
    expect(discordProfile.confirmedSizeBytes, 1000);
    expect(discordProfile.cleanableBytes, 100);
    expect(discordProfile.usage, same(usage));
    expect(
      discordProfile.entries.map((entry) => entry.kind),
      containsAll(<AppStorageKind>[
        AppStorageKind.install,
        AppStorageKind.cache,
      ]),
    );

    final reviewItems = const AppStorageAnalyzer().buildCleanableReviewItems(
      discordProfile,
      environment: const <String, String>{
        'APPDATA': r'C:\Users\me\AppData\Roaming',
      },
    );
    expect(reviewItems, hasLength(1));
    expect(reviewItems.single.path, discordCache.fullPath);
    expect(reviewItems.single.categoryId, 'app_cache');
    expect(reviewItems.single.isContainerOnly, isTrue);
    expect(reviewItems.single.isUserSelected, isFalse);

    expect(report.findApp('store')!.confirmedSizeBytes, 300);
    expect(
      report.findApp('partial')!.entries.single.measurementQuality,
      MeasurementQuality.partial,
    );
    expect(
      report.findApp('icon')!.entries.single.attributionConfidence,
      AttributionConfidence.likely,
    );
    expect(
      report.findApp('estimate')!.measurementQuality,
      MeasurementQuality.estimated,
    );

    expect(
      report.sharedOrUnattributed.map(
        (entry) => AppStorageAnalyzer.normalizeWindowsPath(entry.path),
      ),
      containsAll(<String>[
        r'C:\PROGRAM FILES\SHAREDSUITE',
        r'C:\USERS\ME\APPDATA\LOCAL\ORPHANHUGE',
      ]),
    );
    expect(
      report.sharedOrUnattributed.any(
        (entry) => entry.path.toLowerCase().endsWith(r'\small'),
      ),
      isFalse,
    );
  });

  test('legacy inaccessible paths still make overlapping storage partial', () {
    final appNode = _directory(r'C:\Apps\Legacy', 42);
    final appsNode = _directory(r'C:\Apps', 42, <DiskTreeNode>[appNode]);
    final root = _directory(r'C:\', 42, <DiskTreeNode>[appsNode]);
    final result = FullDiskScanResult(
      root: root,
      duration: Duration.zero,
      inaccessible: const <String>[r'C:\Apps\Legacy\Protected'],
    );

    final report = const AppStorageAnalyzer().analyze(
      root: root,
      scanResult: result,
      apps: const <InstalledAppInfo>[
        InstalledAppInfo(
          id: 'legacy',
          displayName: 'Legacy',
          source: InstalledAppSource.win32,
          installLocation: r'C:\Apps\Legacy',
        ),
      ],
      environment: const <String, String>{'SYSTEMDRIVE': r'C:'},
    );

    expect(result.isPartial, isTrue);
    expect(
      report.findApp('legacy')!.measurementQuality,
      MeasurementQuality.partial,
    );
  });

  test(
    'keeps progressive scan measurements visible but marks them partial',
    () {
      final appNode = _directory(r'C:\Apps\Growing', 128);
      final root = _directory(r'C:\', 128, <DiskTreeNode>[appNode]);
      final result = FullDiskScanResult(
        root: root,
        duration: Duration.zero,
        coverageIssues: const <FullDiskScanCoverageIssue>[
          FullDiskScanCoverageIssue(
            path: r'C:\',
            reason: FullDiskScanCoverageIssueReason.scanInProgress,
          ),
        ],
      );

      final report = const AppStorageAnalyzer().analyze(
        root: root,
        scanResult: result,
        apps: const <InstalledAppInfo>[
          InstalledAppInfo(
            id: 'growing',
            displayName: 'Growing App',
            source: InstalledAppSource.win32,
            installLocation: r'C:\Apps\Growing',
          ),
        ],
        environment: const <String, String>{'SYSTEMDRIVE': r'C:'},
      );

      expect(report.isPartial, isTrue);
      expect(report.findApp('growing')!.confirmedSizeBytes, 128);
      expect(
        report.findApp('growing')!.measurementQuality,
        MeasurementQuality.partial,
      );
    },
  );

  test('an owned rule chooses a unique exact app over a related runtime', () {
    final cache = _directory(
      r'C:\Users\me\AppData\Local\Microsoft\Edge\User Data\Default\GPUCache',
      99,
      const <DiskTreeNode>[],
      'browser_cache',
    );
    final root = _directory(r'C:\', 99, <DiskTreeNode>[cache]);
    final result = FullDiskScanResult(root: root, duration: Duration.zero);

    final report = const AppStorageAnalyzer().analyze(
      root: root,
      scanResult: result,
      apps: const <InstalledAppInfo>[
        InstalledAppInfo(
          id: 'edge',
          displayName: 'Microsoft Edge',
          source: InstalledAppSource.win32,
        ),
        InstalledAppInfo(
          id: 'webview',
          displayName: 'Microsoft Edge WebView2 Runtime',
          source: InstalledAppSource.win32,
        ),
      ],
      environment: const <String, String>{
        'SYSTEMDRIVE': r'C:',
        'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
      },
    );

    expect(report.findApp('edge')!.cleanableBytes, 99);
    expect(report.findApp('webview')!.cleanableBytes, 0);
  });
}
