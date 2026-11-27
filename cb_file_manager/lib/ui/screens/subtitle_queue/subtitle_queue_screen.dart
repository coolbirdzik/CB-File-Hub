import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as pathlib;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/language_controller.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../design_system/cb_design_system.dart';
import '../../../services/media/subtitle_batch/subtitle_batch_models.dart';
import '../../../services/media/subtitle_batch/subtitle_batch_queue.dart';
import '../../../services/media/subtitle_batch/subtitle_batch_scanner.dart';
import '../../../services/media/subtitle_batch/subtitle_batch_store.dart';
import '../../../services/media/subtitle_batch/subtitle_generated_cleanup.dart';
import '../../../services/media/subtitle_preferences.dart';
import '../../../services/media/subtitle_services.dart';
import '../../components/common/app_toast.dart';
import '../../components/common/item_shell.dart';
import '../../components/common/library_hub_scaffold.dart';
import '../../components/common/shared_action_bar.dart';
import '../../components/common/shared_file_context_menu.dart';
import '../../tab_manager/components/search_bar.dart' as tab_components;
import '../../tab_manager/core/tab_manager.dart';
import '../../tab_manager/core/tab_paths.dart';
import '../../widgets/slim_progress_bar.dart';
import '../../widgets/thumbnail_loader.dart';
import '../folder_list/folder_list_state.dart' show SortOption, ViewMode;
import 'subtitle_rule_dialog.dart';

bool get _desktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Sort keys of the queue list. [queue] is the processing order.
enum _JobSort {
  queue,
  name,
  folder,
  status,
  progress,
  modified,
  added,
  updated,
}

const _viewModes = {
  ViewMode.list,
  ViewMode.details,
  ViewMode.tiles,
  ViewMode.grid,
};
const _prefView = 'subtitle_queue.viewMode';
const _prefSort = 'subtitle_queue.sort';
const _prefAscending = 'subtitle_queue.ascending';

/// Running first, then waiting, problems, and finished work last.
const _statusRank = {
  SubtitleBatchStatus.running: 0,
  SubtitleBatchStatus.pending: 1,
  SubtitleBatchStatus.failed: 2,
  SubtitleBatchStatus.cancelled: 3,
  SubtitleBatchStatus.skipped: 4,
  SubtitleBatchStatus.done: 5,
};

/// Queue and rules for generating AI subtitles for many videos. Shares the
/// browser chrome (address bar, history, toolbar) of the media hubs.
class SubtitleQueueScreen extends StatefulWidget {
  final String tabId;

  /// Tests inject these; the app uses the shared instances.
  final SubtitleBatchQueue? queue;
  final SubtitleBatchStore? store;
  final Future<SubtitleServices> Function()? services;

  const SubtitleQueueScreen({
    super.key,
    required this.tabId,
    this.queue,
    this.store,
    this.services,
  });

  @override
  State<SubtitleQueueScreen> createState() => _SubtitleQueueScreenState();
}

class _SubtitleQueueScreenState extends State<SubtitleQueueScreen> {
  late final SubtitleBatchQueue _queue =
      widget.queue ?? SubtitleBatchQueue.instance;
  late final SubtitleBatchStore _store =
      widget.store ?? SubtitleBatchStore.instance;
  late final SubtitleBatchScanner _scanner = SubtitleBatchScanner(
    store: _store,
  );
  SubtitleServices? _services;
  StreamSubscription<void>? _modelsChanged;
  Timer? _poll;

  SubtitleBatchStatus? _filter;
  List<SubtitleBatchJob> _jobs = const [];
  Map<SubtitleBatchStatus, int> _counts = const {};
  List<SubtitleBatchRule> _rules = const [];
  bool _runRequested = false;
  bool _pauseWhileWatching = true;
  int _parallelJobs = SubtitleBatchStore.autoParallelJobs;
  SubtitleBatchOrder _processingOrder = SubtitleBatchOrder.newestFirst;
  bool _loaded = false;
  bool _scanning = false;
  bool _cleaning = false;
  Future<void>? _reloadInFlight;
  bool _reloadPending = false;
  bool _reloadRulesPending = false;
  int _seenRevision = -1;

  ViewMode _viewMode = ViewMode.list;
  _JobSort _sort = _JobSort.queue;
  bool _ascending = true;
  bool _showSearch = false;
  String _query = '';
  final _searchFocus = FocusNode();

  int get _total => _counts.values.fold(0, (a, b) => a + b);

  /// The loaded jobs after the search text and the chosen sort.
  List<SubtitleBatchJob> get _visibleJobs {
    final query = _query.trim().toLowerCase();
    final jobs = [
      for (final job in _jobs)
        if (query.isEmpty || job.path.toLowerCase().contains(query)) job,
    ];
    if (_sort == _JobSort.queue) {
      return _ascending ? jobs : jobs.reversed.toList();
    }
    int compare(SubtitleBatchJob a, SubtitleBatchJob b) => switch (_sort) {
      _JobSort.queue => 0,
      _JobSort.name => a.fileName.toLowerCase().compareTo(
        b.fileName.toLowerCase(),
      ),
      _JobSort.folder => a.folder.toLowerCase().compareTo(
        b.folder.toLowerCase(),
      ),
      _JobSort.status => _statusRank[a.status]!.compareTo(
        _statusRank[b.status]!,
      ),
      _JobSort.progress => _progressOf(a).compareTo(_progressOf(b)),
      _JobSort.modified => (a.fileModifiedAt ?? DateTime(1970)).compareTo(
        b.fileModifiedAt ?? DateTime(1970),
      ),
      _JobSort.added => a.createdAt.compareTo(b.createdAt),
      _JobSort.updated => a.updatedAt.compareTo(b.updatedAt),
    };
    // Ties keep the queue order, so equal statuses stay in processing order.
    final order = {for (var i = 0; i < jobs.length; i++) jobs[i].id: i};
    jobs.sort((a, b) {
      if (_sort == _JobSort.modified &&
          (a.fileModifiedAt == null) != (b.fileModifiedAt == null)) {
        return a.fileModifiedAt == null ? 1 : -1;
      }
      final result = compare(a, b);
      if (result != 0) return _ascending ? result : -result;
      return order[a.id]!.compareTo(order[b.id]!);
    });
    return jobs;
  }

  double _progressOf(SubtitleBatchJob job) =>
      _queue.liveProgress(job.id) ??
      (job.status == SubtitleBatchStatus.done ? 1 : job.progress);

