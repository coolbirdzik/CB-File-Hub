import 'package:cb_file_manager/ui/tab_manager/core/tab_focus_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal stand-in for the desktop tab shell: every tab stays mounted inside
/// an [IndexedStack], each one wrapped in a [TabFocusGate], and each one hosts
/// a `Focus(autofocus: true)` that reacts to Delete the way the real file views
/// do.
class _TabShell extends StatefulWidget {
  const _TabShell({super.key, required this.initialTabs, required this.log});

  final List<String> initialTabs;
  final List<String> log;

  @override
  State<_TabShell> createState() => _TabShellState();
}

class _TabShellState extends State<_TabShell> {
  late final List<String> _tabs = <String>[...widget.initialTabs];
  final Map<String, FocusScopeNode> _scopes = <String, FocusScopeNode>{};
  int _activeIndex = 0;

  FocusScopeNode _scopeFor(String id) =>
      _scopes.putIfAbsent(id, () => FocusScopeNode(debugLabel: id));

  void switchToTab(int index) => setState(() => _activeIndex = index);

  void openBackgroundTab(String id) => setState(() => _tabs.add(id));

  void _restoreFocusToActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = _scopes[_tabs[_activeIndex]];
      if (scope == null || scope.hasFocus) return;
      scope.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _scopes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: IndexedStack(
        index: _activeIndex,
        children: <Widget>[
          for (int i = 0; i < _tabs.length; i++)
            TabFocusGate(
              key: ValueKey<String>(_tabs[i]),
              node: _scopeFor(_tabs[i]),
              isActive: i == _activeIndex,
              onFocusEscaped: _restoreFocusToActiveTab,
              child: _TabContent(tabId: _tabs[i], log: widget.log),
            ),
        ],
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({required this.tabId, required this.log});

  final String tabId;
  final List<String> log;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent event) {
        if (event is! KeyDownEvent ||
            event.logicalKey != LogicalKeyboardKey.delete) {
          return KeyEventResult.ignored;
        }
        if (!TabFocusGate.isActiveTab(context)) {
          log.add('$tabId:blocked');
          return KeyEventResult.ignored;
        }
        log.add('$tabId:delete');
        return KeyEventResult.handled;
      },
      child: const SizedBox.expand(),
    );
  }
}

void main() {
  group('TabFocusGate', () {
    testWidgets('Delete only reaches the tab that is on screen', (
      WidgetTester tester,
    ) async {
      final log = <String>[];
      final shellKey = GlobalKey<_TabShellState>();
      await tester.pumpWidget(
        _TabShell(
          key: shellKey,
          initialTabs: const <String>['tab1', 'tab2'],
          log: log,
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(log, <String>['tab1:delete']);

      shellKey.currentState!.switchToTab(1);
      await tester.pumpAndSettle();

      log.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(log, <String>['tab2:delete']);

      // Switching back hands the keyboard to the tab that is visible again.
      shellKey.currentState!.switchToTab(0);
      await tester.pumpAndSettle();

      log.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(log, <String>['tab1:delete']);
    });

    testWidgets('a tab opened in the background does not steal the keyboard', (
      WidgetTester tester,
    ) async {
      final log = <String>[];
      final shellKey = GlobalKey<_TabShellState>();
      await tester.pumpWidget(
        _TabShell(key: shellKey, initialTabs: const <String>['tab1'], log: log),
      );
      await tester.pumpAndSettle();

      shellKey.currentState!.openBackgroundTab('tab2');
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      expect(log, <String>['tab1:delete']);
    });

    testWidgets('isActiveTab reports false inside a hidden tab', (
      WidgetTester tester,
    ) async {
      late BuildContext hiddenContext;
      late BuildContext visibleContext;

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: IndexedStack(
            index: 0,
            children: <Widget>[
              TabFocusGate(
                node: FocusScopeNode(debugLabel: 'visible'),
                isActive: true,
                child: Builder(
                  builder: (BuildContext context) {
                    visibleContext = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
              TabFocusGate(
                node: FocusScopeNode(debugLabel: 'hidden'),
                isActive: false,
                child: Builder(
                  builder: (BuildContext context) {
                    hiddenContext = context;
                    return const SizedBox.expand();
                  },
                ),
              ),
            ],
          ),
        ),
      );

      expect(TabFocusGate.isActiveTab(visibleContext), isTrue);
      expect(TabFocusGate.isActiveTab(hiddenContext), isFalse);
    });

    testWidgets('defaults to active when no gate is present', (
      WidgetTester tester,
    ) async {
      late BuildContext plainContext;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            plainContext = context;
            return const SizedBox.shrink();
          },
        ),
      );

      expect(TabFocusGate.isActiveTab(plainContext), isTrue);
    });
  });
}
