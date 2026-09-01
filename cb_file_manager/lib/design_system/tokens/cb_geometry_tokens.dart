import 'package:flutter/painting.dart';

/// Spacing scale.
///
/// A 4px base grid, with a 2px half-step for optical nudges inside dense
/// controls. Everything in the app should measure out of this scale rather
/// than inventing values — that is what makes unrelated screens feel like the
/// same product.
///
/// Material's default component paddings (16/24 everywhere) are tuned for
/// touch targets on a phone; a desktop file manager showing hundreds of rows
/// needs the tighter end of the scale to be the common case.
class CbSpacing {
  const CbSpacing._();

  /// 2 — optical nudges only.
  static const double xxs = 2;

  /// 4 — icon-to-label inside a dense control.
  static const double xs = 4;

  /// 8 — the default gap between related elements.
  static const double sm = 8;

  /// 12 — control padding, list-row insets.
  static const double md = 12;

  /// 16 — gap between groups, panel padding.
  static const double lg = 16;

  /// 24 — section separation, dialog padding.
  static const double xl = 24;

  /// 32 — major layout blocks.
  static const double xxl = 32;

  /// 48 — page-level breathing room, empty states.
  static const double xxxl = 48;
}

/// Corner-radius scale.
///
/// The single biggest tell of a Material app is its radius: M3's 20px pill on
/// every button and card reads as consumer-mobile. This scale tops out far
/// lower and reserves the round end for genuinely pill-shaped things
/// (chips, avatars, progress tracks).
class CbRadii {
  const CbRadii._();

  /// 0 — flush edges, table cells.
  static const double none = 0;

  /// 3 — tiny chrome: checkbox, tag dot, thumbnail badge.
  static const double xs = 3;

  /// 5 — inputs, small buttons, list-row selection.
  static const double sm = 5;

  /// 7 — buttons, cards, menu items.
  static const double md = 7;

  /// 10 — panels, popovers, toasts.
  static const double lg = 10;

  /// 14 — dialogs, sheets, the window shell.
  static const double xl = 14;

  /// Fully round — chips, avatars, progress tracks.
  static const double full = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

/// Stroke widths.
///
/// Borders carry the structure in this system instead of Material's tinted
/// elevation, so there are only two weights and both are hairline: 1px for
/// everything, 2px reserved for focus and active indicators where the extra
/// weight is the signal.
class CbStrokes {
  const CbStrokes._();

  static const double hairline = 1;
  static const double emphasis = 2;
}

/// Control heights.
///
/// Fixed heights keep toolbars, inputs and buttons aligning on the same
/// baseline without every call site guessing at vertical padding.
class CbSizes {
  const CbSizes._();

  /// 24 — inline chip, tag, compact icon button.
  static const double controlXs = 24;

  /// 28 — toolbar icon button, dense list row.
  static const double controlSm = 28;

  /// 32 — the default control height (button, input, dropdown).
  static const double controlMd = 32;

  /// 40 — prominent/primary actions, mobile-sized touch targets.
  static const double controlLg = 40;

  /// 44 — minimum comfortable touch target on mobile.
  static const double touchTarget = 44;

  /// Icon sizes, paired with the control heights above.
  static const double iconXs = 12;
  static const double iconSm = 14;
  static const double iconMd = 16;
  static const double iconLg = 20;
  static const double iconXl = 24;
}
