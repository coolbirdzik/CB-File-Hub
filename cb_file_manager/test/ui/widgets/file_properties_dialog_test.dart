import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/screens/folder_list/file_details_screen.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

class _TestFile extends Fake implements File {
  _TestFile(this.path, this.metadata);

  @override
  final String path;
  final FileStat metadata;

  @override
  Future<FileStat> stat() async => metadata;
}

void main() {
  for (final viewport in [const Size(1280, 800), const Size(360, 480)]) {
    testWidgets('Properties opens a bounded modal at $viewport', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final root = Directory.systemTemp.createTempSync('properties-dialog-');
      addTearDown(() => root.deleteSync(recursive: true));
      final file = File(p.join(root.path, 'document.txt'))
        ..writeAsStringSync('test properties');
      final testFile = _TestFile(file.path, file.statSync());

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: CbThemeBuilder.build(
            brightness: Brightness.dark,
            accent: Colors.blue,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    FileDetailsScreen.show(context, file: testFile),
                child: const Text('Open inspector'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open inspector'));
      await tester.pumpAndSettle();

      expect(find.byType(CbDialog), findsOneWidget);
      expect(find.text('Open inspector'), findsOneWidget);
      final size = tester.getSize(
        find
            .descendant(
              of: find.byType(CbDialog),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(size.width, lessThan(viewport.width));
      expect(size.height, lessThan(viewport.height));
      expect(find.text('document.txt'), findsWidgets);
      expect(
        find.byKey(const ValueKey('file-properties-tab-details')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('file-properties-copy-path')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(CbDialog), findsNothing);
      expect(find.text('Open inspector'), findsOneWidget);
    });
  }
}
