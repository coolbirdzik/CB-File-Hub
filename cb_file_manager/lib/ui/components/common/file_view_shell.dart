import 'dart:io';

import 'package:flutter/material.dart';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_keyboard_shortcuts.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/widgets/ctrl_scroll_zoom.dart';

/// A wrapper widget that provides the full set of common file-view interactions
/// for any screen that displays a list/grid/details view of items.
///
/// Handles:
/// - **Ctrl+scroll** → adjust grid zoom (only when [viewMode] == [ViewMode.grid])
/// - **Mouse XButton1/XButton2** → optional back/forward navigation
/// - **Keyboard shortcuts** (only on desktop, only when no text-field is focused):
///   - `Escape`       → [onEscape]
///   - `F5` / `Ctrl+R` → [onRefresh]
///   - `Ctrl+A`       → [onSelectAll]
///   - `Delete`       → [onDelete]`(permanent: false)`
///   - `Shift+Delete` → [onDelete]`(permanent: true)`
///
/// Usage:
/// ```dart
/// body: FileViewShell(
///   viewMode: _viewMode,
///   onGridZoomDelta: _handleGridZoomDelta,
///   onRefresh: _loadItems,
///   onSelectAll: _selectAll,
///   onDelete: (_) => _deleteSelected(),
///   onEscape: isSelectionMode ? exitSelectionMode : null,
///   child: _buildBody(),
/// ),
/// ```
class FileViewShell extends StatefulWidget {
  final Widget child;

  // ── Grid zoom / view spectrum ───────────────────────────────────────────────
  /// Current view mode — used to decide whether Ctrl+scroll adjusts zoom only
  /// (legacy [onGridZoomDelta]) or walks the full view spectrum
  /// ([onViewScaleDelta]).
  final ViewMode viewMode;

  /// Called with +1 (zoom in = fewer columns) or -1 (zoom out = more columns).
  /// The callback is responsible for clamping and persisting the new level.
  ///
  /// Legacy: only active in grid/gridPreview modes. Prefer [onViewScaleDelta]
  /// for the unified tree↔column↔detail↔list↔grid spectrum.
  final void Function(int delta)? onGridZoomDelta;

  /// Called for Ctrl+scroll in **any** view mode with a spectrum delta:
  /// `+1` = more spacious (wider modes / bigger grid items),
  /// `-1` = denser (narrower modes / smaller grid items).
  ///
  /// When provided this takes precedence over [onGridZoomDelta] and the
  /// gesture is active in every view mode. The callback owns clamping,
  /// mode-transition, and persistence (typically via `ViewModeSpectrum.step`).
  final void Function(int delta)? onViewScaleDelta;

  // ── Mouse navigation ───────────────────────────────────────────────────────
  /// Called when mouse XButton1 (back) is pressed. Pass `null` to disable.
  final VoidCallback? onMouseBack;

  /// Called when mouse XButton2 (forward) is pressed. Pass `null` to disable.
  final VoidCallback? onMouseForward;

  // ── Keyboard shortcuts ─────────────────────────────────────────────────────
  /// `Escape` — typically used to exit selection mode or close inline search.
  final VoidCallback? onEscape;

  /// `F5` / `Ctrl+R` — refresh the list.
  final VoidCallback? onRefresh;

  /// `Ctrl+A` — select all items.
  final VoidCallback? onSelectAll;

  /// `Delete` (permanent = false) / `Shift+Delete` (permanent = true).
  final void Function({required bool permanent})? onDelete;
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final VoidCallback? onRename;

  /// `Ctrl+F` — open / toggle the search bar.
  final VoidCallback? onSearch;

  final bool enableKeyboardShortcuts;

  const FileViewShell({
    Key? key,
    required this.child,
    required this.viewMode,
    this.onGridZoomDelta,
    this.onViewScaleDelta,
    this.onMouseBack,
    this.onMouseForward,
    this.onEscape,
    this.onRefresh,
    this.onSelectAll,
    this.onDelete,
    this.onCopy,
    this.onCut,
    this.onPaste,
    this.onRename,
    this.onSearch,
    this.enableKeyboardShortcuts = true,
  }) : super(key: key);

  @override
  State<FileViewShell> createState() => _FileViewShellState();
}

class _FileViewShellState extends State<FileViewShell> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'file-view-shell');

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  // ── Pointer signal (Ctrl+scroll for grid zoom) ────────────────────────────
  // Delegated to CtrlScrollZoom — the canonical implementation.

  // ── Mouse side buttons (back / forward) ───────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == 8) {
      widget.onMouseBack?.call();
    } else if (event.buttons == 16) {
      widget.onMouseForward?.call();
    }
  }

  // ── Keyboard shortcuts ────────────────────────────────────────────────────

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (!widget.enableKeyboardShortcuts) {
      return KeyEventResult.ignored;
    }
    return BrowserLikeKeyboardShortcuts.handleBasic(
      isDesktop: _isDesktop,
      event: event,
      onEscape: widget.onEscape,
      onRefresh: widget.onRefresh,
      onSelectAll: widget.onSelectAll,
      onDelete: widget.onDelete == null
          ? null
          : (permanent) => widget.onDelete!(permanent: permanent),
      onCopy: widget.onCopy,
      onCut: widget.onCut,
      onPaste: widget.onPaste,
      onRename: widget.onRename,
      onSearch: widget.onSearch,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Unified view spectrum (Ctrl+scroll in every mode) takes precedence.
    // CtrlScrollZoom emits +1 on scroll-down; the spectrum convention is
    // +1 = more spacious (scroll-up), so invert the raw sign here.
    final void Function(int delta)? scrollDelta;
    if (widget.onViewScaleDelta != null) {
      scrollDelta = (raw) => widget.onViewScaleDelta!(-raw);
    } else {
      // Legacy: Ctrl+scroll zoom is active only in grid/gridPreview modes.
      scrollDelta = (widget.viewMode == ViewMode.grid ||
              widget.viewMode == ViewMode.gridPreview)
          ? widget.onGridZoomDelta
          : null;
    }

    return CtrlScrollZoom(
      onDelta: scrollDelta,
      child: Listener(
        onPointerDown:
            (widget.onMouseBack != null || widget.onMouseForward != null)
                ? _onPointerDown
                : null,
        child: Focus(
          focusNode: _focusNode,
          autofocus: widget.enableKeyboardShortcuts,
          onKeyEvent: _onKeyEvent,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Convenience helper that computes the next grid zoom level given a delta,
/// clamps it to valid bounds, and returns the result.
///
/// Screens should call this inside their [onGridZoomDelta] callback:
/// ```dart
/// void _handleGridZoomDelta(int delta) {
///   final next = FileViewShell.clampGridZoom(context, _gridZoomLevel, delta);
///   if (next == _gridZoomLevel) return;
///   setState(() => _gridZoomLevel = next);
///   UserPreferences.instance.setTrashGridZoomLevel(next);
/// }
/// ```
extension FileViewShellHelpers on FileViewShell {
  static int clampGridZoom(BuildContext context, int current, int delta) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    return (current + delta)
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();
  }
}
