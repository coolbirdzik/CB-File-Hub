import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as pathlib;

import '../../core/service_locator.dart';
import '../../helpers/files/archive_path_utils.dart';
import '../../helpers/files/external_app_helper.dart';
import '../../services/windowing/desktop_windowing_service.dart';
import '../../services/windowing/window_startup_payload.dart';
import '../controllers/file_operations_handler.dart';
import '../screens/folder_list/folder_list_bloc.dart';
import '../tab_manager/core/tab_manager.dart';
import 'file_type_utils.dart';
import 'video_playback_launcher.dart';

class EntityOpenActions {
  static void openInNewTab(
    BuildContext context, {
    required String sourcePath,
    String? preferredTabName,
    bool openContainingFolder = false,
  }) {
    if (!openContainingFolder && _tryOpenFileDirectly(context, sourcePath)) {
      return;
    }

    final target = _resolveTarget(
      sourcePath,
      preferredTabName: preferredTabName,
      openContainingFolder: openContainingFolder,
    );
    if (target == null) return;

    TabNavigator.openTab(
      context,
      target.path,
      title: target.tabName,
      highlightedFileName: target.highlightedFileName,
    );
  }

  static Future<bool> openInNewWindow(
    BuildContext context, {
    required String sourcePath,
    String? preferredTabName,
    bool openContainingFolder = false,
    bool forceNewWindow = false,
  }) async {
    if (!openContainingFolder &&
        _tryOpenFileDirectly(
          context,
          sourcePath,
          forceNewWindow: forceNewWindow,
        )) {
      return true;
    }

    final target = _resolveTarget(
      sourcePath,
      preferredTabName: preferredTabName,
      openContainingFolder: openContainingFolder,
    );
    if (target == null) return false;

    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (!isDesktop) {
      openInNewTab(
        context,
        sourcePath: sourcePath,
        preferredTabName: preferredTabName,
      );
      return true;
    }

    final service = locator<DesktopWindowingService>();
    return service.openNewWindow(
      tabs: <WindowTabPayload>[
        WindowTabPayload(
          path: target.path,
          name: target.tabName,
          highlightedFileName: target.highlightedFileName,
        ),
      ],
    );
  }

  static void openInNewPane(
    BuildContext context, {
    required String sourcePath,
    String? preferredTabName,
  }) {
    final target = _resolveTarget(
      sourcePath,
      preferredTabName: preferredTabName,
    );
    if (target == null) return;

    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    tabBloc.add(
      AddTab(
        path: target.path,
        name: target.tabName,
        switchToTab: false,
        highlightedFileName: target.highlightedFileName,
      ),
    );
  }

  /// Opens the given [sourcePath] in the right-hand split pane of the active tab.
  /// If the active tab is already split, replaces the right pane's path.
  static void openInSplitView(
    BuildContext context, {
    required String sourcePath,
    String? preferredTabName,
  }) {
    final target = _resolveTarget(
      sourcePath,
      preferredTabName: preferredTabName,
    );
    if (target == null) return;

    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final activeTab = tabBloc.state.activeTab;
    if (activeTab == null) return;

    tabBloc.add(OpenSplitPane(tabId: activeTab.id, path: target.path));
  }

  /// Opens [sourcePath] the same way Enter / double-click does when it points
  /// to a file that cannot be browsed as a folder (i.e. anything but an
  /// archive). Returns true when the open was handled here.
  static bool _tryOpenFileDirectly(
    BuildContext context,
    String sourcePath, {
    bool forceNewWindow = false,
  }) {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return false;
    if (ArchivePathUtils.isArchiveEntryPath(trimmed)) return false;

    final entityType = FileSystemEntity.typeSync(trimmed, followLinks: false);
    if (entityType != FileSystemEntityType.file) return false;
    // Archives are browsable, so they keep opening as a new tab / window.
    if (FileTypeUtils.isArchiveFile(trimmed)) return false;

    // Shift+Enter on a video: always a brand new player window, never the
    // one that is already open.
    if (forceNewWindow && FileTypeUtils.isVideoFile(trimmed)) {
      unawaited(
        VideoPlaybackLauncher.open(
          context,
          file: File(trimmed),
          forceNewWindow: true,
        ),
      );
      return true;
    }

    FolderListBloc? folderListBloc;
    try {
      folderListBloc = BlocProvider.of<FolderListBloc>(context);
    } catch (_) {
      folderListBloc = null;
    }

    if (folderListBloc != null) {
      FileOperationsHandler.onFileTap(
        context: context,
        file: File(trimmed),
        folderListBloc: folderListBloc,
      );
    } else {
      ExternalAppHelper.openFileWithApp(trimmed, 'shell_open');
    }
    return true;
  }

  static _ResolvedOpenTarget? _resolveTarget(
    String sourcePath, {
    String? preferredTabName,
    bool openContainingFolder = false,
  }) {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('#')) {
      return _ResolvedOpenTarget(
        path: trimmed,
        tabName: preferredTabName ?? trimmed,
        highlightedFileName: null,
      );
    }

    final entityType = FileSystemEntity.typeSync(trimmed, followLinks: false);
    if (entityType == FileSystemEntityType.notFound) return null;

    if (entityType == FileSystemEntityType.file) {
      // Archives are browsable containers: open the archive itself in the new
      // tab / window instead of its containing folder.
      if (!openContainingFolder && FileTypeUtils.isArchiveFile(trimmed)) {
        return _ResolvedOpenTarget(
          path: ArchivePathUtils.build(archiveFile: trimmed),
          tabName: preferredTabName ?? pathlib.basename(trimmed),
          highlightedFileName: null,
        );
      }

      final file = File(trimmed);
      final parentPath = file.parent.path;
      return _ResolvedOpenTarget(
        path: parentPath,
        tabName: preferredTabName ?? _nameFromPath(parentPath),
        highlightedFileName: pathlib.basename(trimmed),
      );
    }

    return _ResolvedOpenTarget(
      path: trimmed,
      tabName: preferredTabName ?? _nameFromPath(trimmed),
      highlightedFileName: null,
    );
  }

  static String _nameFromPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return path;
    return parts.last;
  }
}

class _ResolvedOpenTarget {
  final String path;
  final String tabName;
  final String? highlightedFileName;

  const _ResolvedOpenTarget({
    required this.path,
    required this.tabName,
    required this.highlightedFileName,
  });
}
