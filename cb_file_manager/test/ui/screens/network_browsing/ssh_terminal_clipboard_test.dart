import 'dart:async';

import 'package:cb_file_manager/ui/screens/ssh/ssh_terminal_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'network_recovery_test.dart' show host;

void main() {
  late Terminal terminal;
  late TerminalController controller;
  late FocusNode focus;
  late GlobalKey<SshTerminalViewState> view;
  late List<String> output;
  String? clipboard;

  setUp(() {
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          if (call.method == 'Clipboard.getData') {
            return clipboard == null ? null : {'text': clipboard};
          }
          return null;
        });
    output = [];
    terminal = Terminal(onOutput: output.add);
    controller = TerminalController();
    focus = FocusNode();
    view = GlobalKey<SshTerminalViewState>();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    controller.dispose();
    focus.dispose();
  });

  Future<void> pump(WidgetTester tester, {bool readOnly = false}) async {
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SshTerminalView(
            key: view,
            terminal: terminal,
            controller: controller,
            focusNode: focus,
            readOnly: readOnly,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void selectHello() {
    terminal.write('hello world');
    controller.setSelection(
      terminal.buffer.createAnchor(0, 0),
      terminal.buffer.createAnchor(5, 0),
    );
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = true,
    bool shift = false,
    bool meta = false,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  for (final shortcut in ['Ctrl+C', 'Ctrl+Shift+C', 'Ctrl+Insert', 'Cmd+C']) {
    testWidgets(
      '$shortcut copies the terminal selection without remote input',
      (tester) async {
        await pump(tester);
        selectHello();
        await chord(
          tester,
          shortcut == 'Ctrl+Insert'
              ? LogicalKeyboardKey.insert
              : LogicalKeyboardKey.keyC,
          control: shortcut != 'Cmd+C',
          meta: shortcut == 'Cmd+C',
          shift: shortcut == 'Ctrl+Shift+C',
        );
        expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, 'hello');
        expect(output, isEmpty);
      },
    );
  }

  testWidgets(
    'Ctrl+C without a selection interrupts and Ctrl+A reaches the shell',
    (tester) async {
      await pump(tester);
      await chord(tester, LogicalKeyboardKey.keyC);
      await chord(tester, LogicalKeyboardKey.keyA);
      expect(output.join(), '\x03\x01');
    },
  );

  for (final shortcut in ['Ctrl+V', 'Ctrl+Shift+V', 'Shift+Insert', 'Cmd+V']) {
    testWidgets(
      '$shortcut pastes Unicode and multiline text using bracketed paste',
      (tester) async {
        await pump(tester);
        selectHello();
        terminal.write('\x1b[?2004h');
        const text = 'echo tiếng Việt\npwd';
        await Clipboard.setData(const ClipboardData(text: text));
        await chord(
          tester,
          shortcut == 'Shift+Insert'
              ? LogicalKeyboardKey.insert
              : LogicalKeyboardKey.keyV,
          control: shortcut.startsWith('Ctrl'),
          meta: shortcut == 'Cmd+V',
          shift: shortcut.contains('Shift'),
        );
        expect(output.join(), '\x1b[200~$text\x1b[201~');
        expect(controller.selection, isNull);
        expect(focus.hasFocus, isTrue);
      },
    );
  }

  testWidgets('right-click menu copies, pastes and selects scrollback', (
    tester,
  ) async {
    await pump(tester);
    selectHello();
    Future<void> openMenu() async {
      await tester.tapAt(
        tester.getCenter(find.byType(TerminalView)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(
      find.byKey(const ValueKey('context-menu-quick-actions')),
      findsOneWidget,
    );
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, 'hello');
    await openMenu();
    await tester.tap(find.text('Paste Here'));
    await tester.pumpAndSettle();
    expect(output.join(), 'hello');
    terminal.write('\r\n${List.generate(100, (i) => 'line $i').join('\r\n')}');
    await tester.pumpAndSettle();
    await openMenu();
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    await view.currentState!.copySelection();
    final text = (await Clipboard.getData(Clipboard.kTextPlain))!.text!;
    expect(text, contains('hello world'));
    expect(text, contains('line 99'));
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('disconnected terminal can copy but cannot paste', (
    tester,
  ) async {
    await pump(tester, readOnly: true);
    selectHello();
    await view.currentState!.copySelection();
    expect((await Clipboard.getData(Clipboard.kTextPlain))?.text, 'hello');
    await view.currentState!.pasteText();
    await chord(tester, LogicalKeyboardKey.keyV);
    expect(output, isEmpty);
    await tester.tapAt(
      tester.getCenter(find.byType(TerminalView)),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('context-menu-action-paste')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('pending clipboard read is discarded after a disconnect', (
    tester,
  ) async {
    await pump(tester);
    final pending = Completer<Object?>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? pending.future : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final paste = view.currentState!.pasteText();
    await tester.pump();
    await pump(tester, readOnly: true);
    await pump(tester);
    pending.complete({'text': 'must not reach the reconnected shell'});
    await paste;
    expect(output, isEmpty);
  });
}
