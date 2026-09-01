import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/tree_view/tree_view.dart';

/// Tree view for the local file browser.
///
/// Roots are the current directory's `state.entries` (folders + files).
/// Children are loaded lazily the first time a folder expands, by calling
/// `Directory.list()` on the folder's path. Results are cached on the
/// node so subsequent expand/collapse cycles are instantaneous; refresh
/// the whole tree by switching directories or pressing the toolbar
/// refresh button.
class FileTreeView extends StatefulWidget {
  final FolderListState state;
  final SelectionState selectionState;
  final bool isDesktopPlatform;
  final void Function(String path) onNavigateToPath;
  final void Function(File file, bool b) onFileTap;
  final void Function(String path, {bool shiftSelect, bool ctrlSelect})
      toggleFileSelection;
  final void Function(String path, {bool shiftSelect, bool ctrlSelect})
      toggleFolderSelection;
  final VoidCallback clearSelection;
  final void Function(BuildContext context, Offset position) showContextMenu;

  const FileTreeView({
    Key? key,
    required this.state,
    required this.selectionState,
    required this.isDesktopPlatform,
    required this.onNavigateToPath,
    required this.onFileTap,
    required this.toggleFileSelection,
    required this.toggleFolderSelection,
    required this.clearSelection,
    required this.showContextMenu,
  }) : super(key: key);

  @override
  State<FileTreeView> createState() => _FileTreeViewState();
}

class _FileTreeViewState extends State<FileTreeView> {
  /// Tree built from the current directory's contents. Recreated when
  /// the directory or the (folders, files) lists change.
  List<TreeNode<FileSystemEntity>> _roots = const [];
  String? _rootSignature;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeRebuildRoots();
  }

  @override
  void didUpdateWidget(covariant FileTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeRebuildRoots(
      force: oldWidget.state.isRefreshing && !widget.state.isRefreshing,
    );
  }

  /// Rebuild the root nodes only when the underlying directory listing
  /// changes. We can't compare Lists directly (they're new instances on
  /// every state copy), so we use a cheap signature: path + count + last
  /// path for folders and files.
  void _maybeRebuildRoots({bool force = false}) {
    final folders = widget.state.folders;
    final files = widget.state.files;
    final sig = '${widget.state.currentPath.path}'
        '|f${folders.length}:${folders.isEmpty ? "" : folders.last.path}'
        '|x${files.length}:${files.isEmpty ? "" : files.last.path}';
    if (!force && sig == _rootSignature && _roots.isNotEmpty) return;

    _rootSignature = sig;
    _roots = [
      ...folders.map((d) => TreeNode<FileSystemEntity>(
            id: d.path,
            data: d,
            isLeaf: false,
          )),
      ...files.map((f) => TreeNode<FileSystemEntity>(
            id: f.path,
            data: f,
            isLeaf: true,
          )),
    ];
  }

  Future<List<TreeNode<FileSystemEntity>>> _loadChildren(
      TreeNode<FileSystemEntity> node) async {
    final entity = node.data;
    if (entity is! Directory) return const [];
    return _scanDirectory(entity.path);
  }

  void _onTap(TreeNode<FileSystemEntity> node) {
    final entity = node.data;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    if (entity is Directory) {
      widget.toggleFolderSelection(entity.path,
          shiftSelect: isShift, ctrlSelect: isCtrl);
    } else if (entity is File) {
      widget.toggleFileSelection(entity.path,
          shiftSelect: isShift, ctrlSelect: isCtrl);
    }
  }

  void _onDoubleTap(TreeNode<FileSystemEntity> node) {
    final entity = node.data;
    if (entity is Directory) {
      widget.onNavigateToPath(entity.path);
    } else if (entity is File) {
      widget.onFileTap(entity, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selectionState.allSelectedPaths.toSet();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (widget.selectionState.isSelectionMode) widget.clearSelection();
      },
      onSecondaryTapUp: (details) =>
          widget.showContextMenu(context, details.globalPosition),
      onLongPressStart: !widget.isDesktopPlatform
          ? (details) {
              HapticFeedback.mediumImpact();
              widget.showContextMenu(context, details.globalPosition);
            }
          : null,
      child: GenericTreeView<FileSystemEntity>(
        roots: _roots,
        itemExtent: 30,
        selectedIds: selected,
        focusedId: widget.selectionState.lastSelectedPath,
        childrenLoader: _loadChildren,
        onTap: _onTap,
        onDoubleTap: _onDoubleTap,
        onSecondary: (node, pos) => widget.showContextMenu(context, pos),
        emptyState: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('Empty folder'),
          ),
        ),
        itemBuilder: (context, node, depth) {
          final entity = node.data;
          final isDir = entity is Directory;
          final segments = entity.path
              .split(Platform.pathSeparator)
              .where((s) => s.isNotEmpty)
              .toList();
          final name = segments.isEmpty ? entity.path : segments.last;
          final theme = Theme.of(context);
          return Row(
            children: [
              Icon(
                isDir ? PhosphorIconsLight.folder : PhosphorIconsLight.file,
                size: 14,
                color: isDir
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Lists [path] off the main isolate and produces a sorted list of
/// `TreeNode<FileSystemEntity>` (folders first, then files; alphabetical
/// within each group). Hidden config files are skipped to match the
/// existing browser behaviour.
Future<List<TreeNode<FileSystemEntity>>> _scanDirectory(String path) async {
  return compute(_scanDirectoryRaw, path);
}

List<TreeNode<FileSystemEntity>> _scanDirectoryRaw(String path) {
  final dir = Directory(path);
  final folders = <Directory>[];
  final files = <File>[];
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      final p = entity.path;
      final name = p.contains(Platform.pathSeparator)
          ? p.substring(p.lastIndexOf(Platform.pathSeparator) + 1)
          : p;
      if (entity is Directory) {
        folders.add(entity);
      } else if (entity is File) {
        if (p.endsWith('.tags') || name == '.cbfile_config.json') continue;
        files.add(entity);
      }
    }
  } catch (_) {
    // Permission denied / IO errors surface as an empty children list;
    // GenericTreeView shows the (loaded but empty) state.
  }

  int byName(FileSystemEntity a, FileSystemEntity b) {
    final an = a.path.split(Platform.pathSeparator).last.toLowerCase();
    final bn = b.path.split(Platform.pathSeparator).last.toLowerCase();
    return an.compareTo(bn);
  }

  folders.sort(byName);
  files.sort(byName);

  return [
    ...folders.map((d) => TreeNode<FileSystemEntity>(
          id: d.path,
          data: d,
          isLeaf: false,
        )),
    ...files.map((f) => TreeNode<FileSystemEntity>(
          id: f.path,
          data: f,
          isLeaf: true,
        )),
  ];
}
