import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_color_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_decorations.dart';
import 'cb_pressable.dart';

/// Visual weight of a button.
///
/// The set is deliberately small and hierarchical: a screen should have at
/// most one [primary], a few [secondary], and any number of [subtle]/[ghost].
/// Material's five overlapping button types (elevated / filled / tonal /
/// outlined / text) invite inconsistency because the difference between them
/// is decorative rather than semantic.
///
/// Every variant is flat: weight is carried by the fill alone, never by a
/// border.
enum CbButtonVariant {
  /// Solid accent fill. The single most important action in a view.
  primary,

  /// Neutral tonal fill. The default for most actions.
  secondary,

  /// A lighter neutral wash. Dense toolbars, segmented groups.
  subtle,

  /// No fill until hovered. Tertiary actions, close buttons.
  ghost,

  /// Solid destructive fill. Delete, permanently remove, format.
  danger,

  /// Destructive tint. Destructive but not the primary action.
  dangerSubtle,
}

enum CbButtonSize {
  /// 24px tall — inline with body text, inside table rows.
  xs,

  /// 28px tall — dense toolbars.
  sm,

  /// 32px tall — the default.
  md,

  /// 40px tall — prominent actions, mobile.
  lg,
}

/// The CoolBird button.
class CbButton extends StatelessWidget {
  final String? label;
  final IconData? icon;

  /// Icon shown after the label — for disclosure carets and external-link
  /// affordances.
  final IconData? trailingIcon;

  final VoidCallback? onPressed;
  final CbButtonVariant variant;
  final CbButtonSize size;

  /// Stretches the button to its parent's width.
  final bool expand;

  /// Replaces the leading icon with a spinner and blocks interaction.
  final bool loading;

  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;

  const CbButton({
    super.key,
    this.label,
    this.icon,
    this.trailingIcon,
    required this.onPressed,
    this.variant = CbButtonVariant.secondary,
    this.size = CbButtonSize.md,
    this.expand = false,
    this.loading = false,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
  }) : assert(
         label != null || icon != null,
         'A button needs a label, an icon, or both.',
       );

  /// Icon-only button. Requires a [tooltip] so the action stays discoverable
  /// and screen readers have something to announce.
  const CbButton.icon({
    super.key,
    required IconData this.icon,
    required this.onPressed,
    required String this.tooltip,
    this.variant = CbButtonVariant.ghost,
    this.size = CbButtonSize.md,
    this.loading = false,
    this.focusNode,
    this.autofocus = false,
  }) : label = null,
       trailingIcon = null,
       expand = false;

  double get _height {
    switch (size) {
      case CbButtonSize.xs:
        return CbSizes.controlXs;
      case CbButtonSize.sm:
        return CbSizes.controlSm;
      case CbButtonSize.md:
        return CbSizes.controlMd;
      case CbButtonSize.lg:
        return CbSizes.controlLg;
    }
  }

  double get _iconSize {
    switch (size) {
      case CbButtonSize.xs:
        return CbSizes.iconXs;
      case CbButtonSize.sm:
        return CbSizes.iconSm;
      case CbButtonSize.md:
        return CbSizes.iconMd;
      case CbButtonSize.lg:
        return CbSizes.iconLg;
    }
  }

  double get _hPadding {
    if (label == null) return 0; // icon-only buttons stay square
    switch (size) {
      case CbButtonSize.xs:
        return CbSpacing.sm;
      case CbButtonSize.sm:
        return CbSpacing.md - 2;
      case CbButtonSize.md:
        return CbSpacing.md;
      case CbButtonSize.lg:
        return CbSpacing.lg;
    }
  }

  double get _radius => size == CbButtonSize.lg ? CbRadii.md : CbRadii.sm;

  TextStyle get _textStyle {
    switch (size) {
      case CbButtonSize.xs:
        return CbTypography.labelXs;
      case CbButtonSize.sm:
        return CbTypography.labelSm;
      case CbButtonSize.md:
      case CbButtonSize.lg:
        return CbTypography.label;
    }
  }

