import 'package:flutter/foundation.dart';

import '../../../helpers/core/user_preferences.dart';
import '../../utils/grid_zoom_constraints.dart';
import '../../utils/view_mode_spectrum.dart';
import 'grid_list_collection.dart';

/// Shared view/zoom spectrum for virtual collections and transfer panes.
/// The caller owns [view] and listens to it for direct mode changes.
class CollectionViewScaleController extends ChangeNotifier {
  CollectionViewScaleController({
    required this.view,
    this.loadZoom,
    this.saveZoom,
  });
  final GridListViewController view;
  final Future<int> Function()? loadZoom;
  final Future<void> Function(int)? saveZoom;
  int _zoom = UserPreferences.defaultGridZoomLevel;
  int get zoom => _zoom;
  bool _changed = false, _disposed = false;
  Future<void>? _initializing;
  Future<void> _writes = Future.value();

  Future<void> initialize() => _initializing ??= Future.wait([
    view.initialize(),
    _restoreZoom(),
  ]).then((_) {});

  Future<void> _restoreZoom() async {
    final restored = await loadZoom?.call();
    if (_disposed || _changed || restored == null) return;
    _zoom = restored.clamp(
      UserPreferences.minGridZoomLevel,
      UserPreferences.maxGridZoomLevel,
    );
    notifyListeners();
  }

  Future<void> setZoom(int zoom) {
    view.cancelPendingRestore();
    _changed = true;
    _zoom = zoom.clamp(
      UserPreferences.minGridZoomLevel,
      UserPreferences.maxGridZoomLevel,
    );
    notifyListeners();
    final selected = _zoom;
    _writes = _writes.then(
      (_) => saveZoom?.call(selected),
      onError: (Object _, StackTrace _) => saveZoom?.call(selected),
    );
    return _writes;
  }

  Future<void> step(int delta, double width) async {
    view.cancelPendingRestore();
    final result = ViewModeSpectrum.step(
      currentMode: view.mode,
      currentZoom: zoom,
      supported: view.supportedModes,
      delta: delta,
      maxZoom: GridZoomConstraints.maxGridSize(availableWidth: width),
    );
    final writes = <Future<void>>[];
    if (result.gridZoomLevel != zoom) writes.add(setZoom(result.gridZoomLevel));
    if (result.mode != view.mode) writes.add(view.select(result.mode));
    await Future.wait(writes);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
