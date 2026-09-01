import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/ui/screens/cb_agent_cleaner/cb_agent_cleaner_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 120));
}

void main() {
  final cleaner = DiskCleanerService.instance;

  setUp(() {
    cleaner.pendingCleanupItems = <JunkItem>[];
    cleaner.pendingCleanupBytes = 0;
  });

  tearDown(() {
    cleaner.pendingCleanupItems = <JunkItem>[];
    cleaner.pendingCleanupBytes = 0;
  });

  testWidgets(
    'Apps sub-feature is independent and never selects deletion targets',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          supportedLocales: <Locale>[Locale('en'), Locale('vi')],
          localizationsDelegates: <LocalizationsDelegate<dynamic>>[
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: CbAgentCleanerScreen()),
        ),
      );
      await _pumpUi(tester);

      final appsPane = find.byKey(
        const ValueKey<String>('cleaner-apps-results-pane'),
        skipOffstage: false,
      );
      final storagePane = find.byKey(
        const ValueKey<String>('cleaner-storage-results-pane'),
        skipOffstage: false,
      );
      expect(appsPane, findsOneWidget);
      expect(storagePane, findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('cleaner-recent-growth')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('cleaner-growth-filter')),
        findsOneWidget,
      );
      expect(find.text('Recently increased (2)'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>(
            r'cleaner-growth-badge-C:\Users\ngtan\Downloads',
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Recently increased (2)'));
      await _pumpUi(tester);
      expect(find.text('Windows'), findsNothing);
      expect(find.text('Downloads'), findsOneWidget);
      await tester.tap(find.text('Recently increased (2)'));
      await _pumpUi(tester);
      final appsPaneElement = tester.element(appsPane);
      final storagePaneElement = tester.element(storagePane);

      await tester.tap(find.text('Apps'));
      await _pumpUi(tester);
      expect(tester.element(appsPane), same(appsPaneElement));
      expect(tester.element(storagePane), same(storagePaneElement));
      expect(
        find.byKey(const ValueKey<String>('cleaner-apps-view')),
        findsOneWidget,
      );
      final drivePicker = tester.widget<DropdownButton<String>>(
        find.byKey(
          const ValueKey<String>('cleaner-apps-drive-picker'),
        ),
      );
      expect(drivePicker.value, r'C:\');
      expect(
        drivePicker.items?.map((item) => item.value),
        <String>[r'C:\', r'D:\'],
      );
      expect(drivePicker.onChanged, isNotNull);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(cleaner.pendingCleanupBytes, 0);
      expect(cleaner.pendingCleanupItems, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('cleaner-apps-view')),
        findsOneWidget,
      );

      await tester.tap(find.text('Disk usage'));
      await _pumpUi(tester);
      expect(tester.element(appsPane), same(appsPaneElement));
      expect(tester.element(storagePane), same(storagePaneElement));
      final reviewButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('cleaner-review-and-clean')),
      );
      expect(reviewButton.onPressed, isNull);

      await tester.tap(find.text('Downloads'));
      await _pumpUi(tester);
      expect(
        find.byKey(
          const ValueKey<String>(
            r'cleaner-tree-row-selected-C:\Users\ngtan\Downloads',
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(
                const ValueKey<String>('cleaner-review-and-clean'),
              ),
            )
            .onPressed,
        isNotNull,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _pumpUi(tester);
      expect(
        find.byKey(
          const ValueKey<String>(
            r'cleaner-tree-row-idle-C:\Users\ngtan\Downloads',
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(
                const ValueKey<String>('cleaner-review-and-clean'),
              ),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('Downloads'));
      await _pumpUi(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('cleaner-tree-row-idle-C:\\Windows'),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _pumpUi(tester);
      expect(
        find.byKey(
          const ValueKey<String>(
            r'cleaner-tree-row-selected-C:\Users\ngtan\Downloads',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('cleaner-tree-row-selected-C:\\Windows'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(
                const ValueKey<String>('cleaner-review-and-clean'),
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _pumpUi(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(
                const ValueKey<String>('cleaner-review-and-clean'),
              ),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(
          const ValueKey<String>('cleaner-tree-row-idle-C:\\Windows'),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tap(find.text('Downloads').first);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await _pumpUi(tester);
      expect(
        find.byKey(
          const ValueKey<String>(
            r'cleaner-tree-row-selected-C:\Users\ngtan\Downloads',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('cleaner-tree-row-selected-C:\\Windows'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Apps'));
      await _pumpUi(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('cleaner-app-row-win32:google-chrome'),
        ),
      );
      await _pumpUi(tester);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('cleaner-app-review-win32:google-chrome'),
        ),
      );
      await _pumpUi(tester);

      expect(cleaner.pendingCleanupItems, hasLength(1));
      final item = cleaner.pendingCleanupItems!.single;
      expect(item.categoryId, 'browser_cache');
      expect(item.path, endsWith(r'Google\Chrome\User Data\Default\GPUCache'));
      expect(item.isUserSelected, isFalse);
      expect(cleaner.pendingCleanupBytes, 1200 * 1024 * 1024);

      await tester.tap(
        find.byKey(const ValueKey<String>('cleaner-select-drives')),
      );
      await _pumpUi(tester);
      expect(find.byKey(const ValueKey<String>('setup')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('cleaner-subfeature-selector')),
        findsOneWidget,
      );

      await tester.tap(find.text('Apps'));
      await _pumpUi(tester);
      expect(
        find.byKey(const ValueKey<String>('cleaner-apps-view')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('setup')), findsNothing);
    },
    skip: !kCbE2E,
  );
}
