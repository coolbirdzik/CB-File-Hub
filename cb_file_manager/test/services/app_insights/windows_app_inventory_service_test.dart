import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_insights_platform.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_inventory_parser.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_inventory_service.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_usage_matcher.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_usage_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsAppInventoryParser', () {
    const parser = WindowsAppInventoryParser();

    test(
      'filters hidden entries and deterministically merges registry views',
      () {
        final apps = parser.parseWin32Entries(<Map<String, Object?>>[
          <String, Object?>{
            'registryRoot': 'HKLM',
            'registryView': '32',
            'registryKeyName': '{11111111-2222-3333-4444-555555555555}',
            'displayName': 'Example App',
            'publisher': 'Example Inc.',
            'displayVersion': '1.0',
          },
          <String, Object?>{
            'registryRoot': 'HKLM',
            'registryView': '64',
            'registryKeyName': '{11111111-2222-3333-4444-555555555555}',
            'displayName': 'Example App',
            'publisher': 'Example Inc.',
            'displayVersion': '2.0',
            'installLocation': r'C:\Program Files\Example',
            'displayIcon': r'"C:\Program Files\Example\example.exe",0',
            'uninstallString': 'uninstall.exe',
            'estimatedSizeKb': 2048,
            'installDate': '20260731',
          },
          <String, Object?>{
            'registryKeyName': 'system',
            'displayName': 'System Component',
            'systemComponent': 1,
          },
          <String, Object?>{
            'registryKeyName': 'child',
            'displayName': 'Child Feature',
            'parentKeyName': 'parent',
          },
          <String, Object?>{
            'registryKeyName': 'update',
            'displayName': 'Security Update for Windows (KB5030000)',
            'releaseType': 'Security Update',
          },
        ]);

        expect(apps, hasLength(1));
        final app = apps.single;
        expect(app.id, 'win32:{11111111-2222-3333-4444-555555555555}');
        expect(app.version, '2.0');
        expect(app.installLocation, r'C:\Program Files\Example');
        expect(app.displayIconPath, r'C:\Program Files\Example\example.exe');
        expect(app.executablePaths, <String>[
          r'C:\Program Files\Example\example.exe',
        ]);
        expect(app.estimatedSizeBytes, 2 * 1024 * 1024);
        expect(app.canManage, isTrue);
        expect(app.installedOrUpdatedAt, DateTime(2026, 7, 31));
      },
    );

    test('deduplicates non-MSI entries by name publisher and install path', () {
      final entries = <Map<String, Object?>>[
        <String, Object?>{
          'registryRoot': 'HKLM',
          'registryView': '32',
          'registryKeyName': 'Vendor.App.x86',
          'displayName': 'Vendor App',
          'publisher': 'Vendor',
          'installLocation': r'C:\Apps\Vendor',
        },
        <String, Object?>{
          'registryRoot': 'HKCU',
          'registryView': '64',
          'registryKeyName': 'Vendor App',
          'displayName': ' vendor  app ',
          'publisher': 'VENDOR',
          'installLocation': r'C:/Apps/Vendor/',
        },
      ];

      final forward = parser.parseWin32Entries(entries);
      final reverse = parser.parseWin32Entries(entries.reversed);
      expect(forward, hasLength(1));
      expect(reverse, hasLength(1));
      expect(forward.single.id, reverse.single.id);
    });

    test('keeps only launchable non-framework MSIX packages', () {
      final apps = parser.parseMsixEntries(<Map<String, Object?>>[
        <String, Object?>{
          'packageName': 'Contoso.App',
          'packageFamilyName': 'Contoso.App_123',
          'displayName': 'Contoso',
          'version': '1.2.3.4',
          'installedDate': '2026-07-30T10:20:30Z',
          'isLaunchable': true,
          'installLocation': r'C:\Program Files\WindowsApps\Contoso',
        },
        <String, Object?>{
          'packageName': 'Framework',
          'packageFamilyName': 'Framework_123',
          'displayName': 'Framework',
          'isLaunchable': true,
          'isFramework': true,
        },
        <String, Object?>{
          'packageName': 'BackgroundOnly',
          'packageFamilyName': 'BackgroundOnly_123',
          'displayName': 'Background Only',
          'isLaunchable': false,
        },
      ]);

      expect(apps, hasLength(1));
      expect(apps.single.id, 'msix:contoso.app_123');
      expect(apps.single.source, InstalledAppSource.msix);
      expect(
        apps.single.installedOrUpdatedAt,
        DateTime.utc(2026, 7, 30, 10, 20, 30),
      );
    });
  });

  group('WindowsAppUsageParser', () {
    const parser = WindowsAppUsageParser();

    test('decodes ROT13 UserAssist names', () {
      expect(
        parser.decodeRot13(r'P:\Hfref\Npr\Ncc.rkr'),
        r'C:\Users\Ace\App.exe',
      );
    });

    test('reads FILETIME at offset 60 from a modern 72-byte record', () {
      final expected = DateTime.utc(2026, 7, 31, 12, 30, 15);
      final data = _userAssistData(expected);

      expect(parser.parseModernUserAssistLastOpened(data), expected);
      expect(
        parser.parseUserAssistRecord(r'P:\Ncc.rkr', data)?.decodedTarget,
        r'C:\App.exe',
      );
    });

    test('rejects short and zero-FILETIME records', () {
      expect(parser.parseModernUserAssistLastOpened(Uint8List(71)), isNull);
      expect(parser.parseModernUserAssistLastOpened(Uint8List(72)), isNull);
    });

    test('parses executable names with hyphens from Prefetch files', () {
      expect(
        parser.executableNameFromPrefetch('MY-APP.EXE-12ABCDEF.pf'),
        'MY-APP.EXE',
      );
      expect(parser.executableNameFromPrefetch('not-prefetch.txt'), isNull);
    });
  });

  group('WindowsAppUsageMatcher', () {
    const matcher = WindowsAppUsageMatcher();
    final now = DateTime.utc(2026, 8, 1);

    test('does not use ambiguous Prefetch executable names', () {
      final apps = <InstalledAppInfo>[
        const InstalledAppInfo(
          id: 'one',
          displayName: 'One',
          source: InstalledAppSource.win32,
          executablePaths: <String>[r'C:\One\app.exe'],
        ),
        const InstalledAppInfo(
          id: 'two',
          displayName: 'Two',
          source: InstalledAppSource.win32,
          executablePaths: <String>[r'D:\Two\app.exe'],
        ),
      ];

      final evidence = matcher.match(
        apps: apps,
        userAssistRecords: const <ParsedUserAssistRecord>[],
        prefetchRecords: <PrefetchUsageRecord>[
          PrefetchUsageRecord(
            executableName: 'APP.EXE',
            lastModified: now.subtract(const Duration(days: 1)),
          ),
        ],
        now: now,
      );

      expect(evidence['one']!.isKnown, isFalse);
      expect(evidence['two']!.isKnown, isFalse);
    });

    test('prefers newer evidence and ignores future timestamps', () {
      const app = InstalledAppInfo(
        id: 'one',
        displayName: 'One',
        source: InstalledAppSource.win32,
        installLocation: r'C:\One',
        executablePaths: <String>[r'C:\One\one.exe'],
      );
      final evidence = matcher.match(
        apps: const <InstalledAppInfo>[app],
        userAssistRecords: <ParsedUserAssistRecord>[
          ParsedUserAssistRecord(
            decodedTarget: r'C:\One\one.exe',
            lastOpenedAt: now.subtract(const Duration(days: 2)),
          ),
          ParsedUserAssistRecord(
            decodedTarget: r'C:\One\one.exe',
            lastOpenedAt: now.add(const Duration(days: 1)),
          ),
        ],
        prefetchRecords: <PrefetchUsageRecord>[
          PrefetchUsageRecord(
            executableName: 'ONE.EXE',
            lastModified: now.subtract(const Duration(days: 1)),
          ),
        ],
        now: now,
      );

      expect(evidence['one']!.source, AppUsageSource.prefetch);
      expect(
        evidence['one']!.lastOpenedAt,
        now.subtract(const Duration(days: 1)),
      );
    });

    test('unknown evidence is not stale at the 180 day threshold', () {
      const unknown = AppUsageEvidence();
      final old = AppUsageEvidence(
        lastOpenedAt: now.subtract(const Duration(days: 180)),
      );

      expect(
        unknown.isStale(now: now, threshold: const Duration(days: 180)),
        isFalse,
      );
      expect(
        old.isStale(now: now, threshold: const Duration(days: 180)),
        isTrue,
      );
    });
  });

  test('service exposes inventory and usage through the stable API', () async {
    final now = DateTime.utc(2026, 8, 1);
    final source = _FakeDataSource(
      win32: const WindowsRawAppInsightsResult(
        records: <Map<String, Object?>>[
          <String, Object?>{
            'registryKeyName': 'example',
            'displayName': 'Example',
            'displayIcon': r'C:\Example\example.exe',
          },
        ],
      ),
      msix: const WindowsRawAppInsightsResult(),
      userAssist: WindowsRawAppInsightsResult(
        records: <Map<String, Object?>>[
          <String, Object?>{
            'encodedName': r'P:\Rknzcyr\rknzcyr.rkr',
            'data': _userAssistData(now.subtract(const Duration(days: 3))),
          },
        ],
      ),
    );
    final service = WindowsAppInventoryService(
      dataSource: source,
      prefetchDirectory: Directory(
        r'C:\this-path-does-not-exist\cb-app-insights-test',
      ),
      now: () => now,
    );

    final inventory = await service.loadInventory();
    final usage = await service.loadUsageEvidence(inventory.apps);

    expect(inventory.apps, hasLength(1));
    expect(usage[inventory.apps.single.id]!.source, AppUsageSource.userAssist);
  });

  test(
    'service publishes each inventory source as soon as it completes',
    () async {
      final source = _ControlledInventoryDataSource();
      final service = WindowsAppInventoryService(dataSource: source);
      final snapshots = <InstalledAppInventoryResult>[];

      final inventoryFuture = service.loadInventory(onSnapshot: snapshots.add);
      source.win32.complete(
        const WindowsRawAppInsightsResult(
          records: <Map<String, Object?>>[
            <String, Object?>{
              'registryKeyName': 'example',
              'displayName': 'Example Win32',
            },
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(snapshots, hasLength(1));
      expect(snapshots.single.apps.single.displayName, 'Example Win32');
      expect(snapshots.single.isPartial, isTrue);
      expect(
        snapshots.single.warnings,
        contains('MSIX app inventory is still loading.'),
      );

      source.msix.complete(
        const WindowsRawAppInsightsResult(
          records: <Map<String, Object?>>[
            <String, Object?>{
              'packageName': 'Contoso.App',
              'packageFamilyName': 'Contoso.App_123',
              'displayName': 'Contoso Store',
              'isLaunchable': true,
            },
          ],
        ),
      );
      final inventory = await inventoryFuture;

      expect(snapshots, hasLength(2));
      expect(snapshots.last.apps, hasLength(2));
      expect(inventory.apps, hasLength(2));
      expect(inventory.isPartial, isFalse);
    },
  );
}

Uint8List _userAssistData(DateTime timestamp) {
  const windowsToUnixEpochMicroseconds = 11644473600000000;
  final fileTime =
      (timestamp.toUtc().microsecondsSinceEpoch +
          windowsToUnixEpochMicroseconds) *
      10;
  final data = Uint8List(72);
  final bytes = ByteData.sublistView(data);
  bytes.setUint32(60, fileTime & 0xffffffff, Endian.little);
  bytes.setUint32(64, fileTime >> 32, Endian.little);
  return data;
}

class _FakeDataSource implements WindowsAppInsightsDataSource {
  final WindowsRawAppInsightsResult win32;
  final WindowsRawAppInsightsResult msix;
  final WindowsRawAppInsightsResult userAssist;

  const _FakeDataSource({
    this.win32 = const WindowsRawAppInsightsResult(),
    this.msix = const WindowsRawAppInsightsResult(),
    this.userAssist = const WindowsRawAppInsightsResult(),
  });

  @override
  Future<WindowsRawAppInsightsResult> readMsixInventory() async => msix;

  @override
  Future<WindowsRawAppInsightsResult> readUserAssist() async => userAssist;

  @override
  Future<WindowsRawAppInsightsResult> readWin32Inventory() async => win32;

  @override
  Future<Map<String, String>> resolveUserAssistTargets(
    List<String> targets,
  ) async => <String, String>{for (final target in targets) target: target};
}

class _ControlledInventoryDataSource implements WindowsAppInsightsDataSource {
  final Completer<WindowsRawAppInsightsResult> win32 =
      Completer<WindowsRawAppInsightsResult>();
  final Completer<WindowsRawAppInsightsResult> msix =
      Completer<WindowsRawAppInsightsResult>();

  @override
  Future<WindowsRawAppInsightsResult> readMsixInventory() => msix.future;

  @override
  Future<WindowsRawAppInsightsResult> readUserAssist() async =>
      const WindowsRawAppInsightsResult();

  @override
  Future<WindowsRawAppInsightsResult> readWin32Inventory() => win32.future;

  @override
  Future<Map<String, String>> resolveUserAssistTargets(
    List<String> targets,
  ) async => <String, String>{};
}
