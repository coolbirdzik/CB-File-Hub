import 'package:flutter/widgets.dart';

/// Owns the overlay and pending work for a single tab drag.
class TabDragOverlayController {
  OverlayEntry? _entry;
  int _generation = 0;
  bool _disposed = false;

  Future<void> show<T>({
    required OverlayState overlay,
    required Future<T> Function() load,
    required Widget Function(BuildContext context, T data) builder,
  }) async {
    if (_disposed) return;
    remove();
    final generation = _generation;
    final data = await load();
    if (_disposed || generation != _generation || !overlay.mounted) return;

    final entry = OverlayEntry(builder: (context) => builder(context, data));
    _entry = entry;
    overlay.insert(entry);
  }

  void remove() {
    // Ending a drag also invalidates work that has not produced an entry yet.
    _generation++;
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void dispose() {
    _disposed = true;
    remove();
  }
}
