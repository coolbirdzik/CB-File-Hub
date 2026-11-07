import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/disk_cleaner/app_storage/app_space_models.dart';
import '../../services/disk_cleaner/docker/docker_storage.dart';
import 'app_storage_scanner.dart';
import 'cleaner_app_storage_state.dart';

/// App storage page: what each installed app keeps on disk and what of it
/// can go. Results show once the data folders are sized; app bundle sizes
/// follow. Cleaning goes through the Cleaner's queue; this cubit only tracks
/// what is pending and drops what was removed.
class CleanerAppStorageCubit extends Cubit<CleanerAppStorageState> {
  final AppStorageScanner _scanner;

  /// Reads and prunes Docker after the scan read it once.
  final DockerTool _docker;

  /// Bumped per scan and cancel so a stale result cannot publish.
  int _generation = 0;

  /// Progress arrives per chunk; a few updates a second are enough.
  DateTime _lastProgress = DateTime.fromMillisecondsSinceEpoch(0);

  CleanerAppStorageCubit({required this._scanner, DockerTool? docker})
    : _docker = docker ?? DockerTool(),
      super(const CleanerAppStorageState());

  Future<void> scan() async {
    if (state.status == CleanerAppStorageStatus.scanning) return;
    final generation = ++_generation;
    emit(
      CleanerAppStorageState(
        status: CleanerAppStorageStatus.scanning,
        pendingPaths: state.pendingPaths,
        focusedAppId: state.focusedAppId,
      ),
    );
    try {
      final report = await _scanner.scan(
        onProgress: (done, total) {
          if (isClosed || generation != _generation) return;
          final now = DateTime.now();
          if (done < total &&
              now.difference(_lastProgress) <
                  const Duration(milliseconds: 100)) {
            return;
          }
          _lastProgress = now;
          emit(state.copyWith(done: done, total: total));
        },
        onPartial: (partial) {
          if (isClosed || generation != _generation) return;
          _publish(partial, CleanerAppStorageStatus.scanning);
        },
      );
      if (isClosed || generation != _generation) return;
      if (report == null) {
        emit(
          CleanerAppStorageState(
            status: state.report == null
                ? CleanerAppStorageStatus.idle
                : CleanerAppStorageStatus.ready,
            report: state.report,
            selectedGroups: state.selectedGroups,
            knownGroups: state.knownGroups,
            pendingPaths: state.pendingPaths,
            focusedAppId: state.focusedAppId,
          ),
        );
        return;
      }
      _publish(report, CleanerAppStorageStatus.ready);
    } catch (error) {
      if (isClosed || generation != _generation) return;
      emit(
        CleanerAppStorageState(
          status: CleanerAppStorageStatus.failure,
          errorMessage: '$error',
        ),
      );
    }
  }

  void _publish(AppSpaceReport report, CleanerAppStorageStatus status) {
    final groups = [
      for (final entry in report.entries) ...AppCleanGroup.of(entry),
    ];
    final known = {...state.knownGroups};
    final selected = {...state.selectedGroups};
    for (final group in groups) {
      if (known.add(group.id) && group.selectedByDefault) {
        selected.add(group.id);
      }
    }
    // Docker arrives with the complete report: check its regenerable prunes
    // the first time it shows.
    final docker = report.docker;
    var dockerSelected = state.dockerSelected;
    if (docker != null && docker.isReady && known.add('docker')) {
      dockerSelected = {
        for (final kind in docker.cleanable)
          if (kind.selectedByDefault) kind,
      };
    }
    emit(
      state.copyWith(
        status: status,
        report: report,
        selectedGroups: selected,
        knownGroups: known,
        dockerSelected: dockerSelected,
      ),
    );
  }

  /// Stops a running scan; a partial report stays on screen.
  void cancel() {
    if (state.status != CleanerAppStorageStatus.scanning) return;
    _generation++;
    _scanner.cancel();
    emit(
      CleanerAppStorageState(
        status: state.report == null
            ? CleanerAppStorageStatus.idle
            : CleanerAppStorageStatus.ready,
        report: state.report,
        selectedGroups: state.selectedGroups,
        knownGroups: state.knownGroups,
        pendingPaths: state.pendingPaths,
        focusedAppId: state.focusedAppId,
      ),
    );
  }

  /// Removes an app that is no longer installed (moved to the Trash from
  /// the Apps page). Its data turns up on Leftovers after a scan.
  void dropApp(String appId) {
    final report = state.report;
    if (report == null) return;
    emit(
      state.copyWith(
        report: AppSpaceReport(
          entries: [
            for (final entry in report.entries)
              if (entry.key != appId) entry,
          ],
          generatedAt: report.generatedAt,
          complete: report.complete,
          docker: report.docker,
        ),
        focusedAppId: state.focusedAppId == appId ? null : state.focusedAppId,
      ),
    );
  }

  void toggleDocker(DockerCleanKind kind) {
    final selected = {...state.dockerSelected};
    if (!selected.remove(kind)) selected.add(kind);
    emit(state.copyWith(dockerSelected: selected));
  }

  /// Runs the checked Docker prunes, then reads Docker again. Permanent:
  /// the view confirms first.
  Future<void> cleanDocker() async {
    final docker = state.report?.docker;
    if (state.isCleaningDocker ||
        state.status == CleanerAppStorageStatus.scanning ||
        docker == null ||
        !docker.isReady) {
      return;
    }
    final kinds = {
      for (final kind in state.dockerSelected)
        if (docker.countOf(kind) > 0) kind,
    };
    if (kinds.isEmpty) return;
    emit(
      state.copyWith(
        dockerStep: DockerCleanKind.values.firstWhere(kinds.contains),
        dockerFreed: null,
        dockerError: null,
      ),
    );
    int? freed;
    String? error;
    try {
      final byKind = await _docker.prune(
        kinds,
        onStep: (kind) {
          if (!isClosed) emit(state.copyWith(dockerStep: kind));
        },
      );
      freed = byKind.values.fold<int>(0, (sum, bytes) => sum + bytes);
    } catch (e) {
      error = '$e';
    }
    // Read again either way: a failed prune may have removed some of it.
    final reloaded = await _docker.load();
    if (isClosed) return;
    emit(
      state.copyWith(
        dockerStep: null,
        dockerFreed: freed,
        dockerError: error,
        report: state.report?.withDocker(reloaded),
        dockerSelected: {
          for (final kind in state.dockerSelected)
            if (reloaded.countOf(kind) > 0) kind,
        },
      ),
    );
  }

  /// Lists only [appId], opened; null lists every app again.
  void focusApp(String? appId) => emit(state.copyWith(focusedAppId: appId));

  void toggleGroup(String id) {
    final selected = {...state.selectedGroups};
    if (!selected.remove(id)) selected.add(id);
    emit(state.copyWith(selectedGroups: selected));
  }

  void markPending(Iterable<String> paths) =>
      emit(state.copyWith(pendingPaths: {...state.pendingPaths, ...paths}));

  /// Ends a clean: [paths] are no longer pending and [removed] are gone.
  void finishClean(Iterable<String> paths, Iterable<String> removed) {
    emit(
      state.copyWith(
        pendingPaths: {...state.pendingPaths}..removeAll(paths),
        report: state.report?.withoutPaths(removed.toSet()),
      ),
    );
  }

  @override
  Future<void> close() {
    _scanner.cancel();
    return super.close();
  }
}
