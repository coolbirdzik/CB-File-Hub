import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MacCleaner extends DiskCleanerService {
  _MacCleaner() : super.forTesting(fullDiskScanSpawner: spawnFullDiskScan);
  String? scannedPath;
  @override
  Future<List<DriveSpace>> getDriveSpace() async => const [
    DriveSpace(
      path: '/System/Volumes/Data',
      label: 'Macintosh HD',
      totalBytes: 100000,
      freeBytes: 40000,
    ),
  ];
  @override
  Future<FullDiskScanHandle> scanFullDisk({
    required String drivePath,
    int maxDepth = 20,
    int minDisplayEntryBytes = defaultMinDisplayEntryBytes,
    int maxChildrenPerDirectory = defaultMaxChildrenPerDirectory,
  }) async {
    scannedPath = drivePath;
    return FullDiskScanHandle.completed(
      drivePath: drivePath,
      result: FullDiskScanResult(
        root: DiskTreeNode(
          name: 'Data',
          fullPath: drivePath,
          sizeBytes: 300,
          fileCount: 2,
          isExpanded: true,
          children: [
            DiskTreeNode(
              name: 'File',
              fullPath: '$drivePath/File',
              isFile: true,
              sizeBytes: 200,
              fileCount: 1,
            ),
            DiskTreeNode(
              name: 'file',
              fullPath: '$drivePath/file',
              isFile: true,
              sizeBytes: 100,
              fileCount: 1,
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}

void main() {
  testWidgets(
    'macOS exposes disk cleanup, hides Windows Apps and selects exact case',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cleaner = _MacCleaner();
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
          home: Scaffold(body: CbAgentCleanerScreen(cleanerService: cleaner)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cleaner-utility-appInsights')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('cleaner-utility-appLeftovers')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('cleaner-scan-cta')));
      await tester.pumpAndSettle();
      expect(cleaner.scannedPath, '/System/Volumes/Data');
      await tester.tap(
        find.byKey(
          const ValueKey('cleaner-tree-row-idle-/System/Volumes/Data/file'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cleaner-review-and-clean')));
      await tester.pumpAndSettle();
      expect(
        cleaner.pendingCleanupItems!.single.path,
        '/System/Volumes/Data/file',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
