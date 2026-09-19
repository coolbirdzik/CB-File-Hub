import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('01.01 submits pending text when the field is submitted', (
    tester,
  ) async {
    String? submittedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {},
                  behavior: HitTestBehavior.opaque,
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(child: ColoredBox(color: Colors.white)),
              ),
              Center(
                child: SizedBox(
                  width: 320,
                  child: ChipsInput<String>(
                    values: const <String>[],
                    onChanged: (_) {},
                    onSubmitted: (value) => submittedValue = value,
                    chipBuilder: (context, value) => Chip(label: Text(value)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'urgent');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(submittedValue, equals('urgent'));
  });

  testWidgets('01.02 Ctrl+A replaces only draft text and preserves chips', (
    tester,
  ) async {
    final key = GlobalKey<ChipsInputState<String>>();
    String? draftText;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChipsInput<String>(
            key: key,
            values: const <String>['existing', 'favorite'],
            onChanged: (_) {},
            onTextChanged: (value) => draftText = value,
            chipBuilder: (context, value) => Chip(label: Text(value)),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\uFFFE\uFFFEold draft',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final controller = key.currentState!.controller;
    expect(
      controller.selection,
      const TextSelection(baseOffset: 2, extentOffset: 11),
    );

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\uFFFE\uFFFEnew',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(controller.textWithReplacements, '\uFFFE\uFFFEnew');
    expect(controller.textWithoutReplacements, 'new');
    expect(draftText, 'new');
    expect(find.text('existing'), findsOneWidget);
    expect(find.text('favorite'), findsOneWidget);
  });

  testWidgets('01.03 ":" on a suggestion scopes the field to that parent', (
    tester,
  ) async {
    final scopeChanges = <String?>[];
    String? draftText;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: ChipsInput<String>(
            values: const <String>[],
            suggestions: const <String>['Actress', 'Album'],
            enableColonAutocomplete: true,
            onScopeChanged: scopeChanges.add,
            onChanged: (_) {},
            onTextChanged: (value) => draftText = value,
            chipBuilder: (context, value) => Chip(label: Text(value)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'act');
    await tester.pump();

    // ":" arrives as shift+";" — the handler reads event.character, not the key.
    await simulateKeyDownEvent(LogicalKeyboardKey.semicolon, character: ':');
    await simulateKeyUpEvent(LogicalKeyboardKey.semicolon);
    await tester.pumpAndSettle();

    expect(scopeChanges, equals(<String?>['Actress']));
    // The parent moves into the pill, so the draft starts over on the child.
    expect(draftText, isEmpty);
  });

  testWidgets(
    '01.04 Backspace on an empty draft leaves the scope, not a chip',
    (tester) async {
      final scopeChanges = <String?>[];
      var chipsChanged = false;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: ChipsInput<String>(
              values: const <String>['existing'],
              scopeParent: 'Actress',
              onScopeChanged: scopeChanges.add,
              onChanged: (_) => chipsChanged = true,
              chipBuilder: (context, value) => Chip(label: Text(value)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pumpAndSettle();

      expect(scopeChanges, equals(<String?>[null]));
      expect(chipsChanged, isFalse);
    },
  );

  testWidgets('01.05 the scope pill names the parent and its "x" leaves it', (
    tester,
  ) async {
    final scopeChanges = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: ChipsInput<String>(
            values: const <String>['existing'],
            scopeParent: 'Actress',
            onScopeChanged: scopeChanges.add,
            onChanged: (_) {},
            chipBuilder: (context, value) => Chip(label: Text(value)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TagScopeChip, 'Actress'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(TagScopeChip),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();

    expect(scopeChanges, equals(<String?>[null]));
  });
}
