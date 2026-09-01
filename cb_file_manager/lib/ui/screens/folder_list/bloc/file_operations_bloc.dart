import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart'
    show FileOperations;
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:path/path.dart' as path;

import 'file_operations_event.dart';

/// Holds current clipboard state for the file operations layer.
class FileOperationsState extends Equatable {
  final int clipboardRevision;
  final String? error;
  final bool isProcessing;
  final List<String> retryableElevatedDeletePaths;

  const FileOperationsState({
    this.clipboardRevision = 0,
    this.error,
    this.isProcessing = false,
    this.retryableElevatedDeletePaths = const [],
  });

  FileOperationsState copyWith({
    int? clipboardRevision,
    Object? error = _unset,
    bool? isProcessing,
    Object? retryableElevatedDeletePaths = _unset,
  }) {
    return FileOperationsState(
      clipboardRevision: clipboardRevision ?? this.clipboardRevision,
      error: error == _unset ? this.error : error as String?,
      isProcessing: isProcessing ?? this.isProcessing,
      retryableElevatedDeletePaths: retryableElevatedDeletePaths == _unset
          ? this.retryableElevatedDeletePaths
          : List<String>.unmodifiable(
              retryableElevatedDeletePaths as List<String>,
            ),
    );
  }

  static const _unset = Object();

  @override
  List<Object?> get props => [
        clipboardRevision,
        error,
        isProcessing,
        retryableElevatedDeletePaths,
      ];
}

