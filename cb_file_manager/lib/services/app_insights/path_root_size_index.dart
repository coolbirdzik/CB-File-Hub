/// Prefix index over already-normalized Windows paths. Each node caches the
/// sum of its nearest owned roots, so nested roots never subtract bytes twice.
/// Build cost is proportional to total path length; queries walk one path.
class PathRootSizeIndex {
  PathRootSizeIndex(Iterable<(String, int)> roots) {
    for (final (path, size) in roots) {
      var node = _root;
      final ancestors = <_SizeNode>[];
      for (final part in _parts(path)) {
        ancestors.add(node);
        node = node.children.putIfAbsent(part, _SizeNode.new);
      }
      final oldCovered = node.coveredSize;
      node.ownSize = (node.ownSize ?? 0) + size;
      var delta = node.coveredSize - oldCovered;
      for (final ancestor in ancestors.reversed) {
        final old = ancestor.coveredSize;
        ancestor.childrenCoveredSize += delta;
        delta = ancestor.coveredSize - old;
      }
    }
  }

  final _root = _SizeNode();

  static Iterable<String> _parts(String path) sync* {
    // Keep UNC separate from a relative path with the same components.
    if (path.startsWith(r'\\')) yield r'\\';
    yield* path.split(r'\').where((part) => part.isNotEmpty);
  }

  int coveredBytes(String path, {bool descendantsOnly = false}) {
    var node = _root;
    for (final part in _parts(path)) {
      final next = node.children[part];
      if (next == null) return 0;
      node = next;
    }
    return descendantsOnly ? node.childrenCoveredSize : node.coveredSize;
  }

  bool hasAncestor(String path) {
    var node = _root;
    for (final part in _parts(path)) {
      final next = node.children[part];
      if (next == null) return false;
      node = next;
      if (node.ownSize != null) return true;
    }
    return false;
  }
}

class _SizeNode {
  final children = <String, _SizeNode>{};
  int? ownSize;
  int childrenCoveredSize = 0;
  int get coveredSize => ownSize ?? childrenCoveredSize;
}
