import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';

/// Resolves the filesystem / virtual parent of [path] for "Up" navigation.
/// Returns [kDrivesPath] when already at a volume root (e.g. `H:\`).
/// Returns `null` when there is no parent (drives view, settings, search paths, etc.).
String? computeParentPathRaw(String path) {
  if (path.isEmpty || isDrivesPath(path) || isSettingsPath(path)) {
    return null;
  }
  if (path.startsWith('#search')) {
    return null;
  }
  if (ArchivePathUtils.isArchiveBrowsePath(path)) {
    return ArchivePathUtils.parentBrowsePath(path);
  }
  if (path.startsWith('#') && !path.startsWith('#network/')) {
    return null;
  }
  if (path.startsWith('#network/')) {
    final parts = path.split('/');
    if (parts.length <= 3) {
      return null;
    }
    return parts.sublist(0, parts.length - 1).join('/');
  }
  try {
    final normalized = Platform.isWindows ? path.replaceAll('/', r'\') : path;
    final parentPath = Directory(normalized).parent.path;
    final same = Platform.isWindows
        ? parentPath.toLowerCase() == normalized.toLowerCase()
        : parentPath == normalized;
    if (same) {
      return kDrivesPath;
    }
    return parentPath;
  } catch (_) {
    return null;
  }
}

/// Controller for handling navigation operations in tabbed folder screens
class NavigationController {
  final String tabId;
  final TabManagerBloc tabManagerBloc;
  final FolderListBloc folderListBloc;
  final Function(String) onPathChanged;
  final Function() onSaveLastAccessedFolder;

  NavigationController({
    required this.tabId,
    required this.tabManagerBloc,
    required this.folderListBloc,
    required this.onPathChanged,
    required this.onSaveLastAccessedFolder,
  });

  void _recordRecentPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    if (isDrivesPath(trimmed)) return;
    if (trimmed.startsWith('#')) return;
    unawaited(UserPreferences.instance.addRecentPath(trimmed));
  }

  /// Parent path for the Up button, accounting for active in-folder search.
  String? parentPathForUpButton(String tabPath) {
    var pathForParent = tabPath;
    final state = folderListBloc.state;
    if (state.isSearchActive && !tabPath.startsWith('#')) {
      pathForParent = state.currentPath.path;
    } else if (state.isSearchActive && tabPath.startsWith('#search')) {
      return null;
    }
    return computeParentPathRaw(pathForParent);
  }

  /// Navigate to parent folder (address bar Up). No-op if no parent.
  void navigateToParentFolder(
    BuildContext context,
    String tabPath,
    TextEditingController pathController,
    Function(String) clearKeyboardFocus,
  ) {
    final parent = parentPathForUpButton(tabPath);
    if (parent == null) return;
    navigateToPath(context, parent, pathController, clearKeyboardFocus);
  }

  /// Navigate to a specific path
  void navigateToPath(
    BuildContext context,
    String path,
    TextEditingController pathController,
    Function(String) clearKeyboardFocus,
  ) {
    // Stop any ongoing thumbnail processing to prevent UI lag
    VideoThumbnailHelper.stopAllProcessing();
    final l10n = AppLocalizations.of(context)!;

    // Tag-search paths (#search?tag=...) behave like folders: tapping a child
    // tag drills into that tag in the same tab instead of loading a directory.
    final tagForPath = UriUtils.extractTagFromSearchPath(path);
    if (tagForPath != null) {
      clearKeyboardFocus(path);
      pathController.text = tagForPath;
      tabManagerBloc.add(UpdateTabPath(tabId, path));
      onPathChanged(path);
      folderListBloc.add(SearchByTagGlobally(tagForPath));
      tabManagerBloc.add(UpdateTabName(tabId, 'Tag: $tagForPath'));
      return;
    }

    if (ArchivePathUtils.isArchiveBrowsePath(path)) {
      clearKeyboardFocus(path);
      pathController.text = ArchivePathUtils.displayPath(path);
      folderListBloc.add(const ClearSearchAndFilters());
      tabManagerBloc.add(UpdateTabPath(tabId, path));
      onPathChanged(path);
      folderListBloc.add(FolderListLoad(path));
      tabManagerBloc.add(UpdateTabName(tabId, ArchivePathUtils.tabTitle(path)));
      return;
    }

    // Clear keyboard focus
    clearKeyboardFocus(path);

    // Update path controller
    pathController.text = path;

    // Clear any search or filter state when navigating
    folderListBloc.add(const ClearSearchAndFilters());

    // Update the tab's path in the TabManager
    tabManagerBloc.add(UpdateTabPath(tabId, path));

    debugPrint('Navigating to path: $path');
    debugPrint('Tab ID: $tabId');

    // Debug: Check navigation history after adding
    final updatedTab = tabManagerBloc.state.tabs.firstWhere(
      (tab) => tab.id == tabId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );
    debugPrint(
      'Navigation history after adding: ${updatedTab.navigationHistory}',
    );
    debugPrint(
      'Navigation history length: ${updatedTab.navigationHistory.length}',
    );

    // Commit the visible path before the directory scan starts. The listing
    // can take time for large or slow folders, but the address bar and tab
    // should reflect the user's navigation immediately.
    onPathChanged(path);

    // Update the folder list to show the new path
    folderListBloc.add(FolderListLoad(path));

    _recordRecentPath(path);

    // Save this folder as last accessed
    onSaveLastAccessedFolder();

    // Update the tab name based on the new path
    if (isDrivesPath(path)) {
      tabManagerBloc.add(UpdateTabName(tabId, l10n.drivesTab));
    } else {
      final pathParts = path.split(Platform.pathSeparator);
      final lastPart = pathParts.lastWhere(
        (part) => part.isNotEmpty,
        orElse: () => l10n.rootFolder,
      );
      final tabName = lastPart.isEmpty ? l10n.rootFolder : lastPart;
      tabManagerBloc.add(UpdateTabName(tabId, tabName));
    }
  }

  /// Handle path submission when user manually edits the path
  void handlePathSubmit(
    BuildContext context,
    String path,
    String currentPath,
    TextEditingController pathController,
  ) {
    // Handle empty path as drives view.
    if (path.isEmpty) {
      final l10n = AppLocalizations.of(context)!;
      tabManagerBloc.add(UpdateTabPath(tabId, kDrivesPath));
      tabManagerBloc.add(UpdateTabName(tabId, l10n.drivesTab));
      onPathChanged(kDrivesPath);
      pathController.text = '';
      return;
    }

    if (isDrivesPath(path)) {
      final l10n = AppLocalizations.of(context)!;
      tabManagerBloc.add(UpdateTabPath(tabId, kDrivesPath));
      tabManagerBloc.add(UpdateTabName(tabId, l10n.drivesTab));
      onPathChanged(kDrivesPath);
      pathController.text = '';
      return;
    }

    // Check if path exists
    final directory = Directory(path);
    directory.exists().then((exists) {
      if (exists) {
        if (context.mounted) {
          navigateToPath(
            context,
            path,
            pathController,
            (_) {}, // Empty keyboard focus clear
          );
        }
      } else {
        if (context.mounted) {
          AppToast.error(
            context,
            AppLocalizations.of(context)!.pathNotAccessible,
          );
        }
        // Revert to current path
        pathController.text = (isDrivesPath(currentPath) || currentPath.isEmpty)
            ? ''
            : currentPath;
      }
    });
  }

  /// Handle back button press for Android
  Future<bool> handleBackButton(
    BuildContext context,
    String currentPath,
    TextEditingController pathController,
  ) async {
    try {
      debugPrint('=== _handleBackButton called ===');
      debugPrint('Hardware back button pressed!');
      debugPrint('Back button pressed - current path: $currentPath');

      // Stop any ongoing thumbnail processing when navigating
      VideoThumbnailHelper.stopAllProcessing();

      // First check if we're currently showing search results
      final folderListState = folderListBloc.state;
      if (folderListState.isSearchActive) {
        if (currentPath.startsWith('#search?tag=')) {
          // A tag search reached by drilling in from the tag list has back
          // history: walk it, matching the UI back button. Only close the tab
          // when the search is the tab's first entry (opened directly via
          // "Open in New Tab" / middle-click).
          if (!tabManagerBloc.canTabNavigateBack(tabId)) {
            tabManagerBloc.add(CloseTab(tabId));
            return false;
          }
          // Fall through to the shared history-back logic below.
        } else {
          // Clear search results and reload current directory
          folderListBloc.add(const ClearSearchAndFilters());
          folderListBloc.add(FolderListLoad(currentPath));
          return false; // Don't exit app, we cleared the search
        }
      }

      // Check if we can navigate back in the folder hierarchy
      final currentTab = tabManagerBloc.state.tabs.firstWhere(
        (tab) => tab.id == tabId,
        orElse: () => TabData(id: '', name: '', path: ''),
      );

      debugPrint('Current tab path: ${currentTab.path}');
      debugPrint('Navigation history: ${currentTab.navigationHistory}');
      debugPrint(
        'Navigation history length: ${currentTab.navigationHistory.length}',
      );
      debugPrint(
        'Can navigate back: ${tabManagerBloc.canTabNavigateBack(tabId)}',
      );

      if (tabManagerBloc.canTabNavigateBack(tabId)) {
        final newPath = tabManagerBloc.backNavigationToPath(tabId);
        debugPrint('Back navigation result: $newPath');
        if (newPath != null) {
          debugPrint('Successfully navigating back to: $newPath');
          // Tab title is kept in sync by backNavigationToPath itself.
          if (newPath.isEmpty || isDrivesPath(newPath)) {
            onPathChanged(newPath);
            pathController.text = '';
            return false;
          }
          onPathChanged(newPath);
          pathController.text = newPath;
          if (newPath.startsWith('#search?tag=')) {
            final tag =
                UriUtils.extractTagFromSearchPath(newPath) ??
                newPath.substring('#search?tag='.length);
            folderListBloc.add(SearchByTagGlobally(tag));
          } else {
            folderListBloc.add(FolderListLoad(newPath));
            _recordRecentPath(newPath);
          }
          debugPrint('=== Back navigation completed successfully ===');
          return false; // Don't exit app, we navigated back
        } else {
          debugPrint('Back navigation failed - newPath is null');
        }
      }

      // For mobile, if we're at root directory, show exit confirmation
      if (Platform.isAndroid || Platform.isIOS) {
        if (currentPath.isEmpty ||
            isDrivesPath(currentPath) ||
            currentPath == '/storage/emulated/0' ||
            currentPath == '/storage/self/primary') {
          // Show exit confirmation dialog
          debugPrint('At root directory on mobile - showing exit confirmation');
          final shouldExit = await _showExitConfirmation(context);
          debugPrint('Exit confirmation result: $shouldExit');
          return shouldExit;
        }
      }

      // If we can't navigate back in tab, check if we can pop the navigator
      if (Navigator.of(context).canPop()) {
        debugPrint('Popping navigator route');
        Navigator.of(context).pop();
        return false; // Don't exit app
      }

      // If we're at the root and can't navigate back, don't allow back
      debugPrint('At root directory - preventing back navigation');
      return false; // Don't exit app, just prevent back navigation
    } catch (e) {
      debugPrint('Error in _handleBackButton: $e');
      return false; // Don't exit app on error, just prevent back navigation
    }
  }

  /// Show exit confirmation dialog for mobile
  Future<bool> _showExitConfirmation(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.exitApplicationTitle),
        content: Text(l10n.exitApplicationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(l10n.exit),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Centralized method to update path and reload folder contents
  void updatePath(
    String newPath,
    TextEditingController pathController,
    String? currentFilter,
    String? currentSearchTag,
  ) {
    // Stop any ongoing thumbnail processing to prevent UI lag
    VideoThumbnailHelper.stopAllProcessing();

    pathController.text = (isDrivesPath(newPath) || newPath.isEmpty)
        ? ''
        : ArchivePathUtils.isArchiveBrowsePath(newPath)
        ? ArchivePathUtils.displayPath(newPath)
        : newPath;

    if (isDrivesPath(newPath) || newPath.isEmpty) {
      if (currentFilter != null || currentSearchTag != null) {
        folderListBloc.add(const ClearSearchAndFilters());
      }
      onPathChanged(newPath);
      return;
    }

    if (newPath.startsWith('#search?tag=')) {
      final tag =
          UriUtils.extractTagFromSearchPath(newPath) ??
          newPath.substring('#search?tag='.length);
      if (folderListBloc.state.currentSearchTag != tag ||
          folderListBloc.state.searchResults.isEmpty) {
        folderListBloc.add(SearchByTagGlobally(tag));
      }
      onPathChanged(newPath);
      return;
    }

    if (ArchivePathUtils.isArchiveBrowsePath(newPath)) {
      if (currentFilter != null || currentSearchTag != null) {
        folderListBloc.add(const ClearSearchAndFilters());
      }
      onPathChanged(newPath);
      folderListBloc.add(FolderListLoad(newPath));
      return;
    }

    // Clear any search or filter state when navigating to a normal path
    if (currentFilter != null || currentSearchTag != null) {
      folderListBloc.add(const ClearSearchAndFilters());
    }

    // Commit the visible path before the directory scan starts. This keeps
    // external tab path changes, history navigation, and split-pane navigation
    // responsive even when folder enumeration is slow.
    onPathChanged(newPath);

    // Load the folder contents with the new path
    folderListBloc.add(FolderListLoad(newPath));

    _recordRecentPath(newPath);

    // Save as last accessed folder
    onSaveLastAccessedFolder();
  }

  /// Handle result from gallery screens (Video/Image Gallery)
  void handleGalleryResult(BuildContext context, dynamic result) {
    if (result != null && result is Map<String, dynamic>) {
      if (result['action'] == 'openFolder') {
        final folderPath = result['folderPath'] as String;
        debugPrint('Gallery returned openFolder request: $folderPath');

        final l10n = AppLocalizations.of(context)!;
        final folderName = folderPath
            .split(RegExp(r'[\\\\/]+'))
            .lastWhere(
              (part) => part.isNotEmpty,
              orElse: () => l10n.rootFolder,
            );

        // Open new tab with the folder - using TabNavigator utility
        // Note: This requires importing the tab navigator utility
        // For now, we'll use the TabManagerBloc directly
        tabManagerBloc.add(AddTab(path: folderPath, name: folderName));
      }
    }
  }

  /// Handle mouse back button press
  void handleMouseBackButton(
    BuildContext context,
    String currentPath,
    TextEditingController pathController,
  ) {
    // First check if we're currently showing search results
    final folderListState = folderListBloc.state;
    if (folderListState.isSearchActive) {
      if (currentPath.startsWith('#search?tag=')) {
        // A tag search reached by drilling in from the tag list (or any other
        // in-place navigation) has back history: walk it, matching the UI back
        // button. Only close the tab when the search is the tab's first entry
        // (opened directly via "Open in New Tab" / middle-click).
        if (!tabManagerBloc.canTabNavigateBack(tabId)) {
          tabManagerBloc.add(CloseTab(tabId));
          return;
        }
        // Fall through to the shared history-back logic below.
      } else {
        // Clear search results and reload current directory
        folderListBloc.add(const ClearSearchAndFilters());
        folderListBloc.add(FolderListLoad(currentPath));
        return; // Don't navigate back, we're just clearing the search
      }
    }

    if (tabManagerBloc.canTabNavigateBack(tabId)) {
      final actualPath = tabManagerBloc.backNavigationToPath(tabId);
      if (actualPath == null) return;

      // Tab title is kept in sync by backNavigationToPath itself.
      if (actualPath.isEmpty || isDrivesPath(actualPath)) {
        onPathChanged(actualPath);
        pathController.text = '';
      } else {
        onPathChanged(actualPath);
        pathController.text = actualPath;
      }

      if (actualPath.startsWith('#search?tag=')) {
        final tag =
            UriUtils.extractTagFromSearchPath(actualPath) ??
            actualPath.substring('#search?tag='.length);
        folderListBloc.add(SearchByTagGlobally(tag));
      } else {
        folderListBloc.add(FolderListLoad(actualPath));
        _recordRecentPath(actualPath);
      }
    }
  }

  /// Handle mouse forward button press
  void handleMouseForwardButton(
    BuildContext context,
    String currentPath,
    TextEditingController pathController,
  ) {
    if (tabManagerBloc.canTabNavigateForward(tabId)) {
      final String? actualPath = tabManagerBloc.forwardNavigationToPath(tabId);
      if (actualPath == null) return;

      // Tab title is kept in sync by forwardNavigationToPath itself.
      if (actualPath.isEmpty || isDrivesPath(actualPath)) {
        onPathChanged(actualPath);
        pathController.text = '';
        return;
      }

      onPathChanged(actualPath);
      pathController.text = actualPath;

      if (actualPath.startsWith('#search?tag=')) {
        final tag =
            UriUtils.extractTagFromSearchPath(actualPath) ??
            actualPath.substring('#search?tag='.length);
        folderListBloc.add(SearchByTagGlobally(tag));
      } else {
        folderListBloc.add(FolderListLoad(actualPath));
        _recordRecentPath(actualPath);
      }
    }
  }
}
