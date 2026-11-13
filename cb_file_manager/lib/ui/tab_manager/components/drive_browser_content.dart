import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'drive_avatar.dart';

enum DriveDetailsColumn { name, path, type, filesystem, total, free, used }

String driveColumnLabel(BuildContext context, DriveDetailsColumn column) =>
    switch (column) {
      DriveDetailsColumn.name => context.tr.columnName,
      DriveDetailsColumn.path => context.tr.filePath,
      DriveDetailsColumn.type => context.tr.driveType,
      DriveDetailsColumn.filesystem => context.tr.driveFilesystem,
      DriveDetailsColumn.total => context.tr.driveTotal,
      DriveDetailsColumn.free => context.tr.driveFree,
      DriveDetailsColumn.used => context.tr.driveUsed,
    };

/// Shared storage presentation. Hierarchical modes use the file browser's
/// existing tree and Miller columns, supplied by the owning DriveView.
class DriveBrowserContent extends StatelessWidget {
  final List<DriveInfo> drives;
  final List<DriveInfo>? availableDrives;
  final DriveGroup? groupFilter;
  final ValueChanged<DriveGroup?>? onGroupFilterChanged;
  final ViewMode viewMode;
  final int gridZoom;
  final Set<String> selectedPaths;
  final String? focusedPath;
  final bool showProperties;
  final ValueChanged<DriveInfo> onSelect;
  final ValueChanged<DriveInfo> onOpen;
  final ValueChanged<DriveInfo>? onOpenInNewTab;
  final void Function(DriveInfo, Offset) onMenu;
  final ValueChanged<SortOption> onSort;
  final SortOption sortOption;
  final Widget Function() hierarchyBuilder;
  final bool selectOnPointerDown;
  final Set<DriveDetailsColumn> visibleColumns;

