import 'dart:async';

import 'package:cb_file_manager/helpers/media/folder_thumbnail_service.dart';
import 'package:cb_file_manager/helpers/media/photo_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/network/network_thumbnail_helper.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
import 'package:flutter/painting.dart';

/// Releases per-tab caches when a tab transitions to inactive (>= 60 min idle).
///
/// This is intentionally aggressive: file listing snapshots, photo/video
/// thumbnail memory caches, network thumbnail queues, and tab-scoped
/// directory watcher subscriptions associated with the tab's path are
/// released so the OS can reclaim RAM. Heavyweight global stores (video
/// thumbnail SQLite, folder thumbnail disk cache) are left alone — they
/// are designed to survive across sessions and clearing them would hurt
/// the next refocus.
class TabCacheReleaseHelper {
  TabCacheReleaseHelper._();

  /// Memory budget (in bytes) above which the global Flutter image cache is
  /// trimmed when a tab transitions to inactive. Below this budget the
  /// shared cache is left intact so the focused tab is not punished.
  ///
  /// 96 MiB matches the default `imageCache.maximumSizeBytes` on desktop
  /// and is well above what a typical foreground tab needs in a single
  /// folder.
  static const int _imageCacheTrimThresholdBytes = 96 * 1024 * 1024;

  /// Release tab-scoped caches for [tabId] at [path].
  ///
  /// [path] may be null (e.g. system tabs without a filesystem path); in that
  /// case only listing/thumbnail caches keyed by tab path are skipped, but
  /// global short-lived caches are still trimmed.
  static Future<void> releaseForTab({
    required String tabId,
    required String? path,
  }) async {
    AppLogger.perf(
      '[TabActivity] releasing caches for inactive tab=$tabId path=$path',
    );

    final hasPath = path != null && path.isNotEmpty && !path.startsWith('#');
    final isNetworkPath = path != null && path.startsWith('#network/');

    // Suspend further enqueue work in ThumbnailLoader for any visible widgets
    // belonging to this tab. Resumed on refocus.
    if (path != null && path.isNotEmpty) {
      try {
        ThumbnailLoader.suspendTab(tabId, path);
      } catch (e) {
        AppLogger.perf('[TabActivity] thumbnail suspend failed: $e');
      }
    }

    // Drop directory listing snapshot for the tab's current path.
    if (hasPath) {
      try {
        DirectoryListingCacheService.instance.invalidate(path);
      } catch (e) {
        AppLogger.perf(
          '[TabActivity] listing cache invalidate failed for $path: $e',
        );
      }
    }

    // Drop photo thumbnail memory cache for the tab's current path.
    if (hasPath) {
      try {
        await PhotoThumbnailHelper.evictForPaths(<String>[path]);
      } catch (e) {
        AppLogger.perf(
          '[TabActivity] photo thumbnail evict failed for $path: $e',
        );
      }
    }

    // Cancel pending video thumbnail work for the tab's directory.
    if (hasPath) {
      try {
        VideoThumbnailHelper.cancelForDirectory(path);
      } catch (e) {
        AppLogger.perf(
          '[TabActivity] video thumbnail cancel failed for $path: $e',
        );
      }
    }

    // Cancel pending folder thumbnail work for the tab's directory.
    if (hasPath) {
      try {
        FolderThumbnailService().cancelForDirectory(path);
      } catch (e) {
        AppLogger.perf(
          '[TabActivity] folder thumbnail cancel failed for $path: $e',
        );
      }
    }

    // Cancel pending SMB / network thumbnail work for the tab's directory.
    if (isNetworkPath) {
      try {
        NetworkThumbnailHelper().cancelPathsUnder(path);
      } catch (e) {
        AppLogger.perf(
          '[TabActivity] network thumbnail cancel failed for $path: $e',
        );
      }
    }

    // Bounded trim of the global Flutter image cache. Avoids unconditional
    // clear() so the focused tab's decoded bitmaps are preserved.
    try {
      final cache = PaintingBinding.instance.imageCache;
      if (cache.currentSizeBytes > _imageCacheTrimThresholdBytes) {
        cache.clearLiveImages();
      }
    } catch (e) {
      AppLogger.perf('[TabActivity] image cache trim failed: $e');
    }
  }
}
