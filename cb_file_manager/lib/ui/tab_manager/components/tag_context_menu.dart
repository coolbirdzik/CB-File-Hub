import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/design_system/primitives/cb_inline_rename.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/components/common/shared_file_context_menu.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/dialogs/thumbnail_browser_dialog.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

/// Shared context menu for a tag, used both by the tag management screen and by
/// tags shown as folder-like cards in the search results grid/list.
///
/// A tag is not a folder — it only *renders* like one. This menu therefore
/// exposes tag-specific actions (view files, rename, change color, set
/// thumbnail, manage hierarchy, delete from all files) rather than filesystem
/// folder actions.
///
/// All actions operate on the tag singletons ([TagManager],
/// [TagColorManager], [TagThumbnailManager], [TagHierarchyManager]), so the
/// menu is self-contained and does not depend on the tag screen's State.
///
/// [onChanged] is invoked after any mutation (rename, color, thumbnail,
/// hierarchy, delete) so the caller can refresh its own view.
Future<void> showTagContextMenu(
  BuildContext context,
  String tag, {
  Offset? globalPosition,
  VoidCallback? onChanged,
  bool showOpenActions = true,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final sections = _buildTagContextMenuSections(
    context,
    tag,
    l10n,
    onChanged: onChanged,
    showOpenActions: showOpenActions,
  );

  final isMobile = Platform.isAndroid || Platform.isIOS;
  if (isMobile || globalPosition == null) {
    await showContextMenuSheet(
      context: context,
      title: tag,
      icon: PhosphorIconsLight.tag,
      sections: sections,
    );
    return;
  }

  await showContextMenuPopup(
    context: context,
    sections: sections,
    globalPosition: globalPosition,
  );
}

List<ContextMenuSection> _buildTagContextMenuSections(
  BuildContext context,
  String tag,
  AppLocalizations l10n, {
  VoidCallback? onChanged,
  bool showOpenActions = true,
}) {
  return [
    if (showOpenActions)
      ContextMenuSection(
        actions: [
          ContextMenuAction(
            id: 'view_files',
            label: l10n.viewFilesWithTag,
            icon: PhosphorIconsLight.folder,
            onSelected: (_) => openTagSearchTab(context, tag),
          ),
        ],
      ),
    ContextMenuSection(
      actions: [
        ContextMenuAction(
          id: 'rename',
          label: l10n.renameTag,
          icon: PhosphorIconsLight.pencilSimple,
          onSelected: (ctx) => showRenameTagDialog(
            ctx,
            tag,
            onChanged: onChanged,
            anchorRect: cbAnchorRectOf(ctx),
          ),
        ),
        ContextMenuAction(
          id: 'color',
          label: l10n.changeTagColor,
          icon: PhosphorIconsLight.palette,
          onSelected: (ctx) =>
              showTagColorPickerDialog(ctx, tag, onChanged: onChanged),
        ),
        ContextMenuAction(
          id: 'thumbnail',
          label: l10n.setThumbnail,
          icon: PhosphorIconsLight.image,
          onSelected: (ctx) =>
              showTagThumbnailPicker(ctx, tag, onChanged: onChanged),
        ),
        ContextMenuAction(
          id: 'hierarchy',
          label: l10n.manageHierarchy,
          icon: PhosphorIconsLight.treeStructure,
          onSelected: (ctx) =>
              showManageTagHierarchyDialog(ctx, tag, onChanged: onChanged),
        ),
      ],
    ),
    ContextMenuSection(
      actions: [
        ContextMenuAction(
          id: 'delete',
          label: l10n.deleteTagFromAllFiles,
          icon: PhosphorIconsLight.trash,
          isDestructive: true,
          onSelected: (ctx) =>
              confirmDeleteTagFromAllFiles(ctx, tag, onChanged: onChanged),
        ),
      ],
    ),
  ];
}

/// Opens (or switches to) a tab showing all files with [tag].
void openTagSearchTab(BuildContext context, String tag) {
  try {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final tagSearchPath = UriUtils.buildTagSearchPath(tag);

    final existingTab = tabBloc.state.tabs.firstWhere(
      (t) => t.path == tagSearchPath,
      orElse: () => TabData(id: '', name: '', path: ''),
    );

    if (existingTab.id.isNotEmpty) {
      tabBloc.add(SwitchToTab(existingTab.id));
    } else {
      tabBloc.add(
        AddTab(path: tagSearchPath, name: 'Tag: $tag', switchToTab: true),
      );
    }
  } catch (e) {
    AppLogger.warning('Error opening tag in new tab: $e');
  }
}

/// Rename [tag] everywhere (files + color mapping).
Future<void> showRenameTagDialog(
  BuildContext context,
  String tag, {
  VoidCallback? onChanged,
  Rect? anchorRect,
}) async {
  final l10n = AppLocalizations.of(context)!;

  final newTag = await showCbInlineRename(
    context: context,
    title: l10n.renameTag,
    subtitle: tag,
    initialValue: tag,
    icon: PhosphorIconsLight.tag,
    iconColor: TagColorManager.instance.getTagColor(tag),
    hintText: l10n.renameShortcutHint,
    cancelLabel: l10n.cancel,
    confirmLabel: l10n.rename,
    anchorRect: anchorRect,
    validator: (value) => value.trim().isEmpty ? l10n.renameNameRequired : null,
  );

  if (newTag == null || newTag.isEmpty || newTag == tag) return;

  final allTags = await TagManager.getAllUniqueTags('');
  final exists = allTags.any((t) => t.toLowerCase() == newTag.toLowerCase());
  if (exists) {
    if (context.mounted) {
      AppToast.warning(context, l10n.tagAlreadyExists(newTag));
    }
    return;
  }

  final success = await TagManager.renameTag(tag, newTag);
  if (success) {
    final oldColor = TagColorManager.instance.getTagColor(tag);
    await TagColorManager.instance.setTagColor(newTag, oldColor);
    await TagColorManager.instance.removeTagColor(tag);
    TagManager.clearCache();
    TagManager.instance.notifyTagChanged('global:tag_updated');
    if (context.mounted) {
      AppToast.success(context, l10n.tagRenamed(tag, newTag));
    }
    onChanged?.call();
  }
}

/// Pick a new color for [tag].
Future<void> showTagColorPickerDialog(
  BuildContext context,
  String tag, {
  VoidCallback? onChanged,
}) async {
  final l10n = AppLocalizations.of(context)!;
  Color currentColor = TagColorManager.instance.getTagColor(tag);

  final selectedColor = await RouteUtils.showAcrylicDialog<Color>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(l10n.chooseTagColor(tag)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: TagChip(tag: tag, customColor: currentColor),
                  ),
                  ColorPicker(
                    pickerColor: currentColor,
                    onColorChanged: (color) =>
                        setDialogState(() => currentColor = color),
                    pickerAreaHeightPercent: 0.8,
                    enableAlpha: false,
                    displayThumbColor: true,
                    labelTypes: const [ColorLabelType.rgb, ColorLabelType.hsv],
                    pickerAreaBorderRadius: const BorderRadius.all(
                      Radius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(dialogContext, rootNavigator: true).pop(),
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(
                  dialogContext,
                  rootNavigator: true,
                ).pop(currentColor),
                child: Text(l10n.save),
              ),
            ],
          );
        },
      );
    },
  );

  if (selectedColor == null || !context.mounted) return;

  await TagColorManager.instance.setTagColor(tag, selectedColor);
  if (context.mounted) {
    AppToast.success(context, l10n.tagColorUpdated(tag));
  }
  onChanged?.call();
}

