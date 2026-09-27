import 'dart:io';

import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:cb_file_manager/services/home_content_service.dart';
import 'package:cb_file_manager/services/home_preview_policy.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/services/smart_album_service.dart';
import 'package:cb_file_manager/models/objectbox/album_config.dart';
import 'package:cb_file_manager/models/objectbox/video_library_config.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  final provider = SqliteDatabaseProvider();

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb-home-content-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    await provider.initialize();
  });

  setUp(() async {
    DirectoryListingCacheService.instance.clearAll();
    final db = await provider.getDatabase();
    await db.delete('album_files');
    await db.delete('albums');
    await db.delete('video_libraries');
  });

  tearDownAll(() async {
    DirectoryListingCacheService.instance.clearAll();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  test(
    'uses bounded library metadata and prioritizes cached folder photos',
    () async {
      final db = await provider.getDatabase();
      for (var i = 0; i < 5; i++) {
        await db.insert('albums', {
          'name': 'Album $i',
          'cover_image_path': 'cover-$i.jpg',
          'created_at': i,
          'modified_at': i,
        });
      }
      await db.insert('video_libraries', {
        'name': 'Videos',
        'cover_image_path': 'video-cover.jpg',
        'created_at': 1,
        'modified_at': 1,
      });
      final service = HomeContentService();
      final fromLibrary = await service.loadMediaPreviews([]);
      expect(fromLibrary.images, ['cover-4.jpg', 'cover-3.jpg', 'cover-2.jpg']);
      expect(fromLibrary.videoCover, 'video-cover.jpg');

      DirectoryListingCacheService.instance.storeListing(
        path: root.path,
        files: [File(p.join(root.path, 'visited.jpg'))],
        folders: [],
        stats: {},
      );
      final fromCache = await service.loadMediaPreviews([root.path]);
      expect(fromCache.images.first, p.join(root.path, 'visited.jpg'));
      expect(fromCache.images, hasLength(3));
    },
  );

  test('does not discover files by scanning recent directories', () async {
    final photo = File(p.join(root.path, 'not-indexed.jpg'));
    await photo.writeAsBytes([0]);
    final previews = await HomeContentService().loadMediaPreviews([root.path]);
    expect(previews.images, isEmpty);
    expect(previews.videoCover, isNull);
  });

  test('image source albums resolve configured folders from disk', () async {
    final sourceRoot = Directory(p.join(root.path, 'image-source'));
    if (await sourceRoot.exists()) await sourceRoot.delete(recursive: true);
    await sourceRoot.create(recursive: true);
    final nested = Directory(p.join(sourceRoot.path, 'nested'));
    await nested.create();
    final topImage = File(p.join(sourceRoot.path, 'top.jpg'));
    final nestedImage = File(p.join(nested.path, 'nested.png'));
    await topImage.writeAsBytes([1]);
    await nestedImage.writeAsBytes([2]);
    await File(p.join(sourceRoot.path, 'ignore.txt')).writeAsString('ignore');

    final service = AlbumService.instance;
    final album = await service.createAlbum(
      name: 'Folder source',
      directories: [sourceRoot.path],
      config: AlbumConfig(
        albumId: 0,
        includeSubdirectories: false,
        fileExtensions: '.jpg,.png',
      ),
    );
    expect(album, isNotNull);

    final topOnly = await service.getAlbumFileInfos(album!.id);
    expect(topOnly.map((file) => file.path), [topImage.path]);

    final config = await service.getAlbumConfig(album.id);
    expect(config, isNotNull);
    expect(config!.directoriesList, [sourceRoot.path]);
    await service.updateAlbumConfig(
      config.copyWith(includeSubdirectories: true),
    );

    final recursive = await service.getAlbumFileInfos(album.id);
    expect(recursive.map((file) => file.path).toSet(), {
      topImage.path,
      nestedImage.path,
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await service.deleteAlbum(album.id);
  });

  test('image source count is not capped by the scan load limit', () async {
    final sourceRoot = Directory(p.join(root.path, 'counted-image-source'));
    if (await sourceRoot.exists()) await sourceRoot.delete(recursive: true);
    await sourceRoot.create(recursive: true);
    for (var index = 0; index < 3; index++) {
      await File(
        p.join(sourceRoot.path, 'photo-$index.jpg'),
      ).writeAsBytes([index]);
    }
    await File(p.join(sourceRoot.path, 'not-an-image.txt')).writeAsString('x');

    final service = AlbumService.instance;
    final album = await service.createAlbum(
      name: 'Count beyond load limit',
      directories: [sourceRoot.path],
      config: AlbumConfig(albumId: 0, fileExtensions: '.jpg', maxFileCount: 1),
    );
    expect(album, isNotNull);
    expect(await service.getAlbumFileInfos(album!.id), hasLength(1));
    expect(await service.getAlbumImageCount(album.id), 3);
    await service.deleteAlbum(album.id);
  });

  test(
    'NSFW covers, shared files and source folders cannot leak through cache',
    () async {
      final db = await provider.getDatabase();
      final privateRoot = p.join(root.path, 'private');
      final privatePhoto = p.join(root.path, 'Ảnh Riêng', 'shared.jpg');
      final publicPhoto = p.join(root.path, 'private-sibling', 'safe.jpg');
      final album = await AlbumService.instance.createAlbum(
        name: 'Private',
        isNsfw: true,
        coverImagePath: p.join(root.path, 'cover.jpg'),
      );
      final publicAlbum = await AlbumService.instance.createAlbum(
        name: 'Public',
      );
      await db.insert(
        'album_configs',
        AlbumConfig(
          albumId: album!.id,
          directories: privateRoot,
        ).toDatabaseMap(),
      );
      for (final id in [album.id, publicAlbum!.id]) {
        await db.insert('album_files', {
          'album_id': id,
          'file_path': privatePhoto,
          'added_at': 1,
        });
      }
      final video = await VideoLibraryService().createLibrary(
        name: 'Private video',
        isNsfw: true,
        coverImagePath: p.join(root.path, 'video-cover.jpg'),
      );
      await db.insert('video_library_files', {
        'video_library_id': video!.id,
        'file_path': p.join(root.path, 'clip.mp4'),
        'added_at': 1,
      });
      final privateChild = p.join(privateRoot, 'nested', 'photo.jpg');
      DirectoryListingCacheService.instance.storeListing(
        path: root.path,
        files: [
          File(privatePhoto),
          File(album.coverImagePath!),
          File(video.coverImagePath!),
          File(privateChild),
          File(publicPhoto),
          File(p.join(root.path, 'clip.mp4')),
        ],
        folders: [],
        stats: {},
      );
      final previews = await HomeContentService().loadMediaPreviews([
        root.path,
      ]);
      expect(previews.images, [publicPhoto]);
      expect(previews.videoCover, isNull);
      final policy = await HomePreviewPolicy.load(db);
      if (Platform.isWindows) {
        expect(
          await policy.filter([
            privatePhoto.toUpperCase().replaceAll('\\', '/'),
          ]),
          isEmpty,
        );
      }
    },
  );

  test(
    'video source trees and smart album roots are excluded without scanning',
    () async {
      final db = await provider.getDatabase();
      final videoRoot = p.join(root.path, 'videos');
      final smartRoot = p.join(root.path, 'smart');
      await VideoLibraryService().createLibrary(
        name: 'Private source',
        isNsfw: true,
        config: VideoLibraryConfig(videoLibraryId: 0, directories: videoRoot),
      );
      final album = await AlbumService.instance.createAlbum(
        name: 'Smart',
        isNsfw: true,
      );
      await SmartAlbumService.instance.setScanRoots(album!.id, [smartRoot]);
      final policy = await HomePreviewPolicy.load(db);
      expect(
        await policy.filter([
          p.join(videoRoot, 'poster.jpg'),
          p.join(videoRoot, 'clip.mp4'),
          p.join(smartRoot, 'image.jpg'),
        ]),
        isEmpty,
      );
      expect(
        await policy.filter([p.join(root.path, 'videos-other', 'safe.jpg')]),
        hasLength(1),
      );
    },
  );

  test(
    'NSFW persists across metadata edits and unmarking restores Home eligibility',
    () async {
      final service = AlbumService.instance;
      final album = await service.createAlbum(
        name: 'Private',
        isNsfw: true,
        coverImagePath: 'private.jpg',
      );
      expect((await service.getAlbumById(album!.id))!.isNsfw, isTrue);
      expect(
        await service.updateAlbum(album.copyWith(name: 'Renamed')),
        isTrue,
      );
      expect(
        (await HomeContentService().loadMediaPreviews([])).images,
        isEmpty,
      );
      expect(await service.updateAlbum(album.copyWith(isNsfw: false)), isTrue);
      expect((await service.getAlbumById(album.id))!.isNsfw, isFalse);
      expect((await HomeContentService().loadMediaPreviews([])).images, [
        'private.jpg',
      ]);

      final videos = VideoLibraryService();
      final video = await videos.createLibrary(
        name: 'Private video',
        isNsfw: true,
        coverImagePath: 'video.jpg',
      );
      expect((await videos.getLibraryById(video!.id))!.isNsfw, isTrue);
      await videos.updateLibrary(
        video.copyWith(coverImagePath: 'new-cover.jpg'),
      );
      expect((await videos.getLibraryById(video.id))!.isNsfw, isTrue);
      expect(
        (await HomeContentService().loadMediaPreviews([])).videoCover,
        isNull,
      );
      await videos.updateLibrary(video.copyWith(isNsfw: false));
      expect(
        (await HomeContentService().loadMediaPreviews([])).videoCover,
        'video.jpg',
      );
    },
  );

  test(
    'unavailable privacy metadata never falls back to unfiltered folder cache',
    () async {
      final db = await provider.getDatabase();
      DirectoryListingCacheService.instance.storeListing(
        path: root.path,
        files: [File(p.join(root.path, 'unknown.jpg'))],
        folders: [],
        stats: {},
      );
      await db.execute('ALTER TABLE albums RENAME TO unavailable_albums');
      try {
        final previews = await HomeContentService().loadMediaPreviews([
          root.path,
        ]);
        expect(previews.images, isEmpty);
        expect(previews.videoCover, isNull);
      } finally {
        await db.execute('ALTER TABLE unavailable_albums RENAME TO albums');
      }
    },
  );
}
