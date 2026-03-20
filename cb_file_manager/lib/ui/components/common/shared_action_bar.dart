import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../screens/folder_list/folder_list_state.dart';
import '../../../helpers/core/user_preferences.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/languages/app_localizations.dart';
import '../../utils/grid_zoom_constraints.dart';

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
    int size = currentGridSize.clamp(minGridSize, dynamicMax).toInt();
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(builder: (context, setState) {
          final sliderMax = math.max(minGridSize, dynamicMax).toInt();
          final sliderDivisions = math.max(1, sliderMax - minGridSize).toInt();
          return AlertDialog(
            title: Text(l10n.adjustGridSizeTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: size.toDouble(),
                  min: minGridSize.toDouble(),
                  max: sliderMax.toDouble(),
                  divisions: sliderDivisions,
                  label: l10n.gridSizeLabel(size.round()),
                  onChanged: (double value) {
                    setState(() {
                      size =
                          value.round().clamp(minGridSize, sliderMax).toInt();
                    });
                  },
                ),
                Text(
                  l10n.gridSizeInstructions,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: Text(l10n.cancel.toUpperCase()),
              ),
              TextButton(
                onPressed: () {
                  onApply(size);
                  Navigator.pop(context);
                },
                child: Text(l10n.apply),
              ),
            ],
          );
        });
      },
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

    showDialog(
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
    Function(String)? onGallerySelected,
    String? currentPath,
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
            }
          },
        );
      },
    );
  }

  static List<Widget> buildCommonActions({
    required BuildContext context,
    required VoidCallback onSearchPressed,
    required Function(SortOption) onSortOptionSelected,
    required SortOption currentSortOption,
    required ViewMode viewMode,
    required VoidCallback onViewModeToggled,
    required VoidCallback onRefresh,
    VoidCallback? onGridSizePressed,
    VoidCallback? onColumnSettingsPressed,
    required VoidCallback onSelectionModeToggled,
    VoidCallback? onManageTagsPressed,
    Function(String)? onGallerySelected,
    String? currentPath,
    Function(ViewMode)? onViewModeSelected,
    VoidCallback? onPreviewPaneToggled,
    bool isPreviewPaneVisible = true,
    bool showPreviewModeOption = false,
  }) {
    final l10n = AppLocalizations.of(context)!;
    List<Widget> actions = [];

    // Add search button
    actions.add(
      IconButton(
        icon: const Icon(PhosphorIconsLight.magnifyingGlass),
        tooltip: l10n.searchTooltip,
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

    // Add grid size button if in grid mode
    if ((viewMode == ViewMode.grid || viewMode == ViewMode.gridPreview) &&
        onGridSizePressed != null) {
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
      onGallerySelected: onGallerySelected,
      currentPath: currentPath,
    ));

    return actions;
  }
}