/// Set / replace / remove the thumbnail for [tag].
Future<void> showTagThumbnailPicker(
  BuildContext context,
  String tag, {
  VoidCallback? onChanged,
}) async {
  final thumbnailManager = TagThumbnailManager.instance;
  final currentThumbnail = thumbnailManager.getThumbnailSync(tag);
  final theme = Theme.of(context);
  final l10n = AppLocalizations.of(context)!;

  final result = await RouteUtils.showAcrylicDialog<String?>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('${l10n.setThumbnail}: "$tag"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
              child: currentThumbnail != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.file(
                        File(currentThumbnail),
                        width: 160,
                        height: 160,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Icon(
                            PhosphorIconsLight.imageSquare,
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Icon(
                        PhosphorIconsLight.image,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
            ),
          ],
        ),
        actions: [
          if (currentThumbnail != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop('remove'),
              child: Text(
                l10n.delete,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(l10n.cancel),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop('browse'),
            icon: const Icon(PhosphorIconsLight.folderOpen, size: 18),
            label: Text(l10n.browse),
          ),
        ],
      );
    },
  );

  if (!context.mounted) return;
  if (result == 'browse') {
    await _pickThumbnailFromBrowser(context, tag, onChanged: onChanged);
  } else if (result == 'remove') {
    final toast = AppToast.capture(context);
    await thumbnailManager.deleteThumbnail(tag);
    toast.success('Thumbnail removed for "$tag"');
    onChanged?.call();
  }
}

