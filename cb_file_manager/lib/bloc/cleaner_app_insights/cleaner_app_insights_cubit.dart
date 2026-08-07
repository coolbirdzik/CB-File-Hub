import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/app_insights/app_insights_models.dart';
import 'cleaner_app_insights_state.dart';

typedef CleanerAppInsightsLoader = Future<AppStorageReport> Function();

class CleanerAppInsightsCubit extends Cubit<CleanerAppInsightsState> {
  final DateTime Function() _nowProvider;
  int _loadGeneration = 0;

  CleanerAppInsightsCubit({DateTime Function()? nowProvider})
      : _nowProvider = nowProvider ?? DateTime.now,
        super(
          CleanerAppInsightsState(
            evaluatedAt: (nowProvider ?? DateTime.now)(),
          ),
        );

  Future<void> load(CleanerAppInsightsLoader loader) async {
    final generation = ++_loadGeneration;
    emit(
      state.copyWith(
        status: CleanerAppInsightsStatus.loading,
        errorMessage: null,
      ),
    );

    try {
      final report = await loader();
      if (isClosed || generation != _loadGeneration) return;
      _emitReport(report);
    } catch (error) {
      if (isClosed || generation != _loadGeneration) return;
      emit(
        state.copyWith(
          status: CleanerAppInsightsStatus.failure,
          errorMessage: error.toString(),
          evaluatedAt: _nowProvider(),
        ),
      );
    }
  }

  void setLoading() {
    _loadGeneration++;
    emit(
      state.copyWith(
        status: CleanerAppInsightsStatus.loading,
        errorMessage: null,
      ),
    );
  }

  void setError(String message) {
    _loadGeneration++;
    emit(
      state.copyWith(
        status: CleanerAppInsightsStatus.failure,
        errorMessage: message,
        evaluatedAt: _nowProvider(),
      ),
    );
  }

  void setReport(AppStorageReport report, {DateTime? evaluatedAt}) {
    _loadGeneration++;
    _emitReport(report, evaluatedAt: evaluatedAt);
  }

  void clear() {
    _loadGeneration++;
    emit(
      CleanerAppInsightsState(
        evaluatedAt: _nowProvider(),
        searchQuery: state.searchQuery,
        filter: state.filter,
        sort: state.sort,
        largeThresholdBytes: state.largeThresholdBytes,
        staleThresholdDays: state.staleThresholdDays,
      ),
    );
  }

  void setSearchQuery(String query) {
    _emitWithVisibleSelection(state.copyWith(searchQuery: query));
  }

  void setFilter(CleanerAppFilter filter) {
    _emitWithVisibleSelection(state.copyWith(filter: filter));
  }

  void setSort(CleanerAppSort sort) {
    _emitWithVisibleSelection(state.copyWith(sort: sort));
  }

  void setLargeThresholdBytes(int bytes) {
    if (bytes <= 0) return;
    _emitWithVisibleSelection(
      state.copyWith(largeThresholdBytes: bytes),
    );
  }

  void setStaleThresholdDays(int days) {
    if (days <= 0) return;
    _emitWithVisibleSelection(
      state.copyWith(staleThresholdDays: days),
    );
  }

  void selectApp(String? appId) {
    if (appId == null) {
      emit(state.copyWith(selectedAppId: null));
      return;
    }
    if (state.visibleApps.any((profile) => profile.app.id == appId)) {
      emit(state.copyWith(selectedAppId: appId));
    }
  }

  void _emitReport(AppStorageReport report, {DateTime? evaluatedAt}) {
    _emitWithVisibleSelection(
      state.copyWith(
        status: CleanerAppInsightsStatus.ready,
        report: report,
        evaluatedAt: evaluatedAt ?? _nowProvider(),
        errorMessage: null,
      ),
    );
  }

  void _emitWithVisibleSelection(CleanerAppInsightsState next) {
    final visible = next.visibleApps;
    final selectedId = next.selectedAppId;
    final selectedIsVisible = selectedId != null &&
        visible.any((profile) => profile.app.id == selectedId);
    final nextSelectedId = selectedIsVisible
        ? selectedId
        : (visible.isEmpty ? null : visible.first.app.id);
    emit(next.copyWith(selectedAppId: nextSelectedId));
  }
}
