import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _gb = 1024 * 1024 * 1024;

class _ObservedFolder extends DiskTreeNode {
  _ObservedFolder()
    : super(
        name: 'Keep',
        fullPath: r'C:\Archive\Keep',
        sizeBytes: _gb,
        fileCount: 1,
        children: [
          DiskTreeNode(
            name: 'keep.mkv',
            fullPath: r'C:\Archive\Keep\keep.mkv',
            isFile: true,
            sizeBytes: _gb,
            fileCount: 1,
          ),
        ],
      );

  int childrenReads = 0;

  @override
  List<DiskTreeNode> get children {
    childrenReads++;
    return super.children;
  }
}

class _Cleaner extends DiskCleanerService {
  _Cleaner() : super.forTesting(fullDiskScanSpawner: spawnFullDiskScan);

  final removed = DiskTreeNode(
    name: 'remove.iso',
    fullPath: r'C:\remove.iso',
    isFile: true,
    sizeBytes: 2 * _gb,
    fileCount: 1,
  );
  final kept = _ObservedFolder();
  late final root = DiskTreeNode(
    name: r'C:\',
    fullPath: r'C:\',
    sizeBytes: 3 * _gb,
    fileCount: 2,
    isExpanded: true,
    children: [
      removed,
      DiskTreeNode(
        name: 'Archive',
        fullPath: r'C:\Archive',
        sizeBytes: _gb,
        fileCount: 1,
        children: [kept],
      ),
    ],
  );
  int scans = 0;
  final requests = <({List<JunkItem> items, bool permanent})>[];
  bool failDelete = false;
  bool requiresAdmin = false;
  final failureActions = <CleanFailureAction>[];

  @override
  Future<List<DriveSpace>> getDriveSpace() async => const [
    DriveSpace(
      path: r'C:\',
      label: 'Test',
      totalBytes: 10 * _gb,
      freeBytes: 7 * _gb,
    ),
  ];

  @override
  FullDiskScanResult? cachedFullScanResult(String drivePath) => null;

  @override
  Future<FullDiskScanHandle> scanFullDisk({
    required String drivePath,
    int maxDepth = 20,
    int minDisplayEntryBytes = defaultMinDisplayEntryBytes,
    int maxChildrenPerDirectory = defaultMaxChildrenPerDirectory,
  }) async {
    scans++;
    return FullDiskScanHandle.completed(
      drivePath: drivePath,
      result: FullDiskScanResult(root: root, duration: Duration.zero),
    );
  }

  @override
  Future<CleanReport> cleanJunk({
    required List<JunkItem> items,
    required bool permanent,
    void Function(int done, int total, String? currentPath)? onProgress,
    Future<CleanFailureAction> Function(CleanFailureDetails details)?
    onDeleteFailure,
  }) async {
    requests.add((items: items, permanent: permanent));
    if (failDelete && onDeleteFailure != null) {
      failureActions.add(
        await onDeleteFailure(
          CleanFailureDetails(
            item: items.first,
            reason: 'Delete failed',
            isInUse: false,
            blockedPath: null,
            permanent: permanent,
            canRetryAsAdministrator: requiresAdmin,
          ),
        ),
      );
    }
    return CleanReport(
      freedBytes: items.fold(0, (sum, item) => sum + item.sizeBytes),
      succeeded: items.map((item) => item.path).toList(),
      failed: const {},
      skippedUnsafe: const [],
      skippedInUse: const [],
      wasPermanent: permanent,
    );
  }
}

