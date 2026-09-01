import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../bloc/cleaner_app_insights/cleaner_app_insights.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../design_system/primitives/cb_tooltip.dart';
import '../../../helpers/files/windows_app_icon.dart';
import '../../../services/app_insights/app_insights_models.dart';
import '../../utils/format_utils.dart';

typedef AppStorageEntryAction = FutureOr<void> Function(
  AppStorageEntry entry,
);
typedef InstalledAppAction = FutureOr<void> Function(InstalledAppInfo app);
typedef AppStorageProfileAction = FutureOr<void> Function(
  AppStorageProfile profile,
);

class CleanerAppsView extends StatefulWidget {
  final CleanerAppInsightsCubit cubit;
  final AppStorageEntryAction? onOpenFolder;
  final InstalledAppAction? onManageApp;
  final AppStorageProfileAction? onReviewCleanable;
  final AppStorageProfileAction? onAskAgent;

  const CleanerAppsView({
    Key? key,
    required this.cubit,
    this.onOpenFolder,
    this.onManageApp,
    this.onReviewCleanable,
    this.onAskAgent,
  }) : super(key: key);

  @override
  State<CleanerAppsView> createState() => _CleanerAppsViewState();
}

class _CleanerAppsViewState extends State<CleanerAppsView> {
  static const Duration _searchDebounce = Duration(milliseconds: 220);

