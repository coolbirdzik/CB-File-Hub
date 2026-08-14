import 'package:flutter/painting.dart';

/// Elevation tokens — real shadows, not tinted surfaces.
///
/// Material 3 signals depth by tinting a surface with the primary colour
/// (`surfaceTint`), which is why M3 cards drift lavender/blue as they rise.
/// This system rejects that: depth is a shadow plus a hairline border, and
/// surface colour stays neutral at every level. `surfaceTint` is forced
/// transparent wherever Material would otherwise apply it.
///
/// Each level is a two-part shadow — a tight contact shadow that anchors the
/// element to what is under it, plus a wider ambient shadow for the cast.
class CbElevation {
  const CbElevation._();

  /// Flush with its parent. No shadow; use a border for separation.
  static const List<BoxShadow> level0 = <BoxShadow>[];

  /// Resting card or list row.
  static List<BoxShadow> level1(Color shadow, {bool isDark = false}) => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.40 : 0.05),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.24 : 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  /// Hovered/lifted card, sticky headers.
  static List<BoxShadow> level2(Color shadow, {bool isDark = false}) => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.46 : 0.06),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.30 : 0.05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// Menus, popovers, dropdowns, toasts.
  static List<BoxShadow> level3(Color shadow, {bool isDark = false}) => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.52 : 0.08),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.38 : 0.07),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  /// Dialogs and modal sheets — the top of the stack.
  static List<BoxShadow> level4(Color shadow, {bool isDark = false}) => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.60 : 0.10),
          blurRadius: 6,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.46 : 0.09),
          blurRadius: 48,
          offset: const Offset(0, 16),
        ),
      ];
}
