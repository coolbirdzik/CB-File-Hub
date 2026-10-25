import 'dart:async';

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/ui/components/common/search_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../bloc/cleaner_app_leftovers/cleaner_app_leftovers.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../services/app_insights/app_leftover_finder.dart';
import '../../../services/app_insights/app_leftover_scanner.dart';
import '../../../services/disk_cleaner/cleaner_models.dart';
import '../../utils/format_utils.dart';
import 'cleaner_progress_widgets.dart';

const double _checkboxColumnWidth = 40;
const double _dateColumnWidth = 132;
const double _sizeColumnWidth = 84;
const double _openColumnWidth = 36;

/// Below this width the date moves into the row's second line.
const double _wideRowBreakpoint = 640;

/// Below this width the footer stacks the summary above the button.
const double _wideFooterBreakpoint = 560;

typedef AppLeftoverPathAction = FutureOr<void> Function(String path);
typedef AppLeftoverCleanAction =
    Future<CleanReport?> Function(
      List<JunkItem> items,
      void Function(int done, int total, String? path) onProgress,
    );

/// Leftover app data, laid out like a cleanup report: one section per
/// reason, one card per location, the folders inside each card. Folders show
/// up as soon as they are measured. Checked folders go to the Recycle Bin
/// (Trash) only after a confirmation dialog, as explicit user selections.
class CleanerLeftoversView extends StatefulWidget {
  final CleanerAppLeftoversCubit cubit;
  final VoidCallback? onScan;
  final VoidCallback? onCancel;
  final AppLeftoverPathAction? onOpenFolder;

  /// Null while another Cleaner cleanup is running.
  final AppLeftoverCleanAction? onClean;

  /// macOS and Linux move to the Trash instead of the Recycle Bin.
  final bool usesTrash;

  const CleanerLeftoversView({
    super.key,
    required this.cubit,
    this.onScan,
    this.onCancel,
    this.onOpenFolder,
    this.onClean,
    this.usesTrash = false,
  });

  @override
  State<CleanerLeftoversView> createState() => _CleanerLeftoversViewState();
}

class _CleanerLeftoversViewState extends State<CleanerLeftoversView> {
  static const Duration _searchDebounce = Duration(milliseconds: 220);

  /// Cards with more folders than this start collapsed.
  static const int _autoExpandLimit = 40;

  late final SearchTextController _searchController;
  final ValueNotifier<(int, int, String?)?> _cleanProgress = ValueNotifier(
    null,
  );
  final Set<String> _toggledGroups = <String>{};
  Timer? _searchDebounceTimer;
  bool _cleaning = false;

