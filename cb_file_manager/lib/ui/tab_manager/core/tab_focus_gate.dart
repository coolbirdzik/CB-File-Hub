import 'package:flutter/widgets.dart';

/// Confines keyboard focus to the tab the user is actually looking at.
///
/// The desktop shell keeps every tab mounted inside an [IndexedStack], so a
/// hidden tab's [Focus] node stays attached to the focus tree. Two things then
/// go wrong without a gate:
///
///  * switching tabs leaves the primary focus on the tab the user just left,
///    so Delete / Shift+Delete / Ctrl+C run against an invisible folder;
///  * a tab opened in the background mounts a `Focus(autofocus: true)` and
///    steals the keyboard from the visible tab.
///
/// Each tab gets its own [FocusScope], which keeps the "last focused widget"
/// memory per tab, and the gate hands focus back to that tab when it becomes
/// visible again. Focus landing inside a hidden tab is reported through
/// [onFocusEscaped] so the host can pull it back to the active tab.
class TabFocusGate extends StatefulWidget {
  const TabFocusGate({
    super.key,
    required this.node,
    required this.isActive,
    required this.child,
    this.onFocusEscaped,
  });

  /// Focus scope for this tab. Owned by the host so it survives tab reorders
  /// and content rebuilds.
  final FocusScopeNode node;

  /// Whether this tab is the one currently displayed.
  final bool isActive;

  /// Called when focus lands inside this tab while it is hidden.
  final VoidCallback? onFocusEscaped;

  final Widget child;

  /// Whether the tab containing [context] is the visible one.
  ///
  /// Returns `true` when no gate sits above [context] — shared components are
  /// also used outside the tab shell (dialogs, secondary windows, tests) and
  /// must keep their shortcuts there.
  static bool isActiveTab(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ActiveTabMarker>()?.isActive ??
      true;

  @override
  State<TabFocusGate> createState() => _TabFocusGateState();
}

class _TabFocusGateState extends State<TabFocusGate> {
  bool _restoreScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.node.addListener(_handleNodeFocusChanged);
  }

  @override
  void didUpdateWidget(TabFocusGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.node, widget.node)) {
      oldWidget.node.removeListener(_handleNodeFocusChanged);
      widget.node.addListener(_handleNodeFocusChanged);
    }
    if (widget.isActive && !oldWidget.isActive) {
      _restoreFocusAfterFrame();
    }
  }

  @override
  void dispose() {
    widget.node.removeListener(_handleNodeFocusChanged);
    super.dispose();
  }

  void _handleNodeFocusChanged() {
    if (!widget.isActive && widget.node.hasFocus) {
      widget.onFocusEscaped?.call();
    }
  }

  /// Re-focuses this tab once the frame that activated it has settled, so the
  /// content it wants focused is already attached and focusable again.
  void _restoreFocusAfterFrame() {
    if (_restoreScheduled) return;
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreScheduled = false;
      if (!mounted || !widget.isActive || widget.node.hasFocus) return;

      if (widget.node.focusedChild != null) {
        // Hands the keyboard back to the widget that last held it in this tab.
        widget.node.requestFocus();
        return;
      }

      // Nothing remembered: the tab was never focused, or it was built in the
      // background where [IndexedStack] excludes focus and its `autofocus`
      // request was dropped. Fall back to what the traversal policy would pick
      // first — for the file views that is the shortcut [Focus] wrapping the
      // whole tab.
      final policy =
          FocusTraversalGroup.maybeOf(context) ?? ReadingOrderTraversalPolicy();
      final FocusNode? first = policy.findFirstFocus(
        widget.node,
        ignoreCurrentFocus: true,
      );
      (first ?? widget.node).requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: widget.node,
      child: _ActiveTabMarker(isActive: widget.isActive, child: widget.child),
    );
  }
}

class _ActiveTabMarker extends InheritedWidget {
  const _ActiveTabMarker({required this.isActive, required super.child});

  final bool isActive;

  @override
  bool updateShouldNotify(_ActiveTabMarker oldWidget) =>
      oldWidget.isActive != isActive;
}
