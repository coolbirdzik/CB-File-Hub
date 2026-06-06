import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/utils/fluent_background.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'tab_manager.dart';
import 'tabbed_folder/tabbed_folder_list_screen.dart';

/// Which pane is currently focused in a split-pane view.
enum SplitPaneFocus { left, right }

/// Displays two [TabbedFolderListScreen] panes side-by-side within a single tab.
///
/// A SINGLE shared address bar / action bar is rendered at the top.
/// Clicking into a pane focuses it — the shared bar then reflects that pane.
/// The user can drag the divider to resize the two panes.
class SplitPaneView extends StatefulWidget {
  /// The tab ID owning this split view (used so the right pane has a stable key).
  final String tabId;

  /// Path shown in the left pane.
  final String leftPath;

  /// Path shown in the right pane.
  final String rightPath;

  /// File name to highlight/scroll to in the left pane when it opens.
  final String? highlightedFileName;

  const SplitPaneView({
    Key? key,
    required this.tabId,
    required this.leftPath,
    required this.rightPath,
    this.highlightedFileName,
  }) : super(key: key);

  @override
  State<SplitPaneView> createState() => _SplitPaneViewState();
}

class _SplitPaneViewState extends State<SplitPaneView> {
  static const double _dividerWidth = 6.0;
  static const double _minPaneWidth = 240.0;

  /// Which pane is currently focused (shared bar reflects this pane).
  SplitPaneFocus _focus = SplitPaneFocus.left;

  /// Ratio of left pane width to total width (0 < _ratio < 1).
  double _ratio = 0.5;

  /// Notifiers that each pane pushes its current appbar data into.
  late final ValueNotifier<SplitPaneAppBarData?> _leftBarNotifier;
  late final ValueNotifier<SplitPaneAppBarData?> _rightBarNotifier;

  String get _rightTabId => '${widget.tabId}_split';

  @override
  void initState() {
    super.initState();
    _leftBarNotifier = ValueNotifier(null);
    _rightBarNotifier = ValueNotifier(null);
    // Rebuild whenever the focused bar's data changes.
    _leftBarNotifier.addListener(_onBarChanged);
    _rightBarNotifier.addListener(_onBarChanged);
  }

  @override
  void dispose() {
    _leftBarNotifier.removeListener(_onBarChanged);
    _rightBarNotifier.removeListener(_onBarChanged);
    _leftBarNotifier.dispose();
    _rightBarNotifier.dispose();
    super.dispose();
  }

  void _onBarChanged() {
    if (mounted) setState(() {});
  }

  void _setFocus(SplitPaneFocus pane) {
    if (_focus != pane) {
      setState(() => _focus = pane);
    }
  }

  void _onDividerDrag(DragUpdateDetails details, BoxConstraints constraints) {
    setState(() {
      final totalWidth = constraints.maxWidth - _dividerWidth;
      _ratio = (_ratio * totalWidth + details.delta.dx) / totalWidth;
      final minRatio = _minPaneWidth / totalWidth;
      final maxRatio = 1.0 - minRatio;
      _ratio = _ratio.clamp(minRatio, maxRatio);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusColor = theme.colorScheme.primary;
    const borderWidth = 2.0;

    // Current bar data from the focused pane.
    final activeBar = _focus == SplitPaneFocus.left
        ? _leftBarNotifier.value
        : _rightBarNotifier.value;

    // Build shared top bar.
    final Widget sharedBar = FluentBackground.appBar(
      context: context,
      title: activeBar?.titleWidget ?? const SizedBox.shrink(),
      actions: [
        ...(activeBar?.actions ?? []),
        const SizedBox(width: 4),
        _CloseSplitButton(tabId: widget.tabId),
        const SizedBox(width: 4),
      ],
      blurAmount: 12.0,
      opacity: 0.6,
    );

    return LayoutBuilder(builder: (context, constraints) {
      final totalWidth = constraints.maxWidth - _dividerWidth;
      final leftWidth = (totalWidth * _ratio).clamp(
        _minPaneWidth,
        totalWidth - _minPaneWidth,
      );
      final rightWidth = totalWidth - leftWidth;

      final leftPane = _PaneContainer(
        width: leftWidth,
        isFocused: _focus == SplitPaneFocus.left,
        focusColor: focusColor,
        borderWidth: borderWidth,
        onTap: () => _setFocus(SplitPaneFocus.left),
        child: TabbedFolderListScreen(
          key: ValueKey('${widget.tabId}_left'),
          path: widget.leftPath,
          tabId: widget.tabId,
          appBarDataNotifier: _leftBarNotifier,
          highlightedFileName: widget.highlightedFileName,
        ),
      );

      final rightPane = _PaneContainer(
        width: rightWidth,
        isFocused: _focus == SplitPaneFocus.right,
        focusColor: focusColor,
        borderWidth: borderWidth,
        onTap: () => _setFocus(SplitPaneFocus.right),
        child: TabbedFolderListScreen(
          key: ValueKey(_rightTabId),
          path: widget.rightPath,
          tabId: _rightTabId,
          appBarDataNotifier: _rightBarNotifier,
        ),
      );

      // Draggable divider.
      final divider = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => _onDividerDrag(d, constraints),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeColumn,
          child: Container(
            width: _dividerWidth,
            height: double.infinity,
            color: theme.dividerColor.withValues(alpha: 0.6),
            child: Center(
              child: Container(
                width: 2,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ),
      );

      return Column(
        children: [
          // Shared address bar — reflects the focused pane.
          sharedBar,
          // Pane row.
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                leftPane,
                divider,
                rightPane,
              ],
            ),
          ),
        ],
      );
    });
  }
}

/// A container with Windows-11-style Mica glass tint when focused.
///
/// Uses [Listener.onPointerDown] instead of GestureDetector so that any click
/// anywhere in the pane (including on file items) reliably transfers focus,
/// without competing with child gesture recognizers.
class _PaneContainer extends StatelessWidget {
  final double width;
  final bool isFocused;
  final Color focusColor;
  final double borderWidth;
  final VoidCallback onTap;
  final Widget child;

  const _PaneContainer({
    required this.width,
    required this.isFocused,
    required this.focusColor,
    required this.borderWidth,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Mica-style tint: focused pane gets a faint primary-tinted luminous overlay.
    // Unfocused pane is slightly dimmed to let the focused one stand out.
    final focusedTintColor = isDark
        ? theme.colorScheme.primary.withValues(alpha: 0.07)
        : theme.colorScheme.primary.withValues(alpha: 0.04);
    final dimColor = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.06);

    return Listener(
      // onPointerDown fires before any child gesture detectors, so it always
      // transfers focus regardless of what the user tapped inside the pane.
      onPointerDown: (_) => onTap(),
      child: SizedBox(
        width: width,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Pane content.
            ClipRect(child: child),

            // Glass tint overlay — AnimatedOpacity for smooth transitions.
            IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: 1.0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      color: isFocused ? focusedTintColor : dimColor,
                    ),
                  ),
                ),
              ),
            ),

            // Focused-pane indicator: 2 dp primary accent line at the top.
            IgnorePointer(
              child: Align(
                alignment: Alignment.topCenter,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isFocused ? 1.0 : 0.0,
                  child: Container(
                    height: 2,
                    color: focusColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Button to close the split-pane view — styled as a standard appbar action.
class _CloseSplitButton extends StatelessWidget {
  final String tabId;

  const _CloseSplitButton({required this.tabId});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(PhosphorIconsLight.columns),
      tooltip: 'Close split view',
      onPressed: () {
        context.read<TabManagerBloc>().add(CloseSplitPane(tabId: tabId));
      },
    );
  }
}