Future<void> _pumpCleaner(
  WidgetTester tester,
  _Cleaner cleaner, {
  String languageCode = 'en',
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(languageCode),
      supportedLocales: const [Locale('en'), Locale('vi')],
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
  await tester.tap(find.byKey(const ValueKey('cleaner-scan-cta')));
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester) async {
  await tester.tap(
    find.byKey(const ValueKey(r'cleaner-tree-row-idle-C:\remove.iso')),
  );
  await tester.pumpAndSettle();
}

Future<void> _finishCleanup(WidgetTester tester) async {
  await tester.pump();
  final deadline = Stopwatch()..start();
  // Dashboard diagnosis now runs in a real isolate; allow its port messages
  // to arrive while pumping the progress UI under the widget test clock.
  while (find
      .byKey(const ValueKey('cleaner-cleaning-progress'))
      .evaluate()
      .isNotEmpty) {
    if (deadline.elapsed > const Duration(seconds: 10)) {
      fail('Cleanup did not finish');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final languageCode in ['en', 'vi']) {
    testWidgets(
      'system files stay visible and cannot be deleted ($languageCode)',
      (tester) async {
        final cleaner = _Cleaner();
        final pagefile = DiskTreeNode(
          name: 'pagefile.sys',
          fullPath: r'C:\pagefile.sys',
          isFile: true,
          sizeBytes: _gb,
        );
        final cache = DiskTreeNode(
          name: 'cache.tmp',
          fullPath: r'C:\Windows\Temp\cache.tmp',
          isFile: true,
          sizeBytes: 1024,
          junkCategoryId: 'windows_temp',
        );
        final windows = DiskTreeNode(
          name: 'Windows',
          fullPath: r'C:\Windows',
          sizeBytes: _gb,
          isExpanded: true,
          children: [cache],
        );
        cleaner.root.replaceChildren([pagefile, windows]);
        await _pumpCleaner(tester, cleaner, languageCode: languageCode);
        for (final node in [pagefile, windows]) {
          final badge = find.byKey(
            ValueKey('cleaner-protected-${node.fullPath}'),
          );
          expect(badge, findsOneWidget);
          expect(
            find.descendant(
              of: badge,
              matching: find.text(
                languageCode == 'vi' ? 'Không được xoá' : 'Cannot delete',
              ),
            ),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(ValueKey('cleaner-tree-row-idle-${node.fullPath}')),
          );
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.sendKeyEvent(LogicalKeyboardKey.delete);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.delete);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(node.isSelectedForDeletion, isFalse);
        }
        expect(cleaner.requests, isEmpty);
        if (!windows.isExpanded) {
          await tester.tap(
            find
                .descendant(
                  of: find.byKey(
                    ValueKey('cleaner-tree-row-idle-${windows.fullPath}'),
                  ),
                  matching: find.byType(Icon),
                )
                .first,
          );
          await tester.pumpAndSettle();
        }
        expect(
          find.byKey(ValueKey('cleaner-protected-${cache.fullPath}')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(ValueKey('cleaner-tree-row-idle-${cache.fullPath}')),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      },
    );
  }

  for (final requiresAdmin in [true, false]) {
    testWidgets(
      'delete failure offers the appropriate retry (admin: $requiresAdmin)',
      (tester) async {
        final cleaner = _Cleaner()
          ..failDelete = true
          ..requiresAdmin = requiresAdmin;
        await _pumpCleaner(tester, cleaner);
        await _select(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        for (var i = 0; i < 10 && cleaner.requests.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump();
        final retry = find.widgetWithText(
          FilledButton,
          requiresAdmin ? 'Retry (Admin Access)' : 'Try again',
        );
        expect(retry, findsOneWidget);
        expect(cleaner.failureActions, isEmpty);
        if (requiresAdmin) {
          expect(
            find.textContaining('Administrator privileges required'),
            findsOneWidget,
          );
        }
        await tester.tap(retry);
        await _finishCleanup(tester);
        expect(cleaner.failureActions, [
          requiresAdmin
              ? CleanFailureAction.retryAsAdministrator
              : CleanFailureAction.retry,
        ]);
      },
    );
  }

  for (final permanent in [false, true]) {
    testWidgets('Enter confirms selected deletion (permanent: $permanent)', (
      tester,
    ) async {
      final cleaner = _Cleaner();
      await _pumpCleaner(tester, cleaner);
      await _select(tester);

      Future<void> openDialog() async {
        if (permanent) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        if (permanent) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      }

      await openDialog();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(cleaner.requests, isEmpty);
      expect(cleaner.root.children, contains(cleaner.removed));

      await tester.tap(
        find.byKey(const ValueKey(r'cleaner-tree-row-selected-C:\remove.iso')),
      );
      await openDialog();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _finishCleanup(tester);

      expect(find.byType(AlertDialog), findsNothing);
      expect(cleaner.requests, hasLength(1));
      expect(cleaner.requests.single.permanent, permanent);
      expect(
        cleaner.requests.single.items.single.path,
        cleaner.removed.fullPath,
      );
      expect(cleaner.root.children.map((node) => node.name), ['Archive']);
      expect(cleaner.root.sizeBytes, _gb);
      expect(cleaner.scans, 1);
    });
  }

  testWidgets('continue reuses results and dashboard after cleanup', (
    tester,
  ) async {
    final cleaner = _Cleaner();
    await _pumpCleaner(tester, cleaner);
    await tester.tap(
      find.byKey(const ValueKey('cleaner-dashboard-card-largeFiles')),
    );
    await tester.pumpAndSettle();
    final dashboard = tester.state(find.byType(CleanerDashboard));
    final results = tester.element(find.byKey(const ValueKey('results')));

    await _select(tester);
    await tester.tap(find.byKey(const ValueKey('cleaner-review-and-clean')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cleaner-confirm-clean')));
    await _finishCleanup(tester);
    expect(cleaner.requests, hasLength(1));
    expect(
      find.byKey(const ValueKey('cleaner-continue-results')),
      findsOneWidget,
    );
    expect(find.byType(CleanerDashboard), findsNothing);
    expect(
      tester.state(find.byType(CleanerDashboard, skipOffstage: false)),
      same(dashboard),
    );

    cleaner.kept.childrenReads = 0;
    await tester.tap(find.byKey(const ValueKey('cleaner-continue-results')));
    await tester.pumpAndSettle();
    expect(
      cleaner.kept.childrenReads,
      0,
      reason: 'Continue must not traverse the unchanged collapsed subtree',
    );
    expect(tester.state(find.byType(CleanerDashboard)), same(dashboard));
    expect(
      tester.element(find.byKey(const ValueKey('results'))),
      same(results),
    );
    expect(
      find.byKey(const ValueKey('cleaner-dashboard-detail-largeFiles')),
      findsOneWidget,
    );
    expect(find.text('remove.iso'), findsNothing);
    expect(find.text('keep.mkv'), findsWidgets);
    expect(cleaner.root.sizeBytes, _gb);
    expect(cleaner.root.fileCount, 1);
    expect(cleaner.scans, 1);
  });
}
