import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';

enum FilePane { files, preview, properties }

enum FilePaneEdge { left, right, top, bottom }

/// A binary split tree. Hidden panes are pruned for display only, so toggling a
/// pane restores its position and size instead of changing the saved layout.
///
/// A split sizes one side in logical pixels ([extent]) and lets the side that
/// holds the file list absorb everything else. Resizing one divider therefore
/// never changes the width or height of a pane on another divider. [ratio]
/// only seeds a split that has no extent yet (a fresh dock, or an older save).
class FilePaneLayoutNode {
  const FilePaneLayoutNode.pane(this.pane)
    : axis = null,
      first = null,
      second = null,
      ratio = null,
      extent = null,
      id = null;

  const FilePaneLayoutNode.split(
    this.axis,
    this.first,
    this.second, {
    this.ratio,
    this.extent,
    this.id,
  }) : pane = null;

  final FilePane? pane;
  final Axis? axis;
  final FilePaneLayoutNode? first;
  final FilePaneLayoutNode? second;
  final double? ratio;
  final double? extent;
  final String? id;

  static const defaults = FilePaneLayoutNode.split(
    Axis.vertical,
    FilePaneLayoutNode.split(
      Axis.horizontal,
      FilePaneLayoutNode.pane(FilePane.files),
      FilePaneLayoutNode.pane(FilePane.preview),
    ),
    FilePaneLayoutNode.pane(FilePane.properties),
  );

  List<FilePane> get panes =>
      pane != null ? [pane!] : [...first!.panes, ...second!.panes];

  String get splitId => id ?? panes.map((p) => p.name).join('-');

  Size get minimumSize {
    if (pane != null) {
      return switch (pane!) {
        FilePane.files => const Size(160, 80),
        FilePane.preview => const Size(200, 220),
        FilePane.properties => const Size(200, 100),
      };
    }
    final a = first!.minimumSize;
    final b = second!.minimumSize;
    return axis == Axis.horizontal
        ? Size(a.width + b.width + 6, math.max(a.height, b.height))
        : Size(math.max(a.width, b.width), a.height + b.height + 6);
  }

  FilePaneLayoutNode? without(FilePane removed) {
    if (pane != null) return pane == removed ? null : this;
    final a = first!.without(removed);
    final b = second!.without(removed);
    if (a == null) return b;
    if (b == null) return a;
    return FilePaneLayoutNode.split(axis, a, b, ratio: ratio, extent: extent);
  }

  /// The side that keeps its pixel size while the window or a sibling divider
  /// changes: the one without the file list, else the second.
  bool get firstIsFixed =>
      !first!.panes.contains(FilePane.files) &&
      second!.panes.contains(FilePane.files);

  FilePaneLayoutNode? visible(Set<FilePane> shown) {
    if (pane != null) return shown.contains(pane) ? this : null;
    final a = first!.visible(shown);
    final b = second!.visible(shown);
    if (a == null) return b;
    if (b == null) return a;
    return FilePaneLayoutNode.split(
      axis,
      a,
      b,
      ratio: ratio,
      extent: extent,
      id: splitId,
    );
  }

  FilePaneLayoutNode dock(FilePane moving, FilePane target, FilePaneEdge edge) {
    if (moving == target) return this;
    final remaining = without(moving)!;
    FilePaneLayoutNode insert(FilePaneLayoutNode node) {
      if (node.pane == target) {
        final before = edge == FilePaneEdge.left || edge == FilePaneEdge.top;
        final moved = FilePaneLayoutNode.pane(moving);
        return FilePaneLayoutNode.split(
          edge == FilePaneEdge.left || edge == FilePaneEdge.right
              ? Axis.horizontal
              : Axis.vertical,
          before ? moved : node,
          before ? node : moved,
          ratio: .5,
        );
      }
      if (node.pane != null) return node;
      return FilePaneLayoutNode.split(
        node.axis,
        insert(node.first!),
        insert(node.second!),
        ratio: node.ratio,
        extent: node.extent,
      );
    }

    return insert(remaining);
  }

  /// Docks [moving] along a whole edge of the layout, so it spans the full
  /// width (top/bottom) or height (left/right) instead of sharing one pane's
  /// edge. Without an extent the split starts at 30% for an auxiliary pane, or
  /// 70% when the file list itself moves.
  FilePaneLayoutNode dockToEdge(FilePane moving, FilePaneEdge edge) {
    final remaining = without(moving)!;
    final before = edge == FilePaneEdge.left || edge == FilePaneEdge.top;
    final share = moving == FilePane.files ? .7 : .3;
    final moved = FilePaneLayoutNode.pane(moving);
    return FilePaneLayoutNode.split(
      edge == FilePaneEdge.left || edge == FilePaneEdge.right
          ? Axis.horizontal
          : Axis.vertical,
      before ? moved : remaining,
      before ? remaining : moved,
      ratio: before ? share : 1 - share,
    );
  }

  /// Sets the pixel size of the fixed side of split [id].
  FilePaneLayoutNode resize(String id, double value) {
    if (pane != null) return this;
    final target = splitId == id;
    return FilePaneLayoutNode.split(
      axis,
      first!.resize(id, value),
      second!.resize(id, value),
      ratio: target ? null : ratio,
      extent: target ? math.max(1.0, value) : extent,
    );
  }

  Map<String, Object?> toJson() => pane != null
      ? {'pane': pane!.name}
      : {
          'axis': axis!.name,
          'first': first!.toJson(),
          'second': second!.toJson(),
          'ratio': ratio,
          if (extent != null) 'extent': extent,
        };

  String encode() => jsonEncode(toJson());

  static FilePaneLayoutNode decode(String source) {
    try {
      FilePaneLayoutNode parse(dynamic data, int depth) {
        if (data is! Map || depth > 2) throw const FormatException();
        if (data['pane'] != null) {
          return FilePaneLayoutNode.pane(
            FilePane.values.byName(data['pane'] as String),
          );
        }
        final raw = data['ratio'];
        final ratio = raw == null ? null : (raw as num).toDouble();
        if (ratio != null && (!ratio.isFinite || ratio <= 0 || ratio >= 1)) {
          throw const FormatException();
        }
        final rawExtent = data['extent'];
        final extent = rawExtent == null ? null : (rawExtent as num).toDouble();
        if (extent != null && (!extent.isFinite || extent <= 0)) {
          throw const FormatException();
        }
        return FilePaneLayoutNode.split(
          Axis.values.byName(data['axis'] as String),
          parse(data['first'], depth + 1),
          parse(data['second'], depth + 1),
          ratio: ratio,
          extent: extent,
        );
      }

      final result = parse(jsonDecode(source), 0);
      if (result.panes.length != 3 || result.panes.toSet().length != 3) {
        return defaults;
      }
      return result;
    } catch (_) {
      return defaults;
    }
  }
}
