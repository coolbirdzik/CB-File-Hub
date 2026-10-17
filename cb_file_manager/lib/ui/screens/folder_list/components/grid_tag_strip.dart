import 'package:flutter/material.dart';

import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart';

/// Tags under a grid tile, scaled to the tile's width (see [GridTagTier]):
/// bigger tiles get bigger text and more rows. Each chip is a soft tint of the
/// tag colour with a colour dot and neutral text, so a grid full of tags stays
/// calm; whatever does not fit collapses into a muted "+N".
class GridTagStrip extends StatelessWidget {
  final List<String> tags;
  final double tileWidth;

  const GridTagStrip({super.key, required this.tags, required this.tileWidth});

  static const double _chipHPadding = 6.0;
  static const double _chipGap = 4.0;
  static const double _dotGap = 4.0;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final tier = GridTagTier.forWidth(tileWidth);

    return ListenableBuilder(
      listenable: TagColorManager.instance,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        if (tier.dotsOnly) return _buildDots(isDark);
        return LayoutBuilder(
          builder: (context, constraints) =>
              _buildChips(context, tier, constraints.maxWidth, isDark),
        );
      },
    );
  }

  /// The tag's colour, lifted a little in dark mode like every other chip.
  Color _dotColor(String tag, bool isDark) => TagChipStyle.background(
    TagColorManager.instance.getTagColor(tag),
    isDark: isDark,
  );

  static double _dotSize(GridTagTier tier) =>
      (tier.fontSize * 0.55).roundToDouble();

  Widget _buildDots(bool isDark) {
    const maxDots = 4;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final tag in tags.take(maxDots))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: GridTagTier.dotSize,
              height: GridTagTier.dotSize,
              decoration: BoxDecoration(
                color: _dotColor(tag, isDark),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChips(
    BuildContext context,
    GridTagTier tier,
    double maxWidth,
    bool isDark,
  ) {
    // Merged with the ambient style so the measured width matches the font
    // the chips actually render with.
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontSize: tier.fontSize,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
    );
    final scaler = MediaQuery.textScalerOf(context);

    double textWidth(String text, {FontWeight? weight}) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width + 1;
      painter.dispose();
      return width;
    }

    double chipWidth(String tag) =>
        (textWidth(tag) + _chipHPadding * 2 + _dotSize(tier) + _dotGap).clamp(
          0.0,
          maxWidth,
        );
    double moreWidth(int hidden) =>
        textWidth('+$hidden', weight: FontWeight.w600);

    final widths = [for (final tag in tags) chipWidth(tag)];

    // Greedy row packing of the first [count] tags, plus a "+N" chip when some
    // are left out. Returns null if that does not fit in [GridTagTier.maxRows].
    List<List<_Item>>? pack(int count) {
      final hidden = tags.length - count;
      final items = <_Item>[
        for (var i = 0; i < count; i++) _Item.tag(tags[i], widths[i]),
        if (hidden > 0) _Item.more(hidden, moreWidth(hidden)),
      ];
      final rows = <List<_Item>>[[]];
      var used = 0.0;
      for (final item in items) {
        final needed = rows.last.isEmpty
            ? item.width
            : used + _chipGap + item.width;
        if (needed <= maxWidth) {
          rows.last.add(item);
          used = needed;
        } else if (rows.length < tier.maxRows && rows.last.isNotEmpty) {
          rows.add([item]);
          used = item.width;
        } else {
          return null;
        }
      }
      return rows;
    }

    List<List<_Item>>? rows;
    for (var count = tags.length; count >= 1 && rows == null; count--) {
      rows = pack(count);
    }
    // Even one tag plus "+N" does not fit on a row: squeeze the tag.
    rows ??= [
      [
        _Item.tag(tags.first, widths.first),
        if (tags.length > 1)
          _Item.more(tags.length - 1, moreWidth(tags.length - 1)),
      ],
    ];

    bool rowOverflows(List<_Item> row) =>
        row.fold<double>(0, (sum, item) => sum + item.width) +
            _chipGap * (row.length - 1) >
        maxWidth;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) const SizedBox(height: GridTagTier.rowGap),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < rows[r].length; i++) ...[
                if (i > 0) const SizedBox(width: _chipGap),
                // Packed rows fit as measured. Only the squeezed fallback row
                // lets its tag shrink; Flexible on every chip would split the
                // row evenly and clip the longer names.
                if (rows[r][i].tag != null && rowOverflows(rows[r]))
                  Flexible(
                    child: _chip(context, rows[r][i], tier, style, isDark),
                  )
                else
                  _chip(context, rows[r][i], tier, style, isDark),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    _Item item,
    GridTagTier tier,
    TextStyle style,
    bool isDark,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tag = item.tag;

    // The overflow count is not a tag: plain muted text, no pill.
    if (tag == null) {
      return SizedBox(
        height: tier.chipHeight,
        child: Center(
          widthFactor: 1,
          child: Text(
            '+${item.hidden}',
            style: style.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            softWrap: false,
          ),
        ),
      );
    }

    final tagColor = _dotColor(tag, isDark);
    return Container(
      height: tier.chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: _chipHPadding),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: isDark ? 0.20 : 0.13),
        borderRadius: BorderRadius.circular(tier.chipHeight / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _dotSize(tier),
            height: _dotSize(tier),
            decoration: BoxDecoration(color: tagColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: _dotGap),
          Flexible(
            child: Text(
              tag,
              style: style.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.85),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _Item {
  final String? tag;
  final int hidden;
  final double width;

  const _Item.tag(String this.tag, this.width) : hidden = 0;
  const _Item.more(this.hidden, this.width) : tag = null;
}