  @override
  void initState() {
    super.initState();
    _searchController = SearchTextController(
      text: widget.cubit.state.searchQuery,
    );
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _cleanProgress.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      widget.cubit.setSearchQuery(query);
    });
  }

  String _destination(AppLocalizations l) =>
      widget.usesTrash ? l.trashBin : l.diskCleanerRecycleBinLabel;

  Future<void> _cleanSelected() async {
    final onClean = widget.onClean;
    final selected = widget.cubit.state.selectedCandidates;
    if (onClean == null || selected.isEmpty || _cleaning) return;
    final l = AppLocalizations.of(context)!;
    final destination = _destination(l);
    final size = FormatUtils.formatFileSize(
      selected.fold<int>(0, (sum, item) => sum + item.sizeBytes),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cleanerLeftoversConfirmTitle(destination)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.cleanerLeftoversConfirmBody(selected.length, size, destination),
            ),
            const SizedBox(height: 10),
            _Warning(text: l.cleanerLeftoversConfirmWarning),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey<String>('cleaner-leftovers-confirm-clean'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              widget.usesTrash ? l.moveToTrash : l.diskCleanerMoveToRecycleBin,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _cleanProgress.value = null;
    setState(() => _cleaning = true);
    CleanReport? result;
    try {
      result = await onClean(
        [
          for (final candidate in selected)
            JunkItem(
              path: candidate.path,
              sizeBytes: candidate.sizeBytes,
              categoryId: 'selected_item',
              // The folder itself goes, not only its contents.
              isContainerOnly: false,
              isUserSelected: true,
            ),
        ],
        (done, total, path) {
          if (mounted) _cleanProgress.value = (done, total, path);
        },
      );
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
    if (!mounted || result == null) return;
    widget.cubit.removePaths(result.succeeded);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l.cleanerLeftoversCleaned(
            FormatUtils.formatFileSize(result.freedBytes),
            destination,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CleanerAppLeftoversCubit, CleanerAppLeftoversState>(
      key: const ValueKey<String>('cleaner-leftovers-view'),
      bloc: widget.cubit,
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final report = state.report;
        final hasResults =
            state.status == CleanerAppLeftoversStatus.ready &&
            report != null &&
            !report.inventoryUnavailable;
        final scanning =
            state.status == CleanerAppLeftoversStatus.loading ||
            state.isScanning;
        return Column(
          key: const ValueKey<String>('cleaner-leftovers-feature'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              subtitle: hasResults
                  ? (scanning
                        ? l.cleanerLeftoversFound(
                            FormatUtils.formatFileSize(state.visibleBytes),
                          )
                        : l.cleanerLeftoversReclaimable(
                            FormatUtils.formatFileSize(state.visibleBytes),
                          ))
                  : l.cleanerLeftoversUtilityDescription,
              scanning: scanning,
              enabled: !_cleaning,
              onScan: widget.onScan,
              onCancel: widget.onCancel,
            ),
            const Divider(height: 1),
            if (hasResults)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                child: _Toolbar(
                  cubit: widget.cubit,
                  state: state,
                  searchController: _searchController,
                  onSearchChanged: _onSearchChanged,
                ),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.97, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: _buildBody(l, state),
              ),
            ),
            if (hasResults) _buildFooter(l, state),
          ],
        );
      },
    );
  }

  Widget _buildBody(AppLocalizations l, CleanerAppLeftoversState state) {
    switch (state.status) {
      case CleanerAppLeftoversStatus.idle:
        return _Intro(
          key: const ValueKey<String>('cleaner-leftovers-intro'),
          onScan: widget.onScan,
        );
      case CleanerAppLeftoversStatus.loading:
        return ListView(
          key: const ValueKey<String>('cleaner-leftovers-loading'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [_ScanCard(title: l.cleanerLeftoversLoading)],
        );
      case CleanerAppLeftoversStatus.failure:
        return _CenteredStatus(
          key: const ValueKey<String>('cleaner-leftovers-error'),
          icon: Icon(
            Icons.error_outline_rounded,
            size: 34,
            color: Theme.of(context).colorScheme.error,
          ),
          message: l.cleanerAppsLoadFailed(
            state.errorMessage ?? l.cleanerAppsUnknown,
          ),
        );
      case CleanerAppLeftoversStatus.ready:
        final report = state.report;
        if (report == null || report.inventoryUnavailable) {
          return _CenteredStatus(
            key: const ValueKey<String>('cleaner-leftovers-unavailable'),
            icon: const Icon(Icons.apps_outage_rounded, size: 34),
            message: l.cleanerLeftoversInventoryUnavailable,
          );
        }
        return KeyedSubtree(
          key: ValueKey<DateTime>(report.generatedAt),
          child: _buildResults(l, state, report),
        );
    }
  }

  Widget _buildResults(
    AppLocalizations l,
    CleanerAppLeftoversState state,
    AppLeftoverReport report,
  ) {
    final theme = Theme.of(context);
    final visible = state.visibleCandidates;
    final hidden = state.hiddenByActivityCount;
    final sections = <Widget>[
      if (state.isScanning)
        _ScanCard(
          key: const ValueKey<String>('cleaner-leftovers-progress'),
          title: l.cleanerLeftoversMeasuring,
          detail: l.cleanerLeftoversScanProgress(
            state.measuredCount,
            state.totalCount,
          ),
          value: state.totalCount == 0
              ? null
              : state.measuredCount / state.totalCount,
        ),
      _InfoBar(
        key: const ValueKey<String>('cleaner-leftovers-intro-banner'),
        text: report.isPartial
            ? '${l.cleanerLeftoversIntro}\n${l.cleanerLeftoversPartialBanner}'
            : l.cleanerLeftoversIntro,
      ),
      if (hidden > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            l.cleanerLeftoversHiddenRecent(hidden),
            key: const ValueKey<String>('cleaner-leftovers-status'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];

    if (visible.isEmpty && !state.isScanning) {
      sections.add(
        Padding(
          key: const ValueKey<String>('cleaner-leftovers-empty'),
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              l.cleanerLeftoversEmpty,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    var order = 0;
    for (final reason in AppLeftoverReason.values) {
      final inReason = visible.where((c) => c.reason == reason).toList();
      if (inReason.isEmpty) continue;
      sections.add(
        CleanerStaggeredEntrance(
          key: ValueKey<String>('tier-${reason.name}'),
          index: order++,
          child: _TierHeader(reason: reason),
        ),
      );
      for (final location in AppLeftoverLocation.values) {
        final folders = inReason.where((c) => c.location == location).toList();
        if (folders.isEmpty) continue;
        final id = '${reason.name}-${location.name}';
        sections.add(
          CleanerStaggeredEntrance(
            key: ValueKey<String>('group-$id'),
            index: order++,
            child: _buildGroup(l, state, id, location, folders),
          ),
        );
      }
    }

    return ListView(
      key: const ValueKey<String>('cleaner-leftovers-list'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: sections,
    );
  }

  Widget _buildGroup(
    AppLocalizations l,
    CleanerAppLeftoversState state,
    String id,
    AppLeftoverLocation location,
    List<AppLeftoverCandidate> folders,
  ) {
    final theme = Theme.of(context);
    final size = folders.fold<int>(0, (sum, c) => sum + c.sizeBytes);
    final checked = folders
        .where((c) => state.selectedPaths.contains(c.path))
        .length;
    final allChecked = checked == folders.length;
    final expanded =
        (folders.length <= _autoExpandLimit) != _toggledGroups.contains(id);
    final showOpen = widget.onOpenFolder != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        key: ValueKey<String>('cleaner-leftovers-group-$id'),
        clipBehavior: Clip.antiAlias,
        decoration: CbDecorations.card(context, radius: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: ValueKey<String>('cleaner-leftovers-group-toggle-$id'),
              onTap: () => setState(() {
                _toggledGroups.contains(id)
                    ? _toggledGroups.remove(id)
                    : _toggledGroups.add(id);
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: _checkboxColumnWidth,
                      height: _checkboxColumnWidth,
                      child: Checkbox(
                        key: ValueKey<String>(
                          'cleaner-leftovers-group-check-$id',
                        ),
                        tristate: true,
                        value: allChecked
                            ? true
                            : (checked == 0 ? false : null),
                        onChanged: _cleaning
                            ? null
                            : (_) => widget.cubit.setSelected(
                                folders.map((c) => c.path),
                                !allChecked,
                              ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            locationLabel(l, location),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            l.cleanerLeftoversFolderCount(folders.length),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      FormatUtils.formatFileSize(size),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 22,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 1),
              _ColumnHeader(showOpen: showOpen),
              for (final folder in folders) ...[
                const Divider(height: 1),
                _FolderRow(
                  candidate: folder,
                  measurement: state.measurements[folder.path],
                  now: state.evaluatedAt,
                  selected: state.selectedPaths.contains(folder.path),
                  enabled: !_cleaning,
                  onToggle: () => widget.cubit.toggleSelected(folder.path),
                  onOpenFolder: widget.onOpenFolder == null
                      ? null
                      : () => widget.onOpenFolder!(folder.path),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(AppLocalizations l, CleanerAppLeftoversState state) {
    final theme = Theme.of(context);
    final selected = state.selectedCandidates;
    final summary = l.cleanerLeftoversSelected(
      FormatUtils.formatFileSize(state.selectedBytes),
      selected.length,
    );
    final summaryText = AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      child: Text(
        summary,
        key: ValueKey<String>(summary),
        style: theme.textTheme.titleSmall,
      ),
    );
    final cleanButton = FilledButton.icon(
      key: const ValueKey<String>('cleaner-leftovers-clean'),
      onPressed: selected.isEmpty || _cleaning || widget.onClean == null
          ? null
          : _cleanSelected,
      icon: const Icon(Icons.cleaning_services_outlined, size: 18),
      label: Text(
        l.cleanerLeftoversMoveTo(
          selected.length,
          FormatUtils.formatFileSize(state.selectedBytes),
          _destination(l),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _cleaning
                ? CleanerCleanProgress(progress: _cleanProgress)
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The summary and the button side by side need room; below
                // that the button gets its own full-width line.
                if (constraints.maxWidth < _wideFooterBreakpoint) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      summaryText,
                      const SizedBox(height: 8),
                      cleanButton,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: summaryText),
                    cleanButton,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String subtitle;
  final bool scanning;
  final bool enabled;
  final VoidCallback? onScan;
  final VoidCallback? onCancel;

  const _Header({
    required this.subtitle,
    required this.scanning,
    required this.enabled,
    required this.onScan,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            PhosphorIconsLight.folderDashed,
            size: 19,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.cleanerLeftoversTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  key: const ValueKey<String>('cleaner-leftovers-subtitle'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            key: const ValueKey<String>('cleaner-leftovers-rescan'),
            onPressed: !enabled
                ? null
                : scanning
                ? onCancel
                : onScan,
            icon: Icon(
              scanning ? Icons.stop_rounded : Icons.refresh_rounded,
              size: 18,
            ),
            label: Text(
              scanning ? l.diskCleanerCancel : l.diskCleanerScanAgain,
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final CleanerAppLeftoversCubit cubit;
  final CleanerAppLeftoversState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  const _Toolbar({
    required this.cubit,
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth = constraints.maxWidth < 560
            ? constraints.maxWidth
            : 280.0;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: searchWidth,
              height: 38,
              child: SearchTextField(
                key: const ValueKey<String>('cleaner-leftovers-search'),
                controller: searchController,
                onChanged: onSearchChanged,
                textAlignVertical: TextAlignVertical.center,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: l.cleanerLeftoversSearchHint,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ).flat(context, radius: 999),
              ),
            ),
            _SelectAll(cubit: cubit, state: state),
            PopupMenuButton<int>(
              key: const ValueKey<String>('cleaner-leftovers-inactive-menu'),
              tooltip: l.cleanerLeftoversInactiveLabel,
              onSelected: cubit.setInactiveDays,
              itemBuilder: (context) => <PopupMenuEntry<int>>[
                PopupMenuItem<int>(
                  enabled: false,
                  height: 32,
                  child: Text(l.cleanerLeftoversInactiveLabel),
                ),
                for (final days in cleanerLeftoverInactiveDayPresets)
                  CheckedPopupMenuItem<int>(
                    value: days,
                    checked: state.inactiveDays == days,
                    child: Text(_inactiveLabel(l, days)),
                  ),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history_rounded, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${l.cleanerLeftoversInactiveLabel}: '
                        '${_inactiveLabel(l, state.inactiveDays)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SelectAll extends StatelessWidget {
  final CleanerAppLeftoversCubit cubit;
  final CleanerAppLeftoversState state;

  const _SelectAll({required this.cubit, required this.state});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final total = state.visibleCandidates.length;
    final selected = state.selectedCandidates.length;
    final all = total > 0 && selected == total;
    void toggle() => all ? cubit.clearSelection() : cubit.selectAllVisible();
    return InkWell(
      key: const ValueKey<String>('cleaner-leftovers-select-all'),
      borderRadius: BorderRadius.circular(8),
      onTap: total == 0 ? null : toggle,
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              tristate: true,
              value: all ? true : (selected == 0 ? false : null),
              onChanged: total == 0 ? null : (_) => toggle(),
            ),
            Text(
              l.cleanerLeftoversSelectAll,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ],
        ),
      ),
    );
  }
}

/// Step card shown while folders are listed and measured.
class _ScanCard extends StatelessWidget {
  final String title;
  final String? detail;
  final double? value;

  const _ScanCard({super.key, required this.title, this.detail, this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: CbDecorations.card(context, radius: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    PhosphorIconsLight.magnifyingGlass,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(value: value, minHeight: 8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Column titles of a location card; widths match [_FolderRow].
class _ColumnHeader extends StatelessWidget {
  final bool showOpen;

  const _ColumnHeader({required this.showOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideRowBreakpoint;
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              const SizedBox(width: _checkboxColumnWidth),
              Expanded(
                child: Text(l.cleanerLeftoversColumnFolder, style: style),
              ),
              if (wide)
                SizedBox(
                  width: _dateColumnWidth,
                  child: Text(l.cleanerLeftoversColumnChanged, style: style),
                ),
              SizedBox(
                width: _sizeColumnWidth,
                child: Text(
                  l.cleanerLeftoversColumnSize,
                  textAlign: TextAlign.end,
                  style: style,
                ),
              ),
              if (showOpen) const SizedBox(width: _openColumnWidth),
            ],
          ),
        );
      },
    );
  }
}

/// One leftover folder: name, what makes it a leftover, when something
/// inside last changed, and its size, in fixed columns so rows scan easily.
class _FolderRow extends StatelessWidget {
  final AppLeftoverCandidate candidate;
  final AppLeftoverMeasurement? measurement;
  final DateTime now;
  final bool selected;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback? onOpenFolder;

  const _FolderRow({
    required this.candidate,
    required this.measurement,
    required this.now,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    required this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final muted = theme.colorScheme.onSurfaceVariant;
    final last = measurement?.lastModified;
    final newest = measurement?.newestEntry;
    final days = last == null ? null : now.difference(last).inDays;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _wideRowBreakpoint;
        // One short line per fact; a long path then cuts off alone instead of
        // swallowing the facts that follow it.
        final tags = <String>[
          if (candidate.reason == AppLeftoverReason.olderVersion)
            l.cleanerLeftoversReasonOlderVersion(
              candidate.relatedAppName ?? l.cleanerAppsUnknown,
            ),
          if (candidate.isPartial) l.cleanerLeftoversPartialSize,
        ];
        final notes = <String>[
          if (tags.isNotEmpty) tags.join(' • '),
          if (newest != null) l.cleanerLeftoversNewestFile(newest),
          // The date column is hidden on narrow rows.
          if (!wide)
            last == null
                ? l.cleanerLeftoversActivityUnknown
                : [
                    l.cleanerLeftoversLastModified(_dateText(last)),
                    if (days != null && days >= 0)
                      l.cleanerLeftoversDaysAgo(days),
                  ].join(' • '),
        ];
        return Material(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          child: InkWell(
            key: ValueKey<String>('cleaner-leftover-row-${candidate.path}'),
            onTap: enabled ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(
                children: [
                  SizedBox(
                    width: _checkboxColumnWidth,
                    height: _checkboxColumnWidth,
                    child: Checkbox(
                      value: selected,
                      onChanged: enabled ? (_) => onToggle() : null,
                    ),
                  ),
                  Expanded(
                    child: CbTooltip(
                      message: candidate.path,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            candidate.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          for (final note in notes)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (wide)
                    SizedBox(
                      width: _dateColumnWidth,
                      child: last == null
                          ? Text(
                              l.cleanerLeftoversActivityUnknown,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                              ),
                            )
                          : CbTooltip(
                              message: newest == null
                                  ? l.cleanerLeftoversChangedInFolder
                                  : l.cleanerLeftoversNewestFile(newest),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _dateText(last),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  if (days != null && days >= 0)
                                    Text(
                                      l.cleanerLeftoversDaysAgo(days),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: muted),
                                    ),
                                ],
                              ),
                            ),
                    ),
                  SizedBox(
                    width: _sizeColumnWidth,
                    child: Text(
                      FormatUtils.formatFileSize(candidate.sizeBytes),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onOpenFolder != null)
                    SizedBox(
                      width: _openColumnWidth,
                      height: _openColumnWidth,
                      child: IconButton(
                        key: ValueKey<String>(
                          'cleaner-leftover-open-${candidate.path}',
                        ),
                        tooltip: l.openFolder,
                        padding: EdgeInsets.zero,
                        onPressed: onOpenFolder,
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A quiet note, not a warning: the delete confirmation carries the warning.
class _InfoBar extends StatelessWidget {
  final String text;

  const _InfoBar({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _TierHeader extends StatelessWidget {
  final AppLeftoverReason reason;

  const _TierHeader({required this.reason});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final (title, hint, color) = switch (reason) {
      AppLeftoverReason.noInstalledApp => (
        l.cleanerLeftoversTierNoApp,
        l.cleanerLeftoversTierNoAppHint,
        Colors.orange.shade800,
      ),
      AppLeftoverReason.olderVersion => (
        l.cleanerLeftoversTierOlder,
        l.cleanerLeftoversTierOlderHint,
        Colors.teal.shade700,
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final VoidCallback? onScan;

  const _Intro({super.key, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIconsLight.folderDashed,
                size: 44,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                l.cleanerLeftoversIntro,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey<String>('cleaner-leftovers-scan'),
                onPressed: onScan,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: Text(l.cleanerLeftoversScan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  final Widget icon;
  final String message;

  const _CenteredStatus({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final String text;

  const _Warning({required this.text});

  @override
  Widget build(BuildContext context) {
    final color = Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

String _inactiveLabel(AppLocalizations l, int days) => days <= 0
    ? l.cleanerLeftoversInactiveAny
    : l.cleanerLeftoversInactiveDays(days);

/// Windows locations have names; macOS and Linux ones are shown as the
/// home-relative folder they are.
@visibleForTesting
String locationLabel(AppLocalizations l, AppLeftoverLocation location) {
  return switch (location) {
    AppLeftoverLocation.localAppData => l.cleanerLeftoversLocationLocal,
    AppLeftoverLocation.roamingAppData => l.cleanerLeftoversLocationRoaming,
    AppLeftoverLocation.localLowAppData => l.cleanerLeftoversLocationLocalLow,
    AppLeftoverLocation.programData => l.cleanerLeftoversLocationProgramData,
    AppLeftoverLocation.userPrograms => l.cleanerLeftoversLocationUserPrograms,
    AppLeftoverLocation.programFiles => l.cleanerLeftoversLocationProgramFiles,
    AppLeftoverLocation.macContainers => '~/Library/Containers',
    AppLeftoverLocation.macGroupContainers => '~/Library/Group Containers',
    AppLeftoverLocation.macApplicationSupport =>
      '~/Library/Application Support',
    AppLeftoverLocation.macCaches => '~/Library/Caches',
    AppLeftoverLocation.linuxConfig => '~/.config',
    AppLeftoverLocation.linuxData => '~/.local/share',
    AppLeftoverLocation.linuxCache => '~/.cache',
    AppLeftoverLocation.linuxFlatpak => '~/.var/app',
    AppLeftoverLocation.linuxSnap => '~/snap',
  };
}

String _dateText(DateTime date) {
  final local = date.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}';
}
