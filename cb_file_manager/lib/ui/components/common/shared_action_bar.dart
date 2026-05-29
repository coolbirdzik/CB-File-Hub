import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../screens/folder_list/folder_list_state.dart';
import '../../../helpers/core/user_preferences.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/languages/app_localizations.dart';
import '../../utils/grid_zoom_constraints.dart';
import '../../utils/route.dart';

class SharedActionBar {
  /// Tạo popup menu item cho các tùy chọn sắp xếp
  static PopupMenuItem<SortOption> buildSortMenuItem(
    BuildContext context,
    SortOption option,
    String label,
    IconData icon,
    SortOption currentOption,
  ) {
    return PopupMenuItem<SortOption>(
      value: option,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: option == currentOption
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight:
                  option == currentOption ? FontWeight.bold : FontWeight.normal,
              color: option == currentOption
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          const Spacer(),
          if (option == currentOption)
            Icon(PhosphorIconsLight.check,
                color: Theme.of(context).colorScheme.primary, size: 20),
        ],
      ),
    );
  }

  /// Shows grid size selector as a modal bottom sheet (for mobile callers).
  static void showGridSizeDialog(
    BuildContext context, {
    required int currentGridSize,
    required Function(int) onApply,
    GridSizeMode sizeMode = GridSizeMode.referenceWidth,
    int minGridSize = UserPreferences.minGridZoomLevel,
    int maxGridSize = UserPreferences.maxGridZoomLevel,
    double minItemWidth = GridZoomConstraints.defaultMinItemWidth,
    double gridSpacing = GridZoomConstraints.defaultGridSpacing,
    double referenceWidth = GridZoomConstraints.defaultReferenceWidth,
    double gridMinWidth = GridZoomConstraints.defaultGridMinWidth,
  }) {
    final int dynamicMax = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: sizeMode,
      minItemWidth: minItemWidth,
      spacing: gridSpacing,
      referenceWidth: referenceWidth,
      gridMinWidth: gridMinWidth,
      minValue: minGridSize,
      maxValue: maxGridSize,
    );
    final int clampedMax = math.min(maxGridSize, dynamicMax);
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(PhosphorIconsLight.squaresFour,
                        size: 22, color: colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(
                      l10n.adjustGridSizeTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (int i = minGridSize; i <= clampedMax; i++)
                ListTile(
                  leading: Icon(
                    PhosphorIconsLight.squaresFour,
                    size: 20,
                    color: i == currentGridSize ? colorScheme.primary : null,
                  ),
                  title: Text(
                    l10n.gridSizeLabel(i),
                    style: TextStyle(
                      fontWeight: i == currentGridSize
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: i == currentGridSize ? colorScheme.primary : null,
                    ),
                  ),
                  trailing: i == currentGridSize
                      ? Icon(PhosphorIconsLight.check,
                          color: colorScheme.primary, size: 20)
                      : null,
                  onTap: () {
                    onApply(i);
                    Navigator.pop(context);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Builds a PopupMenuItem for grid size selection (used in popover).
  static PopupMenuItem<int> buildGridSizeMenuItem(
    BuildContext context,
    int size,
    int currentSize,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuItem<int>(
      value: size,
      child: Row(
        children: [
          Icon(
            PhosphorIconsLight.squaresFour,
            size: 20,
            color: size == currentSize
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            l10n.gridSizeLabel(size),
            style: TextStyle(
              fontWeight:
                  size == currentSize ? FontWeight.bold : FontWeight.normal,
              color: size == currentSize
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          const Spacer(),
          if (size == currentSize)
            Icon(PhosphorIconsLight.check,
                color: Theme.of(context).colorScheme.primary, size: 20),
        ],
      ),
    );
  }

  static void showColumnVisibilityDialog(
    BuildContext context, {
    required ColumnVisibility currentVisibility,
    required Function(ColumnVisibility) onApply,
  }) {
    final l10n = AppLocalizations.of(context)!;
    // Create a mutable copy of the current visibility
    bool size = currentVisibility.size;
    bool type = currentVisibility.type;
    bool dateModified = currentVisibility.dateModified;
    bool dateCreated = currentVisibility.dateCreated;
    bool attributes = currentVisibility.attributes;
    bool dateAccessed = currentVisibility.dateAccessed;
    bool extension = currentVisibility.extension;
    bool path = currentVisibility.path;
    bool tags = currentVisibility.tags;
    bool dimensions = currentVisibility.dimensions;
    bool duration = currentVisibility.duration;
    bool itemCount = currentVisibility.itemCount;

    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(PhosphorIconsLight.columns, size: 24),
                  const SizedBox(width: 8),
                  Text(l10n.columnVisibilityTitle),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        l10n.columnVisibilityInstructions,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    CheckboxListTile(
                      title: Text(l10n.columnSize),
                      subtitle: Text(l10n.columnSizeDescription),
                      value: size,
                      onChanged: (value) {
                        setState(() {
                          size = value ?? true;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.hardDrives),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnType),
                      subtitle: Text(l10n.columnTypeDescription),
                      value: type,
                      onChanged: (value) {
                        setState(() {
                          type = value ?? true;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.fileText),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnDateModified),
                      subtitle: Text(l10n.columnDateModifiedDescription),
                      value: dateModified,
                      onChanged: (value) {
                        setState(() {
                          dateModified = value ?? true;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.arrowsClockwise),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnDateCreated),
                      subtitle: Text(l10n.columnDateCreatedDescription),
                      value: dateCreated,
                      onChanged: (value) {
                        setState(() {
                          dateCreated = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.calendar),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnAttributes),
                      subtitle: Text(l10n.columnAttributesDescription),
                      value: attributes,
                      onChanged: (value) {
                        setState(() {
                          attributes = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.info),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnDateAccessed),
                      subtitle: Text(l10n.columnDateAccessedDescription),
                      value: dateAccessed,
                      onChanged: (value) {
                        setState(() {
                          dateAccessed = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.clock),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnExtension),
                      subtitle: Text(l10n.columnExtensionDescription),
                      value: extension,
                      onChanged: (value) {
                        setState(() {
                          extension = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.fileText),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnPath),
                      subtitle: Text(l10n.columnPathDescription),
                      value: path,
                      onChanged: (value) {
                        setState(() {
                          path = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.path),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnTags),
                      subtitle: Text(l10n.columnTagsDescription),
                      value: tags,
                      onChanged: (value) {
                        setState(() {
                          tags = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.tag),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnDimensions),
                      subtitle: Text(l10n.columnDimensionsDescription),
                      value: dimensions,
                      onChanged: (value) {
                        setState(() {
                          dimensions = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.frameCorners),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnDuration),
                      subtitle: Text(l10n.columnDurationDescription),
                      value: duration,
                      onChanged: (value) {
                        setState(() {
                          duration = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.timer),
                      dense: true,
                    ),
                    const Divider(height: 1),
                    CheckboxListTile(
                      title: Text(l10n.columnItemCount),
                      subtitle: Text(l10n.columnItemCountDescription),
                      value: itemCount,
                      onChanged: (value) {
                        setState(() {
                          itemCount = value ?? false;
                        });
                      },
                      secondary: const Icon(PhosphorIconsLight.listNumbers),
                      dense: true,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(l10n.cancel.toUpperCase()),
                ),
                ElevatedButton.icon(
                  icon: const Icon(PhosphorIconsLight.check),
                  label: Text(l10n.apply),
                  onPressed: () {
                    final newVisibility = ColumnVisibility(
                      size: size,
                      type: type,
                      dateModified: dateModified,
                      dateCreated: dateCreated,
                      attributes: attributes,
                      dateAccessed: dateAccessed,
                      extension: extension,
                      path: path,
                      tags: tags,
                      dimensions: dimensions,
                      duration: duration,
                      itemCount: itemCount,
                    );
                    onApply(newVisibility);
                    Navigator.pop(context);
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Widget buildMoreOptionsMenu({
    required VoidCallback onSelectionModeToggled,
    VoidCallback? onManageTagsPressed,
    bool allowFileExtensionRename = false,
    ValueChanged<bool>? onAllowFileExtensionRenameChanged,
    Function(String)? onGallerySelected,
    String? currentPath,
    List<PopupMenuEntry<String>>? additionalMoreOptions,
    Function(String)? onAdditionalMoreOptionSelected,
  }) {
    return Builder(
      builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return PopupMenuButton<String>(
          icon: const Icon(PhosphorIconsLight.dotsThreeVertical),
          tooltip: l10n.moreOptionsTooltip,
          offset: const Offset(0, 50),
          itemBuilder: (context) {
            List<PopupMenuEntry<String>> items = [
              PopupMenuItem<String>(
                value: 'selection_mode',
                child: Row(
                  children: [
                    const Icon(PhosphorIconsLight.checkSquare, size: 20),
                    const SizedBox(width: 10),
                    Text(l10n.selectMultipleFiles),
                  ],
                ),
              ),
            ];

            // Only show tag management if the callback is provided
            if (onManageTagsPressed != null) {
              items.add(
                PopupMenuItem<String>(
                  value: 'manage_tags',
                  child: Row(
                    children: [
                      const Icon(PhosphorIconsLight.bookmark, size: 20),
                      const SizedBox(width: 10),
                      Text(l10n.manageTags),
                    ],
                  ),
                ),
              );
            }

            if (onAllowFileExtensionRenameChanged != null) {
              items.add(
                PopupMenuItem<String>(
                  value: 'toggle_file_extension_rename',
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIconsLight.textAa,
                        size: 20,
                        color: allowFileExtensionRename
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(l10n.allowFileExtensionRename),
                      ),
                      if (allowFileExtensionRename)
                        Icon(
                          PhosphorIconsLight.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              );
            }

            if (additionalMoreOptions != null &&
                additionalMoreOptions.isNotEmpty) {
              items.addAll(additionalMoreOptions);
            }

            return items;
          },
          onSelected: (String value) {
            switch (value) {
              case 'selection_mode':
                onSelectionModeToggled();
                break;
              case 'manage_tags':
                if (onManageTagsPressed != null) {
                  onManageTagsPressed();
                }
                break;
              case 'toggle_file_extension_rename':
                onAllowFileExtensionRenameChanged
                    ?.call(!allowFileExtensionRename);
                break;
              default:
                onAdditionalMoreOptionSelected?.call(value);
                break;
            }
          },
        );
      },
    );
  }

  static List<Widget> buildCommonActions({
    required BuildContext context,
    required VoidCallback onSearchPressed,
    bool isSearchActive = false,
    required Function(SortOption) onSortOptionSelected,
    required SortOption currentSortOption,
    required ViewMode viewMode,
    required VoidCallback onViewModeToggled,
    required VoidCallback onRefresh,
    @Deprecated('Use currentGridZoomLevel + onGridZoomChanged instead')
    VoidCallback? onGridSizePressed,
    int? currentGridZoomLevel,
    Function(int)? onGridZoomChanged,
    int gridMinSize = UserPreferences.minGridZoomLevel,
    int gridMaxSize = UserPreferences.maxGridZoomLevel,
    VoidCallback? onColumnSettingsPressed,
    required VoidCallback onSelectionModeToggled,
    VoidCallback? onManageTagsPressed,
    bool allowFileExtensionRename = false,
    ValueChanged<bool>? onAllowFileExtensionRenameChanged,
    Function(String)? onGallerySelected,
    String? currentPath,
    Function(ViewMode)? onViewModeSelected,
    VoidCallback? onPreviewPaneToggled,
    bool isPreviewPaneVisible = true,
    bool showPreviewModeOption = false,
    List<PopupMenuEntry<String>>? additionalMoreOptions,
    Function(String)? onAdditionalMoreOptionSelected,
  }) {
    final l10n = AppLocalizations.of(context)!;
    List<Widget> actions = [];

    // Add search button
    actions.add(
      IconButton(
        icon: Icon(
          isSearchActive
              ? PhosphorIconsLight.x
              : PhosphorIconsLight.magnifyingGlass,
        ),
        tooltip: isSearchActive ? l10n.close : l10n.searchTooltip,
        onPressed: onSearchPressed,
      ),
    );

    // Add sort button
    actions.add(
      PopupMenuButton<SortOption>(
        icon: const Icon(PhosphorIconsLight.funnelSimple),
        tooltip: l10n.sortByTooltip,
        offset: const Offset(0, 50),
        initialValue: currentSortOption,
        onSelected: onSortOptionSelected,
        itemBuilder: (context) => [
          buildSortMenuItem(context, SortOption.nameAsc, l10n.sortNameAsc,
              PhosphorIconsLight.fileText, currentSortOption),
          buildSortMenuItem(context, SortOption.nameDesc, l10n.sortNameDesc,
              PhosphorIconsLight.fileText, currentSortOption),
          const PopupMenuDivider(),
          buildSortMenuItem(
              context,
              SortOption.dateAsc,
              l10n.sortDateModifiedOldest,
              PhosphorIconsLight.calendar,
              currentSortOption),
          buildSortMenuItem(
              context,
              SortOption.dateDesc,
              l10n.sortDateModifiedNewest,
              PhosphorIconsLight.calendar,
              currentSortOption),
          const PopupMenuDivider(),
          buildSortMenuItem(
              context,
              SortOption.dateCreatedAsc,
              l10n.sortDateCreatedOldest,
              PhosphorIconsLight.clock,
              currentSortOption),
          buildSortMenuItem(
              context,
              SortOption.dateCreatedDesc,
              l10n.sortDateCreatedNewest,
              PhosphorIconsLight.clock,
              currentSortOption),
          buildSortMenuItem(context, SortOption.sizeAsc, l10n.sortSizeSmallest,
              PhosphorIconsLight.chartBar, currentSortOption),
          buildSortMenuItem(context, SortOption.sizeDesc, l10n.sortSizeLargest,
              PhosphorIconsLight.chartBar, currentSortOption),
          const PopupMenuDivider(),
          buildSortMenuItem(context, SortOption.typeAsc, l10n.sortTypeAsc,
              PhosphorIconsLight.file, currentSortOption),
          buildSortMenuItem(context, SortOption.typeDesc, l10n.sortTypeDesc,
              PhosphorIconsLight.file, currentSortOption),
          const PopupMenuDivider(),
          buildSortMenuItem(context, SortOption.extensionAsc,
              l10n.sortExtensionAsc, PhosphorIconsLight.at, currentSortOption),
          buildSortMenuItem(context, SortOption.extensionDesc,
              l10n.sortExtensionDesc, PhosphorIconsLight.at, currentSortOption),
          const PopupMenuDivider(),
          buildSortMenuItem(
              context,
              SortOption.attributesAsc,
              l10n.sortAttributesAsc,
              PhosphorIconsLight.info,
              currentSortOption),
          buildSortMenuItem(
              context,
              SortOption.attributesDesc,
              l10n.sortAttributesDesc,
              PhosphorIconsLight.info,
              currentSortOption),
        ],
      ),
    );

    // Add grid size popover if in grid mode
    if ((viewMode == ViewMode.grid || viewMode == ViewMode.gridPreview) &&
        currentGridZoomLevel != null &&
        onGridZoomChanged != null) {
      final bool isMobile = Platform.isAndroid || Platform.isIOS;
      final int dynamicMax = GridZoomConstraints.maxGridSizeForContext(
        context,
        minValue: gridMinSize,
        maxValue: gridMaxSize,
      );
      final int clampedMax = math.min(gridMaxSize, dynamicMax);
      if (isMobile) {
        // Mobile: button that opens bottom sheet
        actions.add(
          IconButton(
            icon: const Icon(PhosphorIconsLight.squaresFour),
            tooltip: l10n.adjustGridSizeTooltip,
            onPressed: () => showGridSizeDialog(
              context,
              currentGridSize: currentGridZoomLevel,
              onApply: onGridZoomChanged,
            ),
          ),
        );
      } else {
        // Desktop: slider popover like sort/viewmode
        actions.add(
          PopupMenuButton<void>(
            icon: const Icon(PhosphorIconsLight.squaresFour),
            tooltip: l10n.adjustGridSizeTooltip,
            offset: const Offset(0, 50),
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                enabled: false,
                padding: EdgeInsets.zero,
                child: GridSizeSliderMenu(
                  currentValue: currentGridZoomLevel,
                  minValue: gridMinSize,
                  maxValue: clampedMax,
                  onChanged: onGridZoomChanged,
                ),
              ),
            ],
          ),
        );
      }
    } else if ((viewMode == ViewMode.grid ||
            viewMode == ViewMode.gridPreview) &&
        onGridSizePressed != null) {
      // Legacy fallback
      actions.add(
        IconButton(
          icon: const Icon(PhosphorIconsLight.squaresFour),
          tooltip: l10n.adjustGridSizeTooltip,
          onPressed: onGridSizePressed,
        ),
      );
    }

    if (viewMode == ViewMode.gridPreview && onPreviewPaneToggled != null) {
      actions.add(
        IconButton(
          icon: const Icon(PhosphorIconsLight.splitVertical),
          tooltip: isPreviewPaneVisible ? l10n.hidePreview : l10n.showPreview,
          onPressed: onPreviewPaneToggled,
        ),
      );
    }

    // Add column settings button if in details mode
    if (viewMode == ViewMode.details && onColumnSettingsPressed != null) {
      actions.add(
        IconButton(
          icon: const Icon(PhosphorIconsLight.layout),
          tooltip: l10n.columnSettingsTooltip,
          onPressed: onColumnSettingsPressed,
        ),
      );
    }

    // Add view mode toggle button
    actions.add(
      PopupMenuButton<ViewMode>(
        icon: const Icon(PhosphorIconsLight.eye),
        tooltip: l10n.viewModeTooltip,
        offset: const Offset(0, 50),
        initialValue: viewMode,
        itemBuilder: (context) => [
          PopupMenuItem<ViewMode>(
            value: ViewMode.list,
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.list,
                  size: 20,
                  color: viewMode == ViewMode.list
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.viewModeList,
                  style: TextStyle(
                    fontWeight: viewMode == ViewMode.list
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: viewMode == ViewMode.list
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                const Spacer(),
                if (viewMode == ViewMode.list)
                  Icon(PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary, size: 20),
              ],
            ),
          ),
          PopupMenuItem<ViewMode>(
            value: ViewMode.grid,
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.squaresFour,
                  size: 20,
                  color: viewMode == ViewMode.grid
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.viewModeGrid,
                  style: TextStyle(
                    fontWeight: viewMode == ViewMode.grid
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: viewMode == ViewMode.grid
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                const Spacer(),
                if (viewMode == ViewMode.grid)
                  Icon(PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary, size: 20),
              ],
            ),
          ),
          if (showPreviewModeOption)
            PopupMenuItem<ViewMode>(
              value: ViewMode.gridPreview,
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.splitVertical,
                    size: 20,
                    color: viewMode == ViewMode.gridPreview
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.viewModeGridPreview,
                    style: TextStyle(
                      fontWeight: viewMode == ViewMode.gridPreview
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: viewMode == ViewMode.gridPreview
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  const Spacer(),
                  if (viewMode == ViewMode.gridPreview)
                    Icon(PhosphorIconsLight.check,
                        color: Theme.of(context).colorScheme.primary, size: 20),
                ],
              ),
            ),
          PopupMenuItem<ViewMode>(
            value: ViewMode.details,
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.listBullets,
                  size: 20,
                  color: viewMode == ViewMode.details
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.viewModeDetails,
                  style: TextStyle(
                    fontWeight: viewMode == ViewMode.details
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: viewMode == ViewMode.details
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                const Spacer(),
                if (viewMode == ViewMode.details)
                  Icon(PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary, size: 20),
              ],
            ),
          ),
          if (showPreviewModeOption)
            PopupMenuItem<ViewMode>(
              value: ViewMode.columns,
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.columns,
                    size: 20,
                    color: viewMode == ViewMode.columns
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.viewModeColumns,
                    style: TextStyle(
                      fontWeight: viewMode == ViewMode.columns
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: viewMode == ViewMode.columns
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  const Spacer(),
                  if (viewMode == ViewMode.columns)
                    Icon(PhosphorIconsLight.check,
                        color: Theme.of(context).colorScheme.primary, size: 20),
                ],
              ),
            ),
        ],
        onSelected: (ViewMode selectedMode) {
          if (selectedMode != viewMode) {
            if (onViewModeSelected != null) {
              onViewModeSelected(selectedMode);
            } else {
              onViewModeToggled();
            }
          }
        },
      ),
    );

    // Add refresh button
    actions.add(
      IconButton(
        icon: const Icon(PhosphorIconsLight.arrowsClockwise),
        tooltip: l10n.refreshTooltip,
        onPressed: onRefresh,
      ),
    );

    // Add more options menu
    actions.add(buildMoreOptionsMenu(
      onSelectionModeToggled: onSelectionModeToggled,
      onManageTagsPressed: onManageTagsPressed,
      allowFileExtensionRename: allowFileExtensionRename,
      onAllowFileExtensionRenameChanged: onAllowFileExtensionRenameChanged,
      onGallerySelected: onGallerySelected,
      currentPath: currentPath,
      additionalMoreOptions: additionalMoreOptions,
      onAdditionalMoreOptionSelected: onAdditionalMoreOptionSelected,
    ));

    return actions;
  }
}

/// Slider widget rendered inside a PopupMenu popover for grid size control.
/// Uses its own state so it can update reactively while the menu stays open.
/// Inline slider widget used inside a [PopupMenuButton] to adjust grid column count.
/// Exposed publicly so other screens (e.g. album detail) can reuse the same UI.
class GridSizeSliderMenu extends StatefulWidget {
  const GridSizeSliderMenu({
    Key? key,
    required this.currentValue,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  }) : super(key: key);

  final int currentValue;
  final int minValue;
  final int maxValue;
  final Function(int) onChanged;

  @override
  State<GridSizeSliderMenu> createState() => _GridSizeSliderMenuState();
}

class _GridSizeSliderMenuState extends State<GridSizeSliderMenu> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.currentValue.clamp(widget.minValue, widget.maxValue);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final divisions = math.max(1, widget.maxValue - widget.minValue);

    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon + current value
            Row(
              children: [
                Icon(PhosphorIconsLight.squaresFour,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.adjustGridSizeTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_value',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Horizontal slider with min/max icons
            Row(
              children: [
                Icon(PhosphorIconsLight.minus,
                    size: 14, color: colorScheme.onSurfaceVariant),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                    ),
                    child: Slider(
                      value: _value.toDouble(),
                      min: widget.minValue.toDouble(),
                      max: widget.maxValue.toDouble(),
                      divisions: divisions,
                      onChanged: (v) {
                        final newVal = v.round();
                        if (newVal != _value) {
                          setState(() => _value = newVal);
                          widget.onChanged(newVal);
                        }
                      },
                    ),
                  ),
                ),
                Icon(PhosphorIconsLight.plus,
                    size: 14, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
