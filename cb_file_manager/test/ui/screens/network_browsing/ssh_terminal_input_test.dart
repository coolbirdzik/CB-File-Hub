import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('terminal attaches native input to its containing Flutter view', (
    tester,
  ) async {
    final terminal = Terminal();
    await tester.pumpWidget(
      MaterialApp(home: TerminalView(terminal, autofocus: true)),
    );
    await tester.pumpAndSettle();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.setClientArgs?['viewId'], tester.view.viewId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing, IME commit and terminal keys reach the output stream', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);
    await tester.pumpWidget(
      MaterialApp(home: TerminalView(terminal, autofocus: true)),
    );
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('pwd');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(output.join(), 'pwd\r');
    output.clear();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'tiếng Việt',
        selection: TextSelection.collapsed(offset: 10),
        composing: TextRange(start: 0, end: 10),
      ),
    );
    await tester.pump();
    expect(output, isEmpty);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'tiếng Việt',
        selection: TextSelection.collapsed(offset: 10),
      ),
    );
    await tester.pump();
    expect(output.join(), 'tiếng Việt');
    output.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(output.join(), '\x7f\x1b[A\x03');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'connecting, disconnecting and refocusing reopen the correct client',
    (tester) async {
      final connected = ValueNotifier(false);
      final focus = FocusNode();
      addTearDown(connected.dispose);
      addTearDown(focus.dispose);
      final terminal = Terminal();
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: connected,
            builder: (_, value, _) => TerminalView(
              terminal,
              focusNode: focus,
              autofocus: true,
              readOnly: !value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      connected.value = true;
      await tester.pumpAndSettle();
      expect(tester.testTextInput.setClientArgs?['viewId'], tester.view.viewId);
      connected.value = false;
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      connected.value = true;
      await tester.pumpAndSettle();
      focus.unfocus();
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(tester.testTextInput.setClientArgs?['viewId'], tester.view.viewId);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.testTextInput.hasAnyClients, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('typed command reaches an SSH PTY and its response is rendered', (
    tester,
  ) async {
    late Process server;
    late Directory directory;
    late SSHClient client;
    late SSHSession session;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('cb-terminal-pty-');
      addTearDown(() => directory.delete(recursive: true));
      server = await Process.start('python', [
        'test/support/secure_network_server.py',
        directory.path,
      ]);
      addTearDown(() async {
        server.stdin.writeln('stop');
        await server.stdin.flush();
        await server.exitCode.timeout(const Duration(seconds: 10));
      });
      unawaited(server.stderr.drain<void>());
      final line = await server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 20));
      final config = jsonDecode(line) as Map<String, dynamic>;
      client = SSHClient(
        await SSHSocket.connect('127.0.0.1', config['ssh']),
        username: 'developer',
        onPasswordRequest: () => 'fixture-password',
      );
      addTearDown(client.close);
      await client.authenticated;
      session = await client.shell();
      addTearDown(session.close);
    });
    final terminal = Terminal(
      onOutput: (text) => session.write(utf8.encode(text)),
    );
    final received = Completer<void>();
    final subscription = session.stdout
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen((text) {
          terminal.write(text);
          if (!received.isCompleted &&
              terminal.buffer.getText().contains('echo: terminal input')) {
            received.complete();
          }
        });
    addTearDown(subscription.cancel);
    await tester.pumpWidget(
      MaterialApp(home: TerminalView(terminal, autofocus: true)),
    );
    await tester.pumpAndSettle();
    expect(tester.testTextInput.setClientArgs?['viewId'], tester.view.viewId);
    tester.testTextInput.enterText('terminal input');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    for (var attempt = 0; attempt < 100 && !received.isCompleted; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(terminal.buffer.getText(), contains('echo: terminal input'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    // Finish the PTY exchange while real socket callbacks can still run. Leaving
    // channel writes for widget-test teardown races the fixture shutdown.
    await tester.runAsync(() async {
      session.write(utf8.encode('exit\r'));
      await session.done.timeout(const Duration(seconds: 10));
      await client.flush();
      await client.close();
    });
  }, skip: !const bool.fromEnvironment('CB_SECURE_NETWORK_TEST'));
}
