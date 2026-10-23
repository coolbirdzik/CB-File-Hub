import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/disk_cleaner/cleaner_space_insights.dart';
import '../../../services/disk_cleaner/disk_tree_node.dart';
import '../../../services/disk_cleaner/full_disk_scan_isolate.dart';

/// Separates informational old-large evidence into independently ranked
/// folder and file sections for the Cleaner results panel.
class OldLargeEvidenceSections {
  final List<FullDiskScanInsight> folders;
  final List<FullDiskScanInsight> files;

  const OldLargeEvidenceSections({required this.folders, required this.files});

  int get totalCount => folders.length + files.length;
}

enum OldLargeEvidenceFilter { all, folders, files }

/// Builds deterministic, size-ranked sections without touching the drive.
OldLargeEvidenceSections splitOldLargeEvidence(
  Iterable<FullDiskScanInsight> items,
) {
  final folders = <FullDiskScanInsight>[];
  final files = <FullDiskScanInsight>[];
  for (final item in items) {
    (item.isFile ? files : folders).add(item);
  }
  folders.sort(compareOldLargeDiskInsights);
  files.sort(compareOldLargeDiskInsights);
  return OldLargeEvidenceSections(folders: folders, files: files);
}

/// Returns the selected old-large evidence in stable presentation order.
///
/// The All view deliberately keeps folders before files so directory evidence
/// cannot be hidden among file rows.
List<FullDiskScanInsight> filterOldLargeEvidence(
  Iterable<FullDiskScanInsight> items,
  OldLargeEvidenceFilter filter,
) {
  final sections = splitOldLargeEvidence(items);
  switch (filter) {
    case OldLargeEvidenceFilter.all:
      return <FullDiskScanInsight>[...sections.folders, ...sections.files];
    case OldLargeEvidenceFilter.folders:
      return sections.folders;
    case OldLargeEvidenceFilter.files:
      return sections.files;
  }
}

/// The overview cards of the Disk usage results.
enum CleanerDashboardView {
  heavyFolders,
  largeFiles,
  oldUnused,
  knownCauses,
  fileTypes,
}

const int _mb = 1024 * 1024;
const int _gb = 1024 * _mb;
const _sizeSteps = <int>[100 * _mb, _gb, 10 * _gb];
const _ageStepsDays = <int>[180, 365, 730];

// Weakly held per scan tree. Returned nodes contain display metadata only, so
// preparing insights in an isolate never copies whole subtrees back to the UI.
final _preparedInsights =
    Expando<({int bytes, int files, _DashboardInsights data})>();

class _DashboardInsights {
  const _DashboardInsights(
    this.hotspots,
    this.causes,
    this.types,
    this.largeFiles,
  );
  final List<CleanerSpaceHotspot> hotspots;
  final List<CleanerSpaceCauseMatch> causes;
  final List<CleanerFileTypeTotal> types;
  final List<DiskTreeNode> largeFiles;
}

_DashboardInsights _scanDashboardInsights(DiskTreeNode root) {
  DiskTreeNode displayNode(DiskTreeNode node) => DiskTreeNode(
    name: node.name,
    fullPath: node.fullPath,
    isFile: node.isFile,
    sizeBytes: node.sizeBytes,
    fileCount: node.fileCount,
  );
  return _DashboardInsights(
    CleanerSpaceInsights.findHotspots(root, limit: 30)
        .map(
          (item) => CleanerSpaceHotspot(
            node: displayNode(item.node),
            spreadBytes: item.spreadBytes,
            isResidual: item.isResidual,
          ),
        )
        .toList(),
    CleanerSpaceInsights.findCauses(root)
        .map(
          (item) =>
              CleanerSpaceCauseMatch(item.cause)
                ..nodes.addAll(item.nodes.map(displayNode)),
        )
        .toList(),
    CleanerSpaceInsights.fileTypeTotals(root, largestPerGroup: 50)
        .where((item) => item.group != 'other')
        .map(
          (item) => CleanerFileTypeTotal(item.group)
            ..bytes = item.bytes
            ..files = item.files
            ..largest.addAll(item.largest.map(displayNode)),
        )
        .toList(),
    CleanerSpaceInsights.search(
      root,
      kind: 'file',
      minBytes: _sizeSteps.first,
      limit: 1 << 30,
    ).matches.map(displayNode).toList(),
  );
}

