import 'package:material_ui/material_ui.dart';

/// Shared row geometry for the file browser and system collections.
class CompactListContent extends StatelessWidget {
  const CompactListContent({
    super.key,
    required this.leading,
    required this.label,
    this.trailing,
  });

  final Widget leading;
  final Widget label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        40 *
        (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
          1.0,
          double.infinity,
        ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(child: label),
          ?trailing,
        ],
      ),
    ),
  );
}
