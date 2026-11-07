import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../bloc/cleaner_app_storage/cleaner_app_storage.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../services/app_insights/app_insights_models.dart';
import '../../../services/disk_cleaner/app_storage/app_space_models.dart';
import '../../../services/disk_cleaner/cleaner_models.dart';
import '../../../services/disk_cleaner/docker/docker_storage.dart';
import '../../../services/disk_cleaner/editor_storage/editor_storage_models.dart';
import '../../utils/format_utils.dart';
import 'cleaner_progress_widgets.dart';
import 'installed_app_icon.dart';

typedef AppStorageCleanAction =
    Future<CleanReport?> Function(
      List<JunkItem> items,
      void Function(int done, int total, String? path) onProgress,
    );

/// Apps shown before "Show all".
const int _appsShown = 25;

/// Extension rows shown before "Show all".
const int _extensionsShown = 8;

/// Targets listed under an expanded cleanup row.
const int _targetsShown = 30;

const double _sizeColumnWidth = 76;
const double _wideFooterBreakpoint = 560;

/// Below this width an extension row drops its data column.
const double _compactExtensionRow = 460;

/// Below this width the stat tiles wrap two per row.
const double _wideStatsBreakpoint = 620;

/// Cards stay readable on very wide panes.
const double _contentMaxWidth = 980;

String _size(int bytes) => FormatUtils.formatFileSize(bytes);

/// App storage page: every installed app with what it keeps on disk and
/// what of that is safe to remove.
///
/// Each app row opens to its cleanup groups, its extensions (VS Code family
/// editors) and the data that is only shown. Safe groups start checked;
/// whole cache and log folders and data of deleted workspaces are opt-in.
/// Checked targets go to the Trash / Recycle Bin whole, after a
/// confirmation.
class CleanerAppStorageView extends StatefulWidget {
  final CleanerAppStorageCubit cubit;

  /// Adds the approved batch to the shared Cleaner queue.
  final AppStorageCleanAction? onClean;
  final FutureOr<void> Function(String path)? onOpenFolder;

  /// Opens the Leftover app data page.
  final VoidCallback? onOpenLeftovers;

  /// False while another Cleaner scan or cleanup runs.
  final bool enabled;
  final bool usesTrash;

  /// Windows apps carry an icon resource; elsewhere the initial is shown.
  final bool showAppIcons;

  const CleanerAppStorageView({
    super.key,
    required this.cubit,
    this.onClean,
    this.onOpenFolder,
    this.onOpenLeftovers,
    this.enabled = true,
    this.usesTrash = false,
    this.showAppIcons = false,
  });

  @override
  State<CleanerAppStorageView> createState() => _CleanerAppStorageViewState();
}

class _CleanerAppStorageViewState extends State<CleanerAppStorageView> {
  final ValueNotifier<(int, int, String?)?> _progress = ValueNotifier(null);
  final Set<String> _expandedApps = {};
  final Set<String> _expandedGroups = {};
  final Set<String> _allExtensions = {};
  bool _showAllApps = false;
  bool _dockerExpanded = true;
  final Set<DockerCleanKind> _expandedDocker = {};
  bool _cleanableOnly = false;
  int _cleans = 0;

  CleanerAppStorageCubit get _cubit => widget.cubit;

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  String _destination(AppLocalizations l) =>
      widget.usesTrash ? l.trashBin : l.diskCleanerRecycleBinLabel;

