import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';

import '../../../config/languages/app_localizations.dart';
import '../../../services/disk_cleaner/cleaner_models.dart';
import '../../../services/disk_cleaner/cleaner_suggestions.dart';
import '../../utils/format_utils.dart';
import 'cleaner_suggestions_progress.dart';

typedef CleanerSuggestionScan =
    Future<CleanerSuggestionReport> Function(
      void Function(CleanerSuggestionProgress progress) onProgress,
    );

typedef CleanerSuggestionClean =
    Future<CleanReport?> Function(
      List<JunkItem> items,
      void Function(int done, int total, String? path) onProgress,
    );

/// "Cleanup suggestions" utility: scans one drive for things worth cleaning,
/// explains each finding and moves only the items the user keeps checked to
/// the Recycle Bin.
class CleanerSuggestionsView extends StatefulWidget {
  final String drivePath;

  /// Whether a Disk usage scan of [drivePath] is available for deeper
  /// suggestions (old large files, node_modules, virtual disks).
  final bool hasDiskScan;

  /// False while another Cleaner scan or cleanup is running.
  final bool enabled;
  final CleanerSuggestionScan onScan;
  final CleanerSuggestionClean onClean;
  final ValueChanged<String> onOpenFolder;
  final ValueChanged<String> onOpenSettings;
  final VoidCallback onOpenDiskUsage;
  final String Function(String categoryId) categoryLabel;
  final String Function(String categoryId) categoryReason;

  const CleanerSuggestionsView({
    super.key,
    required this.drivePath,
    required this.hasDiskScan,
    required this.enabled,
    required this.onScan,
    required this.onClean,
    required this.onOpenFolder,
    required this.onOpenSettings,
    required this.onOpenDiskUsage,
    required this.categoryLabel,
    required this.categoryReason,
  });

  @override
  State<CleanerSuggestionsView> createState() => _CleanerSuggestionsViewState();
}

class _CleanerSuggestionsViewState extends State<CleanerSuggestionsView> {
  static const _visibleItemLimit = 30;

  CleanerSuggestionReport? _report;
  final ValueNotifier<CleanerSuggestionProgress?> _progress = ValueNotifier(
    null,
  );
  final ValueNotifier<(int, int, String?)?> _cleanProgress = ValueNotifier(
    null,
  );
  DateTime _scanStartedAt = DateTime.now();
  bool _scanning = false;
  bool _cleaning = false;
  String? _error;

  /// Checked item paths. Only these are ever passed to [onClean].
  final Set<String> _checked = {};
  final Set<String> _expanded = {};

  bool get _busy => _scanning || _cleaning || !widget.enabled;