/// Opens the shared thumbnail browser (folders + tag search, with inline
/// video-frame extraction) and applies the chosen image as the tag thumbnail.
Future<void> _pickThumbnailFromBrowser(
  BuildContext context,
  String tag, {
  VoidCallback? onChanged,
}) async {
  try {
    final imagePath = await showThumbnailBrowserDialog(
      context,
      title: '${AppLocalizations.of(context)!.setThumbnail}: "$tag"',
    );
    if (imagePath == null) return;

    final ok = await TagThumbnailManager.instance.setThumbnail(tag, imagePath);
    if (context.mounted) {
      if (ok) {
        AppToast.success(context, 'Thumbnail set for "$tag"');
        onChanged?.call();
      } else {
        AppToast.error(context, 'Failed to set thumbnail');
      }
    }
  } catch (e) {
    AppLogger.error('Error picking thumbnail: $e');
    if (context.mounted) AppToast.error(context, 'Error: $e');
  }
}

/// Full hierarchy management dialog (parents + children) for [tag].
Future<void> showManageTagHierarchyDialog(
  BuildContext context,
  String tag, {
  VoidCallback? onChanged,
}) async {
  await TagHierarchyManager.instance.initialize();
  final allTags = (await TagManager.getAllUniqueTags('')).toList()..sort();
  if (!context.mounted) return;

  await RouteUtils.showAcrylicDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      return _ManageHierarchyDialog(
        tag: tag,
        hierarchyManager: TagHierarchyManager.instance,
        allTags: allTags,
        onChanged: () => onChanged?.call(),
      );
    },
  );
}

/// Delete [tag] from all files, with hierarchy-aware handling if it has
/// children.
Future<void> confirmDeleteTagFromAllFiles(
  BuildContext context,
  String tag, {
  VoidCallback? onChanged,
}) async {
  final theme = Theme.of(context);
  final l10n = AppLocalizations.of(context)!;
  final children = TagHierarchyManager.instance.getChildren(tag);

  if (children.isNotEmpty) {
    final result = await RouteUtils.showAcrylicDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteTagConfirmation(tag)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This tag has ${children.length} child tag${children.length > 1 ? "s" : ""}: ${children.join(", ")}',
            ),
            const SizedBox(height: 16),
            const Text(
              'What would you like to do?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('keep_children'),
            child: const Text('Delete parent only'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete_all'),
            child: Text(
              'Delete parent and children',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (result == 'keep_children') {
      final toast = AppToast.capture(context);
      await TagHierarchyManager.instance.removeAllForTag(tag);
      await _deleteTagGlobally(tag, l10n, toast);
      onChanged?.call();
    } else if (result == 'delete_all') {
      final toast = AppToast.capture(context);
      final tagsToDelete = [tag, ...children];
      for (final t in tagsToDelete) {
        await TagHierarchyManager.instance.removeAllForTag(t);
      }
      for (final t in tagsToDelete) {
        await _deleteTagGlobally(
          t,
          l10n,
          toast,
          silent: tagsToDelete.length > 1,
        );
      }
      toast.success(
        'Deleted ${tagsToDelete.length} tags: ${tagsToDelete.join(", ")}',
      );
      onChanged?.call();
    }
    return;
  }

  final confirmed = await RouteUtils.showAcrylicDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.deleteTagConfirmation(tag)),
      content: Text(l10n.tagDeleteConfirmationText),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            l10n.delete,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
    ),
  );

  if (confirmed == true && context.mounted) {
    final toast = AppToast.capture(context);
    await TagHierarchyManager.instance.removeAllForTag(tag);
    await _deleteTagGlobally(tag, l10n, toast);
    onChanged?.call();
  }
}