  _CbButtonPaint _paint(CbColorTokens c, CbInteractionState s) {
    if (s.disabled) {
      return _CbButtonPaint(
        // A disabled filled button keeps its silhouette — the faintest wash —
        // so the layout does not shift and the hierarchy stays readable.
        background: variant == CbButtonVariant.ghost
            ? Colors.transparent
            : c.fillSubtle,
        foreground: c.textDisabled,
      );
    }

    switch (variant) {
      case CbButtonVariant.primary:
        return _CbButtonPaint(
          background: s.pressed
              ? c.accent.pressed
              : s.hovered
              ? c.accent.hover
              : c.accent.base,
          foreground: c.accent.onBase,
        );

      case CbButtonVariant.secondary:
        return _CbButtonPaint(
          background: CbDecorations.controlFill(
            c,
            hovered: s.hovered,
            pressed: s.pressed,
          ),
          foreground: c.textPrimary,
        );

      case CbButtonVariant.subtle:
        return _CbButtonPaint(
          background: s.pressed
              ? c.fillHover
              : s.hovered
              ? c.fill
              : c.fillSubtle,
          foreground: c.textPrimary,
        );

      case CbButtonVariant.ghost:
        return _CbButtonPaint(
          background: s.pressed
              ? c.surfacePressed
              : s.hovered
              ? c.surfaceHover
              : Colors.transparent,
          foreground: s.hovered ? c.textPrimary : c.textSecondary,
        );

      case CbButtonVariant.danger:
        return _CbButtonPaint(
          background: s.pressed || s.hovered
              ? c.status.dangerHover
              : c.status.danger,
          foreground: c.textInverse,
        );

      case CbButtonVariant.dangerSubtle:
        return _CbButtonPaint(
          background: Color.alphaBlend(
            c.status.danger.withValues(
              alpha: s.pressed
                  ? 0.16
                  : s.hovered
                  ? 0.10
                  : 0.0,
            ),
            c.status.dangerSurface,
          ),
          foreground: c.status.danger,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cb;
    final c = tokens.colors;
    final bool interactive = onPressed != null && !loading;

    return CbPressable(
      onPressed: interactive ? onPressed : null,
      enabled: interactive,
      tooltip: tooltip,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: label ?? tooltip,
      builder: (context, state) {
        final paint = _paint(c, state);

        return AnimatedContainer(
          duration: CbDurations.instant,
          curve: CbCurves.standard,
          height: _height,
          width: label == null ? _height : null,
          padding: EdgeInsets.symmetric(horizontal: _hPadding),
          decoration: BoxDecoration(
            color: paint.background,
            borderRadius: CbRadii.all(_radius),
            // The focus ring sits outside the shape, so focus stays visible
            // on every variant including the accent fill.
            boxShadow: state.focused ? CbDecorations.focusRing(c) : null,
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: _content(paint.foreground),
          ),
        );
      },
    );
  }

  List<Widget> _content(Color foreground) {
    final children = <Widget>[];

    if (loading) {
      children.add(
        SizedBox(
          width: _iconSize,
          height: _iconSize,
          child: CircularProgressIndicator(
            strokeWidth: CbStrokes.emphasis,
            valueColor: AlwaysStoppedAnimation<Color>(foreground),
          ),
        ),
      );
    } else if (icon != null) {
      children.add(Icon(icon, size: _iconSize, color: foreground));
    }

    if (label != null) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: CbSpacing.sm));
      }
      children.add(
        Flexible(
          child: Text(
            label!,
            style: _textStyle.copyWith(color: foreground),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    if (trailingIcon != null) {
      children
        ..add(const SizedBox(width: CbSpacing.xs))
        ..add(Icon(trailingIcon, size: _iconSize, color: foreground));
    }

    return children;
  }
}

@immutable
class _CbButtonPaint {
  final Color background;
  final Color foreground;

  const _CbButtonPaint({required this.background, required this.foreground});
}
