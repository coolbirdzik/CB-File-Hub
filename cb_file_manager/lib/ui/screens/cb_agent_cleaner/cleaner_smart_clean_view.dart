import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../bloc/cleaner_smart_clean/cleaner_smart_clean.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../services/disk_cleaner/cleaner_item_origin.dart';
import '../../utils/format_utils.dart';
import '../../widgets/app_progress_indicator.dart';
import 'cleaner_progress_widgets.dart';
import 'installed_app_icon.dart';
import 'cleaner_old_files_panel.dart';
import 'cleaner_audit_labels.dart';
import '../../../services/disk_cleaner/cleaner_review_candidates.dart';

/// Expanded rows list at most this many files.
const int _maxListedItems = 50;

/// Start, scan and result cards stay readable on wide panes.
const double _cardMaxWidth = 560;

/// Below this width the footer stacks the summary above the button.
const double _wideFooterBreakpoint = 560;

const double _checkboxColumnWidth = 40;

/// Smart Clean, laid out like the other Cleaner pages: a header with the
/// page's state, the body, and a footer with the selection and the action.
/// All scanning and cleaning goes through [cubit].
class CleanerSmartCleanView extends StatefulWidget {
  final CleanerSmartCleanCubit cubit;

  /// Categories the scan checks, listed on the start card.
  final List<String> categoryIds;

  final String Function(String categoryId) categoryTitle;
  final String Function(String categoryId) categoryReason;

  /// False while another Cleaner scan or cleanup runs.
  final bool enabled;

  /// macOS moves to the Trash instead of the Recycle Bin.
  final bool usesTrash;
  final ValueChanged<String>? onOpenReviewFile;

  const CleanerSmartCleanView({
    super.key,
    required this.cubit,
    required this.categoryIds,
    required this.categoryTitle,
    required this.categoryReason,
    this.enabled = true,
    this.usesTrash = false,
    this.onOpenReviewFile,
  });

  @override
  State<CleanerSmartCleanView> createState() => _CleanerSmartCleanViewState();
}

class _CleanerSmartCleanViewState extends State<CleanerSmartCleanView> {
  final Set<String> _expanded = <String>{};

  /// [CleanerSmartCleanState.sourceId]s whose files are listed.
  final Set<String> _expandedSources = <String>{};

  CleanerSmartCleanCubit get _cubit => widget.cubit;

