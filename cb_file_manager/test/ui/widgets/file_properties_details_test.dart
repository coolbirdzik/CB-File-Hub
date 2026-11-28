import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/widgets/file_properties_details.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory root;
  late File first, second;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('properties-copy-path-');
    first = File(path.join(root.path, 'file name.txt'))
      ..writeAsStringSync('file');
    second = File(path.join(root.path, 'another file.txt'))
      ..writeAsStringSync('second');
  });
  tearDown(() => root.delete(recursive: true));

  for (final dense in [false, true]) {
    testWidgets(
      'copies the full current path from ${dense ? 'dense' : 'full'} properties',
      (tester) async {
        final copied = <String>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        Future<void> show(File file) async {
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('en'),
              supportedLocales: const [Locale('en')],
              localizationsDelegates: const [
                AppLocalizationsDelegate(),
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 280,
                    child: FilePropertiesDetails(
                      filePath: file.path,
                      statFuture: Future.value(file.statSync()),
                      dense: dense,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        final copy = find.byKey(const ValueKey('file-properties-copy-path'));
        await show(first);
        expect(copy, findsOneWidget);
        await tester.tap(copy);
        await tester.pump();
        expect(copied, [first.path]);
        expect(find.text('Copied path to clipboard'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        await show(second);
        await tester.tap(copy);
        await tester.pump();
        expect(copied, [first.path, second.path]);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
