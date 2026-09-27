import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/widgets/gallery_nsfw_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in ['en', 'vi']) {
    testWidgets('NSFW control can mark and unmark a collection ($locale)', (
      tester,
    ) async {
      var nsfw = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('vi')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Column(
                children: [
                  GalleryNsfwToggle(
                    value: nsfw,
                    onChanged: (value) => setState(() => nsfw = value),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (_) => setState(() => nsfw = !nsfw),
                    itemBuilder: (context) => [
                      galleryNsfwMenuItem(context, nsfw),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(nsfw, isTrue);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckedPopupMenuItem<String>>(
              find.byType(CheckedPopupMenuItem<String>),
            )
            .checked,
        isTrue,
      );
      await tester.tap(find.byType(CheckedPopupMenuItem<String>));
      await tester.pumpAndSettle();
      expect(nsfw, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });
  }
}