  Future<void> _clean() async {
    final onClean = widget.onClean;
    final targets = _cubit.state.selectedTargets;
    if (onClean == null || targets.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    final destination = _destination(l);
    final bytes = targets.fold<int>(0, (sum, t) => sum + t.bytes);
    final confirmed = await CbDialog.show<bool>(
      context: context,
      dialog: CbDialog(
        title: l.cleanerEditorsConfirmTitle(destination),
        icon: PhosphorIconsLight.trash,
        showCloseButton: false,
        content: Text(
          l.cleanerAppStorageConfirmBody(
            targets.length,
            _size(bytes),
            destination,
          ),
        ),
        actions: [
          CbButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            label: l.cancel,
          ),
          CbButton(
            key: const ValueKey<String>('cleaner-app-storage-confirm-clean'),
            variant: CbButtonVariant.primary,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            label: widget.usesTrash
                ? l.moveToTrash
                : l.diskCleanerMoveToRecycleBin,
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final paths = [for (final t in targets) t.path];
    _progress.value = null;
    setState(() => _cleans++);
    _cubit.markPending(paths);
    CleanReport? result;
    try {
      result = await onClean(
        [
          for (final t in targets)
            JunkItem(
              path: t.path,
              sizeBytes: t.bytes,
              categoryId: 'selected_item',
              // The folder or file goes as a whole, never file by file.
              isUserSelected: true,
            ),
        ],
        (done, total, path) {
          if (mounted) _progress.value = (done, total, path);
        },
      );
    } finally {
      if (!_cubit.isClosed) {
        _cubit.finishClean(paths, result?.succeeded ?? const []);
      }
      if (mounted) setState(() => _cleans--);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CleanerAppStorageCubit, CleanerAppStorageState>(
      key: const ValueKey<String>('cleaner-app-storage-view'),
      bloc: _cubit,
      builder: (context, state) {
        final l = AppLocalizations.of(context)!;
        final scanning = state.status == CleanerAppStorageStatus.scanning;
        final report = state.report;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              subtitle: report != null && report.entries.isNotEmpty
                  ? l.cleanerEditorsTotal(_size(report.totalBytes))
                  : l.cleanerAppStorageUtilityDescription,
              action: state.status == CleanerAppStorageStatus.idle
                  ? null
                  : scanning
                  ? CbButton(
                      key: const ValueKey<String>('cleaner-app-storage-cancel'),
                      icon: PhosphorIconsLight.x,
                      label: l.diskCleanerCancel,
                      onPressed: _cubit.cancel,
                    )
                  : CbButton(
                      key: const ValueKey<String>('cleaner-app-storage-rescan'),
                      icon: PhosphorIconsLight.arrowClockwise,
                      label: l.diskCleanerScanAgain,
                      onPressed: widget.enabled && _cleans == 0
                          ? _cubit.scan
                          : null,
                    ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildBody(l, state)),
            if (report != null && state.groups.isNotEmpty)
              _buildFooter(l, state),
          ],
        );
      },
    );
  }

  Widget _buildBody(AppLocalizations l, CleanerAppStorageState state) {
    final c = context.cbColors;
    final report = state.report;
    if (report != null) return _buildReport(l, state, report);
    switch (state.status) {
      case CleanerAppStorageStatus.idle:
        return _Centered(
          key: const ValueKey<String>('cleaner-app-storage-intro'),
          children: [
            const _IconTile(icon: PhosphorIconsLight.appWindow, size: 56),
            const SizedBox(height: CbSpacing.lg),
            Text(
              l.cleanerAppStorageTitle,
              style: CbTypography.headingMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: CbSpacing.sm),
            Text(
              l.cleanerAppStorageIntro,
              textAlign: TextAlign.center,
              style: CbTypography.body.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: CbSpacing.lg),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: CbSpacing.sm,
              runSpacing: CbSpacing.sm,
              children: [
                _Chip(
                  icon: PhosphorIconsLight.appWindow,
                  label: l.cleanerAppStorageKindInstall,
                ),
                _Chip(
                  icon: PhosphorIconsLight.lightning,
                  label: l.cleanerEditorsKindCache,
                ),
                _Chip(
                  icon: PhosphorIconsLight.scroll,
                  label: l.cleanerEditorsKindLogs,
                ),
                _Chip(
                  icon: PhosphorIconsLight.puzzlePiece,
                  label: l.cleanerEditorsStatExtensions,
                ),
              ],
            ),
            const SizedBox(height: CbSpacing.xl),
            CbButton(
              key: const ValueKey<String>('cleaner-app-storage-scan'),
              variant: CbButtonVariant.primary,
              size: CbButtonSize.lg,
              icon: PhosphorIconsLight.magnifyingGlass,
              label: l.cleanerEditorsScan,
              onPressed: widget.enabled ? _cubit.scan : null,
            ),
          ],
        );
      case CleanerAppStorageStatus.scanning:
        return CleanerScanPanel(
          key: const ValueKey<String>('cleaner-app-storage-scanning'),
          title: l.cleanerAppStorageMeasuring(state.done, state.total),
          value: state.total == 0 ? null : state.done / state.total,
        );
      case CleanerAppStorageStatus.failure:
        return _Centered(
          key: const ValueKey<String>('cleaner-app-storage-error'),
          children: [
            Icon(
              PhosphorIconsLight.warningCircle,
              size: 34,
              color: c.status.danger,
            ),
            const SizedBox(height: CbSpacing.md),
            Text(
              l.cleanerAppsLoadFailed(
                state.errorMessage ?? l.cleanerAppsUnknown,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      case CleanerAppStorageStatus.ready:
        return const SizedBox.shrink();
    }
  }

  Widget _buildReport(
    AppLocalizations l,
    CleanerAppStorageState state,
    AppSpaceReport report,
  ) {
    final c = context.cbColors;
    if (report.entries.isEmpty) {
      return _Centered(
        key: const ValueKey<String>('cleaner-app-storage-empty'),
        children: [
          Icon(PhosphorIconsLight.appWindow, size: 34, color: c.iconSubtle),
          const SizedBox(height: CbSpacing.md),
          Text(l.cleanerAppStorageNoneFound),
        ],
      );
    }
    final focused = state.focusedAppId;
    final filtered = focused != null
        ? report.entries.where((e) => e.key == focused).toList()
        : _cleanableOnly
        ? report.entries.where((e) => AppCleanGroup.of(e).isNotEmpty).toList()
        : report.entries;
    final shown = _showAllApps ? filtered : filtered.take(_appsShown).toList();
    final largest = report.entries.fold<int>(
      0,
      (m, e) => math.max(m, e.totalBytes),
    );
    final unreadable = report.unreadable;
    final header = <Widget>[
      _Stats(
        tiles: [
          _StatData(
            icon: PhosphorIconsLight.appWindow,
            label: l.cleanerAppStorageStatApps,
            value: '${report.entries.length}',
          ),
          _StatData(
            icon: PhosphorIconsLight.hardDrive,
            label: l.cleanerAppStorageStatTotal,
            value: _size(report.totalBytes),
          ),
          _StatData(
            icon: PhosphorIconsLight.broom,
            label: l.cleanerEditorsStatCleanable,
            // Docker's regenerable prunes count as safe too.
            value: _size(report.safeBytes + _dockerSafeBytes(report.docker)),
          ),
        ],
      ),
      if (state.isMeasuring) ...[
        const SizedBox(height: CbSpacing.md),
        CleanerScanStrip(
          key: const ValueKey<String>('cleaner-app-storage-measuring'),
          title: l.cleanerAppStorageMeasuringApps,
          trailing: '${state.done}/${state.total}',
          value: state.total == 0 ? null : state.done / state.total,
        ),
      ] else if (!report.complete) ...[
        const SizedBox(height: CbSpacing.md),
        _Note(
          key: const ValueKey<String>('cleaner-app-storage-not-measured'),
          icon: PhosphorIconsLight.info,
          text: l.cleanerAppStorageAppsNotMeasured,
        ),
      ],
      if (unreadable > 0) ...[
        const SizedBox(height: CbSpacing.md),
        _Note(
          icon: PhosphorIconsLight.lockSimple,
          // Full Disk Access is the macOS answer; elsewhere it is only a fact.
          text: Theme.of(context).platform == TargetPlatform.macOS
              ? l.cleanerAppStorageUnreadable(unreadable)
              : l.cleanerAppStorageUnreadableGeneric(unreadable),
        ),
      ],
      const SizedBox(height: CbSpacing.md),
      if (focused != null)
        Align(
          alignment: Alignment.centerLeft,
          child: CbButton(
            key: const ValueKey<String>('cleaner-app-storage-show-every-app'),
            variant: CbButtonVariant.secondary,
            size: CbButtonSize.sm,
            icon: PhosphorIconsLight.arrowLeft,
            label: l.cleanerAppStorageShowAll(report.entries.length),
            onPressed: () => _cubit.focusApp(null),
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final link = _LinkText(
              text: l.cleanerAppStorageLeftoversHint,
              onTap: widget.onOpenLeftovers,
            );
            final toggle = _FilterToggle(
              key: const ValueKey<String>('cleaner-app-storage-cleanable-only'),
              label: l.cleanerAppStorageCleanableOnly,
              value: _cleanableOnly,
              onChanged: (value) => setState(() => _cleanableOnly = value),
            );
            if (constraints.maxWidth < _wideStatsBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  link,
                  const SizedBox(height: CbSpacing.sm),
                  toggle,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: link),
                const SizedBox(width: CbSpacing.md),
                toggle,
              ],
            );
          },
        ),
      const SizedBox(height: CbSpacing.md),
      if (report.docker case final docker?
          when focused == null && docker.status != DockerStatus.notInstalled)
        Padding(
          padding: const EdgeInsets.only(bottom: CbSpacing.sm),
          child: _buildDocker(l, state, docker),
        ),
    ];
    final footer = <Widget>[
      if (!_showAllApps && filtered.length > _appsShown)
        Align(
          alignment: Alignment.centerLeft,
          child: CbButton(
            key: const ValueKey<String>('cleaner-app-storage-show-all'),
            variant: CbButtonVariant.ghost,
            size: CbButtonSize.sm,
            icon: PhosphorIconsLight.caretDown,
            label: l.cleanerAppStorageShowAll(filtered.length),
            onPressed: () => setState(() => _showAllApps = true),
          ),
        ),
    ];
    final count = header.length + shown.length + footer.length;
    return ListView.builder(
      key: const ValueKey<String>('cleaner-app-storage-list'),
      padding: const EdgeInsets.fromLTRB(
        CbSpacing.lg,
        CbSpacing.lg,
        CbSpacing.lg,
        CbSpacing.xl,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final Widget child;
        if (index < header.length) {
          child = header[index];
        } else if (index < header.length + shown.length) {
          final entry = shown[index - header.length];
          child = Padding(
            padding: const EdgeInsets.only(bottom: CbSpacing.sm),
            child: _buildApp(l, state, entry, largest),
          );
        } else {
          child = footer[index - header.length - shown.length];
        }
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
            child: SizedBox(width: double.infinity, child: child),
          ),
        );
      },
    );
  }

  Widget _buildApp(
    AppLocalizations l,
    CleanerAppStorageState state,
    AppSpaceEntry entry,
    int largest,
  ) {
    final c = context.cbColors;
    final expanded =
        _expandedApps.contains(entry.key) || state.focusedAppId == entry.key;
    final safe = entry.safeBytes;
    final parts = _kindSummary(l, entry);
    return CbSurface(
      key: ValueKey<String>('cleaner-app-storage-app-${entry.key}'),
      clip: true,
      padding: const EdgeInsets.all(CbSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HoverRow(
            key: ValueKey<String>('cleaner-app-storage-toggle-${entry.key}'),
            onTap: () => setState(() {
              if (!_expandedApps.remove(entry.key)) {
                _expandedApps.add(entry.key);
              }
            }),
            child: Row(
              children: [
                _AppIcon(
                  app: entry.app,
                  size: CbSizes.controlLg,
                  useIcon: widget.showAppIcons,
                ),
                const SizedBox(width: CbSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: CbSpacing.sm,
                        runSpacing: CbSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            entry.app.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CbTypography.label.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (entry.isRunning)
                            _Badge(
                              label: l.cleanerEditorsRunningBadge,
                              color: c.status.success,
                              dot: true,
                            ),
                        ],
                      ),
                      if (parts.isNotEmpty)
                        Text(
                          parts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.bodySm.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                      const SizedBox(height: CbSpacing.xs + CbSpacing.xxs),
                      _SizeBar(
                        fraction: largest == 0 ? 0 : entry.totalBytes / largest,
                        color: c.textSecondary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CbSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _size(entry.totalBytes),
                      style: CbTypography.label.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (safe > 0) ...[
                      const SizedBox(height: CbSpacing.xxs),
                      _Badge(
                        label: l.cleanerAppStorageSafe(_size(safe)),
                        color: c.status.success,
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: CbSpacing.sm),
                Icon(
                  expanded
                      ? PhosphorIconsLight.caretUp
                      : PhosphorIconsLight.caretDown,
                  size: CbSizes.iconSm,
                  color: c.iconSubtle,
                ),
              ],
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CbSpacing.md,
                0,
                CbSpacing.md,
                CbSpacing.md,
              ),
              child: _buildDetails(l, state, entry),
            ),
        ],
      ),
    );
  }

  /// Docker's images, containers, volumes and build cache, with prunes that
  /// Docker itself runs. Permanent, so its own button and confirmation.
  Widget _buildDocker(
    AppLocalizations l,
    CleanerAppStorageState state,
    DockerReport docker,
  ) {
    final c = context.cbColors;
    final cleanable = docker.isReady
        ? docker.cleanable
        : const <DockerCleanKind>[];
    final safe = _dockerSafeBytes(docker);
    final parts = docker.isReady
        ? [
            if (docker.imageBytes > 0)
              '${l.cleanerDockerImages} ${_size(docker.imageBytes)}',
            if (docker.buildCacheBytes > 0)
              '${l.cleanerDockerBuildCache} ${_size(docker.buildCacheBytes)}',
            if (docker.volumeBytes > 0)
              '${l.cleanerDockerVolumes} ${_size(docker.volumeBytes)}',
          ]
        : const <String>[];
    final largest = cleanable.fold<int>(
      0,
      (m, kind) => math.max(m, docker.bytesOf(kind)),
    );
    final busy =
        state.isCleaningDocker ||
        state.status == CleanerAppStorageStatus.scanning;
    final selectedBytes = state.dockerSelectedBytes;
    return CbSurface(
      key: const ValueKey<String>('cleaner-app-storage-docker'),
      clip: true,
      padding: const EdgeInsets.all(CbSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HoverRow(
            key: const ValueKey<String>('cleaner-app-storage-docker-toggle'),
            onTap: () => setState(() => _dockerExpanded = !_dockerExpanded),
            child: Row(
              children: [
                const _IconTile(
                  icon: PhosphorIconsLight.cube,
                  size: CbSizes.controlLg,
                ),
                const SizedBox(width: CbSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.cleanerDockerTitle,
                        style: CbTypography.label.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (parts.isNotEmpty)
                        Text(
                          parts.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.bodySm.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: CbSpacing.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (docker.isReady)
                      Text(
                        _size(docker.totalBytes),
                        style: CbTypography.label.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    if (safe > 0) ...[
                      const SizedBox(height: CbSpacing.xxs),
                      _Badge(
                        label: l.cleanerAppStorageSafe(_size(safe)),
                        color: c.status.success,
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: CbSpacing.sm),
                Icon(
                  _dockerExpanded
                      ? PhosphorIconsLight.caretUp
                      : PhosphorIconsLight.caretDown,
                  size: CbSizes.iconSm,
                  color: c.iconSubtle,
                ),
              ],
            ),
          ),
          if (_dockerExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CbSpacing.md,
                0,
                CbSpacing.md,
                CbSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (docker.status == DockerStatus.notRunning)
                    _Note(
                      icon: PhosphorIconsLight.info,
                      text: l.cleanerDockerNotRunning,
                    )
                  else if (!docker.isReady)
                    _Note(
                      icon: PhosphorIconsLight.warningCircle,
                      text: l.cleanerDockerFailed(docker.message ?? ''),
                    )
                  else ...[
                    const SizedBox(height: CbSpacing.sm),
                    _Stats(
                      tiles: [
                        _StatData(
                          icon: PhosphorIconsLight.stack,
                          label:
                              '${l.cleanerDockerImages} (${docker.images.length})',
                          value: _size(docker.imageBytes),
                        ),
                        _StatData(
                          icon: PhosphorIconsLight.shippingContainer,
                          label:
                              '${l.cleanerDockerContainers} (${docker.containers.length})',
                          value: _size(docker.containerBytes),
                        ),
                        _StatData(
                          icon: PhosphorIconsLight.hardDrives,
                          label:
                              '${l.cleanerDockerVolumes} (${docker.volumes.length})',
                          value: _size(docker.volumeBytes),
                        ),
                        _StatData(
                          icon: PhosphorIconsLight.hammer,
                          label: l.cleanerDockerBuildCache,
                          value: _size(docker.buildCacheBytes),
                        ),
                      ],
                    ),
                    if (cleanable.isNotEmpty) ...[
                      _SectionTitle(
                        icon: PhosphorIconsLight.broom,
                        text: l.cleanerEditorsCleanableSection,
                      ),
                      for (final kind in cleanable)
                        _buildDockerRow(l, state, docker, kind, largest, busy),
                      const SizedBox(height: CbSpacing.sm),
                      if (state.isCleaningDocker)
                        CleanerScanStrip(
                          key: const ValueKey<String>(
                            'cleaner-app-storage-docker-running',
                          ),
                          title: l.cleanerDockerRunning(
                            'docker ${state.dockerStep!.pruneArgs.take(2).join(' ')}',
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: CbButton(
                            key: const ValueKey<String>(
                              'cleaner-app-storage-docker-clean',
                            ),
                            variant: CbButtonVariant.danger,
                            icon: PhosphorIconsLight.trashSimple,
                            label: l.cleanerDockerClean(_size(selectedBytes)),
                            onPressed:
                                busy ||
                                    !widget.enabled ||
                                    state.dockerSelected.isEmpty
                                ? null
                                : _cleanDocker,
                          ),
                        ),
                    ],
                  ],
                  if (state.dockerFreed case final freed?) ...[
                    const SizedBox(height: CbSpacing.sm),
                    _Note(
                      key: const ValueKey<String>(
                        'cleaner-app-storage-docker-freed',
                      ),
                      icon: PhosphorIconsLight.checkCircle,
                      text: l.cleanerDockerFreed(_size(freed)),
                    ),
                  ],
                  if (state.dockerError case final error?) ...[
                    const SizedBox(height: CbSpacing.sm),
                    _Note(
                      icon: PhosphorIconsLight.warningCircle,
                      text: l.cleanerDockerFailed(error),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDockerRow(
    AppLocalizations l,
    CleanerAppStorageState state,
    DockerReport docker,
    DockerCleanKind kind,
    int largest,
    bool busy,
  ) {
    final c = context.cbColors;
    final count = docker.countOf(kind);
    final bytes = docker.bytesOf(kind);
    final (title, hint, icon) = switch (kind) {
      DockerCleanKind.stoppedContainers => (
        l.cleanerDockerStoppedContainers(count),
        l.cleanerDockerStoppedContainersHint,
        PhosphorIconsLight.shippingContainer,
      ),
      DockerCleanKind.danglingImages => (
        l.cleanerDockerDanglingImages(count),
        l.cleanerDockerDanglingImagesHint,
        PhosphorIconsLight.stack,
      ),
      DockerCleanKind.unusedImages => (
        l.cleanerDockerUnusedImages(count),
        l.cleanerDockerUnusedImagesHint,
        PhosphorIconsLight.stack,
      ),
      DockerCleanKind.buildCache => (
        l.cleanerDockerBuildCache,
        l.cleanerDockerBuildCacheHint,
        PhosphorIconsLight.hammer,
      ),
      DockerCleanKind.unusedVolumes => (
        l.cleanerDockerUnusedVolumes(count),
        l.cleanerDockerUnusedVolumesHint,
        PhosphorIconsLight.hardDrives,
      ),
    };
    final items = <(String, int)>[
      for (final image in docker.images)
        if ((kind == DockerCleanKind.unusedImages && image.isUnused) ||
            (kind == DockerCleanKind.danglingImages &&
                image.isUnused &&
                image.isDangling))
          (image.name, image.uniqueSize),
      if (kind == DockerCleanKind.stoppedContainers)
        for (final container in docker.containers)
          if (!container.isRunning)
            ('${container.name} · ${container.state}', container.size),
      if (kind == DockerCleanKind.unusedVolumes)
        for (final volume in docker.volumes)
          if (volume.isUnused) (volume.name, volume.size),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    final selected = state.dockerSelected.contains(kind);
    final expanded = _expandedDocker.contains(kind);
    return Column(
      key: ValueKey<String>('cleaner-app-storage-docker-${kind.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HoverRow(
          onTap: items.isEmpty
              ? null
              : () => setState(() {
                  if (!_expandedDocker.remove(kind)) _expandedDocker.add(kind);
                }),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Checkbox(
                  key: ValueKey<String>(
                    'cleaner-app-storage-docker-check-${kind.name}',
                  ),
                  value: selected,
                  onChanged: busy ? null : (_) => _cubit.toggleDocker(kind),
                ),
              ),
              const SizedBox(width: CbSpacing.xs),
              _IconTile(icon: icon, size: CbSizes.controlMd),
              const SizedBox(width: CbSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CbTypography.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hint,
                      style: CbTypography.bodySm.copyWith(
                        color: kind == DockerCleanKind.unusedVolumes
                            ? c.status.danger
                            : c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: CbSpacing.xs + CbSpacing.xxs),
                    _SizeBar(
                      fraction: largest == 0 ? 0 : bytes / largest,
                      color: selected ? c.textSecondary : c.strokeStrong,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CbSpacing.md),
              SizedBox(
                width: _sizeColumnWidth,
                child: Text(
                  _size(bytes),
                  textAlign: TextAlign.right,
                  style: CbTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? c.textPrimary : c.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: CbSizes.iconSm,
                child: items.isEmpty
                    ? null
                    : Icon(
                        expanded
                            ? PhosphorIconsLight.caretUp
                            : PhosphorIconsLight.caretDown,
                        size: CbSizes.iconSm,
                        color: c.iconSubtle,
                      ),
              ),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: 84,
              bottom: CbSpacing.xs + CbSpacing.xxs,
              right: CbSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (name, size) in items.take(_targetsShown))
                  _PathRow(icon: icon, path: name, bytes: size),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _cleanDocker() async {
    final l = AppLocalizations.of(context)!;
    final confirmed = await CbDialog.show<bool>(
      context: context,
      dialog: CbDialog(
        title: l.cleanerDockerConfirmTitle,
        icon: PhosphorIconsLight.cube,
        destructive: true,
        showCloseButton: false,
        content: Text(l.cleanerDockerConfirmBody),
        actions: [
          CbButton(
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(false),
            label: l.cancel,
          ),
          CbButton(
            key: const ValueKey<String>('cleaner-app-storage-docker-confirm'),
            variant: CbButtonVariant.danger,
            onPressed: () =>
                Navigator.of(context, rootNavigator: true).pop(true),
            label: l.cleanerDockerClean(
              _size(_cubit.state.dockerSelectedBytes),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _cubit.cleanDocker();
  }

  static int _dockerSafeBytes(DockerReport? docker) =>
      docker == null || !docker.isReady
      ? 0
      : [
          for (final kind in docker.cleanable)
            if (kind.selectedByDefault) docker.bytesOf(kind),
        ].fold<int>(0, (sum, bytes) => sum + bytes);

  /// The largest kinds, for the collapsed row.
  List<String> _kindSummary(AppLocalizations l, AppSpaceEntry entry) {
    final totals = <String, int>{};
    void add(String label, int bytes) {
      if (bytes > 0) totals[label] = (totals[label] ?? 0) + bytes;
    }

    add(l.cleanerAppStorageKindInstall, entry.bytesOf(AppSpaceKind.install));
    add(
      l.cleanerEditorsKindCache,
      entry.bytesOf(AppSpaceKind.cache) +
          (entry.editor?.data
                  .where((d) => d.kind == EditorDataKind.cache)
                  .fold<int>(0, (s, d) => s + d.bytes) ??
              0),
    );
    add(
      l.cleanerEditorsStatExtensions,
      (entry.editor?.extensionInstallBytes ?? 0) +
          (entry.editor?.extensionStorageBytes ?? 0),
    );
    add(
      l.cleanerAppStorageKindUserData,
      entry.bytesOf(AppSpaceKind.userData) +
          entry.bytesOf(AppSpaceKind.settings),
    );
    add(l.cleanerEditorsKindLogs, entry.bytesOf(AppSpaceKind.logs));
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted.take(3)) '${e.key} ${_size(e.value)}'];
  }

  Widget _buildDetails(
    AppLocalizations l,
    CleanerAppStorageState state,
    AppSpaceEntry entry,
  ) {
    final groups = AppCleanGroup.of(entry);
    final editor = entry.editor;
    final largestGroup = groups.fold<int>(0, (m, g) => math.max(m, g.bytes));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (entry.isRunning) ...[
          const SizedBox(height: CbSpacing.sm),
          _Note(
            icon: PhosphorIconsLight.info,
            text: l.cleanerEditorsRunning(entry.app.displayName),
          ),
        ],
        if (groups.isNotEmpty) ...[
          _SectionTitle(
            icon: PhosphorIconsLight.broom,
            text: l.cleanerEditorsCleanableSection,
          ),
          for (final group in groups)
            _buildGroup(l, state, group, largestGroup),
        ],
        if (editor != null && editor.extensions.isNotEmpty)
          ..._buildExtensions(l, entry.key, editor),
        ..._buildReview(l, entry),
      ],
    );
  }

  List<Widget> _buildExtensions(
    AppLocalizations l,
    String key,
    EditorStorageReport editor,
  ) {
    final showAll = _allExtensions.contains(key);
    final extensions = showAll
        ? editor.extensions
        : editor.extensions.take(_extensionsShown).toList();
    final largest = editor.extensions.fold<int>(
      0,
      (m, e) => math.max(m, e.totalBytes),
    );
    return [
      _SectionTitle(
        icon: PhosphorIconsLight.puzzlePiece,
        text: l.cleanerEditorsExtensionsSection,
        trailing: [l.cleanerEditorsInstallColumn, l.cleanerEditorsDataColumn],
      ),
      for (final extension in extensions)
        _ExtensionRow(
          extension: extension,
          largestBytes: largest,
          onOpen: _openAction(extension.path),
        ),
      if (editor.extensions.length > _extensionsShown)
        Align(
          alignment: Alignment.centerLeft,
          child: CbButton(
            key: ValueKey<String>('cleaner-app-storage-extensions-$key'),
            variant: CbButtonVariant.ghost,
            size: CbButtonSize.sm,
            icon: showAll
                ? PhosphorIconsLight.caretUp
                : PhosphorIconsLight.caretDown,
            label: showAll
                ? null
                : l.cleanerEditorsShowAll(editor.extensions.length),
            onPressed: () => setState(() {
              if (!_allExtensions.remove(key)) _allExtensions.add(key);
            }),
          ),
        ),
    ];
  }

  Widget _buildGroup(
    AppLocalizations l,
    CleanerAppStorageState state,
    AppCleanGroup group,
    int largestBytes,
  ) {
    final c = context.cbColors;
    final optional = group.tier == AppSpaceTier.optional;
    final (title, hint, icon) = switch (group.kind) {
      AppCleanKind.obsoleteExtensions => (
        l.cleanerEditorsObsoleteExtensions(group.targets.length),
        l.cleanerEditorsObsoleteExtensionsHint,
        PhosphorIconsLight.puzzlePiece,
      ),
      AppCleanKind.cache => (
        l.cleanerEditorsKindCache,
        optional
            ? l.cleanerAppStorageCacheOptionalHint
            : l.cleanerEditorsKindCacheHint,
        PhosphorIconsLight.lightning,
      ),
      AppCleanKind.extensionDownloads => (
        l.cleanerEditorsKindDownloads,
        l.cleanerEditorsKindDownloadsHint,
        PhosphorIconsLight.downloadSimple,
      ),
      AppCleanKind.logs => (
        l.cleanerEditorsKindLogs,
        optional
            ? l.cleanerAppStorageLogsOptionalHint
            : l.cleanerEditorsKindLogsHint,
        PhosphorIconsLight.scroll,
      ),
      AppCleanKind.crashReports => (
        l.cleanerEditorsKindCrash,
        l.cleanerEditorsKindCrashHint,
        PhosphorIconsLight.bug,
      ),
      AppCleanKind.missingWorkspaces => (
        l.cleanerEditorsMissingWorkspaces(group.targets.length),
        l.cleanerEditorsMissingWorkspacesHint,
        PhosphorIconsLight.folderDashed,
      ),
    };
    final pending = group.targets.every(
      (t) => state.pendingPaths.contains(t.path),
    );
    final selected = state.isSelected(group) && !pending;
    final expanded = _expandedGroups.contains(group.id);
    return Column(
      key: ValueKey<String>('cleaner-app-storage-group-${group.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HoverRow(
          onTap: () => setState(() {
            if (!_expandedGroups.remove(group.id)) {
              _expandedGroups.add(group.id);
            }
          }),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Checkbox(
                  key: ValueKey<String>(
                    'cleaner-app-storage-check-${group.id}',
                  ),
                  value: selected,
                  onChanged:
                      pending ||
                          _cleans > 0 ||
                          state.status == CleanerAppStorageStatus.scanning
                      ? null
                      : (_) => _cubit.toggleGroup(group.id),
                ),
              ),
              const SizedBox(width: CbSpacing.xs),
              _IconTile(icon: icon, size: CbSizes.controlMd),
              const SizedBox(width: CbSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CbTypography.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      hint,
                      style: CbTypography.bodySm.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(height: CbSpacing.xs + CbSpacing.xxs),
                    _SizeBar(
                      fraction: largestBytes == 0
                          ? 0
                          : group.bytes / largestBytes,
                      color: selected ? c.textSecondary : c.strokeStrong,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: CbSpacing.md),
              SizedBox(
                width: _sizeColumnWidth,
                child: Text(
                  _size(group.bytes),
                  textAlign: TextAlign.right,
                  style: CbTypography.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? c.textPrimary : c.textSecondary,
                  ),
                ),
              ),
              Icon(
                expanded
                    ? PhosphorIconsLight.caretUp
                    : PhosphorIconsLight.caretDown,
                size: CbSizes.iconSm,
                color: c.iconSubtle,
              ),
            ],
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: 84,
              bottom: CbSpacing.xs + CbSpacing.xxs,
              right: CbSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final target in group.targets.take(_targetsShown))
                  _PathRow(
                    icon: PhosphorIconsLight.file,
                    path: target.path,
                    bytes: target.bytes,
                    onOpen: _openAction(target.path),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// What is only shown: per kind, review-tier data plus the editor's.
  List<Widget> _buildReview(AppLocalizations l, AppSpaceEntry entry) {
    final rows = <Widget>[];
    void add(IconData icon, String label, int bytes, String? path) {
      if (bytes <= 0) return;
      rows.add(
        _PathRow(
          icon: icon,
          label: label,
          bytes: bytes,
          onOpen: _openAction(path),
        ),
      );
    }

    String? folderOf(List<String> paths) => paths.isEmpty
        ? null
        : paths.length == 1
        ? paths.single
        : p.dirname(paths.first);

    for (final kind in AppSpaceKind.values) {
      final items = entry.items
          .where((i) => i.kind == kind && i.tier == AppSpaceTier.review)
          .toList();
      if (items.isEmpty) continue;
      final (icon, label) = switch (kind) {
        AppSpaceKind.install => (
          PhosphorIconsLight.appWindow,
          l.cleanerAppStorageKindInstall,
        ),
        AppSpaceKind.cache => (
          PhosphorIconsLight.lightning,
          l.cleanerEditorsKindCache,
        ),
        AppSpaceKind.logs => (
          PhosphorIconsLight.scroll,
          l.cleanerEditorsKindLogs,
        ),
        AppSpaceKind.crashReports => (
          PhosphorIconsLight.bug,
          l.cleanerEditorsKindCrash,
        ),
        AppSpaceKind.extensionDownloads => (
          PhosphorIconsLight.downloadSimple,
          l.cleanerEditorsKindDownloads,
        ),
        AppSpaceKind.webStorage => (
          PhosphorIconsLight.globe,
          l.cleanerEditorsKindWebStorage,
        ),
        AppSpaceKind.userData => (
          PhosphorIconsLight.database,
          l.cleanerAppStorageKindUserData,
        ),
        AppSpaceKind.sharedData => (
          PhosphorIconsLight.usersThree,
          l.cleanerAppStorageKindShared,
        ),
        AppSpaceKind.settings => (
          PhosphorIconsLight.gearSix,
          l.cleanerEditorsKindSettings,
        ),
      };
      add(
        icon,
        label,
        items.fold<int>(0, (s, i) => s + i.bytes),
        folderOf([for (final i in items) i.path]),
      );
    }

    final editor = entry.editor;
    if (editor != null) {
      for (final data in editor.data) {
        final bytes = data.bytes - data.cleanableBytes;
        final (icon, label) = switch (data.kind) {
          EditorDataKind.webStorage => (
            PhosphorIconsLight.globe,
            l.cleanerEditorsKindWebStorage,
          ),
          EditorDataKind.localHistory => (
            PhosphorIconsLight.clockCounterClockwise,
            l.cleanerEditorsKindHistory,
          ),
          EditorDataKind.settings => (
            PhosphorIconsLight.gearSix,
            l.cleanerEditorsKindSettings,
          ),
          EditorDataKind.cache => (
            PhosphorIconsLight.lightning,
            l.cleanerEditorsKindCache,
          ),
          EditorDataKind.extensionDownloads => (
            PhosphorIconsLight.downloadSimple,
            l.cleanerEditorsKindDownloads,
          ),
          EditorDataKind.logs => (
            PhosphorIconsLight.scroll,
            l.cleanerEditorsKindLogs,
          ),
          EditorDataKind.crashReports => (
            PhosphorIconsLight.bug,
            l.cleanerEditorsKindCrash,
          ),
          EditorDataKind.other => (
            PhosphorIconsLight.dotsThreeOutline,
            l.cleanerEditorsKindOther,
          ),
        };
        add(
          icon,
          label,
          bytes,
          data.paths.length == 1 ? data.paths.single : editor.dataRoot,
        );
      }
      final orphan = editor.orphanedExtensionData;
      add(
        PhosphorIconsLight.database,
        l.cleanerEditorsOrphanData(orphan.length),
        orphan.fold<int>(0, (s, e) => s + e.bytes),
        folderOf([for (final e in orphan) ...e.paths]),
      );
      final present = editor.workspaces
          .where((w) => w.status == EditorWorkspaceStatus.present)
          .toList();
      add(
        PhosphorIconsLight.folders,
        l.cleanerEditorsActiveWorkspaces(present.length),
        present.fold<int>(0, (s, w) => s + w.bytes),
        folderOf([for (final w in present) w.path]),
      );
      final others = editor.workspaces
          .where(
            (w) =>
                w.status == EditorWorkspaceStatus.offline ||
                w.status == EditorWorkspaceStatus.unknown,
          )
          .toList();
      add(
        PhosphorIconsLight.cloud,
        l.cleanerEditorsOtherWorkspaces(others.length),
        others.fold<int>(0, (s, w) => s + w.bytes),
        folderOf([for (final w in others) w.path]),
      );
    }
    if (rows.isEmpty) return const [];
    return [
      _SectionTitle(
        icon: PhosphorIconsLight.eye,
        text: l.cleanerEditorsReviewSection,
      ),
      ...rows,
    ];
  }

  VoidCallback? _openAction(String? path) {
    final open = widget.onOpenFolder;
    if (open == null || path == null) return null;
    return () => unawaited(Future.sync(() => open(path)));
  }

  Widget _buildFooter(AppLocalizations l, CleanerAppStorageState state) {
    final c = context.cbColors;
    final bytes = state.selectedBytes;
    final summary = Row(
      children: [
        Icon(PhosphorIconsLight.broom, size: CbSizes.iconLg, color: c.icon),
        const SizedBox(width: CbSpacing.sm),
        Flexible(
          child: Text(
            l.cleanerEditorsSelected(_size(bytes)),
            key: const ValueKey<String>('cleaner-app-storage-summary'),
            style: CbTypography.headingSm.copyWith(color: c.textPrimary),
          ),
        ),
      ],
    );
    final button = CbButton(
      key: const ValueKey<String>('cleaner-app-storage-clean'),
      variant: CbButtonVariant.primary,
      size: CbButtonSize.lg,
      icon: PhosphorIconsLight.broom,
      label: l.cleanerEditorsClean(_size(bytes)),
      // Wait for the scan: a later report would bring removed folders back.
      onPressed:
          widget.enabled &&
              widget.onClean != null &&
              bytes > 0 &&
              state.status != CleanerAppStorageStatus.scanning
          ? _clean
          : null,
    );
    return Container(
      decoration: CbDecorations.bar(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_cleans > 0) CleanerCleanProgress(progress: _progress),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: CbSpacing.lg,
              vertical: CbSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth < _wideFooterBreakpoint
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summary,
                        const SizedBox(height: CbSpacing.sm),
                        button,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: summary),
                        button,
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sentence that opens another page when tapped.
class _LinkText extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const _LinkText({required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final label = Text(
      text,
      style: CbTypography.bodySm.copyWith(
        color: onTap == null ? c.textSecondary : c.accent.text,
      ),
    );
    if (onTap == null) return label;
    return CbPressable(
      key: const ValueKey<String>('cleaner-app-storage-leftovers-link'),
      onPressed: onTap,
      builder: (context, state) => label,
    );
  }
}

/// A labelled switch-like toggle for the list filter.
class _FilterToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FilterToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return CbPressable(
      onPressed: () => onChanged(!value),
      builder: (context, state) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: CbSpacing.md,
          vertical: CbSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: value
              ? CbDecorations.selectionFill(context.cb, hovered: state.hovered)
              : CbDecorations.controlFill(
                  c,
                  hovered: state.hovered,
                  pressed: state.pressed,
                ),
          borderRadius: CbRadii.all(CbRadii.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value
                  ? PhosphorIconsLight.checkSquare
                  : PhosphorIconsLight.square,
              size: CbSizes.iconSm,
              color: c.icon,
            ),
            const SizedBox(width: CbSpacing.xs + CbSpacing.xxs),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CbTypography.labelSm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The app's own icon where the platform gives one (Windows), otherwise its
/// initial on a neutral tile.
class _AppIcon extends StatelessWidget {
  final InstalledAppInfo app;
  final double size;
  final bool useIcon;

  const _AppIcon({
    required this.app,
    required this.size,
    required this.useIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (useIcon) return InstalledAppIcon(app: app, size: size);
    final c = context.cbColors;
    final name = app.displayName.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CbDecorations.controlFill(c),
        borderRadius: CbRadii.all(CbRadii.md),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: CbTypography.headingSm.copyWith(color: c.textSecondary),
      ),
    );
  }
}

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
        constraints: const BoxConstraints(minHeight: 36),
        child: Row(
          children: [
            Icon(
              PhosphorIconsLight.chartPieSlice,
              size: 19,
              color: c.accent.base,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.cleanerAppStorageTitle,
                    style: CbTypography.headingSm.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    key: const ValueKey<String>('cleaner-app-storage-subtitle'),
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

class _Centered extends StatelessWidget {
  final List<Widget> children;

  const _Centered({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}

/// A neutral rounded square holding [icon]: one step up the fill ramp from
/// the card, so it reads without a hue (the accent is kept for actions).
class _IconTile extends StatelessWidget {
  final IconData icon;
  final double size;

  const _IconTile({required this.icon, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: CbDecorations.controlFill(c),
        borderRadius: CbRadii.all(size >= 48 ? CbRadii.lg : CbRadii.md),
      ),
      child: Icon(
        icon,
        size: size >= 48 ? CbSizes.iconLg * 1.4 : CbSizes.iconMd,
        color: c.icon,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CbSpacing.md,
        vertical: CbSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: CbDecorations.controlFill(c),
        borderRadius: CbRadii.all(CbRadii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: CbSizes.iconSm, color: c.icon),
          const SizedBox(width: CbSpacing.xs + CbSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CbTypography.labelSm,
            ),
          ),
        ],
      ),
    );
  }
}

/// A status pill: [color] is a status hue, carried by the tint and the dot;
/// the text stays primary for contrast.
class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;

  const _Badge({required this.label, required this.color, this.dot = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: CbSpacing.sm,
      vertical: CbSpacing.xxs,
    ),
    decoration: CbDecorations.tint(context, color, radius: CbRadii.full),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: CbSpacing.xs),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CbTypography.labelXs.copyWith(
              color: context.cbColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _StatData {
  final IconData icon;
  final String label;
  final String value;

  const _StatData({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// Four figures across the card; two per row on narrow panes.
class _Stats extends StatelessWidget {
  final List<_StatData> tiles;

  const _Stats({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = math.min(
          tiles.length,
          constraints.maxWidth < _wideStatsBreakpoint ? 2 : 4,
        );
        const gap = CbSpacing.sm;
        final width = (constraints.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                child: _StatTile(data: tile),
              ),
          ],
        );
      },
    );
  }
}

/// A borderless block one fill step above the card.
class _StatTile extends StatelessWidget {
  final _StatData data;

  const _StatTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Container(
      padding: const EdgeInsets.all(CbSpacing.md),
      decoration: BoxDecoration(
        color: CbDecorations.controlFill(c),
        borderRadius: CbRadii.all(CbRadii.md),
      ),
      child: Row(
        children: [
          Icon(data.icon, size: CbSizes.iconLg, color: c.icon),
          const SizedBox(width: CbSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CbTypography.labelXs.copyWith(color: c.textSecondary),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        data.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: CbTypography.headingSm.copyWith(
                          color: c.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  final List<String> trailing;

  const _SectionTitle({
    required this.icon,
    required this.text,
    this.trailing = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final style = CbTypography.labelXs.copyWith(
      color: c.textSecondary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.4,
    );
    return Padding(
      padding: const EdgeInsets.only(top: CbSpacing.lg, bottom: CbSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: CbSizes.iconSm, color: c.iconSubtle),
              const SizedBox(width: CbSpacing.xs + CbSpacing.xxs),
              Expanded(child: Text(text.toUpperCase(), style: style)),
              for (final label in trailing)
                SizedBox(
                  width: _sizeColumnWidth,
                  child: Text(
                    label.toUpperCase(),
                    textAlign: TextAlign.right,
                    style: style,
                  ),
                ),
              if (trailing.isNotEmpty) const SizedBox(width: CbSpacing.xs),
            ],
          ),
          const SizedBox(height: CbSpacing.xs + CbSpacing.xxs),
          Divider(height: 1, color: c.strokeSubtle),
        ],
      ),
    );
  }
}

/// An informational callout in the status palette's info hue.
class _Note extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Note({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Container(
      padding: const EdgeInsets.all(CbSpacing.md),
      decoration: CbDecorations.tint(context, c.status.info),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: CbSizes.iconMd, color: c.status.info),
          const SizedBox(width: CbSpacing.sm),
          Expanded(child: Text(text, style: CbTypography.bodySm)),
        ],
      ),
    );
  }
}

/// A thin neutral bar filled to [fraction].
class _SizeBar extends StatelessWidget {
  final double fraction;
  final Color color;

  const _SizeBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: CbRadii.all(CbRadii.full),
    child: SizedBox(
      height: CbSpacing.xs,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: CbDecorations.controlFill(context.cbColors)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: fraction.clamp(0, 1).toDouble(),
            child: ColoredBox(color: color),
          ),
        ],
      ),
    ),
  );
}

/// A row with the design system's hover and press washes (no ink ripple).
class _HoverRow extends StatelessWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _HoverRow({super.key, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return CbPressable(
      onPressed: onTap,
      builder: (context, state) => AnimatedContainer(
        duration: CbDurations.instant,
        padding: const EdgeInsets.symmetric(
          vertical: CbSpacing.sm,
          horizontal: CbSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: state.pressed
              ? c.fillPressed
              : state.hovered
              ? c.fillHover
              : null,
          borderRadius: CbRadii.all(CbRadii.md),
          boxShadow: state.focused ? CbDecorations.focusRing(c) : null,
        ),
        child: child,
      ),
    );
  }
}

/// The extension's own icon, or its initial on a neutral tile.
class _ExtensionIcon extends StatelessWidget {
  final EditorExtensionUsage extension;
  final double size;

  const _ExtensionIcon({required this.extension, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = _initial(context);
    final icon = extension.iconPath;
    if (icon == null) return fallback;
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipRRect(
      borderRadius: CbRadii.all(CbRadii.sm),
      child: Image.file(
        File(icon),
        width: size,
        height: size,
        cacheWidth: pixels,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _initial(BuildContext context) {
    final c = context.cbColors;
    final letter = extension.displayName.trim().isEmpty
        ? '?'
        : extension.displayName.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CbDecorations.controlFill(c),
        borderRadius: CbRadii.all(CbRadii.sm),
      ),
      child: Text(
        letter,
        style: CbTypography.headingSm.copyWith(color: c.textSecondary),
      ),
    );
  }
}

class _ExtensionRow extends StatelessWidget {
  final EditorExtensionUsage extension;
  final int largestBytes;
  final VoidCallback? onOpen;

  const _ExtensionRow({
    required this.extension,
    required this.largestBytes,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l = AppLocalizations.of(context)!;
    final badge = switch (extension.status) {
      EditorExtensionStatus.obsolete => (
        l.cleanerEditorsObsoleteBadge,
        c.status.warning,
      ),
      EditorExtensionStatus.unregistered => (
        l.cleanerEditorsUnregisteredBadge,
        c.textSecondary,
      ),
      EditorExtensionStatus.installed => null,
    };
    final data = extension.globalStorageBytes + extension.workspaceStorageBytes;
    final total = math.max(largestBytes, 1);
    return _HoverRow(
      key: ValueKey<String>('cleaner-editors-extension-${extension.path}'),
      onTap: onOpen,
      child: LayoutBuilder(
        builder: (context, constraints) => _row(
          context,
          badge,
          data,
          total,
          // Narrow panes show the data size under the name instead of in
          // its own column.
          compact: constraints.maxWidth < _compactExtensionRow,
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    (String, Color)? badge,
    int data,
    int total, {
    required bool compact,
  }) {
    final c = context.cbColors;
    return Row(
      children: [
        _ExtensionIcon(extension: extension, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The badge moves under the name when the row is narrow.
              Wrap(
                spacing: 6,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    extension.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CbTypography.label.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (badge != null) _Badge(label: badge.$1, color: badge.$2),
                ],
              ),
              Text(
                [
                  extension.id,
                  'v${extension.version}',
                  if (compact && data > 0) '+${_size(data)}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CbTypography.bodySm.copyWith(color: c.textTertiary),
              ),
              const SizedBox(height: 5),
              // Install and data side by side, scaled to the largest.
              ClipRRect(
                borderRadius: CbRadii.all(CbRadii.full),
                child: SizedBox(
                  height: 4,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      return Stack(
                        children: [
                          Positioned.fill(child: ColoredBox(color: c.fill)),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: width * extension.installBytes / total,
                            child: ColoredBox(color: c.textSecondary),
                          ),
                          Positioned(
                            left: width * extension.installBytes / total,
                            top: 0,
                            bottom: 0,
                            width: width * data / total,
                            child: ColoredBox(color: c.iconSubtle),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: _sizeColumnWidth,
          child: Text(
            _size(extension.installBytes),
            textAlign: TextAlign.right,
            style: CbTypography.label,
          ),
        ),
        if (!compact)
          SizedBox(
            width: _sizeColumnWidth,
            child: Text(
              data > 0 ? _size(data) : '–',
              textAlign: TextAlign.right,
              style: CbTypography.label.copyWith(color: c.textSecondary),
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// A labelled size, or a path with its size, that opens its folder.
class _PathRow extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String? path;
  final int bytes;
  final VoidCallback? onOpen;

  const _PathRow({
    required this.icon,
    this.label,
    this.path,
    required this.bytes,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final l = AppLocalizations.of(context)!;
    final isLabel = label != null;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isLabel ? 4 : 1),
      child: Row(
        children: [
          if (isLabel)
            _IconTile(icon: icon, size: CbSizes.controlSm)
          else
            Icon(icon, size: 14, color: c.iconSubtle),
          SizedBox(width: isLabel ? 12 : 8),
          Expanded(
            child: Text(
              label ?? path ?? '',
              maxLines: 1,
              overflow: isLabel ? TextOverflow.ellipsis : TextOverflow.fade,
              softWrap: false,
              style: isLabel
                  ? CbTypography.label
                  : CbTypography.bodySm.copyWith(color: c.textSecondary),
            ),
          ),
          SizedBox(
            width: _sizeColumnWidth,
            child: Text(
              _size(bytes),
              textAlign: TextAlign.right,
              style: isLabel
                  ? CbTypography.label
                  : CbTypography.bodySm.copyWith(color: c.textSecondary),
            ),
          ),
          SizedBox(
            width: 36,
            child: onOpen == null
                ? null
                : CbButton(
                    variant: CbButtonVariant.ghost,
                    size: CbButtonSize.xs,
                    icon: PhosphorIconsLight.folderOpen,
                    tooltip: l.openFolder,
                    onPressed: onOpen,
                  ),
          ),
        ],
      ),
    );
  }
}
