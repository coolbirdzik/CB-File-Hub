// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/dialogs/folder_thumbnail_picker_dialog.dart';
import 'package:cb_file_manager/ui/dialogs/create_file_dialog.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/media/folder_thumbnail_service.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/services/desktop_new_file_service.dart';
import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
import 'package:cb_file_manager/ui/components/common/shared_file_context_menu.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/utils/route.dart';

/// Displays a context menu for empty areas in folder view
class FolderContextMenu {
  /// Shows the context menu for the current directory
  static Future<void> show({
    required BuildContext context,
    required Offset globalPosition,
    required FolderListBloc folderListBloc,
    required String currentPath,
    required ViewMode currentViewMode,
    required SortOption currentSortOption,
    required Function(ViewMode) onViewModeChanged,
    required VoidCallback onRefresh,
    required Future<void> Function(String) onCreateFolder,
    InlineRenameController? inlineRenameController,
    ValueChanged<String>? onAfterFileCreated,
  }) async {
    final sections = await _buildSections(
      context: context,
      folderListBloc: folderListBloc,
      currentPath: currentPath,
      currentViewMode: currentViewMode,
      currentSortOption: currentSortOption,
      onViewModeChanged: onViewModeChanged,
      onRefresh: onRefresh,
      onCreateFolder: onCreateFolder,
      inlineRenameController: inlineRenameController,
      onAfterFileCreated: onAfterFileCreated,
    );

    if (_isMobilePlatform()) {
      await showContextMenuSheet(
        context: context,
        title: Directory(currentPath).path.split(Platform.pathSeparator).last,
        icon: PhosphorIconsLight.folderOpen,
        subtitle: currentPath,
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

  static Future<void> showCreateMenu({
    required BuildContext context,
    required String currentPath,
    FolderListBloc? folderListBloc,
    required Future<void> Function(String) onCreateFolder,
    InlineRenameController? inlineRenameController,
    ValueChanged<String>? onAfterFileCreated,
  }) async {
    final sections = await _buildCreateSections(
      context: context,
      currentPath: currentPath,
      folderListBloc: folderListBloc,
      onCreateFolder: onCreateFolder,
      inlineRenameController: inlineRenameController,
      onAfterFileCreated: onAfterFileCreated,
    );
    await showContextMenuSheet(
      context: context,
      title: AppLocalizations.of(context)!.create,
      icon: PhosphorIconsLight.plusCircle,
      subtitle: currentPath,
      sections: sections,
    );
  }

  static Future<List<ContextMenuSection>> _buildSections({
    required BuildContext context,
    required FolderListBloc folderListBloc,
    required String currentPath,
    required ViewMode currentViewMode,
    required SortOption currentSortOption,
    required Function(ViewMode) onViewModeChanged,
    required VoidCallback onRefresh,
    required Future<void> Function(String) onCreateFolder,
    InlineRenameController? inlineRenameController,
    ValueChanged<String>? onAfterFileCreated,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final createSections = Platform.isWindows && !_isMobilePlatform()
        ? _buildLazyWindowsCreateSections(
            context: context,
            currentPath: currentPath,
            folderListBloc: folderListBloc,
            onCreateFolder: onCreateFolder,
            inlineRenameController: inlineRenameController,
            onAfterFileCreated: onAfterFileCreated,
          )
        : await _buildCreateSections(
            context: context,
            currentPath: currentPath,
            folderListBloc: folderListBloc,
            onCreateFolder: onCreateFolder,
            inlineRenameController: inlineRenameController,
            onAfterFileCreated: onAfterFileCreated,
          );
    return [
      ContextMenuSection(
        actions: [
          ContextMenuAction(
            id: 'view_submenu',
            label: l10n.viewModeTooltip,
            icon: PhosphorIconsLight.eye,
            childSections: [
              ContextMenuSection(
                actions: [
                  ContextMenuAction(
                    id: 'view_list',
                    label: l10n.viewModeList,
                    icon: PhosphorIconsLight.listBullets,
                    isChecked: currentViewMode == ViewMode.list,
                    onSelected: (_) => onViewModeChanged(ViewMode.list),
                  ),
                  ContextMenuAction(
                    id: 'view_tiles',
                    label: l10n.viewModeTiles,
                    icon: PhosphorIconsLight.gridNine,
                    isChecked: currentViewMode == ViewMode.tiles,
                    onSelected: (_) => onViewModeChanged(ViewMode.tiles),
                  ),
                  ContextMenuAction(
                    id: 'view_grid',
                    label: l10n.viewModeGrid,
                    icon: PhosphorIconsLight.squaresFour,
                    isChecked: currentViewMode == ViewMode.grid,
                    onSelected: (_) => onViewModeChanged(ViewMode.grid),
                  ),
                  ContextMenuAction(
                    id: 'view_details',
                    label: l10n.viewModeDetails,
                    icon: PhosphorIconsLight.rows,
                    isChecked: currentViewMode == ViewMode.details,
                    onSelected: (_) => onViewModeChanged(ViewMode.details),
                  ),
                ],
              ),
            ],
          ),
          ContextMenuAction(
            id: 'sort_submenu',
            label: l10n.sortByTooltip,
            icon: PhosphorIconsLight.sortAscending,
            childSections: [
              ContextMenuSection(
                actions: [
                  ContextMenuAction(
                    id: 'sort_name_asc',
                    label: l10n.sortNameAsc,
                    icon: PhosphorIconsLight.sortAscending,
                    isChecked: currentSortOption == SortOption.nameAsc,
                    onSelected: (_) {
                      folderListBloc.add(SetSortOption(
                        SortOption.nameAsc,
                        folderPath: currentPath,
                      ));
                    },
                  ),
                  ContextMenuAction(
                    id: 'sort_name_desc',
                    label: l10n.sortNameDesc,
                    icon: PhosphorIconsLight.sortDescending,
                    isChecked: currentSortOption == SortOption.nameDesc,
                    onSelected: (_) {
                      folderListBloc.add(SetSortOption(
                        SortOption.nameDesc,
                        folderPath: currentPath,
                      ));
                    },
                  ),
                  ContextMenuAction(
                    id: 'sort_date_desc',
                    label: l10n.sortDateModifiedNewest,
                    icon: PhosphorIconsLight.calendarBlank,
                    isChecked: currentSortOption == SortOption.dateDesc,
                    onSelected: (_) {
                      folderListBloc.add(SetSortOption(
                        SortOption.dateDesc,
                        folderPath: currentPath,
                      ));
                    },
                  ),
                  ContextMenuAction(
                    id: 'sort_date_asc',
                    label: l10n.sortDateModifiedOldest,
                    icon: PhosphorIconsLight.calendarBlank,
                    isChecked: currentSortOption == SortOption.dateAsc,
                    onSelected: (_) {
                      folderListBloc.add(SetSortOption(
                        SortOption.dateAsc,
                        folderPath: currentPath,
                      ));
                    },
                  ),
                  ContextMenuAction(
                    id: 'sort_size_desc',
                    label: l10n.sortSizeLargest,
                    icon: PhosphorIconsLight.arrowsOut,
                    isChecked: currentSortOption == SortOption.sizeDesc,
                    onSelected: (_) {
                      folderListBloc.add(SetSortOption(
                        SortOption.sizeDesc,
                        folderPath: currentPath,
                      ));
                    },
                  ),
                  ContextMenuAction(
                    id: 'sort_size_asc',
                    label: l10n.sortSizeSmallest,
                    icon: PhosphorIconsLight.arrowsIn,
                    isChecked: currentSortOption == SortOption.sizeAsc,
                    onSelected: (_) {
                      folderListBloc.add(SetSortOption(
                        SortOption.sizeAsc,
                        folderPath: currentPath,
                      ));
                    },
                  ),
                  ContextMenuAction(
                    id: 'sort_type_asc',
                    label: l10n.sortTypeAsc,
                    icon: PhosphorIconsLight.textAa,
                    isChecked: currentSortOption == SortOption.typeAsc,
                    onSelected: (_) {
                      folderListBloc.add(SetSortOption(
                        SortOption.typeAsc,
                        folderPath: currentPath,
                      ));
                    },
                  ),
                  ContextMenuAction(
                    id: 'sort_type_desc',
                    label: l10n.sortTypeDesc,
                    icon: PhosphorIconsLight.textAa,
                    isChecked: currentSortOption == SortOption.typeDesc,
                    onSelected: (_) {
                      folderListBloc.add(SetSortOption(
                        SortOption.typeDesc,
                        folderPath: currentPath,
                      ));
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      ...createSections,
      ContextMenuSection(
        title: l10n.moreOptions,
        actions: [
          ContextMenuAction(
            id: 'paste',
            label: l10n.pasteHere,
            icon: PhosphorIconsLight.clipboard,
            onSelected: (_) => FileOperationsHandler.pasteFromClipboard(
              context: context,
              destinationPath: currentPath,
            ),
          ),
          ContextMenuAction(
            id: 'refresh',
            label: l10n.refresh,
            icon: PhosphorIconsLight.arrowsClockwise,
            onSelected: (_) => onRefresh(),
          ),
          ContextMenuAction(
            id: 'properties',
            label: l10n.properties,
            icon: PhosphorIconsLight.info,
            onSelected: (_) => _showFolderProperties(context, currentPath),
          ),
        ],
      ),
    ];
  }

  static List<ContextMenuSection> _buildLazyWindowsCreateSections({
    required BuildContext context,
    required String currentPath,
    FolderListBloc? folderListBloc,
    required Future<void> Function(String) onCreateFolder,
    InlineRenameController? inlineRenameController,
    ValueChanged<String>? onAfterFileCreated,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return <ContextMenuSection>[
      ContextMenuSection(
        title: l10n.create,
        actions: <ContextMenuAction>[
          ContextMenuAction(
            id: 'new_submenu',
            label: 'New',
            icon: PhosphorIconsLight.filePlus,
            loadChildSections: (_) async {
              final sections = await _buildCreateSections(
                context: context,
                currentPath: currentPath,
                folderListBloc: folderListBloc,
                onCreateFolder: onCreateFolder,
                inlineRenameController: inlineRenameController,
                onAfterFileCreated: onAfterFileCreated,
              );
              for (final section in sections) {
                for (final action in section.actions) {
                  if (action.id == 'new_submenu') {
                    return action.childSections ?? const <ContextMenuSection>[];
                  }
                }
              }
              return const <ContextMenuSection>[];
            },
          ),
        ],
      ),
    ];
  }

  static Future<List<ContextMenuSection>> _buildCreateSections({
    required BuildContext context,
    required String currentPath,
    FolderListBloc? folderListBloc,
    required Future<void> Function(String) onCreateFolder,
    InlineRenameController? inlineRenameController,
    ValueChanged<String>? onAfterFileCreated,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (!Platform.isWindows || _isMobilePlatform()) {
      return [
        ContextMenuSection(
          title: l10n.create,
          actions: [
            ContextMenuAction(
              id: 'new_folder',
              label: l10n.newFolder,
              icon: PhosphorIconsLight.folderPlus,
              onSelected: (_) => _showCreateFolderDialog(
                context,
                currentPath,
                onCreateFolder,
              ),
            ),
            ContextMenuAction(
              id: 'new_file',
              label: l10n.createNewFile,
              icon: PhosphorIconsLight.filePlus,
              onSelected: (_) => _showCreateFileDialog(
                context,
                currentPath,
                folderListBloc,
                inlineRenameController,
                onAfterFileCreated,
              ),
            ),
          ],
        ),
      ];
    }

    final desktopNewFileItems =
        await DesktopNewFileService.instance.getAvailableItems();
    final quickCreateItems =
        await _resolveQuickCreateItems(desktopNewFileItems);

    final quickCreateActions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'new_folder',
        label: l10n.newFolder,
        icon: PhosphorIconsLight.folderPlus,
        onSelected: (_) => _showCreateFolderDialog(
          context,
          currentPath,
          onCreateFolder,
        ),
      ),
    ];

    for (final item in quickCreateItems) {
      quickCreateActions.add(
        ContextMenuAction(
          id: 'quick_create:${item.id}',
          label: _desktopNewFileItemLabel(context, item),
          icon: item.icon,
          onSelected: (_) => _createDesktopNewFile(
            context: context,
            currentPath: currentPath,
            folderListBloc: folderListBloc,
            item: item,
            inlineRenameController: inlineRenameController,
            onAfterFileCreated: onAfterFileCreated,
          ),
        ),
      );
    }

    final utilityActions = <ContextMenuAction>[
      ContextMenuAction(
        id: 'new_file_more',
        label: '${l10n.createNewFile}...',
        icon: PhosphorIconsLight.dotsThree,
        onSelected: (_) => _showCreateFileDialog(
          context,
          currentPath,
          folderListBloc,
          inlineRenameController,
          onAfterFileCreated,
        ),
      ),
      ContextMenuAction(
        id: 'customize_new_menu',
        label: 'Customize...',
        icon: PhosphorIconsLight.slidersHorizontal,
        onSelected: (_) => _showDesktopNewMenuCustomizationDialog(
          context: context,
          items: desktopNewFileItems,
        ),
      ),
    ];

    return [
      ContextMenuSection(
        title: l10n.create,
        actions: [
          ContextMenuAction(
            id: 'new_submenu',
            label: 'New',
            icon: PhosphorIconsLight.filePlus,
            childSections: [
              ContextMenuSection(actions: quickCreateActions),
              ContextMenuSection(actions: utilityActions),
            ],
          ),
        ],
      ),
    ];
  }

  static Future<List<DesktopNewFileItem>> _resolveQuickCreateItems(
    List<DesktopNewFileItem> items,
  ) async {
    final preferences = UserPreferences.instance;
    final storedIds = await preferences.getDesktopQuickCreateItemIds();
    final defaultIds = DesktopNewFileService.instance.buildDefaultQuickItemIds(
      items,
    );
    final preferredIds = storedIds.isEmpty ? defaultIds : storedIds;
    final itemById = <String, DesktopNewFileItem>{
      for (final item in items) item.id: item,
    };

    final ordered = <DesktopNewFileItem>[];
    for (final id in preferredIds) {
      final item = itemById[id];
      if (item != null) {
        ordered.add(item);
      }
    }
    return ordered;
  }

  static Future<void> _createDesktopNewFile({
    required BuildContext context,
    required String currentPath,
    required DesktopNewFileItem item,
    FolderListBloc? folderListBloc,
    InlineRenameController? inlineRenameController,
    ValueChanged<String>? onAfterFileCreated,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final toast = AppToast.capture(context);

    DirectoryWatcherService.instance.suppressRefreshForPath(currentPath);
    final createdPath = await DesktopNewFileService.instance.createItem(
      directoryPath: currentPath,
      item: item,
      customBaseName: _defaultDesktopNewFileBaseName(context, item),
    );

    if (createdPath == null) {
      toast.error(
        l10n.errorCreatingFile(
          'File may already exist or the destination is not writable',
        ),
      );
      return;
    }

    folderListBloc?.add(FolderListRefresh(currentPath));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (onAfterFileCreated != null) {
        onAfterFileCreated(createdPath);
        return;
      }

      if (inlineRenameController != null && !_isMobilePlatform()) {
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          inlineRenameController.startRename(createdPath);
        });
      }
    });
  }

  static Future<void> _showDesktopNewMenuCustomizationDialog({
    required BuildContext context,
    required List<DesktopNewFileItem> items,
  }) async {
    final preferences = UserPreferences.instance;
    final storedIds = await preferences.getDesktopQuickCreateItemIds();
    final selectedIds = List<String>.from(
      storedIds.isEmpty
          ? DesktopNewFileService.instance.buildDefaultQuickItemIds(items)
          : storedIds,
    );
    final allItems = _buildCustomizationOrder(items, selectedIds);

    if (!context.mounted) {
      return;
    }

    await _showNoAnimationDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Customize New Menu'),
          content: SizedBox(
            width: 460,
            height: 520,
            child: ReorderableListView.builder(
              itemCount: allItems.length,
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final movedItem = allItems.removeAt(oldIndex);
                  allItems.insert(newIndex, movedItem);
                });
              },
              itemBuilder: (itemContext, index) {
                final item = allItems[index];
                final isSelected = selectedIds.contains(item.id);
                return CheckboxListTile(
                  key: ValueKey(item.id),
                  value: isSelected,
                  secondary: Icon(item.icon),
                  title: Text(_desktopNewFileItemLabel(context, item)),
                  subtitle: Text(item.extension.toUpperCase()),
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        if (!selectedIds.contains(item.id)) {
                          selectedIds.add(item.id);
                        }
                      } else {
                        selectedIds.remove(item.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await preferences.clearDesktopQuickCreateItemIds();
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(AppLocalizations.of(context)!.resetSettings),
            ),
            TextButton(
              onPressed: () {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(AppLocalizations.of(context)!.cancel),
            ),
            TextButton(
              onPressed: () async {
                final orderedIds = <String>[];
                for (final item in allItems) {
                  if (selectedIds.contains(item.id)) {
                    orderedIds.add(item.id);
                  }
                }
                await preferences.setDesktopQuickCreateItemIds(orderedIds);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: Text(AppLocalizations.of(context)!.save),
            ),
          ],
        ),
      ),
    );
  }

  static List<DesktopNewFileItem> _buildCustomizationOrder(
    List<DesktopNewFileItem> items,
    List<String> selectedIds,
  ) {
    final itemById = <String, DesktopNewFileItem>{
      for (final item in items) item.id: item,
    };
    final ordered = <DesktopNewFileItem>[];

    for (final id in selectedIds) {
      final item = itemById[id];
      if (item != null) {
        ordered.add(item);
      }
    }

    final remaining = items
        .where((item) => !selectedIds.contains(item.id))
        .toList(growable: false)
      ..sort(
        (a, b) => _desktopNewFileItemSortKey(a)
            .compareTo(_desktopNewFileItemSortKey(b)),
      );

    ordered.addAll(remaining);
    return ordered;
  }

  static String _desktopNewFileItemSortKey(DesktopNewFileItem item) {
    return '${item.extension.toLowerCase()}|${item.id.toLowerCase()}';
  }

  static String _desktopNewFileItemLabel(
    BuildContext context,
    DesktopNewFileItem item,
  ) {
    final l10n = AppLocalizations.of(context)!;
    switch (item.extension.toLowerCase()) {
      case '.txt':
        return l10n.fileTypeTxt;
      case '.rtf':
        return l10n.fileTypeRtf;
      case '.bmp':
        return l10n.fileTypeBmp;
      case '.png':
        return l10n.fileTypePng;
      case '.jpg':
      case '.jpeg':
        return l10n.fileTypeJpeg;
      case '.gif':
        return l10n.fileTypeGif;
      case '.svg':
        return l10n.fileTypeSvg;
      case '.pdf':
        return l10n.fileTypePdf;
      case '.zip':
        return l10n.fileTypeZip;
      case '.rar':
        return l10n.fileTypeRar;
      case '.7z':
        return l10n.fileType7z;
      case '.md':
        return l10n.fileTypeMarkdown;
      case '.json':
        return l10n.fileTypeJson;
      case '.html':
        return l10n.fileTypeHtml;
      case '.css':
        return l10n.fileTypeCss;
      case '.dart':
        return l10n.fileTypeDart;
      case '.py':
        return l10n.fileTypePython;
      case '.js':
        return l10n.fileTypeJavaScript;
      case '.ts':
        return l10n.fileTypeTypeScript;
      case '.java':
        return l10n.fileTypeJava;
      case '.cpp':
        return l10n.fileTypeCpp;
      case '.c':
        return l10n.fileTypeC;
      case '.go':
        return l10n.fileTypeGo;
      case '.rs':
        return l10n.fileTypeRust;
      case '.xml':
        return l10n.fileTypeXml;
      case '.yaml':
        return l10n.fileTypeYaml;
      case '.sh':
        return l10n.fileTypeShell;
      case '.csv':
        return l10n.fileTypeCsv;
      case '.doc':
      case '.docx':
        return l10n.fileTypeWord;
      case '.xls':
      case '.xlsx':
        return l10n.fileTypeExcel;
      case '.ppt':
      case '.pptx':
        return l10n.fileTypePowerPoint;
      case '.odt':
        return l10n.fileTypeLibreDoc;
      case '.ods':
        return l10n.fileTypeLibreSheet;
      case '.odp':
        return l10n.fileTypeLibrePresentation;
      case '.odg':
        return l10n.fileTypeLibreDraw;
      case '.odc':
        return l10n.fileTypeLibreChart;
      case '.odf':
        return l10n.fileTypeLibreFormula;
      case '.wps':
        return l10n.fileTypeWpsDoc;
      case '.et':
        return l10n.fileTypeWpsSheet;
      case '.dps':
        return l10n.fileTypeWpsPresentation;
      case '.gdoc':
        return l10n.fileTypeGoogleDoc;
      case '.gsheet':
        return l10n.fileTypeGoogleSheet;
      case '.gslides':
        return l10n.fileTypeGoogleSlides;
      case '.tar':
        return l10n.fileTypeTar;
      case '.gz':
        return l10n.fileTypeGzip;
      default:
        return l10n.fileTypeWithExtension(
          item.extension.replaceFirst('.', '').toUpperCase(),
        );
    }
  }

  static String _defaultDesktopNewFileBaseName(
    BuildContext context,
    DesktopNewFileItem item,
  ) {
    final label = _desktopNewFileItemLabel(context, item);
    return label
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isMobilePlatform() => Platform.isAndroid || Platform.isIOS;

  static Future<void> _showCreateFolderDialog(
    BuildContext context,
    String currentPath,
    Future<void> Function(String) onCreateFolder,
  ) async {
    if (!context.mounted) return;

    final l10n = AppLocalizations.of(context)!;
    return RouteUtils.showAcrylicDialog(
      context: context,
      builder: (dialogContext) => _CreateFolderDialog(
        title: l10n.createNewFolder,
        labelText: l10n.folderNameLabel,
        cancelLabel: l10n.cancel,
        createLabel: l10n.create,
        onCreateFolder: onCreateFolder,
      ),
    );
  }

  static Future<void> _showCreateFileDialog(
    BuildContext context,
    String currentPath,
    FolderListBloc? folderListBloc,
    InlineRenameController? inlineRenameController,
    ValueChanged<String>? onAfterFileCreated,
  ) async {
    await CreateFileDialog.show(
      context,
      directoryPath: currentPath,
      onAfterFileCreated: onAfterFileCreated,
      inlineRenameController: inlineRenameController,
      folderListBloc: folderListBloc,
    );
  }

  static Future<void> _showFolderProperties(
    BuildContext context,
    String path,
  ) async {
    if (!context.mounted) return;
    final toast = AppToast.capture(context);

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
      _showNoAnimationDialog(
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
                            toast.warning(
                              AppLocalizations.of(context)!
                                  .invalidThumbnailFile,
                            );
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
      toast.error(
        AppLocalizations.of(context)!
            .errorGettingFolderProperties(e.toString()),
      );
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

  static Future<T?> _showNoAnimationDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final dialogContext = navigator.context;
    return showGeneralDialog<T>(
      context: dialogContext,
      barrierDismissible: true,
      barrierLabel:
          MaterialLocalizations.of(dialogContext).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Builder(builder: builder),
        );
      },
    );
  }
}

class _CreateFolderDialog extends StatefulWidget {
  final String title;
  final String labelText;
  final String cancelLabel;
  final String createLabel;
  final Future<void> Function(String) onCreateFolder;

  const _CreateFolderDialog({
    required this.title,
    required this.labelText,
    required this.cancelLabel,
    required this.createLabel,
    required this.onCreateFolder,
  });

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final folderName = _nameController.text.trim();
    if (folderName.isEmpty) {
      return;
    }

    Navigator.of(context).pop();
    await widget.onCreateFolder(folderName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _nameController,
        decoration: InputDecoration(
          labelText: widget.labelText,
          border: const OutlineInputBorder(),
        ),
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.createLabel),
        ),
      ],
    );
  }
}
