import 'package:cb_file_manager/ui/tab_manager/core/tab_keyboard_shortcuts.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/desktop_keyboard_test_support.dart';

Widget host(List<Intent> invoked, {Widget? child}) => MaterialApp(
  home: Shortcuts(
    shortcuts: tabKeyboardShortcuts(),
    child: Actions(
      actions: {
        for (final type in [
          CreateNewTabIntent,
          CloseTabIntent,
          CreateNewWindowIntent,
          SwitchToTabIntent,
          CycleTabIntent,
          ToggleSplitViewIntent,
        ])
          type: CallbackAction<Intent>(
            onInvoke: (intent) => invoked.add(intent),
          ),
      },
      child: Focus(autofocus: true, child: Scaffold(body: child)),
    ),
  ),
);

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    platformTestWidgets(
      '$platform tab bindings use the platform command modifier',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final invoked = <Intent>[];
        await tester.pumpWidget(host(invoked));
        await tester.pump();
        final modifier = platform == TargetPlatform.macOS
            ? LogicalKeyboardKey.metaLeft
            : LogicalKeyboardKey.controlLeft;
        for (final key in [
          LogicalKeyboardKey.keyT,
          LogicalKeyboardKey.keyW,
          LogicalKeyboardKey.backslash,
        ]) {
          await press(tester, key, modifiers: [modifier], repeat: true);
        }
        expect(invoked.map((intent) => intent.runtimeType), [
          CreateNewTabIntent,
          CloseTabIntent,
          ToggleSplitViewIntent,
        ]);
        for (final key in [
          LogicalKeyboardKey.digit1,
          LogicalKeyboardKey.digit5,
          LogicalKeyboardKey.digit9,
        ]) {
          await press(tester, key, modifiers: [modifier]);
        }
        expect(
          invoked.whereType<SwitchToTabIntent>().map(
            (intent) => intent.tabIndex,
          ),
          [0, 4, 8],
        );
        await press(tester, LogicalKeyboardKey.keyN, modifiers: [modifier]);
        expect(
          invoked.last,
          platform == TargetPlatform.macOS
              ? isA<CreateNewWindowIntent>()
              : isA<CreateNewTabIntent>(),
        );
        await press(
          tester,
          LogicalKeyboardKey.tab,
          modifiers: [LogicalKeyboardKey.controlLeft],
        );
        await press(
          tester,
          LogicalKeyboardKey.tab,
          modifiers: [
            LogicalKeyboardKey.controlLeft,
            LogicalKeyboardKey.shiftLeft,
          ],
        );
        expect(
          invoked.whereType<CycleTabIntent>().map((intent) => intent.delta),
          [1, -1],
        );
        final count = invoked.length;
        await press(tester, LogicalKeyboardKey.keyW);
        await press(
          tester,
          LogicalKeyboardKey.keyW,
          modifiers: [modifier, LogicalKeyboardKey.shiftLeft],
        );
        expect(invoked, hasLength(count));
      },
    );
  }

  platformTestWidgets(
    'macOS bracket cycling and Ctrl aliases do not consume new-folder chord',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final invoked = <Intent>[];
      await tester.pumpWidget(host(invoked));
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.bracketLeft,
        LogicalKeyboardKey.bracketRight,
      ]) {
        await press(
          tester,
          key,
          modifiers: [
            LogicalKeyboardKey.metaLeft,
            LogicalKeyboardKey.shiftLeft,
          ],
        );
      }
      expect(
        invoked.whereType<CycleTabIntent>().map((intent) => intent.delta),
        [-1, 1],
      );
      await press(
        tester,
        LogicalKeyboardKey.keyW,
        modifiers: [LogicalKeyboardKey.controlLeft],
      );
      expect(invoked.last, isA<CloseTabIntent>());
      final count = invoked.length;
      await press(
        tester,
        LogicalKeyboardKey.keyN,
        modifiers: [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft],
      );
      expect(invoked, hasLength(count));
    },
  );

  platformTestWidgets(
    'Cmd+W closes the active tab while editing, then handles the last and empty tab',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final tabs = TabManagerBloc();
      addTearDown(tabs.close);
      for (final path in ['#home', '#settings']) {
        final changed = tabs.stream.first;
        tabs.add(AddTab(path: path));
        await tester.runAsync(() => changed);
      }
      final first = tabs.state.tabs.first.id;
      await tester.pumpWidget(
        MaterialApp(
          home: Shortcuts(
            shortcuts: tabKeyboardShortcuts(),
            child: Actions(
              actions: {
                CloseTabIntent: CallbackAction<CloseTabIntent>(
                  onInvoke: (_) {
                    final active = tabs.state.activeTab;
                    if (active != null) tabs.add(CloseTab(active.id));
                    return null;
                  },
                ),
              },
              child: const Scaffold(body: TextField(autofocus: true)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tabs.state.activeTab!.path, '#settings');
      await press(
        tester,
        LogicalKeyboardKey.keyW,
        modifiers: [LogicalKeyboardKey.metaLeft],
        repeat: true,
      );
      expect(tabs.state.tabs, hasLength(1));
      expect(tabs.state.activeTabId, first);
      await press(
        tester,
        LogicalKeyboardKey.keyW,
        modifiers: [LogicalKeyboardKey.metaLeft],
      );
      expect(tabs.state.tabs, isEmpty);
      expect(tabs.state.activeTab, isNull);
      await press(
        tester,
        LogicalKeyboardKey.keyW,
        modifiers: [LogicalKeyboardKey.metaLeft],
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      // Closing a tab schedules the existing thumbnail-cache persistence timer.
      await tester.pump(const Duration(seconds: 11));
    },
  );

  platformTestWidgets('dialog focus does not close the tab behind it', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final invoked = <Intent>[];
    late BuildContext homeContext;
    await tester.pumpWidget(
      host(
        invoked,
        child: Builder(
          builder: (context) {
            homeContext = context;
            return const Text('files');
          },
        ),
      ),
    );
    await tester.pump();
    showDialog<void>(
      context: homeContext,
      builder: (_) => const AlertDialog(content: TextField(autofocus: true)),
    );
    await tester.pumpAndSettle();
    await press(
      tester,
      LogicalKeyboardKey.keyW,
      modifiers: [LogicalKeyboardKey.metaLeft],
    );
    expect(invoked, isEmpty);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
