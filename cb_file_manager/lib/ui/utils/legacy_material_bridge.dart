import 'package:material_ui/material_ui.dart';

/// Lets packages that still import `package:flutter/material.dart` find a
/// legacy `Theme` and `MaterialLocalizations` under this app's `material_ui`
/// theme. Without it they fall back to the default light theme or throw
/// "No MaterialLocalizations found".
///
/// Needed for `flutter_markdown_plus`, `media_kit_video`,
/// `flutter_colorpicker` and `window_manager`. Remove it, and the `ignore`
/// below, once those packages import `package:material_ui`.
///
/// Place it below a `material_ui` [Theme], e.g. in `MaterialApp.builder`.
class LegacyMaterialBridge extends StatelessWidget {
  const LegacyMaterialBridge({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return MaterialUiCompatibilityBridge(child: child);
  }
}
