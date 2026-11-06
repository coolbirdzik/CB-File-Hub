import 'dart:math' as math;

import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/utils/platform_utils.dart';
import 'package:cb_file_manager/ui/utils/view_mode_utils.dart';
import 'package:cb_file_manager/ui/widgets/adaptive_file_list.dart';
import 'package:flutter/material.dart';

/// File-shaped, static loading rows. Progress is shown once by the host screen.
class FileLoadingSkeleton extends StatelessWidget {
  const FileLoadingSkeleton({
    super.key,
    required this.viewMode,
    this.gridZoomLevel = 4,
    this.itemCount = 12,
    this.layoutKnown = true,
    this.singleColumn = false,
    this.drives = false,
  });

  final ViewMode viewMode;
  final int gridZoomLevel;
  final int itemCount;
  final bool layoutKnown;
  final bool singleColumn;
  final bool drives;

  @override
  Widget build(BuildContext context) {
    // Media detection needs the listing. Do not promise a List layout and then
    // switch it to Grid; the host's slim progress bar conveys this short wait.
    if (!layoutKnown) return const SizedBox.expand();
    final mode = ViewModeUtils.normalize(viewMode);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (mode == ViewMode.grid) {
              final spacing = drives
                  ? 12.0
                  : GridZoomConstraints.fileGridSpacing;
              final maxZoom = GridZoomConstraints.maxGridSize(
                availableWidth: constraints.maxWidth,
                spacing: spacing,
              );
              final zoom = gridZoomLevel
                  .clamp(UserPreferences.minGridZoomLevel, maxZoom)
                  .toInt();
              final width = GridZoomConstraints.itemWidthForZoom(
                zoom,
                spacing: spacing,
                minWidth: drives
                    ? 150
                    : GridZoomConstraints.fileGridMinItemWidth,
              );
              return GridView.builder(
                padding: EdgeInsets.all(drives ? 16 : 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: GridZoomConstraints.columnCountForItemWidth(
                    constraints.maxWidth - (drives ? spacing * 2 : 0),
                    width,
                    spacing: spacing,
                  ),
                  mainAxisExtent:
                      width /
                      (drives ? 1.35 : GridZoomConstraints.fileGridAspectRatio),
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: itemCount,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: _Block()),
                      const SizedBox(height: 8),
                      _Block(height: 12, fraction: index.isEven ? .75 : .55),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
            }
            if (mode == ViewMode.tiles) {
              return GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 76,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: itemCount,
                itemBuilder: (context, index) =>
                    _row(index, height: 76, iconSize: 40, secondary: true),
              );
            }
            if (mode == ViewMode.list) {
              return AdaptiveFileList(
                isDesktop: isDesktopPlatform,
                itemCount: itemCount,
                itemBuilder: (context, index) => _row(
                  index,
                  height: isDesktopPlatform ? 40 : 72,
                  iconSize: isDesktopPlatform ? 20 : 48,
                  secondary: !isDesktopPlatform,
                ),
              );
            }
            if (mode == ViewMode.columns) {
              if (singleColumn) return _rows(height: 36, iconSize: 20);
              final columns = math.max(1, (constraints.maxWidth / 281).ceil());
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(
                    columns,
                    (column) => SizedBox(
                      width: 280,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 1),
                        child: _rows(height: 36, iconSize: 20),
                      ),
                    ),
                  ),
                ),
              );
            }
            if (mode == ViewMode.details) {
              return Column(
                children: [
                  _row(0, height: 36, iconSize: 0, details: true),
                  const Divider(height: 1),
                  Expanded(
                    child: _rows(height: 36, iconSize: 20, details: true),
                  ),
                ],
              );
            }
            return _rows(height: 32, iconSize: 20, tree: true);
          },
        ),
      ),
    );
  }

  Widget _rows({
    required double height,
    required double iconSize,
    bool details = false,
    bool tree = false,
  }) => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 4),
    itemCount: itemCount,
    itemBuilder: (context, index) => _row(
      index,
      height: height,
      iconSize: iconSize,
      details: details,
      indent: tree ? (index % 4) * 16.0 : 0,
    ),
  );

  Widget _row(
    int index, {
    required double height,
    required double iconSize,
    bool secondary = false,
    bool details = false,
    double indent = 0,
  }) => SizedBox(
    height: height,
    child: Padding(
      padding: EdgeInsets.only(left: 10 + indent, right: 12),
      child: Row(
        children: [
          if (iconSize > 0) ...[
            SizedBox(width: iconSize, height: iconSize, child: const _Block()),
            const SizedBox(width: 10),
          ],
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Block(height: 10, fraction: index.isEven ? .65 : .45),
                if (secondary) ...[
                  const SizedBox(height: 7),
                  const _Block(height: 8, fraction: .4),
                ],
              ],
            ),
          ),
          if (details) ...[
            const Expanded(child: _Block(height: 9, fraction: .6)),
            const Expanded(child: _Block(height: 9, fraction: .6)),
          ],
        ],
      ),
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({this.height, this.fraction = 1});
  final double? height;
  final double fraction;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    widthFactor: fraction,
    alignment: Alignment.centerLeft,
    child: Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(4),
      ),
    ),
  );
}