Future<void> _deleteTagGlobally(
  String tag,
  AppLocalizations l10n,
  AppToastPresenter toast, {
  bool silent = false,
}) async {
  final operation = locator<OperationProgressController>();
  final operationId = operation.begin(
    title: l10n.deleteTag,
    total: 1,
    detail: tag,
    isIndeterminate: true,
    showModal: true,
  );

  try {
    await TagManager.deleteTagGlobally(tag);
    await TagColorManager.instance.removeTagColor(tag);
    if (!silent) {
      toast.success(l10n.tagDeleted(tag));
    }
    operation.succeed(operationId, detail: l10n.tagDeleted(tag));
  } catch (e) {
    operation.fail(operationId, detail: l10n.errorDeletingTag(e.toString()));
    toast.error(l10n.errorDeletingTag(e.toString()));
  }
}

/// Hierarchy editor dialog: shows current parents + children and lets the user
/// add/remove either. Self-contained; operates on [TagHierarchyManager].
class _ManageHierarchyDialog extends StatefulWidget {
  final String tag;
  final TagHierarchyManager hierarchyManager;
  final List<String> allTags;
  final VoidCallback onChanged;

  const _ManageHierarchyDialog({
    required this.tag,
    required this.hierarchyManager,
    required this.allTags,
    required this.onChanged,
  });

  @override
  State<_ManageHierarchyDialog> createState() => _ManageHierarchyDialogState();
}

