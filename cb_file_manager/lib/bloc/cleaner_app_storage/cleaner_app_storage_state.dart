import 'package:equatable/equatable.dart';

import '../../services/disk_cleaner/app_storage/app_space_models.dart';
import '../../services/disk_cleaner/docker/docker_storage.dart';
import '../../services/disk_cleaner/editor_storage/editor_storage_models.dart';

enum CleanerAppStorageStatus { idle, scanning, ready, failure }

class CleanerAppStorageState extends Equatable {
  final CleanerAppStorageStatus status;

  /// The latest report: partial while app bundles are still measured.
  final AppSpaceReport? report;

  /// Folders sized so far, of [total].
  final int done;
  final int total;

  /// [AppCleanGroup.id]s that are checked.
  final Set<String> selectedGroups;

  /// Group ids the user has seen, so a later report keeps their choices and
  /// only checks groups that are new.
  final Set<String> knownGroups;

  /// Targets handed to a running clean.
  final Set<String> pendingPaths;
  final String? errorMessage;

  /// Only this app is listed, opened (from the Apps page).
  final String? focusedAppId;

  /// Docker prunes that are checked.
  final Set<DockerCleanKind> dockerSelected;

  /// The prune running now, while Docker is cleaned.
  final DockerCleanKind? dockerStep;

  /// Bytes the last Docker clean freed, by Docker's count.
  final int? dockerFreed;
  final String? dockerError;

  const CleanerAppStorageState({
    this.status = CleanerAppStorageStatus.idle,
    this.report,
    this.done = 0,
    this.total = 0,
    this.selectedGroups = const {},
    this.knownGroups = const {},
    this.pendingPaths = const {},
    this.errorMessage,
    this.focusedAppId,
    this.dockerSelected = const {},
    this.dockerStep,
    this.dockerFreed,
    this.dockerError,
  });

  bool get isCleaningDocker => dockerStep != null;

  /// What the checked Docker prunes free, by Docker's estimate. Unused
  /// images include the untagged ones.
  int get dockerSelectedBytes {
    final docker = report?.docker;
    if (docker == null || !docker.isReady) return 0;
    return [
      for (final kind in dockerSelected)
        if (!(kind == DockerCleanKind.danglingImages &&
            dockerSelected.contains(DockerCleanKind.unusedImages)))
          docker.bytesOf(kind),
    ].fold(0, (sum, bytes) => sum + bytes);
  }

  /// A scan is running. A report can be incomplete without one (a cancelled
  /// scan): its app bundles were never measured.
  bool get isMeasuring => status == CleanerAppStorageStatus.scanning;

  List<AppCleanGroup> get groups => [
    for (final entry in report?.entries ?? const <AppSpaceEntry>[])
      ...AppCleanGroup.of(entry),
  ];

  bool isSelected(AppCleanGroup group) => selectedGroups.contains(group.id);

  /// Checked targets not already being cleaned.
  List<EditorCleanTarget> get selectedTargets => [
    for (final group in groups)
      if (isSelected(group))
        for (final target in group.targets)
          if (!pendingPaths.contains(target.path)) target,
  ];

  int get selectedBytes =>
      selectedTargets.fold<int>(0, (sum, target) => sum + target.bytes);

  CleanerAppStorageState copyWith({
    CleanerAppStorageStatus? status,
    AppSpaceReport? report,
    int? done,
    int? total,
    Set<String>? selectedGroups,
    Set<String>? knownGroups,
    Set<String>? pendingPaths,
    String? errorMessage,
    Object? focusedAppId = _keep,
    Set<DockerCleanKind>? dockerSelected,
    Object? dockerStep = _keep,
    Object? dockerFreed = _keep,
    Object? dockerError = _keep,
  }) => CleanerAppStorageState(
    status: status ?? this.status,
    report: report ?? this.report,
    done: done ?? this.done,
    total: total ?? this.total,
    selectedGroups: selectedGroups ?? this.selectedGroups,
    knownGroups: knownGroups ?? this.knownGroups,
    pendingPaths: pendingPaths ?? this.pendingPaths,
    errorMessage: errorMessage ?? this.errorMessage,
    focusedAppId: identical(focusedAppId, _keep)
        ? this.focusedAppId
        : focusedAppId as String?,
    dockerSelected: dockerSelected ?? this.dockerSelected,
    dockerStep: identical(dockerStep, _keep)
        ? this.dockerStep
        : dockerStep as DockerCleanKind?,
    dockerFreed: identical(dockerFreed, _keep)
        ? this.dockerFreed
        : dockerFreed as int?,
    dockerError: identical(dockerError, _keep)
        ? this.dockerError
        : dockerError as String?,
  );

  @override
  List<Object?> get props => [
    status,
    report,
    done,
    total,
    selectedGroups,
    knownGroups,
    pendingPaths,
    errorMessage,
    focusedAppId,
    dockerSelected,
    dockerStep,
    dockerFreed,
    dockerError,
  ];
}

const Object _keep = Object();
