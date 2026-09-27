import 'home_preview_policy.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';

class HomeMediaPreviews {
  final List<String> images;
  final String? videoCover;

  const HomeMediaPreviews({this.images = const [], this.videoCover});
}

/// Home reads a small snapshot of existing history and media metadata. It never
/// enumerates directories or starts thumbnail generation/background scanning.
class HomeContentService {
  Future<List<String>> loadRecentPaths() => UserPreferences.instance
      .getRecentPaths(limit: 6, validateDirectories: false);

  Future<HomeMediaPreviews> loadMediaPreviews(List<String> recentPaths) async {
    try {
      final database = await SqliteDatabaseProvider().getDatabase();
      final policy = await HomePreviewPolicy.load(database);
      final images = <String>{};
      final videos = <String>{};
      for (final directory in recentPaths) {
        final listing = DirectoryListingCacheService.instance.getListing(
          directory,
        );
        if (listing == null) continue;
        for (final file in listing.files) {
          if (images.length < 12 && FileTypeUtils.isImageFile(file.path)) {
            images.add(file.path);
          } else if (videos.length < 12 &&
              FileTypeUtils.isVideoFile(file.path)) {
            videos.add(file.path);
          }
          if (images.length == 12 && videos.length == 12) break;
        }
      }
      final covers = await database.query(
        'albums',
        columns: ['cover_image_path'],
        where:
            "is_nsfw = 0 AND cover_image_path IS NOT NULL AND cover_image_path != ''",
        orderBy: 'modified_at DESC',
        limit: 12,
      );
      images.addAll(
        covers.map((row) => row['cover_image_path']).whereType<String>(),
      );
      final files = await database.rawQuery('''
        SELECT f.file_path FROM album_files f JOIN albums a ON a.id = f.album_id
        WHERE a.is_nsfw = 0 ORDER BY f.added_at DESC LIMIT 12
      ''');
      images.addAll(files.map((row) => row['file_path']).whereType<String>());
      final safeImages = await policy.filter(images);

      final videoCovers = await database.query(
        'video_libraries',
        columns: ['cover_image_path'],
        where:
            "is_nsfw = 0 AND cover_image_path IS NOT NULL AND cover_image_path != ''",
        orderBy: 'modified_at DESC',
        limit: 12,
      );
      final safeCovers = await policy.filter(
        videoCovers.map((row) => row['cover_image_path']).whereType<String>(),
      );
      String? videoCover = safeCovers.firstOrNull;
      if (videoCover == null) {
        final files = await database.rawQuery('''
          SELECT f.file_path FROM video_library_files f
          JOIN video_libraries v ON v.id = f.video_library_id
          WHERE v.is_nsfw = 0 ORDER BY f.added_at DESC LIMIT 12
        ''');
        videos.addAll(files.map((row) => row['file_path']).whereType<String>());
        final safeVideos = await policy.filter(videos);
        for (final video in safeVideos.take(4)) {
          final cached = await VideoThumbnailHelper.getFromCache(video);
          if (cached != null && (await policy.filter([cached])).isNotEmpty) {
            videoCover = cached;
            break;
          }
        }
      }
      return HomeMediaPreviews(
        images: safeImages.take(3).toList(growable: false),
        videoCover: videoCover,
      );
    } catch (_) {
      // If privacy metadata cannot be checked, show the neutral illustration.
      return const HomeMediaPreviews();
    }
  }
}
