import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/app_insights/app_leftover_finder.dart';
import '../../services/app_insights/app_leftover_scanner.dart';
import '../../services/app_insights/app_storage_analyzer.dart';
import 'cleaner_app_leftovers_state.dart';

class CleanerAppLeftoversCubit extends Cubit<CleanerAppLeftoversState> {
  final DateTime Function() _nowProvider;

  CleanerAppLeftoversCubit({DateTime Function()? nowProvider})
    : _nowProvider = nowProvider ?? DateTime.now,
      super(
        CleanerAppLeftoversState(evaluatedAt: (nowProvider ?? DateTime.now)()),
      );

  void setLoading() {
    emit(
      state.copyWith(
        status: CleanerAppLeftoversStatus.loading,
        errorMessage: null,
      ),
    );
  }

  void setError(String message) {
    emit(
      state.copyWith(
        status: CleanerAppLeftoversStatus.failure,
        errorMessage: message,
        isScanning: false,
        evaluatedAt: _nowProvider(),
      ),
    );
  }

  /// Publishes discovered folders. Nothing is listed until [addMeasurement]
  /// delivers each folder's size, so the list grows while the walk runs.
  void setReport(AppLeftoverReport report, {bool scanning = false}) {
    emit(
      state.copyWith(
        status: CleanerAppLeftoversStatus.ready,
        report: report,
        measurements: const <String, AppLeftoverMeasurement>{},
        isScanning: scanning,
        selectedPaths: const <String>{},
        evaluatedAt: _nowProvider(),
        errorMessage: null,
      ),
    );
  }

  void addMeasurement(String path, AppLeftoverMeasurement measurement) {
    addMeasurements(<String, AppLeftoverMeasurement>{path: measurement});
  }

  void addMeasurements(Map<String, AppLeftoverMeasurement> measurements) {
    if (measurements.isEmpty) return;
    _emitPruned(
      state.copyWith(
        measurements: <String, AppLeftoverMeasurement>{
          ...state.measurements,
          ...measurements,
        },
      ),
    );
  }

  /// Ends the walk, finished or cancelled. Folders measured so far stay.
  void finishScan() {
    if (!state.isScanning) return;
    emit(state.copyWith(isScanning: false));
  }

  void clear() {
    emit(
      CleanerAppLeftoversState(
        evaluatedAt: _nowProvider(),
        searchQuery: state.searchQuery,
        inactiveDays: state.inactiveDays,
      ),
    );
  }

  void setSearchQuery(String query) {
    _emitPruned(state.copyWith(searchQuery: query));
  }

  void setInactiveDays(int days) {
    if (days < 0) return;
    _emitPruned(state.copyWith(inactiveDays: days));
  }

  void toggleSelected(String path) {
    final selected = <String>{...state.selectedPaths};
    if (!selected.remove(path)) {
      if (!state.visibleCandidates.any((item) => item.path == path)) return;
      selected.add(path);
    }
    emit(state.copyWith(selectedPaths: selected));
  }

  /// Checks or unchecks a group of folders at once; hidden ones are ignored.
  void setSelected(Iterable<String> paths, bool selected) {
    final visible = {
      for (final candidate in state.visibleCandidates) candidate.path,
    };
    final next = <String>{...state.selectedPaths};
    for (final path in paths) {
      if (!selected) {
        next.remove(path);
      } else if (visible.contains(path)) {
        next.add(path);
      }
    }
    emit(state.copyWith(selectedPaths: next));
  }

  void selectAllVisible() {
    emit(
      state.copyWith(
        selectedPaths: <String>{
          for (final candidate in state.visibleCandidates) candidate.path,
        },
      ),
    );
  }

  void clearSelection() {
    if (state.selectedPaths.isEmpty) return;
    emit(state.copyWith(selectedPaths: const <String>{}));
  }

  /// Drops folders that were deleted (or are inside deleted folders).
  void removePaths(Iterable<String> deletedPaths) {
    final report = state.report;
    if (report == null) return;
    final deleted = deletedPaths.toList(growable: false);
    if (deleted.isEmpty) return;
    bool isDeleted(String path) => deleted.any(
      (removed) => AppStorageAnalyzer.isSameOrDescendant(path, removed),
    );
    final remaining = report.candidates
        .where((candidate) => !isDeleted(candidate.path))
        .toList(growable: false);
    if (remaining.length == report.candidates.length) return;
    emit(
      state.copyWith(
        report: AppLeftoverReport(
          drivePath: report.drivePath,
          candidates: remaining,
          generatedAt: report.generatedAt,
          isPartial: report.isPartial,
          inventoryUnavailable: report.inventoryUnavailable,
        ),
        measurements: <String, AppLeftoverMeasurement>{
          for (final entry in state.measurements.entries)
            if (!isDeleted(entry.key)) entry.key: entry.value,
        },
        selectedPaths: state.selectedPaths
            .where((path) => !isDeleted(path))
            .toSet(),
      ),
    );
  }

  /// Selection only ever covers visible folders, so a filter change cannot
  /// leave hidden folders queued for deletion.
  void _emitPruned(CleanerAppLeftoversState next) {
    if (next.selectedPaths.isEmpty) {
      emit(next);
      return;
    }
    final visible = {
      for (final candidate in next.visibleCandidates) candidate.path,
    };
    final pruned = next.selectedPaths.where(visible.contains).toSet();
    emit(
      pruned.length == next.selectedPaths.length
          ? next
          : next.copyWith(selectedPaths: pruned),
    );
  }
}
