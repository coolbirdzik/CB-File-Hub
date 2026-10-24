import 'package:flutter/material.dart';

/// Material slider with a local overlay for its value-indicator portal.
///
/// On Flutter 3.47.2 a slider inserted in a dialog or pushed route can serialize
/// an unreachable semantics node into the app overlay, even without a label.
/// A semantics container alone does not prevent that. Keeping the portal and
/// its anchor in this subtree preserves incremental accessibility updates.
class CbSlider extends StatelessWidget {
  const CbSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.activeColor,
    this.inactiveColor,
    this.semanticFormatterCallback,
    this.focusNode,
    this.autofocus = false,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final Color? activeColor;
  final Color? inactiveColor;
  final SemanticFormatterCallback? semanticFormatterCallback;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Overlay.wrap(
    // Preserve the slider's intrinsic height in rows, columns and scroll views.
    alwaysSizeToContent: true,
    clipBehavior: Clip.none,
    child: Slider(
      value: value,
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      min: min,
      max: max,
      divisions: divisions,
      label: label,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      semanticFormatterCallback: semanticFormatterCallback,
      focusNode: focusNode,
      autofocus: autofocus,
    ),
  );
}