  Future<void> _loadViewPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final view = ViewMode.values
          .where((m) => m.name == prefs.getString(_prefView))
          .firstOrNull;
      final sort = _JobSort.values
          .where((s) => s.name == prefs.getString(_prefSort))
          .firstOrNull;
      if (!mounted) return;
      setState(() {
        if (view != null && _viewModes.contains(view)) _viewMode = view;
        if (sort != null) _sort = sort;
        _ascending =
            prefs.getBool(_prefAscending) ?? (_sort != _JobSort.modified);
      });
    } catch (_) {
      // Defaults are fine.
    }
  }

  void _setViewMode(ViewMode mode) {
    if (!_viewModes.contains(mode)) return;
    setState(() => _viewMode = mode);
    unawaited(
      SharedPreferences.getInstance().then(
        (p) => p.setString(_prefView, mode.name),
      ),
    );
  }

  /// Picking the active key again flips the direction, like a column header.
  void _setSort(_JobSort sort) {
    setState(() {
      if (_sort == sort) {
        _ascending = !_ascending;
      } else {
        _sort = sort;
        _ascending =
            sort != _JobSort.updated &&
            sort != _JobSort.added &&
            sort != _JobSort.modified;
      }
    });
    unawaited(
      SharedPreferences.getInstance().then((p) async {
        await p.setString(_prefSort, _sort.name);
        await p.setBool(_prefAscending, _ascending);
      }),
    );
  }

  void _openSearch() {
    setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _closeSearch() => setState(() {
    _showSearch = false;
    _query = '';
  });

  /// Whole queue, for the status card.
  int _count(SubtitleBatchStatus status) => _counts[status] ?? 0;

  /// The rule the queue list is limited to; null shows every rule.
  int? _ruleFilter;
  Map<SubtitleBatchStatus, int> _listCounts = const {};
  Map<int, Map<SubtitleBatchStatus, int>> _ruleCounts = const {};

  /// The list's counts: the selected rule, or the whole queue.
  int _listCount(SubtitleBatchStatus status) => _listCounts[status] ?? 0;
  int get _listTotal => _listCounts.values.fold(0, (a, b) => a + b);

  SubtitleBatchRule? get _selectedRule =>
      _rules.where((r) => r.id == _ruleFilter).firstOrNull;

  void _selectRule(int? id) {
    setState(() {
      _ruleFilter = id;
      _filter = null;
    });
    unawaited(_reload());
  }

  @override
  void initState() {
    super.initState();
    if (!SubtitleBatchQueue.supported) return;
    _queue.addListener(_queueChanged);
    _queue.queueResources
      ..acquire()
      ..addListener(_resourcesChanged);
    _queue.ensureStarted();
    unawaited(_loadViewPreferences());
    _poll = Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => unawaited(_reload(rules: true)),
    );
    unawaited(_init());
  }

  void _resourcesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    final services = await (widget.services ?? SubtitleServices.load)();
    if (!mounted) return;
    _services = services;
    // A model may have been installed meanwhile, possibly in another window
    // whose change events this isolate never sees. A still-missing model
    // simply blocks the queue again on the next job.
    _queue.clearBlock();
    _modelsChanged = services.models.onInstalledModelsChanged.listen((_) {
      _queue.clearBlock();
      if (mounted) setState(() {});
    });
    await _reload(rules: true);
  }

  /// Progress ticks only repaint; job changes also reload the list.
  void _queueChanged() {
    if (!mounted) return;
    setState(() {});
    if (_queue.revision != _seenRevision) {
      _seenRevision = _queue.revision;
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _modelsChanged?.cancel();
    _queue.removeListener(_queueChanged);
    if (SubtitleBatchQueue.supported) {
      _queue.queueResources
        ..removeListener(_resourcesChanged)
        ..release();
    }
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _reload({bool rules = false}) {
    if (!mounted) return Future.value();
    _reloadPending = true;
    _reloadRulesPending = _reloadRulesPending || rules;
    return _reloadInFlight ??= _drainReloads();
  }

  Future<void> _drainReloads() async {
    try {
      while (mounted && _reloadPending) {
        _reloadPending = false;
        final rules = _reloadRulesPending || !_loaded;
        _reloadRulesPending = false;
        await _reloadOnce(rules: rules);
      }
    } finally {
      _reloadInFlight = null;
    }
  }

  Future<void> _reloadOnce({required bool rules}) async {
    try {
      final rule = _ruleFilter;
      final filter = _filter;
      final results = await Future.wait([
        _store.jobs(statuses: filter == null ? null : {filter}, ruleId: rule),
        _store.counts(),
        rule == null ? Future.value(null) : _store.counts(ruleId: rule),
        _store.ruleCounts(),
        _store.runRequested(),
        _store.pauseWhileWatching(),
        _store.runRule(),
        _store.parallelJobs(),
        _store.processingOrder(),
        if (rules || !_loaded) _store.rules(),
      ]);
      if (!mounted) return;
      if (rule != _ruleFilter || filter != _filter) {
        // A selection changed while SQLite was reading. Never paint rows
        // from an old scope, and retain any requested rules refresh.
        _reloadPending = true;
        _reloadRulesPending = _reloadRulesPending || rules;
        return;
      }
      setState(() {
        _jobs = results[0] as List<SubtitleBatchJob>;
        _counts = results[1] as Map<SubtitleBatchStatus, int>;
        _listCounts = results[2] as Map<SubtitleBatchStatus, int>? ?? _counts;
        _ruleCounts = results[3] as Map<int, Map<SubtitleBatchStatus, int>>;
        _runRequested = results[4] as bool;
        _pauseWhileWatching = results[5] as bool;
        _runRule = results[6] as int?;
        _parallelJobs = results[7] as int;
        _processingOrder = results[8] as SubtitleBatchOrder;
        if (results.length > 9) {
          _rules = results[9] as List<SubtitleBatchRule>;
          // The selected rule was deleted, maybe in another window.
          if (_ruleFilter != null && _selectedRule == null) {
            _ruleFilter = null;
            _filter = null;
            _reloadPending = true;
          }
        }
        _loaded = true;
      });
    } catch (e) {
      debugPrint('Subtitle queue screen: $e');
    }
  }

  Future<String> _appLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_language') ??
        LanguageController().currentLocale.languageCode;
  }

  // ------------------------------------------------------------ actions

  /// Start runs the focused scope: the selected rule, or every rule.
  /// While another scope runs, it switches to the focused one.
  Future<void> _toggleRun() async {
    if (_cleaning) return;
    _runningFocus
        ? await _queue.pause()
        : await _queue.start(ruleId: _ruleFilter);
    await _reload();
  }

  Future<void> _cleanGenerated() async {
    if (_cleaning) return;
    final l = AppLocalizations.of(context)!;
    if (_runRequested || _count(SubtitleBatchStatus.running) > 0) {
      AppToast.info(context, l.subtitleQueueCleanPause);
      return;
    }
    final scope = _ruleFilter;
    final ok = await showCbConfirmDialog(
      context: context,
      title: l.subtitleQueueCleanGenerated,
      message: l.subtitleQueueCleanConfirm(_scopeName(l, scope)),
      confirmLabel: l.subtitleQueueCleanGenerated,
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _cleaning = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final report = await SubtitleGeneratedCleanup(
        _store,
        _services!.cache,
        prefs,
      ).clean(ruleId: scope);
      _queue.notifyEnqueued();
      if (mounted) {
        AppToast.success(
          context,
          l.subtitleQueueCleanResult(
            report.cleaned,
            report.retained,
            report.failed,
          ),
        );
      }
    } catch (error) {
      if (mounted) AppToast.error(context, error.toString());
    } finally {
      if (mounted) setState(() => _cleaning = false);
      await _reload();
    }
  }

  Future<void> _showGeneratedModels(SubtitleBatchJob job) async {
    final metadata = await _store.generatedMetadata(job);
    if (!mounted) return;
    final l = AppLocalizations.of(context)!;
    final settings = metadata?.settings ?? job.settings;
    await showDialog<void>(
      context: context,
      barrierColor: context.cbColors.scrim,
      builder: (context) => CbDialog(
        title: l.subtitleQueueGeneratedModels,
        icon: PhosphorIconsLight.cpu,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.fileName),
            const SizedBox(height: CbSpacing.md),
            Text('${l.aiModelSpeech}: ${settings.speechModel}'),
            Text('${l.aiModelTranslation}: ${settings.translationModel}'),
            Text(
              '${l.language}: ${settings.sourceLanguage} → ${settings.targetLanguage}',
            ),
            if (metadata != null) Text(_time(metadata.generatedAt.toLocal())),
            if (metadata == null) Text(l.subtitleQueueLegacyModels),
          ],
        ),
        actions: [
          CbButton(
            label: l.close,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// The rule the queue runs; null runs every rule.
  int? _runRule;

  bool get _runningFocus => _runRequested && _runRule == _ruleFilter;

  String _scopeName(AppLocalizations l, int? ruleId) => ruleId == null
      ? l.subtitleQueueAllRules
      : _rules.where((r) => r.id == ruleId).firstOrNull?.name ??
            l.subtitleQueueAllRules;

  String _startLabel(AppLocalizations l) => _runningFocus
      ? l.subtitleQueuePause
      : _ruleFilter == null
      ? l.subtitleQueueStart
      : l.subtitleQueueStartRule(_scopeName(l, _ruleFilter));

  IconData get _startIcon =>
      _runningFocus ? PhosphorIconsLight.pause : PhosphorIconsLight.play;

  Future<void> _scan(Iterable<SubtitleBatchRule> rules) async {
    if (_scanning) return;
    final l = AppLocalizations.of(context)!;
    setState(() => _scanning = true);
    try {
      final language = await _appLanguage();
      var report = const SubtitleBatchScanReport();
      for (final rule in rules) {
        report += await _scanner.enqueueRule(rule, appLanguage: language);
      }
      _queue.notifyEnqueued();
      if (mounted) {
        AppToast.success(
          context,
          l.subtitleQueueScanResult(
            report.added,
            report.alreadyQueued,
            report.skippedExisting,
          ),
        );
      }
    } catch (e) {
      if (mounted) AppToast.error(context, e.toString());
    } finally {
      if (mounted) setState(() => _scanning = false);
      await _reload();
    }
  }

  Future<void> _editRule([SubtitleBatchRule? rule]) async {
    final services = _services;
    if (services == null) return;
    final l = AppLocalizations.of(context)!;
    final edited = await showSubtitleRuleDialog(
      context,
      rule:
          rule ??
          SubtitleBatchRule.fromPreferences(
            services.preferences,
            name: l.subtitleRuleDefaultName,
          ),
      models: services.models,
      isNew: rule == null,
    );
    if (edited == null) return;
    final saved = await _store.saveRule(edited);
    // Each rule owns its jobs: waiting ones follow the edited settings.
    if (rule != null) {
      await _queue.applyRule(saved, appLanguage: await _appLanguage());
    }
    await _reload(rules: true);
    // Saving queues the rule's videos right away, including new folders.
    if (mounted) await _scan([saved]);
  }

  Future<void> _deleteRule(SubtitleBatchRule rule) async {
    final l = AppLocalizations.of(context)!;
    final ok = await showCbConfirmDialog(
      context: context,
      title: l.delete,
      message: l.subtitleRuleDeleteConfirm(rule.name),
      confirmLabel: l.delete,
      destructive: true,
    );
    if (ok != true || rule.id == null || !mounted) return;
    try {
      await _queue.deleteRule(rule.id!);
      await _reload(rules: true);
    } catch (error) {
      if (mounted) AppToast.error(context, error.toString());
    }
  }

  Future<void> _setRuleEnabled(SubtitleBatchRule rule, bool enabled) async {
    await _store.saveRule(rule.copyWith(enabled: enabled));
    await _reload(rules: true);
  }

  Future<void> _addVideos() async {
    final l = AppLocalizations.of(context)!;
    if (_rules.isEmpty) {
      AppToast.info(context, l.subtitleQueueNeedRule);
      return;
    }
    final picked = await FilePicker.pickFiles(type: FileType.video);
    final paths = [for (final file in picked) ?file.path];
    if (paths.isEmpty || !mounted) return;
    var rule = _rules.first;
    if (_rules.length > 1) {
      final chosen = await _chooseRule(l);
      if (chosen == null) return;
      rule = chosen;
    }
    final report = await _scanner.enqueuePaths(
      paths,
      settings: rule.resolve(await _appLanguage()),
      ruleId: rule.id,
      ruleName: rule.name,
    );
    _queue.notifyEnqueued();
    if (mounted) {
      AppToast.success(
        context,
        l.subtitleQueueScanResult(
          report.added,
          report.alreadyQueued,
          report.skippedExisting,
        ),
      );
    }
    await _reload();
  }

  Future<SubtitleBatchRule?> _chooseRule(AppLocalizations l) {
    var selected = _rules.first;
    return showDialog<SubtitleBatchRule>(
      context: context,
      barrierColor: context.cbColors.scrim,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => CbDialog(
          title: l.subtitleQueueAddVideos,
          icon: PhosphorIconsLight.filePlus,
          content: CbSelect<SubtitleBatchRule>(
            label: l.subtitleQueueChooseRule,
            value: selected,
            expand: true,
            items: [
              for (final rule in _rules)
                CbSelectItem(value: rule, label: rule.name),
            ],
            onChanged: (rule) => setDialogState(() => selected = rule),
          ),
          actions: [
            CbButton(
              onPressed: () => Navigator.of(context).pop(),
              label: l.cancel,
              variant: CbButtonVariant.ghost,
            ),
            CbButton(
              onPressed: () => Navigator.of(context).pop(selected),
              label: l.add,
              variant: CbButtonVariant.primary,
            ),
          ],
        ),
      ),
    );
  }

  /// The failure of a failed job, or of a waiting job that is retried
  /// after a transient failure.
  SubtitleBatchFailureKind? _failureOf(SubtitleBatchJob job) {
    final message = job.message;
    if (message == null || message.isEmpty) return null;
    return switch (job.status) {
      SubtitleBatchStatus.failed => SubtitleBatchFailure.kind(message),
      SubtitleBatchStatus.pending || SubtitleBatchStatus.running
          when SubtitleBatchFailure.transient(message) =>
        SubtitleBatchFailure.kind(message),
      _ => null,
    };
  }

  /// One line about a failure: what went wrong, or the coming retry.
  String? _failureLine(AppLocalizations l, SubtitleBatchJob job) {
    final kind = _failureOf(job);
    if (kind == null) return null;
    final title = l.subtitleBatchFailureTitle(kind.name);
    if (job.status == SubtitleBatchStatus.failed) return title;
    final attempt = _queue.attemptsOf(job);
    if (attempt == 0) return title;
    final retry = l.subtitleQueueRetrying(
      attempt + 1,
      SubtitleBatchFailure.maxAttempts,
    );
    return '$title · $retry';
  }

  Future<void> _showError(SubtitleBatchJob job) {
    final l = AppLocalizations.of(context)!;
    final c = context.cbColors;
    final kind = _failureOf(job) ?? SubtitleBatchFailureKind.unknown;
    final detail = SubtitleBatchFailure.detail(job.message);
    return showDialog<void>(
      context: context,
      barrierColor: c.scrim,
      builder: (context) => CbDialog(
        title: l.subtitleBatchFailureTitle(kind.name),
        icon: PhosphorIconsLight.warningCircle,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.subtitleBatchFailureHint(kind.name),
              style: CbTypography.body.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: CbSpacing.lg),
            Text(
              job.fileName,
              style: CbTypography.label.copyWith(color: c.textPrimary),
            ),
            SelectableText(
              job.folder,
              style: CbTypography.caption.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: CbSpacing.lg),
            Text(
              l.subtitleQueueTechnicalDetails,
              style: CbTypography.labelSm.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: CbSpacing.xs),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CbSpacing.md),
              decoration: BoxDecoration(
                color: c.fillSubtle,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                key: const ValueKey('subtitle-error-detail'),
                detail.isEmpty ? '-' : detail,
                style: CbTypography.bodySm.copyWith(
                  color: c.textSecondary,
                  fontFamily: 'Consolas',
                  fontFamilyFallback: const ['Menlo', 'DejaVu Sans Mono'],
                ),
              ),
            ),
          ],
        ),
        actions: [
          CbButton(
            onPressed: () {
              final text = [job.path, ?job.message].join('\n');
              unawaited(Clipboard.setData(ClipboardData(text: text)));
              AppToast.success(context, l.copied);
            },
            icon: PhosphorIconsLight.copy,
            label: l.copy,
            variant: CbButtonVariant.ghost,
          ),
          CbButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _queue.retry([job.id]);
              await _reload();
            },
            icon: PhosphorIconsLight.arrowClockwise,
            label: l.retry,
            variant: CbButtonVariant.secondary,
          ),
          CbButton(
            onPressed: () => Navigator.of(context).pop(),
            label: l.close,
            variant: CbButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  void _openFolder(SubtitleBatchJob job, {bool subtitle = false}) {
    final target = subtitle ? (job.outputPath ?? job.path) : job.path;
    context.read<TabManagerBloc>().add(
      AddTab(
        path: pathlib.dirname(target),
        name: pathlib.basename(pathlib.dirname(target)),
        highlightedFileName: pathlib.basename(target),
      ),
    );
  }

  void _openSubtitleSettings() {
    TabNavigator.updateTabPath(context, widget.tabId, kSettingsPath);
  }

  Future<void> _showMoreMenu(Offset position) {
    final l = AppLocalizations.of(context)!;
    // Bulk actions follow the list: the selected rule, or every rule.
    final failed =
        _listCount(SubtitleBatchStatus.failed) +
        _listCount(SubtitleBatchStatus.cancelled);
    final finished =
        _listCount(SubtitleBatchStatus.done) +
        _listCount(SubtitleBatchStatus.skipped) +
        _listCount(SubtitleBatchStatus.cancelled);
    final compact = _compactToolbar;
    IconData viewIcon(ViewMode mode) => switch (mode) {
      ViewMode.grid => PhosphorIconsLight.squaresFour,
      ViewMode.details => PhosphorIconsLight.listDashes,
      ViewMode.tiles => PhosphorIconsLight.gridNine,
      _ => PhosphorIconsLight.list,
    };
    String viewLabel(ViewMode mode) => switch (mode) {
      ViewMode.grid => l.viewModeGrid,
      ViewMode.details => l.viewModeDetails,
      ViewMode.tiles => l.viewModeTiles,
      _ => l.viewModeList,
    };
    return showContextMenuPopup(
      context: context,
      globalPosition: position,
      sections: [
        if (compact)
          ContextMenuSection(
            actions: [
              ContextMenuAction(
                id: 'subtitle-add-videos',
                label: l.subtitleQueueAddVideos,
                icon: PhosphorIconsLight.filePlus,
                onSelected: (_) => _addVideos(),
              ),
              ContextMenuAction(
                id: 'subtitle-new-rule',
                label: l.subtitleRuleNew,
                icon: PhosphorIconsLight.plus,
                onSelected: (_) => _editRule(),
              ),
              ContextMenuAction(
                id: 'subtitle-sort',
                label: l.sortByTooltip,
                icon: PhosphorIconsLight.sortAscending,
                childSections: [
                  ContextMenuSection(
                    actions: [
                      for (final sort in _JobSort.values)
                        ContextMenuAction(
                          id: 'subtitle-sort-${sort.name}',
                          label: _sortLabel(l, sort),
                          icon: _sort != sort
                              ? PhosphorIconsLight.sortAscending
                              : _ascending
                              ? PhosphorIconsLight.arrowUp
                              : PhosphorIconsLight.arrowDown,
                          isChecked: _sort == sort,
                          onSelected: (_) => _setSort(sort),
                        ),
                    ],
                  ),
                ],
              ),
              ContextMenuAction(
                id: 'subtitle-view-mode',
                label: l.viewModeTooltip,
                icon: PhosphorIconsLight.eye,
                childSections: [
                  ContextMenuSection(
                    actions: [
                      for (final mode in _viewModes)
                        ContextMenuAction(
                          id: 'subtitle-view-${mode.name}',
                          label: viewLabel(mode),
                          icon: viewIcon(mode),
                          isChecked: _viewMode == mode,
                          onSelected: (_) => _setViewMode(mode),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ContextMenuSection(
          actions: [
            ContextMenuAction(
              id: 'subtitle-scan-all',
              label: l.subtitleQueueScanAll,
              icon: PhosphorIconsLight.magnifyingGlass,
              isEnabled: !_scanning && _rules.any((r) => r.enabled),
              onSelected: (_) => _scan(_rules.where((r) => r.enabled)),
            ),
            ContextMenuAction(
              id: 'subtitle-retry-failed',
              label: l.subtitleQueueRetryFailed,
              icon: PhosphorIconsLight.arrowClockwise,
              isEnabled: failed > 0,
              onSelected: (_) async {
                await _queue.retryFailed(ruleId: _ruleFilter);
                await _reload();
              },
            ),
            ContextMenuAction(
              id: 'subtitle-clear-finished',
              label: l.subtitleQueueClearFinished,
              icon: PhosphorIconsLight.broom,
              isEnabled: finished > 0,
              onSelected: (_) async {
                await _queue.clearFinished(ruleId: _ruleFilter);
                await _reload();
              },
            ),
            if (compact)
              ContextMenuAction(
                id: 'subtitle-clean-generated',
                label: l.subtitleQueueCleanGenerated,
                icon: PhosphorIconsLight.trash,
                isEnabled:
                    !_cleaning &&
                    _services != null &&
                    _listCount(SubtitleBatchStatus.done) > 0,
                onSelected: (_) => _cleanGenerated(),
              ),
          ],
        ),
        ContextMenuSection(
          actions: [
            ContextMenuAction(
              id: 'subtitle-pause-while-watching',
              label: l.subtitleQueuePauseWhileWatching,
              icon: PhosphorIconsLight.playCircle,
              isChecked: _pauseWhileWatching,
              onSelected: (_) async {
                await _store.setPauseWhileWatching(!_pauseWhileWatching);
                _queue.schedule();
                await _reload();
              },
            ),
            ContextMenuAction(
              id: 'subtitle-processing-order',
              label: l.subtitleQueueProcessingOrder,
              icon: PhosphorIconsLight.sortAscending,
              childSections: [
                ContextMenuSection(
                  title: l.subtitleQueueProcessingOrderHint,
                  actions: [
                    for (final order in SubtitleBatchOrder.values)
                      ContextMenuAction(
                        id: 'subtitle-order-${order.name}',
                        label: order == SubtitleBatchOrder.oldestFirst
                            ? l.subtitleQueueOldestFirst
                            : l.subtitleQueueNewestFirst,
                        icon: order == SubtitleBatchOrder.oldestFirst
                            ? PhosphorIconsLight.sortAscending
                            : PhosphorIconsLight.sortDescending,
                        isChecked: _processingOrder == order,
                        onSelected: (_) async {
                          await _store.setProcessingOrder(order);
                          _queue.schedule();
                          await _reload();
                        },
                      ),
                  ],
                ),
              ],
            ),
            ContextMenuAction(
              id: 'subtitle-parallel-jobs',
              label: l.subtitleQueueParallelJobs,
              icon: PhosphorIconsLight.stack,
              childSections: [
                ContextMenuSection(
                  actions: [
                    ContextMenuAction(
                      id: 'subtitle-parallel-auto',
                      label: l.subtitleQueueParallelAuto,
                      icon: PhosphorIconsLight.magicWand,
                      isChecked:
                          _parallelJobs == SubtitleBatchStore.autoParallelJobs,
                      onSelected: (_) async {
                        await _queue.setParallelJobs(
                          SubtitleBatchStore.autoParallelJobs,
                        );
                        await _reload();
                      },
                    ),
                  ],
                ),
                ContextMenuSection(
                  title: l.subtitleQueueParallelHint,
                  actions: [
                    for (
                      var count = 1;
                      count <= SubtitleBatchStore.maxParallelJobs;
                      count++
                    )
                      ContextMenuAction(
                        id: 'subtitle-parallel-$count',
                        label: l.subtitleQueueParallelOption(count),
                        icon: PhosphorIconsLight.stack,
                        isChecked: _parallelJobs == count,
                        onSelected: (_) async {
                          await _queue.setParallelJobs(count);
                          await _reload();
                        },
                      ),
                  ],
                ),
              ],
            ),
            ContextMenuAction(
              id: 'subtitle-settings',
              label: l.aiSubtitleManage,
              icon: PhosphorIconsLight.slidersHorizontal,
              onSelected: (_) => _openSubtitleSettings(),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showJobMenu(SubtitleBatchJob job, Offset position) {
    final l = AppLocalizations.of(context)!;
    final active =
        job.status == SubtitleBatchStatus.pending ||
        job.status == SubtitleBatchStatus.running;
    return showContextMenuPopup(
      context: context,
      globalPosition: position,
      sections: [
        ContextMenuSection(
          actions: [
            if (_failureOf(job) != null)
              ContextMenuAction(
                id: 'subtitle-job-error',
                label: l.subtitleQueueErrorDetails,
                icon: PhosphorIconsLight.info,
                onSelected: (_) => _showError(job),
              ),
            ContextMenuAction(
              id: 'subtitle-job-folder',
              label: l.openContainingFolder,
              icon: PhosphorIconsLight.folderOpen,
              onSelected: (_) => _openFolder(job),
            ),
            if (job.outputPath != null && job.outputPath != job.path)
              ContextMenuAction(
                id: 'subtitle-job-output-folder',
                label: '${l.openContainingFolder} (SRT)',
                icon: PhosphorIconsLight.subtitles,
                onSelected: (_) => _openFolder(job, subtitle: true),
              ),
            if (job.status == SubtitleBatchStatus.done)
              ContextMenuAction(
                id: 'subtitle-job-generated-models',
                label: l.subtitleQueueGeneratedModels,
                icon: PhosphorIconsLight.cpu,
                onSelected: (_) => _showGeneratedModels(job),
              ),
            if (active)
              ContextMenuAction(
                id: 'subtitle-job-cancel',
                label: l.cancel,
                icon: PhosphorIconsLight.stop,
                onSelected: (_) async {
                  await _queue.cancel([job.id]);
                  await _reload();
                },
              )
            else
              ContextMenuAction(
                id: 'subtitle-job-retry',
                label: l.retry,
                icon: PhosphorIconsLight.arrowClockwise,
                onSelected: (_) async {
                  await _queue.retry([job.id]);
                  await _reload();
                },
              ),
          ],
        ),
        ContextMenuSection(
          actions: [
            ContextMenuAction(
              id: 'subtitle-job-remove',
              label: l.remove,
              icon: PhosphorIconsLight.x,
              isDestructive: true,
              onSelected: (_) async {
                await _queue.remove([job.id]);
                await _reload();
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showRuleMenu(SubtitleBatchRule rule, Offset position) {
    final l = AppLocalizations.of(context)!;
    return showContextMenuPopup(
      context: context,
      globalPosition: position,
      sections: [
        ContextMenuSection(
          actions: [
            ContextMenuAction(
              id: 'subtitle-rule-scan',
              label: l.subtitleRuleScanNow,
              icon: PhosphorIconsLight.magnifyingGlass,
              isEnabled: !_scanning,
              onSelected: (_) => _scan([rule]),
            ),
            ContextMenuAction(
              id: 'subtitle-rule-edit',
              label: l.edit,
              icon: PhosphorIconsLight.pencilSimple,
              onSelected: (_) => _editRule(rule),
            ),
            ContextMenuAction(
              id: 'subtitle-rule-enabled',
              label: l.subtitleRuleEnabled,
              icon: PhosphorIconsLight.checkSquare,
              isChecked: rule.enabled,
              onSelected: (_) => _setRuleEnabled(rule, !rule.enabled),
            ),
          ],
        ),
        ContextMenuSection(
          actions: [
            ContextMenuAction(
              id: 'subtitle-rule-remove',
              label: l.delete,
              icon: PhosphorIconsLight.trash,
              isDestructive: true,
              onSelected: (_) => _deleteRule(rule),
            ),
          ],
        ),
      ],
    );
  }

  Offset _below(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.localToGlobal(Offset(0, box.size.height));
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return LibraryHubScaffold(
      tabId: widget.tabId,
      path: kSubtitleQueuePath,
      title: l.subtitleQueueTitle,
      icon: PhosphorIconsLight.subtitles,
      onRefresh: () => unawaited(_reload(rules: true)),
      showRefreshAction: false,
      viewMode: _viewMode,
      onSearch: SubtitleBatchQueue.supported ? _openSearch : null,
      showSearchBar: _showSearch,
      searchBar: tab_components.SearchBar(
        key: const ValueKey('subtitle-queue-search'),
        currentPath: kSubtitleQueuePath,
        tabId: widget.tabId,
        initialQuery: _query,
        focusNode: _searchFocus,
        hintText: l.subtitleQueueSearchHint,
        onCloseSearch: _closeSearch,
        showTagSearch: false,
        showGlobalSearchToggle: false,
        showTipsButton: false,
        showRegexToggle: false,
        onQueryChanged: (query) => setState(() => _query = query),
        onSearch: (query) => setState(() => _query = query),
        onSearchWithOptions: (query, _) => setState(() => _query = query),
        onClearSearch: () => setState(() => _query = ''),
      ),
      onEscape: () {
        if (_showSearch) {
          _closeSearch();
        } else if (_filter != null) {
          setState(() => _filter = null);
          unawaited(_reload());
        }
      },
      actions: SubtitleBatchQueue.supported ? _toolbar(l) : const [],
      body: !SubtitleBatchQueue.supported
          ? _message(l.subtitleQueueDesktopOnly, PhosphorIconsLight.desktop)
          : Stack(
              children: [
                Positioned.fill(
                  child: _loaded ? _body(l) : const SizedBox.shrink(),
                ),
                // Same slim bar as the file lists, along the top edge.
                if (!_loaded || _scanning)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SlimProgressBar(
                      key: ValueKey('subtitle-queue-loading'),
                    ),
                  ),
              ],
            ),
    );
  }

  String _sortLabel(AppLocalizations l, _JobSort sort) => switch (sort) {
    _JobSort.queue => l.subtitleQueueSortQueue,
    _JobSort.name => l.columnName,
    _JobSort.folder => l.folder,
    _JobSort.status => l.subtitleQueueColumnStatus,
    _JobSort.progress => l.subtitleQueueColumnProgress,
    _JobSort.modified => l.columnDateModified,
    _JobSort.added => l.subtitleQueueColumnAdded,
    _JobSort.updated => l.subtitleQueueColumnUpdated,
  };

  Widget _sortMenu(AppLocalizations l) => PopupMenuButton<_JobSort>(
    popUpAnimationStyle: CbPopoverTransition.menuStyleOf(context),
    key: const ValueKey('shared-sort-menu'),
    icon: const Icon(PhosphorIconsLight.sortAscending),
    tooltip: l.sortByTooltip,
    offset: const Offset(0, 50),
    onSelected: _setSort,
    itemBuilder: (context) {
      final primary = Theme.of(context).colorScheme.primary;
      return [
        for (final sort in _JobSort.values)
          PopupMenuItem<_JobSort>(
            key: ValueKey('subtitle-sort-${sort.name}'),
            value: sort,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _sortLabel(l, sort),
                    style: TextStyle(
                      fontWeight: _sort == sort
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: _sort == sort ? primary : null,
                    ),
                  ),
                ),
                if (_sort == sort)
                  Icon(
                    _ascending
                        ? PhosphorIconsLight.arrowUp
                        : PhosphorIconsLight.arrowDown,
                    size: 18,
                    color: primary,
                  ),
              ],
            ),
          ),
      ];
    },
  );

  /// Narrow windows keep the address bar readable: sort, view mode and the
  /// create commands move into the more menu.
  bool get _compactToolbar => MediaQuery.sizeOf(context).width < 760;

  List<Widget> _toolbar(AppLocalizations l) => _compactToolbar
      ? [
          CbButton.icon(
            key: const ValueKey('shared-search-action'),
            icon: _showSearch
                ? PhosphorIconsLight.x
                : PhosphorIconsLight.magnifyingGlass,
            tooltip: _showSearch ? l.close : l.searchTooltip,
            onPressed: () => _showSearch ? _closeSearch() : _openSearch(),
          ),
          CbButton.icon(
            key: const ValueKey('subtitle-queue-toggle'),
            icon: _startIcon,
            tooltip: _startLabel(l),
            onPressed: () => unawaited(_toggleRun()),
          ),
          _moreButton(l),
        ]
      : _fullToolbar(l);

  Widget _moreButton(AppLocalizations l) => Builder(
    builder: (buttonContext) => CbButton.icon(
      key: const ValueKey('subtitle-queue-more'),
      icon: PhosphorIconsLight.dotsThreeVertical,
      tooltip: l.moreOptions,
      onPressed: () => unawaited(_showMoreMenu(_below(buttonContext))),
    ),
  );

  List<Widget> _fullToolbar(AppLocalizations l) => [
    ...SharedActionBar.buildCommonActions(
      context: context,
      onSearchPressed: () => _showSearch ? _closeSearch() : _openSearch(),
      isSearchActive: _showSearch,
      // The menu above replaces the file sort options.
      onSortOptionSelected: (_) {},
      currentSortOption: SortOption.nameAsc,
      sortAction: _sortMenu(l),
      viewMode: _viewMode,
      onViewModeToggled: () => _setViewMode(
        _viewMode == ViewMode.list ? ViewMode.details : ViewMode.list,
      ),
      onViewModeSelected: _setViewMode,
      allowedViewModes: _viewModes,
      onRefresh: () => unawaited(_reload(rules: true)),
      onSelectionModeToggled: () {},
      showMoreOptions: false,
    ),
    CbButton.icon(
      key: const ValueKey('subtitle-queue-toggle'),
      icon: _startIcon,
      tooltip: _startLabel(l),
      onPressed: () => unawaited(_toggleRun()),
    ),
    CbButton.icon(
      key: const ValueKey('subtitle-queue-add-videos'),
      icon: PhosphorIconsLight.filePlus,
      tooltip: l.subtitleQueueAddVideos,
      onPressed: () => unawaited(_addVideos()),
    ),
    CbButton.icon(
      key: const ValueKey('subtitle-rule-new'),
      icon: PhosphorIconsLight.plus,
      tooltip: l.subtitleRuleNew,
      onPressed: () => unawaited(_editRule()),
    ),
    CbButton.icon(
      key: const ValueKey('subtitle-queue-clean-generated'),
      icon: PhosphorIconsLight.trash,
      tooltip: l.subtitleQueueCleanGenerated,
      loading: _cleaning,
      onPressed:
          _cleaning ||
              _services == null ||
              _listCount(SubtitleBatchStatus.done) == 0
          ? null
          : () => unawaited(_cleanGenerated()),
    ),
    _moreButton(l),
  ];

  Widget _body(AppLocalizations l) {
    final firstRun = _rules.isEmpty && _total == 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Side-by-side panels scroll on their own and need room below the
        // status card; a short window scrolls the whole page instead, so
        // nothing is ever pushed past the bottom edge.
        final split =
            constraints.maxWidth >= 920 &&
            constraints.maxHeight >= (firstRun ? 600 : 480);
        final status = Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: firstRun ? _guideCard(l) : _statusCard(l),
        );
        if (!split) {
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: status),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: _rulesSection(l, scrollable: false),
                ),
              ),
              ..._queueSlivers(l),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            status,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 340,
                      child: _rulesSection(l, scrollable: true),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _panel(
                        padding: EdgeInsets.zero,
                        child: CustomScrollView(
                          slivers: _queueSlivers(l, inPanel: true),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------- shared look

  /// Translucent surface, as the media hub cards use on the desktop glass.
  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: light
            ? theme.colorScheme.surface.withValues(alpha: _desktop ? .46 : 1)
            : theme.colorScheme.surfaceContainerHigh.withValues(
                alpha: _desktop ? .52 : 1,
              ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String title, {int? count, Widget? trailing}) {
    final c = context.cbColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: CbSpacing.sm),
      child: Row(
        children: [
          Text(
            title,
            style: CbTypography.headingSm.copyWith(color: c.textPrimary),
          ),
          if (count != null) ...[
            const SizedBox(width: CbSpacing.sm),
            Text(
              '$count',
              style: CbTypography.labelSm.copyWith(color: c.textTertiary),
            ),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }

  Widget _message(String text, IconData icon) {
    final c = context.cbColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CbSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: c.iconSubtle),
            const SizedBox(height: CbSpacing.md),
            Text(
              text,
              textAlign: TextAlign.center,
              style: CbTypography.body.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- status card

  (String, Color, IconData) _stateLook(AppLocalizations l) {
    final c = context.cbColors;
    final state = _runRequested ? _queue.state : SubtitleBatchQueueState.paused;
    return switch (state) {
      SubtitleBatchQueueState.paused => (
        l.subtitleQueueStatePaused,
        c.textSecondary,
        PhosphorIconsLight.pauseCircle,
      ),
      SubtitleBatchQueueState.idle => (
        l.subtitleQueueStateIdle,
        c.status.success,
        PhosphorIconsLight.checkCircle,
      ),
      SubtitleBatchQueueState.running => (
        l.subtitleQueueStateRunning,
        c.accent.base,
        PhosphorIconsLight.waveform,
      ),
      SubtitleBatchQueueState.waitingForPlayback => (
        l.subtitleQueueStateWatching,
        c.status.warning,
        PhosphorIconsLight.playCircle,
      ),
      SubtitleBatchQueueState.blocked => (
        l.subtitleQueueStateBlocked(_queue.blockedModel ?? ''),
        c.status.danger,
        PhosphorIconsLight.warningCircle,
      ),
      SubtitleBatchQueueState.otherWindow => (
        l.subtitleQueueStateOtherWindow,
        c.status.info,
        PhosphorIconsLight.appWindow,
      ),
    };
  }

  Widget _heroCard({required Widget child}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final light = theme.brightness == Brightness.light;
    final alpha = _desktop ? .44 : 1.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: light
            ? null
            : cs.surfaceContainerHigh.withValues(alpha: _desktop ? .52 : 1),
        gradient: light
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    cs.primary.withValues(alpha: .09),
                    cs.surfaceContainerHigh,
                  ).withValues(alpha: alpha),
                  Color.alphaBlend(
                    cs.primary.withValues(alpha: .05),
                    cs.surfaceContainer,
                  ).withValues(alpha: alpha),
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }

  Widget _statusCard(AppLocalizations l) {
    final c = context.cbColors;
    final (label, color, icon) = _stateLook(l);
    // Another window's runner: show its jobs from the loaded rows. Twins in
    // other rules are one generation, so count path + settings once.
    var active = _queue.activeJobs;
    if (active.isEmpty) {
      final seen = <String>{};
      active = [
        for (final job in _jobs)
          if (job.status == SubtitleBatchStatus.running &&
              seen.add('${job.path}\n${job.settings.signature}'))
            job,
      ];
    }
    final running = active.isNotEmpty;
    final progress = running
        ? active.map(_progressOf).reduce((a, b) => a + b) / active.length
        : 0.0;
    final current = active.firstOrNull;
    final scope = _runRequested ? _runRule : _ruleFilter;
    final waiting = scope == null
        ? _count(SubtitleBatchStatus.pending)
        : _ruleCounts[scope]?[SubtitleBatchStatus.pending] ?? 0;
    final detail = [
      active.length > 1
          ? '${l.subtitleQueueRunningCount(active.length)} · '
                '${(progress * 100).floor()}%'
          : current != null
          ? '${current.fileName} · ${(progress * 100).floor()}%'
          : waiting > 0
          ? l.subtitleQueueWaitingCount(waiting)
          : l.subtitleQueueAllDone,
      if (_runRequested) l.subtitleQueueRunScope(_scopeName(l, _runRule)),
    ].join(' · ');
    final resources = _resourceStrip(l);
    final blocked =
        _runRequested && _queue.state == SubtitleBatchQueueState.blocked;
    final counters = Wrap(
      spacing: CbSpacing.sm,
      runSpacing: CbSpacing.sm,
      children: [
        _counter(
          _count(SubtitleBatchStatus.pending) +
              _count(SubtitleBatchStatus.running),
          l.subtitleQueueStatusPending,
          c.textPrimary,
        ),
        _counter(
          _count(SubtitleBatchStatus.done),
          l.subtitleQueueStatusDone,
          c.status.success,
        ),
        if (_count(SubtitleBatchStatus.failed) > 0)
          _counter(
            _count(SubtitleBatchStatus.failed),
            l.subtitleQueueStatusFailed,
            c.status.danger,
          ),
      ],
    );
    final button = blocked
        ? CbButton(
            onPressed: _openSubtitleSettings,
            icon: PhosphorIconsLight.slidersHorizontal,
            label: l.aiSubtitleManage,
            variant: CbButtonVariant.primary,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Another rule is running: pausing it stays one click away.
              if (_runRequested && !_runningFocus) ...[
                CbButton.icon(
                  key: const ValueKey('subtitle-queue-pause-other'),
                  icon: PhosphorIconsLight.pause,
                  tooltip: l.subtitleQueuePause,
                  onPressed: () async {
                    await _queue.pause();
                    await _reload();
                  },
                ),
                const SizedBox(width: CbSpacing.xs),
              ],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: CbButton(
                  key: const ValueKey('subtitle-queue-start'),
                  onPressed: () => unawaited(_toggleRun()),
                  icon: _startIcon,
                  label: _startLabel(l),
                  variant: _runningFocus
                      ? CbButtonVariant.secondary
                      : CbButtonVariant.primary,
                ),
              ),
            ],
          );
    final summary = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: CbSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                key: ValueKey('subtitle-queue-state:${_queue.state.name}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: CbTypography.headingMd.copyWith(color: c.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CbTypography.body.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
    return _heroCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 640;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide)
                Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: CbSpacing.lg),
                    counters,
                    const SizedBox(width: CbSpacing.lg),
                    button,
                  ],
                )
              else ...[
                summary,
                const SizedBox(height: CbSpacing.md),
                Row(
                  children: [
                    Expanded(child: counters),
                    button,
                  ],
                ),
              ],
              if (running) ...[
                const SizedBox(height: CbSpacing.md),
                ClipRRect(
                  borderRadius: BorderRadius.circular(CbRadii.full),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                    color: c.accent.base,
                    backgroundColor: c.accent.tint,
                  ),
                ),
              ],
              if (resources != null) ...[
                const SizedBox(height: CbSpacing.md),
                resources,
              ],
            ],
          );
        },
      ),
    );
  }

  static String _gb(int bytes) => (bytes / (1 << 30)).toStringAsFixed(1);

  /// Load attributable only to queue inference children. Global machine load
  /// stays separate for the automatic concurrency controller.
  Widget? _resourceStrip(AppLocalizations l) {
    final monitor = _queue.queueResources;
    final auto = _parallelJobs == SubtitleBatchStore.autoParallelJobs;
    if (!monitor.supported && !auto) return null;
    final c = context.cbColors;
    final sample = monitor.latest;
    final meters = <Widget>[
      if (auto && _runRequested)
        Tooltip(
          message: l.subtitleQueueAutoReason(_queue.autoScaler.reason.name),
          child: Container(
            key: const ValueKey('subtitle-queue-auto'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.accent.tint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsLight.magicWand,
                  size: 14,
                  color: c.accent.text,
                ),
                const SizedBox(width: 6),
                Text(
                  [
                    l.subtitleQueueAutoLimit(_queue.parallelLimit),
                    l.subtitleQueueAutoReason(_queue.autoScaler.reason.name),
                  ].where((t) => t.isNotEmpty).join(' · '),
                  style: CbTypography.labelSm.copyWith(color: c.accent.text),
                ),
              ],
            ),
          ),
        ),
      if (monitor.supported) ...[
        _meter('CPU', sample?.cpu, _percent(sample?.cpu)),
        _meter(
          'RAM',
          _share(sample?.processRamUsed, sample?.ramTotal),
          _amount(sample?.processRamUsed, sample?.ramTotal),
        ),
        if (sample == null || sample.gpu != null)
          _meter('GPU', sample?.gpu, _percent(sample?.gpu)),
        if (sample == null || sample.vramTotal != null)
          _meter(
            'VRAM',
            _share(sample?.vramUsed, sample?.vramTotal),
            _amount(sample?.vramUsed, sample?.vramTotal),
          ),
        if (sample == null || sample.ioBytesPerSecond != null)
          _meter(
            'I/O',
            null,
            sample?.ioBytesPerSecond == null
                ? '—'
                : '${(sample!.ioBytesPerSecond! / (1 << 20)).toStringAsFixed(1)} MB/s',
            showBar: false,
          ),
      ],
    ];
    if (meters.isEmpty) return null;
    return Column(
      key: const ValueKey('subtitle-queue-resources'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.subtitleQueueResources,
          style: CbTypography.labelSm.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: CbSpacing.sm),
        Wrap(
          spacing: CbSpacing.sm,
          runSpacing: CbSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: meters,
        ),
      ],
    );
  }

  static String _percent(double? value) =>
      value == null ? '—' : '${(value * 100).round()}%';

  static double? _share(int? used, int? total) =>
      used == null || total == null || total <= 0 ? null : used / total;

  static String _amount(int? used, int? total) =>
      used == null || total == null ? '—' : '${_gb(used)}/${_gb(total)} GB';

  Widget _meter(
    String label,
    double? load,
    String value, {
    bool showBar = true,
  }) {
    final c = context.cbColors;
    final theme = Theme.of(context);
    final tone = load == null
        ? c.textTertiary
        : load >= .9
        ? c.status.danger
        : load >= .75
        ? c.status.warning
        : c.status.success;
    return Container(
      width: 148,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CbTypography.labelSm.copyWith(color: c.textSecondary),
                ),
              ),
              Text(
                value,
                style: CbTypography.labelSm.copyWith(color: c.textPrimary),
              ),
            ],
          ),
          if (showBar) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(CbRadii.full),
              child: LinearProgressIndicator(
                value: (load ?? 0).clamp(0.0, 1.0),
                minHeight: 3,
                color: tone,
                backgroundColor: c.fillSubtle,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _counter(int value, String label, Color color) {
    final c = context.cbColors;
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('$value', style: CbTypography.headingMd.copyWith(color: color)),
          Text(
            label,
            style: CbTypography.caption.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _guideCard(AppLocalizations l) {
    final c = context.cbColors;
    Widget step(int n, String text) => Padding(
      padding: const EdgeInsets.only(top: CbSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accent.tint,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: CbTypography.labelSm.copyWith(color: c.accent.text),
            ),
          ),
          const SizedBox(width: CbSpacing.md),
          Expanded(
            child: Text(
              text,
              style: CbTypography.body.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
    return _heroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsLight.subtitles,
                size: 30,
                color: c.accent.base,
              ),
              const SizedBox(width: CbSpacing.lg),
              Expanded(
                child: Text(
                  l.subtitleQueueGuideTitle,
                  style: CbTypography.headingLg.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: CbSpacing.sm),
          step(1, l.subtitleQueueGuideStep1),
          step(2, l.subtitleQueueGuideStep2),
          step(3, l.subtitleQueueGuideStep3),
          const SizedBox(height: CbSpacing.lg),
          CbButton(
            key: const ValueKey('subtitle-guide-new-rule'),
            onPressed: () => unawaited(_editRule()),
            icon: PhosphorIconsLight.plus,
            label: l.subtitleRuleNew,
            variant: CbButtonVariant.primary,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- rules

  Widget _rulesSection(AppLocalizations l, {required bool scrollable}) {
    final header = _sectionHeader(
      l.subtitleQueueTabRules,
      count: _rules.length,
      trailing: CbButton.icon(
        icon: PhosphorIconsLight.plus,
        tooltip: l.subtitleRuleNew,
        size: CbButtonSize.sm,
        onPressed: () => unawaited(_editRule()),
      ),
    );
    final tiles = [for (final rule in _rules) _ruleTile(l, rule)];
    final empty = Padding(
      padding: const EdgeInsets.symmetric(vertical: CbSpacing.md),
      child: Text(
        l.subtitleRuleEmpty,
        style: CbTypography.bodySm.copyWith(
          color: context.cbColors.textSecondary,
        ),
      ),
    );
    return _panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
      child: scrollable
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Expanded(
                  child: _rules.isEmpty
                      ? Align(alignment: Alignment.topLeft, child: empty)
                      : ListView(children: tiles),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header, if (_rules.isEmpty) empty, ...tiles],
            ),
    );
  }

  String _language(AppLocalizations l, String code, {bool target = false}) {
    if (code == 'auto') return l.subtitleRuleAutoDetect;
    if (code == SubtitlePreferences.followApp) return l.subtitleRuleFollowApp;
    return (target ? subtitleTargetLanguages : subtitleSourceLanguages)[code] ??
        code;
  }

  Widget _ruleTile(AppLocalizations l, SubtitleBatchRule rule) {
    final c = context.cbColors;
    final sources = [
      ...rule.folders.map(pathlib.basename),
      if (rule.libraryIds.isNotEmpty)
        '${l.videoLibrary} ×${rule.libraryIds.length}',
    ];
    final muted = !rule.enabled;
    final selected = rule.id != null && rule.id == _ruleFilter;
    final counts = _ruleCounts[rule.id] ?? const {};
    int count(SubtitleBatchStatus s) => counts[s] ?? 0;
    final total = counts.values.fold(0, (a, b) => a + b);
    final done =
        count(SubtitleBatchStatus.done) + count(SubtitleBatchStatus.skipped);
    final stats = [
      l.subtitleRuleVideoCount(total),
      if (count(SubtitleBatchStatus.running) +
              count(SubtitleBatchStatus.pending) >
          0)
        '${count(SubtitleBatchStatus.running) + count(SubtitleBatchStatus.pending)} '
            '${l.subtitleQueueStatusPending.toLowerCase()}',
      if (done > 0) '$done ${l.subtitleQueueStatusDone.toLowerCase()}',
      if (count(SubtitleBatchStatus.failed) > 0)
        '${count(SubtitleBatchStatus.failed)} '
            '${l.subtitleQueueStatusFailed.toLowerCase()}',
    ].join(' · ');
    return Padding(
      key: ValueKey('subtitle-rule:${rule.id}'),
      padding: const EdgeInsets.only(bottom: 2),
      child: ListItemShell(
        isSelected: selected,
        isSelectionMode: false,
        isDesktopMode: _desktop,
        borderRadius: BorderRadius.circular(10),
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        // A click shows only this rule's videos; clicking again shows all.
        onTap: () => _selectRule(selected ? null : rule.id),
        onDoubleTap: () => unawaited(_editRule(rule)),
        onSecondaryTapUp: (d) =>
            unawaited(_showRuleMenu(rule, d.globalPosition)),
        child: Opacity(
          opacity: muted ? .55 : 1,
          child: Row(
            children: [
              Icon(
                PhosphorIconsLight.listChecks,
                size: CbSizes.iconLg,
                color: muted ? c.iconSubtle : c.accent.base,
              ),
              const SizedBox(width: CbSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            rule.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CbTypography.label.copyWith(
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        // The rule Start is running (or all of them).
                        if (_runRequested &&
                            (_runRule == null || _runRule == rule.id)) ...[
                          const SizedBox(width: CbSpacing.xs),
                          Icon(
                            PhosphorIconsLight.play,
                            key: ValueKey('subtitle-rule-running:${rule.id}'),
                            size: 12,
                            color: c.accent.base,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      sources.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.bodySm.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    Text(
                      '${_language(l, rule.sourceLanguage)} → '
                      '${_language(l, rule.targetLanguage, target: true)}'
                      ' · ${subtitleOutputModeLabel(l, rule.outputMode)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.caption.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stats,
                      key: ValueKey('subtitle-rule-stats:${rule.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.caption.copyWith(
                        color: count(SubtitleBatchStatus.failed) > 0
                            ? c.status.danger
                            : c.textSecondary,
                      ),
                    ),
                    if (total > 0) ...[
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(CbRadii.full),
                        child: LinearProgressIndicator(
                          value: done / total,
                          minHeight: 3,
                          color: c.status.success,
                          backgroundColor: c.fillSubtle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              CbButton.icon(
                icon: PhosphorIconsLight.magnifyingGlass,
                tooltip: l.subtitleRuleScanNow,
                size: CbButtonSize.sm,
                onPressed: _scanning ? null : () => unawaited(_scan([rule])),
              ),
              Builder(
                builder: (buttonContext) => CbButton.icon(
                  icon: PhosphorIconsLight.dotsThreeVertical,
                  tooltip: l.moreOptions,
                  size: CbButtonSize.sm,
                  onPressed: () =>
                      unawaited(_showRuleMenu(rule, _below(buttonContext))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- queue

  /// Limits the list to one rule; every rule is independent.
  Widget _rulePicker(AppLocalizations l) => CbSelect<int>(
    key: ValueKey('subtitle-rule-filter:${_ruleFilter ?? 0}'),
    value: _ruleFilter ?? 0,
    size: CbSelectSize.sm,
    variant: CbSelectVariant.ghost,
    items: [
      CbSelectItem(
        value: 0,
        label: l.subtitleQueueAllRules,
        icon: PhosphorIconsLight.stack,
      ),
      for (final rule in _rules)
        if (rule.id != null)
          CbSelectItem(
            value: rule.id!,
            label: rule.name,
            icon: PhosphorIconsLight.listChecks,
          ),
    ],
    onChanged: (id) => _selectRule(id == 0 ? null : id),
  );

  String _statusLabel(AppLocalizations l, SubtitleBatchStatus status) =>
      switch (status) {
        SubtitleBatchStatus.pending => l.subtitleQueueStatusPending,
        SubtitleBatchStatus.running => l.subtitleQueueStatusRunning,
        SubtitleBatchStatus.done => l.subtitleQueueStatusDone,
        SubtitleBatchStatus.skipped => l.subtitleQueueStatusSkipped,
        SubtitleBatchStatus.failed => l.subtitleQueueStatusFailed,
        SubtitleBatchStatus.cancelled => l.subtitleQueueStatusCancelled,
      };

  List<Widget> _queueSlivers(AppLocalizations l, {bool inPanel = false}) {
    final pad = inPanel ? 12.0 : 16.0;
    final filters = Wrap(
      spacing: CbSpacing.xs,
      runSpacing: CbSpacing.xs,
      children: [
        _filterPill(l.subtitleQueueAll, _listTotal, null),
        for (final status in SubtitleBatchStatus.values)
          if (_listCount(status) > 0 || _filter == status)
            _filterPill(_statusLabel(l, status), _listCount(status), status),
      ],
    );
    final jobs = _visibleJobs;
    final listPadding = EdgeInsets.fromLTRB(pad - 4, 0, pad - 4, 16);
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, inPanel ? 12 : 16, pad, 0),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(
                l.subtitleQueueTabQueue,
                count: _listTotal,
                trailing: _rulePicker(l),
              ),
              filters,
              const SizedBox(height: CbSpacing.sm),
            ],
          ),
        ),
      ),
      if (jobs.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _message(
            _query.trim().isNotEmpty ? l.noResultsFound : l.subtitleQueueEmpty,
            _query.trim().isNotEmpty
                ? PhosphorIconsLight.magnifyingGlass
                : PhosphorIconsLight.subtitles,
          ),
        )
      else if (_viewMode == ViewMode.details) ...[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad - 4, 0, pad - 4, 0),
          sliver: SliverToBoxAdapter(child: _detailsHeader(l)),
        ),
        SliverPadding(
          padding: listPadding,
          sliver: SliverList.builder(
            itemCount: jobs.length,
            itemBuilder: (context, i) => _detailsRow(l, jobs[i]),
          ),
        ),
      ] else if (_viewMode == ViewMode.grid)
        SliverPadding(
          padding: listPadding,
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 240,
              mainAxisExtent: 230,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: jobs.length,
            itemBuilder: (context, i) => _jobGridCard(l, jobs[i]),
          ),
        )
      else if (_viewMode == ViewMode.tiles)
        SliverPadding(
          padding: listPadding,
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 92,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: jobs.length,
            itemBuilder: (context, i) => _jobTile(l, jobs[i]),
          ),
        )
      else
        SliverPadding(
          padding: listPadding,
          sliver: SliverList.builder(
            itemCount: jobs.length,
            itemBuilder: (context, i) => _jobRow(l, jobs[i]),
          ),
        ),
    ];
  }

  // ------------------------------------------------- details and tiles

  (IconData, Color) _statusLook(SubtitleBatchStatus status) {
    final c = context.cbColors;
    return switch (status) {
      SubtitleBatchStatus.pending => (PhosphorIconsLight.clock, c.iconSubtle),
      SubtitleBatchStatus.running => (
        PhosphorIconsLight.waveform,
        c.accent.base,
      ),
      SubtitleBatchStatus.done => (
        PhosphorIconsLight.checkCircle,
        c.status.success,
      ),
      SubtitleBatchStatus.skipped => (
        PhosphorIconsLight.skipForward,
        c.textTertiary,
      ),
      SubtitleBatchStatus.failed => (
        PhosphorIconsLight.warningCircle,
        c.status.danger,
      ),
      SubtitleBatchStatus.cancelled => (
        PhosphorIconsLight.prohibit,
        c.textTertiary,
      ),
    };
  }

  static String _time(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  /// Columns that fit a details row [width] wide; the name and the
  /// percentage always show, the status icon stands in for its column.
  static ({
    bool status,
    bool bar,
    bool folder,
    bool languages,
    bool rule,
    bool updated,
  })
  _columns(double width) => (
    status: width >= 520,
    bar: width >= 460,
    folder: width >= 620,
    languages: width >= 760,
    rule: width >= 900,
    updated: width >= 1040,
  );

  Widget _detailsHeader(AppLocalizations l) {
    final c = context.cbColors;
    Widget cell(_JobSort? sort, String label, {int flex = 2}) {
      final active = sort != null && _sort == sort;
      final text = Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: CbTypography.labelSm.copyWith(
                color: active ? c.textPrimary : c.textSecondary,
              ),
            ),
          ),
          if (active)
            Icon(
              _ascending
                  ? PhosphorIconsLight.caretUp
                  : PhosphorIconsLight.caretDown,
              size: 12,
              color: c.textSecondary,
            ),
        ],
      );
      return Expanded(
        flex: flex,
        child: sort == null
            ? text
            : InkWell(
                key: ValueKey('subtitle-column-${sort.name}'),
                onTap: () => _setSort(sort),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: text,
                ),
              ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final show = _columns(constraints.maxWidth);
        return Container(
          // Matches the rows: 10 + 4 px padding and 84 px of actions.
          padding: const EdgeInsets.fromLTRB(10, 0, 88, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.strokeSubtle)),
          ),
          child: Row(
            children: [
              const SizedBox(width: CbSizes.iconMd + CbSpacing.md),
              cell(_JobSort.name, l.columnName, flex: 5),
              if (show.folder) cell(_JobSort.folder, l.folder, flex: 4),
              if (show.status)
                cell(_JobSort.status, l.subtitleQueueColumnStatus),
              cell(_JobSort.progress, l.subtitleQueueColumnProgress),
              if (show.languages) cell(null, l.language),
              if (show.rule) cell(null, l.subtitleQueueColumnRule),
              if (show.updated)
                cell(_JobSort.modified, l.columnDateModified, flex: 3),
            ],
          ),
        );
      },
    );
  }

  Widget _detailsRow(AppLocalizations l, SubtitleBatchJob job) {
    final c = context.cbColors;
    final (icon, color) = _statusLook(job.status);
    final progress = _progressOf(job);
    final running = job.status == SubtitleBatchStatus.running;
    Widget text(String value, {int flex = 2, Color? tone, TextStyle? style}) =>
        Expanded(
          flex: flex,
          child: Padding(
            padding: const EdgeInsets.only(right: CbSpacing.sm),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (style ?? CbTypography.body).copyWith(
                color: tone ?? c.textSecondary,
              ),
            ),
          ),
        );
    return Padding(
      key: ValueKey('subtitle-job:${job.id}'),
      padding: const EdgeInsets.only(top: 1),
      child: ListItemShell(
        isSelected: false,
        isSelectionMode: false,
        isDesktopMode: _desktop,
        borderRadius: BorderRadius.circular(6),
        padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
        onDoubleTap: () => _openFolder(job),
        onSecondaryTapUp: (d) => unawaited(_showJobMenu(job, d.globalPosition)),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Same basis as the header: the row's full width.
            final show = _columns(constraints.maxWidth + 14);
            return Row(
              children: [
                Icon(icon, size: CbSizes.iconMd, color: color),
                const SizedBox(width: CbSpacing.md),
                text(job.fileName, flex: 5, tone: c.textPrimary),
                if (show.folder) text(job.folder, flex: 4),
                if (show.status)
                  if (_failureLine(l, job) case final failure?)
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.only(right: CbSpacing.sm),
                        child: _failureLink(job, failure, CbTypography.body),
                      ),
                    )
                  else
                    text(
                      _statusLabel(l, job.status),
                      tone: running ? c.accent.text : null,
                    ),
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.only(right: CbSpacing.md),
                    child: Row(
                      children: [
                        if (!show.bar)
                          const Spacer()
                        else
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(CbRadii.full),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 4,
                                color: job.status == SubtitleBatchStatus.failed
                                    ? c.status.danger
                                    : c.accent.base,
                                backgroundColor: c.fillSubtle,
                              ),
                            ),
                          ),
                        const SizedBox(width: CbSpacing.sm),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '${(progress * 100).floor()}%',
                            textAlign: TextAlign.right,
                            style: CbTypography.caption.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (show.languages)
                  text(
                    '${job.settings.sourceLanguage} → '
                    '${job.settings.targetLanguage}',
                  ),
                if (show.rule) text(job.ruleName),
                if (show.updated)
                  text(
                    job.fileModifiedAt == null
                        ? '—'
                        : _time(job.fileModifiedAt!),
                    flex: 3,
                    style: CbTypography.bodySm,
                  ),
                _jobActions(l, job, compact: true),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _jobGridCard(AppLocalizations l, SubtitleBatchJob job) {
    final c = context.cbColors;
    final (icon, color) = _statusLook(job.status);
    final progress = _progressOf(job);
    return GridItemShell(
      key: ValueKey('subtitle-job:${job.id}'),
      isSelected: false,
      isSelectionMode: false,
      isDesktopMode: _desktop,
      onDoubleTap: () => _openFolder(job),
      onSecondaryTapUp: (d) => unawaited(_showJobMenu(job, d.globalPosition)),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.surface.withValues(alpha: _desktop ? .5 : 1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.strokeSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => ThumbnailLoader(
                  key: ValueKey('subtitle-thumbnail:${job.id}'),
                  filePath: job.path,
                  isVideo: true,
                  isImage: false,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fit: BoxFit.contain,
                  keepAlive: false,
                  borderRadius: BorderRadius.circular(8),
                  fallbackBuilder: () => Center(
                    child: Icon(
                      PhosphorIconsLight.videoCamera,
                      size: 36,
                      color: c.iconSubtle,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: CbSpacing.sm),
            Tooltip(
              message: job.path,
              child: Text(
                job.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CbTypography.label.copyWith(color: c.textPrimary),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _statusLabel(l, job.status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CbTypography.caption.copyWith(color: color),
                  ),
                ),
                Text(
                  '${(progress * 100).floor()}%',
                  style: CbTypography.caption.copyWith(color: c.textSecondary),
                ),
              ],
            ),
            if (_failureLine(l, job) case final failure?)
              _failureLink(job, failure, CbTypography.caption),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(CbRadii.full),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                color: color,
                backgroundColor: c.fillSubtle,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: _jobActions(l, job, compact: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobTile(AppLocalizations l, SubtitleBatchJob job) {
    final c = context.cbColors;
    final (icon, color) = _statusLook(job.status);
    final progress = _progressOf(job);
    final theme = Theme.of(context);
    return GridItemShell(
      key: ValueKey('subtitle-job:${job.id}'),
      isSelected: false,
      isSelectionMode: false,
      isDesktopMode: _desktop,
      onDoubleTap: () => _openFolder(job),
      onSecondaryTapUp: (d) => unawaited(_showJobMenu(job, d.globalPosition)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: _desktop ? .5 : 1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.strokeSubtle),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(width: CbSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CbTypography.label.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  if (_failureLine(l, job) case final failure?)
                    _failureLink(job, failure, CbTypography.caption)
                  else
                    Text(
                      '${_statusLabel(l, job.status)} · '
                      '${(progress * 100).floor()}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.caption.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(CbRadii.full),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      color: c.accent.base,
                      backgroundColor: c.fillSubtle,
                    ),
                  ),
                ],
              ),
            ),
            _sourceFolderButton(l, job, CbButtonSize.sm),
            Builder(
              builder: (buttonContext) => CbButton.icon(
                icon: PhosphorIconsLight.dotsThreeVertical,
                tooltip: l.moreOptions,
                size: CbButtonSize.sm,
                onPressed: () =>
                    unawaited(_showJobMenu(job, _below(buttonContext))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPill(String label, int count, SubtitleBatchStatus? status) {
    final c = context.cbColors;
    final selected = _filter == status;
    return Material(
      color: selected ? c.accent.tint : Colors.transparent,
      borderRadius: BorderRadius.circular(CbRadii.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(CbRadii.full),
        onTap: () {
          setState(() => _filter = status);
          unawaited(_reload());
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            '$label  $count',
            style: CbTypography.labelSm.copyWith(
              color: selected ? c.accent.text : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _jobRow(AppLocalizations l, SubtitleBatchJob job) {
    final c = context.cbColors;
    final progress = _queue.liveProgress(job.id) ?? job.progress;
    final running = job.status == SubtitleBatchStatus.running;
    final (icon, color) = switch (job.status) {
      SubtitleBatchStatus.pending => (PhosphorIconsLight.clock, c.iconSubtle),
      SubtitleBatchStatus.running => (
        PhosphorIconsLight.waveform,
        c.accent.base,
      ),
      SubtitleBatchStatus.done => (
        PhosphorIconsLight.checkCircle,
        c.status.success,
      ),
      SubtitleBatchStatus.skipped => (
        PhosphorIconsLight.skipForward,
        c.textTertiary,
      ),
      SubtitleBatchStatus.failed => (
        PhosphorIconsLight.warningCircle,
        c.status.danger,
      ),
      SubtitleBatchStatus.cancelled => (
        PhosphorIconsLight.prohibit,
        c.textTertiary,
      ),
    };
    final settings = job.settings;
    final status = [
      _statusLabel(l, job.status),
      if (running ||
          (job.status == SubtitleBatchStatus.pending && progress > 0))
        '${(progress * 100).floor()}%',
      '${_language(l, settings.sourceLanguage)} → '
          '${_language(l, settings.targetLanguage, target: true)}',
      if (job.ruleName.isNotEmpty) job.ruleName,
    ].join(' · ');
    final failure = _failureLine(l, job);
    final note = failure != null
        ? null
        : job.status == SubtitleBatchStatus.failed
        ? job.message
        : job.outputPath ?? job.message;
    return Padding(
      key: ValueKey('subtitle-job:${job.id}'),
      padding: const EdgeInsets.only(bottom: 2),
      child: ListItemShell(
        isSelected: false,
        isSelectionMode: false,
        isDesktopMode: _desktop,
        borderRadius: BorderRadius.circular(10),
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        onDoubleTap: () => _openFolder(job),
        onSecondaryTapUp: (d) => unawaited(_showJobMenu(job, d.globalPosition)),
        child: Row(
          children: [
            Icon(icon, size: CbSizes.iconLg, color: color),
            const SizedBox(width: CbSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          job.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.label.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: CbSpacing.sm),
                      Flexible(
                        child: Text(
                          job.folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: CbTypography.caption.copyWith(
                            color: c.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CbTypography.bodySm.copyWith(
                      color: running ? c.accent.text : c.textSecondary,
                    ),
                  ),
                  if (failure != null)
                    _failureLink(job, failure, CbTypography.caption)
                  else if (note != null && note.isNotEmpty)
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.caption.copyWith(
                        color: job.status == SubtitleBatchStatus.failed
                            ? c.status.danger
                            : c.textTertiary,
                      ),
                    ),
                  if (running) ...[
                    const SizedBox(height: CbSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CbRadii.full),
                      child: LinearProgressIndicator(
                        value: progress > 0 ? progress : null,
                        minHeight: 3,
                        color: c.accent.base,
                        backgroundColor: c.accent.tint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: CbSpacing.sm),
            _jobActions(l, job),
          ],
        ),
      ),
    );
  }

  /// The failure in plain words; clicking it shows the details.
  Widget _failureLink(SubtitleBatchJob job, String text, TextStyle style) {
    final c = context.cbColors;
    final l = AppLocalizations.of(context)!;
    final kind = _failureOf(job) ?? SubtitleBatchFailureKind.unknown;
    final color = job.status == SubtitleBatchStatus.failed
        ? c.status.danger
        : c.status.warning;
    return Tooltip(
      message: l.subtitleBatchFailureHint(kind.name),
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('subtitle-job-failure:${job.id}'),
          onTap: () => unawaited(_showError(job)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsLight.info, size: 13, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style.copyWith(
                    color: color,
                    decoration: TextDecoration.underline,
                    decorationColor: color.withValues(alpha: .4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceFolderButton(
    AppLocalizations l,
    SubtitleBatchJob job,
    CbButtonSize size,
  ) => CbButton.icon(
    key: ValueKey('subtitle-source-folder:${job.id}'),
    icon: PhosphorIconsLight.folderOpen,
    tooltip: l.openContainingFolder,
    size: size,
    onPressed: () => _openFolder(job),
  );

  /// Always offer the original video location, then the state action and menu.
  Widget _jobActions(
    AppLocalizations l,
    SubtitleBatchJob job, {
    bool compact = false,
  }) {
    final size = compact ? CbButtonSize.xs : CbButtonSize.sm;
    final active =
        job.status == SubtitleBatchStatus.pending ||
        job.status == SubtitleBatchStatus.running;
    return SizedBox(
      width: compact ? 84 : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _sourceFolderButton(l, job, size),
          if (active)
            CbButton.icon(
              icon: PhosphorIconsLight.stop,
              tooltip: l.cancel,
              size: size,
              onPressed: () async {
                await _queue.cancel([job.id]);
                await _reload();
              },
            )
          else if (job.status != SubtitleBatchStatus.done)
            CbButton.icon(
              icon: PhosphorIconsLight.arrowClockwise,
              tooltip: l.retry,
              size: size,
              onPressed: () async {
                await _queue.retry([job.id]);
                await _reload();
              },
            ),
          Builder(
            builder: (buttonContext) => CbButton.icon(
              icon: PhosphorIconsLight.dotsThreeVertical,
              tooltip: l.moreOptions,
              size: size,
              onPressed: () =>
                  unawaited(_showJobMenu(job, _below(buttonContext))),
            ),
          ),
        ],
      ),
    );
  }
}
