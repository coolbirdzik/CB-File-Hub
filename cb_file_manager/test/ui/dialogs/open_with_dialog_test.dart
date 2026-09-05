import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cb_file_manager/ui/dialogs/open_with_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('cb_file_manager/app_icon');
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getAppsForExtension') return <Object>[];
          if (call.method == 'getAssociatedAppPath') {
            return r'C:\Apps\vlc.exe';
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final size in [
    const Size(1280, 800),
    const Size(360, 640),
    const Size(900, 420),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('app selection and default checkbox fit $size dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark
                ? ThemeConfig.getDarkTheme()
                : ThemeConfig.getLightTheme(),
            locale: Locale(dark ? 'vi' : 'en'),
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const Scaffold(
              body: OpenWithDialog(
                filePath:
                    r'C:\Videos\Summer holiday - A long video filename for checking the dialog layout.mp4',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final confirm = find.byKey(const ValueKey('open-with-confirm'));
        expect(tester.widget<ElevatedButton>(confirm).onPressed, isNull);
        final app = find.byKey(
          const ValueKey('open-with-app-__cb_video_player__'),
        );
        await tester.ensureVisible(app);
        await tester.tap(app);
        await tester.pumpAndSettle();
        // Choosing an app keeps the dialog open until explicitly confirmed.
        expect(find.byType(OpenWithDialog), findsOneWidget);
        expect(tester.widget<ElevatedButton>(confirm).onPressed, isNotNull);
        final checkbox = find.byKey(const ValueKey('open-with-default'));
        expect(tester.getRect(confirm).bottom, lessThan(size.height));
        expect(tester.getRect(checkbox).bottom, lessThan(size.height));
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
        // Space toggles the focused checkbox without opening the application.
        Focus.of(
          tester.element(
            find
                .descendant(
                  of: checkbox,
                  matching: find.byType(GestureDetector),
                )
                .first,
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
        expect(tester.takeException(), isNull);
      }, skip: !Platform.isWindows);
    }
  }
}
