import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/services.dart'; // Added import for HapticFeedback
import 'package:phosphor_flutter/phosphor_flutter.dart';
// Import app theme
import 'package:window_manager/window_manager.dart'; // Import window_manager
import 'dart:io'; // Import dart:io for Platform check
import '../../components/common/window_caption_buttons.dart';
import 'desktop_tab_drag_data.dart';
import 'external_tab_drop_controller.dart';
import 'package:cb_file_manager/config/translation_helper.dart';

/// Asks to move a dragged tab to its own window. [geometry] says where the
/// tab is and where the pointer should sit in the new window, so the tab stays
/// under the pointer, as in Chrome.
typedef NativeTabDetachCallback =
    Future<void> Function(
      DesktopTabDragData data,
      Offset globalPosition,
      TabDetachGeometry geometry,
    );

/// A custom TabBar wrapper that translates vertical mouse wheel scrolling
/// to horizontal scrolling of the tab bar, with modern styling.
class ScrollableTabBar extends StatefulWidget {
  final TabController controller;
  final List<Widget> tabs;
  final Color? barBackgroundColor;
  final Color? activeTabBackgroundColor;
  final bool isScrollable;
  final EdgeInsetsGeometry? labelPadding;
  final TabBarIndicatorSize? indicatorSize;
  final ScrollPhysics? physics;
  final Decoration? indicator;
  final TextStyle? labelStyle;
  final TextStyle? unselectedLabelStyle;
  final Color? labelColor;
  final Color? unselectedLabelColor;
  final Function(int)? onTap;
  final VoidCallback? onAddTabPressed;
  final Function(int)? onTabClose; // Added callback for tab closing
  final void Function(int index, Offset globalPosition)? onTabContextMenu;
  final List<DesktopTabDragData>? draggableTabs;
  final Set<String> selectedTabIds;
  final ValueChanged<DesktopTabDragData>? onTabDragStarted;
  final VoidCallback? onTabDragEnded;
  final NativeTabDetachCallback? onNativeTabDragRequested;
  final void Function(int fromIndex, int toIndex)? onTabReorder;
  final void Function(int index, bool shiftPressed)? onTabPrimaryClick;
  final List<Widget> leadingCaptionActions;

  /// Accepts tabs dragged in from other windows: the bar reports its strip
  /// bounds here and shows where hovering tabs would land.
  final ExternalTabDropController? externalTabDrop;

  /// The active tab. The caller's [controller] may only catch up with a new
  /// tab count a frame later, which would flash the highlight on the wrong
  /// tab; when null, [controller]'s index is used.
  final int? activeTabIndex;

  /// Whether the bar stands in for the window's title bar (caption buttons,
  /// drag-to-move, double-click to maximize). Off in a window that keeps its
  /// native frame.
  final bool showWindowControls;

  const ScrollableTabBar({
    super.key,
    required this.controller,
    required this.tabs,
    this.barBackgroundColor,
    this.activeTabBackgroundColor,
    this.isScrollable = true,
    this.labelPadding,
    this.indicatorSize,
    this.physics,
    this.indicator,
    this.labelStyle,
    this.unselectedLabelStyle,
    this.labelColor,
    this.unselectedLabelColor,
    this.onTap,
    this.onAddTabPressed,
    this.onTabClose, // Added parameter
    this.onTabContextMenu,
    this.draggableTabs,
    this.selectedTabIds = const <String>{},
    this.onTabDragStarted,
    this.onTabDragEnded,
    this.onNativeTabDragRequested,
    this.onTabReorder,
    this.onTabPrimaryClick,
    this.leadingCaptionActions = const <Widget>[],
    this.externalTabDrop,
    this.activeTabIndex,
    this.showWindowControls = true,
  });

  @override
  State<ScrollableTabBar> createState() => _ScrollableTabBarState();
}

