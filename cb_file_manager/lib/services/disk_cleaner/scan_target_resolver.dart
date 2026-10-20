import 'dart:math' as math;

import 'disk_tree_node.dart';

/// The scan row an agent tool call names, found even when the model copied
/// the path slightly wrong.
class ScanTargetMatch {
  const ScanTargetMatch({
    this.node,
    this.correctedFrom,
    this.suggestions = const [],
  });

  final DiskTreeNode? node;

  /// The path as the caller wrote it, when [node] was found by correcting it.
  final String? correctedFrom;

  /// Closest real paths when nothing could be resolved.
  final List<String> suggestions;
}

/// Upper-cased, `\`-separated, without trailing separators: the key both
/// exact matching and correction compare.
String scanPathKey(String path) => path
    .trim()
    .replaceAll('/', r'\')
    .toUpperCase()
    .replaceFirst(RegExp(r'\\+$'), '');

/// Edits within which one unique sibling counts as the intended name. Small
/// models routinely drop or repeat a character of long hex names.
const _maxCorrection = 2;

/// Names shorter than this are never corrected: `log1` vs `log2` is a
/// different file, not a typo.
const _minCorrectableLength = 6;

/// Walks [root] one path segment at a time. A segment that matches no child
/// exactly is replaced by the only child whose name is within
/// [_maxCorrection] edits of it; otherwise the closest children come back as
/// [ScanTargetMatch.suggestions] and nothing is resolved.
///
/// Never resolves to [root] itself or to a folded aggregate row.
ScanTargetMatch resolveScanTarget(DiskTreeNode root, String path) {
  final rootKey = scanPathKey(root.fullPath);
  final target = scanPathKey(path);
  if (target.isEmpty || !target.startsWith('$rootKey\\')) {
    return const ScanTargetMatch();
  }
  final segments = target
      .substring(rootKey.length + 1)
      .split(r'\')
      .where((segment) => segment.isNotEmpty)
      .toList();
  if (segments.isEmpty) return const ScanTargetMatch();

  var current = root;
  var corrected = false;
  for (final segment in segments) {
    final children = [
      for (final child in current.children)
        if (child.fullPath.isNotEmpty && !child.isAggregate) child,
    ];
    DiskTreeNode? next;
    for (final child in children) {
      if (child.name.toUpperCase() == segment) {
        next = child;
        break;
      }
    }
    if (next == null) {
      final ranked = [
        for (final child in children)
          (child, editDistance(child.name.toUpperCase(), segment)),
      ]..sort((a, b) => a.$2.compareTo(b.$2));
      final best = ranked.isEmpty ? null : ranked.first;
      final unique = ranked.length < 2 || ranked[1].$2 > best!.$2;
      if (best != null &&
          segment.length >= _minCorrectableLength &&
          best.$2 <= _maxCorrection &&
          unique) {
        next = best.$1;
        corrected = true;
      } else {
        final close = math.max(3, segment.length ~/ 3);
        return ScanTargetMatch(
          suggestions: [
            for (final (child, distance) in ranked.take(5))
              if (distance <= close) child.fullPath,
          ],
        );
      }
    }
    current = next;
  }
  return ScanTargetMatch(node: current, correctedFrom: corrected ? path : null);
}

/// Levenshtein distance.
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var row = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    row[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= b.length; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      row[j] = math.min(
        math.min(row[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + cost,
      );
    }
    final swap = previous;
    previous = row;
    row = swap;
  }
  return previous[b.length];
}