  late final TextEditingController _searchController;
  Timer? _searchDebounceTimer;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.cubit.state.searchQuery,
    );
  }

  @override
  void didUpdateWidget(CleanerAppsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cubit != widget.cubit) {
      _syncSearchText(widget.cubit.state.searchQuery);
    }
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Filtering rescans every app, so keystrokes are coalesced instead of
  // driving one full filter + rebuild each.
  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();
    if (query.trim() == widget.cubit.state.searchQuery.trim()) return;
    _searchDebounceTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      widget.cubit.setSearchQuery(query);
    });
  }

  void _syncSearchText(String query) {
    // A pending debounce means the field is ahead of the cubit on purpose.
    if (_searchDebounceTimer?.isActive ?? false) return;
    if (_searchController.text == query) return;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CleanerAppInsightsCubit, CleanerAppInsightsState>(
      key: const ValueKey<String>('cleaner-apps-view'),
      bloc: widget.cubit,
      listener: (context, state) => _syncSearchText(state.searchQuery),
      builder: (context, state) {
        final l10n = AppLocalizations.of(context)!;

        switch (state.status) {
          case CleanerAppInsightsStatus.loading:
            return _CenteredStatus(
              key: const ValueKey<String>('cleaner-apps-loading'),
              icon: const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              message: l10n.cleanerAppsLoading,
            );
          case CleanerAppInsightsStatus.failure:
            return _CenteredStatus(
              key: const ValueKey<String>('cleaner-apps-error'),
              icon: Icon(
                Icons.error_outline_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.error,
              ),
              message: l10n.cleanerAppsLoadFailed(
                state.errorMessage ?? l10n.cleanerAppsUnknown,
              ),
            );
          case CleanerAppInsightsStatus.idle:
            return _CenteredStatus(
              key: const ValueKey<String>('cleaner-apps-idle'),
              icon: const Icon(Icons.apps_rounded, size: 34),
              message: l10n.cleanerAppsUnavailable,
            );
          case CleanerAppInsightsStatus.ready:
            final report = state.report;
            if (report == null) {
              return _CenteredStatus(
                key: const ValueKey<String>('cleaner-apps-unavailable'),
                icon: const Icon(Icons.apps_rounded, size: 34),
                message: l10n.cleanerAppsUnavailable,
              );
            }
            return _buildReport(context, l10n, state, report);
        }
      },
    );
  }

  Widget _buildReport(
    BuildContext context,
    AppLocalizations l10n,
    CleanerAppInsightsState state,
    AppStorageReport report,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report.isPartial || report.warnings.isNotEmpty)
          _PartialReportBanner(message: l10n.cleanerAppsPartialBanner),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SummaryCards(cubit: widget.cubit, state: state),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _FiltersToolbar(
            cubit: widget.cubit,
            state: state,
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 1120;
              if (isWide) {
                return _buildWideBody(context, state, report);
              }
              return _buildCompactBody(context, state, report);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWideBody(
    BuildContext context,
    CleanerAppInsightsState state,
    AppStorageReport report,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 6,
          child: _AppsListPanel(
            cubit: widget.cubit,
            state: state,
            sharedEntries: report.sharedOrUnattributed,
            onOpenFolder: widget.onOpenFolder,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 5,
          child: _AppDetailsPanel(
            profile: state.selectedProfile,
            onOpenFolder: widget.onOpenFolder,
            onManageApp: widget.onManageApp,
            onReviewCleanable: widget.onReviewCleanable,
            onAskAgent: widget.onAskAgent,
            evaluatedAt: state.evaluatedAt,
            isAttention: state.selectedProfile != null &&
                appNeedsAttention(
                  state.selectedProfile!,
                  evaluatedAt: state.evaluatedAt,
                  largeThresholdBytes: state.largeThresholdBytes,
                  staleThresholdDays: state.staleThresholdDays,
                ),
            scrollable: true,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactBody(
    BuildContext context,
    CleanerAppInsightsState state,
    AppStorageReport report,
  ) {
    final profiles = state.visibleApps;
    final hasShared = report.sharedOrUnattributed.isNotEmpty;
    final itemCount =
        profiles.length + (profiles.isEmpty ? 1 : 0) + (hasShared ? 1 : 0);

    return ListView.builder(
      key: const ValueKey<String>('cleaner-apps-compact-list'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      itemCount: itemCount + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _ResultsCount(count: profiles.length);
        }
        var contentIndex = index - 1;
        if (profiles.isEmpty) {
          if (contentIndex == 0) {
            return const _NoAppsFound();
          }
          contentIndex--;
        }
        if (contentIndex < profiles.length) {
          final profile = profiles[contentIndex];
          final isSelected = profile.app.id == state.selectedAppId;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AppRow(
                profile: profile,
                isSelected: isSelected,
                isAttention: appNeedsAttention(
                  profile,
                  evaluatedAt: state.evaluatedAt,
                  largeThresholdBytes: state.largeThresholdBytes,
                  staleThresholdDays: state.staleThresholdDays,
                ),
                evaluatedAt: state.evaluatedAt,
                onTap: () => widget.cubit.selectApp(profile.app.id),
              ),
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AppDetailsPanel(
                    profile: profile,
                    onOpenFolder: widget.onOpenFolder,
                    onManageApp: widget.onManageApp,
                    onReviewCleanable: widget.onReviewCleanable,
                    onAskAgent: widget.onAskAgent,
                    evaluatedAt: state.evaluatedAt,
                    isAttention: appNeedsAttention(
                      profile,
                      evaluatedAt: state.evaluatedAt,
                      largeThresholdBytes: state.largeThresholdBytes,
                      staleThresholdDays: state.staleThresholdDays,
                    ),
                    scrollable: false,
                  ),
                ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: _SharedStoragePanel(
            entries: report.sharedOrUnattributed,
            onOpenFolder: widget.onOpenFolder,
          ),
        );
      },
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  final Widget icon;
  final String message;

  const _CenteredStatus({
    Key? key,
    required this.icon,
    required this.message,
  }) : super(key: key);

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

class _PartialReportBanner extends StatelessWidget {
  final String message;

  const _PartialReportBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey<String>('cleaner-apps-partial-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      color: theme.colorScheme.tertiaryContainer,
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final CleanerAppInsightsCubit cubit;
  final CleanerAppInsightsState state;

  const _SummaryCards({required this.cubit, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final report = state.report!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCard(
              key: const ValueKey<String>('cleaner-apps-summary-footprint'),
              icon: Icons.apps_rounded,
              title: l10n.cleanerAppsTitle,
              value: FormatUtils.formatFileSize(report.confirmedSizeBytes),
            ),
          ),
          const _SummaryDivider(),
          Expanded(
            child: _SummaryCard(
              key: const ValueKey<String>('cleaner-apps-summary-attention'),
              icon: Icons.auto_awesome_rounded,
              title: l10n.cleanerAppsSummaryAttention,
              value: state.attentionAppCount.toString(),
              accentColor: Colors.orange.shade800,
              selected: state.filter == CleanerAppFilter.attention,
              onTap: () => cubit.setFilter(CleanerAppFilter.attention),
            ),
          ),
          const _SummaryDivider(),
          Expanded(
            child: _SummaryCard(
              key: const ValueKey<String>('cleaner-apps-summary-cleanable'),
              icon: Icons.cleaning_services_outlined,
              title: l10n.cleanerAppsSummaryCleanable,
              value: FormatUtils.formatFileSize(report.cleanableBytes),
              accentColor: Colors.teal.shade700,
              onTap: () => cubit.setFilter(CleanerAppFilter.cleanable),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      color: Theme.of(context).dividerColor,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color? accentColor;
  final bool selected;
  final VoidCallback? onTap;

  const _SummaryCard({
    Key? key,
    required this.icon,
    required this.title,
    required this.value,
    this.accentColor,
    this.selected = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: selected
            ? BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(11),
              )
            : null,
        child: Row(
          children: [
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

class _FiltersToolbar extends StatelessWidget {
  final CleanerAppInsightsCubit cubit;
  final CleanerAppInsightsState state;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  const _FiltersToolbar({
    required this.cubit,
    required this.state,
    required this.searchController,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchWidth =
            constraints.maxWidth < 560 ? constraints.maxWidth : 280.0;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _SearchField(
              width: searchWidth,
              controller: searchController,
              hintText: l10n.cleanerAppsSearchHint,
              onChanged: onSearchChanged,
            ),
            for (final filter in CleanerAppFilter.values)
              FilterChip(
                key: ValueKey<String>('cleaner-apps-filter-${filter.name}'),
                selected: state.filter == filter,
                onSelected: (_) => cubit.setFilter(filter),
                label: Text(_filterLabel(l10n, filter)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                showCheckmark: false,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            _ViewOptionsMenu(
              cubit: cubit,
              state: state,
            ),
          ],
        );
      },
    );
  }
}

/// Search box for the apps list. Rebuilds on its own (clear button, focus
/// highlight) so typing never repaints the surrounding toolbar or list.
class _SearchField extends StatelessWidget {
  final double width;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const _SearchField({
    required this.width,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(
        color: colors.outline.withValues(alpha: 0.55),
      ),
    );

    return SizedBox(
      width: width,
      height: 38,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          return TextField(
            key: const ValueKey<String>('cleaner-apps-search'),
            controller: controller,
            onChanged: onChanged,
            textAlignVertical: TextAlignVertical.center,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: WidgetStateColor.resolveWith((states) {
                return colors.surfaceContainerHighest.withValues(
                  alpha: states.contains(WidgetState.focused) ? 0.62 : 0.45,
                );
              }),
              hintText: hintText,
              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              suffixIcon: value.text.isEmpty
                  ? null
                  : IconButton(
                      key: const ValueKey<String>('cleaner-apps-search-clear'),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      splashRadius: 14,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip:
                          MaterialLocalizations.of(context).deleteButtonTooltip,
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: focusedBorder,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          );
        },
      ),
    );
  }
}

enum _ViewOption {
  sortAttention,
  sortSize,
  sortName,
  sortLastOpened,
  large500Mb,
  large1Gb,
  large5Gb,
  stale90Days,
  stale180Days,
  stale365Days,
}

class _ViewOptionsMenu extends StatelessWidget {
  final CleanerAppInsightsCubit cubit;
  final CleanerAppInsightsState state;

  const _ViewOptionsMenu({required this.cubit, required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<_ViewOption>(
      key: const ValueKey<String>('cleaner-apps-view-options'),
      tooltip: l10n.cleanerAppsViewOptions,
      icon: const Icon(Icons.tune_rounded, size: 20),
      onSelected: (option) => _apply(option),
      itemBuilder: (context) => <PopupMenuEntry<_ViewOption>>[
        PopupMenuItem<_ViewOption>(
          enabled: false,
          height: 32,
          child: Text(l10n.cleanerAppsSortLabel),
        ),
        ...CleanerAppSort.values.map(
          (sort) => CheckedPopupMenuItem<_ViewOption>(
            value: _sortOption(sort),
            checked: state.sort == sort,
            child: Text(_sortLabel(l10n, sort)),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_ViewOption>(
          enabled: false,
          height: 32,
          child: Text(l10n.cleanerAppsLargeThresholdLabel),
        ),
        for (var index = 0;
            index < cleanerAppLargeThresholdPresets.length;
            index++)
          CheckedPopupMenuItem<_ViewOption>(
            value: <_ViewOption>[
              _ViewOption.large500Mb,
              _ViewOption.large1Gb,
              _ViewOption.large5Gb,
            ][index],
            checked: state.largeThresholdBytes ==
                cleanerAppLargeThresholdPresets[index],
            child: Text(
              FormatUtils.formatFileSize(
                cleanerAppLargeThresholdPresets[index],
              ),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<_ViewOption>(
          enabled: false,
          height: 32,
          child: Text(l10n.cleanerAppsFilterStale),
        ),
        for (var index = 0; index < cleanerAppStaleDayPresets.length; index++)
          CheckedPopupMenuItem<_ViewOption>(
            value: <_ViewOption>[
              _ViewOption.stale90Days,
              _ViewOption.stale180Days,
              _ViewOption.stale365Days,
            ][index],
            checked:
                state.staleThresholdDays == cleanerAppStaleDayPresets[index],
            child: Text(l10n.cleanerAppsDays(cleanerAppStaleDayPresets[index])),
          ),
      ],
    );
  }

  _ViewOption _sortOption(CleanerAppSort sort) {
    switch (sort) {
      case CleanerAppSort.attentionDescending:
        return _ViewOption.sortAttention;
      case CleanerAppSort.sizeDescending:
        return _ViewOption.sortSize;
      case CleanerAppSort.nameAscending:
        return _ViewOption.sortName;
      case CleanerAppSort.lastOpenedOldest:
        return _ViewOption.sortLastOpened;
    }
  }

  void _apply(_ViewOption option) {
    switch (option) {
      case _ViewOption.sortAttention:
        cubit.setSort(CleanerAppSort.attentionDescending);
        break;
      case _ViewOption.sortSize:
        cubit.setSort(CleanerAppSort.sizeDescending);
        break;
      case _ViewOption.sortName:
        cubit.setSort(CleanerAppSort.nameAscending);
        break;
      case _ViewOption.sortLastOpened:
        cubit.setSort(CleanerAppSort.lastOpenedOldest);
        break;
      case _ViewOption.large500Mb:
        cubit.setLargeThresholdBytes(cleanerAppLargeThresholdPresets[0]);
        break;
      case _ViewOption.large1Gb:
        cubit.setLargeThresholdBytes(cleanerAppLargeThresholdPresets[1]);
        break;
      case _ViewOption.large5Gb:
        cubit.setLargeThresholdBytes(cleanerAppLargeThresholdPresets[2]);
        break;
      case _ViewOption.stale90Days:
        cubit.setStaleThresholdDays(cleanerAppStaleDayPresets[0]);
        break;
      case _ViewOption.stale180Days:
        cubit.setStaleThresholdDays(cleanerAppStaleDayPresets[1]);
        break;
      case _ViewOption.stale365Days:
        cubit.setStaleThresholdDays(cleanerAppStaleDayPresets[2]);
        break;
    }
  }
}

class _AppsListPanel extends StatelessWidget {
  final CleanerAppInsightsCubit cubit;
  final CleanerAppInsightsState state;
  final List<AppStorageEntry> sharedEntries;
  final AppStorageEntryAction? onOpenFolder;

  const _AppsListPanel({
    required this.cubit,
    required this.state,
    required this.sharedEntries,
    this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    final profiles = state.visibleApps;
    final hasShared = sharedEntries.isNotEmpty;
    final itemCount =
        profiles.length + (profiles.isEmpty ? 1 : 0) + (hasShared ? 1 : 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: _ResultsCount(count: profiles.length),
        ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey<String>('cleaner-apps-wide-list'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            itemCount: itemCount,
            itemBuilder: (context, index) {
              var contentIndex = index;
              if (profiles.isEmpty) {
                if (contentIndex == 0) return const _NoAppsFound();
                contentIndex--;
              }
              if (contentIndex < profiles.length) {
                final profile = profiles[contentIndex];
                return _AppRow(
                  profile: profile,
                  isSelected: profile.app.id == state.selectedAppId,
                  isAttention: appNeedsAttention(
                    profile,
                    evaluatedAt: state.evaluatedAt,
                    largeThresholdBytes: state.largeThresholdBytes,
                    staleThresholdDays: state.staleThresholdDays,
                  ),
                  evaluatedAt: state.evaluatedAt,
                  onTap: () => cubit.selectApp(profile.app.id),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _SharedStoragePanel(
                  entries: sharedEntries,
                  onOpenFolder: onOpenFolder,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResultsCount extends StatelessWidget {
  final int count;

  const _ResultsCount({required this.count});

  @override
  Widget build(BuildContext context) {
    return Text(
      AppLocalizations.of(context)!.cleanerAppsShowingCount(count),
      key: const ValueKey<String>('cleaner-apps-result-count'),
      style: Theme.of(context).textTheme.labelLarge,
    );
  }
}

class _NoAppsFound extends StatelessWidget {
  const _NoAppsFound();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('cleaner-apps-no-results'),
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Text(
        AppLocalizations.of(context)!.cleanerAppsNoResults,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  final AppStorageProfile profile;
  final bool isSelected;
  final bool isAttention;
  final DateTime evaluatedAt;
  final VoidCallback onTap;

  const _AppRow({
    required this.profile,
    required this.isSelected,
    required this.isAttention,
    required this.evaluatedAt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final app = profile.app;
    final usageLabel = _compactUsageLabel(
      l10n,
      profile.usage,
      evaluatedAt,
    );
    final sizeLabel = _profileSizeLabel(l10n, profile);
    final attentionColor = Colors.orange.shade800;

    return Container(
      key: ValueKey<String>('cleaner-app-row-${app.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isAttention
            ? attentionColor.withValues(alpha: isSelected ? 0.12 : 0.055)
            : isSelected
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.52)
                : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isAttention
              ? attentionColor.withValues(alpha: 0.65)
              : isSelected
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
          width: isAttention ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          child: Row(
            children: [
              if (isAttention) ...[
                Container(
                  width: 3,
                  height: 38,
                  decoration: BoxDecoration(
                    color: attentionColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              _InstalledAppIcon(app: app, size: 36),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (isAttention) ...[
                          _MetaBadge(
                            label: l10n.cleanerAppsAttentionBadge,
                            color: attentionColor,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            usageLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isAttention
                                  ? attentionColor
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: isAttention ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      sizeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (profile.cleanableBytes > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${FormatUtils.formatFileSize(profile.cleanableBytes)} '
                        '• ${l10n.cleanerAppsFilterCleanable}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppDetailsPanel extends StatelessWidget {
  final AppStorageProfile? profile;
  final AppStorageEntryAction? onOpenFolder;
  final InstalledAppAction? onManageApp;
  final AppStorageProfileAction? onReviewCleanable;
  final AppStorageProfileAction? onAskAgent;
  final DateTime evaluatedAt;
  final bool isAttention;
  final bool scrollable;

  const _AppDetailsPanel({
    required this.profile,
    required this.onOpenFolder,
    required this.onManageApp,
    required this.onReviewCleanable,
    required this.onAskAgent,
    required this.evaluatedAt,
    required this.isAttention,
    required this.scrollable,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final current = profile;
    if (current == null) {
      return _CenteredStatus(
        icon: const Icon(Icons.touch_app_outlined, size: 32),
        message: l10n.cleanerAppsSelectApp,
      );
    }

    final content = Container(
      key: ValueKey<String>('cleaner-app-detail-${current.app.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailsHeader(profile: current),
          const SizedBox(height: 12),
          _DetailsMetrics(
            profile: current,
            evaluatedAt: evaluatedAt,
            isAttention: isAttention,
          ),
          const SizedBox(height: 12),
          _DetailsActions(
            profile: current,
            onManageApp: onManageApp,
            onReviewCleanable: onReviewCleanable,
            onAskAgent: onAskAgent,
          ),
          const SizedBox(height: 18),
          Text(
            l10n.cleanerAppsStorageBreakdown,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (current.entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(l10n.cleanerAppsNoStorageDetails),
            )
          else
            for (final entry in current.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _StorageEntryTile(
                  key: ValueKey<String>(
                    'cleaner-app-entry-${current.app.id}-${entry.path}',
                  ),
                  entry: entry,
                  onOpenFolder: onOpenFolder,
                ),
              ),
        ],
      ),
    );

    if (!scrollable) return content;
    return SingleChildScrollView(child: content);
  }
}

class _DetailsHeader extends StatelessWidget {
  final AppStorageProfile profile;

  const _DetailsHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final app = profile.app;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InstalledAppIcon(app: app, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.displayName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (app.publisher?.trim().isNotEmpty ?? false)
                Text(
                  app.publisher!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (app.version?.trim().isNotEmpty ?? false) ...[
                const SizedBox(height: 3),
                Text(
                  l10n.cleanerAppsVersion(app.version!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailsMetrics extends StatelessWidget {
  final AppStorageProfile profile;
  final DateTime evaluatedAt;
  final bool isAttention;

  const _DetailsMetrics({
    required this.profile,
    required this.evaluatedAt,
    required this.isAttention,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final attentionColor = Colors.orange.shade800;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isAttention
            ? attentionColor.withValues(alpha: 0.07)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: isAttention
              ? attentionColor.withValues(alpha: 0.5)
              : theme.dividerColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _CompactMetric(
              label: l10n.cleanerAppsConfirmedFootprint,
              value: profile.confirmedSizeBytes > 0
                  ? FormatUtils.formatFileSize(profile.confirmedSizeBytes)
                  : _profileSizeLabel(l10n, profile),
            ),
          ),
          Container(width: 1, height: 34, color: theme.dividerColor),
          const SizedBox(width: 12),
          Expanded(
            child: _CompactMetric(
              label: l10n.cleanerAppsFilterStale,
              value: _compactUsageLabel(
                l10n,
                profile.usage,
                evaluatedAt,
              ),
              valueColor: isAttention ? attentionColor : null,
            ),
          ),
          if (profile.cleanableBytes > 0) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 34, color: theme.dividerColor),
            const SizedBox(width: 12),
            Expanded(
              child: _CompactMetric(
                label: l10n.cleanerAppsFilterCleanable,
                value: FormatUtils.formatFileSize(profile.cleanableBytes),
                valueColor: Colors.teal.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _CompactMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DetailsActions extends StatelessWidget {
  final AppStorageProfile profile;
  final InstalledAppAction? onManageApp;
  final AppStorageProfileAction? onReviewCleanable;
  final AppStorageProfileAction? onAskAgent;

  const _DetailsActions({
    required this.profile,
    required this.onManageApp,
    required this.onReviewCleanable,
    required this.onAskAgent,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final buttonShape = ChipTheme.of(context).shape ?? const StadiumBorder();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (profile.app.canManage && onManageApp != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(shape: buttonShape),
            key: ValueKey<String>(
              'cleaner-app-manage-${profile.app.id}',
            ),
            onPressed: () => onManageApp!(profile.app),
            icon: const Icon(Icons.settings_outlined, size: 17),
            label: Text(l10n.cleanerAppsManageInWindows),
          ),
        if (profile.cleanableBytes > 0 && onReviewCleanable != null)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(shape: buttonShape),
            key: ValueKey<String>(
              'cleaner-app-review-${profile.app.id}',
            ),
            onPressed: () => onReviewCleanable!(profile),
            icon: const Icon(Icons.fact_check_outlined, size: 17),
            label: Text(l10n.cleanerAppsReviewCleanable),
          ),
        if (onAskAgent != null)
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(shape: buttonShape),
            key: ValueKey<String>(
              'cleaner-app-ask-agent-${profile.app.id}',
            ),
            onPressed: () => onAskAgent!(profile),
            icon: const Icon(Icons.auto_awesome_outlined, size: 17),
            label: Text(l10n.cleanerAppsAskAgent),
          ),
      ],
    );
  }
}

class _StorageEntryTile extends StatelessWidget {
  final AppStorageEntry entry;
  final AppStorageEntryAction? onOpenFolder;

  const _StorageEntryTile({
    Key? key,
    required this.entry,
    required this.onOpenFolder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final size = entry.sizeBytes > 0
        ? FormatUtils.formatFileSize(entry.sizeBytes)
        : l10n.cleanerAppsUnknown;
    final technicalDetails = '${_measurementLabel(
      l10n,
      entry.measurementQuality,
    )} • ${_attributionLabel(l10n, entry.attributionConfidence)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(_storageKindIcon(entry.kind), size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _storageKindLabel(l10n, entry.kind),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                    Text(
                      size,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                CbTooltip(
                  message: '${entry.path}\n$technicalDetails',
                  child: Text(
                    entry.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (entry.isCleanable)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                Icons.cleaning_services_outlined,
                size: 17,
                color: Colors.teal.shade700,
              ),
            ),
          if (onOpenFolder != null)
            IconButton(
              style: IconButton.styleFrom(
                shape: ChipTheme.of(context).shape ?? const StadiumBorder(),
              ),
              key: ValueKey<String>(
                'cleaner-app-open-folder-${entry.path}',
              ),
              tooltip: l10n.cleanerAppsOpenFolder,
              onPressed: () => onOpenFolder!(entry),
              icon: const Icon(Icons.folder_open_outlined, size: 18),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

class _SharedStoragePanel extends StatelessWidget {
  final List<AppStorageEntry> entries;
  final AppStorageEntryAction? onOpenFolder;

  const _SharedStoragePanel({
    required this.entries,
    required this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return ExpansionTile(
      key: const ValueKey<String>('cleaner-apps-shared-storage'),
      initiallyExpanded: false,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: theme.dividerColor),
      ),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: theme.dividerColor),
      ),
      leading: const Icon(Icons.folder_shared_outlined, size: 19),
      title: Text(
        '${l10n.cleanerAppsSharedFolders} (${entries.length})',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelLarge,
      ),
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _StorageEntryTile(
              key: ValueKey<String>('cleaner-app-shared-${entry.path}'),
              entry: entry,
              onOpenFolder: onOpenFolder,
            ),
          ),
      ],
    );
  }
}

class _MetaBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MetaBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _InstalledAppIcon extends StatefulWidget {
  final InstalledAppInfo app;
  final double size;

  const _InstalledAppIcon({required this.app, required this.size});

  @override
  State<_InstalledAppIcon> createState() => _InstalledAppIconState();
}

class _InstalledAppIconState extends State<_InstalledAppIcon> {
  Future<ui.Image?>? _iconFuture;
  String? _iconPath;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(_InstalledAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPath = _resolveIconPath(widget.app);
    if (nextPath != _iconPath) _loadIcon();
  }

  void _loadIcon() {
    _iconPath = _resolveIconPath(widget.app);
    _iconFuture = _iconPath == null
        ? Future<ui.Image?>.value(null)
        : WindowsAppIcon.extractIconFromFile(_iconPath!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(widget.size * 0.22),
      ),
      child: FutureBuilder<ui.Image?>(
        future: _iconFuture,
        builder: (context, snapshot) {
          final image = snapshot.data;
          if (image != null) {
            return RawImage(
              image: image,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            );
          }
          return Icon(
            widget.app.source == InstalledAppSource.msix
                ? Icons.window_rounded
                : Icons.apps_rounded,
            size: widget.size * 0.58,
            color: theme.colorScheme.onSurfaceVariant,
          );
        },
      ),
    );
  }
}

String? _resolveIconPath(InstalledAppInfo app) {
  final displayIcon = app.displayIconPath?.trim();
  if (displayIcon != null && displayIcon.isNotEmpty) return displayIcon;
  if (app.executablePaths.isNotEmpty) return app.executablePaths.first;
  return null;
}

String _filterLabel(AppLocalizations l10n, CleanerAppFilter filter) {
  switch (filter) {
    case CleanerAppFilter.all:
      return l10n.cleanerAppsFilterAll;
    case CleanerAppFilter.attention:
      return l10n.cleanerAppsFilterAttention;
    case CleanerAppFilter.large:
      return l10n.cleanerAppsFilterLarge;
    case CleanerAppFilter.stale:
      return l10n.cleanerAppsFilterStale;
    case CleanerAppFilter.cleanable:
      return l10n.cleanerAppsFilterCleanable;
  }
}

String _sortLabel(AppLocalizations l10n, CleanerAppSort sort) {
  switch (sort) {
    case CleanerAppSort.attentionDescending:
      return l10n.cleanerAppsFilterAttention;
    case CleanerAppSort.sizeDescending:
      return l10n.cleanerAppsSortSize;
    case CleanerAppSort.nameAscending:
      return l10n.cleanerAppsSortName;
    case CleanerAppSort.lastOpenedOldest:
      return l10n.cleanerAppsSortLastOpened;
  }
}

String _measurementLabel(
  AppLocalizations l10n,
  MeasurementQuality quality,
) {
  switch (quality) {
    case MeasurementQuality.measured:
      return l10n.cleanerAppsMeasurementMeasured;
    case MeasurementQuality.estimated:
      return l10n.cleanerAppsMeasurementEstimated;
    case MeasurementQuality.partial:
      return l10n.cleanerAppsMeasurementPartial;
    case MeasurementQuality.unknown:
      return l10n.cleanerAppsMeasurementUnknown;
  }
}

String _attributionLabel(
  AppLocalizations l10n,
  AttributionConfidence confidence,
) {
  switch (confidence) {
    case AttributionConfidence.confirmed:
      return l10n.cleanerAppsAttributionConfirmed;
    case AttributionConfidence.likely:
      return l10n.cleanerAppsAttributionPossible;
    case AttributionConfidence.shared:
      return l10n.cleanerAppsAttributionShared;
  }
}

String _storageKindLabel(AppLocalizations l10n, AppStorageKind kind) {
  switch (kind) {
    case AppStorageKind.install:
      return l10n.cleanerAppsStorageInstall;
    case AppStorageKind.localData:
      return l10n.cleanerAppsStorageLocalData;
    case AppStorageKind.roamingData:
      return l10n.cleanerAppsStorageRoamingData;
    case AppStorageKind.packageData:
      return l10n.cleanerAppsStoragePackageData;
    case AppStorageKind.programData:
      return l10n.cleanerAppsStorageProgramData;
    case AppStorageKind.cache:
      return l10n.cleanerAppsStorageCache;
    case AppStorageKind.logs:
      return l10n.cleanerAppsStorageLogs;
    case AppStorageKind.shared:
      return l10n.cleanerAppsStorageShared;
    case AppStorageKind.unknown:
      return l10n.cleanerAppsStorageUnknown;
  }
}

IconData _storageKindIcon(AppStorageKind kind) {
  switch (kind) {
    case AppStorageKind.install:
      return Icons.inventory_2_outlined;
    case AppStorageKind.localData:
    case AppStorageKind.roamingData:
    case AppStorageKind.packageData:
    case AppStorageKind.programData:
      return Icons.folder_outlined;
    case AppStorageKind.cache:
      return Icons.cached_rounded;
    case AppStorageKind.logs:
      return Icons.receipt_long_outlined;
    case AppStorageKind.shared:
      return Icons.folder_shared_outlined;
    case AppStorageKind.unknown:
      return Icons.folder_copy_outlined;
  }
}

String _profileSizeLabel(
  AppLocalizations l10n,
  AppStorageProfile profile,
) {
  final bytes = profile.bestKnownSizeBytes;
  if (bytes <= 0 &&
      (profile.measurementQuality == MeasurementQuality.partial ||
          profile.measurementQuality == MeasurementQuality.unknown)) {
    return l10n.cleanerAppsUnknown;
  }
  return FormatUtils.formatFileSize(bytes);
}

String _compactUsageLabel(
  AppLocalizations l10n,
  AppUsageEvidence usage,
  DateTime evaluatedAt,
) {
  final date = usage.lastOpenedAt;
  if (date == null || date.isAfter(evaluatedAt)) {
    return l10n.cleanerAppsUsageUnknownCompact;
  }
  return l10n.cleanerAppsNotOpenedForDays(
    evaluatedAt.difference(date).inDays,
  );
}
