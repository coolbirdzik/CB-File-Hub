import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A lightweight wrapper that intercepts **Ctrl+scroll** events and converts
/// them into a ±1 zoom delta, leaving all other pointer-signal events (plain
/// scroll, horizontal scroll, etc.) unaffected.
///
/// This is the **single, canonical** implementation of Ctrl+scroll zoom used
/// throughout the app.  Every screen or widget that wants this behaviour
/// should wrap its content with [CtrlScrollZoom] instead of writing its own
/// [Listener].
///
/// Usage:
/// ```dart
/// CtrlScrollZoom(
///   onDelta: _handleGridZoomDelta,
///   child: GridView.builder(...),
/// )
/// ```
///
/// Pass `onDelta: null` to disable the feature without removing the widget
/// from the tree (useful for list/details view modes where zooming is N/A).
class CtrlScrollZoom extends StatelessWidget {
  /// Called with +1 (zoom in / fewer columns) or -1 (zoom out / more columns).
  /// Pass `null` to make the widget a transparent pass-through.
  final void Function(int delta)? onDelta;
  final Widget child;

  const CtrlScrollZoom({super.key, required this.child, this.onDelta});

  bool _isCtrlPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        // macOS / Meta key
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (onDelta == null) return;
    if (event is! PointerScrollEvent) return;
    if (!_isCtrlPressed()) return;

    final direction = event.scrollDelta.dy > 0 ? 1 : -1;
    onDelta!(direction);
    // Prevent other Listeners (parent/sibling) from also handling this event.
    GestureBinding.instance.pointerSignalResolver.resolve(event);
  }

  @override
  Widget build(BuildContext context) {
    if (onDelta == null) return child;
    return Listener(
      onPointerSignal: _onPointerSignal,
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}
