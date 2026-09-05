import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/cb_motion_tokens.dart';
import 'cb_tooltip.dart';

/// The interaction states a CoolBird control can be in.
@immutable
class CbInteractionState {
  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool disabled;

  const CbInteractionState({
    this.hovered = false,
    this.pressed = false,
    this.focused = false,
    this.disabled = false,
  });
}

/// Interaction foundation for every CoolBird control.
///
/// This exists to replace `InkWell`. Material's ink ripple is a touch idiom:
/// it animates outward from a finger's contact point, and on a desktop file
/// manager — where every row, toolbar icon and breadcrumb is clickable — it
/// reads as constant visual noise. Here, feedback is an instant colour change
/// on hover and press, which is what pointer-driven UI conventionally does.
///
/// It also handles the keyboard contract Material gives you for free: Space
/// and Enter activate, and focus is shown with a real 2px ring rather than a
/// tinted overlay.
class CbPressable extends StatefulWidget {
  /// Builds the visual for the current state. Called on every state change.
  final Widget Function(BuildContext context, CbInteractionState state) builder;

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  /// When false the control is inert and paints its disabled state.
  final bool enabled;

  /// Cursor shown on hover. Buttons use [SystemMouseCursors.basic] rather than
  /// `click` to match native desktop conventions, where the hand cursor means
  /// "hyperlink".
  final MouseCursor cursor;

  final FocusNode? focusNode;
  final bool autofocus;

  /// Whether the control participates in tab traversal.
  final bool canRequestFocus;

  final String? semanticLabel;
  final String? tooltip;

  const CbPressable({
    super.key,
    required this.builder,
    this.onPressed,
    this.onLongPress,
    this.onSecondaryTap,
    this.enabled = true,
    this.cursor = SystemMouseCursors.basic,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.semanticLabel,
    this.tooltip,
  });

  @override
  State<CbPressable> createState() => _CbPressableState();
}

class _CbPressableState extends State<CbPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _isEnabled => widget.enabled && widget.onPressed != null;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _activate() {
    if (!_isEnabled) return;
    widget.onPressed!.call();
  }

  @override
  Widget build(BuildContext context) {
    final state = CbInteractionState(
      hovered: _hovered && _isEnabled,
      pressed: _pressed && _isEnabled,
      focused: _focused && _isEnabled,
      disabled: !_isEnabled,
    );

    Widget child = widget.builder(context, state);

    child = MouseRegion(
      cursor: _isEnabled ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => _setHovered(true),
      onExit: (_) {
        _setHovered(false);
        _setPressed(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isEnabled ? _activate : null,
        onTapDown: _isEnabled ? (_) => _setPressed(true) : null,
        onTapUp: _isEnabled ? (_) => _setPressed(false) : null,
        onTapCancel: _isEnabled ? () => _setPressed(false) : null,
        onLongPress: _isEnabled ? widget.onLongPress : null,
        onSecondaryTap: _isEnabled ? widget.onSecondaryTap : null,
        child: child,
      ),
    );

    child = FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: _isEnabled && widget.canRequestFocus,
      descendantsAreFocusable: false,
      onFocusChange: (value) {
        if (_focused == value) return;
        setState(() => _focused = value);
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: child,
    );

    if (widget.semanticLabel != null) {
      child = Semantics(
        label: widget.semanticLabel,
        button: true,
        enabled: _isEnabled,
        child: child,
      );
    }

    if (widget.tooltip != null) {
      child = CbTooltip(
        message: widget.tooltip!,
        waitDuration: CbDurations.slow,
        child: child,
      );
    }

    return child;
  }
}
