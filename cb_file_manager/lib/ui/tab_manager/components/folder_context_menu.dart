// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/helpers/media/folder_thumbnail_service.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/dialogs/folder_thumbnail_picker_dialog.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';

/// Displays a context menu for empty areas in folder view
class FolderContextMenu {
  /// Currently displayed submenu overlay
  static OverlayEntry? _submenuOverlayEntry;

  /// Remove the submenu overlay if it's open
  static void _removeSubMenu() {
    _submenuOverlayEntry?.remove();
    _submenuOverlayEntry = null;
  }

  /// Shows the context menu for the current directory
  static Future<void> show({
    required BuildContext context,
    required Offset globalPosition, // Renamed from position for clarity
    required FolderListBloc folderListBloc,
    required String currentPath,
    required ViewMode currentViewMode,
    required SortOption currentSortOption,
    required Function(ViewMode) onViewModeChanged,
    required VoidCallback onRefresh,
    required Future<void> Function(String) onCreateFolder,
    required Future<void> Function(SortOption)
        onSortOptionSaved, // Keep for future use or remove if not needed by caller
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );

    await showMenu<String>(
      context: context,
      position: position,
      items: <PopupMenuEntry<String>>[
        _buildSubmenuPopupMenuItem(
          context: context,
          value: 'view',
          title: l10n.viewModeTooltip,
          icon: PhosphorIconsLight.eye,
          builder: (BuildContext context) {
            return <PopupMenuEntry<ViewMode>>[
              _buildCheckedPopupMenuItem(
                title: l10n.viewModeList,
                value: ViewMode.list,
                isChecked: currentViewMode == ViewMode.list,
              ),
              _buildCheckedPopupMenuItem(
                title: l10n.viewModeGrid,
                value: ViewMode.grid,
                isChecked: currentViewMode == ViewMode.grid,
              ),
              if (!Platform.isAndroid && !Platform.isIOS)
                _buildCheckedPopupMenuItem(
                  title: l10n.viewModeGridPreview,
                  value: ViewMode.gridPreview,
                  isChecked: currentViewMode == ViewMode.gridPreview,
                ),
              _buildCheckedPopupMenuItem(
                title: l10n.viewModeDetails,
                value: ViewMode.details,
                isChecked: currentViewMode == ViewMode.details,
              ),
            ];
          },
          onSelected: (ViewMode viewMode) {
            onViewModeChanged(viewMode);
          },
        ),
        _buildSubmenuPopupMenuItem(
          context: context,
          value: 'sort',
          title: l10n.sortByTooltip,
          icon: PhosphorIconsLight.sortAscending,
          builder: (BuildContext context) {
            final l10n = AppLocalizations.of(context)!;
            return <PopupMenuEntry<SortOption>>[
              _buildCheckedPopupMenuItem(
                  title: l10n.sortNameAsc,
                  value: SortOption.nameAsc,
                  isChecked: currentSortOption == SortOption.nameAsc),
              _buildCheckedPopupMenuItem(
                  title: l10n.sortNameDesc,
                  value: SortOption.nameDesc,
                  isChecked: currentSortOption == SortOption.nameDesc),
              _buildCheckedPopupMenuItem(
                  title: l10n.sortDateModifiedNewest,
                  value: SortOption.dateDesc,
                  isChecked: currentSortOption == SortOption.dateDesc),
              _buildCheckedPopupMenuItem(
                  title: l10n.sortDateModifiedOldest,
                  value: SortOption.dateAsc,
                  isChecked: currentSortOption == SortOption.dateAsc),
              _buildCheckedPopupMenuItem(
                  title: l10n.sortSizeLargest,
                  value: SortOption.sizeDesc,
                  isChecked: currentSortOption == SortOption.sizeDesc),
              _buildCheckedPopupMenuItem(
                  title: l10n.sortSizeSmallest,
                  value: SortOption.sizeAsc,
                  isChecked: currentSortOption == SortOption.sizeAsc),
              _buildCheckedPopupMenuItem(
                  title: l10n.sortTypeAsc,
                  value: SortOption.typeAsc,
                  isChecked: currentSortOption == SortOption.typeAsc),
              _buildCheckedPopupMenuItem(
                  title: l10n.sortTypeDesc,
                  value: SortOption.typeDesc,
                  isChecked: currentSortOption == SortOption.typeDesc),
            ];
          },
          onSelected: (SortOption sortOption) {
            folderListBloc.add(SetSortOption(sortOption));
            onSortOptionSaved(sortOption);
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'refresh',
          child: _buildIconMenuItemContent(
              title: l10n.refresh, icon: PhosphorIconsLight.arrowsClockwise),
        ),
        PopupMenuItem<String>(
          value: 'new_folder',
          child: _buildIconMenuItemContent(
              title: l10n.newFolder, icon: PhosphorIconsLight.folderPlus),
        ),
        PopupMenuItem<String>(
          value: 'new_file',
          child: _buildIconMenuItemContent(
              title: 'New File', icon: PhosphorIconsLight.filePlus),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          child: _buildIconMenuItemContent(
              title: l10n.pasteHere, icon: PhosphorIconsLight.clipboard),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'properties',
          child: _buildIconMenuItemContent(
              title: l10n.properties, icon: PhosphorIconsLight.info),
        ),
      ],
    ).then((String? value) async {
      // Ensure any open submenu overlay is removed when the main menu closes
      _removeSubMenu();
      if (value == null) return;

      switch (value) {
        case 'refresh':
          onRefresh();
          break;
        case 'new_folder':
          _showCreateFolderDialog(context, currentPath, onCreateFolder);
          break;
        case 'new_file':
          _showCreateFileDialog(context, currentPath);
          break;
        case 'paste':
          // TODO: Implement paste functionality
          break;
        case 'properties':
          _showFolderProperties(context, currentPath);
          break;
        // 'view' and 'sort' are handled by their onSelected callbacks in _buildSubmenuPopupMenuItem
      }
    });
  }

  // New helper method to encapsulate submenu opening logic
  static void _openActualSubMenu<T>(
    BuildContext anchorContext,
    GlobalKey itemKey,
    List<PopupMenuEntry<T>> Function(BuildContext) builder,
    ValueChanged<T> onSelectedCallback, // Renamed for clarity
    VoidCallback onSubMenuDismissedWithoutSelection, // New callback
  ) {
    // Remove any existing submenu overlay
    _removeSubMenu();
    if (itemKey.currentContext == null) return;
    final overlayState = Overlay.of(anchorContext);
    final RenderBox overlay =
        overlayState.context.findRenderObject() as RenderBox;
    final RenderBox itemRenderBox =
        itemKey.currentContext!.findRenderObject() as RenderBox;
    final Offset itemPosition =
        itemRenderBox.localToGlobal(Offset.zero, ancestor: overlay);

    const double minSubMenuWidth = 180.0;
    final double subMenuWidth =
        math.max(itemRenderBox.size.width, minSubMenuWidth);
    const double menuGap = 2.0;
    const double verticalOffsetCorrection = -8.0;
    double subMenuLeft;
    if (itemPosition.dx + itemRenderBox.size.width + menuGap + subMenuWidth >
        overlay.size.width) {
      subMenuLeft = itemPosition.dx - subMenuWidth - menuGap;
    } else {
      subMenuLeft = itemPosition.dx + itemRenderBox.size.width + menuGap;
    }
    final double subMenuTop =
        math.max(0.0, itemPosition.dy + verticalOffsetCorrection);
    final List<PopupMenuEntry<T>> items = builder(anchorContext);
    final double subMenuHeight =
        itemRenderBox.size.height * items.length * 1.2 + 16.0;

    // Create and insert submenu overlay
    final entry = OverlayEntry(builder: (context) {
      return Positioned(
        left: subMenuLeft,
        top: subMenuTop,
        width: subMenuWidth,
        child: Material(
          elevation: 0,
          color: Theme.of(anchorContext).canvasColor,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8.0))),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: subMenuHeight),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, thickness: 1),
              itemBuilder: (context, index) {
                final entryItem = items[index];
                if (entryItem is PopupMenuDivider) {
                  return Divider(height: entryItem.height, thickness: 1);
                } else if (entryItem is PopupMenuItem<T>) {
                  return InkWell(
                    onTap: () {
                      onSelectedCallback(entryItem.value as T);
                      _removeSubMenu();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 12.0),
                      child: entryItem.child,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });
    _submenuOverlayEntry = entry;
    overlayState.insert(entry);
  }

  // Helper to build a PopupMenuItem that opens a submenu
  static PopupMenuEntry<String> _buildSubmenuPopupMenuItem<T>({
    required BuildContext context,
    required String value,
    required String title,
    required IconData icon,
    required List<PopupMenuEntry<T>> Function(BuildContext) builder,
    required ValueChanged<T> onSelected,
  }) {
    final GlobalKey itemKey = GlobalKey();
    return PopupMenuItem<String>(
      value: value,
      enabled: true,
      child: MouseRegion(
        onEnter: (_) {
          _openActualSubMenu<T>(context, itemKey, builder, onSelected, () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            }
          });
        },
        child: _buildIconMenuItemContent(
          key: itemKey,
          title: title,
          icon: icon,
          hasTrailingArrow: true,
        ),
      ),
      onTap: () {
        _openActualSubMenu<T>(context, itemKey, builder, onSelected, () {
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        });
      },
    );
  }

  // Helper for direct action menu items
  static Widget _buildIconMenuItemContent({
    Key? key, // Added key parameter
    required String title,
    required IconData icon,
    bool hasTrailingArrow = false,
  }) {
    return Row(
      key: key, // Assign the key to the Row
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(title)),
        if (hasTrailingArrow)
          const Icon(PhosphorIconsLight.arrowRight, size: 20),
      ],
    );
  }

  // Helper for items within submenus (with checkmark)
  static PopupMenuItem<T> _buildCheckedPopupMenuItem<T>({
    required String title,
    required T value,
    required bool isChecked,
  }) {
    return PopupMenuItem<T>(
      value: value,
      child: Row(
        children: [
          Expanded(child: Text(title)),
          if (isChecked)
            const Icon(PhosphorIconsLight.check, size: 18)
          else
            const SizedBox(width: 18),
        ],
      ),
    );
  }

  static Future<void> _showCreateFolderDialog(
    BuildContext context,
    String currentPath,
    Future<void> Function(String) onCreateFolder,
  ) async {
    final TextEditingController nameController = TextEditingController();
    if (!context.mounted) return;

    final l10n = AppLocalizations.of(context)!;
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.createNewFolder),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: l10n.folderNameLabel,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final String folderName = nameController.text.trim();
              if (folderName.isNotEmpty) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                await onCreateFolder(folderName);
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    ).then((_) {
      nameController.dispose();
    });
  }

  static Future<void> _showCreateFileDialog(
    BuildContext context,
    String currentPath,
  ) async {
    if (!context.mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final folderListBloc = context.read<FolderListBloc>();

    final TextEditingController nameController = TextEditingController();

    final l10n = AppLocalizations.of(context)!;
    return showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.createNewFile),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: l10n.fileNameLabel,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final String fileName = nameController.text.trim();
              if (fileName.isNotEmpty) {
                final String newFilePath =
                    '$currentPath${Platform.pathSeparator}$fileName';

                try {
                  File(newFilePath).createSync();
                  folderListBloc.add(FolderListLoad(currentPath));
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                } catch (error) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text(l10n.errorCreatingFile(error.toString())),
                      backgroundColor: Colors.red,
                    ),
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                }
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    ).then((_) {
      nameController.dispose();
    });
  }

  static Future<void> _showFolderProperties(
    BuildContext context,
    String path,
  ) async {
    if (!context.mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final directory = Directory(path);
      final stat = await directory.stat();

      int totalSize = 0;
      int fileCount = 0;
      int folderCount = 0;

      try {
        await for (final entity in directory.list(recursive: false)) {
          if (entity is File) {
            fileCount++;
            totalSize += await entity.length();
          } else if (entity is Directory) {
            folderCount++;
          }
        }
      } catch (e) {
        // Ignore errors
      }

      if (!context.mounted) return;
      final thumbnailService = FolderThumbnailService();
      Future<String?> customThumbnailFuture =
          thumbnailService.getCustomThumbnailPath(path);

      final l10n = AppLocalizations.of(context)!;
      showDialog(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setState) => AlertDialog(
            title: Text(l10n.folderProperties),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(l10n.folderPropertyPath),
                    subtitle: Text(path),
                  ),
                  ListTile(
                    title: Text(l10n.folderPropertyCreated),
                    subtitle: Text(stat.modified.toLocal().toString()),
                  ),
                  ListTile(
                    title: Text(l10n.folderPropertyContent),
                    subtitle: Text('$fileCount files, $folderCount folders'),
                  ),
                  ListTile(
                    title: Text(l10n.folderPropertySizeDirectChildren),
                    subtitle: Text(_formatFileSize(totalSize)),
                  ),
                  const Divider(),
                  Text(
                    l10n.folderThumbnail,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<String?>(
                    future: customThumbnailFuture,
                    builder: (ctx, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Text(l10n.loading);
                      }
                      final value = snapshot.data;
                      if (value == null || value.isEmpty) {
                        return Text(l10n.thumbnailAuto);
                      }
                      final displayValue = value.startsWith('video::')
                          ? value.substring(7)
                          : value;
                      return Text(displayValue);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () async {
                          final selectedPath =
                              await showFolderThumbnailPickerDialog(
                            dialogContext,
                            path,
                          );
                          if (selectedPath == null) {
                            return;
                          }

                          final isImage =
                              FileTypeUtils.isImageFile(selectedPath);
                          final isVideo =
                              VideoThumbnailHelper.isSupportedVideoFormat(
                                  selectedPath);
                          if (!isImage && !isVideo) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(AppLocalizations.of(context)!
                                      .invalidThumbnailFile),
                                ),
                              );
                            }
                            return;
                          }

                          await thumbnailService.setCustomThumbnail(
                            path,
                            selectedPath,
                            isVideo: isVideo,
                          );
                          if (dialogContext.mounted) {
                            setState(() {
                              customThumbnailFuture = Future.value(
                                isVideo ? 'video::$selectedPath' : selectedPath,
                              );
                            });
                          }
                        },
                        child: Text(l10n.chooseThumbnail),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          await thumbnailService.clearCustomThumbnail(path);
                          if (dialogContext.mounted) {
                            setState(() {
                              customThumbnailFuture = Future.value(null);
                            });
                          }
                        },
                        child: Text(l10n.clearThumbnail),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (scaffoldMessenger.mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .errorGettingFolderProperties(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static String _formatFileSize(int sizeInBytes) {
    if (sizeInBytes < 1024) {
      return '$sizeInBytes B';
    } else if (sizeInBytes < 1024 * 1024) {
      final kb = sizeInBytes / 1024;
      return '${kb.toStringAsFixed(2)} KB';
    } else if (sizeInBytes < 1024 * 1024 * 1024) {
      final mb = sizeInBytes / (1024 * 1024);
      return '${mb.toStringAsFixed(2)} MB';
    } else {
      final gb = sizeInBytes / (1024 * 1024 * 1024);
      return '${gb.toStringAsFixed(2)} GB';
    }
  }
}