  @override
  void dispose() {
    _progress.dispose();
    _cleanProgress.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() {
      _scanning = true;
      _error = null;
      _scanStartedAt = DateTime.now();
    });
    _progress.value = null;
    try {
      final report = await widget.onScan((progress) {
        if (mounted) _progress.value = progress;
      });
      if (!mounted) return;
      setState(() {
        _report = report;
        _checked
          ..clear()
          ..addAll([
            for (final suggestion in report.suggestions)
              if (suggestion.selectedByDefault)
                for (final item in suggestion.items) item.path,
          ]);
        _expanded.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<JunkItem> get _checkedItems {
    final report = _report;
    if (report == null) return const [];
    final seen = <String>{};
    return [
      for (final suggestion in report.suggestions)
        if (suggestion.tier != CleanerSuggestionTier.guided)
          for (final item in suggestion.items)
            if (_checked.contains(item.path) && seen.add(item.path)) item,
    ];
  }

  Future<void> _cleanChecked() async {
    final items = _checkedItems;
    if (items.isEmpty || _busy) return;
    final l = AppLocalizations.of(context)!;
    final bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final personal = items.where((item) => item.isUserSelected).length;
    final binItems = items
        .where(
          (item) => item.isRecycleBinItem || item.categoryId == 'recycle_bin',
        )
        .length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cleanerSuggestionsConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.cleanerSuggestionsConfirmBody(
                items.length,
                FormatUtils.formatFileSize(bytes),
              ),
            ),
            if (personal > 0) ...[
              const SizedBox(height: 10),
              _Warning(text: l.cleanerSuggestionsConfirmPersonal(personal)),
            ],
            if (binItems > 0) ...[
              const SizedBox(height: 10),
              _Warning(text: l.cleanerSuggestionsConfirmRecycleBin(binItems)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('cleaner-suggestions-confirm-clean'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.diskCleanerMoveToRecycleBin),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _cleanProgress.value = null;
    setState(() => _cleaning = true);
    CleanReport? result;
    try {
      result = await widget.onClean(items, (done, total, path) {
        if (mounted) _cleanProgress.value = (done, total, path);
      });
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
    if (!mounted || result == null) return;

    final removed = result.succeeded.toSet();
    final report = _report!;
    setState(() {
      _checked.removeAll(removed);
      _report = CleanerSuggestionReport(
        drivePath: report.drivePath,
        usedDiskScan: report.usedDiskScan,
        warnings: report.warnings,
        errors: report.errors,
        scannedAt: report.scannedAt,
        suggestions: [
          for (final suggestion in report.suggestions)
            if (suggestion.tier == CleanerSuggestionTier.guided)
              suggestion
            else if (suggestion.items.any(
              (item) => !removed.contains(item.path),
            ))
              suggestion.withItems(
                suggestion.items
                    .where((item) => !removed.contains(item.path))
                    .toList(),
              ),
        ],
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l.cleanerSuggestionsCleaned(
            FormatUtils.formatFileSize(result.freedBytes),
          ),
        ),
      ),
    );
  }

  void _toggleSuggestion(CleanerSuggestion suggestion, bool select) {
    setState(() {
      for (final item in suggestion.items) {
        select ? _checked.add(item.path) : _checked.remove(item.path);
      }
    });
  }

  void _toggleItem(JunkItem item, bool select) {
    setState(() {
      select ? _checked.add(item.path) : _checked.remove(item.path);
    });
  }

  Future<void> _copyCommand(String command) async {
    await Clipboard.setData(ClipboardData(text: command));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(
            context,
          )!.cleanerSuggestionsCommandCopied(command),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final report = _report;
    return Column(
      key: const ValueKey('cleaner-suggestions-feature'),
      children: [
        _Header(
          drivePath: widget.drivePath,
          report: report,
          busy: _busy,
          scanning: _scanning,
          onScan: _scan,
        ),
        const Divider(height: 1),
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
            child: _scanning
                ? KeyedSubtree(
                    key: const ValueKey('cleaner-suggestions-loading'),
                    child: _buildLoading(),
                  )
                : report == null
                ? _Intro(
                    key: const ValueKey('cleaner-suggestions-intro'),
                    error: _error,
                    enabled: !_busy,
                    onScan: _scan,
                  )
                : KeyedSubtree(
                    key: ValueKey(report.scannedAt),
                    child: _buildResults(theme, l, report),
                  ),
          ),
        ),
        if (report != null) _buildFooter(theme, l),
      ],
    );
  }

  Widget _buildLoading() {
    return CleanerSuggestionScanPanel(
      progress: _progress,
      startedAt: _scanStartedAt,
      categoryLabel: widget.categoryLabel,
    );
  }

  Widget _buildResults(
    ThemeData theme,
    AppLocalizations l,
    CleanerSuggestionReport report,
  ) {
    final sections = <Widget>[
      if (_error != null)
        _Warning(text: l.cleanerSuggestionsScanFailed(_error!)),
      for (final error in report.errors)
        _Warning(
          key: ValueKey('cleaner-suggestions-error-${error.kind.name}'),
          text: error.kind == CleanerSuggestionErrorKind.junkScanBusy
              ? l.cleanerSuggestionsJunkScanBusy
              : l.cleanerSuggestionsPartialScan(error.detail),
        ),
    ];
    if (report.suggestions.isEmpty) {
      sections.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              l.cleanerSuggestionsNothing,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }
    // Each entry animates in once per scan; cleaning keeps entries in place.
    var order = 0;
    for (final tier in CleanerSuggestionTier.values) {
      final suggestions = report.byTier(tier).toList();
      if (suggestions.isEmpty) continue;
      sections.add(
        CleanerStaggeredEntrance(
          key: ValueKey('tier-${tier.name}'),
          index: order++,
          child: _TierHeader(tier: tier),
        ),
      );
      for (final suggestion in suggestions) {
        sections.add(
          CleanerStaggeredEntrance(
            key: ValueKey('entry-${suggestion.id}'),
            index: order++,
            child: _buildCard(theme, l, suggestion),
          ),
        );
      }
    }
    if (!report.usedDiskScan) {
      sections.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: CbDecorations.card(context, radius: 12),
            child: Row(
              children: [
                Icon(
                  Icons.insights_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(l.cleanerSuggestionsDiskScanHint)),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _busy ? null : widget.onOpenDiskUsage,
                  child: Text(l.cleanerDiskUsageTitle),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListView(
      key: const ValueKey('cleaner-suggestions-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: sections,
    );
  }

  Widget _buildCard(
    ThemeData theme,
    AppLocalizations l,
    CleanerSuggestion suggestion,
  ) {
    final categoryId = suggestion.categoryId;
    final title = categoryId != null
        ? widget.categoryLabel(categoryId)
        : l.cleanerSuggestionTitle(suggestion.id);
    final detail = categoryId != null
        ? widget.categoryReason(categoryId)
        : l.cleanerSuggestionDetail(suggestion.id);
    final size = FormatUtils.formatFileSize(suggestion.sizeBytes);
    final selectable = suggestion.tier != CleanerSuggestionTier.guided;
    final checkedCount = suggestion.items
        .where((item) => _checked.contains(item.path))
        .length;
    final allChecked =
        suggestion.items.isNotEmpty && checkedCount == suggestion.items.length;
    final expanded = _expanded.contains(suggestion.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: ValueKey('cleaner-suggestion-${suggestion.id}'),
        decoration: CbDecorations.card(context, radius: 12),
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectable)
                  Checkbox(
                    key: ValueKey('cleaner-suggestion-check-${suggestion.id}'),
                    tristate: true,
                    value: allChecked
                        ? true
                        : (checkedCount == 0 ? false : null),
                    onChanged: _busy
                        ? null
                        : (_) => _toggleSuggestion(suggestion, !allChecked),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Icon(
                      Icons.tips_and_updates_outlined,
                      size: 20,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              suggestion.sizeIsPartial
                                  ? l.cleanerSuggestionsAtLeast(size)
                                  : size,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        if (detail.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            detail,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        _buildActions(l, suggestion, expanded),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (expanded) _buildItems(theme, l, suggestion),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(
    AppLocalizations l,
    CleanerSuggestion suggestion,
    bool expanded,
  ) {
    final actions = <Widget>[
      if (suggestion.items.isNotEmpty)
        TextButton.icon(
          onPressed: () => setState(() {
            expanded
                ? _expanded.remove(suggestion.id)
                : _expanded.add(suggestion.id);
          }),
          icon: Icon(
            expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18,
          ),
          label: Text(
            expanded
                ? l.cleanerSuggestionsHideItems
                : l.cleanerSuggestionsShowItems(suggestion.items.length),
          ),
        ),
      if (suggestion.folderPath != null)
        TextButton.icon(
          onPressed: () => widget.onOpenFolder(suggestion.folderPath!),
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: Text(l.openFolder),
        ),
      if (suggestion.settingsUri != null)
        TextButton.icon(
          onPressed: () => widget.onOpenSettings(suggestion.settingsUri!),
          icon: const Icon(Icons.settings_outlined, size: 18),
          label: Text(l.cleanerSuggestionsOpenSettings),
        ),
      if (suggestion.command != null)
        TextButton.icon(
          onPressed: () => _copyCommand(suggestion.command!),
          icon: const Icon(Icons.content_copy_rounded, size: 16),
          label: Text(l.cleanerSuggestionsCopyCommand),
        ),
    ];
    if (actions.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Wrap(spacing: 4, children: actions),
    );
  }

  Widget _buildItems(
    ThemeData theme,
    AppLocalizations l,
    CleanerSuggestion suggestion,
  ) {
    final visible = suggestion.items.take(_visibleItemLimit).toList();
    final hidden = suggestion.items.length - visible.length;
    return Padding(
      padding: const EdgeInsets.only(left: 36, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in visible)
            Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Checkbox(
                    value: _checked.contains(item.path),
                    visualDensity: VisualDensity.compact,
                    onChanged: _busy
                        ? null
                        : (value) => _toggleItem(item, value ?? false),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Tooltip(
                    message: item.path,
                    child: Text(
                      item.originalPath ?? item.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                if (item.lastModified != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    FormatUtils.formatDate(item.lastModified!),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                SizedBox(
                  width: 72,
                  child: Text(
                    FormatUtils.formatFileSize(item.sizeBytes),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 4),
              child: Text(
                l.cleanerSuggestionsMoreItems(hidden),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, AppLocalizations l) {
    final items = _checkedItems;
    final bytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final selected = l.cleanerSuggestionsSelected(
      FormatUtils.formatFileSize(bytes),
      items.length,
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
                ? CleanerSuggestionsCleanProgress(progress: _cleanProgress)
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: _buildFooterRow(theme, l, items, selected),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow(
    ThemeData theme,
    AppLocalizations l,
    List<JunkItem> items,
    String selected,
  ) {
    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, ?current],
            ),
            child: Text(
              selected,
              key: ValueKey(selected),
              style: theme.textTheme.titleSmall,
            ),
          ),
        ),
        FilledButton.icon(
          key: const ValueKey('cleaner-suggestions-clean'),
          onPressed: items.isEmpty || _busy ? null : _cleanChecked,
          icon: const Icon(Icons.cleaning_services_outlined, size: 18),
          label: Text(l.diskCleanerMoveToRecycleBin),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final String drivePath;
  final CleanerSuggestionReport? report;
  final bool busy;
  final bool scanning;
  final VoidCallback onScan;

  const _Header({
    required this.drivePath,
    required this.report,
    required this.busy,
    required this.scanning,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final report = this.report;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 19,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l.cleanerSuggestionsTitle} · $drivePath',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (report != null)
                  Text(
                    l.cleanerSuggestionsReclaimable(
                      FormatUtils.formatFileSize(report.reclaimableBytes),
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (report != null)
            OutlinedButton.icon(
              key: const ValueKey('cleaner-suggestions-rescan'),
              onPressed: busy ? null : onScan,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l.diskCleanerScanAgain),
            ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final String? error;
  final bool enabled;
  final VoidCallback onScan;

  const _Intro({
    super.key,
    required this.error,
    required this.enabled,
    required this.onScan,
  });

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
                Icons.cleaning_services_outlined,
                size: 44,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                l.cleanerSuggestionsIntro,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (error != null) ...[
                const SizedBox(height: 14),
                _Warning(text: l.cleanerSuggestionsScanFailed(error!)),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('cleaner-suggestions-scan'),
                onPressed: enabled ? onScan : null,
                icon: const Icon(Icons.search_rounded, size: 18),
                label: Text(l.cleanerSuggestionsScan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TierHeader extends StatelessWidget {
  final CleanerSuggestionTier tier;

  const _TierHeader({required this.tier});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    final (title, hint, color) = switch (tier) {
      CleanerSuggestionTier.clean => (
        l.cleanerSuggestionsTierClean,
        l.cleanerSuggestionsTierCleanHint,
        Colors.teal.shade700,
      ),
      CleanerSuggestionTier.review => (
        l.cleanerSuggestionsTierReview,
        l.cleanerSuggestionsTierReviewHint,
        Colors.orange.shade800,
      ),
      CleanerSuggestionTier.guided => (
        l.cleanerSuggestionsTierGuided,
        l.cleanerSuggestionsTierGuidedHint,
        theme.colorScheme.tertiary,
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

class _Warning extends StatelessWidget {
  final String text;

  const _Warning({super.key, required this.text});

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