class _ManageHierarchyDialogState extends State<_ManageHierarchyDialog> {
  late List<String> _parents;
  late List<String> _children;
  final _addChildController = TextEditingController();
  final _setParentController = TextEditingController();
  List<String> _childSuggestions = [];
  List<String> _parentSuggestions = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _parents = widget.hierarchyManager.getParents(widget.tag);
    _children = widget.hierarchyManager.getChildren(widget.tag);
  }

  @override
  void dispose() {
    _addChildController.dispose();
    _setParentController.dispose();
    super.dispose();
  }

  void _updateChildSuggestions(String query) {
    if (query.trim().isEmpty) {
      setState(() => _childSuggestions = []);
      return;
    }
    final q = query.toLowerCase().trim();
    final suggestions = widget.allTags
        .where((t) {
          final tl = t.toLowerCase();
          return tl.contains(q) &&
              tl != widget.tag.toLowerCase() &&
              !_children.any((c) => c.toLowerCase() == tl);
        })
        .take(8)
        .toList();
    setState(() => _childSuggestions = suggestions);
  }

  void _updateParentSuggestions(String query) {
    if (query.trim().isEmpty) {
      setState(() => _parentSuggestions = []);
      return;
    }
    final q = query.toLowerCase().trim();
    final suggestions = widget.allTags
        .where((t) {
          final tl = t.toLowerCase();
          return tl.contains(q) &&
              tl != widget.tag.toLowerCase() &&
              !_parents.any((p) => p.toLowerCase() == tl);
        })
        .take(8)
        .toList();
    setState(() => _parentSuggestions = suggestions);
  }

  Future<void> _addChild(String childName) async {
    if (childName.trim().isEmpty) return;
    final exists = widget.allTags.any(
      (t) => t.toLowerCase() == childName.toLowerCase(),
    );
    if (!exists) {
      await TagManager.addStandaloneTag(childName.trim());
    }
    final ok = await widget.hierarchyManager.addChild(
      widget.tag,
      childName.trim(),
    );
    if (ok) {
      _addChildController.clear();
      _refresh();
      widget.onChanged();
      if (mounted) setState(() => _childSuggestions = []);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot add "$childName" - circular reference or error',
          ),
        ),
      );
    }
  }

  Future<void> _removeChild(String child) async {
    await widget.hierarchyManager.removeChild(widget.tag, child);
    _refresh();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _addParent(String parentName) async {
    if (parentName.trim().isEmpty) return;
    final exists = widget.allTags.any(
      (t) => t.toLowerCase() == parentName.toLowerCase(),
    );
    if (!exists) {
      await TagManager.addStandaloneTag(parentName.trim());
    }
    final ok = await widget.hierarchyManager.addChild(
      parentName.trim(),
      widget.tag,
    );
    if (ok) {
      _setParentController.clear();
      _refresh();
      widget.onChanged();
      if (mounted) setState(() => _parentSuggestions = []);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot set "$parentName" as parent - circular reference or error',
          ),
        ),
      );
    }
  }

  Future<void> _removeParent(String parent) async {
    await widget.hierarchyManager.removeChild(parent, widget.tag);
    _refresh();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            PhosphorIconsLight.treeStructure,
            size: 22,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hierarchy: "${widget.tag}"',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Parents
              Text(
                'Parents',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
              if (_parents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No parent tags',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _parents
                      .map(
                        (parent) => Chip(
                          avatar: Icon(
                            PhosphorIconsLight.arrowBendUpLeft,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          label: Text(
                            parent,
                            style: const TextStyle(fontSize: 13),
                          ),
                          deleteIcon: const Icon(
                            PhosphorIconsLight.x,
                            size: 14,
                          ),
                          onDeleted: () => _removeParent(parent),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 6),
              _buildAutocompleteInput(
                controller: _setParentController,
                hint: 'Add parent...',
                suggestions: _parentSuggestions,
                onChanged: _updateParentSuggestions,
                onSubmit: _addParent,
              ),
              const SizedBox(height: 20),
              Divider(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              // Children
              Text(
                'Children',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: theme.colorScheme.tertiary,
                ),
              ),
              const SizedBox(height: 6),
              if (_children.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No child tags',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.6,
                      ),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _children
                      .map(
                        (child) => Chip(
                          avatar: Icon(
                            PhosphorIconsLight.treeStructure,
                            size: 14,
                            color: theme.colorScheme.tertiary,
                          ),
                          label: Text(
                            child,
                            style: const TextStyle(fontSize: 13),
                          ),
                          deleteIcon: const Icon(
                            PhosphorIconsLight.x,
                            size: 14,
                          ),
                          onDeleted: () => _removeChild(child),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),
              const SizedBox(height: 6),
              _buildAutocompleteInput(
                controller: _addChildController,
                hint: 'Add child... (comma-separated)',
                suggestions: _childSuggestions,
                onChanged: _updateChildSuggestions,
                onSubmit: (value) async {
                  final names = value
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty);
                  for (final name in names) {
                    await _addChild(name);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildAutocompleteInput({
    required TextEditingController controller,
    required String hint,
    required List<String> suggestions,
    required ValueChanged<String> onChanged,
    required Future<void> Function(String) onSubmit,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            suffixIcon: IconButton(
              icon: const Icon(PhosphorIconsLight.plus, size: 18),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) onSubmit(text);
              },
              visualDensity: VisualDensity.compact,
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: onChanged,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) onSubmit(value.trim());
          },
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = suggestions[index];
                return InkWell(
                  onTap: () => onSubmit(suggestion),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          PhosphorIconsLight.tag,
                          size: 14,
                          color: TagColorManager.instance.getTagColor(
                            suggestion,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(suggestion, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
