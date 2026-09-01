import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_motion_tokens.dart';

/// How far a surface sits above what is behind it.
///
/// Depth reads through shadow and border only. Unlike Material 3, the surface
/// colour is *not* tinted with the accent as it rises, so a stack of panels
/// stays neutral instead of drifting blue.
enum CbSurfaceLevel {
  /// Flush with the page. Border-only separation.
  flat,

  /// Resting card or list row.
  raised,

  /// Hovered/lifted card, sticky header.
  lifted,

  /// Menu, popover, dropdown, toast.
  overlay,

  /// Dialog or modal sheet.
  modal,
}

/// The container primitive — replaces `Card`, `Material` and the endless
/// bespoke `Container(decoration: BoxDecoration(...))` blocks.
///
/// Giving every panel one implementation is what keeps radius, border colour
/// and shadow consistent; those three together are most of what makes a
/// design system legible as one system.
class CbSurface extends StatelessWidget {
  final Widget child;
  final CbSurfaceLevel level;

  /// Corner radius. Defaults to the radius conventional for [level].
  final double? radius;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// Draws the hairline border. Defaults to on for [CbSurfaceLevel.flat] and
  /// [CbSurfaceLevel.raised], where the shadow alone is too weak to separate.
  final bool? bordered;

  /// Overrides the background. Use a token, not a literal.
  final Color? color;

  /// Paints the accent selection background and border.
  final bool selected;

  final double? width;
  final double? height;

  /// Clips [child] to the rounded corners. Off by default — clipping forces a
  /// save layer, which is measurable in long file lists.
  final bool clip;

  const CbSurface({
    Key? key,
    required this.child,
    this.level = CbSurfaceLevel.raised,
    this.radius,
    this.padding,
    this.margin,
    this.bordered,
    this.color,
    this.selected = false,
    this.width,
    this.height,
    this.clip = false,
  }) : super(key: key);

  double _radiusFor(CbSurfaceLevel level) {
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
    final tokens = context.cb;
    final c = tokens.colors;
    final double r = radius ?? _radiusFor(level);

    Color background;
    List<BoxShadow> shadow;
    switch (level) {
      case CbSurfaceLevel.flat:
        background = c.surface;
        shadow = const [];
        break;
      case CbSurfaceLevel.raised:
        background = c.surfaceRaised;
        shadow = tokens.shadowLevel1;
        break;
      case CbSurfaceLevel.lifted:
        background = c.surfaceRaised;
        shadow = tokens.shadowLevel2;
        break;
      case CbSurfaceLevel.overlay:
        background = c.surfaceOverlay;
        shadow = tokens.shadowLevel3;
        break;
      case CbSurfaceLevel.modal:
        background = c.surfaceOverlay;
        shadow = tokens.shadowLevel4;
        break;
    }

    final bool showBorder = bordered ??
        (level == CbSurfaceLevel.flat || level == CbSurfaceLevel.raised);

    return AnimatedContainer(
      duration: CbDurations.fast,
      curve: CbCurves.standard,
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: selected ? c.surfaceSelected : (color ?? background),
        borderRadius: CbRadii.all(r),
        border: showBorder || selected
            ? Border.all(
                color: selected ? c.accent.border : c.stroke,
                width: CbStrokes.hairline,
              )
            : null,
        boxShadow: shadow,
      ),
      child: child,
    );
  }
}
