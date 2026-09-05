// Covers the rename editor that replaced the AlertDialog-based rename flow.
//
// What is worth pinning is everything a plain TextField would not give us: the
// extension the user may not edit survives untouched, Escape backs out without
// committing, filesystem-unsafe characters are refused for paths but allowed
// for tags, and confirm stays disabled while the name is one that would fail.
import 'package:cb_file_manager/design_system/cb_theme_builder.dart';
import 'package:cb_file_manager/design_system/primitives/cb_inline_rename.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData _theme() => CbThemeBuilder.build(
  brightness: Brightness.light,
  accent: const Color(0xFF0078D4),
);

Widget _host(Widget child) => MaterialApp(
  theme: _theme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('CbInlineRenameField', () {
    testWidgets('renders the locked suffix without putting it in the field', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'report');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 240,
            child: CbInlineRenameField(
              controller: controller,
              focusNode: focusNode,
              onCommit: () {},
              onCancel: () {},
              lockedSuffix: '.pdf',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('.pdf'), findsOneWidget);
      expect(controller.text, 'report');
    });

    testWidgets('commits on Enter and cancels on Escape', (tester) async {
      final controller = TextEditingController(text: 'report');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      var commits = 0;
      var cancels = 0;

      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 240,
            child: CbInlineRenameField(
              controller: controller,
              focusNode: focusNode,
              onCommit: () => commits++,
              onCancel: () => cancels++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(commits, 1);
      expect(cancels, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(cancels, 1);
      expect(commits, 1);
    });

    testWidgets('refuses characters no filesystem accepts', (tester) async {
      final controller = TextEditingController(text: 'report');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 240,
            child: CbInlineRenameField(
              controller: controller,
              focusNode: focusNode,
              onCommit: () {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'in/valid:name?');
      expect(controller.text, 'invalidname');
    });

    testWidgets('lets free-form labels through when unrestricted', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'work');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 240,
            child: CbInlineRenameField(
              controller: controller,
              focusNode: focusNode,
              onCommit: () {},
              onCancel: () {},
              // Tags are labels, not paths.
              restrictToFilesystemSafeCharacters: false,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'work/2026: q1');
      expect(controller.text, 'work/2026: q1');
    });

    testWidgets('blur is reported to the caller, not acted on', (tester) async {
      final controller = TextEditingController(text: 'work');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      var blurs = 0;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 240,
            child: CbInlineRenameField(
              controller: controller,
              focusNode: focusNode,
              onCommit: () {},
              onCancel: () {},
              onBlur: () => blurs++,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      focusNode.unfocus();
      await tester.pump();
      expect(blurs, 1);
    });
  });

  group('showCbInlineRename', () {
    testWidgets('returns the trimmed new name', (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final result = showCbInlineRename(
        context: hostContext,
        title: 'Rename file',
        initialValue: 'report',
        confirmLabel: 'Rename',
        cancelLabel: 'Cancel',
        lockedSuffix: '.pdf',
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  quarterly report  ');
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(await result, 'quarterly report');
    });

    testWidgets('blocks confirm while the name is invalid', (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final result = showCbInlineRename(
        context: hostContext,
        title: 'Rename tag',
        initialValue: 'invoices',
        confirmLabel: 'Rename',
        cancelLabel: 'Cancel',
        validator: (value) =>
            value.trim() == 'taken' ? 'That name is already used' : null,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'taken');
      await tester.pump();
      expect(find.text('That name is already used'), findsOneWidget);

      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      // Still open: the disabled confirm swallowed the tap.
      expect(find.text('That name is already used'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'receipts');
      await tester.pump();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(await result, 'receipts');
    });

    testWidgets('an empty name cannot be committed', (tester) async {
      late BuildContext hostContext;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final result = showCbInlineRename(
        context: hostContext,
        title: 'Rename folder',
        initialValue: 'archive',
        confirmLabel: 'Rename',
        cancelLabel: 'Cancel',
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(await result, isNull);
    });
  });
}
