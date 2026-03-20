import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/image_viewer_screen.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/video_player_full_screen.dart';
import 'package:cb_file_manager/ui/dialogs/open_with_dialog.dart';
import 'package:cb_file_manager/ui/dialogs/delete_confirmation_dialog.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';

/// Handles file operations such as opening files with appropriate viewers
class FileOperationsHandler {
  static List<FileSystemEntity> _getNavigableItems(FolderListState state) {
    if (state.currentSearchTag != null || state.currentSearchQuery != null) {
      return List<FileSystemEntity>.from(state.searchResults);
    }

    final currentFilter = state.currentFilter;
    if (currentFilter != null && currentFilter.isNotEmpty) {
      return List<FileSystemEntity>.from(state.filteredFiles);
    }

    return [
      ...state.folders.whereType<FileSystemEntity>(),
      ...state.files.whereType<FileSystemEntity>(),
    ];
  }

  @visibleForTesting
  static String? computeNextFocusPathAfterDelete({
    required FolderListState state,
    required Set<String> pathsToDelete,
    String? anchorPath,
  }) {
    final items = _getNavigableItems(state);
    if (items.isEmpty) return null;

    final orderedPaths = items.map((e) => e.path).toList(growable: false);

    final String? effectiveAnchor = () {
      if (anchorPath != null && orderedPaths.contains(anchorPath)) {
        return anchorPath;
      }
      for (final p in orderedPaths) {
        if (pathsToDelete.contains(p)) return p;
      }
      return null;
    }();

    if (effectiveAnchor == null) {
      for (final p in orderedPaths) {
        if (!pathsToDelete.contains(p)) return p;
      }
      return null;
    }

    final int anchorIndex = orderedPaths.indexOf(effectiveAnchor);
    if (anchorIndex < 0) return null;

    for (int i = anchorIndex + 1; i < orderedPaths.length; i++) {
      final p = orderedPaths[i];
      if (!pathsToDelete.contains(p)) return p;
    }

    for (int i = anchorIndex - 1; i >= 0; i--) {
      final p = orderedPaths[i];
      if (!pathsToDelete.contains(p)) return p;
    }

    return null;
  }

  static String _entityBaseName(FileSystemEntity entity) {
    final normalized = path.normalize(entity.path);
    final name = path.basename(normalized);
    return name.isEmpty ? normalized : name;
  }

  static SelectionState? _tryGetSelectionState(
    BuildContext context, {
    required SelectionBloc? selectionBloc,
  }) {
    if (selectionBloc != null) return selectionBloc.state;
    try {
      return context.read<SelectionBloc>().state;
    } catch (_) {
      return null;
    }
  }

  static void _tryRestoreSelectionAfterViewer(
    BuildContext context, {
    required SelectionState? snapshot,
    required SelectionBloc? selectionBloc,
  }) {
    if (snapshot == null) return;
    if (snapshot.allSelectedPaths.isEmpty) return;

    if (!context.mounted) return;

    final SelectionBloc bloc;
    try {
      bloc = selectionBloc ?? context.read<SelectionBloc>();
    } catch (_) {
      return;
    }

    final current = bloc.state;
    if (current.selectedFilePaths.length == snapshot.selectedFilePaths.length &&
        current.selectedFolderPaths.length ==
            snapshot.selectedFolderPaths.length &&
        current.selectedFilePaths.containsAll(snapshot.selectedFilePaths) &&
        current.selectedFolderPaths.containsAll(snapshot.selectedFolderPaths) &&
        current.lastSelectedPath == snapshot.lastSelectedPath) {
      return;
    }

    final List<String> filePaths = snapshot.selectedFilePaths.toList();
    final List<String> folderPaths = snapshot.selectedFolderPaths.toList();

    final last = snapshot.lastSelectedPath;
    if (last != null && snapshot.selectedFilePaths.contains(last)) {
      filePaths.remove(last);
      filePaths.add(last);
    } else if (last != null && snapshot.selectedFolderPaths.contains(last)) {
      folderPaths.remove(last);
      folderPaths.add(last);
    }

    bloc.add(SelectItemsInRect(
      folderPaths: folderPaths.toSet(),
      filePaths: filePaths.toSet(),
      isCtrlPressed: false,
      isShiftPressed: true,
    ));
  }

