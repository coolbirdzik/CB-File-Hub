import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/app_insights/app_insights_models.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_scanner.dart';
import 'package:cb_file_manager/services/app_insights/app_uninstall_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_app_uninstall_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _first = r'C:\Users\Test\AppData\Local\Alpha Editor';
const _second = r'C:\Users\Test\AppData\Roaming\Alpha Editor';
const _profile = AppStorageProfile(
  app: InstalledAppInfo(
    id: 'alpha',
    displayName: 'Alpha Editor',
    source: InstalledAppSource.win32,
    uninstallCommand: 'uninstall.exe',
  ),
);

class _Service extends AppUninstallService {
  int removals = 0;
  int scans = 0;
  bool failUninstall = false;
  bool reinstalled = false;
  @override
  Future<InstalledAppInventoryResult> uninstall(
    InstalledAppInfo selected,
  ) async {
    removals++;
    if (failUninstall) throw const AppUninstallException('Uninstall cancelled');
    return const InstalledAppInventoryResult(apps: []);
  }

  @override
  Future<AppUninstallScan> scan(
    AppStorageProfile profile, {
    required List<String> excludedPaths,
  }) async {
    scans++;
    if (reinstalled) throw const AppUninstallException('App was reinstalled');
    return const AppUninstallScan({
      _first: AppLeftoverMeasurement(sizeBytes: 12, fileCount: 1),
      _second: AppLeftoverMeasurement(sizeBytes: 6, fileCount: 1),
    });
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    _Service service, {
    required Future<CleanReport?> Function(List<JunkItem>) clean,
    VoidCallback? onUninstalled,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => CleanerAppUninstallDialog(
                  profile: _profile,
                  service: service,
                  excludedPaths: const [],
                  onUninstalled: onUninstalled ?? () {},
                  onOpenFolder: (_) {},
                  onClean: (items, progress) => clean(items),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'does not uninstall on open; scans only after confirmed removal and leaves folders unchecked',
    (tester) async {
      final service = _Service();
      var removed = 0;
      await open(
        tester,
        service,
        clean: (_) async => null,
        onUninstalled: () => removed++,
      );
      expect(service.removals, 0);
      expect(service.scans, 0);
      await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-start')));
      await tester.pumpAndSettle();
      expect(service.removals, 1);
      expect(service.scans, 1);
      expect(removed, 1);
      expect(find.text(_first), findsOneWidget);
      expect(find.text(_second), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.byKey(const ValueKey('cleaner-uninstall-folder-$_first')),
            )
            .value,
        isFalse,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('cleaner-uninstall-clean')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled uninstall never scans or offers deletion', (
    tester,
  ) async {
    final service = _Service()..failUninstall = true;
    await open(tester, service, clean: (_) async => null);
    await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-start')));
    await tester.pumpAndSettle();
    expect(service.scans, 0);
    expect(find.text('Uninstall cancelled'), findsOneWidget);
    expect(find.byKey(const ValueKey('cleaner-uninstall-clean')), findsNothing);
  });

  testWidgets(
    'requires a second confirmation and sends only explicitly checked paths',
    (tester) async {
      final service = _Service();
      final batches = <List<JunkItem>>[];
      await open(
        tester,
        service,
        clean: (items) async {
          batches.add(items);
          return CleanReport(
            freedBytes: 12,
            succeeded: items.map((e) => e.path).toList(),
            failed: const {},
            skippedUnsafe: const [],
            skippedInUse: const [],
            wasPermanent: false,
          );
        },
      );
      await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-start')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-uninstall-folder-$_first')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-clean')));
      await tester.pumpAndSettle();
      expect(batches, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(batches, isEmpty);
      await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-clean')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-uninstall-confirm-clean')),
      );
      await tester.pumpAndSettle();
      expect(batches.single.single.path, _first);
      expect(batches.single.single.isUserSelected, isTrue);
      expect(batches.single.single.isContainerOnly, isFalse);
      expect(service.scans, 2);
      expect(
        find.byKey(const ValueKey('cleaner-uninstall-folder-$_first')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('cleaner-uninstall-folder-$_second')),
        findsOneWidget,
      );
    },
  );

  testWidgets('reinstall during review blocks cleanup callback', (
    tester,
  ) async {
    final service = _Service();
    var cleans = 0;
    await open(
      tester,
      service,
      clean: (_) async {
        cleans++;
        return null;
      },
    );
    await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-start')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cleaner-uninstall-folder-$_first')),
    );
    await tester.pump();
    service.reinstalled = true;
    await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-clean')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('cleaner-uninstall-confirm-clean')),
    );
    await tester.pumpAndSettle();
    expect(cleans, 0);
    expect(find.text('App was reinstalled'), findsOneWidget);
  });

  testWidgets(
    'failed paths remain visible with their OS error and Vietnamese controls',
    (tester) async {
      final service = _Service();
      await open(
        tester,
        service,
        locale: const Locale('vi'),
        clean: (_) async => const CleanReport(
          freedBytes: 0,
          succeeded: [],
          failed: {_first: 'Access denied'},
          skippedUnsafe: [],
          skippedInUse: [],
          wasPermanent: false,
        ),
      );
      expect(find.text('Gỡ ứng dụng'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-start')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-uninstall-folder-$_first')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cleaner-uninstall-clean')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cleaner-uninstall-confirm-clean')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('cleaner-uninstall-folder-$_first')),
        findsOneWidget,
      );
      expect(find.textContaining('Access denied'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
