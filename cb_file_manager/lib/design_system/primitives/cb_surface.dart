import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import 'cb_decorations.dart';
import 'cb_pressable.dart';

/// How far a surface sits above what is behind it.
///
/// Nothing here draws a border. Resting surfaces are separated from the page
/// by a step on the translucent fill ramp; only layers that float above the
/// page cast a shadow. The surface colour is never tinted with the accent as
/// it rises (as Material 3 does), so a stack of panels stays neutral.
enum CbSurfaceLevel {
  /// A tonal block flush with the page. The default card and section.
  flat,

  /// A stronger tonal block — emphasised cards, or a card nested in a
  /// [flat] one.
  raised,

  /// Solid surface with a soft shadow — dragged/lifted card, sticky header.
  lifted,

  /// Menu, popover, dropdown, toast.
  overlay,

  /// Dialog or modal sheet.
  modal,
}

/// The container primitive — replaces `Card`, `Material` and the endless
/// bespoke `Container(decoration: BoxDecoration(...))` blocks.
///
/// Giving every panel one implementation is what keeps radius, fill and
/// shadow consistent; those three together are most of what makes a design
/// system legible as one system.
///
/// Pass [onPressed] to make it a pressable card: the fill steps up the ramp
/// on hover and press, and keyboard focus shows the focus ring.
class CbSurface extends StatelessWidget {
  final Widget child;
  final CbSurfaceLevel level;

  /// Corner radius. Defaults to the radius conventional for [level].
  final double? radius;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Overrides the resting background. Use a token, not a literal.
  final Color? color;

  /// Paints the accent selection fill.
  final bool selected;

  final double? width;
  final double? height;

  /// Clips [child] to the rounded corners. Off by default — clipping forces a
  /// save layer, which is measurable in long file lists.
  final bool clip;

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final String? tooltip;
  final String? semanticLabel;
  final MouseCursor cursor;

  const CbSurface({
    super.key,
    required this.child,
    this.level = CbSurfaceLevel.flat,
    this.radius,
    this.padding,
    this.margin,
    this.color,
    this.selected = false,
    this.width,
    this.height,
    this.clip = false,
    this.onPressed,
    this.onLongPress,
    this.onSecondaryTap,
    this.tooltip,
    this.semanticLabel,
    this.cursor = SystemMouseCursors.click,
  });

  static double radiusFor(CbSurfaceLevel level) {
    switch (level) {
      case CbSurfaceLevel.flat:
      case CbSurfaceLevel.raised:
        return CbRadii.md;
      case CbSurfaceLevel.lifted:
      case CbSurfaceLevel.overlay:
        return CbRadii.lg;
      case CbSurfaceLevel.modal:
        return CbRadii.xl;
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = onPressed == null
        ? _paint(context, const CbInteractionState())
        : CbPressable(
            onPressed: onPressed,
            onLongPress: onLongPress,
            onSecondaryTap: onSecondaryTap,
            tooltip: tooltip,
            semanticLabel: semanticLabel,
            cursor: cursor,
            builder: _paint,
          );
    if (margin == null) return surface;
    return Padding(padding: margin!, child: surface);
  }

  Widget _paint(BuildContext context, CbInteractionState state) {
    final tokens = context.cb;
    final c = tokens.colors;
    final double r = radius ?? radiusFor(level);
    // Resting colour per level: null means "on the fill ramp" (flat/raised),
    // otherwise a solid surface that hover washes over.
    final (Color? base, List<BoxShadow> shadow) = switch (level) {
      CbSurfaceLevel.flat || CbSurfaceLevel.raised => (null, const []),
      CbSurfaceLevel.lifted => (c.surfaceRaised, tokens.shadowLevel2),
      CbSurfaceLevel.overlay => (c.surfaceOverlay, tokens.shadowLevel3),
      CbSurfaceLevel.modal => (c.surfaceOverlay, tokens.shadowLevel4),
    };

    final Color background =
        level == CbSurfaceLevel.raised && color == null && !selected
        ? CbDecorations.controlFill(
            c,
            hovered: state.hovered,
            pressed: state.pressed,
          )
        : CbDecorations.cardFill(
            c,
            color: color ?? base,
            selected: selected,
            hovered: state.hovered,
            pressed: state.pressed,
          );

    return AnimatedContainer(
      duration: CbDurations.fast,
      curve: CbCurves.standard,
      width: width,
      height: height,
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: background,
        borderRadius: CbRadii.all(r),
        boxShadow: state.focused
            ? [...shadow, ...CbDecorations.focusRing(c)]
            : shadow,
      ),
      child: child,
    );
  }
}
