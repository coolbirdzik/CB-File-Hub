import 'package:flutter/widgets.dart';

import '../../../helpers/core/text_utils.dart';

/// The groups a command palette result can belong to, in display order.
enum CommandPaletteSection {
  goTo,
  tabs,
  currentFolder,
  pinned,
  recent,
  places,
  commands,
}

/// One row in the command palette.
@immutable
class CommandPaletteItem {
  /// Stable identity — used for keys and to de-duplicate sources.
  final String id;
  final String title;

  /// Secondary text shown after the title (a path, a hint).
  final String? subtitle;
  final IconData icon;
  final CommandPaletteSection section;

  /// Extra words the query may match that are not displayed.
  final List<String> keywords;

  /// Key caps shown at the end of the row, e.g. `['Ctrl', 'T']`.
  final List<String> shortcut;

  /// Short label shown at the end of the row when there is no [shortcut].
  final String? accessory;

  /// Runs the item. Called after the palette has closed.
  final VoidCallback onRun;

  /// Hidden until the user types something — for large, low-priority sets
  /// such as the entries of the current folder.
  final bool onlyWhenSearching;

  const CommandPaletteItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.section,
    required this.onRun,
    this.subtitle,
    this.keywords = const <String>[],
    this.shortcut = const <String>[],
    this.accessory,
    this.onlyWhenSearching = false,
  });
}

/// Most rows a single section may contribute while searching, so a folder
/// with thousands of matching files cannot bury tabs and commands.
const int kCommandPaletteSectionLimit = 30;

/// Filters [items] by [query] and orders them for display.
///
/// Sections keep their [CommandPaletteSection] order — Raycast-style
/// grouping stays stable while typing — and items inside a section are ranked
/// by how well the title matches: prefix, then word start, then anywhere,
/// then a match only in the subtitle or keywords. Ties keep source order.
/// Matching is accent- and case-insensitive ([TextUtils.searchKey]), so
/// "cai dat" finds "Cài đặt".
List<CommandPaletteItem> rankCommandPaletteItems(
  Iterable<CommandPaletteItem> items,
  String query,
) {
  final seen = <String>{};
  final unique = <CommandPaletteItem>[
    for (final item in items)
      if (seen.add(item.id)) item,
  ];
  final String key = TextUtils.searchKey(query).trim();
  if (key.isEmpty) {
    return unique.where((item) => !item.onlyWhenSearching).toList()
      ..sort((a, b) => a.section.index.compareTo(b.section.index));
  }

  final scored = <(CommandPaletteItem, int, int)>[];
  for (var i = 0; i < unique.length; i++) {
    final item = unique[i];
    final haystack = [
      item.title,
      if (item.subtitle != null) item.subtitle!,
      ...item.keywords,
    ].join(' ');
    if (!TextUtils.matchesSearch(haystack, query)) continue;
    scored.add((item, _titleScore(item.title, key), i));
  }
  scored.sort((a, b) {
    final bySection = a.$1.section.index.compareTo(b.$1.section.index);
    if (bySection != 0) return bySection;
    final byScore = a.$2.compareTo(b.$2);
    if (byScore != 0) return byScore;
    return a.$3.compareTo(b.$3);
  });
  final perSection = <CommandPaletteSection, int>{};
  final ranked = <CommandPaletteItem>[];
  for (final (item, _, _) in scored) {
    final shown = perSection.update(
      item.section,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    if (shown <= kCommandPaletteSectionLimit) ranked.add(item);
  }
  return ranked;
}

int _titleScore(String title, String queryKey) {
  final String t = TextUtils.searchKey(title);
  if (t.startsWith(queryKey)) return 0;
  if (t.contains(' $queryKey')) return 1;
  if (t.contains(queryKey)) return 2;
  return 3;
}
