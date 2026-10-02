import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return clipboard == null
                  ? null
                  : <String, dynamic>{'text': clipboard};
            case 'Clipboard.hasStrings':
              return <String, dynamic>{'value': clipboard != null};
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final key = GlobalKey<ChipsInputState<String>>();

  Future<({List<List<String>> changes, List<String> submitted})> pumpField(
    WidgetTester tester, {
    List<String> tags = const <String>['existing', 'favorite'],
    String draft = '',
  }) async {
    final changes = <List<String>>[];
    final submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(
          body: ChipsInput<String>(
            key: key,
            values: tags,
            onChanged: changes.add,
            onSubmitted: submitted.add,
            chipBuilder: (context, value) => Chip(label: Text(value)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final prefix = '￾' * tags.length;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$prefix$draft',
        selection: TextSelection.collapsed(
          offset: prefix.length + draft.length,
        ),
      ),
    );
    await tester.pump();
    return (changes: changes, submitted: submitted);
  }

  void select(int start, int end) {
    key.currentState!.controller.selection = TextSelection(
      baseOffset: start,
      extentOffset: end,
    );
  }

  Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey keyCode) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(keyCode);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+C with nothing selected copies every tag', (tester) async {
    await pumpField(tester);

    await shortcut(tester, LogicalKeyboardKey.keyC);

    expect(clipboard, 'existing, favorite');
  });

  testWidgets('Ctrl+C copies the selected chips and draft text by name', (
    tester,
  ) async {
    await pumpField(tester, draft: 'draft');
    select(1, 5);

    await shortcut(tester, LogicalKeyboardKey.keyC);

    expect(clipboard, 'favorite, dra');
  });

  testWidgets('Ctrl+C on draft text alone copies it as plain text', (
    tester,
  ) async {
    await pumpField(tester, draft: 'draft');
    select(4, 7);

    await shortcut(tester, LogicalKeyboardKey.keyC);

    expect(clipboard, 'aft');
  });

  testWidgets('Ctrl+X copies the selected chips and removes them', (
    tester,
  ) async {
    final field = await pumpField(tester, draft: 'draft');
    select(0, 1);

    await shortcut(tester, LogicalKeyboardKey.keyX);

    expect(clipboard, 'existing');
    expect(field.changes, <List<String>>[
      <String>['favorite'],
    ]);
    expect(key.currentState!.controller.textWithoutReplacements, 'draft');
  });

  testWidgets('Ctrl+V adds a pasted tag list as separate tags', (tester) async {
    final field = await pumpField(tester);
    clipboard = 'alpha, beta;\ngamma';

    await shortcut(tester, LogicalKeyboardKey.keyV);

    expect(field.submitted, <String>['alpha', 'beta', 'gamma']);
    expect(key.currentState!.controller.textWithoutReplacements, isEmpty);
  });

  testWidgets('Ctrl+V pastes a single name as draft text', (tester) async {
    final field = await pumpField(tester);
    clipboard = 'solo';

    await shortcut(tester, LogicalKeyboardKey.keyV);

    expect(field.submitted, isEmpty);
    expect(key.currentState!.controller.textWithoutReplacements, 'solo');
  });

  testWidgets('Ctrl+V into a draft keeps the list as text', (tester) async {
    final field = await pumpField(tester, draft: 'ab');
    clipboard = 'x, y';

    await shortcut(tester, LogicalKeyboardKey.keyV);

    expect(field.submitted, isEmpty);
    expect(key.currentState!.controller.textWithoutReplacements, 'abx, y');
  });

  testWidgets('the context menu offers to copy the tags', (tester) async {
    await pumpField(tester);

    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy tags'));
    await tester.pumpAndSettle();

    expect(clipboard, 'existing, favorite');
    expect(find.text('Copy tags'), findsNothing);
  });

  test('a hierarchy entry is not split into tags', () {
    expect(ChipsInputState.splitPastedTags('parent:a, b'), isEmpty);
    expect(ChipsInputState.splitPastedTags(' a ,b,, c '), <String>[
      'a',
      'b',
      'c',
    ]);
  });
}