  const DriveBrowserContent({
    super.key,
    required this.drives,
    this.availableDrives,
    this.groupFilter,
    this.onGroupFilterChanged,
    required this.viewMode,
    required this.gridZoom,
    required this.selectedPaths,
    required this.focusedPath,
    required this.showProperties,
    required this.onSelect,
    required this.onOpen,
    this.onOpenInNewTab,
    required this.onMenu,
    required this.onSort,
    required this.sortOption,
    required this.hierarchyBuilder,
    this.selectOnPointerDown = true,
    this.visibleColumns = const {
      DriveDetailsColumn.name,
      DriveDetailsColumn.path,
      DriveDetailsColumn.type,
      DriveDetailsColumn.filesystem,
      DriveDetailsColumn.total,
      DriveDetailsColumn.free,
      DriveDetailsColumn.used,
    },
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l10n = context.tr;
    final known = drives.where(
      (d) => d.kind != DriveKind.wsl && d.space.hasDetails,
    );
    final free = known.fold<int>(0, (n, d) => n + d.space.freeBytes);
    final total = known.fold<int>(0, (n, d) => n + d.space.totalBytes);
    final selected = drives.where((d) => d.path == focusedPath).firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 650;
        final showInspector = showProperties && !narrow;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(narrow ? 16 : 28, 24, 20, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!narrow) ...[
                    CbSurface(
                      width: 48,
                      height: 48,
                      radius: 12,
                      color: c.accent.tint,
                      child: Icon(
                        PhosphorIconsLight.hardDrives,
                        size: 28,
                        color: c.accent.text,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.drives,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.6,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l10n.driveLocationCount(drives.length),
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (total > 0)
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${FormatUtils.formatFileSize(free)} ${l10n.driveFree.toLowerCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w500,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (!narrow) ...[
                            const SizedBox(height: 6),
                            Text(
                              '${l10n.driveTotal}: ${FormatUtils.formatFileSize(total)}',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (onGroupFilterChanged != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _groupFilterChip(
                      context,
                      null,
                      l10n.all,
                      (availableDrives ?? drives).length,
                    ),
                    for (final group in [
                      DriveGroup.fixed,
                      DriveGroup.removable,
                      DriveGroup.network,
                      DriveGroup.wsl,
                      DriveGroup.other,
                    ])
                      if ((availableDrives ?? drives).any(
                        (d) => d.group == group,
                      ))
                        _groupFilterChip(
                          context,
                          group,
                          _groupLabel(context, group),
                          (availableDrives ?? drives)
                              .where((d) => d.group == group)
                              .length,
                        ),
                  ],
                ),
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: showProperties && narrow
                        ? DriveInspector(drive: selected)
                        : _collection(context),
                  ),
                  if (showInspector)
                    SizedBox(
                      key: const ValueKey('drive-inspector'),
                      width: 270,
                      child: DriveInspector(drive: selected),
                    ),
                ],
              ),
            ),
            if (selectedPaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 10),
                child: Text(
                  l10n.itemsSelected(selectedPaths.length),
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _collection(BuildContext context) {
    if (viewMode == ViewMode.tree || viewMode == ViewMode.columns) {
      return hierarchyBuilder();
    }
    if (viewMode == ViewMode.details) return _details(context);
    final list = viewMode == ViewMode.list;
    final tiles = viewMode == ViewMode.tiles;
    final groups = <DriveGroup, List<DriveInfo>>{};
    for (final drive in drives) {
      groups.putIfAbsent(drive.group, () => []).add(drive);
    }
    final order = [
      DriveGroup.fixed,
      DriveGroup.removable,
      DriveGroup.network,
      DriveGroup.wsl,
      DriveGroup.other,
    ];
    if (sortOption == SortOption.typeDesc) {
      order.sort(
        (a, b) =>
            DriveInfo.groupSortOrder(b).compareTo(DriveInfo.groupSortOrder(a)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = tiles
            ? 340.0
            : (960 / gridZoom.clamp(2, 8)).clamp(180, 420).toDouble();
        final columns = ((constraints.maxWidth - 28) / (targetWidth + 12))
            .floor()
            .clamp(1, 20);
        return CustomScrollView(
          key: ValueKey('drive-mode-${viewMode.name}'),
          slivers: [
            for (final group in order)
              if (groups.containsKey(group)) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
                    child: Row(
                      children: [
                        Icon(
                          _groupIcon(group),
                          size: 17,
                          color: context.cbColors.icon,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          _groupLabel(context, group),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.cbColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${groups[group]!.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.cbColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Divider(
                            height: 1,
                            color: context.cbColors.strokeSubtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  sliver: list
                      ? SliverList.builder(
                          itemCount: groups[group]!.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: _entry(
                              context,
                              groups[group]![i],
                              compact: true,
                            ),
                          ),
                        )
                      : SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: columns,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                mainAxisExtent: tiles ? 100 : 190,
                              ),
                          itemCount: groups[group]!.length,
                          itemBuilder: (context, i) => _entry(
                            context,
                            groups[group]![i],
                            compact: tiles,
                            tile: tiles,
                          ),
                        ),
                ),
              ],
          ],
        );
      },
    );
  }

  Widget _groupFilterChip(
    BuildContext context,
    DriveGroup? group,
    String label,
    int count,
  ) => CbSurface(
    key: ValueKey('drive-filter-${group?.name ?? 'all'}'),
    radius: 7,
    selected: groupFilter == group,
    onPressed: () => onGroupFilterChanged!(group),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          group == null ? PhosphorIconsLight.squaresFour : _groupIcon(group),
          size: 15,
          color: context.cbColors.icon,
        ),
        const SizedBox(width: 7),
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 7),
        Text(
          '$count',
          style: TextStyle(fontSize: 11, color: context.cbColors.textSecondary),
        ),
      ],
    ),
  );

  Widget _entry(
    BuildContext context,
    DriveInfo drive, {
    required bool compact,
    bool tile = false,
  }) {
    final c = context.cbColors;
    final selected = selectedPaths.contains(drive.path);
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        onTertiaryTapUp: onOpenInNewTab == null
            ? null
            : (_) => onOpenInNewTab!(drive),
        onSecondaryTapDown: (event) => onMenu(drive, event.globalPosition),
        onLongPressStart: (event) => onMenu(drive, event.globalPosition),
        child: CbSurface(
          key: ValueKey('drive-entry-${drive.path}'),
          selected: selected,
          radius: compact ? 8 : 12,
          color: compact && !tile ? Colors.transparent : null,
          onPressed: () => onSelect(drive),
          pressOnPointerDown: selectOnPointerDown,
          onDoubleTap: () => onOpen(drive),
          onActivate: () => onOpen(drive),
          descendantsAreFocusable: true,
          semanticLabel: '${drive.displayName}, ${drive.path}',
          padding: EdgeInsets.all(compact ? 12 : 18),
          child: compact
              ? Row(
                  children: [
                    _driveIcon(context, drive, 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _name(context, drive),
                          const SizedBox(height: 4),
                          Text(
                            '${drive.path}  ·  ${drive.filesystem.isEmpty ? driveKindLabel(context, drive) : drive.filesystem}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          if (tile) ...[
                            const SizedBox(height: 10),
                            DriveCapacityBar(space: drive.space),
                          ],
                        ],
                      ),
                    ),
                    if (!tile && constraints.maxWidth >= 520) ...[
                      const SizedBox(width: 12),
                      SizedBox(width: 140, child: _spaceLabel(context, drive)),
                    ],
                    _menu(context, drive),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _driveIcon(context, drive, 48),
                        const Spacer(),
                        _menu(context, drive),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _name(context, drive),
                    const SizedBox(height: 4),
                    Text(
                      '${drive.path}  ·  ${driveKindLabel(context, drive)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                    const Spacer(),
                    if (drive.kind == DriveKind.wsl)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: CbButton(
                          label: context.tr.open,
                          icon: PhosphorIconsLight.folderOpen,
                          variant: CbButtonVariant.ghost,
                          size: CbButtonSize.sm,
                          onPressed: () => onOpen(drive),
                        ),
                      )
                    else ...[
                      DriveCapacityBar(space: drive.space),
                      const SizedBox(height: 8),
                      _spaceLabel(context, drive),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _name(BuildContext context, DriveInfo drive) => Text(
    drive.displayName,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: context.cbColors.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _spaceLabel(BuildContext context, DriveInfo drive) => Text(
    drive.space.hasDetails
        ? '${FormatUtils.formatFileSize(drive.space.freeBytes)} ${context.tr.driveFree.toLowerCase()}'
        : drive.kind == DriveKind.wsl
        ? 'Linux · WSL'
        : drive.requiresAdmin
        ? context.tr.driveRestrictedAccess
        : '—',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: context.cbColors.textSecondary,
      fontSize: 12,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );

  Widget _menu(BuildContext context, DriveInfo drive) => Builder(
    builder: (buttonContext) => IconButton(
      tooltip: context.tr.moreOptions,
      iconSize: 16,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      icon: const Icon(PhosphorIconsLight.dotsThree),
      onPressed: () {
        final box = buttonContext.findRenderObject() as RenderBox;
        onMenu(drive, box.localToGlobal(Offset(0, box.size.height)));
      },
    ),
  );

  Widget _details(BuildContext context) {
    final c = context.cbColors;
    final specs =
        <(DriveDetailsColumn, double, SortOption?)>[
              (DriveDetailsColumn.name, 260, SortOption.nameAsc),
              (DriveDetailsColumn.path, 140, SortOption.pathAsc),
              (DriveDetailsColumn.type, 140, SortOption.typeAsc),
              (DriveDetailsColumn.filesystem, 100, null),
              (DriveDetailsColumn.total, 110, SortOption.sizeAsc),
              (DriveDetailsColumn.free, 110, null),
              (DriveDetailsColumn.used, 130, null),
            ]
            .where(
              (spec) =>
                  spec.$1 == DriveDetailsColumn.name ||
                  visibleColumns.contains(spec.$1),
            )
            .toList();
    Widget cell(DriveInfo drive, DriveDetailsColumn column) {
      if (column == DriveDetailsColumn.name) {
        return Row(
          children: [
            _driveIcon(context, drive, 28),
            const SizedBox(width: 10),
            Expanded(child: _name(context, drive)),
            const SizedBox(width: 16),
          ],
        );
      }
      if (column == DriveDetailsColumn.used) {
        return Padding(
          padding: const EdgeInsets.only(right: 24),
          child: DriveCapacityBar(space: drive.space),
        );
      }
      final value = switch (column) {
        DriveDetailsColumn.path => drive.path,
        DriveDetailsColumn.type => driveKindLabel(context, drive),
        DriveDetailsColumn.filesystem => drive.filesystem,
        DriveDetailsColumn.total =>
          drive.space.hasDetails
              ? FormatUtils.formatFileSize(drive.space.totalBytes)
              : '—',
        DriveDetailsColumn.free =>
          drive.space.hasDetails
              ? FormatUtils.formatFileSize(drive.space.freeBytes)
              : '—',
        _ => '',
      };
      return Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: c.textSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidth = specs.fold<double>(72, (sum, spec) => sum + spec.$2);
        return SingleChildScrollView(
          key: const ValueKey('drive-mode-details'),
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth > minWidth
                ? constraints.maxWidth
                : minWidth,
            child: Column(
              children: [
                Container(
                  color: c.fillSubtle,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final col in specs)
                        SizedBox(
                          width: col.$2,
                          child: CbPressable(
                            onPressed: col.$3 == null
                                ? null
                                : () {
                                    final asc = col.$3!;
                                    onSort(
                                      sortOption == asc
                                          ? SortOption.values[asc.index + 1]
                                          : asc,
                                    );
                                  },
                            builder: (context, state) => Container(
                              height: 38,
                              alignment: Alignment.centerLeft,
                              color: state.hovered
                                  ? c.surfaceHover
                                  : Colors.transparent,
                              child: Text(
                                '${driveColumnLabel(context, col.$1)}${col.$3 != null && col.$3!.index ~/ 2 == sortOption.index ~/ 2
                                    ? sortOption.ascending
                                          ? ' ↑'
                                          : ' ↓'
                                    : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: drives.length,
                    itemBuilder: (context, i) {
                      final drive = drives[i];
                      return GestureDetector(
                        onTertiaryTapUp: onOpenInNewTab == null
                            ? null
                            : (_) => onOpenInNewTab!(drive),
                        onSecondaryTapDown: (event) =>
                            onMenu(drive, event.globalPosition),
                        child: CbSurface(
                          key: ValueKey('drive-entry-${drive.path}'),
                          radius: 4,
                          selected: selectedPaths.contains(drive.path),
                          color: Colors.transparent,
                          onPressed: () => onSelect(drive),
                          pressOnPointerDown: selectOnPointerDown,
                          onDoubleTap: () => onOpen(drive),
                          onActivate: () => onOpen(drive),
                          descendantsAreFocusable: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              for (final spec in specs)
                                SizedBox(
                                  width: spec.$2,
                                  child: cell(drive, spec.$1),
                                ),
                              SizedBox(width: 40, child: _menu(context, drive)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class DriveCapacityBar extends StatelessWidget {
  final DriveSpaceInfo space;
  const DriveCapacityBar({super.key, required this.space});
  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Semantics(
      label:
          '${context.tr.driveUsed}: ${space.hasDetails ? '${(space.usageRatio * 100).round()}%' : '—'}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 4,
          child: ColoredBox(
            color: c.fill,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: space.hasDetails ? space.usageRatio : 0,
                heightFactor: 1,
                child: ColoredBox(
                  color: space.usageRatio >= .9
                      ? c.status.danger
                      : c.accent.base,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DriveInspector extends StatelessWidget {
  final DriveInfo? drive;
  const DriveInspector({super.key, this.drive});
  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l = context.tr;
    final d = drive;
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.strokeSubtle)),
      ),
      padding: const EdgeInsets.all(24),
      child: d == null
          ? Center(
              child: Icon(
                PhosphorIconsLight.hardDrives,
                size: 48,
                color: c.iconSubtle,
              ),
            )
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _driveIcon(context, d, 56),
                  const SizedBox(height: 20),
                  Text(
                    d.displayName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    d.path,
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 28),
                  DriveCapacityBar(space: d.space),
                  const SizedBox(height: 20),
                  for (final field in <(String, String)>[
                    (l.driveType, driveKindLabel(context, d)),
                    if (d.filesystem.isNotEmpty)
                      (l.driveFilesystem, d.filesystem),
                    if (d.space.hasDetails) ...[
                      (
                        l.driveTotal,
                        FormatUtils.formatFileSize(d.space.totalBytes),
                      ),
                      (
                        l.driveFree,
                        FormatUtils.formatFileSize(d.space.freeBytes),
                      ),
                      (
                        l.driveUsed,
                        FormatUtils.formatFileSize(d.space.usedBytes),
                      ),
                    ],
                    if (d.volumeSerial?.isNotEmpty == true)
                      (l.driveSerial, d.volumeSerial!),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field.$1,
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 5),
                          SelectableText(
                            field.$2,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

Widget _driveIcon(BuildContext context, DriveInfo drive, double size) =>
    DriveAvatar(drive: drive, size: size);

IconData _groupIcon(DriveGroup group) => switch (group) {
  DriveGroup.fixed => PhosphorIconsLight.hardDrives,
  DriveGroup.removable => PhosphorIconsLight.usb,
  DriveGroup.network => PhosphorIconsLight.network,
  DriveGroup.wsl => PhosphorIconsLight.linuxLogo,
  DriveGroup.other => PhosphorIconsLight.disc,
};

String _groupLabel(BuildContext context, DriveGroup group) => switch (group) {
  DriveGroup.fixed => context.tr.driveGroupFixed,
  DriveGroup.removable => context.tr.driveGroupRemovable,
  DriveGroup.network => context.tr.driveGroupNetwork,
  DriveGroup.wsl => 'Linux · WSL',
  DriveGroup.other => context.tr.driveGroupOther,
};

String driveKindLabel(BuildContext context, DriveInfo drive) =>
    switch (drive.kind) {
      DriveKind.fixed => context.tr.driveKindFixed,
      DriveKind.removable => context.tr.driveKindRemovable,
      DriveKind.network => context.tr.driveKindNetwork,
      DriveKind.optical => context.tr.driveKindOptical,
      DriveKind.ram => context.tr.driveKindRam,
      DriveKind.internal => context.tr.driveKindInternal,
      DriveKind.unknown => context.tr.driveKindUnknown,
      DriveKind.wsl => 'Linux (WSL)',
    };
