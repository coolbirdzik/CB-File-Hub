import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/ui/widgets/tag_chips_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _TagEditor extends StatefulWidget {
  const _TagEditor({super.key});

  @override
  State<_TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<_TagEditor> {
  final inputKey = GlobalKey<ChipsInputState<String>>();
  final tags = <String>['existing'];
  final added = <String>[];
  String? parent;
  String draft = '';
  List<String> children = ['Alice', 'Bob'];

  void setChildren(List<String> values) => setState(() => children = values);

  void add(String tag) => setState(() {
    added.add(parent == null ? tag : '$parent:$tag');
    tags.add(tag);
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 320,
    child: TagChipsField(
      fieldKey: inputKey,
      tags: tags,
      suggestions: parent == null
          ? (draft.isEmpty
                ? const <String>[]
                : ['People', 'Places']
                      .where(
                        (tag) =>
                            tag.toLowerCase().contains(draft.toLowerCase()),
                      )
                      .toList())
          : children.where((tag) => !tags.contains(tag)).toList(),
      scopeParent: parent,
      onScopeChanged: (value) => setState(() {
        parent = value;
        draft = '';
      }),
      onSuggestionSelected: add,
      onTextChanged: (value) => setState(() => draft = value),
      onSubmitted: add,
      onRemoved: (tag) => setState(() => tags.remove(tag)),
    ),
  );
}

void main() {
  Future<_TagEditorState> mount(
    WidgetTester tester, {
    String language = 'en',
    Alignment alignment = Alignment.topCenter,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    final key = GlobalKey<_TagEditorState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('vi')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Align(
            alignment: alignment,
            child: _TagEditor(key: key),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  Future<void> type(
    WidgetTester tester,
    _TagEditorState editor,
    String text, {
    TextRange composing = TextRange.empty,
  }) async {
    final prefix = editor.parent == null ? '\uFFFE' * editor.tags.length : '';
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: '$prefix$text',
        selection: TextSelection.collapsed(offset: prefix.length + text.length),
        composing: composing,
      ),
    );
    await tester.pumpAndSettle();
    expect(editor.draft, text);
  }

  for (final brightness in Brightness.values) {
    for (final textScale in [1.0, 1.5]) {
      testWidgets(
        'child text aligns with parent in $brightness at scale $textScale',
        (tester) async {
          final editor = await mount(
            tester,
            theme: brightness == Brightness.dark
                ? ThemeConfig.getDarkTheme()
                : ThemeConfig.getLightTheme(),
            textScale: textScale,
          );
          await type(tester, editor, 'Peo');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();

          void expectAligned() {
            final scope = find.byType(TagScopeChip);
            final parent = tester.renderObject<RenderParagraph>(
              find.descendant(of: scope, matching: find.text('People')),
            );
            final editable = tester
                .state<EditableTextState>(
                  find.descendant(
                    of: scope,
                    matching: find.byType(EditableText),
                  ),
                )
                .renderEditable;
            final parentBaseline = parent
                .localToGlobal(
                  Offset(
                    0,
                    parent.getDryBaseline(
                      parent.constraints,
                      TextBaseline.alphabetic,
                    )!,
                  ),
                )
                .dy;
            final childBaseline = editable
                .localToGlobal(
                  Offset(
                    0,
                    editable.getDryBaseline(
                      editable.constraints,
                      TextBaseline.alphabetic,
                    )!,
                  ),
                )
                .dy;
            expect(childBaseline, closeTo(parentBaseline, .5));
          }

          expectAligned();
          await type(tester, editor, 'Alice');
          expectAligned();
          await type(
            tester,
            editor,
            'người',
            composing: const TextRange(start: 0, end: 5),
          );
          expectAligned();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'entering a parent places the real child caret inside its inline chip',
    (tester) async {
      final editor = await mount(tester);
      await type(tester, editor, 'Peo');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(editor.parent, 'People');
      expect(editor.added, isEmpty);
      expect(
        editor.inputKey.currentState!.controller.textWithoutReplacements,
        isEmpty,
      );
      expect(find.text('Alice'), findsOneWidget);
      final childEditor = find.descendant(
        of: find.byType(TagScopeChip),
        matching: find.byType(EditableText),
      );
      expect(childEditor, findsOneWidget);
      final editable = tester
          .state<EditableTextState>(childEditor)
          .renderEditable;
      final caret = editable.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      final chipRect = tester.getRect(find.byType(TagScopeChip));
      expect(chipRect.contains(editable.localToGlobal(caret.topLeft)), isTrue);
      expect(
        chipRect.contains(editable.localToGlobal(caret.bottomRight)),
        isTrue,
      );
      await type(tester, editor, 'Alice');
      final typedCaret = editable.getLocalRectForCaret(
        const TextPosition(offset: 5),
      );
      final typedChipRect = tester.getRect(find.byType(TagScopeChip));
      expect(
        typedChipRect.contains(editable.localToGlobal(typedCaret.bottomRight)),
        isTrue,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(
        editor.inputKey.currentState!.controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      expect(editor.tags, ['existing']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a typed parent supports repeated children and a visible exit', (
    tester,
  ) async {
    final editor = await mount(tester, language: 'vi');
    await type(tester, editor, 'Gia đình');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(editor.parent, 'Gia đình');
    for (final child in ['Ảnh', 'Du lịch']) {
      await type(tester, editor, child);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor.parent, 'Gia đình');
    }
    expect(editor.added, ['Gia đình:Ảnh', 'Gia đình:Du lịch']);
    await tester.tap(
      find.descendant(
        of: find.byType(TagScopeChip),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(editor.parent, isNull);
    expect(editor.tags, containsAll(['existing', 'Ảnh', 'Du lịch']));
  });

  testWidgets(
    'arrow navigation then Enter picks the selected child suggestion',
    (tester) async {
      final editor = await mount(tester);
      await type(tester, editor, 'Peo');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await type(tester, editor, 'B');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor.added, ['People:Bob']);
      expect(editor.parent, 'People');
    },
  );

  testWidgets('Shift+Right selects text instead of entering a parent', (
    tester,
  ) async {
    final editor = await mount(tester);
    await type(tester, editor, 'Peo');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(editor.parent, isNull);
    expect(editor.draft, 'Peo');
  });

  testWidgets('composition is not interrupted by parent shortcuts', (
    tester,
  ) async {
    final editor = await mount(tester);
    await type(
      tester,
      editor,
      'người',
      composing: const TextRange(start: 1, end: 6),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(editor.parent, isNull);
  });

  testWidgets('Escape leaves a parent and preserves assigned tags', (
    tester,
  ) async {
    final editor = await mount(tester);
    await type(tester, editor, 'Peo');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(editor.parent, isNull);
    expect(editor.tags, ['existing']);
  });

  testWidgets('suggestions open upward near the bottom of a narrow viewport', (
    tester,
  ) async {
    final editor = await mount(tester, alignment: Alignment.bottomCenter);
    await type(tester, editor, 'Peo');
    final suggestion = find.text('People');
    expect(
      tester.getBottomLeft(suggestion).dy,
      lessThan(tester.getTopLeft(find.byType(TextField)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard navigation scrolls the highlighted child into view', (
    tester,
  ) async {
    final editor = await mount(tester);
    await type(tester, editor, 'Peo');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    editor.setChildren(List.generate(9, (index) => 'Child $index'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('Child 8').hitTestable(), findsOneWidget);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.added, ['People:Child 8']);
  });

  testWidgets('Escape dismisses suggestions until the draft changes', (
    tester,
  ) async {
    final editor = await mount(tester);
    await type(tester, editor, 'Peo');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('People'), findsNothing);
    expect(editor.draft, 'Peo');
    await type(tester, editor, 'Peop');
    expect(find.text('People'), findsOneWidget);
  });

  testWidgets('removing an assigned chip keeps the pending child draft', (
    tester,
  ) async {
    final editor = await mount(tester);
    await type(tester, editor, 'Peo');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await type(tester, editor, 'Carol');
    final chip = tester.widget<TagInputChip>(find.byType(TagInputChip));
    chip.onDeleted('existing');
    await tester.pumpAndSettle();
    expect(editor.parent, 'People');
    expect(editor.draft, 'Carol');
    expect(
      editor.inputKey.currentState!.controller.textWithoutReplacements,
      'Carol',
    );
    expect(
      editor.inputKey.currentState!.controller.selection,
      const TextSelection.collapsed(offset: 5),
    );
  });
}