  String _destination(AppLocalizations l) =>
      widget.usesTrash ? l.trashBin : l.diskCleanerRecycleBinLabel;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CleanerSmartCleanCubit, CleanerSmartCleanState>(
      bloc: _cubit,
      listenWhen: (previous, current) =>
          current.status == CleanerSmartCleanStatus.scanning &&
          previous.status != CleanerSmartCleanStatus.scanning,
      listener: (context, state) => setState(() {
        _expanded.clear();
        _expandedSources.clear();
      }),
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final hasList =
            (state.status == CleanerSmartCleanStatus.ready ||
                state.status == CleanerSmartCleanStatus.cleaning) &&
            state.groups.isNotEmpty;
        return Column(
          key: const ValueKey<String>('cleaner-smart-clean-view'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              subtitle: _subtitle(l, state),
              action: _headerAction(l, state),
            ),
            const SizedBox(height: CbSpacing.xs),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.98, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey<String>(_bodyId(state)),
                  child: _buildBody(l, state),
                ),
              ),
            ),
            if (hasList) _buildFooter(l, state),
          ],
        );
      },
    );
  }

  /// Changes only when the body's layout changes, not on every progress tick.
  static String _bodyId(CleanerSmartCleanState state) => switch (state.status) {
    CleanerSmartCleanStatus.idle ||
    CleanerSmartCleanStatus.failure => 'cleaner-smart-clean-phase-start',
    CleanerSmartCleanStatus.scanning => 'cleaner-smart-clean-phase-scanning',
    CleanerSmartCleanStatus.ready || CleanerSmartCleanStatus.cleaning =>
      state.groups.isEmpty &&
              state.reviewCandidates.isEmpty &&
              state.scanWarnings.isEmpty
          ? 'cleaner-smart-clean-phase-empty'
          : 'cleaner-smart-clean-phase-list',
    CleanerSmartCleanStatus.done => 'cleaner-smart-clean-phase-done',
  };

  String _subtitle(AppLocalizations l, CleanerSmartCleanState state) {
    switch (state.status) {
      case CleanerSmartCleanStatus.scanning:
        final id = state.scanCategoryId;
        return id == null
            ? l.cleanerSmartCleanPreparing
            : l.cleanerSmartCleanScanningCategory(widget.categoryTitle(id));
      case CleanerSmartCleanStatus.ready:
        if (state.groups.isEmpty) {
          return state.reviewCandidates.isEmpty
              ? l.diskCleanerQuickCleanNothing
              : l.cleanerReviewSectionsTitle;
        }
        final found = state.groups
            .where((g) => !g.isPermanent)
            .fold<int>(0, (sum, g) => sum + g.bytes);
        return l.cleanerSmartCleanReclaimable(
          FormatUtils.formatFileSize(found),
        );
      case CleanerSmartCleanStatus.cleaning:
        return widget.usesTrash
            ? l.moveToTrash
            : l.diskCleanerMovingToRecycleBin;
      case CleanerSmartCleanStatus.idle:
      case CleanerSmartCleanStatus.failure:
      case CleanerSmartCleanStatus.done:
        return l.cleanerSmartCleanUtilityDescription;
    }
  }

  /// Cancel while scanning, Scan again once there is something to redo. The
  /// start card has its own Scan button, so the header stays empty there.
  Widget? _headerAction(AppLocalizations l, CleanerSmartCleanState state) {
    switch (state.status) {
      case CleanerSmartCleanStatus.scanning:
        return CbButton(
          key: const ValueKey<String>('cleaner-smart-clean-cancel'),
          onPressed: _cubit.cancelScan,
          icon: PhosphorIconsLight.stop,
          label: l.diskCleanerCancel,
        );
      case CleanerSmartCleanStatus.ready:
      case CleanerSmartCleanStatus.cleaning:
      case CleanerSmartCleanStatus.done:
        return CbButton(
          key: const ValueKey<String>('cleaner-smart-clean-rescan'),
          onPressed:
              widget.enabled && state.status != CleanerSmartCleanStatus.cleaning
              ? _cubit.scan
              : null,
          icon: PhosphorIconsLight.arrowClockwise,
          label: l.diskCleanerScanAgain,
        );
      case CleanerSmartCleanStatus.idle:
      case CleanerSmartCleanStatus.failure:
        return null;
    }
  }

  Widget _buildBody(AppLocalizations l, CleanerSmartCleanState state) {
    switch (state.status) {
      case CleanerSmartCleanStatus.idle:
      case CleanerSmartCleanStatus.failure:
        return _CenteredCard(child: _buildStart(l, state));
      case CleanerSmartCleanStatus.scanning:
        return _CenteredCard(child: _buildScanning(l, state));
      case CleanerSmartCleanStatus.ready:
      case CleanerSmartCleanStatus.cleaning:
        if (state.groups.isEmpty &&
            state.reviewCandidates.isEmpty &&
            state.scanWarnings.isEmpty) {
          return _CenteredCard(
            child: _Message(
              icon: PhosphorIconsLight.checkCircle,
              title: l.cleanerSmartCleanAllCleanTitle,
              body: l.diskCleanerQuickCleanNothing,
            ),
          );
        }
        return _buildList(l, state);
      case CleanerSmartCleanStatus.done:
        if (state.reviewCandidates.isNotEmpty ||
            state.scanWarnings.isNotEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildDone(l, state),
              const SizedBox(height: 16),
              ..._reviewPanels(l, state),
            ],
          );
        }
        return _CenteredCard(child: _buildDone(l, state));
    }
  }

  // ---------------------------------------------------------------------------
  // Start
  // ---------------------------------------------------------------------------

  Widget _buildStart(AppLocalizations l, CleanerSmartCleanState state) {
    final c = context.cbColors;
    final error = switch (state.error) {
      CleanerSmartCleanError.busy => l.cleanerSmartCleanBusy,
      CleanerSmartCleanError.failed => l.diskCleanerScanFailedMsg(
        state.errorMessage ?? '',
      ),
      null => null,
    };
    final scanButton = CbButton(
      key: const ValueKey<String>('cleaner-smart-clean-scan'),
      variant: CbButtonVariant.primary,
      size: CbButtonSize.lg,
      onPressed: widget.enabled ? _cubit.scan : null,
      icon: PhosphorIconsLight.magnifyingGlass,
      label: l.cleanerSmartCleanScan,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _IconTile(icon: PhosphorIconsLight.broom, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Text(l.cleanerSmartCleanIntro, style: CbTypography.body),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          l.cleanerSmartCleanChecksLabel,
          style: CbTypography.labelSm.copyWith(
            color: c.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 400 ? 2 : 1;
            final itemWidth =
                (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final id in widget.categoryIds)
                  SizedBox(
                    width: itemWidth,
                    child: Row(
                      children: [
                        _IconTile(
                          icon: _categoryIcon(id),
                          size: 28,
                          danger: id == _recycleBinId,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.categoryTitle(id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CbTypography.body,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          _Banner(
            icon: PhosphorIconsLight.warningCircle,
            text: error,
            color: c.status.danger,
          ),
        ],
        const SizedBox(height: 16),
        const SizedBox(height: CbSpacing.xs),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final note = _Note(
              icon: PhosphorIconsLight.shieldCheck,
              text: l.diskCleanerQuickCleanSafetyNote,
            );
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  note,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: scanButton),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: note),
                const SizedBox(width: 16),
                scanButton,
              ],
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  Widget _buildScanning(AppLocalizations l, CleanerSmartCleanState state) {
    final c = context.cbColors;
    final id = state.scanCategoryId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _IconTile(
              icon: id == null
                  ? PhosphorIconsLight.magnifyingGlass
                  : _categoryIcon(id),
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    id == null
                        ? l.cleanerSmartCleanPreparing
                        : l.cleanerSmartCleanScanningCategory(
                            widget.categoryTitle(id),
                          ),
                    style: CbTypography.headingSm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    state.scanPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CbTypography.bodySm.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: AppProgressIndicator(
            value: state.scanFraction,
            height: 3,
            backgroundColor: c.fill,
            valueColor: c.accent.base,
            showGlow: false,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  Widget _buildList(AppLocalizations l, CleanerSmartCleanState state) {
    final cleaning = state.status == CleanerSmartCleanStatus.cleaning;
    final total = state.groups.fold<int>(0, (sum, g) => sum + g.bytes);
    final recycleNote = widget.usesTrash
        ? l.cleanerSmartCleanDoneHint(_destination(l))
        : l.diskCleanerQuickCleanRecycleNote;
    return ListView(
      key: const ValueKey<String>('cleaner-smart-clean-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Banner(
          icon: PhosphorIconsLight.info,
          text: state.groups.isEmpty
              ? l.diskCleanerQuickCleanNothing
              : '${l.diskCleanerQuickCleanSafetyNote}\n$recycleNote',
        ),
        const SizedBox(height: 12),
        if (state.groups.isNotEmpty)
          CleanerStaggeredEntrance(
            index: 0,
            child: CbSurface(
              clip: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, group) in state.groups.indexed) ...[
                    if (index > 0) const SizedBox(height: CbSpacing.xs),
                    _GroupRow(
                      group: group,
                      selection: state.groupSelection(group.categoryId),
                      share: total == 0 ? 0 : group.bytes / total,
                      title: widget.categoryTitle(group.categoryId),
                      reason: group.isPermanent
                          ? l.cleanerSmartCleanRecycleBinWarning
                          : widget.categoryReason(group.categoryId),
                      apps: group.isPermanent ? const [] : group.topApps(),
                      icon: _categoryIcon(group.categoryId),
                      enabled: !cleaning,
                      expanded: _expanded.contains(group.categoryId),
                      onToggle: () => _cubit.toggleGroup(group.categoryId),
                      onExpand: () => setState(() {
                        _expanded.contains(group.categoryId)
                            ? _expanded.remove(group.categoryId)
                            : _expanded.add(group.categoryId);
                      }),
                      isSourceSelected: (key) =>
                          state.isSourceSelected(group.categoryId, key),
                      onToggleSource: (key) =>
                          _cubit.toggleSource(group.categoryId, key),
                      isSourceExpanded: (key) => _expandedSources.contains(
                        CleanerSmartCleanState.sourceId(group.categoryId, key),
                      ),
                      onExpandSource: (key) => setState(() {
                        final id = CleanerSmartCleanState.sourceId(
                          group.categoryId,
                          key,
                        );
                        if (!_expandedSources.remove(id)) {
                          _expandedSources.add(id);
                        }
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (state.reviewCandidates.isNotEmpty ||
            state.scanWarnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          ..._reviewPanels(l, state),
        ],
      ],
    );
  }

  Widget _buildFooter(AppLocalizations l, CleanerSmartCleanState state) {
    final c = context.cbColors;
    final cleaning = state.status == CleanerSmartCleanStatus.cleaning;
    final size = FormatUtils.formatFileSize(state.selectedBytes);
    final summary = Text(
      l.cleanerSmartCleanSelected(size, state.selectedCount),
      key: const ValueKey<String>('cleaner-smart-clean-summary'),
      style: CbTypography.headingSm.copyWith(color: c.textPrimary),
    );
    final cleanButton = CbButton(
      key: const ValueKey<String>('cleaner-smart-clean-clean'),
      variant: CbButtonVariant.primary,
      size: CbButtonSize.lg,
      onPressed: widget.enabled && !cleaning && state.selectedCount > 0
          ? () => _clean(state)
          : null,
      icon: PhosphorIconsLight.broom,
      label: l.cleanerSmartCleanCleanButton(size),
    );
    return Container(
      decoration: CbDecorations.bar(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: cleaning
                ? _CleanProgress(
                    done: state.cleanDone,
                    total: state.cleanTotal,
                    path: state.cleanPath,
                  )
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < _wideFooterBreakpoint) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [summary, const SizedBox(height: 8), cleanButton],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: summary),
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

  List<Widget> _reviewPanels(AppLocalizations l, CleanerSmartCleanState state) {
    final byCategory = <String, List<CleanerFileReviewCandidate>>{};
    for (final item in state.reviewCandidates) {
      byCategory.putIfAbsent(item.categoryId, () => []).add(item);
    }
    return [
      if (state.scanWarnings.isNotEmpty)
        CbSurface(
          child: CbExpander(
            key: const ValueKey('cleaner-scan-warnings'),
            title: Text(l.cleanerScanWarnings(state.scanWarnings.length)),
            leading: const Icon(PhosphorIconsLight.warning),
            children: [
              for (final warning in state.scanWarnings)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(warning),
                ),
            ],
          ),
        ),
      for (final entry in byCategory.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: CleanerOldFilesPanel(
            key: ValueKey('review-category-${entry.key}'),
            categoryId: entry.key,
            candidates: entry.value,
            title: CleanerAuditLabels.title(l, entry.key),
            description: CleanerAuditLabels.reason(l, entry.key),
            onOpenFile: widget.onOpenReviewFile,
          ),
        ),
    ];
  }

  /// Recycle Bin entries cannot be restored, so including them asks first.
  Future<void> _clean(CleanerSmartCleanState state) async {
    if (state.selectedIncludesPermanent) {
      final l = AppLocalizations.of(context)!;
      final permanentBytes = state.selectedPermanentBytes;
      final confirmed = await CbDialog.show<bool>(
        context: context,
        dialog: CbDialog(
          title: l.cleanerSmartCleanPermanentConfirmTitle,
          icon: PhosphorIconsLight.trash,
          destructive: true,
          showCloseButton: false,
          content: Text(
            l.cleanerSmartCleanPermanentConfirmBody(
              FormatUtils.formatFileSize(permanentBytes),
            ),
          ),
          actions: [
            CbButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              label: l.cancel,
            ),
            CbButton(
              key: const ValueKey<String>(
                'cleaner-smart-clean-confirm-permanent',
              ),
              variant: CbButtonVariant.danger,
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              label: l.cleanerSmartCleanConfirmClean,
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _cubit.clean();
  }

  // ---------------------------------------------------------------------------
  // Done
  // ---------------------------------------------------------------------------

  Widget _buildDone(AppLocalizations l, CleanerSmartCleanState state) {
    final c = context.cbColors;
    final result = state.result ?? const CleanerSmartCleanResult();
    final lines = <String>[
      if (result.movedCount > 0)
        l.cleanerSmartCleanDoneMoved(
          FormatUtils.formatFileSize(result.movedBytes),
          _destination(l),
        ),
      if (result.permanentCount > 0)
        l.cleanerSmartCleanDonePermanent(
          FormatUtils.formatFileSize(result.permanentBytes),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Message(
          icon: PhosphorIconsLight.checkCircle,
          title: l.cleanerSmartCleanDoneTitle,
          body: lines.join('\n'),
        ),
        if (result.skippedCount > 0) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 58),
            child: Text(
              l.cleanerSmartCleanDoneSkipped(result.skippedCount),
              style: CbTypography.bodySm.copyWith(color: c.textSecondary),
            ),
          ),
        ],
        if (result.movedCount > 0) ...[
          const SizedBox(height: 14),
          _Banner(
            icon: PhosphorIconsLight.info,
            text: l.cleanerSmartCleanDoneHint(_destination(l)),
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: CbButton(
            key: const ValueKey<String>('cleaner-smart-clean-done'),
            variant: CbButtonVariant.primary,
            size: CbButtonSize.lg,
            onPressed: _cubit.reset,
            label: l.done,
          ),
        ),
      ],
    );
  }
}

const String _recycleBinId = 'recycle_bin';

IconData _categoryIcon(String categoryId) => switch (categoryId) {
  'windows_temp' => PhosphorIconsLight.hourglass,
  'browser_cache' => PhosphorIconsLight.globe,
  'thumbnail_cache' => PhosphorIconsLight.image,
  'app_cache' => PhosphorIconsLight.squaresFour,
  'crash_dumps_logs' => PhosphorIconsLight.warningCircle,
  'system_cache' => PhosphorIconsLight.cpu,
  'package_download_cache' => PhosphorIconsLight.package,
  'electron_cache' => PhosphorIconsLight.code,
  'xcode_build_cache' => PhosphorIconsLight.hammer,
  'old_downloads_review' => PhosphorIconsLight.clock,
  'developer_analysis_cache' => PhosphorIconsLight.code,
  'developer_download_cache' => PhosphorIconsLight.package,
  'electron_crash_reports' => PhosphorIconsLight.warningCircle,
  _recycleBinId => PhosphorIconsLight.trash,
  _ => PhosphorIconsLight.broom,
};

class _Header extends StatelessWidget {
  final String subtitle;
  final Widget? action;

  const _Header({required this.subtitle, required this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: ConstrainedBox(
        // Keeps the header height steady when the action appears.
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          children: [
            Icon(PhosphorIconsLight.sparkle, size: 19, color: c.accent.base),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.cleanerSmartCleanTitle,
                    style: CbTypography.headingSm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    key: const ValueKey<String>('cleaner-smart-clean-subtitle'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CbTypography.bodySm.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 12), action!],
          ],
        ),
      ),
    );
  }
}

/// A card centred in the pane, scrolling when the pane is short.
class _CenteredCard extends StatelessWidget {
  final Widget child;

  const _CenteredCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _cardMaxWidth),
          child: CbSurface(
            padding: const EdgeInsets.all(CbSpacing.xxl),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Tinted rounded square behind an icon, as used across the Cleaner.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool danger;

  const _IconTile({
    required this.icon,
    required this.size,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final color = danger ? c.status.danger : c.icon;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: danger ? c.status.dangerSurface : c.fill,
        borderRadius: BorderRadius.circular(size >= 40 ? 12 : 8),
      ),
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }
}

/// Icon tile, title and body: the empty and done states.
class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _Message({required this.icon, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IconTile(icon: icon, size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: CbTypography.headingMd.copyWith(color: c.textPrimary),
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(body, style: CbTypography.body),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final color = c.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: CbTypography.bodySm.copyWith(color: color)),
        ),
      ],
    );
  }
}

/// A quiet note bar; [color] tints it for errors.
class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _Banner({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final accent = color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent == null ? c.fillSubtle : accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: accent ?? c.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: CbTypography.bodySm.copyWith(color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pointer feedback for a selectable row. Its checkbox and disclosure retain
/// separate keyboard stops, so opening details never changes the selection.
class _SelectableRow extends StatelessWidget {
  final bool selected;
  final VoidCallback? onPressed;
  final Widget child;

  const _SelectableRow({
    required this.selected,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => CbPressable(
    onPressed: onPressed,
    canRequestFocus: false,
    descendantsAreFocusable: true,
    builder: (context, state) => AnimatedContainer(
      duration: CbDurations.fast,
      decoration: CbDecorations.card(
        context,
        selected: selected,
        hovered: state.hovered,
        pressed: state.pressed,
      ),
      child: child,
    ),
  );
}

/// Three-state selection using the app's fill, focus and pointer conventions.
class _SelectionCheckbox extends StatelessWidget {
  final bool? value;
  final String label;
  final ValueChanged<bool>? onChanged;

  const _SelectionCheckbox({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final enabled = onChanged != null;
    void toggle() => onChanged?.call(value != true);
    return Semantics(
      label: label,
      checked: value == true,
      mixed: value == null,
      enabled: enabled,
      onTap: enabled ? toggle : null,
      child: ExcludeSemantics(
        child: CbPressable(
          onPressed: enabled ? toggle : null,
          builder: (context, state) => Center(
            child: AnimatedContainer(
              duration: CbDurations.instant,
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: !enabled
                    ? c.fillSubtle
                    : value != false
                    ? c.accent.base
                    : CbDecorations.controlFill(
                        c,
                        hovered: state.hovered,
                        pressed: state.pressed,
                      ),
                borderRadius: CbRadii.all(CbRadii.sm),
                border: value == false
                    ? Border.all(
                        color: enabled ? c.strokeStrong : c.strokeSubtle,
                      )
                    : null,
                boxShadow: state.focused ? CbDecorations.focusRing(c) : null,
              ),
              child: value == false
                  ? null
                  : Icon(
                      value == null
                          ? PhosphorIconsLight.minus
                          : PhosphorIconsLight.check,
                      size: 13,
                      color: enabled ? c.accent.onBase : c.textDisabled,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One category: checkbox, what it is, its share of the found junk, and on
/// demand the apps that made it, each with its own checkbox.
class _GroupRow extends StatelessWidget {
  final CleanerSmartCleanGroup group;

  /// Tristate: null when only some sources are checked.
  final bool? selection;
  final double share;
  final String title;
  final String reason;

  /// Recognised apps holding most of the group.
  final List<String> apps;
  final IconData icon;
  final bool enabled;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onExpand;
  final bool Function(String sourceKey) isSourceSelected;
  final void Function(String sourceKey) onToggleSource;
  final bool Function(String sourceKey) isSourceExpanded;
  final void Function(String sourceKey) onExpandSource;

  const _GroupRow({
    required this.group,
    required this.selection,
    required this.share,
    required this.title,
    required this.reason,
    required this.apps,
    required this.icon,
    required this.enabled,
    required this.expanded,
    required this.onToggle,
    required this.onExpand,
    required this.isSourceSelected,
    required this.onToggleSource,
    required this.isSourceExpanded,
    required this.onExpandSource,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l = AppLocalizations.of(context)!;
    final muted = c.textSecondary;
    final accent = group.isPermanent ? c.status.danger : c.accent.base;

    return Column(
      key: ValueKey<String>('cleaner-smart-clean-group-${group.categoryId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SelectableRow(
          selected: selection != false,
          onPressed: enabled ? onToggle : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 6, 10),
            child: Row(
              children: [
                SizedBox(
                  width: _checkboxColumnWidth,
                  height: _checkboxColumnWidth,
                  child: _SelectionCheckbox(
                    key: ValueKey<String>(
                      'cleaner-smart-clean-toggle-${group.categoryId}',
                    ),
                    value: selection,
                    label: title,
                    onChanged: enabled ? (_) => onToggle() : null,
                  ),
                ),
                _IconTile(icon: icon, size: 32, danger: group.isPermanent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CbTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (group.isPermanent) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: c.status.danger.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                l.cleanerSmartCleanPermanentBadge,
                                style: CbTypography.labelXs.copyWith(
                                  color: c.status.danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: CbTypography.bodySm.copyWith(
                          color: group.isPermanent ? c.status.danger : muted,
                        ),
                      ),
                      if (apps.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          l.cleanerSmartCleanMostlyFrom(apps.join(', ')),
                          key: ValueKey<String>(
                            'cleaner-smart-clean-apps-${group.categoryId}',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.bodySm.copyWith(
                            color: c.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      _ShareBar(share: share, color: accent),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 84,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        FormatUtils.formatFileSize(group.bytes),
                        style: CbTypography.headingSm.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        l.cleanerSmartCleanItemCount(group.items.length),
                        style: CbTypography.bodySm.copyWith(color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                CbButton.icon(
                  key: ValueKey<String>(
                    'cleaner-smart-clean-expand-${group.categoryId}',
                  ),
                  onPressed: onExpand,
                  tooltip: l.viewDetails,
                  icon: expanded
                      ? PhosphorIconsLight.caretUp
                      : PhosphorIconsLight.caretDown,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            color: c.fillSubtle,
            padding: const EdgeInsets.fromLTRB(_checkboxColumnWidth, 2, 6, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, source) in group.sources.indexed) ...[
                  if (index > 0) const SizedBox(height: CbSpacing.xs),
                  _SourceRow(
                    categoryId: group.categoryId,
                    source: source,
                    selected: isSourceSelected(source.key),
                    enabled: enabled,
                    expanded: isSourceExpanded(source.key),
                    onToggle: () => onToggleSource(source.key),
                    onExpand: () => onExpandSource(source.key),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One app's files of one kind: who made them, what they are, what removing
/// them costs, and the files themselves on demand.
class _SourceRow extends StatelessWidget {
  final String categoryId;
  final CleanerSmartCleanSource source;
  final bool selected;
  final bool enabled;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onExpand;

  const _SourceRow({
    required this.categoryId,
    required this.source,
    required this.selected,
    required this.enabled,
    required this.expanded,
    required this.onToggle,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l = AppLocalizations.of(context)!;
    final muted = c.textSecondary;
    final origin = source.origin;
    final impactColor = switch (origin.impact) {
      CleanerItemImpact.rebuilt || CleanerItemImpact.leftover => c.accent.base,
      CleanerItemImpact.redownload => c.textSecondary,
      CleanerItemImpact.diagnostic => c.textSecondary,
      CleanerItemImpact.permanent => c.status.danger,
    };
    final id = CleanerSmartCleanState.sourceId(categoryId, source.key);
    final hidden = source.items.length - _maxListedItems;
    final installed = origin.installedApp;

    return Column(
      key: ValueKey<String>('cleaner-smart-clean-source-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SelectableRow(
          selected: selected,
          onPressed: enabled ? onToggle : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _checkboxColumnWidth,
                  height: _checkboxColumnWidth,
                  child: _SelectionCheckbox(
                    key: ValueKey<String>(
                      'cleaner-smart-clean-source-toggle-$id',
                    ),
                    value: selected,
                    label: _sourceTitle(l, source),
                    onChanged: enabled ? (_) => onToggle() : null,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: installed == null
                      ? _IconTile(
                          icon: _kindIcon(origin.kind),
                          size: 28,
                          danger: origin.kind == CleanerItemKind.deletedFile,
                        )
                      : InstalledAppIcon(
                          key: ValueKey<String>(
                            'cleaner-smart-clean-source-icon-$id',
                          ),
                          app: installed,
                          size: 28,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sourceTitle(l, source),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _Tag(
                              text: _kindLabel(l, origin.kind),
                              color: muted,
                            ),
                            _Tag(
                              text: _impactLabel(l, origin.impact),
                              color: impactColor,
                            ),
                            if (installed != null)
                              _Tag(
                                text: l.cleanerSmartCleanInstalledBadge,
                                color: c.textSecondary,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _kindInfo(l, origin.kind),
                          style: CbTypography.bodySm.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 84,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          FormatUtils.formatFileSize(source.bytes),
                          style: CbTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          l.cleanerSmartCleanItemCount(source.items.length),
                          style: CbTypography.bodySm.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                CbButton.icon(
                  key: ValueKey<String>(
                    'cleaner-smart-clean-source-expand-$id',
                  ),
                  onPressed: onExpand,
                  tooltip: l.viewDetails,
                  icon: expanded
                      ? PhosphorIconsLight.caretUp
                      : PhosphorIconsLight.caretDown,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _checkboxColumnWidth + 4,
              0,
              56,
              8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final item in source.items.take(_maxListedItems))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: CbTooltip(
                            message: item.originalPath ?? item.path,
                            child: Text(
                              item.originalPath ?? item.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: CbTypography.monoSm,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          FormatUtils.formatFileSize(item.sizeBytes),
                          style: CbTypography.bodySm.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l.cleanerSmartCleanMoreItems(hidden),
                      style: CbTypography.bodySm.copyWith(color: muted),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Small rounded label, tinted by [color].
class _Tag extends StatelessWidget {
  final String text;
  final Color color;

  const _Tag({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: CbDecorations.tint(context, color),
      child: Text(
        text,
        style: CbTypography.labelXs.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _sourceTitle(AppLocalizations l, CleanerSmartCleanSource source) {
  if (source.mergedCount > 0) {
    return l.cleanerSmartCleanOtherSources(source.mergedCount);
  }
  final origin = source.origin;
  final app = origin.app;
  if (app == null) {
    return origin.kind == CleanerItemKind.deletedFile
        ? l.cleanerSmartCleanKindDeletedFile
        : l.cleanerSmartCleanUnknownApp;
  }
  return origin.appIsFolder ? l.cleanerSmartCleanFolderSource(app) : app;
}

IconData _kindIcon(CleanerItemKind kind) => switch (kind) {
  CleanerItemKind.webCache => PhosphorIconsLight.globe,
  CleanerItemKind.codeCache => PhosphorIconsLight.code,
  CleanerItemKind.gpuCache => PhosphorIconsLight.cpu,
  CleanerItemKind.appCache => PhosphorIconsLight.squaresFour,
  CleanerItemKind.thumbnailCache => PhosphorIconsLight.image,
  CleanerItemKind.tempFile => PhosphorIconsLight.hourglass,
  CleanerItemKind.installer => PhosphorIconsLight.package,
  CleanerItemKind.log => PhosphorIconsLight.fileText,
  CleanerItemKind.crashReport => PhosphorIconsLight.warningCircle,
  CleanerItemKind.deletedFile => PhosphorIconsLight.trash,
  CleanerItemKind.other => PhosphorIconsLight.dotsThree,
  CleanerItemKind.packageDownload => PhosphorIconsLight.package,
  CleanerItemKind.buildCache => PhosphorIconsLight.hammer,
  CleanerItemKind.analysisCache => PhosphorIconsLight.code,
};

String _kindLabel(AppLocalizations l, CleanerItemKind kind) => switch (kind) {
  CleanerItemKind.webCache => l.cleanerSmartCleanKindWebCache,
  CleanerItemKind.codeCache => l.cleanerSmartCleanKindCodeCache,
  CleanerItemKind.gpuCache => l.cleanerSmartCleanKindGpuCache,
  CleanerItemKind.appCache => l.cleanerSmartCleanKindAppCache,
  CleanerItemKind.thumbnailCache => l.cleanerSmartCleanKindThumbnailCache,
  CleanerItemKind.tempFile => l.cleanerSmartCleanKindTempFile,
  CleanerItemKind.installer => l.cleanerSmartCleanKindInstaller,
  CleanerItemKind.log => l.cleanerSmartCleanKindLog,
  CleanerItemKind.crashReport => l.cleanerSmartCleanKindCrashReport,
  CleanerItemKind.deletedFile => l.cleanerSmartCleanKindDeletedFile,
  CleanerItemKind.other => l.cleanerSmartCleanKindOther,
  CleanerItemKind.packageDownload => l.diskCleanerCategoryPackageDownloads,
  CleanerItemKind.buildCache => l.diskCleanerCategoryXcodeBuild,
  CleanerItemKind.analysisCache => l.cleanerDeveloperAnalysisTitle,
};

String _kindInfo(AppLocalizations l, CleanerItemKind kind) => switch (kind) {
  CleanerItemKind.webCache => l.cleanerSmartCleanKindWebCacheInfo,
  CleanerItemKind.codeCache => l.cleanerSmartCleanKindCodeCacheInfo,
  CleanerItemKind.gpuCache => l.cleanerSmartCleanKindGpuCacheInfo,
  CleanerItemKind.appCache => l.cleanerSmartCleanKindAppCacheInfo,
  CleanerItemKind.thumbnailCache => l.cleanerSmartCleanKindThumbnailCacheInfo,
  CleanerItemKind.tempFile => l.cleanerSmartCleanKindTempFileInfo,
  CleanerItemKind.installer => l.cleanerSmartCleanKindInstallerInfo,
  CleanerItemKind.log => l.cleanerSmartCleanKindLogInfo,
  CleanerItemKind.crashReport => l.cleanerSmartCleanKindCrashReportInfo,
  CleanerItemKind.deletedFile => l.cleanerSmartCleanKindDeletedFileInfo,
  CleanerItemKind.other => l.cleanerSmartCleanKindOtherInfo,
  CleanerItemKind.packageDownload => l.diskCleanerReasonPackageDownloads,
  CleanerItemKind.buildCache => l.diskCleanerReasonXcodeBuild,
  CleanerItemKind.analysisCache => l.cleanerDeveloperAnalysisReason,
};

String _impactLabel(AppLocalizations l, CleanerItemImpact impact) =>
    switch (impact) {
      CleanerItemImpact.rebuilt => l.cleanerSmartCleanImpactRebuilt,
      CleanerItemImpact.leftover => l.cleanerSmartCleanImpactLeftover,
      CleanerItemImpact.diagnostic => l.cleanerSmartCleanImpactDiagnostic,
      CleanerItemImpact.permanent => l.cleanerSmartCleanImpactPermanent,
      CleanerItemImpact.redownload => l.cleanerSmartCleanImpactRedownload,
    };

/// Thin bar showing a group's share of everything found.
class _ShareBar extends StatelessWidget {
  final double share;
  final Color color;

  const _ShareBar({required this.share, required this.color});

  @override
  Widget build(BuildContext context) {
    final track = context.cbColors.fill;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(2),
        ),
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: share.clamp(0.02, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

/// Footer progress while the selection is cleaned.
class _CleanProgress extends StatelessWidget {
  final int done;
  final int total;
  final String path;

  const _CleanProgress({
    required this.done,
    required this.total,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l = AppLocalizations.of(context)!;
    return Padding(
      key: const ValueKey<String>('cleaner-smart-clean-progress'),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppWaveLoader(size: 18, color: c.accent.base),
              const SizedBox(width: 8),
              Text(
                total > 0
                    ? l.diskCleanerProcessedCount(done, total)
                    : l.diskCleanerPreparingFiles,
                style: CbTypography.labelSm.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CbTypography.bodySm.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: AppProgressIndicator(
              value: total > 0 ? (done / total).clamp(0.0, 1.0) : null,
              height: 3,
              backgroundColor: c.fill,
              valueColor: c.accent.base,
              showGlow: false,
            ),
          ),
        ],
      ),
    );
  }
}
