import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../services/disk_cleaner/cleaner_models.dart';

/// A TreeSize-style hierarchical view of junk files.
///
/// Builds a tree from flat [JunkItem] paths, groups by directory segments,
/// and renders each node with: name, size, % of parent bar, file count.
/// Nodes are expandable/collapsible, sorted by size descending.
class JunkTreeView extends StatefulWidget {
  final List<JunkItem> items;
  final String categoryName;
  final int categoryTotalBytes;

  const JunkTreeView({
    Key? key,
    required this.items,
    required this.categoryName,
    required this.categoryTotalBytes,
  }) : super(key: key);

  @override
  State<JunkTreeView> createState() => _JunkTreeViewState();
}

class _JunkTreeViewState extends State<JunkTreeView> {
  late _TreeNode _root;

  @override
  void initState() {
    super.initState();
    _root = _buildTree(widget.items, widget.categoryName);
  }

  @override
  void didUpdateWidget(JunkTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _root = _buildTree(widget.items, widget.categoryName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 400),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        children: [
          // Render children of root (root itself is the category)
          ..._root.children.map(
            (child) => _TreeNodeTile(
              node: child,
              depth: 0,
              parentSize: _root.totalBytes,
              theme: theme,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tree data model
// ---------------------------------------------------------------------------

class _TreeNode {
  final String name;
  final String fullPath;
  final bool isFile;
  int totalBytes;
  int fileCount;
  final List<_TreeNode> children;

  _TreeNode({
    required this.name,
    required this.fullPath,
    this.isFile = false,
    this.totalBytes = 0,
    this.fileCount = 0,
    List<_TreeNode>? children,
  }) : children = children ?? [];

  double percentOfParent(int parentBytes) =>
      parentBytes > 0 ? totalBytes / parentBytes : 0.0;
}

/// Builds a tree from flat file paths.
_TreeNode _buildTree(List<JunkItem> items, String rootName) {
  final root = _TreeNode(name: rootName, fullPath: '');

  for (final item in items) {
    final segments = _splitPath(item.path);
    var current = root;

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;
      final partialPath = segments.sublist(0, i + 1).join('\\');

      if (isLast) {
        // Leaf file node
        current.children.add(_TreeNode(
          name: segment,
          fullPath: item.path,
          isFile: true,
          totalBytes: item.sizeBytes,
          fileCount: 1,
        ));
      } else {
        // Find or create directory node
        var found = false;
        for (final child in current.children) {
          if (!child.isFile && child.name == segment) {
            current = child;
            found = true;
            break;
          }
        }
        if (!found) {
          final newNode = _TreeNode(
            name: segment,
            fullPath: partialPath,
          );
          current.children.add(newNode);
          current = newNode;
        }
      }
    }
  }

  // Propagate sizes up and sort children by size descending
  _propagateSizes(root);
  _sortBySize(root);

  // Collapse single-child directory chains (e.g. A/B/C → A\B\C)
  _collapseSingleChildDirs(root);

  return root;
}

void _propagateSizes(_TreeNode node) {
  if (node.isFile) return;

  int totalBytes = 0;
  int fileCount = 0;

  for (final child in node.children) {
    _propagateSizes(child);
    totalBytes += child.totalBytes;
    fileCount += child.fileCount;
  }

  node.totalBytes = totalBytes;
  node.fileCount = fileCount;
}

void _sortBySize(_TreeNode node) {
  if (node.children.isEmpty) return;
  node.children.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));
  for (final child in node.children) {
    _sortBySize(child);
  }
}

/// Collapses chains like `Users` → `ngtan` → `AppData` into a single node
/// named `Users\ngtan\AppData` when each intermediate has exactly one child
/// directory.
void _collapseSingleChildDirs(_TreeNode node) {
  for (int i = 0; i < node.children.length; i++) {
    var child = node.children[i];
    if (child.isFile) continue;

    // Collapse chain
    while (child.children.length == 1 && !child.children.first.isFile) {
      final grandchild = child.children.first;
      child = _TreeNode(
        name: '${child.name}\\${grandchild.name}',
        fullPath: grandchild.fullPath,
        totalBytes: grandchild.totalBytes,
        fileCount: grandchild.fileCount,
        children: grandchild.children,
      );
    }
    node.children[i] = child;

    // Recurse into the (possibly collapsed) child
    _collapseSingleChildDirs(child);
  }
}

List<String> _splitPath(String path) {
  // Normalize and split: C:\Users\foo\bar.txt → [C:, Users, foo, bar.txt]
  return path
      .replaceAll('/', '\\')
      .split('\\')
      .where((s) => s.isNotEmpty)
      .toList();
}

// ---------------------------------------------------------------------------
// Tree node tile widget (recursive)
// ---------------------------------------------------------------------------

class _TreeNodeTile extends StatefulWidget {
  final _TreeNode node;
  final int depth;
  final int parentSize;
  final ThemeData theme;

  const _TreeNodeTile({
    required this.node,
    required this.depth,
    required this.parentSize,
    required this.theme,
  });

  @override
  State<_TreeNodeTile> createState() => _TreeNodeTileState();
}

class _TreeNodeTileState extends State<_TreeNodeTile> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand first level
    _expanded = widget.depth == 0 && !widget.node.isFile;
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final theme = widget.theme;
    final indent = 20.0 * widget.depth;
    final percent = node.percentOfParent(widget.parentSize);
    final hasChildren = !node.isFile && node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Node row
        InkWell(
          onTap: hasChildren
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Padding(
            padding: EdgeInsets.only(
                left: 12 + indent, right: 12, top: 4, bottom: 4),
            child: Row(
              children: [
                // Expand/collapse arrow or spacer
                SizedBox(
                  width: 20,
                  child: hasChildren
                      ? AnimatedRotation(
                          duration: const Duration(milliseconds: 150),
                          turns: _expanded ? 0.25 : 0.0,
                          child: Icon(
                            PhosphorIconsLight.caretRight,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                // Icon
                Icon(
                  node.isFile
                      ? PhosphorIconsLight.file
                      : PhosphorIconsLight.folder,
                  size: 16,
                  color: node.isFile
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                // Name
                Expanded(
                  flex: 3,
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          node.isFile ? FontWeight.normal : FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Size
                SizedBox(
                  width: 70,
                  child: Text(
                    _formatSize(node.totalBytes),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 10),
                // % of parent bar
                SizedBox(
                  width: 80,
                  child: _PercentBar(
                    percent: percent,
                    color: _barColor(percent, theme),
                  ),
                ),
                const SizedBox(width: 8),
                // % text
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(percent * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                // File count (directories only)
                if (!node.isFile) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${node.fileCount} files',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Children (when expanded)
        if (_expanded && hasChildren)
          ...node.children.map(
            (child) => _TreeNodeTile(
              node: child,
              depth: widget.depth + 1,
              parentSize: node.totalBytes,
              theme: theme,
            ),
          ),
      ],
    );
  }

  Color _barColor(double percent, ThemeData theme) {
    if (percent > 0.5) return Colors.green.shade600;
    if (percent > 0.25) return Colors.green.shade400;
    if (percent > 0.1) return Colors.lightGreen;
    return Colors.grey.shade400;
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ---------------------------------------------------------------------------
// Percent bar (like TreeSize's green bar)
// ---------------------------------------------------------------------------

class _PercentBar extends StatelessWidget {
  final double percent;
  final Color color;

  const _PercentBar({required this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 14,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: percent.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: color,
          ),
        ),
      ),
    );
  }
}