class _ScrollableTabBarState extends State<ScrollableTabBar> {
  // Create a scroll controller for the horizontal scroll view
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _stripAreaKey = GlobalKey();
  bool _stripBoundsReportScheduled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Reports the strip area after layout. Deduplicated by the controller, so
  /// only real changes (a resize) reach the platform.
  void _scheduleStripBoundsReport() {
    if (widget.externalTabDrop == null || _stripBoundsReportScheduled) return;
    _stripBoundsReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stripBoundsReportScheduled = false;
      final controller = widget.externalTabDrop;
      if (!mounted || controller == null) return;
      final box = _stripAreaKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      controller.reportStripBounds(box.localToGlobal(Offset.zero) & box.size);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Modern tab colors
    final tabBackgroundColor =
        widget.barBackgroundColor ?? theme.scaffoldBackgroundColor;
    final activeTabColor =
        widget.activeTabBackgroundColor ?? tabBackgroundColor;
    final hoverColor = theme.colorScheme.surfaceContainerHigh;

    final customTitleBar = Platform.isWindows && widget.showWindowControls;
    Widget windowCaptionButtons = customTitleBar
        ? WindowCaptionButtons(theme: theme)
        : const SizedBox.shrink();

    // Main container for the entire bar
    return Container(
      height: Platform.isWindows
          ? 50
          : null, // Provide a specific height for the custom title bar on Windows
      decoration: BoxDecoration(color: tabBackgroundColor, boxShadow: const []),
      margin: Platform.isWindows || Platform.isMacOS
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (customTitleBar)
            const DragToMoveArea(
              child: SizedBox(width: 12, height: double.infinity),
            )
          else if (Platform.isWindows)
            const SizedBox(width: 12),
          // Tab strip area (not draggable) so tab drag gestures can win.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                _scheduleStripBoundsReport();
                return Listener(
                  key: _stripAreaKey,
                  onPointerSignal: (PointerSignalEvent event) {
                    if (event is PointerScrollEvent) {
                      // Support both horizontal trackpad gestures and the
                      // vertical mouse wheel while the pointer is over the tab
                      // strip.
                      final delta = event.scrollDelta.dx.abs() > 0
                          ? event.scrollDelta.dx
                          : event.scrollDelta.dy;

                      GestureBinding.instance.pointerSignalResolver.register(
                        event,
                        (_) {},
                      );

                      if (delta == 0.0) return;
                      if (!_scrollController.hasClients) return;

                      final double newPosition =
                          _scrollController.offset + delta;
                      _scrollController.animateTo(
                        newPosition.clamp(
                          _scrollController.position.minScrollExtent,
                          _scrollController.position.maxScrollExtent,
                        ),
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: ScrollConfiguration(
                    behavior: const _NoMouseDragScrollBehavior(),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: _ModernTabBar(
                        viewportWidth: constraints.maxWidth,
                        controller: widget.controller,
                        tabs: widget.tabs,
                        labelColor: isDarkMode
                            ? Colors.white
                            : theme.colorScheme.primary,
                        unselectedLabelColor: isDarkMode
                            ? Colors.white70
                            : theme.colorScheme.onSurface,
                        labelStyle: widget.labelStyle,
                        unselectedLabelStyle: widget.unselectedLabelStyle,
                        onTap: widget.onTap,
                        activeTabColor: activeTabColor,
                        hoverColor: hoverColor,
                        tabBackgroundColor: tabBackgroundColor,
                        onAddTabPressed: widget.onAddTabPressed,
                        onTabClose: widget.onTabClose,
                        onTabContextMenu: widget.onTabContextMenu,
                        draggableTabs: widget.draggableTabs,
                        selectedTabIds: widget.selectedTabIds,
                        onTabDragStarted: widget.onTabDragStarted,
                        onTabDragEnded: widget.onTabDragEnded,
                        onNativeTabDragRequested:
                            widget.onNativeTabDragRequested,
                        onTabReorder: widget.onTabReorder,
                        onTabPrimaryClick: widget.onTabPrimaryClick,
                        externalTabDrop: widget.externalTabDrop,
                        activeTabIndex: widget.activeTabIndex,
                        hasCustomTitleBar:
                            widget.showWindowControls &&
                            (Platform.isWindows || Platform.isMacOS),
                        theme: theme,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (customTitleBar && widget.leadingCaptionActions.isEmpty)
            const DragToMoveArea(
              child: SizedBox(width: 84, height: double.infinity),
            ),
          if (customTitleBar && widget.leadingCaptionActions.isNotEmpty)
            const DragToMoveArea(
              child: SizedBox(width: 24, height: double.infinity),
            ),
          if (widget.leadingCaptionActions.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.leadingCaptionActions,
            ),
          // Window caption buttons.
          windowCaptionButtons,
        ],
      ),
    );
  }
}

class _NoMouseDragScrollBehavior extends MaterialScrollBehavior {
  const _NoMouseDragScrollBehavior();

  // Avoid click-and-drag panning with the mouse on desktop. This prevents
  // the tab strip from scrolling when the user is trying to drag a tab.
  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.unknown,
  };
}

/// Modern tab bar implementation with softer, more elegant styling
class _ModernTabBar extends StatefulWidget {
  final double viewportWidth;
  final TabController controller;
  final List<Widget> tabs;
  final Color? labelColor;
  final Color? unselectedLabelColor;
  final TextStyle? labelStyle;
  final TextStyle? unselectedLabelStyle;
  final Function(int)? onTap;
  final Color activeTabColor;
  final Color hoverColor;
  final Color
  tabBackgroundColor; // This is the background of the tab itself, not the whole bar
  final VoidCallback? onAddTabPressed;
  final Function(int)? onTabClose;
  final void Function(int index, Offset globalPosition)? onTabContextMenu;
  final List<DesktopTabDragData>? draggableTabs;
  final Set<String> selectedTabIds;
  final ValueChanged<DesktopTabDragData>? onTabDragStarted;
  final VoidCallback? onTabDragEnded;
  final NativeTabDetachCallback? onNativeTabDragRequested;
  final void Function(int fromIndex, int toIndex)? onTabReorder;
  final void Function(int index, bool shiftPressed)? onTabPrimaryClick;
  final ExternalTabDropController? externalTabDrop;
  final int? activeTabIndex;
  final bool hasCustomTitleBar;
  final ThemeData theme;

  const _ModernTabBar({
    required this.viewportWidth,
    required this.controller,
    required this.tabs,
    this.labelColor,
    this.unselectedLabelColor,
    this.labelStyle,
    this.unselectedLabelStyle,
    this.onTap,
    required this.activeTabColor,
    required this.hoverColor,
    required this.tabBackgroundColor,
    this.onAddTabPressed,
    this.onTabClose,
    this.onTabContextMenu,
    this.draggableTabs,
    this.selectedTabIds = const <String>{},
    this.onTabDragStarted,
    this.onTabDragEnded,
    this.onNativeTabDragRequested,
    this.onTabReorder,
    this.onTabPrimaryClick,
    this.externalTabDrop,
    this.activeTabIndex,
    this.hasCustomTitleBar = false,
    required this.theme,
  });

  @override
  State<_ModernTabBar> createState() => _ModernTabBarState();
}

class _ModernTabBarState extends State<_ModernTabBar> {
  final GlobalKey _tabRowKey = GlobalKey();
  final GlobalKey _tabStripKey = GlobalKey();
  final GlobalKey _addTabButtonKey = GlobalKey();
  String? _activeDragTabId;
  int? _previewTargetIndex;
  int? _lastReorderFromIndex;
  int? _lastReorderToIndex;
  Offset? _blankPointerDownGlobal;
  DateTime? _lastBlankTapAt;
  Offset? _lastBlankTapGlobal;
  bool _blankDragEligible = false;
  bool _blankDragStarted = false;

  // Native drag: the dragged tab follows the pointer. A copy of it is painted
  // above the row (so neighbours slide underneath) at its slot plus this.
  final ValueNotifier<double> _dragDx = ValueNotifier<double>(0);
  bool _followPointer = false;
  double _dragGrabDx = 0;
  double _dragTabLeft = 0;
  Widget? _draggedTabCopy;
  // Tabs fading out while they move to a new window.
  final Set<String> _leavingTabIds = <String>{};
  // Gap opened for tabs dragged in from another window.
  int? _externalGap;
  String _externalLabel = '';
  // New tabs animate in, except the ones present on the first frame.
  bool _animateEntries = false;
  // A strip that had no tabs (a fresh window) shows its first tabs at once,
  // and tabs dropped into an open gap simply take the ghost's place.
  int _lastBuiltTabCount = 0;
  bool _gapOpenLastBuild = false;

  static const double _blankDragThreshold = 5.0;
  // A tab detaches only this far outside the strip, while another window's tab
  // attaches anywhere inside it: the gap keeps a torn-off tab from snapping
  // straight back into the strip it left.
  static const double _detachBandMargin = 10.0;

  /// Horizontal space one tab takes in the row, margins included.
  static double get _tabSlotWidth =>
      FluentSurfaceTokens.tabWidth + (FluentSurfaceTokens.isMacOS ? 6 : 4);
  static const Duration _doubleClickTimeout = Duration(milliseconds: 350);
  static const double _doubleClickSlop = 22.0;

  // Windows and macOS hide the native title bar, so the blank strip stands in
  // for it: drag to move the window, double-click to maximize/zoom.
  bool get _hasCustomTitleBar => widget.hasCustomTitleBar;

  Future<void> _toggleMaximizeRestore() async {
    if (!_hasCustomTitleBar) return;
    try {
      final isMax = await windowManager.isMaximized();
      if (isMax) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  bool _isBlankStripPosition(Offset globalPosition) {
    if (!_hasCustomTitleBar) return false;

    final stripContext = _tabStripKey.currentContext;
    final rowContext = _tabRowKey.currentContext;
    if (stripContext == null || rowContext == null) return false;

    final stripBox = stripContext.findRenderObject() as RenderBox?;
    final rowBox = rowContext.findRenderObject() as RenderBox?;
    if (stripBox == null || rowBox == null) return false;

    // Treat the strip as "blank" only when the pointer is outside the actual
    // tab row bounds. This avoids starting a window drag when the user drags a
    // tab (reorder/native drag).
    final rowLocal = rowBox.globalToLocal(globalPosition);
    final isOverTabRow =
        rowLocal.dx >= 0 &&
        rowLocal.dx <= rowBox.size.width &&
        rowLocal.dy >= 0 &&
        rowLocal.dy <= rowBox.size.height;
    return !isOverTabRow;
  }

  void _resetBlankDrag() {
    _blankPointerDownGlobal = null;
    _blankDragEligible = false;
    _blankDragStarted = false;
  }

  int _activeDragIndex() {
    final activeTabId = _activeDragTabId;
    final items = widget.draggableTabs;
    if (activeTabId == null || items == null || items.isEmpty) return -1;
    return items.indexWhere((e) => e.tabId == activeTabId);
  }

  RenderBox? _rowBox() {
    final box = _tabRowKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  int _indexOfDragData(DesktopTabDragData data) {
    final items = widget.draggableTabs;
    if (items == null || items.isEmpty) return -1;
    return items.indexWhere((e) => e.tabId == data.tabId);
  }

  int _resolveTargetIndex(Offset globalPosition) {
    final rowContext = _tabRowKey.currentContext;
    if (rowContext == null) return -1;
    final box = rowContext.findRenderObject() as RenderBox?;
    if (box == null || widget.tabs.isEmpty) return -1;

    final local = box.globalToLocal(globalPosition);
    final raw = (local.dx / _tabSlotWidth).floor();
    return raw.clamp(0, widget.tabs.length - 1);
  }

  /// The gap nearest [globalPosition], as the index a dropped tab takes.
  /// While a gap is open its ghost tab counts as that index, and tabs after it
  /// are measured where they would sit without it, so the gap stays put until
  /// the pointer is clearly past a neighbour's middle.
  int _externalInsertIndexAt(Offset globalPosition) {
    final box = _rowBox();
    if (box == null) return widget.tabs.length;
    var slots = box.globalToLocal(globalPosition).dx / _tabSlotWidth;
    final gap = _externalGap;
    if (gap != null) {
      if (slots >= gap && slots < gap + 1) return gap;
      if (slots >= gap + 1) slots -= 1;
    }
    return slots.round().clamp(0, widget.tabs.length);
  }

  void _onExternalHoverChanged() {
    final hover = widget.externalTabDrop?.hover.value;
    final gap = hover == null ? null : _externalInsertIndexAt(hover.position);
    final label = hover?.label ?? '';
    if (gap == _externalGap && label == _externalLabel) return;
    setState(() {
      _externalGap = gap;
      _externalLabel = label;
    });
  }

  bool _isOutsideDetachBand(Offset globalPosition) {
    final box = _tabStripKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return true;
    final top = box.localToGlobal(Offset.zero).dy;
    return globalPosition.dy < top - _detachBandMargin ||
        globalPosition.dy > top + box.size.height + _detachBandMargin;
  }

  /// Where the first tab sits when the strip is not scrolled, which is where a
  /// torn-off window shows the dragged tab.
  Offset _restingFirstTabOrigin() {
    final box = _tabRowKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return const Offset(12, 4);
    final scrolled = Scrollable.maybeOf(context)?.position.pixels ?? 0;
    return box.localToGlobal(Offset.zero) + Offset(scrolled, 0);
  }

  void _beginDrag(DesktopTabDragData data, {Offset? grabOffset}) {
    _activeDragTabId = data.tabId;
    _previewTargetIndex = _indexOfDragData(data);
    _followPointer = grabOffset != null;
    _dragGrabDx = grabOffset?.dx ?? 0;
    _dragTabLeft = _previewTargetIndex! * _tabSlotWidth;
    _dragDx.value = 0;
    _lastReorderFromIndex = null;
    _lastReorderToIndex = null;
    widget.onTabDragStarted?.call(data);
    if (mounted) {
      setState(() {});
    }
  }

  void _endDrag({bool rebuild = true}) {
    if (_activeDragTabId == null) return;
    // _dragDx keeps its value: the released tab settles from there.
    _followPointer = false;
    _activeDragTabId = null;
    _previewTargetIndex = null;
    _lastReorderFromIndex = null;
    _lastReorderToIndex = null;
    widget.onTabDragEnded?.call();
    if (mounted && rebuild) {
      setState(() {});
    }
  }

  void _notifyReorder(DesktopTabDragData data, int toIndex) {
    final fromIndex = _indexOfDragData(data);
    if (fromIndex < 0) return;
    if (toIndex < 0 || toIndex >= widget.tabs.length) return;
    if (fromIndex == toIndex) return;
    if (_lastReorderFromIndex == fromIndex && _lastReorderToIndex == toIndex) {
      return;
    }
    _lastReorderFromIndex = fromIndex;
    _lastReorderToIndex = toIndex;
    _previewTargetIndex = toIndex;
    if (mounted) {
      setState(() {});
    }
    widget.onTabReorder?.call(fromIndex, toIndex);
  }

  /// Moves the dragged tab with the pointer, and reorders once its middle
  /// crosses into a neighbour's slot.
  void _handleNativeReorderMove(
    DesktopTabDragData data,
    Offset globalPosition,
  ) {
    final box = _rowBox();
    final from = _indexOfDragData(data);
    if (box == null || from < 0) return;
    final slot = _tabSlotWidth;
    final maxLeft = math.max(0.0, (widget.tabs.length - 1) * slot);
    final left = (box.globalToLocal(globalPosition).dx - _dragGrabDx).clamp(
      0.0,
      maxLeft,
    );
    _dragTabLeft = left;
    _dragDx.value = left - from * slot;
    final toIndex = ((left + slot / 2) / slot).floor().clamp(
      0,
      widget.tabs.length - 1,
    );
    _notifyReorder(data, toIndex);
  }

  void _handleDragUpdate(DesktopTabDragData data, DragUpdateDetails details) {
    final toIndex = _resolveTargetIndex(details.globalPosition);
    if (toIndex < 0) return;
    _notifyReorder(data, toIndex);
  }

  Future<void> _handleNativeDetachRequest(
    DesktopTabDragData data,
    Offset globalPosition,
    Offset grabOffset,
  ) async {
    // The only tab drags its window instead, so it stays visible.
    final leaving = widget.tabs.length > 1
        ? (widget.selectedTabIds.length > 1 &&
                  widget.selectedTabIds.contains(data.tabId)
              ? widget.selectedTabIds.toSet()
              : <String>{data.tabId})
        : const <String>{};
    final firstTab = _restingFirstTabOrigin();
    final row = _rowBox();
    final rowOrigin = row?.localToGlobal(Offset.zero) ?? Offset.zero;
    final strip = _tabStripKey.currentContext?.findRenderObject();
    final stripBottom = strip is RenderBox && strip.hasSize
        ? strip.localToGlobal(Offset(0, strip.size.height)).dy
        : rowOrigin.dy + (row?.size.height ?? 46);
    final geometry = TabDetachGeometry(
      windowAnchor: firstTab + grabOffset,
      tabRect: Rect.fromLTWH(
        rowOrigin.dx + _dragTabLeft,
        rowOrigin.dy,
        _tabSlotWidth,
        row?.size.height ?? 46,
      ),
      firstTabOrigin: firstTab,
      stripBottom: stripBottom,
    );
    try {
      // Started before the fade below is drawn: the drag preview captures
      // the tab from the screen.
      final request = widget.onNativeTabDragRequested?.call(
        data,
        globalPosition,
        geometry,
      );
      if (leaving.isNotEmpty) {
        setState(() => _leavingTabIds.addAll(leaving));
      }
      await request;
    } finally {
      _endDrag();
      if (leaving.isNotEmpty) {
        // Moved tabs are closed by then; a failed tear-off fades back in.
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          setState(() => _leavingTabIds.removeAll(leaving));
        });
      }
    }
  }

  Widget _buildReorderTarget({
    required int targetIndex,
    required Widget child,
  }) {
    if (widget.onTabReorder == null) return child;
    return DragTarget<DesktopTabDragData>(
      onWillAcceptWithDetails: (details) {
        final from = _indexOfDragData(details.data);
        return from >= 0 && from != targetIndex;
      },
      onMove: (details) {
        _notifyReorder(details.data, targetIndex);
      },
      onAcceptWithDetails: (details) {
        _notifyReorder(details.data, targetIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering =
            candidateData.isNotEmpty ||
            (_activeDragTabId != null && _previewTargetIndex == targetIndex);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: isHovering ? 1 : 0,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.0),
                      color: widget.theme.colorScheme.primary.withValues(
                        alpha: 0.10,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: -2,
              top: 7,
              bottom: 7,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                scale: isHovering ? 1 : 0.7,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOutCubic,
                  opacity: isHovering ? 1 : 0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: isHovering ? 4 : 2,
                    decoration: BoxDecoration(
                      color: widget.theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTabControllerChange);
    widget.externalTabDrop?.attach(_externalInsertIndexAt);
    widget.externalTabDrop?.hover.addListener(_onExternalHoverChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _animateEntries = true;
    });
  }

  @override
  void didUpdateWidget(_ModernTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onTabControllerChange);
      widget.controller.addListener(_onTabControllerChange);
    }
    if (widget.externalTabDrop != oldWidget.externalTabDrop) {
      oldWidget.externalTabDrop?.hover.removeListener(_onExternalHoverChanged);
      oldWidget.externalTabDrop?.detach(_externalInsertIndexAt);
      widget.externalTabDrop?.attach(_externalInsertIndexAt);
      widget.externalTabDrop?.hover.addListener(_onExternalHoverChanged);
      _externalGap = null;
    }
    if (_activeDragTabId != null && _activeDragIndex() < 0) {
      _endDrag(rebuild: false);
    }
    if (_followPointer) {
      // A reorder moved the dragged tab's slot; keep it under the pointer.
      final index = _activeDragIndex();
      if (index >= 0) _dragDx.value = _dragTabLeft - index * _tabSlotWidth;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabControllerChange);
    widget.externalTabDrop?.hover.removeListener(_onExternalHoverChanged);
    widget.externalTabDrop?.detach(_externalInsertIndexAt);
    _endDrag(rebuild: false);
    _dragDx.dispose();
    super.dispose();
  }

  void _onTabControllerChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return Padding(
      padding: Platform.isMacOS
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(0, 4, 4, 0),
      child: Listener(
        key: _tabStripKey,
        onPointerDown: (e) {
          if (!_hasCustomTitleBar) return;
          if (e.kind != PointerDeviceKind.mouse) return;
          if (e.buttons != kPrimaryMouseButton) return;
          if (!_isBlankStripPosition(e.position)) return;

          _blankPointerDownGlobal = e.position;
          _blankDragEligible = true;
          _blankDragStarted = false;
        },
        onPointerMove: (e) {
          if (!_hasCustomTitleBar) return;
          if (!_blankDragEligible) return;
          if (_blankPointerDownGlobal == null) return;
          if ((e.buttons & kPrimaryMouseButton) == 0) {
            _resetBlankDrag();
            return;
          }

          final delta = (e.position - _blankPointerDownGlobal!).distance;
          if (delta < _blankDragThreshold) return;
          _blankDragStarted = true;
          // Dragging should not count as a "tap" for double-click.
          _lastBlankTapAt = null;
          _lastBlankTapGlobal = null;
          _resetBlankDrag();
          unawaited(windowManager.startDragging());
        },
        onPointerUp: (e) {
          if (!_hasCustomTitleBar) {
            _resetBlankDrag();
            return;
          }

          if (_blankDragEligible &&
              !_blankDragStarted &&
              _blankPointerDownGlobal != null &&
              _isBlankStripPosition(e.position)) {
            final now = DateTime.now();
            final lastAt = _lastBlankTapAt;
            final lastPos = _lastBlankTapGlobal;

            if (lastAt != null &&
                now.difference(lastAt) <= _doubleClickTimeout &&
                lastPos != null &&
                (e.position - lastPos).distance <= _doubleClickSlop) {
              _lastBlankTapAt = null;
              _lastBlankTapGlobal = null;
              _resetBlankDrag();
              unawaited(_toggleMaximizeRestore());
              return;
            }

            _lastBlankTapAt = now;
            _lastBlankTapGlobal = e.position;
          }

          _resetBlankDrag();
        },
        onPointerCancel: (_) => _resetBlankDrag(),
        behavior: HitTestBehavior.translucent,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: widget.viewportWidth),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildTabRow(context, isDesktop),
          ),
        ),
      ),
    );
  }

