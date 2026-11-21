import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late File legacyVideo;
  late File currentVideo;
  late File legacyThumb;
  late File currentThumb;

  String md5Of(String value) => md5.convert(utf8.encode(value)).toString();

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_thumb_version_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);

    final cacheDir = await Directory(
      p.join(root.path, 'cb_file_hub', 'video_thumbnails'),
    ).create(recursive: true);
    legacyVideo = await File(p.join(root.path, 'legacy.mp4')).create();
    currentVideo = await File(p.join(root.path, 'current.mp4')).create();
    final legacyKey = VideoThumbnailHelper.getNormalizedPath(legacyVideo.path);
    final currentKey = VideoThumbnailHelper.getNormalizedPath(
      currentVideo.path,
    );
    // A file written by an older build, under its old name.
    legacyThumb = await File(
      p.join(cacheDir.path, 'thumb_${md5Of(legacyKey)}.jpg'),
    ).writeAsBytes([1, 2, 3]);
    currentThumb = await File(
      p.join(cacheDir.path, 'thumb_v2_${md5Of(currentKey)}.jpg'),
    ).writeAsBytes([1, 2, 3]);

    await File(p.join(root.path, 'thumbnail_cache_index.json')).writeAsString(
      jsonEncode({legacyKey: legacyThumb.path, currentKey: currentThumb.path}),
    );
    await VideoThumbnailHelper.initializeCache();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test('recognizes only the unversioned cache file name as legacy', () {
    final hex = md5Of('x');
    expect(VideoThumbnailHelper.isLegacyCacheFile('/c/thumb_$hex.jpg'), isTrue);
    expect(
      VideoThumbnailHelper.isLegacyCacheFile('/c/thumb_v2_$hex.jpg'),
      isFalse,
    );
    expect(
      VideoThumbnailHelper.isLegacyCacheFile('/c/thumb_crop_123.jpg'),
      isFalse,
    );
    expect(VideoThumbnailHelper.isLegacyCacheFile('/c/frame.png'), isFalse);
  });

  test('legacy index entries are dropped and their files deleted', () async {
    expect(
      VideoThumbnailHelper.peekCachedThumbnailPath(legacyVideo.path),
      isNull,
    );
    expect(await VideoThumbnailHelper.getFromCache(legacyVideo.path), isNull);
    // The background deletion runs right after the index load.
    for (var i = 0; i < 50 && legacyThumb.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(legacyThumb.existsSync(), isFalse);
  });

  test('versioned entries are still served from the cache', () async {
    expect(
      VideoThumbnailHelper.peekCachedThumbnailPath(currentVideo.path),
      currentThumb.path,
    );
    expect(
      await VideoThumbnailHelper.getFromCache(currentVideo.path),
      currentThumb.path,
    );
  });
}
