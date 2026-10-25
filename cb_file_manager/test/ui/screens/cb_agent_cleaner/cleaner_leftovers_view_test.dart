import 'package:cb_file_manager/bloc/cleaner_app_leftovers/cleaner_app_leftovers.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_finder.dart';
import 'package:cb_file_manager/services/app_insights/app_leftover_scanner.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cleaner_leftovers_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const int _mb = 1024 * 1024;
const String _oldGame = r'C:\Users\me\AppData\Local\OldGame';
const String _oldTool = r'C:\Users\me\AppData\Roaming\OldTool';
const String _pyCharm = r'C:\Users\me\AppData\Local\JetBrains\PyCharm2021.3';

void main() {
  final now = DateTime(2026, 10, 1, 12);

  AppLeftoverReport fixtureReport({bool inventoryUnavailable = false}) {
    return AppLeftoverReport(
      drivePath: r'C:\',
      generatedAt: now,
      inventoryUnavailable: inventoryUnavailable,
      candidates: inventoryUnavailable
          ? const <AppLeftoverCandidate>[]
          : const <AppLeftoverCandidate>[
              AppLeftoverCandidate(
                path: _oldGame,
                displayName: 'OldGame',
                location: AppLeftoverLocation.localAppData,
                reason: AppLeftoverReason.noInstalledApp,
                sizeBytes: 0,
              ),
              AppLeftoverCandidate(
                path: _oldTool,
                displayName: 'OldTool',
                location: AppLeftoverLocation.roamingAppData,
                reason: AppLeftoverReason.noInstalledApp,
                sizeBytes: 0,
              ),
              AppLeftoverCandidate(
                path: _pyCharm,
                displayName: r'JetBrains\PyCharm2021.3',
                location: AppLeftoverLocation.localAppData,
                reason: AppLeftoverReason.olderVersion,
                sizeBytes: 0,
                relatedAppName: 'PyCharm 2024.1',
              ),
            ],
    );
  }

  AppLeftoverMeasurement measured(
    int mb, {
    int daysAgo = 400,
    String? newestEntry,
  }) {
    return AppLeftoverMeasurement(
      sizeBytes: mb * _mb,
      fileCount: 10,
      lastModified: now.subtract(Duration(days: daysAgo)),
      newestEntry: newestEntry,
    );
  }

  Future<void> pumpView(
    WidgetTester tester, {
    required CleanerAppLeftoversCubit cubit,
    void Function(String)? onOpenFolder,
    AppLeftoverCleanAction? onClean,
    VoidCallback? onScan,
    bool usesTrash = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: CleanerLeftoversView(
            cubit: cubit,
            onOpenFolder: onOpenFolder,
            onClean: onClean,
            onScan: onScan,
            usesTrash: usesTrash,
          ),
        ),
      ),
    );
    // Progress bars shown while scanning never settle.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  CleanReport succeededReport(List<JunkItem> items) => CleanReport(
    succeeded: <String>[for (final item in items) item.path],
    failed: const <String, String>{},
    skippedUnsafe: const <String>[],
    skippedInUse: const <String>[],
    freedBytes: items.fold<int>(0, (sum, item) => sum + item.sizeBytes),
    wasPermanent: false,
  );

  testWidgets('starts from an intro with a scan button', (tester) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now);
    addTearDown(cubit.close);
    var scans = 0;

    await pumpView(tester, cubit: cubit, onScan: () => scans++);
    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-leftovers-scan')),
    );
    expect(scans, 1);
  });

  testWidgets('groups folders by reason and location as they are measured', (
    tester,
  ) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport(), scanning: true);
    addTearDown(cubit.close);

    await pumpView(tester, cubit: cubit, settle: false);
    expect(
      find.byKey(const ValueKey<String>('cleaner-leftovers-progress')),
      findsOneWidget,
    );
    expect(find.text('Checked 0 of 3 folders'), findsOneWidget);
    expect(find.text('OldGame'), findsNothing);

    cubit.addMeasurement(_oldGame, measured(300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Apps no longer installed'), findsOneWidget);
    expect(find.text('Local AppData'), findsOneWidget);
    expect(find.text('OldGame'), findsOneWidget);
    expect(find.text('Found 300.0 MB so far'), findsOneWidget);

    cubit
      ..addMeasurements(<String, AppLeftoverMeasurement>{
        _oldTool: measured(50),
        _pyCharm: measured(200),
      })
      ..finishScan();
    await tester.pumpAndSettle();
    expect(find.text('Older versions'), findsOneWidget);
    expect(find.text('Roaming AppData'), findsOneWidget);
    expect(find.textContaining('Older version of PyCharm 2024.1'), findsOne);
    expect(find.text('Up to 550.0 MB can be freed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('cleaner-leftovers-progress')),
      findsNothing,
    );
  });

  testWidgets('moves only confirmed, checked folders to the Recycle Bin', (
    tester,
  ) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport())
      ..addMeasurements(<String, AppLeftoverMeasurement>{
        _oldGame: measured(300),
        _oldTool: measured(50),
        _pyCharm: measured(200),
      });
    addTearDown(cubit.close);
    List<JunkItem>? cleaned;
    String? opened;

    await pumpView(
      tester,
      cubit: cubit,
      onOpenFolder: (path) => opened = path,
      onClean: (items, onProgress) async {
        cleaned = items;
        return succeededReport(items);
      },
    );

    final clean = find.byKey(const ValueKey<String>('cleaner-leftovers-clean'));
    expect(tester.widget<FilledButton>(clean).onPressed, isNull);

    // The group checkbox checks every folder of that location.
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'cleaner-leftovers-group-check-noInstalledApp-localAppData',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('300.0 MB selected (1 folder)'), findsOneWidget);
    expect(
      find.text('Move 1 folder to Recycle Bin (300.0 MB)'),
      findsOneWidget,
    );

    await tester.tap(clean);
    await tester.pumpAndSettle();
    expect(cleaned, isNull, reason: 'nothing happens before confirming');
    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-leftovers-confirm-clean')),
    );
    await tester.pumpAndSettle();

    expect(cleaned?.map((item) => item.path), <String>[_oldGame]);
    expect(cleaned!.single.isUserSelected, isTrue);
    expect(cleaned!.single.isContainerOnly, isFalse);
    expect(find.text('OldGame'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-leftover-open-$_oldTool')),
    );
    expect(opened, _oldTool);
  });

  testWidgets('macOS and Linux move folders to the Trash', (tester) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport())
      ..addMeasurement(_oldGame, measured(300));
    addTearDown(cubit.close);

    await pumpView(tester, cubit: cubit, usesTrash: true);
    await tester.tap(
      find.byKey(const ValueKey<String>('cleaner-leftover-row-$_oldGame')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Move 1 folder to Trash Bin (300.0 MB)'), findsOneWidget);
  });

  testWidgets('hides folders changed recently', (tester) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport())
      ..addMeasurements(<String, AppLeftoverMeasurement>{
        _oldGame: measured(300, daysAgo: 2),
        _pyCharm: measured(200),
      });
    addTearDown(cubit.close);

    await pumpView(tester, cubit: cubit);
    expect(find.text('OldGame'), findsNothing);
    expect(find.textContaining('1 recently used folder hidden'), findsOne);

    cubit.setInactiveDays(0);
    await tester.pumpAndSettle();
    expect(find.text('OldGame'), findsOneWidget);
  });

  testWidgets('shows the date, its age and the newest file inside', (
    tester,
  ) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport())
      ..addMeasurements(<String, AppLeftoverMeasurement>{
        _oldGame: measured(300, newestEntry: r'Saved\Config\Engine.ini'),
        _oldTool: measured(50),
      });
    addTearDown(cubit.close);

    await pumpView(tester, cubit: cubit);

    expect(find.text('Folder'), findsWidgets);
    expect(find.text('Last changed'), findsWidgets);
    expect(find.text('Size'), findsWidgets);
    // 400 days before the fixture's "now".
    expect(find.text('2025-08-27'), findsNWidgets(2));
    expect(find.text('400 days ago'), findsNWidgets(2));
    expect(
      find.text(r'Newest file inside: Saved\Config\Engine.ini'),
      findsOneWidget,
    );
  });

  testWidgets('narrow rows move the date under the name without overflow', (
    tester,
  ) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport())
      ..addMeasurements(<String, AppLeftoverMeasurement>{
        _oldGame: measured(
          300,
          newestEntry: r'Saved\SaveGames\SomeVeryLongProfileName\slot_01.sav',
        ),
      });
    addTearDown(cubit.close);

    await pumpView(tester, cubit: cubit);
    tester.view.physicalSize = const Size(420, 900);
    await tester.pumpAndSettle();

    expect(find.text('Last changed 2025-08-27 • 400 days ago'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the group header collapses and expands its folders', (
    tester,
  ) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport())
      ..addMeasurements(<String, AppLeftoverMeasurement>{
        _oldGame: measured(300),
        _pyCharm: measured(200),
      });
    addTearDown(cubit.close);

    await pumpView(tester, cubit: cubit);
    expect(find.text('OldGame'), findsOneWidget);

    final header = find.byKey(
      const ValueKey<String>(
        'cleaner-leftovers-group-toggle-noInstalledApp-localAppData',
      ),
    );
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('OldGame'), findsNothing);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text('OldGame'), findsOneWidget);
  });

  testWidgets('Select all checks every listed folder and clears again', (
    tester,
  ) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport())
      ..addMeasurements(<String, AppLeftoverMeasurement>{
        _oldGame: measured(300),
        _oldTool: measured(50),
        _pyCharm: measured(200),
      });
    addTearDown(cubit.close);

    await pumpView(tester, cubit: cubit);
    final selectAll = find.byKey(
      const ValueKey<String>('cleaner-leftovers-select-all'),
    );
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    expect(cubit.state.selectedPaths, hasLength(3));
    expect(find.text('550.0 MB selected (3 folders)'), findsOneWidget);

    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    expect(cubit.state.selectedPaths, isEmpty);
  });

  testWidgets('explains when the app inventory is unavailable', (tester) async {
    final cubit = CleanerAppLeftoversCubit(nowProvider: () => now)
      ..setReport(fixtureReport(inventoryUnavailable: true));
    addTearDown(cubit.close);

    await pumpView(tester, cubit: cubit);

    expect(
      find.byKey(const ValueKey<String>('cleaner-leftovers-unavailable')),
      findsOneWidget,
    );
  });
}
