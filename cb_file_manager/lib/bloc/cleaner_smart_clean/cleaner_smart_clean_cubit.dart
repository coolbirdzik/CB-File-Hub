import 'dart:isolate';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/app_insights/app_insights_models.dart';
import '../../services/disk_cleaner/cleaner_installed_apps.dart';
import '../../services/disk_cleaner/cleaner_item_origin.dart';
import '../../services/disk_cleaner/cleaner_models.dart';
import '../../services/disk_cleaner/cleaner_quick_clean.dart';
import '../../services/disk_cleaner/cleaner_review_candidates.dart';
import 'cleaner_smart_clean_state.dart';

typedef CleanerSmartCleanScan =
    Future<ScanReport> Function(void Function(ScanProgress) onProgress);

/// Returns null when the clean did not run (another cleanup was active or it
/// failed; the caller reports why).
typedef CleanerSmartCleanClean =
    Future<CleanReport?> Function(
      List<JunkItem> items,
      void Function(int done, int total, String? path) onProgress,
    );

/// Smart Clean: one scan of the safest junk ([CleanerQuickClean]), a card per
/// category split by the app that made the files and what they are
/// ([CleanerItemOrigins]), one button to clean what stays checked.
///
/// Recycle Bin entries come back as their own unchecked group, because the
/// clean pipeline always deletes them permanently.
class CleanerSmartCleanCubit extends Cubit<CleanerSmartCleanState> {
  final CleanerSmartCleanScan _scan;
  final CleanerSmartCleanClean _clean;
  final void Function()? _cancelScan;
  final DateTime Function() _nowProvider;

  /// The apps installed on this machine, used to name who made each file.
  final Future<List<InstalledAppInfo>> Function()? _installedApps;

  /// Smart Clean does not wait longer than this for [_installedApps].
  final Duration _installedAppsTimeout;

  /// False builds the groups on the calling isolate (widget tests, whose fake
  /// async never delivers an isolate's reply).
  final bool _groupOffThread;

  /// Bumped on every scan and cancel so a stale scan cannot publish.
  int _generation = 0;

