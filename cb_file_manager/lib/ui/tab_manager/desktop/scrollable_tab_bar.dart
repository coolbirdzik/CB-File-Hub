import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/services.dart'; // Added import for HapticFeedback
import 'package:phosphor_flutter/phosphor_flutter.dart';
// Import app theme
import 'package:window_manager/window_manager.dart'; // Import window_manager
import 'dart:io'; // Import dart:io for Platform check
import '../../components/common/window_caption_buttons.dart';
import 'desktop_tab_drag_data.dart';

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
  final Future<void> Function(DesktopTabDragData data)?
      onNativeTabDragRequested;
  final void Function(int fromIndex, int toIndex)? onTabReorder;
  final void Function(int index, bool shiftPressed)? onTabPrimaryClick;

  const ScrollableTabBar({
    Key? key,
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
  }) : super(key: key);

  @override
  State<ScrollableTabBar> createState() => _ScrollableTabBarState();
}

class _ScrollableTabBarState extends State<ScrollableTabBar> {
  // Create a scroll controller for the horizontal scroll view
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

    Widget windowCaptionButtons = Platform.isWindows
        ? WindowCaptionButtons(theme: theme)
        : const SizedBox.shrink();

    // Main container for the entire bar
    return Container(
      height: Platform.isWindows
          ? 50
          : null, // Provide a specific height for the custom title bar on Windows
      decoration: BoxDecoration(
        color: tabBackgroundColor,
        boxShadow: [],
      ),
      margin: Platform.isWindows
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (Platform.isWindows)
            DragToMoveArea(
              child: const SizedBox(
                width: 12,
                height: double.infinity,
              ),
            ),
          // Tab strip area (not draggable) so tab drag gestures can win.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Listener(
                  onPointerSignal: (PointerSignalEvent event) {
                    if (event is PointerScrollEvent) {
                      final keys = HardwareKeyboard.instance.logicalKeysPressed;
                      final isShiftPressed =
                          HardwareKeyboard.instance.isShiftPressed ||
                              keys.contains(LogicalKeyboardKey.shiftLeft) ||
                              keys.contains(LogicalKeyboardKey.shiftRight);

                      // Only scroll the tab strip when a horizontal scroll is
                      // requested (trackpad swipe) or when the user holds Shift.
                      // Do not map vertical wheel scrolling to horizontal by
                      // default so vertical scroll can pass through naturally.
                      final delta = event.scrollDelta.dx.abs() > 0
                          ? event.scrollDelta.dx
                          : (isShiftPressed ? event.scrollDelta.dy : 0.0);

                      // Always consume the wheel event over the tab strip so
                      // the content underneath does not scroll vertically.
                      GestureBinding.instance.pointerSignalResolver
                          .register(event, (_) {});

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
                        theme: theme,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (Platform.isWindows)
            DragToMoveArea(
              child: const SizedBox(
                width: 84,
                height: double.infinity,
              ),
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
  final Future<void> Function(DesktopTabDragData data)?
      onNativeTabDragRequested;
  final void Function(int fromIndex, int toIndex)? onTabReorder;
  final void Function(int index, bool shiftPressed)? onTabPrimaryClick;
  final ThemeData theme;

  const _ModernTabBar({
    Key? key,
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
    required this.theme,
  }) : super(key: key);

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

  static const double _blankDragThreshold = 5.0;
  static const Duration _doubleClickTimeout = Duration(milliseconds: 350);
  static const double _doubleClickSlop = 22.0;

  Future<void> _toggleMaximizeRestore() async {
    if (!Platform.isWindows) return;
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
    if (!Platform.isWindows) return false;

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
    final isOverTabRow = rowLocal.dx >= 0 &&
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

  bool _isDraggedTabAt(int index) {
    final activeTabId = _activeDragTabId;
    final items = widget.draggableTabs;
    if (activeTabId == null || items == null || index >= items.length) {
      return false;
    }
    return items[index].tabId == activeTabId;
  }

  double _slideOffsetForIndex(int index) {
    final fromIndex = _activeDragIndex();
    final toIndex = _previewTargetIndex;
    if (fromIndex < 0 || toIndex == null) return 0;
    if (index == fromIndex) return 0;

    if (fromIndex < toIndex && index > fromIndex && index <= toIndex) {
      return -0.10;
    }
    if (fromIndex > toIndex && index >= toIndex && index < fromIndex) {
      return 0.10;
    }
    return 0;
  }

  Widget _wrapTabReorderEffect({
    required int index,
    required Widget child,
  }) {
    final slideX = _slideOffsetForIndex(index);
    final isAnyDragActive = _activeDragTabId != null;
    final isDraggedTab = _isDraggedTabAt(index);
    final shouldDimDraggedTab = Platform.isWindows &&
        widget.onNativeTabDragRequested != null &&
        isAnyDragActive &&
        isDraggedTab;
    final scale =
        isDraggedTab ? 0.97 : (isAnyDragActive && slideX != 0 ? 1.01 : 1.0);

    return AnimatedSlide(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      offset: Offset(slideX, 0),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        scale: scale,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: shouldDimDraggedTab ? 0.62 : 1,
          child: child,
        ),
      ),
    );
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
    const tabSlotWidth = 216.0;
    final raw = (local.dx / tabSlotWidth).floor();
    return raw.clamp(0, widget.tabs.length - 1);
  }

  void _beginDrag(DesktopTabDragData data) {
    _activeDragTabId = data.tabId;
    _previewTargetIndex = _indexOfDragData(data);
    _lastReorderFromIndex = null;
    _lastReorderToIndex = null;
    widget.onTabDragStarted?.call(data);
    if (mounted) {
      setState(() {});
    }
  }

  void _endDrag() {
    _activeDragTabId = null;
    _previewTargetIndex = null;
    _lastReorderFromIndex = null;
    _lastReorderToIndex = null;
    widget.onTabDragEnded?.call();
    if (mounted) {
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

  void _handleNativeReorderMove(
    DesktopTabDragData data,
    Offset globalPosition,
  ) {
    final toIndex = _resolveTargetIndex(globalPosition);
    if (toIndex < 0) return;
    _notifyReorder(data, toIndex);
  }

  void _handleDragUpdate(
    DesktopTabDragData data,
    DragUpdateDetails details,
  ) {
    _handleNativeReorderMove(data, details.globalPosition);
  }

  Future<void> _handleNativeDetachRequest(DesktopTabDragData data) async {
    try {
      await widget.onNativeTabDragRequested?.call(data);
    } finally {
      _endDrag();
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
        final isHovering = candidateData.isNotEmpty ||
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
                    margin:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16.0),
                      color: widget.theme.colorScheme.primary
                          .withValues(alpha: 0.10),
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
                      boxShadow: [],
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
  }

  @override
  void didUpdateWidget(_ModernTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_onTabControllerChange);
      widget.controller.addListener(_onTabControllerChange);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTabControllerChange);
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
      padding: const EdgeInsets.fromLTRB(0, 4, 4, 0),
      child: Listener(
        key: _tabStripKey,
        onPointerDown: (e) {
          if (!Platform.isWindows) return;
          if (e.kind != PointerDeviceKind.mouse) return;
          if (e.buttons != kPrimaryMouseButton) return;
          if (!_isBlankStripPosition(e.position)) return;

          _blankPointerDownGlobal = e.position;
          _blankDragEligible = true;
          _blankDragStarted = false;
        },
        onPointerMove: (e) {
          if (!Platform.isWindows) return;
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
          if (!Platform.isWindows) {
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
            child: Row(
              key: _tabRowKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(widget.tabs.length, (index) {
                  final isActive = widget.controller.index == index;
                  final showRightDivider =
                      isDesktop && index < widget.tabs.length - 1;

                  final dragData = (widget.draggableTabs != null &&
                          index < (widget.draggableTabs?.length ?? 0))
                      ? widget.draggableTabs![index]
                      : null;

                  final isSelected = dragData != null &&
                      widget.selectedTabIds.contains(dragData.tabId);

                  final tabWidget = _ModernTab(
                    isActive: isActive,
                    isSelected: isSelected,
                    showRightDivider: showRightDivider,
                    onPrimaryDown: (event) {
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
                    labelColor: isActive
                        ? widget.labelColor
                        : widget.unselectedLabelColor,
                    labelStyle: isActive
                        ? widget.labelStyle
                        : widget.unselectedLabelStyle,
                    onClose: () => widget.onTabClose?.call(index),
                    theme: widget.theme,
                    child: widget.tabs[index],
                  );
                  final tabKey = ValueKey<String>(
                    dragData != null
                        ? 'desktop_tab_${dragData.tabId}'
                        : 'desktop_tab_index_$index',
                  );

                  if (dragData == null) {
                    return _wrapTabReorderEffect(
                      index: index,
                      child: KeyedSubtree(key: tabKey, child: tabWidget),
                    );
                  }

                  final shouldUseNativeDrag = Platform.isWindows &&
                      widget.onNativeTabDragRequested != null;
                  if (shouldUseNativeDrag) {
                    return _wrapTabReorderEffect(
                      index: index,
                      child: KeyedSubtree(
                        key: tabKey,
                        child: _buildReorderTarget(
                          targetIndex: index,
                          child: _NativeTabDragHandle(
                            data: dragData,
                            onDragStarted: _beginDrag,
                            onDragMove: _handleNativeReorderMove,
                            onDragFinished: (_) => _endDrag(),
                            onDetachRequested: _handleNativeDetachRequest,
                            child: tabWidget,
                          ),
                        ),
                      ),
                    );
                  }

                  return _wrapTabReorderEffect(
                    index: index,
                    child: KeyedSubtree(
                      key: tabKey,
                      child: _buildReorderTarget(
                        targetIndex: index,
                        child: Draggable<DesktopTabDragData>(
                          data: dragData,
                          onDragStarted: () => _beginDrag(dragData),
                          onDragUpdate: (details) =>
                              _handleDragUpdate(dragData, details),
                          onDragEnd: (_) => _endDrag(),
                          childWhenDragging:
                              Opacity(opacity: 0.35, child: tabWidget),
                          feedback: Material(
                            color: Colors.transparent,
                            child: Opacity(
                              opacity: 0.95,
                              child: Transform.scale(
                                scale: 1.02,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints.tightFor(
                                      width: 210, height: 38),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: widget.activeTabColor,
                                      borderRadius: BorderRadius.circular(16.0),
                                      border: Border.all(
                                        color: widget.theme.colorScheme.primary
                                            .withValues(alpha: 0.35),
                                        width: 0.8,
                                      ),
                                      boxShadow: [],
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
                      ),
                    ),
                  );
                }),
                if (widget.onAddTabPressed != null)
                  KeyedSubtree(
                    key: _addTabButtonKey,
                    child: Material(
                      color: Colors.transparent,
                      child: Tooltip(
                        message: 'Add new tab',
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
              ],
            ),
          ),
        ),
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
      child: _OptimizedButtonInteraction(
        onTap: () {
          widget.onPressed?.call();
          HapticFeedback.lightImpact();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _isHovered ? hoverBg : idleBg,
            borderRadius: BorderRadius.circular(16.0),
          ),
          child: Icon(
            PhosphorIconsLight.plus,
            size: 18,
            color: accentColor,
          ),
        ),
      ),
    );
  }
}

/// Individual modern tab with softer, more elegant styling
class _ModernTab extends StatefulWidget {
  final bool isActive;
  final bool isSelected;
  final bool showRightDivider;
  final ValueChanged<PointerDownEvent> onPrimaryDown;
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
    Key? key,
    required this.isActive,
    required this.isSelected,
    required this.showRightDivider,
    required this.onPrimaryDown,
    this.onSecondaryClick,
    required this.activeTabColor,
    required this.hoverColor,
    required this.tabBackgroundColor,
    this.labelColor,
    this.labelStyle,
    required this.child,
    this.onClose,
    required this.theme,
  }) : super(key: key);

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
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

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
    const tabWidth = 210.0;
    const tabHeight = 40.0;
    final isDarkMode = widget.theme.brightness == Brightness.dark;
    final cs = widget.theme.colorScheme;
    final primaryColor = cs.primary;
    final hoverColor = isDarkMode
        ? cs.surfaceContainerHighest.withValues(alpha: 0.75)
        : cs.surfaceContainerHighest.withValues(alpha: 0.95);
    final selectedFillColor =
        primaryColor.withValues(alpha: isDarkMode ? 0.22 : 0.12);
    final activeFillColor = widget.activeTabColor;
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
                  : cs.onSurfaceVariant
                      .withValues(alpha: isDarkMode ? 0.94 : 1.0));

          return _OptimizedTabInteraction(
            onPrimaryDown: widget.onPrimaryDown,
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
                  margin: const EdgeInsets.only(left: 2, right: 2, top: 6),
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? selectedFillColor
                        : (widget.isActive
                            ? activeFillColor
                            : (_isHovered && !_isCloseButtonHovered
                                ? hoverColor
                                : inactiveFillColor)),
                    borderRadius: const BorderRadius.only(
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
                                      padding:
                                          const EdgeInsets.only(right: 24.0),
                                      child: Center(child: widget.child),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.isActive)
                        Positioned(
                          left: 8,
                          right: 8,
                          top: 0,
                          height: 2,
                          child: ColoredBox(
                            color: cs.primary
                                .withValues(alpha: isDarkMode ? 0.75 : 0.65),
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
                      opacity: (_isHovered || widget.isActive) ? 1.0 : 0.5,
                      duration: const Duration(milliseconds: 150),
                      child: Material(
                        color: Colors.transparent,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) =>
                              setState(() => _isCloseButtonHovered = true),
                          onExit: (_) =>
                              setState(() => _isCloseButtonHovered = false),
                          child: _OptimizedButtonInteraction(
                            onTap: () {
                              widget.onClose?.call();
                              HapticFeedback.lightImpact();
                            },
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: _isCloseButtonHovered
                                    ? (isDarkMode
                                        ? Colors.white
                                            .withAlpha((0.15 * 255).round())
                                        : Colors.black
                                            .withAlpha((0.08 * 255).round()))
                                    : Colors.transparent,
                                shape: BoxShape.circle,
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

/// Optimized tab interaction handler that eliminates delay on tab clicks
class _OptimizedTabInteraction extends StatefulWidget {
  final ValueChanged<PointerDownEvent> onPrimaryDown;
  final VoidCallback? onMiddleClick;
  final ValueChanged<Offset>? onSecondaryClick;
  final Widget child;

  const _OptimizedTabInteraction({
    Key? key,
    required this.onPrimaryDown,
    this.onMiddleClick,
    this.onSecondaryClick,
    required this.child,
  }) : super(key: key);

  @override
  _OptimizedTabInteractionState createState() =>
      _OptimizedTabInteractionState();
}

class _OptimizedTabInteractionState extends State<_OptimizedTabInteraction> {
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        // Primary mouse button (left click)
        if (event.buttons == kPrimaryMouseButton) {
          widget.onPrimaryDown(event);
          HapticFeedback.lightImpact();
        }
        // Middle mouse button (wheel click)
        else if (event.buttons == kMiddleMouseButton &&
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
    );
  }
}

/// Optimized button interaction handler for the close and add tab buttons
class _OptimizedButtonInteraction extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _OptimizedButtonInteraction({
    Key? key,
    required this.onTap,
    required this.child,
  }) : super(key: key);

  @override
  _OptimizedButtonInteractionState createState() =>
      _OptimizedButtonInteractionState();
}

class _OptimizedButtonInteractionState
    extends State<_OptimizedButtonInteraction> {
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        if (event.buttons == kPrimaryMouseButton) {
          widget.onTap();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

// New widget for window caption buttons

class _NativeTabDragHandle extends StatefulWidget {
  final DesktopTabDragData data;
  final ValueChanged<DesktopTabDragData>? onDragStarted;
  final void Function(DesktopTabDragData data, Offset globalPosition)?
      onDragMove;
  final ValueChanged<DesktopTabDragData>? onDragFinished;
  final Future<void> Function(DesktopTabDragData data) onDetachRequested;
  final Widget child;

  const _NativeTabDragHandle({
    Key? key,
    required this.data,
    this.onDragStarted,
    this.onDragMove,
    this.onDragFinished,
    required this.onDetachRequested,
    required this.child,
  }) : super(key: key);

  @override
  State<_NativeTabDragHandle> createState() => _NativeTabDragHandleState();
}

class _NativeTabDragHandleState extends State<_NativeTabDragHandle> {
  Offset? _downPosition;
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
        }
      },
      onPointerMove: (e) {
        if (_downPosition == null) return;
        if ((e.buttons & kPrimaryMouseButton) == 0) return;

        final delta = e.position - _downPosition!;
        if (!_dragging && delta.distance >= _startDistance) {
          _dragging = true;
          widget.onDragStarted?.call(widget.data);
        }

        if (!_dragging || _detaching) return;

        if (delta.dy.abs() >= _detachDistance) {
          _detaching = true;
          unawaited(widget.onDetachRequested(widget.data).whenComplete(_reset));
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
