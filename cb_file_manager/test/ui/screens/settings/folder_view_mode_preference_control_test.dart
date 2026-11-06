import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/languages/vietnamese_localizations.dart';
import 'package:cb_file_manager/design_system/primitives/cb_select.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/settings/folder_view_mode_preference_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [360.0, 1000.0]) {
    for (final language in ['en', 'vi']) {
      testWidgets('policy select works at width $width in $language', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.reset);
        final l10n = language == 'vi'
            ? VietnameseLocalizations()
            : EnglishLocalizations();
        var value = FolderViewModePreference.mediaGrid;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('en'), Locale('vi')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Align(
                    alignment: Alignment.topCenter,
                    child: FolderViewModePreferenceControl(
                      value: value,
                      onChanged: (next) => setState(() => value = next),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.folderViewModePreferenceDescription),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        final select = find.byType(CbSelect<FolderViewModePreference>);
        await tester.tap(select);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.folderViewModeInheritParent).last);
        await tester.pumpAndSettle();
        expect(value, FolderViewModePreference.inheritParent);

        await tester.tap(select);
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.folderViewModeMediaGrid).last);
        await tester.pumpAndSettle();
        expect(value, FolderViewModePreference.mediaGrid);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
