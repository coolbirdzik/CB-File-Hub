import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cb_file_manager/design_system/primitives/cb_slider.dart';
import 'package:flutter/material.dart';
import '../../screens/folder_list/components/details_columns.dart';
import '../../screens/folder_list/folder_list_state.dart';
import '../../../helpers/core/user_preferences.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/languages/app_localizations.dart';
import '../../utils/grid_zoom_constraints.dart';
import '../../utils/route.dart';
import 'column_chooser_dialog.dart';

class SharedActionBar {
  /// Tạo popup menu item cho các tùy chọn sắp xếp
  static PopupMenuItem<SortOption> buildSortMenuItem(
    BuildContext context,
    SortOption option,
    String label,
    IconData icon,
    SortOption? currentOption,
  ) {
    final theme = Theme.of(context);
    final isActive = option == currentOption;
    return PopupMenuItem<SortOption>(
      value: option,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isActive ? theme.colorScheme.primary : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? theme.colorScheme.primary : null,
              ),
            ),
          ),
          if (isActive)
            Icon(
              _isAscendingSortOption(option)
                  ? PhosphorIconsLight.arrowUp
                  : PhosphorIconsLight.arrowDown,
              color: theme.colorScheme.primary,
              size: 18,
            ),
        ],
      ),
    );
  }

  static bool _isAscendingSortOption(SortOption option) => option.ascending;

  static List<PopupMenuEntry<SortOption>> buildSortMenuItems(
    BuildContext context,
    SortOption? currentOption,
    Set<SortOption> allowedOptions,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final entries = <PopupMenuEntry<SortOption>>[];
    void addGroup(List<PopupMenuItem<SortOption>> group) {
      final visible = group
          .where((item) => allowedOptions.contains(item.value))
          .toList();
      if (visible.isEmpty) return;
      if (entries.isNotEmpty) entries.add(const PopupMenuDivider());
      entries.addAll(visible);
    }

    addGroup([
      buildSortMenuItem(
        context,
        SortOption.nameAsc,
        l10n.sortNameAsc,
        PhosphorIconsLight.fileText,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.nameDesc,
        l10n.sortNameDesc,
        PhosphorIconsLight.fileText,
        currentOption,
      ),
    ]);
    addGroup([
      buildSortMenuItem(
        context,
        SortOption.dateAsc,
        l10n.sortDateModifiedOldest,
        PhosphorIconsLight.calendar,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.dateDesc,
        l10n.sortDateModifiedNewest,
        PhosphorIconsLight.calendar,
        currentOption,
      ),
    ]);
    addGroup([
      buildSortMenuItem(
        context,
        SortOption.dateCreatedAsc,
        l10n.sortDateCreatedOldest,
        PhosphorIconsLight.clock,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.dateCreatedDesc,
        l10n.sortDateCreatedNewest,
        PhosphorIconsLight.clock,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.dateAccessedAsc,
        l10n.sortDateAccessedOldest,
        PhosphorIconsLight.clock,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.dateAccessedDesc,
        l10n.sortDateAccessedNewest,
        PhosphorIconsLight.clock,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.sizeAsc,
        l10n.sortSizeSmallest,
        PhosphorIconsLight.chartBar,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.sizeDesc,
        l10n.sortSizeLargest,
        PhosphorIconsLight.chartBar,
        currentOption,
      ),
    ]);
    addGroup([
      buildSortMenuItem(
        context,
        SortOption.typeAsc,
        l10n.sortTypeAsc,
        PhosphorIconsLight.file,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.typeDesc,
        l10n.sortTypeDesc,
        PhosphorIconsLight.file,
        currentOption,
      ),
    ]);
    addGroup([
      buildSortMenuItem(
        context,
        SortOption.extensionAsc,
        l10n.sortExtensionAsc,
        PhosphorIconsLight.at,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.extensionDesc,
        l10n.sortExtensionDesc,
        PhosphorIconsLight.at,
        currentOption,
      ),
    ]);
    addGroup([
      buildSortMenuItem(
        context,
        SortOption.attributesAsc,
        l10n.sortAttributesAsc,
        PhosphorIconsLight.info,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.attributesDesc,
        l10n.sortAttributesDesc,
        PhosphorIconsLight.info,
        currentOption,
      ),
    ]);
    addGroup([
      buildSortMenuItem(
        context,
        SortOption.pathAsc,
        l10n.sortPathAsc,
        PhosphorIconsLight.path,
        currentOption,
      ),
      buildSortMenuItem(
        context,
        SortOption.pathDesc,
        l10n.sortPathDesc,
        PhosphorIconsLight.path,
        currentOption,
      ),
    ]);
    for (final column in DetailsColumn.values.where((c) => c.isAvailable)) {
      final pair = column.sortOptions;
      if (pair == null || pair.$1.metadataColumn == null) continue;
      addGroup([
        buildSortMenuItem(
          context,
          pair.$1,
          '${column.label(l10n)} ↑',
          column.icon,
          currentOption,
        ),
        buildSortMenuItem(
          context,
          pair.$2,
          '${column.label(l10n)} ↓',
          column.icon,
          currentOption,
        ),
      ]);
    }
    return entries;
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
                    Icon(
                      PhosphorIconsLight.squaresFour,
                      size: 22,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.adjustGridSizeTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // List from largest items (low zoom) to smallest (high zoom) so
              // the first row always means "bigger items" – mirrors the slider.
              for (int i = clampedMax; i >= minGridSize; i--)
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
                      ? Icon(
                          PhosphorIconsLight.check,
                          color: colorScheme.primary,
                          size: 20,
                        )
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
              fontWeight: size == currentSize
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: size == currentSize
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          const Spacer(),
          if (size == currentSize)
            Icon(
              PhosphorIconsLight.check,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
        ],
      ),
    );
  }

  static void showColumnVisibilityDialog(
    BuildContext context, {
    required ColumnVisibility currentVisibility,
    required Function(ColumnVisibility) onApply,
    Map<String, String> additionalColumns = const {},
    Set<String> visibleAdditionalColumns = const {},
    ValueChanged<Set<String>>? onApplyAdditionalColumns,
  }) {
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => ColumnChooserDialog(
        initial: currentVisibility,
        onApply: onApply,
        additionalColumns: additionalColumns,
        visibleAdditionalColumns: visibleAdditionalColumns,
        onApplyAdditionalColumns: onApplyAdditionalColumns,
      ),
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
                      Expanded(child: Text(l10n.allowFileExtensionRename)),
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
                onAllowFileExtensionRenameChanged?.call(
                  !allowFileExtensionRename,
                );
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
    String? refreshTooltip,
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
    bool showDesktopViewModes = false,
    Set<SortOption>? allowedSortOptions,
    bool allowMetadataSorting = false,
    Widget? sortAction,
    Set<ViewMode>? allowedViewModes,
    bool showMoreOptions = true,
    List<PopupMenuEntry<String>>? additionalMoreOptions,
    Function(String)? onAdditionalMoreOptionSelected,
  }) {
    final l10n = AppLocalizations.of(context)!;
    List<Widget> actions = [];
    bool allowsViewMode(ViewMode mode) =>
        allowedViewModes?.contains(mode) ?? true;

    // Add search button
    actions.add(
      IconButton(
        key: const ValueKey('shared-search-action'),
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
      sortAction ??
          PopupMenuButton<SortOption>(
            key: const ValueKey('shared-sort-menu'),
            icon: const Icon(PhosphorIconsLight.sortAscending),
            tooltip: l10n.sortByTooltip,
            offset: const Offset(0, 50),
            initialValue: currentSortOption,
            onSelected: onSortOptionSelected,
            itemBuilder: (context) => buildSortMenuItems(
              context,
              currentSortOption,
              allowedSortOptions ??
                  SortOption.values
                      .where(
                        (option) =>
                            allowMetadataSorting ||
                            option.metadataColumn == null,
                      )
                      .toSet(),
            ),
          ),
    );

    // Add grid size popover if in grid mode
    if (viewMode == ViewMode.grid &&
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
    } else if (viewMode == ViewMode.grid && onGridSizePressed != null) {
      // Legacy fallback
      actions.add(
        IconButton(
          icon: const Icon(PhosphorIconsLight.squaresFour),
          tooltip: l10n.adjustGridSizeTooltip,
          onPressed: onGridSizePressed,
        ),
      );
    }

    if (onPreviewPaneToggled != null) {
      actions.add(
        IconButton(
          icon: const Icon(PhosphorIconsLight.sidebar),
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
        key: const ValueKey('shared-view-mode-menu'),
        icon: const Icon(PhosphorIconsLight.eye),
        tooltip: l10n.viewModeTooltip,
        offset: const Offset(0, 50),
        initialValue: viewMode,
        itemBuilder: (context) => [
          if (allowsViewMode(ViewMode.list))
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
                    Icon(
                      PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          if (allowsViewMode(ViewMode.tiles))
            PopupMenuItem<ViewMode>(
              value: ViewMode.tiles,
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.gridNine,
                    size: 20,
                    color: viewMode == ViewMode.tiles
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.viewModeTiles,
                    style: TextStyle(
                      fontWeight: viewMode == ViewMode.tiles
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: viewMode == ViewMode.tiles
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  const Spacer(),
                  if (viewMode == ViewMode.tiles)
                    Icon(
                      PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          if (allowsViewMode(ViewMode.grid))
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
                    Icon(
                      PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          if (allowsViewMode(ViewMode.details))
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
                    Icon(
                      PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          if (showDesktopViewModes && allowsViewMode(ViewMode.columns))
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
                    Icon(
                      PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
                ],
              ),
            ),
          if (allowsViewMode(ViewMode.tree))
            PopupMenuItem<ViewMode>(
              value: ViewMode.tree,
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.treeView,
                    size: 20,
                    color: viewMode == ViewMode.tree
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.viewModeTree,
                    style: TextStyle(
                      fontWeight: viewMode == ViewMode.tree
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: viewMode == ViewMode.tree
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  const Spacer(),
                  if (viewMode == ViewMode.tree)
                    Icon(
                      PhosphorIconsLight.check,
                      color: Theme.of(context).colorScheme.primary,
                      size: 20,
                    ),
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
        key: const ValueKey('shared-refresh-action'),
        icon: const Icon(PhosphorIconsLight.arrowsClockwise),
        tooltip: refreshTooltip ?? l10n.refreshTooltip,
        onPressed: onRefresh,
      ),
    );

    // Add more options menu
    if (showMoreOptions) {
      actions.add(
        buildMoreOptionsMenu(
          onSelectionModeToggled: onSelectionModeToggled,
          onManageTagsPressed: onManageTagsPressed,
          allowFileExtensionRename: allowFileExtensionRename,
          onAllowFileExtensionRenameChanged: onAllowFileExtensionRenameChanged,
          onGallerySelected: onGallerySelected,
          currentPath: currentPath,
          additionalMoreOptions: additionalMoreOptions,
          onAdditionalMoreOptionSelected: onAdditionalMoreOptionSelected,
        ),
      );
    }
    return actions;
  }
}

/// Slider widget rendered inside a PopupMenu popover for grid size control.
/// Uses its own state so it can update reactively while the menu stays open.
/// Inline slider widget used inside a [PopupMenuButton] to adjust grid column count.
/// Exposed publicly so other screens (e.g. album detail) can reuse the same UI.
class GridSizeSliderMenu extends StatefulWidget {
  const GridSizeSliderMenu({
    super.key,
    required this.currentValue,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
  });

  final int currentValue;
  final int minValue;
  final int maxValue;
  final Function(int) onChanged;

  @override
  State<GridSizeSliderMenu> createState() => _GridSizeSliderMenuState();
}

class _GridSizeSliderMenuState extends State<GridSizeSliderMenu> {
  // Internal storage is the raw gridZoomLevel (higher = more columns = smaller
  // items). The slider is displayed in "item-size space" where the mapping is
  // inverted: displayValue = minValue + maxValue - gridZoomLevel so that
  // dragging RIGHT increases item size (fewer columns).
  late int _zoomValue;

  int get _displayValue => widget.minValue + widget.maxValue - _zoomValue;

  int _displayToZoom(int display) =>
      widget.minValue + widget.maxValue - display;

  @override
  void initState() {
    super.initState();
    _zoomValue = widget.currentValue
        .clamp(widget.minValue, widget.maxValue)
        .toInt();
  }

  @override
  void didUpdateWidget(GridSizeSliderMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentValue != oldWidget.currentValue) {
      _zoomValue = widget.currentValue
          .clamp(widget.minValue, widget.maxValue)
          .toInt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final divisions = math.max(1, widget.maxValue - widget.minValue);
    final displayVal = _displayValue;

    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon + current display value (bigger number = bigger items)
            Row(
              children: [
                Icon(
                  PhosphorIconsLight.squaresFour,
                  size: 18,
                  color: colorScheme.primary,
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$displayVal',
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
            // Slider: left = smallest items (many columns), right = largest items (few columns).
            Row(
              children: [
                Icon(
                  PhosphorIconsLight.minus,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                Expanded(
                  child: Semantics(
                    container: true,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: CbSlider(
                        value: displayVal.toDouble(),
                        min: widget.minValue.toDouble(),
                        max: widget.maxValue.toDouble(),
                        divisions: divisions,
                        onChanged: (v) {
                          final newDisplay = v.round();
                          if (newDisplay != displayVal) {
                            final newZoom = _displayToZoom(newDisplay);
                            setState(() => _zoomValue = newZoom);
                            widget.onChanged(newZoom);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                Icon(
                  PhosphorIconsLight.plus,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
