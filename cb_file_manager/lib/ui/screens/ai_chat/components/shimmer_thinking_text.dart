import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:material_ui/material_ui.dart';

/// Animated thinking text with a gradient shimmer effect that slides
/// from left to right, giving the appearance of "processing".
class ShimmerThinkingText extends StatelessWidget {
  final String text;

  const ShimmerThinkingText({super.key, required this.text});

  @override
  Widget build(BuildContext context) => CbLoadingText(
    text: text,
    style: CbTypography.label,
    maxLines: null,
    textAlign: TextAlign.start,
  );
}