  Widget _buildTabRow(BuildContext context, bool isDesktop) {
    final slot = _tabSlotWidth;
    final gap = _externalGap;
    final shouldUseNativeDrag =
        Platform.isWindows && widget.onNativeTabDragRequested != null;
    final children = <Widget>[];
    int? draggedVisualIndex;
    _draggedTabCopy = null;
    final activeIndex = widget.activeTabIndex ?? widget.controller.index;
    final animateEntry =
        _animateEntries && _lastBuiltTabCount > 0 && !_gapOpenLastBuild;
    _lastBuiltTabCount = widget.tabs.length;
    _gapOpenLastBuild = gap != null;

    for (int index = 0; index < widget.tabs.length; index++) {
      if (gap == index) children.add(_buildExternalGhost(gap!));
      final visualIndex = gap != null && index >= gap ? index + 1 : index;
      final isActive = activeIndex == index;
      final showRightDivider = isDesktop && index < widget.tabs.length - 1;

      final dragData =
          (widget.draggableTabs != null &&
              index < (widget.draggableTabs?.length ?? 0))
          ? widget.draggableTabs![index]
          : null;

      final isSelected =
          dragData != null && widget.selectedTabIds.contains(dragData.tabId);

      _ModernTab buildTab({bool hovered = false}) => _ModernTab(
        isActive: isActive,
        isSelected: isSelected,
        forceHovered: hovered,
        showRightDivider: showRightDivider,
        onPrimaryPressed: () {
          final keys = HardwareKeyboard.instance.logicalKeysPressed;
          final shiftPressed =
              HardwareKeyboard.instance.isShiftPressed ||
              keys.contains(LogicalKeyboardKey.shiftLeft) ||
              keys.contains(LogicalKeyboardKey.shiftRight);
          final handler = widget.onTabPrimaryClick;
          if (handler != null) {
            handler(index, shiftPressed);
            return;
          }
          widget.onTap?.call(index);
        },
        onSecondaryClick: widget.onTabContextMenu == null
            ? null
            : (pos) => widget.onTabContextMenu!.call(index, pos),
        activeTabColor: widget.activeTabColor,
        hoverColor: widget.hoverColor,
        tabBackgroundColor: widget.tabBackgroundColor,
        labelColor: isActive ? widget.labelColor : widget.unselectedLabelColor,
        labelStyle: isActive ? widget.labelStyle : widget.unselectedLabelStyle,
        onClose: () => widget.onTabClose?.call(index),
        theme: widget.theme,
        child: widget.tabs[index],
      );

      final tabWidget = buildTab();
      final tabKey = ValueKey<String>(
        dragData != null
            ? 'desktop_tab_${dragData.tabId}'
            : 'desktop_tab_index_$index',
      );

      final Widget content;
      if (dragData == null) {
        content = tabWidget;
      } else if (shouldUseNativeDrag) {
        content = _NativeTabDragHandle(
          data: dragData,
          onDragStarted: (data, grabOffset) =>
              _beginDrag(data, grabOffset: grabOffset),
          onDragMove: _handleNativeReorderMove,
          onDragFinished: (_) => _endDrag(),
          onDetachRequested: _handleNativeDetachRequest,
          canDetachAt: _isOutsideDetachBand,
          child: tabWidget,
        );
      } else {
        content = _buildReorderTarget(
          targetIndex: index,
          child: Draggable<DesktopTabDragData>(
            data: dragData,
            allowedButtonsFilter: (buttons) => buttons == kPrimaryMouseButton,
            onDragStarted: () => _beginDrag(dragData),
            onDragUpdate: (details) => _handleDragUpdate(dragData, details),
            onDragEnd: (_) => _endDrag(),
            childWhenDragging: Opacity(opacity: 0.35, child: tabWidget),
            feedback: Material(
              color: Colors.transparent,
              child: Opacity(
                opacity: 0.95,
                child: Transform.scale(
                  scale: 1.02,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints.tightFor(
                      width: 210,
                      height: 38,
                    ),
                    child: DecoratedBox(
                      // A dragged tab floats: shadow, no outline.
                      decoration: CbDecorations.floating(
                        context,
                        radius: 16.0,
                        color: widget.activeTabColor,
                      ),
                      child: Center(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(
                            color: widget.labelColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          child: widget.tabs[index],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            child: tabWidget,
          ),
        );
      }

      final tabId = dragData?.tabId;
      final followsPointer =
          _followPointer && tabId != null && tabId == _activeDragTabId;
      final leaving = tabId != null && _leavingTabIds.contains(tabId);
      if (followsPointer) {
        draggedVisualIndex = visualIndex;
        // Looks exactly like the pressed tab it stands in for, which is
        // under the pointer and so hovered.
        _draggedTabCopy = _fadeWhenLeaving(leaving, buildTab(hovered: true));
      }

      children.add(
        _TabSlotMotion(
          key: tabKey,
          visualIndex: visualIndex,
          slotWidth: slot,
          dragOffset: followsPointer ? _dragDx : null,
          animateEntry: animateEntry,
          // The copy above the row stands in while the tab follows the pointer.
          child: Opacity(
            opacity: followsPointer ? 0 : 1,
            child: _fadeWhenLeaving(leaving, content),
          ),
        ),
      );
    }
    if (gap != null && gap >= widget.tabs.length) {
      children.add(_buildExternalGhost(widget.tabs.length));
    }

    if (widget.onAddTabPressed != null) {
      children.add(
        _TabSlotMotion(
          key: const ValueKey<String>('desktop_tab_add_button'),
          visualIndex: widget.tabs.length + (gap != null ? 1 : 0),
          slotWidth: slot,
          animateEntry: false,
          child: KeyedSubtree(
            key: _addTabButtonKey,
            child: Material(
              color: Colors.transparent,
              child: CbTooltip(
                message: context.tr.addNewTab,
                child: Container(
                  margin: const EdgeInsets.only(left: 4, right: 4),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: _CaptionStyleAddTabButton(
                      theme: widget.theme,
                      onPressed: widget.onAddTabPressed,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final copy = _draggedTabCopy;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          key: _tabRowKey,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
        if (copy != null && draggedVisualIndex != null)
          Positioned(
            left: draggedVisualIndex * slot,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ValueListenableBuilder<double>(
                valueListenable: _dragDx,
                builder: (context, dx, child) =>
                    Transform.translate(offset: Offset(dx, 0), child: child),
                child: copy,
              ),
            ),
          ),
      ],
    );
  }

  Widget _fadeWhenLeaving(bool leaving, Widget child) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      opacity: leaving ? 0 : 1,
      child: child,
    );
  }

  Widget _buildExternalGhost(int visualIndex) {
    return _TabSlotMotion(
      key: const ValueKey<String>('desktop_tab_external_drop'),
      visualIndex: visualIndex,
      slotWidth: _tabSlotWidth,
      animateEntry: true,
      child: IgnorePointer(
        child: _ExternalTabGhost(label: _externalLabel, theme: widget.theme),
      ),
    );
  }
}

/// Animates a tab between slots: when its slot changes (reorder, close, a gap
/// opening for an incoming tab) it slides from where it was drawn, and a new
/// tab scales and fades in. While [dragOffset] is set it follows that offset
/// instead, and settles into its slot once released.
///
/// Only a transform changes during the animation, so neighbours never relayout.
class _TabSlotMotion extends StatefulWidget {
  final int visualIndex;
  final double slotWidth;
  final ValueListenable<double>? dragOffset;
  final bool animateEntry;
  final Widget child;

  const _TabSlotMotion({
    super.key,
    required this.visualIndex,
    required this.slotWidth,
    this.dragOffset,
    required this.animateEntry,
    required this.child,
  });

  @override
  State<_TabSlotMotion> createState() => _TabSlotMotionState();
}

class _TabSlotMotionState extends State<_TabSlotMotion>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 180);
  static const Curve _curve = Curves.easeOutCubic;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: 1,
  );
  double _startDx = 0;
  bool _entering = false;

  double get _settlingDx =>
      _startDx * (1 - _curve.transform(_controller.value));

  @override
  void initState() {
    super.initState();
    if (widget.animateEntry) {
      _entering = true;
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(_TabSlotMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.dragOffset != null) return;
    final slotShift =
        (oldWidget.visualIndex - widget.visualIndex) * widget.slotWidth;
    final released = oldWidget.dragOffset;
    final double from;
    if (released != null) {
      from = released.value + slotShift;
    } else if (slotShift != 0) {
      from = _settlingDx + slotShift;
    } else {
      return;
    }
    _entering = false;
    _startDx = from;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drag = widget.dragOffset;
    return AnimatedBuilder(
      animation: drag == null
          ? _controller
          : Listenable.merge([_controller, drag]),
      builder: (context, child) {
        final t = _curve.transform(_controller.value);
        final dx = drag?.value ?? _startDx * (1 - t);
        final scale = _entering ? 0.92 + 0.08 * t : 1.0;
        // Fixed structure: swapping wrappers would remount the tab.
        return Opacity(
          opacity: _entering ? t : 1,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(dx, 0, 0)
              ..scaleByDouble(scale, scale, 1, 1),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Placeholder tab where tabs dragged in from another window will land.
class _ExternalTabGhost extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _ExternalTabGhost({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final isMacOS = FluentSurfaceTokens.isMacOS;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: FluentSurfaceTokens.tabWidth,
      height: 40,
      margin: isMacOS
          ? const EdgeInsets.symmetric(horizontal: 3, vertical: 6)
          : const EdgeInsets.only(left: 2, right: 2, top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: isMacOS
            ? BorderRadius.circular(10)
            : const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsLight.arrowSquareIn, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptionStyleAddTabButton extends StatefulWidget {
  final ThemeData theme;
  final VoidCallback? onPressed;

  const _CaptionStyleAddTabButton({
    required this.theme,
    required this.onPressed,
  });

  @override
  State<_CaptionStyleAddTabButton> createState() =>
      _CaptionStyleAddTabButtonState();
}

class _CaptionStyleAddTabButtonState extends State<_CaptionStyleAddTabButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final accentColor = widget.theme.colorScheme.primary;
    final idleBg = isDark
        ? accentColor.withValues(alpha: 0.06)
        : accentColor.withValues(alpha: 0.07);
    final hoverBg = isDark
        ? accentColor.withValues(alpha: 0.16)
        : accentColor.withValues(alpha: 0.14);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: CbPressable(
        cursor: SystemMouseCursors.click,
        canRequestFocus: false,
        onPressed: () {
          widget.onPressed?.call();
          HapticFeedback.lightImpact();
        },
        builder: (context, state) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _isHovered ? hoverBg : idleBg,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Icon(PhosphorIconsLight.plus, size: 18, color: accentColor),
        ),
      ),
    );
  }
}

/// Individual modern tab with softer, more elegant styling
class _ModernTab extends StatefulWidget {
  final bool isActive;
  final bool isSelected;
  // Draw as hovered regardless of the pointer (the dragged tab's copy).
  final bool forceHovered;
  final bool showRightDivider;
  final VoidCallback onPrimaryPressed;
  final ValueChanged<Offset>? onSecondaryClick;
  final Color activeTabColor;
  final Color hoverColor;
  final Color tabBackgroundColor;
  final Color? labelColor;
  final TextStyle? labelStyle;
  final Widget child;
  final VoidCallback? onClose;
  final ThemeData theme;

  const _ModernTab({
    required this.isActive,
    required this.isSelected,
    this.forceHovered = false,
    required this.showRightDivider,
    required this.onPrimaryPressed,
    this.onSecondaryClick,
    required this.activeTabColor,
    required this.hoverColor,
    required this.tabBackgroundColor,
    this.labelColor,
    this.labelStyle,
    required this.child,
    this.onClose,
    required this.theme,
  });

  @override
  State<_ModernTab> createState() => _ModernTabState();
}

class _ModernTabState extends State<_ModernTab>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  bool _isCloseButtonHovered = false;
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);

    if (widget.isActive) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(_ModernTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabWidth = FluentSurfaceTokens.tabWidth;
    final isMacOS = FluentSurfaceTokens.isMacOS;
    const tabHeight = 40.0;
    final isDarkMode = widget.theme.brightness == Brightness.dark;
    final cs = widget.theme.colorScheme;
    final primaryColor = cs.primary;
    final hoverColor = isDarkMode
        ? cs.surfaceContainerHighest.withValues(alpha: 0.75)
        : cs.surfaceContainerHighest.withValues(alpha: 0.95);
    final selectedFillColor = primaryColor.withValues(
      alpha: isDarkMode ? 0.22 : 0.12,
    );
    final activeFillColor = isMacOS
        ? cs.onSurface.withValues(alpha: isDarkMode ? 0.10 : 0.07)
        : widget.activeTabColor;
    const inactiveFillColor = Colors.transparent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final effectiveLabelColor = widget.isSelected
              ? cs.onSurface
              : (widget.isActive
                    ? cs.onSurface
                    : cs.onSurfaceVariant.withValues(
                        alpha: isDarkMode ? 0.94 : 1.0,
                      ));

          return _OptimizedTabInteraction(
            onPrimaryPressed: widget.onPrimaryPressed,
            onMiddleClick: widget.onClose,
            onSecondaryClick: widget.onSecondaryClick,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  width: tabWidth,
                  height: tabHeight,
                  margin: isMacOS
                      ? const EdgeInsets.symmetric(horizontal: 3, vertical: 6)
                      : const EdgeInsets.only(left: 2, right: 2, top: 6),
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? selectedFillColor
                        : (widget.isActive
                              ? activeFillColor
                              : ((_isHovered || widget.forceHovered) &&
                                        !_isCloseButtonHovered
                                    ? hoverColor
                                    : inactiveFillColor)),
                    borderRadius: isMacOS
                        ? BorderRadius.circular(10)
                        : const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                          ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: IconTheme(
                            data: IconThemeData(
                              color: effectiveLabelColor,
                              size: 16,
                            ),
                            child: DefaultTextStyle(
                              style: TextStyle(
                                color: effectiveLabelColor,
                                fontSize: 13,
                                fontWeight: widget.isActive
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ).merge(widget.labelStyle),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        right: 24.0,
                                      ),
                                      child: Center(child: widget.child),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.isActive && !isMacOS)
                        Positioned(
                          left: 8,
                          right: 8,
                          top: 0,
                          height: 2,
                          child: ColoredBox(
                            color: cs.primary.withValues(
                              alpha: isDarkMode ? 0.75 : 0.65,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Close button - positioned on top of tab
                if (widget.onClose != null)
                  Positioned(
                    top: 6 + (tabHeight - 22) / 2,
                    right: 12, // Position from right edge
                    child: AnimatedOpacity(
                      opacity:
                          (_isHovered || widget.forceHovered || widget.isActive)
                          ? 1.0
                          : 0.5,
                      duration: const Duration(milliseconds: 150),
                      child: Material(
                        color: Colors.transparent,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) =>
                              setState(() => _isCloseButtonHovered = true),
                          onExit: (_) =>
                              setState(() => _isCloseButtonHovered = false),
                          child: CbPressable(
                            cursor: SystemMouseCursors.click,
                            semanticLabel: context.tr.closeTab,
                            onPressed: () {
                              widget.onClose?.call();
                              HapticFeedback.lightImpact();
                            },
                            builder: (context, state) => Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _isCloseButtonHovered
                                    ? (isDarkMode
                                          ? Colors.white.withAlpha(
                                              (0.15 * 255).round(),
                                            )
                                          : Colors.black.withAlpha(
                                              (0.08 * 255).round(),
                                            ))
                                    : Colors.transparent,
                                borderRadius: CbRadii.smAll,
                              ),
                              child: Icon(
                                PhosphorIconsLight.x,
                                size: 16,
                                color: widget.isActive
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Gesture-owned primary clicks keep nested close buttons independent.
class _OptimizedTabInteraction extends StatefulWidget {
  final VoidCallback onPrimaryPressed;
  final VoidCallback? onMiddleClick;
  final ValueChanged<Offset>? onSecondaryClick;
  final Widget child;

  const _OptimizedTabInteraction({
    required this.onPrimaryPressed,
    this.onMiddleClick,
    this.onSecondaryClick,
    required this.child,
  });

  @override
  _OptimizedTabInteractionState createState() =>
      _OptimizedTabInteractionState();
}

class _OptimizedTabInteractionState extends State<_OptimizedTabInteraction> {
  @override
  Widget build(BuildContext context) {
    // A tap recognizer must compete with the enclosing Draggable. A raw
    // Listener alone lets the drag win on pointer-down without any movement.
    return GestureDetector(
      onTap: () {
        widget.onPrimaryPressed();
        HapticFeedback.lightImpact();
      },
      child: Listener(
        onPointerDown: (PointerDownEvent event) {
          // Auxiliary mouse buttons are not handled by the tap recognizer.
          if (event.buttons == kMiddleMouseButton &&
              widget.onMiddleClick != null) {
            widget.onMiddleClick!();
            HapticFeedback.lightImpact();
          }
          // Secondary mouse button (right click)
          else if (event.buttons == kSecondaryMouseButton &&
              widget.onSecondaryClick != null) {
            widget.onSecondaryClick!(event.position);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: widget.child,
      ),
    );
  }
}

// New widget for window caption buttons

class _NativeTabDragHandle extends StatefulWidget {
  final DesktopTabDragData data;
  final void Function(DesktopTabDragData data, Offset grabOffset)?
  onDragStarted;
  final void Function(DesktopTabDragData data, Offset globalPosition)?
  onDragMove;
  final ValueChanged<DesktopTabDragData>? onDragFinished;
  final Future<void> Function(
    DesktopTabDragData data,
    Offset globalPosition,
    Offset grabOffset,
  )
  onDetachRequested;
  final bool Function(Offset globalPosition) canDetachAt;
  final Widget child;

  const _NativeTabDragHandle({
    required this.data,
    this.onDragStarted,
    this.onDragMove,
    this.onDragFinished,
    required this.onDetachRequested,
    required this.canDetachAt,
    required this.child,
  });

  @override
  State<_NativeTabDragHandle> createState() => _NativeTabDragHandleState();
}

class _NativeTabDragHandleState extends State<_NativeTabDragHandle> {
  Offset? _downPosition;
  // Pointer position inside the tab at press time.
  Offset _grabOffset = Offset.zero;
  bool _dragging = false;
  bool _detaching = false;

  static const double _startDistance = 6.0;
  static const double _detachDistance = 28.0;

  void _reset() {
    _downPosition = null;
    _dragging = false;
    _detaching = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kPrimaryMouseButton) {
          _downPosition = e.position;
          _grabOffset = e.localPosition;
        }
      },
      onPointerMove: (e) {
        if (_downPosition == null) return;
        if ((e.buttons & kPrimaryMouseButton) == 0) return;

        final delta = e.position - _downPosition!;
        if (!_dragging && delta.distance >= _startDistance) {
          _dragging = true;
          widget.onDragStarted?.call(widget.data, _grabOffset);
        }

        if (!_dragging || _detaching) return;

        if (delta.dy.abs() >= _detachDistance &&
            widget.canDetachAt(e.position)) {
          _detaching = true;
          unawaited(
            widget
                .onDetachRequested(widget.data, e.position, _grabOffset)
                .whenComplete(_reset),
          );
          return;
        }

        widget.onDragMove?.call(widget.data, e.position);
      },
      onPointerUp: (_) {
        if (_dragging && !_detaching) {
          widget.onDragFinished?.call(widget.data);
        }
        _reset();
      },
      onPointerCancel: (_) {
        if (_dragging && !_detaching) {
          widget.onDragFinished?.call(widget.data);
        }
        _reset();
      },
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}
