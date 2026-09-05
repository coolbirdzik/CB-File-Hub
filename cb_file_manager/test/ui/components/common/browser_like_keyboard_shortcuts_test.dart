// Covers the one place every screen's keyboard bindings now come from.
//
// The tags page used to re-derive its own smaller set by hand — Ctrl+A, Ctrl+F
// and F5, but no F2, no Delete, no Escape — which is why renaming a tag with
// the keyboard did nothing. Routing it through `handleBasic` fixed that, and
// these tests hold the shared contract so the next screen to adopt it gets the
// same behaviour rather than another hand-rolled subset.
import 'package:cb_file_manager/ui/components/common/browser_like_keyboard_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Presses [key], routing the event through `handleBasic` with whichever
/// callbacks the test cares about, and reports what it did with it.
Future<KeyEventResult> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  List<LogicalKeyboardKey> holding = const <LogicalKeyboardKey>[],
  bool isDesktop = true,
  VoidCallback? onEscape,
  VoidCallback? onRefresh,
  VoidCallback? onSelectAll,
  void Function(bool permanent)? onDelete,
  VoidCallback? onRename,
  VoidCallback? onSearch,
}) async {
  KeyEventResult result = KeyEventResult.ignored;

  bool handler(KeyEvent event) {
    final KeyEventResult outcome = BrowserLikeKeyboardShortcuts.handleBasic(
      isDesktop: isDesktop,
      event: event,
      onEscape: onEscape,
      onRefresh: onRefresh,
      onSelectAll: onSelectAll,
      onDelete: onDelete,
      onRename: onRename,
      onSearch: onSearch,
    );
    // Every event is offered to the handler, as it is in the app, but only the
    // key-down carries the verdict: the key-up that follows always reports
    // "ignored" and would otherwise overwrite it.
    if (event is KeyDownEvent) {
      result = outcome;
    }
    return outcome == KeyEventResult.handled;
  }

  HardwareKeyboard.instance.addHandler(handler);
  try {
    for (final modifier in holding) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyEvent(key);
  } finally {
    for (final modifier in holding.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    HardwareKeyboard.instance.removeHandler(handler);
  }
  return result;
}

void main() {
  testWidgets('F2 renames', (tester) async {
    var renames = 0;
    final result = await _press(
      tester,
      LogicalKeyboardKey.f2,
      onRename: () => renames++,
    );

    expect(result, KeyEventResult.handled);
    expect(renames, 1);
  });

  testWidgets('F2 without a rename target is left for someone else', (
    tester,
  ) async {
    // A screen with nothing selected passes no callback; the event must stay
    // unhandled rather than being silently swallowed.
    final result = await _press(tester, LogicalKeyboardKey.f2);
    expect(result, KeyEventResult.ignored);
  });

  testWidgets('Delete deletes, and Shift asks for the permanent kind', (
    tester,
  ) async {
    bool? permanent;

    await _press(
      tester,
      LogicalKeyboardKey.delete,
      onDelete: (value) => permanent = value,
    );
    expect(permanent, isFalse);

    await _press(
      tester,
      LogicalKeyboardKey.delete,
      holding: const [LogicalKeyboardKey.shiftLeft],
      onDelete: (value) => permanent = value,
    );
    expect(permanent, isTrue);
  });

  testWidgets('Escape, F5 and Ctrl+R, Ctrl+A and Ctrl+F all route', (
    tester,
  ) async {
    var escapes = 0;
    var refreshes = 0;
    var selectAlls = 0;
    var searches = 0;

    await _press(tester, LogicalKeyboardKey.escape, onEscape: () => escapes++);
    await _press(tester, LogicalKeyboardKey.f5, onRefresh: () => refreshes++);
    await _press(
      tester,
      LogicalKeyboardKey.keyR,
      holding: const [LogicalKeyboardKey.controlLeft],
      onRefresh: () => refreshes++,
    );
    await _press(
      tester,
      LogicalKeyboardKey.keyA,
      holding: const [LogicalKeyboardKey.controlLeft],
      onSelectAll: () => selectAlls++,
    );
    await _press(
      tester,
      LogicalKeyboardKey.keyF,
      holding: const [LogicalKeyboardKey.controlLeft],
      onSearch: () => searches++,
    );

    expect(escapes, 1);
    expect(refreshes, 2);
    expect(selectAlls, 1);
    expect(searches, 1);
  });

  testWidgets('an unmodified letter is not mistaken for a shortcut', (
    tester,
  ) async {
    var selectAlls = 0;
    final result = await _press(
      tester,
      LogicalKeyboardKey.keyA,
      onSelectAll: () => selectAlls++,
    );

    expect(result, KeyEventResult.ignored);
    expect(selectAlls, 0);
  });

  testWidgets('nothing fires on a touch platform', (tester) async {
    var renames = 0;
    final result = await _press(
      tester,
      LogicalKeyboardKey.f2,
      isDesktop: false,
      onRename: () => renames++,
    );

    expect(result, KeyEventResult.ignored);
    expect(renames, 0);
  });

  testWidgets('typing in a text field is never a shortcut', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(focusNode: focusNode, autofocus: true)),
      ),
    );
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);

    var deletes = 0;
    var renames = 0;
    final result = await _press(
      tester,
      LogicalKeyboardKey.delete,
      onDelete: (_) => deletes++,
      onRename: () => renames++,
    );

    // Pressing Delete while renaming must edit the name, not delete the file.
    expect(result, KeyEventResult.ignored);
    expect(deletes, 0);
    expect(renames, 0);
  });
}
