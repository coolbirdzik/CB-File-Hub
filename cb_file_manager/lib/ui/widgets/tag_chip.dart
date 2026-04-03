import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';

/// A reusable tag chip widget for consistent tag styling across the app
class TagChip extends StatelessWidget {
  final String tag;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final bool isCompact;
  final Color? customColor;

  const TagChip({
    Key? key,
    required this.tag,
    this.onTap,
    this.onDeleted,
    this.isCompact = false,
    this.customColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    String tagName = tag;
    if (tag.contains(" (") && tag.endsWith(")")) {
      tagName = tag.substring(0, tag.lastIndexOf(" ("));
    }

    final Color tagColor =
        customColor ?? TagColorManager.instance.getTagColor(tagName);

    final Color displayColor = isDarkMode
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.3), tagColor)
        : tagColor;
    final Color foregroundColor = _bestForegroundColor(displayColor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Chip(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelStyle: TextStyle(
          fontSize: isCompact ? 11 : 12,
          color: foregroundColor,
          fontWeight: FontWeight.w500,
        ),
        label: Text(
          tag,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        backgroundColor: displayColor,
        visualDensity: isCompact ? VisualDensity.compact : null,
        padding: isCompact ? const EdgeInsets.all(1) : const EdgeInsets.all(2),
        deleteIconColor: foregroundColor,
        deleteIcon: onDeleted != null
            ? Icon(PhosphorIconsLight.x, size: 14, color: foregroundColor)
            : null,
        onDeleted: onDeleted,
        elevation: 0,
        side: BorderSide.none,
      ),
    );
  }

  static Color _bestForegroundColor(Color background) {
    const light = Colors.white;
    const dark = Colors.black;
    final lightContrast = _contrastRatio(background, light);
    final darkContrast = _contrastRatio(background, dark);
    return lightContrast >= darkContrast ? light : dark;
  }

  static double _contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
    final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
