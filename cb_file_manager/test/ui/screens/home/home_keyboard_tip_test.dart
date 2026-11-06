import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/screens/home/home_keyboard_tip.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_keyboard_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  final prefs = UserPreferences.instance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('home-keyboard-tip-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => root.path);
    await prefs.init();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    DatabaseManager.resetSingletonForE2ETest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await root.delete(recursive: true);
  });

  test('the tip is on by default and remembers being turned off', () async {
    expect(await prefs.getShowHomeKeyboardTip(), isTrue);
    expect(await prefs.setShowHomeKeyboardTip(false), isTrue);
    expect(await prefs.getShowHomeKeyboardTip(), isFalse);
    expect(prefs.showHomeKeyboardTip.value, isFalse);
    await prefs.setShowHomeKeyboardTip(true);
  });

  Future<List<Intent>> pumpTip(WidgetTester tester) async {
    final invoked = <Intent>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeConfig.getDarkTheme(),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        home: Actions(
          actions: {
            OpenCommandPaletteIntent: CallbackAction<OpenCommandPaletteIntent>(
              onInvoke: (intent) {
                invoked.add(intent);
                return null;
              },
            ),
          },
          child: const Scaffold(body: HomeKeyboardTip()),
        ),
      ),
    );
    // The stored choice is real I/O; the card stays hidden until it is read.
    // Let the read finish on the real event loop, pumping its callbacks.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    return invoked;
  }

  testWidgets('is hidden off the desktop', (tester) async {
    await pumpTip(tester);
    expect(find.byKey(const ValueKey('home-keyboard-tip')), findsNothing);
  });

  testWidgets('opens the palette through the shell action and dismisses', (
    tester,
  ) async {
    final invoked = await pumpTip(tester);
    expect(find.byKey(const ValueKey('home-keyboard-tip')), findsOneWidget);
    expect(find.text('Ctrl'), findsNWidgets(2));

    await tester.tap(
      find.byKey(const ValueKey('home-keyboard-tip-open-palette')),
    );
    expect(invoked.single, isA<OpenCommandPaletteIntent>());

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('home-keyboard-tip-dismiss')));
      // The preference write is real I/O.
      for (var i = 0; i < 50 && prefs.showHomeKeyboardTip.value; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('home-keyboard-tip')), findsNothing);
    expect(prefs.showHomeKeyboardTip.value, isFalse);
    await tester.runAsync(() => prefs.setShowHomeKeyboardTip(true));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
