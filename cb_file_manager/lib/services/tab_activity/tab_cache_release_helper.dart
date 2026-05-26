import 'dart:async';

import 'package:cb_file_manager/helpers/media/photo_thumbnail_helper.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

/// Releases per-tab caches when a tab transitions to inactive (>= 60 min idle).
///
/// This is intentionally aggressive: file listing snapshots and photo thumbnail
/// memory caches associated with a tab's path are evicted so the OS can reclaim
/// RAM. Heavyweight global stores (video thumbnail SQLite, folder thumbnail
/// disk cache, etc.) are left alone — they are designed to survive across
/// sessions and clearing them would hurt the next refocus.
class TabCacheReleaseHelper {
  TabCacheReleaseHelper._();

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

    // Drop directory listing snapshot for the tab's current path.
    if (path != null && path.isNotEmpty && !path.startsWith('#')) {
      try {
        DirectoryListingCacheService.instance.invalidate(path);
      } catch (e) {
        AppLogger.perf(
          '[TabActivity] listing cache invalidate failed for $path: $e',
        );
      }
    }

    // Drop photo thumbnail memory cache for the tab's current path.
    if (path != null && path.isNotEmpty && !path.startsWith('#')) {
      try {
        await PhotoThumbnailHelper.evictForPaths(<String>[path]);
      } catch (e) {
        AppLogger.perf(
          '[TabActivity] photo thumbnail evict failed for $path: $e',
        );
      }
    }
  }
}
