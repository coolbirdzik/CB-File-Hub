import 'package:flutter/painting.dart';

/// CoolBird type scale.
///
/// Typography is the strongest signal that an app "is Material" — the default
/// Roboto ramp (14/16 body, loose tracking, w400/w500 only) is instantly
/// recognisable. This scale is desktop-density: 13px body, a tighter ramp, a
/// third weight for emphasis, and negative tracking on the large sizes so
/// headings read as set rather than typed.
///
/// Both faces are bundled with the app (`assets/fonts/`, declared in
/// `pubspec.yaml`) rather than borrowed from the platform. Bundling is what
/// makes the type an *identity* instead of a suggestion: a system-font stack
/// renders as Segoe UI on Windows, SF on macOS and Roboto on Android, so the
/// app never looks like one product. Both are SIL Open Font License 1.1 —
/// free for commercial use and redistributable — and both carry the full
/// Vietnamese range, including the đồng sign (₫, U+20AB).
class CbTypography {
  const CbTypography._();

  /// The UI face: Inter.
  static const String uiFamily = 'Inter';

  /// The monospace face: JetBrains Mono.
  static const String monoFamily = 'JetBrains Mono';

  /// Faces to fall back to if a glyph is missing from Inter — CJK and emoji
  /// in particular, which neither bundled family covers.
  static const List<String> uiFallback = <String>[
    'Segoe UI Variable Display',
    'Segoe UI',
    'SF Pro Text',
    'Roboto',
    'Noto Sans',
  ];

  /// Fallbacks for the monospace ramp. Paths and filenames can contain any
  /// script, so a mono run has to degrade to a real font rather than tofu.
  static const List<String> monoFallback = <String>[
    'Cascadia Mono',
    'Consolas',
    'SF Mono',
    'Roboto Mono',
    'monospace',
  ];

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;

  static TextStyle _base(
    double size,
    double height,
    FontWeight weight,
    double tracking, {
    bool mono = false,
  }) {
    return TextStyle(
      fontSize: size,
      // Flutter's `height` is a multiplier of font size, so line heights are
      // expressed here as ratios derived from the intended px leading.
      height: height / size,
      fontWeight: weight,
      letterSpacing: tracking,
      fontFamily: mono ? monoFamily : uiFamily,
      fontFamilyFallback: mono ? monoFallback : uiFallback,
      leadingDistribution: TextLeadingDistribution.even,
    );
  }

  // ─── Display / headings ────────────────────────────────────────────────
  // Negative tracking tightens the large sizes; without it, big text set in a
  // UI face looks airy and unresolved.

  /// 30/36 — the one big number on a screen (scan results, storage totals).
  static TextStyle get displayLg => _base(30, 36, semibold, -0.6);

  /// 24/30 — screen title.
  static TextStyle get displaySm => _base(24, 30, semibold, -0.4);

  /// 19/26 — dialog title, major section header.
  static TextStyle get headingLg => _base(19, 26, semibold, -0.25);

  /// 16/22 — panel header, card title.
  static TextStyle get headingMd => _base(16, 22, semibold, -0.15);

  /// 14/20 — sub-section header, list group label.
  static TextStyle get headingSm => _base(14, 20, semibold, 0);

  // ─── Body ──────────────────────────────────────────────────────────────

  /// 14/20 — long-form text, dialog copy.
  static TextStyle get bodyLg => _base(14, 20, regular, 0);

  /// 13/18 — **the default UI text size**: list rows, labels, menus.
  static TextStyle get body => _base(13, 18, regular, 0);

  /// 12/16 — secondary metadata (size, date modified, item counts).
  static TextStyle get bodySm => _base(12, 16, regular, 0.05);

  // ─── Labels ────────────────────────────────────────────────────────────
  // Labels are the medium-weight counterparts of body: same metrics, more
  // weight, used where text is a control rather than content.

  /// 13/18 medium — button and tab labels.
  static TextStyle get label => _base(13, 18, medium, 0);

  /// 12/16 medium — dense controls, chips, toolbar labels.
  static TextStyle get labelSm => _base(12, 16, medium, 0.05);

  /// 11/14 medium — badges, status pills, column headers.
  static TextStyle get labelXs => _base(11, 14, medium, 0.1);

  /// 11/14 semibold, wide tracking — the small all-caps eyebrow label.
  /// Apply `TextTransform`-style casing at the call site.
  static TextStyle get overline => _base(11, 14, semibold, 0.6);

  /// 11/14 — helper and caption text under an input.
  static TextStyle get caption => _base(11, 14, regular, 0.1);

  // ─── Mono ──────────────────────────────────────────────────────────────

  /// 12/18 monospace — paths, hashes, byte counts in detail panes.
  static TextStyle get mono => _base(12, 18, regular, 0, mono: true);

  /// 11/16 monospace — dense technical readouts.
  static TextStyle get monoSm => _base(11, 16, regular, 0, mono: true);
}
