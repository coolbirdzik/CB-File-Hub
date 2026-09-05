import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';

/// A widget that wraps content with RefreshIndicator and handles complex refresh logic
class RefreshableFileListView extends StatefulWidget {
  final FolderListState folderListState;
  final String currentPath;
  final String tabId;
  final FolderListBloc folderListBloc;
  final TabManagerBloc tabManagerBloc;
  final Widget child;
  final Function()? isMounted;
  final Function(bool)? onRefreshStateChanged;

  const RefreshableFileListView({
    super.key,
    required this.folderListState,
    required this.currentPath,
    required this.tabId,
    required this.folderListBloc,
    required this.tabManagerBloc,
    required this.child,
    this.isMounted,
    this.onRefreshStateChanged,
  });

  @override
  State<RefreshableFileListView> createState() =>
      _RefreshableFileListViewState();
}

class _RefreshableFileListViewState extends State<RefreshableFileListView> {
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      // Improve mobile experience with better colors and behavior
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      strokeWidth: 2.0,
      displacement: Platform.isAndroid || Platform.isIOS ? 40.0 : 60.0,
      onRefresh: () => _handleRefresh(context),
      child: widget.child,
    );
  }

  Future<void> _handleRefresh(BuildContext context) async {
    // Add haptic feedback for mobile
    if (Platform.isAndroid || Platform.isIOS) {
      HapticFeedback.lightImpact();
    }

    _setRefreshState(true);

    // Create the completer first
    final completer = Completer<void>();

    // Create the subscription variable
    late StreamSubscription subscription;

    // Now set up the listener
    subscription = widget.folderListBloc.stream.listen((state) {
      // Refresh is done when isRefreshing goes false AND isLoading is also false.
      // (isRefreshing covers FolderListRefresh; isLoading covers initial loads via
      // tag-search paths that still use isLoading to signal completion.)
      if (!state.isRefreshing && !state.isLoading) {
        // Add success haptic feedback for mobile
        if (Platform.isAndroid || Platform.isIOS) {
          HapticFeedback.selectionClick();
        }
        _setRefreshState(false);
        completer.complete();
        subscription.cancel();
      }
    });

    // Check if this is a system path (starts with #)
    if (widget.currentPath.startsWith('#')) {
      // For system paths, we need special handling
      if (widget.currentPath == '#tags') {
        // For tag management screen
        TagManager.clearCache();
        // Clear the system screen router cache for this path
        SystemScreenRouter.refreshSystemPath(widget.currentPath, widget.tabId);
        // Notify completion after a short delay since there's no explicit loading state
        Future.delayed(const Duration(milliseconds: 500), () {
          completer.complete();
        });
      } else if (widget.currentPath.startsWith('#search?tag=')) {
        final tag =
            UriUtils.extractTagFromSearchPath(widget.currentPath) ??
            widget.currentPath.substring('#search?tag='.length);
        TagManager.clearCache();
        // Clear the system screen router cache for this path
        SystemScreenRouter.refreshSystemPath(widget.currentPath, widget.tabId);
        widget.folderListBloc.add(SearchByTagGlobally(tag));
        // Completion will be triggered by the listener above
      } else if (widget.currentPath.startsWith('#network/')) {
        // Network special paths (#network/TYPE/...) – clear widget cache and reload
        SystemScreenRouter.refreshSystemPath(widget.currentPath, widget.tabId);

        // Force TabManager to re-set the same path to trigger rebuild
        widget.tabManagerBloc.add(
          UpdateTabPath(widget.tabId, widget.currentPath),
        );

        // If this screen still uses FolderList, trigger bloc refresh to regenerate thumbnails
        widget.folderListBloc.add(
          FolderListRefresh(
            widget.currentPath,
            forceRegenerateThumbnails: true,
          ),
        );
      }
    } else {
      // Use FolderListRefresh instead of FolderListLoad to force thumbnail regeneration
      VideoThumbnailHelper.trimCache();
      widget.folderListBloc.add(
        FolderListRefresh(widget.currentPath, forceRegenerateThumbnails: true),
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
  }

  void _setRefreshState(bool isRefreshing) {
    if (widget.isMounted != null && !widget.isMounted!()) return;

    if (mounted) {
      widget.onRefreshStateChanged?.call(isRefreshing);
    }
  }
}