/// A collapsed-by-default overview of where the space is: one card per
/// question (heavy folders, large files, old & unused, known space hogs, file
/// types). Picking a card opens its list with filter conditions; every row
/// reveals itself in the tree or opens in a new tab. Read-only: nothing here
/// selects or deletes.
class CleanerDashboard extends StatefulWidget {
  /// Refresh diagnosis off the UI isolate while cleanup progress is visible.
  static Future<void> prepareInsights(DiskTreeNode root) async {
    final bytes = root.sizeBytes;
    final files = root.fileCount;
    final data = await compute(_scanDashboardInsights, root);
    if (root.sizeBytes == bytes && root.fileCount == files) {
      _preparedInsights[root] = (bytes: bytes, files: files, data: data);
    }
  }

  const CleanerDashboard({
    super.key,
    required this.root,
    required this.oldLargeItems,
    required this.formatBytes,
    required this.formatDate,
    required this.onReveal,
    required this.onOpen,
  });

  final DiskTreeNode root;
  final List<FullDiskScanInsight> oldLargeItems;
  final String Function(int bytes) formatBytes;
  final String Function(DateTime date) formatDate;

  /// Reveal the nearest displayed tree row for a path.
  final void Function(String path) onReveal;

  /// Open a folder, or a file's containing folder, in a new tab.
  final void Function(String path, bool isFile) onOpen;

  @override
  State<CleanerDashboard> createState() => _CleanerDashboardState();
}

class _DashboardRow {
  const _DashboardRow({
    required this.path,
    required this.name,
    required this.isFile,
    required this.sizeBytes,
    this.detail,
  });

  final String path;
  final String name;
  final bool isFile;
  final int sizeBytes;
  final String? detail;
}

class _CleanerDashboardState extends State<CleanerDashboard> {
  CleanerDashboardView? _open;

  int _largeMinBytes = _gb;
  String? _largeType;
  int _oldMinDays = _ageStepsDays.first;
  int _oldMinBytes = _sizeSteps.first;
  OldLargeEvidenceFilter _oldKind = OldLargeEvidenceFilter.all;
  String? _typeGroup;

  // Whole-tree insights, recomputed only when the tree changes.
  Object? _insightsKey;
  List<CleanerSpaceHotspot> _hotspots = const [];
  List<CleanerSpaceCauseMatch> _causes = const [];
  List<CleanerFileTypeTotal> _types = const [];
  List<DiskTreeNode> _largeCandidates = const [];
  Object? _largeFilesKey;
  ({List<DiskTreeNode> matches, int count, int totalBytes})? _largeFilesResult;
  Object? _typeFilesKey;
  List<DiskTreeNode> _typeFilesResult = const [];

  void _ensureInsights() {
    final root = widget.root;
    final key = (root, root.sizeBytes, root.fileCount);
    if (key == _insightsKey) return;
    _insightsKey = key;
    final prepared = _preparedInsights[root];
    final data =
        prepared?.bytes == root.sizeBytes && prepared?.files == root.fileCount
        ? prepared!.data
        : _scanDashboardInsights(root);
    _hotspots = data.hotspots;
    _causes = data.causes;
    _types = data.types;
    _largeCandidates = data.largeFiles;
    if (_typeGroup != null && !_types.any((t) => t.group == _typeGroup)) {
      _typeGroup = null;
    }
  }