  /// Progress arrives per file; the view only needs a few frames' worth.
  static const Duration _progressInterval = Duration(milliseconds: 80);
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);

  bool _shouldEmitProgress({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastProgress) < _progressInterval) {
      return false;
    }
    _lastProgress = now;
    return true;
  }

  CleanerSmartCleanCubit({
    required this._scan,
    required this._clean,
    this._cancelScan,
    DateTime Function()? nowProvider,
    this._groupOffThread = true,
    this._installedApps,
    this._installedAppsTimeout = const Duration(seconds: 3),
  }) : _nowProvider = nowProvider ?? DateTime.now,
       super(const CleanerSmartCleanState());

  static const String _recycleBinId = 'recycle_bin';

  Future<void> scan() async {
    if (state.status == CleanerSmartCleanStatus.scanning ||
        state.status == CleanerSmartCleanStatus.cleaning) {
      return;
    }
    final generation = ++_generation;
    // Loads alongside the scan; a slow or failed inventory only costs names.
    final appsFuture = _loadInstalledApps();
    emit(
      const CleanerSmartCleanState(status: CleanerSmartCleanStatus.scanning),
    );

    final ScanReport report;
    try {
      report = await _scan((progress) {
        if (isClosed || generation != _generation) return;
        if (!_shouldEmitProgress()) return;
        emit(
          state.copyWith(
            scanCategoryId: progress.categoryId.isEmpty
                ? state.scanCategoryId
                : progress.categoryId,
            scanPath: progress.currentPath,
            scanFraction: progress.fraction,
          ),
        );
      });
    } on CleanerScanBusyError {
      if (isClosed || generation != _generation) return;
      emit(
        const CleanerSmartCleanState(
          status: CleanerSmartCleanStatus.failure,
          error: CleanerSmartCleanError.busy,
        ),
      );
      return;
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        CleanerSmartCleanState(
          status: CleanerSmartCleanStatus.failure,
          error: CleanerSmartCleanError.failed,
          errorMessage: '$error',
        ),
      );
      return;
    }
    if (isClosed || generation != _generation) return;

    final now = _nowProvider();
    final apps = await appsFuture;
    if (isClosed || generation != _generation) return;
    final prepared = _groupOffThread
        ? await _groupsOffThread(report, now, apps)
        : _prepareResults(report, now, apps);
    final groups = prepared.groups;
    if (isClosed || generation != _generation) return;
    emit(
      CleanerSmartCleanState(
        status: CleanerSmartCleanStatus.ready,
        groups: groups,
        reviewCandidates: prepared.review,
        scanWarnings: report.warnings,
        excluded: {
          for (final group in groups)
            if (group.isPermanent)
              for (final source in group.sources)
                CleanerSmartCleanState.sourceId(group.categoryId, source.key),
        },
      ),
    );
  }

  /// Selecting and classifying a large %TEMP% takes hundreds of milliseconds,
  /// so it runs in an isolate. Static, so the closure cannot capture the
  /// cubit.
  static Future<
    ({
      List<CleanerSmartCleanGroup> groups,
      List<CleanerFileReviewCandidate> review,
    })
  >
  _groupsOffThread(
    ScanReport report,
    DateTime now,
    List<InstalledAppInfo> apps,
  ) async {
    try {
      return await Isolate.run(() => _prepareResults(report, now, apps));
    } catch (_) {
      return _prepareResults(report, now, apps);
    }
  }

  static ({
    List<CleanerSmartCleanGroup> groups,
    List<CleanerFileReviewCandidate> review,
  })
  _prepareResults(
    ScanReport report,
    DateTime now,
    List<InstalledAppInfo> apps,
  ) => (
    groups: _buildGroups(report, now, apps),
    review: CleanerReviewCandidates.select(report, now),
  );

  static List<CleanerSmartCleanGroup> _buildGroups(
    ScanReport report,
    DateTime now,
    List<InstalledAppInfo> apps,
  ) {
    final safe = CleanerQuickClean.select(report, now: now);
    final installed = apps.isEmpty ? null : CleanerInstalledApps(apps);
    final groups = <CleanerSmartCleanGroup>[
      for (final entry in safe.itemsByCategory.entries)
        CleanerSmartCleanGroup(
          categoryId: entry.key,
          items: entry.value,
          installedApps: installed,
        ),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    final bin = report.itemsByCategory[_recycleBinId] ?? const <JunkItem>[];
    if (bin.isNotEmpty) {
      groups.add(
        CleanerSmartCleanGroup(
          categoryId: _recycleBinId,
          items: bin,
          isPermanent: true,
        ),
      );
    }
    return groups;
  }

  /// Never throws; empty when there is no loader, it fails or it is slow.
  Future<List<InstalledAppInfo>> _loadInstalledApps() async {
    final load = _installedApps;
    if (load == null) return const <InstalledAppInfo>[];
    try {
      return await load().timeout(_installedAppsTimeout);
    } catch (_) {
      return const <InstalledAppInfo>[];
    }
  }

  void cancelScan() {
    if (state.status != CleanerSmartCleanStatus.scanning) return;
    _generation++;
    _cancelScan?.call();
    emit(const CleanerSmartCleanState());
  }

  /// Unchecks the whole group when all of it is checked, checks all of it
  /// otherwise.
  void toggleGroup(String categoryId) {
    if (state.status != CleanerSmartCleanStatus.ready) return;
    final ids = [
      for (final group in state.groups)
        if (group.categoryId == categoryId)
          for (final source in group.sources)
            CleanerSmartCleanState.sourceId(categoryId, source.key),
    ];
    if (ids.isEmpty) return;
    final excluded = {...state.excluded};
    if (state.groupSelection(categoryId) == true) {
      excluded.addAll(ids);
    } else {
      excluded.removeAll(ids);
    }
    emit(state.copyWith(excluded: excluded));
  }

  void toggleSource(String categoryId, String sourceKey) {
    if (state.status != CleanerSmartCleanStatus.ready) return;
    final id = CleanerSmartCleanState.sourceId(categoryId, sourceKey);
    final excluded = {...state.excluded};
    if (!excluded.remove(id)) excluded.add(id);
    emit(state.copyWith(excluded: excluded));
  }

  Future<void> clean() async {
    if (state.status != CleanerSmartCleanStatus.ready) return;
    final items = state.selectedItems;
    if (items.isEmpty) return;
    final ready = state;
    emit(
      state.copyWith(
        status: CleanerSmartCleanStatus.cleaning,
        cleanDone: 0,
        cleanTotal: items.length,
        cleanPath: '',
      ),
    );

    CleanReport? report;
    try {
      report = await _clean(items, (done, total, path) {
        if (isClosed || state.status != CleanerSmartCleanStatus.cleaning) {
          return;
        }
        if (!_shouldEmitProgress(force: total > 0 && done >= total)) return;
        emit(
          state.copyWith(
            cleanDone: done,
            cleanTotal: total,
            cleanPath: path ?? '',
          ),
        );
      });
    } catch (_) {
      report = null;
    }
    if (isClosed) return;
    if (report == null) {
      // Nothing ran, or the caller already reported a failure: keep the
      // results so the user can retry or rescan.
      emit(ready);
      return;
    }

    final succeeded = report.succeeded.toSet();
    var movedBytes = 0, movedCount = 0, permanentBytes = 0, permanentCount = 0;
    for (final group in ready.groups) {
      for (final item in [
        for (final source in ready.selectedSources(group)) ...source.items,
      ]) {
        if (!succeeded.contains(item.path)) continue;
        if (group.isPermanent) {
          permanentBytes += item.sizeBytes;
          permanentCount++;
        } else {
          movedBytes += item.sizeBytes;
          movedCount++;
        }
      }
    }
    emit(
      CleanerSmartCleanState(
        status: CleanerSmartCleanStatus.done,
        reviewCandidates: ready.reviewCandidates,
        scanWarnings: ready.scanWarnings,
        result: CleanerSmartCleanResult(
          movedBytes: movedBytes,
          movedCount: movedCount,
          permanentBytes: permanentBytes,
          permanentCount: permanentCount,
          skippedCount: (items.length - movedCount - permanentCount).clamp(
            0,
            items.length,
          ),
        ),
      ),
    );
  }

  /// Back to the start screen.
  void reset() {
    if (state.status == CleanerSmartCleanStatus.scanning ||
        state.status == CleanerSmartCleanStatus.cleaning) {
      return;
    }
    emit(const CleanerSmartCleanState());
  }
}
