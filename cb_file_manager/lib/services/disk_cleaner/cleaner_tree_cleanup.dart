import 'disk_tree_node.dart';
import 'cleaner_paths.dart';

/// Updates the displayed scan after deletion without blocking one frame with
/// several full-tree walks. Keeps node identities and unrepresented scan bytes.
Future<({int junkBytes, int cleanableCount})> pruneCleanedDiskTree(
  DiskTreeNode root,
  Set<String> deletedPaths, {
  Duration workSlice = const Duration(milliseconds: 4),
}) async {
  final deleted = deletedPaths.map(CleanerPaths.key).toSet();
  final budget = Stopwatch()..start();
  Future<void> yieldIfNeeded() async {
    if (budget.elapsed < workSlice) return;
    await Future<void>.delayed(Duration.zero);
    budget.reset();
  }

  Future<({int bytes, int files, int junk, bool hasJunk, int cleanable})> walk(
    DiskTreeNode node,
  ) async {
    if (budget.elapsed >= workSlice) await yieldIfNeeded();
    var removedBytes = 0;
    var removedFiles = 0;
    var childJunkBytes = 0;
    var hasJunkChildren = false;
    var cleanableCount = node.isJunk && node.fullPath.isNotEmpty ? 1 : 0;
    final children = node.children;
    if (children.isNotEmpty) {
      final survivors = <DiskTreeNode>[];
      for (final child in children) {
        if (budget.elapsed >= workSlice) await yieldIfNeeded();
        if (deleted.contains(CleanerPaths.key(child.fullPath))) {
          removedBytes += child.sizeBytes;
          removedFiles += child.fileCount;
          continue;
        }
        final result = await walk(child);
        removedBytes += result.bytes;
        removedFiles += result.files;
        childJunkBytes += result.junk;
        hasJunkChildren |= child.isJunk || result.hasJunk;
        cleanableCount += result.cleanable;
        survivors.add(child);
      }
      if (survivors.length != children.length) node.replaceChildren(survivors);
    }
    node.sizeBytes = (node.sizeBytes - removedBytes).clamp(0, node.sizeBytes);
    node.fileCount = (node.fileCount - removedFiles).clamp(0, node.fileCount);
    node.isSelectedForDeletion = false;
    node.invalidateSelectionCache(recursive: false);
    final junkBytes = node.isJunk ? node.sizeBytes : childJunkBytes;
    node.cacheJunkMetadata(
      junkBytes: junkBytes,
      hasJunkChildren: hasJunkChildren,
    );
    return (
      bytes: removedBytes,
      files: removedFiles,
      junk: junkBytes,
      hasJunk: hasJunkChildren,
      cleanable: cleanableCount,
    );
  }

  final result = await walk(root);
  return (junkBytes: result.junk, cleanableCount: result.cleanable);
}
