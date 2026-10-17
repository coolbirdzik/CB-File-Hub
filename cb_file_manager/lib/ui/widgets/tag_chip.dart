import 'package:flutter/material.dart';
import 'dart:math' as math;
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
    super.key,
    required this.tag,
    this.onTap,
    this.onDeleted,
    this.isCompact = false,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: TagColorManager.instance,
    builder: (context, _) => _buildChip(context),
  );

  Widget _buildChip(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    String tagName = tag;
    if (tag.contains(" (") && tag.endsWith(")")) {
      tagName = tag.substring(0, tag.lastIndexOf(" ("));
    }

    final Color tagColor =
        customColor ?? TagColorManager.instance.getTagColor(tagName);

    final Color displayColor = TagChipStyle.background(
      tagColor,
      isDark: isDarkMode,
    );
    final Color foregroundColor = TagChipStyle.readableOn(displayColor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Chip(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelStyle: TagChipStyle.labelStyle(context).copyWith(
          fontSize: isCompact ? 11 : TagChipStyle.fontSize,
          color: foregroundColor,
        ),
        label: Text(tag, overflow: TextOverflow.ellipsis, maxLines: 1),
        backgroundColor: displayColor,
        visualDensity: isCompact
            ? VisualDensity.compact
            : VisualDensity.standard,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        padding: isCompact
            ? const EdgeInsets.all(1)
            : const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
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
}

/// The shared colour recipe for every tag chip in the app.
///
/// Flat: a chip uses its tag colour with no outline; hover adjusts its shade.
/// Keeping the recipe
/// here is what lets the inline chips, the chips-input chips and the tag
/// management chips stay the same object in three places.
class TagChipStyle {
  const TagChipStyle._();

  static const double radius = 16;
  static const double fontSize = 13;
  static const double lineHeight = 1.25;
  static const double iconSize = 14;
  static const double iconExtent = 20;
  static const padding = EdgeInsets.symmetric(horizontal: 10, vertical: 6);

  static TextStyle labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: fontSize,
        height: lineHeight,
        fontWeight: FontWeight.w500,
      );

  /// The editor inside a parent chip has the same height as a single-line tag,
  /// including when the user increases the system text size.
  static double height(BuildContext context) =>
      math.max(
        iconExtent,
        MediaQuery.textScalerOf(context).scale(fontSize) * lineHeight,
      ) +
      padding.vertical;

  /// Matches file-list chips, including their lighter shade in dark mode.
  static Color background(
    Color tagColor, {
    required bool isDark,
    bool hovered = false,
  }) {
    final base = isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.3), tagColor)
        : tagColor;
    return hovered
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.08), base)
        : base;
  }

  static BoxDecoration decoration(
    Color tagColor, {
    required bool isDark,
    bool hovered = false,
  }) {
    return BoxDecoration(
      color: background(tagColor, isDark: isDark, hovered: hovered),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// Black or white — whichever contrasts better with [background].
  static Color readableOn(Color background) {
    const light = Colors.white;
    const dark = Colors.black;
    return _contrastRatio(background, light) >= _contrastRatio(background, dark)
        ? light
        : dark;
  }

  static double _contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
    final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
