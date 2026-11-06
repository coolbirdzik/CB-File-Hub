import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_color_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';

/// Decoration recipes — the Raycast-style look.
///
/// Resting things have no decorative border: they are separated by a step on
/// the translucent fill ramp and by spacing. Selection is a *neutral* wash —
/// the accent is kept for the primary action and for state (focus, toggles),
/// so a screen full of selected rows does not turn blue. Layers that float
/// above the page (menus, popovers, dialogs, the command palette) get a
/// hairline edge plus a soft, wide shadow, which lets them sit on the acrylic
/// backdrop without a heavy drop shadow.
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
      return hovered || pressed
          ? Color.alphaBlend(c.surfaceHover, c.surfaceSelected)
          : c.surfaceSelected;
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
  /// floating toolbars, the command palette. A hairline edge plus a soft,
  /// wide shadow.
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
      border: Border.all(color: floatingEdge(tokens.colors)),
      boxShadow: modal ? tokens.shadowLevel4 : tokens.shadowLevel3,
    );
  }

  /// The hairline edge of a floating layer (see [floating]). Exposed so the
  /// Material component themes (dialogs, menus, tooltips) draw the same line.
  static Color floatingEdge(CbColorTokens c) => c.stroke;

  /// The shape for a floating Material component — dialog, popup menu,
  /// snackbar — carrying the [floatingEdge] hairline.
  static RoundedRectangleBorder floatingShape(
    CbColorTokens c, {
    double radius = CbRadii.lg,
  }) {
    return RoundedRectangleBorder(
      borderRadius: CbRadii.all(radius),
      side: BorderSide(color: floatingEdge(c)),
    );
  }

  /// A keyboard-shortcut key cap (`Ctrl`, `K`, `↵`) shown beside menu items
  /// and in the command palette footer.
  static BoxDecoration kbd(BuildContext context) {
    final c = context.cbColors;
    return BoxDecoration(color: c.fill, borderRadius: CbRadii.all(CbRadii.xs));
  }

  /// Text-entry chrome: a control fill with a hairline edge that brightens on
  /// hover and focus, and turns danger on error.
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
        hovered: hovered,
        error: error,
        enabled: enabled,
      ),
    );
  }

  /// The hairline edge used by [field]. Always present (transparent when
  /// disabled) so focusing a field never shifts its content by a pixel.
  static Border fieldIndicator(
    CbColorTokens c, {
    bool focused = false,
    bool hovered = false,
    bool error = false,
    bool enabled = true,
  }) {
    return Border.all(
      color: fieldEdge(
        c,
        focused: focused,
        hovered: hovered,
        error: error,
        enabled: enabled,
      ),
    );
  }

  /// Colour of a field's hairline edge for the given state.
  static Color fieldEdge(
    CbColorTokens c, {
    bool focused = false,
    bool hovered = false,
    bool error = false,
    bool enabled = true,
  }) {
    if (!enabled) return Colors.transparent;
    if (error) return c.status.danger;
    if (focused) return c.textTertiary;
    if (hovered) return c.strokeStrong;
    return c.stroke;
  }

  /// The Material input border for the field recipe: a rounded hairline in
  /// [edge]. Fields in this app carry a static label above them, so the
  /// outline's label notch is rarely in play.
  static OutlineInputBorder inputBorder(
    Color edge, {
    double radius = CbRadii.sm,
  }) {
    return OutlineInputBorder(
      borderRadius: CbRadii.all(radius),
      borderSide: BorderSide(color: edge),
    );
  }

  /// Selection wash for file and folder items — list rows and grid tiles.
  ///
  /// Neutral, Raycast-style: a strong grey wash rather than an accent fill,
  /// so a large selection reads as highlighted without flooding the listing
  /// with colour. It stands at least twice as far off the canvas as the hover
  /// fill (asserted in `cb_design_system_test.dart`), and [hovered] steps it
  /// up once more so a selected item still answers the pointer. Translucent,
  /// so it reads the same on the canvas and over the acrylic backdrop.
  static Color selectionFill(CbTokens tokens, {bool hovered = false}) {
    final Color ink = tokens.isDark ? Colors.white : CbNeutral.n1000;
    final double alpha = tokens.isDark
        ? (hovered ? 0.22 : 0.17)
        : (hovered ? 0.16 : 0.125);
    return ink.withValues(alpha: alpha);
  }

  /// Selection painted *over* media — photos, video thumbnails — whose own
  /// pixels would hide a fill. A neutral wash alone vanishes on a busy image,
  /// so this adds a 2px ring in the primary text colour. Use it as a
  /// foreground decoration.
  static BoxDecoration selectedOverlay(
    BuildContext context, {
    double radius = CbRadii.md,
    bool hovered = false,
  }) {
    final tokens = context.cb;
    return BoxDecoration(
      color: (tokens.isDark ? Colors.white : CbNeutral.n1000).withValues(
        alpha: hovered ? 0.16 : 0.10,
      ),
      borderRadius: CbRadii.all(radius),
      border: Border.all(
        color: tokens.colors.textPrimary.withValues(alpha: hovered ? 1 : 0.85),
        width: CbStrokes.emphasis,
      ),
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
    final rest = CbDecorations.inputBorder(c.stroke, radius: radius);
    final danger = CbDecorations.inputBorder(c.status.danger, radius: radius);
    return copyWith(
      filled: true,
      border: rest,
      enabledBorder: rest,
      disabledBorder: CbDecorations.inputBorder(
        Colors.transparent,
        radius: radius,
      ),
      focusedBorder: CbDecorations.inputBorder(c.textTertiary, radius: radius),
      errorBorder: danger,
      focusedErrorBorder: danger,
    );
  }
}
