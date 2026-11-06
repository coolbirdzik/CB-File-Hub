import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/windows_app_inventory_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _app = InstalledAppInfo(
  id: 'alpha',
  displayName: 'Alpha Editor',
  source: InstalledAppSource.win32,
  uninstallCommand: 'uninstall.exe',
  installLocation: r'C:\Apps\Alpha',
  estimatedSizeBytes: 1024,
);

class _Inventory extends WindowsAppInventoryService {
  final gate = Completer<void>();
  bool hangUsage = false;
  final usageGate = Completer<Map<String, AppUsageEvidence>>();
  @override
  Future<InstalledAppInventoryResult> loadInventory({
    void Function(InstalledAppInventoryResult)? onSnapshot,
  }) async {
    onSnapshot?.call(
      const InstalledAppInventoryResult(apps: [_app], isPartial: true),
    );
    await gate.future;
    return const InstalledAppInventoryResult(
      apps: [
        _app,
        InstalledAppInfo(
          id: 'late',
          displayName: 'Late App',
          source: InstalledAppSource.win32,
        ),
      ],
    );
  }

  @override
  Future<Map<String, AppUsageEvidence>> loadUsageEvidence(
    List<InstalledAppInfo> apps,
  ) async => hangUsage ? usageGate.future : const {};
}

class _Cleaner extends DiskCleanerService {
  _Cleaner() : super.forTesting(fullDiskScanSpawner: spawnFullDiskScan);
  int diskScans = 0;
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
    diskScans++;
    throw StateError('Apps must not start a full-disk scan');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> open(
    WidgetTester tester,
    _Cleaner cleaner,
    _Inventory inventory,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('vi')],
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
    await tester.tap(find.text('Apps'));
    // The running indicator is intentionally indeterminate; avoid pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
    'partial inventory exposes uninstall; cancelling keeps apps and ignores late results',
    (tester) async {
      final cleaner = _Cleaner();
      final inventory = _Inventory();
      await open(tester, cleaner, inventory);
      final uninstall = find.byKey(
        const ValueKey('cleaner-app-uninstall-alpha'),
      );
      expect(uninstall, findsOneWidget);
      expect(tester.widget<FilledButton>(uninstall).onPressed, isNotNull);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cleaner-apps-summary-footprint')),
          matching: find.textContaining('≈ '),
        ),
        findsOneWidget,
      );
      expect(cleaner.diskScans, 0);
      await tester.tap(find.byKey(const ValueKey('cleaner-apps-rescan')));
      await tester.pumpAndSettle();
      inventory.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Late App'), findsNothing);
      expect(uninstall, findsOneWidget);
      expect(cleaner.diskScans, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'optional usage timeout ends loading and refresh never scans the drive',
    (tester) async {
      final cleaner = _Cleaner();
      final inventory = _Inventory()..hangUsage = true;
      await open(tester, cleaner, inventory);
      inventory.gate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
      expect(
        find.byKey(const ValueKey('cleaner-app-uninstall-alpha')),
        findsOneWidget,
      );
      expect(cleaner.diskScans, 0);
      await tester.tap(find.byKey(const ValueKey('cleaner-apps-rescan')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.stop_rounded), findsNothing);
      expect(cleaner.diskScans, 0);
      inventory.usageGate.complete(const {});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
