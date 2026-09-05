import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as path;

import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';

/// Controller for managing inline rename state on desktop.
///
/// This controller manages which entity is currently being renamed inline
/// and provides methods for starting, committing, and cancelling renames.
class InlineRenameController extends ChangeNotifier {
  bool allowFileExtensionRename = false;

  /// The path of the entity currently being renamed, or null if none.
  String? _renamingPath;

  /// The extension the user is *not* editing, kept so the field can render it
  /// dimmed beside the editable stem. Computed once at [startRename] because
  /// deciding it needs a `typeSync` call, which has no business running in a
  /// build method on every frame.
  String? _lockedSuffix;

  /// The text editing controller for the rename field.
  TextEditingController? _textController;

  /// The focus node for the rename field.
  FocusNode? _focusNode;

  /// Callback to be called when rename is cancelled.
  VoidCallback? _onCancelled;

  /// Callback to be called when rename is committed successfully.
  VoidCallback? _onCommitted;

  /// The path of the entity currently being renamed.
  String? get renamingPath => _renamingPath;

  /// Whether an inline rename is currently active.
  bool get isRenaming => _renamingPath != null;

  /// The text controller for the rename field.
  TextEditingController? get textController => _textController;

  /// The focus node for the rename field.
  FocusNode? get focusNode => _focusNode;

  /// The trailing run of the name held constant during this rename — the file
  /// extension when extension renaming is off. Null for folders and whenever
  /// the whole name is editable.
  String? get lockedSuffix => _lockedSuffix;

  /// Start inline rename for the given entity path.
  void startRename(
    String entityPath, {
    VoidCallback? onCancelled,
    VoidCallback? onCommitted,
  }) {
    // Cancel any existing rename first
    if (_renamingPath != null) {
      cancelRename();
    }

    _renamingPath = entityPath;
    _onCancelled = onCancelled;
    _onCommitted = onCommitted;

    // Get basename for the text field
    final isFile =
        FileSystemEntity.typeSync(entityPath) == FileSystemEntityType.file;
    final baseName = path.basename(entityPath);
    final nameWithoutExt = isFile
        ? path.basenameWithoutExtension(entityPath)
        : baseName;
    final initialValue = isFile && allowFileExtensionRename
        ? baseName
        : nameWithoutExt;
    final extension = isFile ? path.extension(entityPath) : '';
    _lockedSuffix = isFile && !allowFileExtensionRename && extension.isNotEmpty
        ? extension
        : null;

    _textController = TextEditingController(text: initialValue);
    _focusNode = FocusNode();

    // Select all text
    _textController!.selection = TextSelection(
      baseOffset: 0,
      extentOffset: initialValue.length,
    );

    notifyListeners();

    // Request focus after the widget builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode?.requestFocus();
    });
  }

  /// Commit the rename operation.
  /// Returns true if the rename was successful.
  Future<bool> commitRename(BuildContext context) async {
    if (_renamingPath == null || _textController == null) {
      return false;
    }

    final entityPath = _renamingPath!;
    final newName = _textController!.text.trim();

    if (newName.isEmpty) {
      cancelRename();
      return false;
    }

    final isFile =
        FileSystemEntity.typeSync(entityPath) == FileSystemEntityType.file;
    final currentBaseName = path.basename(entityPath);
    final extension = isFile ? path.extension(entityPath) : '';

    final finalNewName = isFile
        ? _resolveFileRename(rawName: newName, extension: extension)
        : newName;

    if (finalNewName.isEmpty) {
      cancelRename();
      return false;
    }

    // Check if name actually changed
    if (finalNewName == currentBaseName) {
      cancelRename();
      return false;
    }

    // Perform the rename
    try {
      final folderListBloc = context.read<FolderListBloc>();
      final entity = isFile ? File(entityPath) : Directory(entityPath);

      folderListBloc.add(RenameFileOrFolder(entity, finalNewName));

      final callback = _onCommitted;
      _cleanup();
      notifyListeners();
      callback?.call();
      return true;
    } catch (e) {
      debugPrint('Error committing rename: $e');
      cancelRename();
      return false;
    }
  }

  /// Cancel the current rename operation.
  void cancelRename() {
    final callback = _onCancelled;

    // Schedule cleanup for next frame to avoid disposing FocusNode
    // while it's notifying listeners (which causes crash)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _cleanup();
    });

    // But clear the renaming path immediately so UI updates
    _renamingPath = null;
    _lockedSuffix = null;
    notifyListeners();
    callback?.call();
  }

  void _cleanup() {
    _textController?.dispose();
    _textController = null;
    _focusNode?.dispose();
    _focusNode = null;
    _renamingPath = null;
    _lockedSuffix = null;
    _onCancelled = null;
    _onCommitted = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  String _resolveFileRename({
    required String rawName,
    required String extension,
  }) {
    if (allowFileExtensionRename) {
      return rawName;
    }

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
}

/// InheritedWidget to provide InlineRenameController down the widget tree.
class InlineRenameScope extends InheritedNotifier<InlineRenameController> {
  const InlineRenameScope({
    super.key,
    required InlineRenameController controller,
    required super.child,
  }) : super(notifier: controller);

  static InlineRenameController? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InlineRenameScope>()
        ?.notifier;
  }

  static InlineRenameController? maybeOf(BuildContext context) {
    return context.findAncestorWidgetOfExactType<InlineRenameScope>()?.notifier;
  }
}