  /// Handle delete operation - shows confirmation dialog and dispatches delete event
  static Future<void> handleDelete({
    required BuildContext context,
    required FolderListBloc folderListBloc,
    required List<String> selectedFiles,
    required List<String> selectedFolders,
    SelectionBloc? selectionBloc,
    String? focusedPath,
    required bool permanent,
    required VoidCallback onClearSelection,
  }) async {
    // Clone lists to avoid modifying the original lists from state
    final filesToDelete = List<String>.from(selectedFiles);
    final foldersToDelete = List<String>.from(selectedFolders);

    // If no selection, check focused item
    if (filesToDelete.isEmpty &&
        foldersToDelete.isEmpty &&
        focusedPath != null) {
      final focusedType =
          FileSystemEntity.typeSync(focusedPath, followLinks: false);
      if (focusedType == FileSystemEntityType.directory) {
        foldersToDelete.add(focusedPath);
      } else {
        filesToDelete.add(focusedPath);
      }
    }

    if (filesToDelete.isEmpty && foldersToDelete.isEmpty) {
      debugPrint('FileOperationsHandler.handleDelete - no items to delete');
      return;
    }

    final localizations = AppLocalizations.of(context);
    if (localizations == null) {
      debugPrint('FileOperationsHandler.handleDelete - localizations is null!');
      return;
    }

    final stateBeforeDelete = folderListBloc.state;
    final pathsToDelete = <String>{...filesToDelete, ...foldersToDelete};
    final nextFocusPath = selectionBloc == null
        ? null
        : computeNextFocusPathAfterDelete(
            state: stateBeforeDelete,
            pathsToDelete: pathsToDelete,
            anchorPath: focusedPath,
          );

    final totalCount = filesToDelete.length + foldersToDelete.length;
    final String firstItemName = filesToDelete.isNotEmpty
        ? path.basename(filesToDelete.first)
        : path.basename(foldersToDelete.first);

    debugPrint(
        'FileOperationsHandler.handleDelete - permanent: $permanent, totalCount: $totalCount');
    debugPrint('  First item: $firstItemName');

    if (permanent) {
      // Show permanent delete dialog with keyboard support
      debugPrint('Showing permanent delete dialog');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => DeleteConfirmationDialog(
          title: localizations.permanentDeleteTitle,
          message: totalCount == 1
              ? localizations.confirmDeletePermanent(firstItemName)
              : localizations.confirmDeletePermanentMultiple(totalCount),
          confirmText: localizations.deleteTitle,
          cancelText: localizations.cancel,
        ),
      );

      debugPrint('Permanent delete dialog result: $confirmed');

      if (confirmed == true) {
        folderListBloc.add(FolderListDeleteItems(
          filePaths: filesToDelete,
          folderPaths: foldersToDelete,
          permanent: true,
        ));
        onClearSelection();
        if (selectionBloc != null && nextFocusPath != null) {
          final nextType =
              FileSystemEntity.typeSync(nextFocusPath, followLinks: false);
          if (nextType == FileSystemEntityType.directory) {
            selectionBloc.add(ToggleFolderSelection(
              nextFocusPath,
              shiftSelect: false,
              ctrlSelect: false,
            ));
          } else {
            selectionBloc.add(ToggleFileSelection(
              nextFocusPath,
              shiftSelect: false,
              ctrlSelect: false,
            ));
          }
        }
      }
    } else {
      // Show trash delete dialog with keyboard support
      debugPrint('Showing trash delete dialog');
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => DeleteConfirmationDialog(
          title: localizations.deleteTitle,
          message: totalCount == 1
              ? localizations.moveToTrashConfirmMessage(firstItemName)
              : localizations.moveItemsToTrashConfirmation(
                  totalCount, localizations.items),
          confirmText: localizations.deleteTitle,
          cancelText: localizations.cancel,
        ),
      );

      debugPrint('Trash delete dialog result: $confirmed');

