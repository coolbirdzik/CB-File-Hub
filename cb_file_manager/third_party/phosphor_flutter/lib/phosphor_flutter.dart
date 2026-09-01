library phosphor_flutter;

// Trimmed, locally patched build of phosphor_flutter 2.1.0.
//
// Upstream declares `class PhosphorIconData extends IconData`, which stopped
// compiling when Flutter made IconData a final class. pub.dev has no newer
// release (2.1.0 is the latest) and upstream `main` carries the same broken
// declaration, so there is nothing to upgrade to -- the package is patched here
// instead. See README.md for the regeneration procedure.
//
// Only the styles this app uses are vendored. Reaching for Thin, Regular or
// Duotone is a deliberate compile error rather than a missing glyph; add the
// style via tool/regenerate.sh if one is ever needed.

export 'package:phosphor_flutter/src/phosphor_icons_light.dart';
export 'package:phosphor_flutter/src/phosphor_icons_fill.dart';
export 'package:phosphor_flutter/src/phosphor_icons_bold.dart';