class FileOperationsBloc
    extends Bloc<FileOperationsEvent, FileOperationsState> {
  final FileNavigationBloc navigationBloc;
  final OperationProgressController _progressController;

  FileOperationsBloc({
    required this.navigationBloc,
    required OperationProgressController progressController,
  })  : _progressController = progressController,
        super(const FileOperationsState()) {
    on<FileOperationsCopy>(_onCopy);
    on<FileOperationsCut>(_onCut);
    on<FileOperationsPaste>(_onPaste);
    on<FileOperationsDeleteFiles>(_onDeleteFiles);
    on<FileOperationsDeleteItems>(_onDeleteItems);
    on<FileOperationsRetryDeleteAsAdministrator>(
      _onRetryDeleteAsAdministrator,
    );
    on<FileOperationsRename>(_onRename);
    on<FileOperationsClearClipboard>(_onClearClipboard);
  }

  void _onCopy(
    FileOperationsCopy event,
    Emitter<FileOperationsState> emit,
  ) {
    try {
      FileOperations().copyFilesToClipboard(event.entities);
      emit(state.copyWith(
        error: null,
        clipboardRevision: state.clipboardRevision + 1,
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Error copying: ${e.toString()}'));
    }
  }

  void _onCut(
    FileOperationsCut event,
    Emitter<FileOperationsState> emit,
  ) {
    try {
      FileOperations().cutFilesToClipboard(event.entities);
      emit(state.copyWith(
        error: null,
        clipboardRevision: state.clipboardRevision + 1,
      ));
    } catch (e) {
      emit(state.copyWith(error: 'Error cutting: ${e.toString()}'));
    }
  }

  Future<void> _onPaste(
    FileOperationsPaste event,
    Emitter<FileOperationsState> emit,
  ) async {
    if (!FileOperations().hasClipboardItem) {
      emit(state.copyWith(error: 'Nothing to paste — clipboard is empty'));
      return;
    }

    emit(state.copyWith(isProcessing: true));

    final isCut = FileOperations().isCutOperation;
    final itemCount = FileOperations().clipboardItemCount;
    final clipboardItems = FileOperations().clipboardItems;
    final opType = isCut ? 'Moving' : 'Copying';
    final firstItemPath =
        clipboardItems.isNotEmpty ? clipboardItems.first.path : null;
    final firstItemName =
        firstItemPath == null ? null : path.basename(firstItemPath);

    final progressId = _progressController.begin(
      title: itemCount == 1 && firstItemName != null
          ? '$opType "$firstItemName"'
          : '$opType $itemCount items',
      total: itemCount,
      detail: _pasteDetail(
        action: opType,
        sourcePath: firstItemPath,
        destinationPath: event.destinationPath,
        itemCount: itemCount,
      ),
      kind: isCut ? OperationProgressKind.move : OperationProgressKind.copy,
      sourcePath: firstItemPath,
      destinationPath: event.destinationPath,
    );

    try {
      await FileOperations().pasteFromClipboard(
        event.destinationPath,
        onProgress: (completed, total) {
          _progressController.update(
            progressId,
            completed: completed,
            detail:
                '$opType item $completed of $total to ${event.destinationPath}',
          );
        },
      );

      if (isCut) {
        final movedSourcePaths = <String>[];
        for (final item in clipboardItems) {
          final type = await FileSystemEntity.type(
            item.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.notFound) {
            movedSourcePaths.add(item.path);
          }
        }
        DirectoryListingCacheService.instance.removePaths(movedSourcePaths);
      }

      _progressController.succeed(
        progressId,
        detail:
            '${isCut ? 'Moved' : 'Copied'} $itemCount item${itemCount > 1 ? 's' : ''} to ${event.destinationPath}',
      );

      emit(state.copyWith(
        isProcessing: false,
        clipboardRevision: state.clipboardRevision + 1,
      ));

      // Refresh the navigation bloc
      final navState = navigationBloc.state;
      navigationBloc.add(
        FileNavigationRefresh(navState.currentPath.path),
      );
    } catch (e) {
      _progressController.fail(progressId, detail: 'Error: ${e.toString()}');
      emit(state.copyWith(
        isProcessing: false,
        error: 'Error pasting: ${e.toString()}',
      ));
    }
  }

  Future<void> _onDeleteFiles(
    FileOperationsDeleteFiles event,
    Emitter<FileOperationsState> emit,
  ) async {
    final targetPaths = event.filePaths.toSet();
    if (targetPaths.isEmpty) return;
    emit(state.copyWith(
      error: null,
      retryableElevatedDeletePaths: const <String>[],
    ));
    final firstPath = event.filePaths.first;
    final destinationLabel = event.permanent ? 'permanently' : 'to Trash Bin';

    final progressId = _progressController.begin(
      title: event.filePaths.length == 1
          ? 'Deleting "${path.basename(firstPath)}" $destinationLabel'
          : 'Deleting ${event.filePaths.length} files $destinationLabel',
      total: event.filePaths.length,
      detail: _deleteDetail(
        action: event.permanent ? 'Permanent delete' : 'Move to Trash Bin',
        firstPath: firstPath,
        itemCount: event.filePaths.length,
      ),
      showModal: true,
      kind: OperationProgressKind.delete,
      sourcePath: firstPath,
    );

    final trashManager = TrashManager();
    int completed = 0;
    final List<String> failed = [];
    final failureErrors = <String, Object>{};
    final progressThrottle = _ProgressUpdateThrottle();

    navigationBloc.add(FileNavigationRemovePaths(targetPaths));

    final pathsList = event.filePaths.toList(growable: false);
    final Set<String> succeededSet = event.permanent
        ? await trashManager.deleteMultiplePermanently(
            pathsList,
            onChunkDone: (done, total) {
              completed = done;
              progressThrottle.maybeUpdate(
                completed: completed,
                total: total,
                update: () => _progressController.update(
                  progressId,
                  completed: completed,
                  detail: 'Permanently deleted $completed of $total',
                ),
              );
            },
            onError: (path, error) => failureErrors[path] = error,
          )
        : await trashManager.moveMultipleToTrashBatched(
            pathsList,
            onChunkDone: (done, total) {
              completed = done;
              progressThrottle.maybeUpdate(
                completed: completed,
                total: total,
                update: () => _progressController.update(
                  progressId,
                  completed: completed,
                  detail: 'Moved to Trash Bin $completed of $total',
                ),
              );
            },
          );
    for (final p in pathsList) {
      if (!succeededSet.contains(p)) failed.add(p);
    }
    completed = pathsList.length;

    if (failed.isNotEmpty) {
      final failureMessage = formatDeleteFailure(
        failedPaths: failed,
        errorsByPath: failureErrors,
      );
      _progressController.fail(
        progressId,
        detail: failureMessage,
      );
      emit(state.copyWith(
        error: failureMessage,
        retryableElevatedDeletePaths: event.permanent
            ? _accessDeniedPaths(failed, failureErrors)
            : const <String>[],
      ));
    } else {
      _progressController.succeed(
        progressId,
        detail:
            '${event.permanent ? 'Permanently deleted' : 'Moved to Trash Bin'} ${event.filePaths.length} file${event.filePaths.length > 1 ? 's' : ''}',
      );
      emit(state.copyWith(
        error: null,
        retryableElevatedDeletePaths: const <String>[],
      ));
    }

    // Refresh
    final navState = navigationBloc.state;
    navigationBloc.add(FileNavigationRefresh(navState.currentPath.path));
  }

  Future<void> _onDeleteItems(
    FileOperationsDeleteItems event,
    Emitter<FileOperationsState> emit,
  ) async {
    final Set<String> targets = {...event.filePaths, ...event.folderPaths};
    if (targets.isEmpty) return;
    emit(state.copyWith(
      error: null,
      retryableElevatedDeletePaths: const <String>[],
    ));

    final total = event.filePaths.length + event.folderPaths.length;
    final orderedTargets = <String>[...event.filePaths, ...event.folderPaths];
    final firstPath = orderedTargets.first;
    final title = event.permanent
        ? (total == 1
            ? 'Deleting "${path.basename(firstPath)}" permanently'
            : 'Deleting $total items permanently')
        : (total == 1
            ? 'Moving "${path.basename(firstPath)}" to Trash Bin'
            : 'Moving $total items to Trash Bin');

    final progressId = _progressController.begin(
      title: title,
      total: total,
      detail: _deleteDetail(
        action: event.permanent ? 'Permanent delete' : 'Move to Trash Bin',
        firstPath: firstPath,
        itemCount: total,
      ),
      showModal: true,
      kind: OperationProgressKind.delete,
      sourcePath: firstPath,
    );

    final trashManager = TrashManager();
    int completed = 0;
    final List<String> failed = [];
    final failureErrors = <String, Object>{};
    final progressThrottle = _ProgressUpdateThrottle();

    navigationBloc.add(FileNavigationRemovePaths(targets));

    // Combine files + folders into a single batch — SHFileOperationW handles
    // both in one shell call, much faster than per-item Dart deletes.
    final pathsList = <String>[
      ...event.filePaths,
      ...event.folderPaths,
    ];

    final Set<String> succeededSet = event.permanent
        ? await trashManager.deleteMultiplePermanently(
            pathsList,
            onChunkDone: (done, t) {
              completed = done;
              progressThrottle.maybeUpdate(
                completed: completed,
                total: t,
                update: () => _progressController.update(
                  progressId,
                  completed: completed,
                  detail: 'Permanently deleted $completed of $t',
                ),
              );
            },
            onError: (path, error) => failureErrors[path] = error,
          )
        : await trashManager.moveMultipleToTrashBatched(
            pathsList,
            onChunkDone: (done, t) {
              completed = done;
              progressThrottle.maybeUpdate(
                completed: completed,
                total: t,
                update: () => _progressController.update(
                  progressId,
                  completed: completed,
                  detail: 'Moved to Trash Bin $completed of $t',
                ),
              );
            },
          );
    for (final p in pathsList) {
      if (!succeededSet.contains(p)) failed.add(p);
    }
    completed = pathsList.length;

    final successfulDeletes = targets.difference(failed.toSet());
    if (successfulDeletes.isNotEmpty && failed.isNotEmpty) {
      navigationBloc.add(FileNavigationRemovePaths(successfulDeletes));
    }

    if (failed.isNotEmpty) {
      final failureMessage = formatDeleteFailure(
        failedPaths: failed,
        errorsByPath: failureErrors,
      );
      _progressController.fail(
        progressId,
        detail: failureMessage,
      );
      emit(state.copyWith(
        error: failureMessage,
        retryableElevatedDeletePaths: event.permanent
            ? _accessDeniedPaths(failed, failureErrors)
            : const <String>[],
      ));
    } else {
      _progressController.succeed(
        progressId,
        detail:
            '${event.permanent ? 'Permanently deleted' : 'Moved to Trash Bin'} $total item${total > 1 ? 's' : ''}',
      );
      emit(state.copyWith(
        error: null,
        retryableElevatedDeletePaths: const <String>[],
      ));
    }

    final navState = navigationBloc.state;
    navigationBloc.add(FileNavigationRefresh(navState.currentPath.path));
  }

  Future<void> _onRetryDeleteAsAdministrator(
    FileOperationsRetryDeleteAsAdministrator event,
    Emitter<FileOperationsState> emit,
  ) async {
    final exactRetryPaths = retainApprovedRetryPaths(
      approvedPaths: state.retryableElevatedDeletePaths,
      requestedPaths: event.failedPaths,
    ).toSet();
    if (exactRetryPaths.isEmpty) return;

    emit(state.copyWith(
      error: null,
      isProcessing: true,
      retryableElevatedDeletePaths: const <String>[],
    ));

    final paths = exactRetryPaths.toList(growable: false);
    final progressId = _progressController.begin(
      title: paths.length == 1
          ? 'Deleting "${path.basename(paths.first)}" as administrator'
          : 'Deleting ${paths.length} items as administrator',
      total: paths.length,
      detail: 'Waiting for Windows administrator approval',
      isIndeterminate: true,
      kind: OperationProgressKind.delete,
      sourcePath: paths.first,
    );

    final succeeded =
        await TrashManager().retryPermanentDeleteAsAdministrator(paths);
    final failed = paths.where((path) => !succeeded.contains(path)).toList();

    if (succeeded.isNotEmpty) {
      navigationBloc.add(FileNavigationRemovePaths(succeeded));
    }

    if (failed.isEmpty) {
      final message = paths.length == 1
          ? 'Deleted "${paths.first}" as administrator.'
          : 'Deleted ${paths.length} items as administrator.';
      _progressController.succeed(progressId, detail: message);
      emit(state.copyWith(
        error: null,
        isProcessing: false,
        retryableElevatedDeletePaths: const <String>[],
      ));
    } else {
      final message = failed.length == 1
          ? 'Administrator delete was cancelled or failed for "${failed.first}".'
          : 'Administrator delete was cancelled or failed for ${failed.length} items.';
      _progressController.fail(progressId, detail: message);
      emit(state.copyWith(
        error: message,
        isProcessing: false,
        retryableElevatedDeletePaths: failed,
      ));
    }

    final navState = navigationBloc.state;
    navigationBloc.add(FileNavigationRefresh(navState.currentPath.path));
  }

  Future<void> _onRename(
    FileOperationsRename event,
    Emitter<FileOperationsState> emit,
  ) async {
    try {
      await FileOperations().rename(event.entity, event.newName);
      emit(state.copyWith(error: null));

      // Refresh navigation bloc
      final navState = navigationBloc.state;
      navigationBloc.add(FileNavigationRefresh(navState.currentPath.path));
    } catch (e) {
      emit(state.copyWith(error: 'Error renaming: ${e.toString()}'));
    }
  }

  void _onClearClipboard(
    FileOperationsClearClipboard event,
    Emitter<FileOperationsState> emit,
  ) {
    FileOperations().clearClipboard();
    emit(state.copyWith(clipboardRevision: state.clipboardRevision + 1));
  }

  String _deleteDetail({
    required String action,
    required String firstPath,
    required int itemCount,
  }) {
    final parent = path.dirname(firstPath);
    final itemLabel = itemCount == 1
        ? path.basename(firstPath)
        : '${path.basename(firstPath)} and ${itemCount - 1} more';
    return '$action: $itemLabel from $parent';
  }

  String _pasteDetail({
    required String action,
    required String? sourcePath,
    required String destinationPath,
    required int itemCount,
  }) {
    if (sourcePath == null) {
      return '$action $itemCount item${itemCount > 1 ? 's' : ''} to $destinationPath';
    }
    final sourceLabel = itemCount == 1
        ? path.basename(sourcePath)
        : '${path.basename(sourcePath)} and ${itemCount - 1} more';
    return '$action $sourceLabel from ${path.dirname(sourcePath)} to $destinationPath';
  }

  static String formatDeleteFailure({
    required List<String> failedPaths,
    required Map<String, Object> errorsByPath,
  }) {
    if (failedPaths.isEmpty) return 'Delete failed';

    final firstPath = failedPaths.first;
    final error = errorsByPath[firstPath];
    final itemLabel = failedPaths.length == 1
        ? '"$firstPath"'
        : '${failedPaths.length} items; first failure: "$firstPath"';

    if (error is FileSystemException && error.osError?.errorCode == 5) {
      return 'Could not delete $itemLabel: Access denied. Check folder permissions or run the app as administrator.';
    }

    if (error is FileSystemException) {
      final reason = error.osError?.message.trim();
      if (reason != null && reason.isNotEmpty) {
        return 'Could not delete $itemLabel: $reason.';
      }
    }

    return 'Could not delete $itemLabel.';
  }

  static List<String> _accessDeniedPaths(
    List<String> failedPaths,
    Map<String, Object> errorsByPath,
  ) {
    return failedPaths.where((path) {
      final error = errorsByPath[path];
      return error is FileSystemException && error.osError?.errorCode == 5;
    }).toList(growable: false);
  }

  static List<String> retainApprovedRetryPaths({
    required List<String> approvedPaths,
    required List<String> requestedPaths,
  }) {
    final approved = approvedPaths.toSet();
    return requestedPaths
        .where(approved.contains)
        .toSet()
        .toList(growable: false);
  }
}

class _ProgressUpdateThrottle {
  static const int _minimumItemInterval = 10;
  static const Duration _minimumTimeInterval = Duration(milliseconds: 120);

  final Stopwatch _stopwatch = Stopwatch()..start();
  int _lastCompleted = 0;

  void maybeUpdate({
    required int completed,
    required int total,
    required void Function() update,
  }) {
    final isFirst = completed == 1;
    final isLast = completed >= total;
    final enoughItems = completed - _lastCompleted >= _minimumItemInterval;
    final enoughTime = _stopwatch.elapsed >= _minimumTimeInterval;

    if (!isFirst && !isLast && !enoughItems && !enoughTime) {
      return;
    }

    _lastCompleted = completed;
    _stopwatch
      ..reset()
      ..start();
    update();
  }
}
