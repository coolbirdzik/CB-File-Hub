import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_color_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';

/// Flat decoration recipes.
///
/// The CoolBird look has no decorative borders. Things are separated by a
/// step on the translucent fill ramp and by spacing; selection is an accent
/// tint; only layers that genuinely float above the page (menus, popovers,
/// dialogs, drag feedback) cast a shadow.
///
/// Every primitive paints through these recipes, and so should any screen
/// that has to own its container — an `AnimatedContainer`, a `DecoratedBox`
/// behind a custom layout. That is what stops each screen re-inventing its
/// own `surfaceContainerHighest.withValues(alpha: 0.3)` plus outline pair.
///
/// The one line that survives is the focus/error indicator: it is state
/// rather than decoration, and keyboard users depend on it.
class CbDecorations {
  const CbDecorations._();

  // ─── Colours ────────────────────────────────────────────────────────────

  /// Fill for a flat container (card, section, selectable tile).
  static Color containerFill(
    CbColorTokens c, {
    bool selected = false,
    bool hovered = false,
    bool pressed = false,
  }) {
    if (selected) {
      return hovered || pressed ? c.accent.tintStrong : c.surfaceSelected;
    }
    if (pressed) return c.fillPressed;
    if (hovered) return c.fillHover;
    return c.fillSubtle;
  }

  /// Fill for a control (secondary button, input, chip, select trigger).
  static Color controlFill(
    CbColorTokens c, {
    bool hovered = false,
    bool pressed = false,
    bool enabled = true,
  }) {
    if (!enabled) return c.fillSubtle;
    if (pressed) return c.fillPressed;
    if (hovered) return c.fillHover;
    return c.fill;
  }

  /// Fill for a card whose resting colour may be overridden by [color].
  ///
  /// Selection always wins. A custom colour cannot step up the fill ramp, so
  /// hover and press layer a wash over it instead — the card keeps its
  /// interaction feedback whatever it is painted.
  static Color cardFill(
    CbColorTokens c, {
    Color? color,
    bool selected = false,
    bool hovered = false,
    bool pressed = false,
  }) {
    if (selected || color == null) {
      return containerFill(
        c,
        selected: selected,
        hovered: hovered,
        pressed: pressed,
      );
    }
    if (pressed) return Color.alphaBlend(c.surfacePressed, color);
    if (hovered) return Color.alphaBlend(c.surfaceHover, color);
    return color;
  }

  // ─── Decorations ────────────────────────────────────────────────────────

  /// A flat card, section or selectable tile. See [cardFill] for [color].
  static BoxDecoration card(
    BuildContext context, {
    bool selected = false,
    bool hovered = false,
    bool pressed = false,
    bool focused = false,
    double radius = CbRadii.md,
    Color? color,
  }) {
    final c = context.cbColors;
    return BoxDecoration(
      color: cardFill(
        c,
        color: color,
        selected: selected,
        hovered: hovered,
        pressed: pressed,
      ),
      borderRadius: CbRadii.all(radius),
      boxShadow: focused ? focusRing(c) : const <BoxShadow>[],
    );
  }

  /// A docked bar — footer action strip, status bar, pane header. An opaque
  /// fill step over the surface stands in for the rule that used to divide
  /// it from the content; opaque because bars often overlay scrolling lists.
  static BoxDecoration bar(BuildContext context) {
    final c = context.cbColors;
    return BoxDecoration(color: Color.alphaBlend(c.fill, c.surface));
  }

  /// A tinted block in [hue] — status badges, error/warning callouts, accent
  /// pills. Flat: the hue alone carries the meaning, so there is no outline
  /// in a stronger shade of the same hue. [strong] is the selected/hovered
  /// step.
  static BoxDecoration tint(
    BuildContext context,
    Color hue, {
    double radius = CbRadii.md,
    bool strong = false,
  }) {
    final bool isDark = context.cb.isDark;
    final double alpha = strong
        ? (isDark ? 0.26 : 0.18)
        : (isDark ? 0.16 : 0.10);
    return BoxDecoration(
      color: hue.withValues(alpha: alpha),
      borderRadius: CbRadii.all(radius),
    );
  }

  /// A layer floating above the page: menus, popovers, drag feedback,
  /// floating toolbars. Depth comes from the shadow alone.
  static BoxDecoration floating(
    BuildContext context, {
    double radius = CbRadii.lg,
    Color? color,
    bool modal = false,
  }) {
    final tokens = context.cb;
    return BoxDecoration(
      color: color ?? tokens.colors.surfaceOverlay,
      borderRadius: CbRadii.all(radius),
      boxShadow: modal ? tokens.shadowLevel4 : tokens.shadowLevel3,
    );
  }

