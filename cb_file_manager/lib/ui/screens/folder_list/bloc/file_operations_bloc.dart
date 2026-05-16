import 'dart:io';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart'
    show FileOperations;
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:path/path.dart' as path;

import 'file_operations_event.dart';

/// Holds current clipboard state for the file operations layer.
class FileOperationsState extends Equatable {
  final int clipboardRevision;
  final String? error;
  final bool isProcessing;

  const FileOperationsState({
    this.clipboardRevision = 0,
    this.error,
    this.isProcessing = false,
  });

  FileOperationsState copyWith({
    int? clipboardRevision,
    Object? error,
    bool? isProcessing,
  }) {
    return FileOperationsState(
      clipboardRevision: clipboardRevision ?? this.clipboardRevision,
      error: error is String ? error : (error == _unset ? null : this.error),
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }

  static const _unset = Object();

  @override
  List<Object?> get props => [clipboardRevision, error, isProcessing];
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

    for (final filePath in event.filePaths) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          if (event.permanent) {
            await file.delete();
          } else {
            await trashManager.moveToTrash(filePath);
          }
        }
        completed++;
        _progressController.update(
          progressId,
          completed: completed,
          detail:
              '${event.permanent ? 'Permanently deleted' : 'Moved to Trash Bin'}: $filePath',
        );
      } catch (e) {
        failed.add(filePath);
        AppLogger.warning('Delete failed for $filePath: $e');
      }
    }

    if (failed.isNotEmpty) {
      _progressController.fail(
        progressId,
        detail:
            'Failed to delete ${failed.length} item${failed.length > 1 ? 's' : ''}',
      );
      emit(state.copyWith(
        error:
            'Failed to delete ${failed.length} item${failed.length > 1 ? 's' : ''}',
      ));
    } else {
      _progressController.succeed(
        progressId,
        detail:
            '${event.permanent ? 'Permanently deleted' : 'Moved to Trash Bin'} ${event.filePaths.length} file${event.filePaths.length > 1 ? 's' : ''}',
      );
      emit(state.copyWith(error: null));
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

    for (final path in event.filePaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          if (event.permanent) {
            await file.delete();
          } else {
            await trashManager.moveToTrash(path);
          }
        }
        completed++;
        _progressController.update(
          progressId,
          completed: completed,
          detail:
              '${event.permanent ? 'Permanently deleting' : 'Moving to Trash Bin'} file $completed of $total: $path',
        );
      } catch (e) {
        failed.add(path);
        AppLogger.warning('Delete failed for $path: $e');
      }
    }

    for (final path in event.folderPaths) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          if (event.permanent) {
            await dir.delete(recursive: true);
          } else {
            await trashManager.moveToTrash(path);
          }
        }
        completed++;
        _progressController.update(
          progressId,
          completed: completed,
          detail:
              '${event.permanent ? 'Permanently deleting' : 'Moving to Trash Bin'} folder $completed of $total: $path',
        );
      } catch (e) {
        failed.add(path);
        AppLogger.warning('Delete failed for $path: $e');
      }
    }

    final successfulDeletes = targets.difference(failed.toSet());
    if (successfulDeletes.isNotEmpty) {
      navigationBloc.add(FileNavigationRemovePaths(successfulDeletes));
    }

    if (failed.isNotEmpty) {
      _progressController.fail(
        progressId,
        detail:
            'Failed to delete ${failed.length} item${failed.length > 1 ? 's' : ''}',
      );
      emit(state.copyWith(
        error:
            'Failed to delete ${failed.length} item${failed.length > 1 ? 's' : ''}',
      ));
    } else {
      _progressController.succeed(
        progressId,
        detail:
            '${event.permanent ? 'Permanently deleted' : 'Moved to Trash Bin'} $total item${total > 1 ? 's' : ''}',
      );
      emit(state.copyWith(error: null));
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
}
