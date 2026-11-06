/// Tracks visible tiles by owner, so duplicate paths in different views do not
/// cancel each other. Neighbours follow the current display order.
class ThumbnailViewportPolicy {
  ThumbnailViewportPolicy({this.nearbyCount = 4});

  final int nearbyCount;
  final Map<Object, String> _visible = {};
  List<String> _paths = const [];
  Map<String, int> _indices = const {};

  void updateDisplayPaths(List<String> paths) {
    _paths = List.of(paths);
    _indices = {for (var i = 0; i < paths.length; i++) paths[i]: i};
  }

  void setVisible(Object owner, String? path) {
    if (path == null) {
      _visible.remove(owner);
    } else {
      _visible[owner] = path;
    }
  }

  bool containsOwner(Object owner, String path) => _visible[owner] == path;

  Set<String> get visiblePaths => _visible.values.toSet();

  Set<String> get wantedPaths {
    final wanted = visiblePaths;
    for (final path in visiblePaths) {
      final index = _indices[path];
      if (index == null) continue;
      final start = (index - nearbyCount).clamp(0, _paths.length);
      final end = (index + nearbyCount + 1).clamp(0, _paths.length);
      wanted.addAll(_paths.getRange(start, end));
    }
    return wanted;
  }
}
