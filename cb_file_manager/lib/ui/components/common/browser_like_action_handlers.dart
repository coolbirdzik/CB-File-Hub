// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:cb_file_manager/ui/controllers/file_operations_handler.dart';
import 'package:cb_file_manager/ui/controllers/inline_rename_controller.dart';
import 'package:cb_file_manager/ui/dialogs/delete_confirmation_dialog.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

class BrowserLikeActionHandlers {
  static Future<bool> showConfirmationDialog({
    required BuildContext context,
    required Widget dialog,
    Future<bool?> Function(BuildContext context, Widget dialog)?
        showDialogWithWidget,
  }) async {
    final confirmed = showDialogWithWidget == null
        ? await showDialog<bool>(
            context: context,
            builder: (_) => dialog,
          )
        : await showDialogWithWidget(context, dialog);
    if (!context.mounted) {
      return false;
    }
    return confirmed == true;
  }

  static Future<int> runBatchOperation<T>({
    required Iterable<T> items,
    required Future<bool> Function(T item) operation,
    void Function(T item, Object error)? onItemError,
  }) async {
    var successCount = 0;
    for (final item in items) {
      try {
        final success = await operation(item);
        if (success) {
          successCount++;
        }
      } catch (error) {
        onItemError?.call(item, error);
      }
    }
    return successCount;
  }

  static Future<void> handleDelete({
    required BuildContext context,
    required FolderListBloc folderListBloc,
    required SelectionBloc selectionBloc,
    required String? focusedPath,
    required bool permanent,
    required VoidCallback onClearSelection,
    void Function(Set<String> deletedPaths, String? nextFocusPath)?
        onDeleteConfirmed,
  }) {
    final selectionState = selectionBloc.state;
    return FileOperationsHandler.handleDelete(
      context: context,
      folderListBloc: folderListBloc,
      selectedFiles: selectionState.selectedFilePaths.toList(),
      selectedFolders: selectionState.selectedFolderPaths.toList(),
      selectionBloc: selectionBloc,
      focusedPath: focusedPath,
      permanent: permanent,
      onClearSelection: onClearSelection,
      onDeleteConfirmed: onDeleteConfirmed,
    );
  }

  static void selectAll({
    required SelectionBloc selectionBloc,
    required Iterable<String> allFilePaths,
    required Iterable<String> allFolderPaths,
    VoidCallback? ensureSelectionMode,
  }) {
    if (!selectionBloc.state.isSelectionMode) {
      ensureSelectionMode?.call();
    }

    selectionBloc.add(SelectAll(
      allFilePaths: allFilePaths.toList(),
      allFolderPaths: allFolderPaths.toList(),
    ));
  }

  static void copySelectionOrFocused({
    required BuildContext context,
    required SelectionState selectionState,
    required String? focusedPath,
    FolderListBloc? folderListBloc,
  }) {
    final focusedEntity = _focusedEntity(focusedPath);
    if (_hasNoSelection(selectionState) && focusedEntity != null) {
      FileOperationsHandler.copyToClipboard(
        context: context,
        entity: focusedEntity,
        folderListBloc: folderListBloc,
      );
      return;
    }

    final entities = _selectedEntities(selectionState);
    if (entities.isEmpty) return;
    FileOperationsHandler.copyFilesToClipboard(
      context: context,
      entities: entities,
      folderListBloc: folderListBloc,
    );
  }

  static void cutSelectionOrFocused({
    required BuildContext context,
    required SelectionState selectionState,
    required String? focusedPath,
    FolderListBloc? folderListBloc,
  }) {
    final focusedEntity = _focusedEntity(focusedPath);
    if (_hasNoSelection(selectionState) && focusedEntity != null) {
      FileOperationsHandler.cutToClipboard(
        context: context,
        entity: focusedEntity,
        folderListBloc: folderListBloc,
      );
      return;
    }

    final entities = _selectedEntities(selectionState);
    if (entities.isEmpty) return;
    FileOperationsHandler.cutFilesToClipboard(
      context: context,
      entities: entities,
      folderListBloc: folderListBloc,
    );
  }

  static void pasteInto({
    required BuildContext context,
    required String destinationPath,
    FolderListBloc? folderListBloc,
  }) {
    FileOperationsHandler.pasteFromClipboard(
      context: context,
      destinationPath: destinationPath,
      folderListBloc: folderListBloc,
    );
  }