  ({List<DiskTreeNode> matches, int count, int totalBytes}) _largeFiles() {
    final root = widget.root;
    final key = (
      root,
      root.sizeBytes,
      root.fileCount,
      _largeMinBytes,
      _largeType,
    );
    if (key != _largeFilesKey) {
      _largeFilesKey = key;
      final matches = _largeCandidates
          .where(
            (node) =>
                node.sizeBytes >= _largeMinBytes &&
                (_largeType == null ||
                    CleanerSpaceInsights.groupOfExtension(
                          CleanerSpaceInsights.extensionOf(node.name),
                        ) ==
                        _largeType),
          )
          .toList();
      _largeFilesResult = (
        matches: matches.take(50).toList(),
        count: matches.length,
        totalBytes: matches.fold<int>(0, (sum, node) => sum + node.sizeBytes),
      );
    }
    return _largeFilesResult!;
  }

  List<DiskTreeNode> _typeFiles(String group) {
    final root = widget.root;
    final key = (root, root.sizeBytes, root.fileCount, group);
    if (key != _typeFilesKey) {
      _typeFilesKey = key;
      _typeFilesResult = _types
          .where((item) => item.group == group)
          .expand((item) => item.largest)
          .toList();
    }
    return _typeFilesResult;
  }

  List<FullDiskScanInsight> _oldItems() {
    final cutoff = DateTime.now().subtract(Duration(days: _oldMinDays));
    return filterOldLargeEvidence(widget.oldLargeItems, _oldKind).where((item) {
      if (item.sizeBytes < _oldMinBytes) return false;
      final activity = item.lastActivity;
      // The scan already applied the shortest age; unknown activity only
      // qualifies there.
      if (activity == null) return _oldMinDays == _ageStepsDays.first;
      return activity.isBefore(cutoff);
    }).toList();
  }

  String _causeTitle(AppLocalizations l, CleanerSpaceCause cause) {
    final title = l.cleanerSuggestionTitle(cause.id);
    return title == cause.id ? cause.label : title;
  }

  String _causeDetail(AppLocalizations l, CleanerSpaceCause cause) {
    final detail = l.cleanerSuggestionDetail(cause.id);
    return detail == cause.id ? cause.action : detail;
  }

  String _percentOfDisk(AppLocalizations l, int bytes) {
    final total = widget.root.sizeBytes;
    if (total <= 0) return '';
    final percent = bytes * 100 / total;
    return l.diskCleanerDashboardOfDisk(
      '${percent < 10 ? percent.toStringAsFixed(1) : percent.round()}%',
    );
  }

  String _ageLabel(AppLocalizations l, int days) => days < 365
      ? l.diskCleanerDashboardMonths(days ~/ 30)
      : l.diskCleanerDashboardYears(days ~/ 365);

