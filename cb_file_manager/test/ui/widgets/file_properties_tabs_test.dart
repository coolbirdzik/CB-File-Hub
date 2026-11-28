import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/widgets/file_properties_tabs.dart';
import 'package:crypto/crypto.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late File document, image;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('file-properties-tabs-');
    document = File(p.join(root.path, 'document.txt'))
      ..writeAsStringSync('test properties');
    image = File(p.join(root.path, 'image.png'))
      ..writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 2)));
  });
  tearDown(() => root.delete(recursive: true));

  Future<void> show(
    WidgetTester tester,
    String filePath,
    FileStat stat, {
    bool dense = false,
    bool isDirectory = false,
    FilePropertiesTab initialTab = FilePropertiesTab.overview,
    Widget? tags,
    Future<String> Function(String, String)? shellReader,
  }) async {
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
        theme: CbThemeBuilder.build(
          brightness: Brightness.dark,
          accent: Colors.blue,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: dense ? 260 : 520,
              child: SingleChildScrollView(
                child: FilePropertiesTabs(
                  filePath: filePath,
                  statFuture: Future.value(stat),
                  dense: dense,
                  isDirectory: isDirectory,
                  tags: tags,
                  initialTab: initialTab,
                  shellReader: shellReader,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder tab(FilePropertiesTab tab) =>
      find.byKey(ValueKey('file-properties-tab-${tab.name}'));
  Future<void> open(WidgetTester tester, FilePropertiesTab selected) async {
    await tester.ensureVisible(tab(selected));
    await tester.tap(tab(selected));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets(
    'details are lazy, display real file facts and available shell metadata',
    (tester) async {
      final calls = <String>[];
      await show(
        tester,
        document.path,
        document.statSync(),
        dense: true,
        shellReader: (path, property) async {
          expect(path, document.path);
          calls.add(property);
          return property == 'owner' ? 'Test owner' : '';
        },
      );
      expect(
        find.byKey(const ValueKey('file-properties-copy-path')),
        findsOneWidget,
      );
      expect(tab(FilePropertiesTab.media), findsNothing);
      expect(calls, isEmpty);
      await open(tester, FilePropertiesTab.details);
      await tester.pumpAndSettle();
      expect(find.text('${document.lengthSync()} B'), findsOneWidget);
      expect(find.text('Test owner'), findsOneWidget);
      expect(calls, contains('owner'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('media tab appears for images and shows available metadata', (
    tester,
  ) async {
    await show(
      tester,
      image.path,
      image.statSync(),
      shellReader: (path, property) async =>
          property == 'cameraModel' ? 'Test camera' : '',
    );
    expect(tab(FilePropertiesTab.media), findsOneWidget);
    await open(tester, FilePropertiesTab.media);
    for (
      var i = 0;
      i < 100 &&
          (find.text('Test camera').evaluate().isEmpty ||
              find.byType(Image).evaluate().isEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('Test camera'), findsOneWidget);
    expect(find.text('4 × 2'), findsOneWidget);
    expect(find.text('2:1'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
  });

  testWidgets(
    'checksum calculates only on demand, copies the digest and resets on file change',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await show(tester, document.path, document.statSync());
      await open(tester, FilePropertiesTab.checksum);
      final expected = sha256.convert(document.readAsBytesSync()).toString();
      expect(find.text(expected), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('file-properties-calculate-checksum')),
      );
      await tester.pump();
      for (var i = 0; i < 100 && find.text(expected).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text(expected), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('file-properties-copy-checksum')),
      );
      await tester.pump();
      expect(copied, [expected]);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await show(tester, image.path, image.statSync());
      expect(find.text(expected), findsNothing);
      expect(
        find.byKey(const ValueKey('file-properties-calculate-checksum')),
        findsOneWidget,
      );
    },
  );

  testWidgets('folder has no media or checksum tab', (tester) async {
    await show(tester, root.path, root.statSync(), isDirectory: true);
    expect(tab(FilePropertiesTab.overview), findsOneWidget);
    expect(tab(FilePropertiesTab.details), findsOneWidget);
    expect(tab(FilePropertiesTab.media), findsNothing);
    expect(tab(FilePropertiesTab.checksum), findsNothing);
  });

  testWidgets(
    'initial Tags tab opens directly and keeps the draft during navigation',
    (tester) async {
      await show(
        tester,
        document.path,
        document.statSync(),
        initialTab: FilePropertiesTab.tags,
        tags: const TextField(key: ValueKey('tag-test-draft')),
      );
      expect(find.byKey(const ValueKey('tag-test-draft')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('tag-test-draft')),
        'unsaved draft',
      );
      await open(tester, FilePropertiesTab.overview);
      expect(find.byKey(const ValueKey('tag-test-draft')), findsNothing);
      await open(tester, FilePropertiesTab.tags);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'unsaved draft',
      );
    },
  );
}
