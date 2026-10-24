import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Tabs of another window hovering over this window's tab strip, at
/// [position] in this window's logical coordinates.
@immutable
class ExternalTabDropHover {
  final Offset position;
  final String label;

  const ExternalTabDropHover({required this.position, required this.label});

  @override
  bool operator ==(Object other) =>
      other is ExternalTabDropHover &&
      other.position == position &&
      other.label == label;

  @override
  int get hashCode => Object.hash(position, label);
}

/// Joins the cross-window tab merge protocol to the tab bar that owns the
/// strip: the bar reports where the strip is and maps drop positions to tab
/// indices, the platform side reports windows hovering over it.
class ExternalTabDropController {
  ExternalTabDropController({this.onStripBoundsChanged});

  /// Receives the strip bounds in logical view coordinates, null when no tab
  /// bar is showing. Called only when the bounds change.
  final ValueChanged<Rect?>? onStripBoundsChanged;

  final ValueNotifier<ExternalTabDropHover?> hover =
      ValueNotifier<ExternalTabDropHover?>(null);

  int Function(Offset position)? _insertIndexAt;
  Rect? _stripBounds;

  Rect? get stripBounds => _stripBounds;

  void attach(int Function(Offset position) insertIndexAt) {
    _insertIndexAt = insertIndexAt;
  }

  void detach(int Function(Offset position) insertIndexAt) {
    if (_insertIndexAt != insertIndexAt) return;
    _insertIndexAt = null;
    hover.value = null;
    reportStripBounds(null);
  }

  void reportStripBounds(Rect? bounds) {
    if (bounds == _stripBounds) return;
    _stripBounds = bounds;
    onStripBoundsChanged?.call(bounds);
  }

  /// The index a drop at [position] inserts at, or null (append) when no tab
  /// bar is attached.
  int? insertIndexAt(Offset position) => _insertIndexAt?.call(position);
}
