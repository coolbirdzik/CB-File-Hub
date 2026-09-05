import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';

/// Controller for handling refresh operations in folder list screens
///
/// This controller manages:
/// - File list refreshing
/// - System path refreshing (tags, network paths)
/// - Thumbnail regeneration
/// - Cache clearing
class RefreshController {
  final FolderListBloc folderListBloc;
  final TabManagerBloc tabManagerBloc;
  final String tabId;

  RefreshController({
    required this.folderListBloc,
    required this.tabManagerBloc,
    required this.tabId,
  });

  /// Refresh the file list for the current path
  ///
  /// This method handles different types of paths:
  /// - System paths (starting with #)
  /// - Network paths
  /// - Regular file system paths
  Future<void> refreshFileList({
    required String currentPath,
    required bool Function() isMounted,
    required VoidCallback onRefreshComplete,
  }) async {
    // Flag to track refresh state
    bool isRefreshing = true;
    StreamSubscription? refreshSubscription;

    void stopOnce() {
      if (!isRefreshing) return;
      isRefreshing = false;
      refreshSubscription?.cancel();
      if (!isMounted()) return;
      onRefreshComplete();
    }

    // Clear Flutter's image cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    if (isDrivesPath(currentPath)) {
      folderListBloc.add(const FolderListLoadDrives());
      Future.delayed(const Duration(milliseconds: 250), stopOnce);
      return;
    }

    // Check if this is a system path (starts with #)
    if (currentPath.startsWith('#')) {
      // For system paths, we need special handling
      if (currentPath == '#tags') {
        // For tag management screen
        TagManager.clearCache();
        // Clear the system screen router cache for this path
        SystemScreenRouter.refreshSystemPath(currentPath, tabId);
        // Reload tag management data (will be handled by the component)
      } else if (currentPath.startsWith('#search?tag=')) {
        final tag =
            UriUtils.extractTagFromSearchPath(currentPath) ??
            currentPath.substring('#search?tag='.length);
        TagManager.clearCache();
        // Clear the system screen router cache for this path
        SystemScreenRouter.refreshSystemPath(currentPath, tabId);
        folderListBloc.add(SearchByTagGlobally(tag));
      } else if (currentPath.startsWith('#network/')) {
        // Network special paths (#network/TYPE/...) – clear widget cache and reload
        SystemScreenRouter.refreshSystemPath(currentPath, tabId);

        // Force TabManager to re-set the same path to trigger rebuild
        tabManagerBloc.add(UpdateTabPath(tabId, currentPath));

        // If this screen still uses FolderList, trigger bloc refresh to regenerate thumbnails
        folderListBloc.add(
          FolderListRefresh(currentPath, forceRegenerateThumbnails: true),
        );
      }
    } else {
      // For regular paths, finish the visible refresh state as soon as the
      // actual folder scan completes instead of holding it for a fixed delay.
      bool sawRefreshStart =
          folderListBloc.state.isRefreshing || folderListBloc.state.isLoading;
      refreshSubscription = folderListBloc.stream.listen((state) {
        if (state.isRefreshing || state.isLoading) {
          sawRefreshStart = true;
        } else if (sawRefreshStart) {
          stopOnce();
        }
      });
      folderListBloc.add(FolderListRefresh(currentPath));
    }

    // Safety timeout for exceptional paths that do not publish completion.
    Future.delayed(const Duration(seconds: 15), stopOnce);
  }

  /// Build a RefreshIndicator widget with proper configuration
  ///
  /// This creates a pull-to-refresh widget that handles the refresh operation
  /// and provides appropriate visual feedback.
  Widget buildRefreshIndicator({
    required Widget child,
    required String currentPath,
    required BuildContext context,
    required bool Function() isMounted,
    required VoidCallback onRefreshStart,
    required VoidCallback onRefreshComplete,
  }) {
    return RefreshIndicator(
      // Improve mobile experience with better colors and behavior
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      strokeWidth: 2.0,
      displacement: Platform.isAndroid || Platform.isIOS ? 40.0 : 60.0,
      onRefresh: () async {
        // Add haptic feedback for mobile
        if (Platform.isAndroid || Platform.isIOS) {
          HapticFeedback.lightImpact();
        }

        onRefreshStart();

        // Create the completer first
        final completer = Completer<void>();

        // Create the subscription variable
        late StreamSubscription subscription;

        // Now set up the listener
        subscription = folderListBloc.stream.listen((state) {
          // When loading is done (changed from true to false), complete the Future
          if (!state.isRefreshing && !state.isLoading) {
            // Add success haptic feedback for mobile
            if (Platform.isAndroid || Platform.isIOS) {
              HapticFeedback.selectionClick();
            }
            onRefreshComplete();
            completer.complete();
            subscription.cancel();
          }
        });

        // Check if this is a system path (starts with #)
        if (isDrivesPath(currentPath)) {
          folderListBloc.add(const FolderListLoadDrives());
          Future.delayed(const Duration(milliseconds: 250), () {
            if (completer.isCompleted) return;
            onRefreshComplete();
            completer.complete();
            subscription.cancel();
          });
          return;
        }

        if (currentPath.startsWith('#')) {
          // For system paths, we need special handling
          if (currentPath == '#tags') {
            // For tag management screen
            TagManager.clearCache();
            // Clear the system screen router cache for this path
            SystemScreenRouter.refreshSystemPath(currentPath, tabId);
            // Notify completion after a short delay since there's no explicit loading state
            Future.delayed(const Duration(milliseconds: 500), () {
              completer.complete();
            });
          } else if (currentPath.startsWith('#search?tag=')) {
            final tag =
                UriUtils.extractTagFromSearchPath(currentPath) ??
                currentPath.substring('#search?tag='.length);
            TagManager.clearCache();
            // Clear the system screen router cache for this path
            SystemScreenRouter.refreshSystemPath(currentPath, tabId);
            folderListBloc.add(SearchByTagGlobally(tag));
            // Completion will be triggered by the listener above
          } else if (currentPath.startsWith('#network/')) {
            // Network special paths (#network/TYPE/...) – clear widget cache and reload
            SystemScreenRouter.refreshSystemPath(currentPath, tabId);

            // Force TabManager to re-set the same path to trigger rebuild
            tabManagerBloc.add(UpdateTabPath(tabId, currentPath));

            // If this screen still uses FolderList, trigger bloc refresh to regenerate thumbnails
            folderListBloc.add(
              FolderListRefresh(currentPath, forceRegenerateThumbnails: true),
            );
          } else if (ArchivePathUtils.isArchiveBrowsePath(currentPath)) {
            folderListBloc.add(
              FolderListRefresh(currentPath, forceRegenerateThumbnails: true),
            );
          }
        } else {
          // Use FolderListRefresh instead of FolderListLoad to force thumbnail regeneration
          VideoThumbnailHelper.trimCache();
          folderListBloc.add(
            FolderListRefresh(currentPath, forceRegenerateThumbnails: true),
          );
        }

        // Wait for the loading to complete before returning
        // Add timeout to prevent infinite waiting
        return completer.future.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('Refresh timeout - completing anyway');
            subscription.cancel();
          },
        );
      },
      child: child,
    );
  }
}