  static Future<void> renameSelectionOrFocused({
    required BuildContext context,
    required SelectionState selectionState,
    required String? focusedPath,
    required bool isDesktop,
    required InlineRenameController inlineRenameController,
    FolderListBloc? folderListBloc,
    FocusNode? refocusNode,
    VoidCallback? onInlineRenameStarted,
  }) async {
    final entity = _primaryEntity(selectionState, focusedPath);
    if (entity == null) return;

    if (isDesktop) {
      inlineRenameController.startRename(
        entity.path,
        onCancelled: () => refocusNode?.requestFocus(),
        onCommitted: () => refocusNode?.requestFocus(),
      );
      onInlineRenameStarted?.call();
      return;
    }

    await FileOperationsHandler.showRenameDialog(
      context: context,
      entity: entity,
      folderListBloc: folderListBloc,
    );
  }

  static Future<Set<String>> confirmAndMoveFilesToTrash({
    required BuildContext context,
    required List<String> filePaths,
    Future<bool?> Function(BuildContext context, Widget dialog)?
        showDialogWithWidget,
    required Future<void> Function(String filePath) onMoved,
    Future<void> Function(Set<String> deletedPaths)? onAfterSuccess,
    void Function(String filePath, Object error)? onMoveError,
  }) async {
    if (filePaths.isEmpty) {
      return <String>{};
    }

    final l10n = AppLocalizations.of(context);
    if (l10n == null) {
      return <String>{};
    }

    final totalCount = filePaths.length;
    final firstName = path.basename(filePaths.first);
    final dialog = DeleteConfirmationDialog(
      title: l10n.moveToTrash,
      message: totalCount == 1
          ? l10n.moveToTrashConfirmMessage(firstName)
          : l10n.moveItemsToTrashConfirmation(totalCount, l10n.items),
      confirmText: l10n.moveToTrash,
      cancelText: l10n.cancel,
      previewPaths: filePaths.take(4).toList(),
    );

    final confirmed = await showConfirmationDialog(
      context: context,
      dialog: dialog,
      showDialogWithWidget: showDialogWithWidget,
    );
    if (!confirmed) {
      return <String>{};
    }

    final deletedPaths = <String>{};
    final trashManager = TrashManager();
    await runBatchOperation<String>(
      items: filePaths,
      operation: (filePath) async {
        final moved = await trashManager.moveToTrash(filePath);
        if (!moved) {
          return false;
        }
        deletedPaths.add(filePath);
        await onMoved(filePath);
        return true;
      },
      onItemError: onMoveError,
    );

    if (!context.mounted) {
      return deletedPaths;
    }

    if (deletedPaths.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(l10n.failedToDelete(path.basename(filePaths.first))),
        ),
      );
      return deletedPaths;
    }

    if (onAfterSuccess != null) {
      await onAfterSuccess(deletedPaths);
    }

    if (!context.mounted) {
      return deletedPaths;
    }

    final message = deletedPaths.length == 1
        ? l10n.movedToTrash(path.basename(deletedPaths.first))
        : l10n.movedToTrash('${deletedPaths.length} ${l10n.items}');
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );

    return deletedPaths;
  }

  static bool _hasNoSelection(SelectionState selectionState) {
    return selectionState.selectedFilePaths.isEmpty &&
        selectionState.selectedFolderPaths.isEmpty;
  }

  static FileSystemEntity? _focusedEntity(String? focusedPath) {
    if (focusedPath == null || focusedPath.isEmpty) return null;
    final type = FileSystemEntity.typeSync(focusedPath);
    if (type == FileSystemEntityType.notFound) return null;
    return type == FileSystemEntityType.directory
        ? Directory(focusedPath)
        : File(focusedPath);
  }

  static FileSystemEntity? _primaryEntity(
    SelectionState selectionState,
    String? focusedPath,
  ) {
    final focusedEntity = _focusedEntity(focusedPath);
    if (focusedEntity != null) return focusedEntity;

    if (selectionState.selectedFilePaths.isNotEmpty) {
      return File(selectionState.selectedFilePaths.first);
    }
    if (selectionState.selectedFolderPaths.isNotEmpty) {
      return Directory(selectionState.selectedFolderPaths.first);
    }
    return null;
  }

  static List<FileSystemEntity> _selectedEntities(
      SelectionState selectionState) {
    final allPaths = <String>[
      ...selectionState.selectedFilePaths,
      ...selectionState.selectedFolderPaths,
    ];
    return allPaths.map((path) {
      return FileSystemEntity.typeSync(path) == FileSystemEntityType.directory
          ? Directory(path) as FileSystemEntity
          : File(path) as FileSystemEntity;
    }).toList();
  }
}