  /// Text-entry chrome: a control fill with a bottom indicator for focus and
  /// error — the Windows 11 field, not a boxed outline.
  static BoxDecoration field(
    BuildContext context, {
    bool focused = false,
    bool hovered = false,
    bool error = false,
    bool enabled = true,
    double radius = CbRadii.sm,
    Color? color,
  }) {
    final c = context.cbColors;
    return BoxDecoration(
      color:
          color ??
          controlFill(c, hovered: hovered && !focused, enabled: enabled),
      borderRadius: CbRadii.all(radius),
      border: fieldIndicator(
        c,
        focused: focused,
        error: error,
        enabled: enabled,
      ),
    );
  }

  /// The bottom focus/error indicator used by [field]. Null when at rest.
  static Border? fieldIndicator(
    CbColorTokens c, {
    bool focused = false,
    bool error = false,
    bool enabled = true,
  }) {
    if (!enabled || (!focused && !error)) return null;
    return Border(
      bottom: BorderSide(
        color: error ? c.status.danger : c.accent.base,
        width: CbStrokes.emphasis,
      ),
    );
  }

  /// The Material input border for the flat field recipe: rounded so the
  /// fill is clipped, with no line at rest and a bottom [indicator] line
  /// otherwise. Underline (not outline) borders keep a floating label inside
  /// the fill instead of cutting across its top edge.
  static UnderlineInputBorder inputBorder(
    Color? indicator, {
    double radius = CbRadii.sm,
  }) {
    return UnderlineInputBorder(
      borderRadius: CbRadii.all(radius),
      borderSide: indicator == null
          ? BorderSide.none
          : BorderSide(color: indicator, width: CbStrokes.emphasis),
    );
  }

  /// Selection wash for file and folder items — list rows, grid tiles and
  /// media tiles alike.
  ///
  /// A translucent accent fill rather than the pale `accent.tintStrong`: with
  /// the default blue that tint sits at about the lightness of the neutral
  /// hover fill, so a selected item differed from a hovered one by hue alone
  /// and was easy to lose in a dense listing. [hovered] steps it up once more
  /// so a selected item still answers the pointer. Translucent, so it reads
  /// the same on the canvas, over the acrylic backdrop, and painted *over* a
  /// thumbnail.
  static Color selectionFill(CbTokens tokens, {bool hovered = false}) {
    final double alpha = tokens.isDark
        ? (hovered ? 0.48 : 0.38)
        : (hovered ? 0.30 : 0.22);
    return tokens.colors.accent.base.withValues(alpha: alpha);
  }

  /// [selectionFill] painted *over* media — photos, video thumbnails — whose
  /// own pixels would hide any fill behind them. Use as a foreground
  /// decoration; it replaces the accent outline such tiles used to draw.
  static BoxDecoration selectedOverlay(
    BuildContext context, {
    double radius = CbRadii.md,
    bool hovered = false,
  }) {
    return BoxDecoration(
      color: selectionFill(context.cb, hovered: hovered),
      borderRadius: CbRadii.all(radius),
    );
  }

  /// Drag-and-drop target highlight. Translucent, so it can also be painted
  /// as a *foreground* decoration over content that has its own background.
  static BoxDecoration dropTarget(
    BuildContext context, {
    bool rejected = false,
    double radius = CbRadii.md,
  }) {
    final c = context.cbColors;
    return BoxDecoration(
      color: (rejected ? c.status.danger : c.accent.base).withValues(
        alpha: 0.14,
      ),
      borderRadius: CbRadii.all(radius),
    );
  }

  /// The 2px keyboard focus ring, drawn outside the shape so it stays
  /// visible on every fill, including the accent one.
  static List<BoxShadow> focusRing(CbColorTokens c) => [
    BoxShadow(color: c.focusRing, spreadRadius: CbStrokes.emphasis),
  ];
}

/// Applies the flat field recipe to a Material [InputDecoration].
///
/// A field that is happy with the app radius needs nothing — the theme's
/// `InputDecorationTheme` already is this recipe. Use `.flat(context, radius:
/// …)` only where a field needs its own corner radius (a pill-shaped search
/// box, a rounded composer), instead of hand-writing six outline borders.
extension CbFlatInputDecoration on InputDecoration {
  InputDecoration flat(BuildContext context, {double radius = CbRadii.sm}) {
    final c = context.cbColors;
    final rest = CbDecorations.inputBorder(null, radius: radius);
    final danger = CbDecorations.inputBorder(c.status.danger, radius: radius);
    return copyWith(
      filled: true,
      border: rest,
      enabledBorder: rest,
      disabledBorder: rest,
      focusedBorder: CbDecorations.inputBorder(c.accent.base, radius: radius),
      errorBorder: danger,
      focusedErrorBorder: danger,
    );
  }
}
