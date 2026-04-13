import 'dart:io';
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
      return;
    }

    final localizations = AppLocalizations.of(context);
    if (localizations == null) {
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

    if (permanent) {
      // Show permanent delete dialog with keyboard support
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
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      debugPrint('FileOperationsHandler: ScaffoldMessenger unavailable — $message');
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  static Future<void> showRenameDialog({
    required BuildContext context,
    required FileSystemEntity entity,
    FolderListBloc? folderListBloc,
  }) async {
    FolderListBloc? bloc = folderListBloc;
    if (bloc == null) {
      try {
        bloc = context.read<FolderListBloc>();
      } catch (_) {
        bloc = null;
      }
    }
    if (bloc == null) {
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    final preferences = UserPreferences.instance;
    await preferences.init();
    final allowFileExtensionRename =
        await preferences.getAllowFileExtensionRename();
    if (!context.mounted) {
      return;
    }
    final currentName = _entityBaseName(entity);
    final isFile = entity is File;
    final initialValue = isFile && allowFileExtensionRename
        ? currentName
        : path.basenameWithoutExtension(currentName);

    final rawName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameEntityDialog(
        title: isFile ? l10n.renameFileTitle : l10n.renameFolderTitle,
        currentNameLabel: isFile ? l10n.currentNameLabel(currentName) : null,
        newNameLabel: l10n.newNameLabel,
        cancelLabel: l10n.cancel.toUpperCase(),
        confirmLabel: l10n.rename.toUpperCase(),
        initialValue: isFile ? initialValue : currentName,
      ),
    );

    if (rawName == null) {
      return;
    }

    try {
      final newName = _resolveRenameTargetName(
        rawName: rawName.trim(),
        currentName: currentName,
        isFile: isFile,
        allowFileExtensionRename: allowFileExtensionRename,
      );

      if (newName.isEmpty || newName == currentName) return;

      bloc.add(RenameFileOrFolder(entity, newName));

      try {
        scaffoldMessenger?.showSnackBar(
          SnackBar(
            content: Text(isFile
                ? l10n.renamedFileTo(newName)
                : l10n.renamedFolderTo(newName)),
          ),
        );
      } catch (_) {}
    } finally {}
  }

  static String _resolveRenameTargetName({
    required String rawName,
    required String currentName,
    required bool isFile,
    required bool allowFileExtensionRename,
  }) {
    if (!isFile) {
      return rawName;
    }

    if (allowFileExtensionRename) {
      return rawName;
    }

    final extension = path.extension(currentName);
    var baseName = rawName;
    if (extension.isNotEmpty &&
        rawName.toLowerCase().endsWith(extension.toLowerCase())) {
      baseName = rawName.substring(0, rawName.length - extension.length);
    }

    baseName = baseName.trim();
    if (baseName.isEmpty) {
      return '';
    }

    return '$baseName$extension';
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
              // ignore: use_build_context_synchronously
              Navigator.of(context, rootNavigator: true)
                  .push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => VideoPlayerFullScreen(file: file),
                ),
              )
                  .then((_) {
                _tryRestoreSelectionAfterViewer(
                  // ignore: use_build_context_synchronously
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

class _RenameEntityDialog extends StatefulWidget {
  final String title;
  final String? currentNameLabel;
  final String newNameLabel;
  final String cancelLabel;
  final String confirmLabel;
  final String initialValue;

  const _RenameEntityDialog({
    required this.title,
    required this.newNameLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.initialValue,
    this.currentNameLabel,
  });

  @override
  State<_RenameEntityDialog> createState() => _RenameEntityDialogState();
}

class _RenameEntityDialogState extends State<_RenameEntityDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(context, _controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final textField = TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.newNameLabel,
        border: const OutlineInputBorder(),
      ),
      autofocus: true,
      onSubmitted: (_) => _submit(),
    );

    return AlertDialog(
      title: Text(widget.title),
      content: widget.currentNameLabel != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.currentNameLabel!),
                const SizedBox(height: 16),
                textField,
              ],
            )
          : textField,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
