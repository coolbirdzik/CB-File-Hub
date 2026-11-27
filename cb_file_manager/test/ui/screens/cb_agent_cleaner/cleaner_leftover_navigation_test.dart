import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_inventory_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _inventoryResult = InstalledAppInventoryResult(
  apps: [
    InstalledAppInfo(
      id: 'fixture-app',
      displayName: 'Fixture App',
      source: InstalledAppSource.win32,
    ),
  ],
);

class _ControlledInventory extends WindowsAppInventoryService {
  int calls = 0;
  final pending = <Completer<InstalledAppInventoryResult>>[];

  @override
  Future<InstalledAppInventoryResult> loadInventory({
    void Function(InstalledAppInventoryResult)? onSnapshot,
  }) async {
    calls++;
    // Smart Clean prefetches the app inventory once on screen startup.
    if (calls == 1) return _inventoryResult;
    final gate = Completer<InstalledAppInventoryResult>();
    pending.add(gate);
    return gate.future;
  }
}

class _Cleaner extends DiskCleanerService {
  _Cleaner() : super.forTesting(fullDiskScanSpawner: spawnFullDiskScan);

  int fullDiskScans = 0;

  @override
  Stream<void> get driveChanges => const Stream.empty();

  @override
  Future<List<DriveSpace>> getDriveSpace() async => const [
    DriveSpace(path: r'C:\', label: 'Test', totalBytes: 10000, freeBytes: 5000),
  ];

  @override
  Future<FullDiskScanHandle> scanFullDisk({
    required String drivePath,
    int maxDepth = 20,
    int minDisplayEntryBytes = defaultMinDisplayEntryBytes,
    int maxChildrenPerDirectory = defaultMaxChildrenPerDirectory,
  }) async {
    fullDiskScans++;
    throw StateError('App Leftovers must not start a Disk Usage scan');
  }
}

void main() {
  testWidgets(
    'App Leftovers opens idle until a scan mode is explicitly chosen',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cleaner = _Cleaner();
      final inventory = _ControlledInventory();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: CbAgentCleanerScreen(
            cleanerService: cleaner,
            appInventoryService: inventory,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final startupReads = inventory.calls;
      expect(startupReads, 1);

      final leftoverUtility = find.byKey(
        const ValueKey('cleaner-utility-appLeftovers'),
      );
      final intro = find.byKey(const ValueKey('cleaner-leftovers-intro'));
      final normalScan = find.byKey(const ValueKey('cleaner-leftovers-scan'));
      final deepScan = find.byKey(
        const ValueKey('cleaner-leftovers-deep-scan'),
      );
      final loading = find.byKey(const ValueKey('cleaner-leftovers-loading'));

      Future<void> openLeftovers() async {
        await tester.tap(leftoverUtility);
        // Do not settle indefinitely if a regression starts an automatic scan.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(inventory.calls, startupReads);
        expect(intro, findsOneWidget);
        expect(normalScan, findsOneWidget);
        expect(deepScan, findsOneWidget);
        expect(loading, findsNothing);
      }

      await openLeftovers();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-utility-diskCleaner')),
      );
      await tester.pumpAndSettle();
      await openLeftovers();

      // Both modes start a *new* inventory read only from their scan button.
      for (final (index, button) in [normalScan, deepScan].indexed) {
        await tester.tap(button);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(inventory.calls, startupReads + index + 1);
        expect(loading, findsOneWidget);
        expect(intro, findsNothing);

        // Cancel before releasing the fake inventory so no real directory
        // discovery can run. A late inventory result must not restart a scan.
        await tester.tap(
          find.byKey(const ValueKey('cleaner-leftovers-rescan')),
        );
        await tester.pumpAndSettle();
        inventory.pending[index].complete(_inventoryResult);
        await tester.pumpAndSettle();
        expect(intro, findsOneWidget);
        expect(loading, findsNothing);
        expect(inventory.calls, startupReads + index + 1);
      }

      expect(cleaner.fullDiskScans, 0);
      expect(tester.takeException(), isNull);
    },
    // The scanner's choice of filesystem and the Deep Scan button depend on
    // Platform.isWindows rather than only Flutter's target-platform override.
    skip: !Platform.isWindows,
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