  @override
  Widget build(BuildContext context) {
    _ensureInsights();
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final large = _largeFiles();
    final old = _oldItems();

    final cards = <(CleanerDashboardView, IconData, String, int, int)>[
      (
        CleanerDashboardView.heavyFolders,
        PhosphorIconsLight.folderSimple,
        l.diskCleanerDashboardHeavyFolders,
        _hotspots.fold(0, (sum, h) => sum + h.spreadBytes),
        _hotspots.length,
      ),
      (
        CleanerDashboardView.largeFiles,
        PhosphorIconsLight.fileArrowUp,
        l.diskCleanerDashboardLargeFiles,
        large.totalBytes,
        large.count,
      ),
      (
        CleanerDashboardView.oldUnused,
        PhosphorIconsLight.clockCounterClockwise,
        l.diskCleanerDashboardOldUnused,
        old.fold(0, (sum, item) => sum + item.sizeBytes),
        old.length,
      ),
      (
        CleanerDashboardView.knownCauses,
        PhosphorIconsLight.lightbulb,
        l.diskCleanerDashboardKnownCauses,
        _causes.fold(0, (sum, c) => sum + c.totalBytes),
        _causes.length,
      ),
      (
        CleanerDashboardView.fileTypes,
        PhosphorIconsLight.chartPieSlice,
        l.diskCleanerDashboardFileTypes,
        _types.fold(0, (sum, t) => sum + t.bytes),
        _types.length,
      ),
    ];

    Widget card((CleanerDashboardView, IconData, String, int, int) data) {
      final (view, icon, title, bytes, count) = data;
      final selected = _open == view;
      return Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
            : theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: CbRadii.lgAll,
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('cleaner-dashboard-card-${view.name}'),
          onTap: () => setState(() => _open = selected ? null : view),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: CbRadii.mdAll,
                  ),
                  child: Icon(icon, size: 17, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        widget.formatBytes(bytes),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        l.diskCleanerDashboardCount(count),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? PhosphorIconsLight.caretUp
                      : PhosphorIconsLight.caretDown,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        key: const ValueKey<String>('cleaner-dashboard'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Five across when there is room; otherwise wrap at a width
              // that still fits a size like "123.4 GB".
              const spacing = 8.0;
              final perRow = constraints.maxWidth >= 900
                  ? cards.length
                  : constraints.maxWidth >= 560
                  ? 3
                  : 2;
              final width =
                  (constraints.maxWidth - spacing * (perRow - 1)) / perRow;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final data in cards)
                    SizedBox(width: width, child: card(data)),
                ],
              );
            },
          ),
          if (_open != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 300,
              child: DecoratedBox(
                key: ValueKey<String>(
                  'cleaner-dashboard-detail-${_open!.name}',
                ),
                decoration: CbDecorations.card(context, radius: 10),
                child: _buildDetail(theme, l, _open!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, {Key? key}) =>
      ChoiceChip(
        key: key,
        label: Text(label),
        selected: selected,
        visualDensity: VisualDensity.compact,
        onSelected: (_) => onTap(),
      );

  Widget _buildDetail(
    ThemeData theme,
    AppLocalizations l,
    CleanerDashboardView view,
  ) {
    final conditions = <Widget>[];
    late final List<_DashboardRow> rows;
    switch (view) {
      case CleanerDashboardView.heavyFolders:
        rows = [
          for (final hotspot in _hotspots)
            _DashboardRow(
              path: hotspot.node.fullPath,
              name: hotspot.node.name,
              isFile: hotspot.node.isFile,
              sizeBytes: hotspot.node.sizeBytes,
              detail: _percentOfDisk(l, hotspot.node.sizeBytes),
            ),
        ];
      case CleanerDashboardView.largeFiles:
        for (final bytes in _sizeSteps) {
          conditions.add(
            _chip(
              l.diskCleanerDashboardAtLeast(widget.formatBytes(bytes)),
              _largeMinBytes == bytes,
              () => setState(() => _largeMinBytes = bytes),
              key: ValueKey<String>('cleaner-dashboard-large-min-$bytes'),
            ),
          );
        }
        conditions.add(const SizedBox(width: 8));
        conditions.add(
          _chip(
            l.diskCleanerDashboardAllTypes,
            _largeType == null,
            () => setState(() => _largeType = null),
          ),
        );
        for (final type in CleanerSpaceInsights.fileTypeGroups.keys) {
          conditions.add(
            _chip(
              l.diskCleanerFileTypeLabel(type),
              _largeType == type,
              () => setState(() => _largeType = type),
            ),
          );
        }
        rows = [
          for (final node in _largeFiles().matches)
            _DashboardRow(
              path: node.fullPath,
              name: node.name,
              isFile: true,
              sizeBytes: node.sizeBytes,
              detail: switch (CleanerSpaceInsights.groupOfExtension(
                CleanerSpaceInsights.extensionOf(node.name),
              )) {
                final group? => l.diskCleanerFileTypeLabel(group),
                null => null,
              },
            ),
        ];
      case CleanerDashboardView.oldUnused:
        for (final days in _ageStepsDays) {
          conditions.add(
            _chip(
              l.diskCleanerDashboardUnusedFor(_ageLabel(l, days)),
              _oldMinDays == days,
              () => setState(() => _oldMinDays = days),
              key: ValueKey<String>('cleaner-dashboard-old-age-$days'),
            ),
          );
        }
        conditions.add(const SizedBox(width: 8));
        for (final (kind, label) in [
          (OldLargeEvidenceFilter.all, l.diskCleanerOldLargeAll),
          (OldLargeEvidenceFilter.folders, l.diskCleanerOldLargeFolders),
          (OldLargeEvidenceFilter.files, l.diskCleanerOldLargeFiles),
        ]) {
          conditions.add(
            _chip(
              label,
              _oldKind == kind,
              () => setState(() => _oldKind = kind),
            ),
          );
        }
        conditions.add(const SizedBox(width: 8));
        for (final bytes in _sizeSteps) {
          conditions.add(
            _chip(
              l.diskCleanerDashboardAtLeast(widget.formatBytes(bytes)),
              _oldMinBytes == bytes,
              () => setState(() => _oldMinBytes = bytes),
            ),
          );
        }
        rows = [
          for (final item in _oldItems())
            _DashboardRow(
              path: item.path,
              name: item.name,
              isFile: item.isFile,
              sizeBytes: item.sizeBytes,
              detail: switch (item.lastActivity) {
                final activity? => l.diskCleanerOldLargeLastActivity(
                  widget.formatDate(activity),
                ),
                null => null,
              },
            ),
        ];
      case CleanerDashboardView.knownCauses:
        rows = [
          for (final match in _causes)
            if (match.nodes.isNotEmpty)
              _DashboardRow(
                path: match.nodes.first.fullPath,
                name: _causeTitle(l, match.cause),
                isFile: match.nodes.first.isFile,
                sizeBytes: match.totalBytes,
                detail: _causeDetail(l, match.cause),
              ),
        ];
      case CleanerDashboardView.fileTypes:
        final group =
            _typeGroup ?? (_types.isEmpty ? null : _types.first.group);
        for (final total in _types) {
          conditions.add(
            _chip(
              '${l.diskCleanerFileTypeLabel(total.group)} · '
              '${widget.formatBytes(total.bytes)}',
              group == total.group,
              () => setState(() => _typeGroup = total.group),
            ),
          );
        }
        rows = group == null
            ? const []
            : [
                for (final node in _typeFiles(group))
                  _DashboardRow(
                    path: node.fullPath,
                    name: node.name,
                    isFile: true,
                    sizeBytes: node.sizeBytes,
                    detail: _percentOfDisk(l, node.sizeBytes),
                  ),
              ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (conditions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (index, chip) in conditions.indexed) ...[
                    if (index > 0) const SizedBox(width: 6),
                    chip,
                  ],
                ],
              ),
            ),
          ),
        if (conditions.isNotEmpty)
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    l.diskCleanerDashboardNoMatches,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : Scrollbar(
                  child: ListView.separated(
                    primary: false,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    itemCount: rows.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 46,
                      endIndent: 8,
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.3,
                      ),
                    ),
                    itemBuilder: (context, index) =>
                        _buildRow(theme, l, rows[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildRow(ThemeData theme, AppLocalizations l, _DashboardRow row) {
    return InkWell(
      key: ValueKey<String>('cleaner-dashboard-row-${row.path}'),
      onTap: () => widget.onReveal(row.path),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.55,
                ),
                borderRadius: CbRadii.mdAll,
              ),
              child: Icon(
                row.isFile
                    ? PhosphorIconsLight.file
                    : PhosphorIconsLight.folder,
                size: 16,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    row.detail == null || row.detail!.isEmpty
                        ? row.path
                        : '${row.path} · ${row.detail}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.formatBytes(row.sizeBytes),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            IconButton(
              key: ValueKey<String>('cleaner-dashboard-open-${row.path}'),
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              tooltip: row.isFile ? l.openContainingFolder : l.openInNewTab,
              icon: const Icon(PhosphorIconsLight.folderOpen, size: 17),
              onPressed: () => widget.onOpen(row.path, row.isFile),
            ),
          ],
        ),
      ),
    );
  }
}