      if (confirmed == true) {
        folderListBloc.add(FolderListDeleteItems(
          filePaths: filesToDelete,
          folderPaths: foldersToDelete,
          permanent: false,
        ));
        onClearSelection();
        if (selectionBloc != null && nextFocusPath != null) {
          final nextType =
              FileSystemEntity.typeSync(nextFocusPath, followLinks: false);
          if (nextType == FileSystemEntityType.directory) {
            selectionBloc.add(ToggleFolderSelection(
              nextFocusPath,
              shiftSelect: false,
              ctrlSelect: false,
            ));
          } else {
            selectionBloc.add(ToggleFileSelection(
              nextFocusPath,
              shiftSelect: false,
              ctrlSelect: false,
            ));
          }
        }
      }
    }
  }

  static void copyToClipboard({
    required BuildContext context,
    required FileSystemEntity entity,
    FolderListBloc? folderListBloc,
  }) {
    final bloc = folderListBloc ?? context.read<FolderListBloc>();
    final l10n = AppLocalizations.of(context)!;
    final name = _entityBaseName(entity);
    bloc.add(CopyFile(entity));
    _showSnackBarSafe(context, l10n.copiedToClipboard(name));
  }

  static void copyFilesToClipboard({
    required BuildContext context,
    required List<FileSystemEntity> entities,
    FolderListBloc? folderListBloc,
  }) {
    if (entities.isEmpty) return;
    final bloc = folderListBloc ?? context.read<FolderListBloc>();
    final l10n = AppLocalizations.of(context)!;
    bloc.add(CopyFiles(entities));
    final message = entities.length == 1
        ? l10n.copiedToClipboard(_entityBaseName(entities.first))
        : '${entities.length} items copied to clipboard';
    _showSnackBarSafe(context, message);
  }

  static void cutToClipboard({
    required BuildContext context,
    required FileSystemEntity entity,
    FolderListBloc? folderListBloc,
  }) {
    final bloc = folderListBloc ?? context.read<FolderListBloc>();
    final l10n = AppLocalizations.of(context)!;
    final name = _entityBaseName(entity);
    bloc.add(CutFile(entity));
    _showSnackBarSafe(context, l10n.cutToClipboard(name));
  }

  static void cutFilesToClipboard({
    required BuildContext context,
    required List<FileSystemEntity> entities,
    FolderListBloc? folderListBloc,
  }) {
    if (entities.isEmpty) return;
    final bloc = folderListBloc ?? context.read<FolderListBloc>();
    final l10n = AppLocalizations.of(context)!;
    bloc.add(CutFiles(entities));
    final message = entities.length == 1
        ? l10n.cutToClipboard(_entityBaseName(entities.first))
        : '${entities.length} items cut to clipboard';
    _showSnackBarSafe(context, message);
  }

  static void pasteFromClipboard({
    required BuildContext context,
    required String destinationPath,
    FolderListBloc? folderListBloc,
  }) {
    final bloc = folderListBloc ?? context.read<FolderListBloc>();
    final l10n = AppLocalizations.of(context)!;
    bloc.add(PasteFile(destinationPath));
    _showSnackBarSafe(context, l10n.pasting);
  }

  /// Safely shows a snackbar, falling back to debugPrint if no ScaffoldMessenger is available.
  static void _showSnackBarSafe(BuildContext context, String message) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      debugPrint('FileOperationsHandler: ScaffoldMessenger unavailable — $message');
    }
  }

  static Future<void> showRenameDialog({
    required BuildContext context,
    required FileSystemEntity entity,
    FolderListBloc? folderListBloc,
  }) async {
    final bloc = folderListBloc ?? context.read<FolderListBloc>();
    final l10n = AppLocalizations.of(context)!;
    final currentName = _entityBaseName(entity);
    final isFile = entity is File;

    final controller = TextEditingController(
      text: isFile ? path.basenameWithoutExtension(currentName) : currentName,
    );

    if (isFile) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isFile ? l10n.renameFileTitle : l10n.renameFolderTitle),
        content: isFile
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l10n.currentNameLabel(currentName)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: l10n.newNameLabel,
                      border: const OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                ],
              )
            : TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: l10n.newNameLabel,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel.toUpperCase()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.rename.toUpperCase()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final rawName = controller.text.trim();
    final newName = isFile ? rawName + path.extension(currentName) : rawName;

    if (newName.isEmpty || newName == currentName) return;

    bloc.add(RenameFileOrFolder(entity, newName));

    _showSnackBarSafe(
      context,
      isFile ? l10n.renamedFileTo(newName) : l10n.renamedFolderTo(newName),
    );
  }

  /// Handle file tap - opens the file with the appropriate viewer based on file type
  static void onFileTap({
    required BuildContext context,
    required File file,
    required FolderListBloc folderListBloc,
    SelectionBloc? selectionBloc,
    String? currentFilter,
    String? currentSearchTag,
  }) {
    // Stop any ongoing thumbnail processing when opening a file
    VideoThumbnailHelper.stopAllProcessing();

    // Check file type using utility
    final isVideo = FileTypeUtils.isVideoFile(file.path);
    final isImage = FileTypeUtils.isImageFile(file.path);

    // Open file based on file type
    if (isVideo) {
      final currentSelection = _tryGetSelectionState(
        context,
        selectionBloc: selectionBloc,
      );
      final SelectionState selectionSnapshot = (currentSelection == null ||
              currentSelection.allSelectedPaths.isEmpty)
          ? SelectionState(
              selectedFilePaths: <String>{file.path},
              selectedFolderPaths: const <String>{},
              isSelectionMode: true,
              lastSelectedPath: file.path,
            )
          : currentSelection;
      // Priority:
      // 1) User-selected preferred external app for video (if set)
      // 2) System default app when setting enabled
      // 3) In-app player (default)
      ExternalAppHelper.openWithPreferredVideoApp(file.path)
          .then((openedPreferred) {
        if (openedPreferred) return;

        locator<UserPreferences>()
            .getUseSystemDefaultForVideo()
            .then((useSystem) {
          if (useSystem) {
            ExternalAppHelper.openWithSystemDefault(file.path).then((success) {
              if (!success && context.mounted) {
                showDialog(
                  context: context,
                  builder: (context) => OpenWithDialog(filePath: file.path),
                );
              }
            });
          } else {
            if (context.mounted) {
              Navigator.of(context, rootNavigator: true)
                  .push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => VideoPlayerFullScreen(file: file),
                ),
              )
                  .then((_) {
                _tryRestoreSelectionAfterViewer(
                  context,
                  snapshot: selectionSnapshot,
                  selectionBloc: selectionBloc,
                );
              });
            }
          }
        });
      });
    } else if (isImage) {
      // Get all image files in the same directory for gallery navigation
      List<File> imageFiles = [];
      int initialIndex = 0;

      final bool canUseFilteredImages = currentFilter == 'image' &&
          folderListBloc.state.filteredFiles.isNotEmpty;
      final bool canUseFolderImages = currentFilter == null &&
          currentSearchTag == null &&
          folderListBloc.state.files.isNotEmpty;

      if (canUseFilteredImages || canUseFolderImages) {
        final sourceFiles = canUseFilteredImages
            ? folderListBloc.state.filteredFiles
            : folderListBloc.state.files;
        imageFiles = sourceFiles
            .whereType<File>()
            .where((f) => FileTypeUtils.isImageFile(f.path))
            .toList();

        // Find the index of the current file in the imageFiles list
        initialIndex = imageFiles.indexWhere((f) => f.path == file.path);
        if (initialIndex < 0) initialIndex = 0;
      }

      // Open image in our enhanced image viewer with gallery support
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageViewerScreen(
            file: file,
            imageFiles: imageFiles.isNotEmpty ? imageFiles : null,
            initialIndex: initialIndex,
          ),
        ),
      );
    } else {
      // For other file types, open with external app
      // First try to open with the default app
      ExternalAppHelper.openFileWithApp(file.path, 'shell_open')
          .then((success) {
        if (!success && context.mounted) {
          // If that fails, show the open with dialog
          showDialog(
            context: context,
            builder: (context) => OpenWithDialog(filePath: file.path),
          );
        }
      });
    }
  }
}
