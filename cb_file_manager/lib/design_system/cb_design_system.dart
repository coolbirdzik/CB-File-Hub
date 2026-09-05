/// The CoolBird design system.
///
/// Import this one file to get every token and primitive:
///
/// ```dart
/// import 'package:cb_file_manager/design_system/cb_design_system.dart';
/// ```
///
/// Two layers, and the distinction matters:
///
///   * **Tokens** — `CbSpacing`, `CbRadii`, `CbTypography`, `CbDurations`,
///     `CbSizes` are compile-time constants, reachable anywhere without a
///     [BuildContext]. Colour is the exception: it varies by theme, so it
///     comes from `context.cb.colors`.
///   * **Primitives** — `CbButton`, `CbSurface`, `CbTextField`, `CbDialog`
///     are the widgets that consume those tokens. New UI should be built from
///     these rather than from Material's widgets.
///
/// Existing Material widgets still render correctly: `CbThemeBuilder` maps
/// these tokens onto `ThemeData`, so an un-migrated `ElevatedButton` picks up
/// the right colour, radius and type even before it is replaced.
library;

export 'cb_font_licenses.dart';
export 'cb_theme_builder.dart';
export 'cb_tokens.dart';
export 'fluent_surface_tokens.dart';
export 'primitives/cb_button.dart';
export 'primitives/cb_dialog.dart';
export 'primitives/cb_inline_rename.dart';
export 'primitives/cb_pressable.dart';
export 'primitives/cb_select.dart';
export 'primitives/cb_surface.dart';
export 'primitives/cb_text_field.dart';
export 'primitives/cb_tooltip.dart';
export 'tokens/cb_color_tokens.dart';
export 'tokens/cb_elevation_tokens.dart';
export 'tokens/cb_geometry_tokens.dart';
export 'tokens/cb_motion_tokens.dart';
export 'tokens/cb_type_tokens.dart';
