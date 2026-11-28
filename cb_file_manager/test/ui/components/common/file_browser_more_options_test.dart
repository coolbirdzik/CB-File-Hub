import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/file_browser_options.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/components/common/file_browser_preference_option.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/screens/settings/file_browser_settings_section.dart';
import 'package:cb_file_manager/ui/tab_manager/mobile/mobile_file_actions_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final preferences = UserPreferences.instance;
  final l = EnglishLocalizations();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('file-browser-menu-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => root.path);
    await preferences.init();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    DatabaseManager.resetSingletonForE2ETest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await root.delete(recursive: true);
  });

  Future<void> reset(WidgetTester tester) async {
    await tester.runAsync(() async {
      await preferences.setFileBrowserOptions(const FileBrowserOptions());
      await preferences.setAllowFileExtensionRename(false);
    });
  }

  Future<void> waitForSave(WidgetTester tester, bool Function() saved) async {
    for (var i = 0; i < 50 && !saved(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(saved(), isTrue);
    await tester.pumpAndSettle();
  }

  Finder menuOption(FileBrowserPreferenceOption option) =>
      find.byWidgetPredicate(
        (widget) =>
            widget is PopupMenuItem<String> && widget.value == option.menuId,
      );

  Finder settingsSwitch(FileBrowserPreferenceOption option) => find.descendant(
    of: find.ancestor(
      of: find.text(option.label(l)),
      matching: find.byType(ListTile),
    ),
    matching: find.byType(Switch),
  );

  testWidgets(
    'desktop more menu changes each preference and reflects it in Settings',
    (tester) async {
      await reset(tester);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: Scaffold(
            body: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: preferences.allowFileExtensionRename,
                  builder: (context, rename, _) =>
                      SharedActionBar.buildMoreOptionsMenu(
                        onSelectionModeToggled: () {},
                        allowFileExtensionRename: rename,
                        onAllowFileExtensionRenameChanged: (value) => unawaited(
                          preferences.setAllowFileExtensionRename(value),
                        ),
                      ),
                ),
                const Expanded(
                  child: SingleChildScrollView(
                    child: FileBrowserSettingsSection(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final option in FileBrowserPreferenceOption.available()) {
        final before = option.isEnabled(preferences);
        await tester.tap(find.byKey(const ValueKey('shared-more-action')));
        await tester.pumpAndSettle();
        final entry = menuOption(option);
        expect(entry, findsOneWidget);
        expect(
          find.descendant(
            of: entry,
            matching: find.byIcon(PhosphorIconsLight.check),
          ),
          before ? findsOneWidget : findsNothing,
        );
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        await waitForSave(
          tester,
          () => option.isEnabled(preferences) != before,
        );
        expect(entry, findsNothing);
        expect(tester.widget<Switch>(settingsSwitch(option)).value, !before);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('shared more menu leaves non-file-browser screens unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: SharedActionBar.buildMoreOptionsMenu(
            onSelectionModeToggled: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('shared-more-action')));
    await tester.pumpAndSettle();
    for (final option in FileBrowserPreferenceOption.values) {
      expect(menuOption(option), findsNothing);
    }
    expect(find.text(l.selectMultipleFiles), findsOneWidget);
  });

  testWidgets(
    'mobile more sheet is scrollable and exposes touch-appropriate settings',
    (tester) async {
      await reset(tester);
      await tester.binding.setSurfaceSize(const Size(360, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = MobileFileActionsController('file-browser-menu-test')
        ..onAllowFileExtensionRenameChanged = (value) =>
            unawaited(preferences.setAllowFileExtensionRename(value));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => controller.showMoreOptionsMenu(context),
                child: const Text('More'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      for (final option in FileBrowserPreferenceOption.available()) {
        expect(find.text(option.label(l)), findsOneWidget);
      }
      expect(find.text(l.showSystemItems), findsNothing);
      expect(find.text(l.singleClickToOpen), findsNothing);
      final checkboxes = find.text(l.fileSelectionCheckboxes);
      await tester.ensureVisible(checkboxes);
      await tester.tap(checkboxes);
      await tester.pumpAndSettle();
      await waitForSave(
        tester,
        () => preferences.fileBrowserOptions.value.selectionCheckboxes,
      );
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      final tile = find.ancestor(
        of: checkboxes,
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.byIcon(PhosphorIconsLight.check),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
