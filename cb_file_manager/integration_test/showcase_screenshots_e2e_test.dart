import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/main.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/services/featured_albums_service.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e_helpers.dart';
import 'e2e_keys.dart';
import 'e2e_report.dart';
import 'e2e_sandbox_paths.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Isolate ALL app data (SQLite DB, tags, prefs-backed files, thumbnail
  // caches, trash) into a throwaway sandbox so capturing screenshots never
  // touches the real Documents/CBFileHub_v2 data of your debug/release build.
  setUpAll(() async {
    await E2ESandboxPaths.install();
  });
  tearDownAll(() async {
    await E2ESandboxPaths.uninstall();
  });

  group('Showcase', () {
    testWidgets('file browser', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_files_');
      final media = await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop(dir);

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase file browser');

        expectFolderRowVisible(media.movies.path);
        expectFolderRowVisible(media.photos.path);
        expectFileRowVisible(media.heroImage);
        expectFileRowVisible(media.heroVideo);

        final gridIcon = find.byIcon(Icons.grid_view);
        if (gridIcon.evaluate().isNotEmpty) {
          await et.tap(gridIcon.first, detail: 'grid_layout');
          await et.pumpAndSettle(const Duration(seconds: 2));
        }

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('gallery hub', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_gallery_');
      final media = await seedShowcaseLibrary(dir);
      await seedShowcaseAlbum(media);
      await seedWallpaperBackdrop(dir);

      CbE2EConfig.startupPayload = const WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: '#gallery')],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase gallery hub');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('album detail', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_album_');
      final media = await seedShowcaseLibrary(dir);
      final albumId = await seedShowcaseAlbum(media);
      await seedWallpaperBackdrop(dir);

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: '#album/$albumId')],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase album detail');
        await tester.pumpAndSettle(const Duration(seconds: 2));

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

// -------------------------------------------------------------------------
    // 4. AI side panel — chat with search results
    // -------------------------------------------------------------------------
    testWidgets('AI side panel — search results', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir =
          await Directory.systemTemp.createTemp('cb_showcase_ai_search_');
      final media = await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop(dir);
      await seedAiConversationWithResults(
        workspacePath: dir.path,
        userQuery: 'Find duplicate videos and large files',
        resultPaths: <String>[...media.images, ...media.videos],
      );

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase AI side panel search');

        // Tap the sparkle (AI) button in the top bar to open the side panel
        final sparkleButton = find.byIcon(PhosphorIconsLight.sparkle);
        if (sparkleButton.evaluate().isNotEmpty) {
          await et.tap(sparkleButton.first, detail: 'open_ai_panel');
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    // -------------------------------------------------------------------------
    // 5. AI side panel — approval card
    // -------------------------------------------------------------------------
    testWidgets('AI side panel — approval', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir =
          await Directory.systemTemp.createTemp('cb_showcase_ai_approval_');
      await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop(dir);
      await seedAiConversationWithApproval(
        workspacePath: dir.path,
        userQuery: 'Delete all duplicate files in Photos',
        actionType: 'deleteFile',
        title: 'Confirm: Delete 3 files',
        description: 'The following files will be permanently deleted:\n'
            '• Photos/vacation_01.jpg\n'
            '• Photos/vacation_02.jpg',
      );

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase AI approval');

        final sparkleButton = find.byIcon(PhosphorIconsLight.sparkle);
        if (sparkleButton.evaluate().isNotEmpty) {
          await et.tap(sparkleButton.first, detail: 'open_ai_panel');
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    // -------------------------------------------------------------------------
    // 6. AI side panel — multi-turn conversation
    // -------------------------------------------------------------------------
    testWidgets('AI side panel — conversation', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_ai_conv_');
      await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop(dir);
      await seedAiMultiTurnConversation(workspacePath: dir.path);

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase AI conversation');

        final sparkleButton = find.byIcon(PhosphorIconsLight.sparkle);
        if (sparkleButton.evaluate().isNotEmpty) {
          await et.tap(sparkleButton.first, detail: 'open_ai_panel');
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    // -------------------------------------------------------------------------
    // 7. Tag management — tag list
    // -------------------------------------------------------------------------
    testWidgets('tag management list', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_tags_');
      final media = await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop(dir);
      await seedTags(media.images);

      // Open tags screen via system path
      CbE2EConfig.startupPayload = const WindowStartupPayload(
        tabs: [WindowTabPayload(path: '#tags')],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase tag management');

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    // -------------------------------------------------------------------------
    // 8. Tag management — tagged files panel
    // -------------------------------------------------------------------------
    testWidgets('tag management tagged files', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_tagged_');
      final media = await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop(dir);
      await seedTags(media.images);

      CbE2EConfig.startupPayload = const WindowStartupPayload(
        tabs: [WindowTabPayload(path: '#tags')],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase tag tagged files');

        // Wait for tag list to appear, then double-tap first tag to open its files
        final tagFinder = find.byType(ListTile);
        final exists = await tester.runAsync(() async {
          await tester.pump(const Duration(seconds: 2));
          return tagFinder.evaluate().isNotEmpty;
        });
        if (exists == true) {
          await tester.tap(tagFinder.first);
          await tester.pumpAndSettle(const Duration(seconds: 1));
          await tester.tap(tagFinder.first);
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    // -------------------------------------------------------------------------
    // 9. Tag management — tree view (parent/child hierarchy)
    // -------------------------------------------------------------------------
    testWidgets('tag management tree', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_tagtree_');
      final media = await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop(dir);
      await seedTagHierarchy(media.images);

      CbE2EConfig.startupPayload = const WindowStartupPayload(
        tabs: [WindowTabPayload(path: '#tags')],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase tag tree');

        // Switch to tree view: open the "eye" view-mode menu, pick Tree.
        final eyeIcon = find.byIcon(PhosphorIconsLight.eye);
        if (eyeIcon.evaluate().isNotEmpty) {
          await et.tap(eyeIcon.first, detail: 'view_mode_menu');
          await tester.pumpAndSettle(const Duration(seconds: 1));
          final treeIcon = find.byIcon(PhosphorIconsLight.treeView);
          if (treeIcon.evaluate().isNotEmpty) {
            await et.tap(treeIcon.last, detail: 'tree_mode');
            await tester.pumpAndSettle(const Duration(seconds: 1));
          }
        }

        // Expand the first few parent rows so the hierarchy is visible.
        final caretIcons = find.byIcon(PhosphorIconsLight.caretRight);
        final caretCount = caretIcons.evaluate().length;
        for (var i = 0; i < caretCount && i < 3; i++) {
          final caret = find.byIcon(PhosphorIconsLight.caretRight);
          if (caret.evaluate().isEmpty) break;
          await tester.tap(caret.first);
          await tester.pumpAndSettle(const Duration(milliseconds: 400));
        }

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });
  });
}

class ShowcaseMedia {
  final Directory root;
  final Directory movies;
  final Directory photos;
  final Directory albums;
  final List<String> images;
  final List<String> videos;

  const ShowcaseMedia({
    required this.root,
    required this.movies,
    required this.photos,
    required this.albums,
    required this.images,
    required this.videos,
  });

  String get heroImage => images.first;
  String get heroVideo => videos.first;
}

Future<ShowcaseMedia> seedShowcaseLibrary(Directory root) async {
  final movies = Directory(p.join(root.path, 'Movies'))..createSync();
  final photos = Directory(p.join(root.path, 'Photos'))..createSync();
  final albums = Directory(p.join(root.path, 'Albums'))..createSync();

  final images = <String>[
    p.join(root.path, 'cover_ocean.jpg'),
    p.join(root.path, 'cover_sunset.jpg'),
    p.join(photos.path, 'vacation_01.jpg'),
    p.join(photos.path, 'vacation_02.jpg'),
    p.join(movies.path, 'poster_01.jpg'),
    p.join(movies.path, 'poster_02.jpg'),
  ];

  seedImage(images[0], width: 1280, height: 720, palette: SeedPalette.ocean);
  seedImage(images[1], width: 1280, height: 720, palette: SeedPalette.sunset);
  seedImage(images[2], width: 1200, height: 900, palette: SeedPalette.forest);
  seedImage(images[3], width: 1200, height: 900, palette: SeedPalette.violet);
  seedImage(images[4], width: 720, height: 1080, palette: SeedPalette.sunset);
  seedImage(images[5], width: 720, height: 1080, palette: SeedPalette.ocean);

  final videos = <String>[
    p.join(root.path, 'trailer.mp4'),
    p.join(movies.path, 'feature_film.mp4'),
  ];
  seedVideo(videos[0]);
  seedVideo(videos[1]);

  File(p.join(albums.path, 'curation_notes.txt')).writeAsStringSync(
      'Weekend picks, favorite scenes, and smart album rules.');
  File(p.join(root.path, 'README.txt')).writeAsStringSync(
      'Showcase media library generated for screenshot automation.');

  return ShowcaseMedia(
    root: root,
    movies: movies,
    photos: photos,
    albums: albums,
    images: images,
    videos: videos,
  );
}

Future<int> seedShowcaseAlbum(ShowcaseMedia media) async {
  await AlbumService.instance.initialize();
  final album = await AlbumService.instance.createAlbum(
    name: 'Weekend Picks ${DateTime.now().microsecondsSinceEpoch}',
    description: 'Curated images and videos for showcase screenshots',
    coverImagePath: media.heroImage,
    colorTheme: 'blue',
  );

  if (album == null) {
    throw StateError('Failed to create showcase album');
  }

  await AlbumService.instance.addFilesToAlbum(
    album.id,
    <String>[...media.images, ...media.videos],
  );
  await FeaturedAlbumsService.instance.addToFeatured(album.id);
  return album.id;
}

// ---------------------------------------------------------------------------
// AI conversation seed helpers
//
// The AI chat screen loads conversation via:
//   AiChatHistoryService.findLatestSummaryForPath(normalizedWorkspacePath)
//
// This writes a conversation summary and messages into SharedPreferences
// so the bloc starts with pre-populated messages when the workspace path matches.
// ---------------------------------------------------------------------------

/// Writes a fake AI conversation with file search results into SharedPreferences.
Future<void> seedAiConversationWithResults({
  required String workspacePath,
  required String userQuery,
  required List<String> resultPaths,
}) async {
  const convId = 'showcase-conversation';

  final resultJson = <Map<String, dynamic>>[];
  for (int i = 0; i < resultPaths.length && i < 6; i++) {
    final path = resultPaths[i];
    final name = p.basename(path);
    final ext = p.extension(path).toLowerCase();
    resultJson.add({
      'path': path,
      'fileName': name,
      'relevance': (95 - i * 8).clamp(50, 100),
      'explanation': _explanationFor(name, ext),
      'verified': true,
    });
  }

  await _persistAiConversation(
    convId: convId,
    title: userQuery,
    messages: <Map<String, dynamic>>[
      {
        'id': '1',
        'role': 'user',
        'content': userQuery,
        'isLoading': false,
      },
      {
        'id': '2',
        'role': 'assistant',
        'content': 'I found several files matching your query. '
            'Here are the most relevant results:',
        'isLoading': false,
      },
      {
        'id': '3',
        'role': 'assistant',
        'content': 'Here are the top matches:',
        'isLoading': false,
        'searchResults': resultJson,
      },
    ],
    initialPath: workspacePath,
  );
}

/// Writes a fake AI conversation that ends with a pending approval card.
Future<void> seedAiConversationWithApproval({
  required String workspacePath,
  required String userQuery,
  required String actionType,
  required String title,
  required String description,
}) async {
  const convId = 'showcase-approval';

  await _persistAiConversation(
    convId: convId,
    title: userQuery,
    messages: <Map<String, dynamic>>[
      {
        'id': 'a1',
        'role': 'user',
        'content': userQuery,
        'isLoading': false,
      },
      {
        'id': 'a2',
        'role': 'assistant',
        'content': title,
        'isLoading': false,
      },
    ],
    initialPath: workspacePath,
  );
}

/// Writes a realistic 4-message multi-turn conversation.
Future<void> seedAiMultiTurnConversation({
  required String workspacePath,
}) async {
  const convId = 'showcase-multi-turn';

  await _persistAiConversation(
    convId: convId,
    title: 'Find duplicate videos',
    messages: <Map<String, dynamic>>[
      {
        'id': 'm1',
        'role': 'user',
        'content': 'Find duplicate videos in my library',
        'isLoading': false,
      },
      {
        'id': 'm2',
        'role': 'assistant',
        'content': 'I found **2 potential duplicate videos** in your library. '
            'Both have similar resolution and duration. '
            'Would you like me to highlight them so you can decide?',
        'isLoading': false,
      },
      {
        'id': 'm3',
        'role': 'user',
        'content': 'Yes, highlight them in the file browser',
        'isLoading': false,
      },
      {
        'id': 'm4',
        'role': 'assistant',
        'content':
            'Done! I\'ve highlighted the two duplicate files in your Photos folder. '
                'They appear to be the same recording saved at different times. '
                'Would you like me to suggest a cleanup strategy?',
        'isLoading': false,
      },
    ],
    initialPath: workspacePath,
  );
}

/// Writes conversation messages + index entry into SharedPreferences.
Future<void> _persistAiConversation({
  required String convId,
  required String title,
  required List<Map<String, dynamic>> messages,
  required String initialPath,
}) async {
  final prefs = await SharedPreferences.getInstance();

  // Persist the message list
  await prefs.setString('ai_conv_$convId', jsonEncode(messages));

  // Update the conversation index — read, modify, write
  final indexRaw = prefs.getString('ai_conv_index');
  List<Map<String, dynamic>> index = [];
  if (indexRaw != null) {
    try {
      index = (jsonDecode(indexRaw) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .toList();
    } catch (_) {}
  }

  // Remove any existing entry with same ID (update scenario)
  index.removeWhere((e) => e['id'] == convId);

  final now = DateTime.now();
  index.insert(0, {
    'id': convId,
    'title': title,
    'createdAt': now.toIso8601String(),
    'updatedAt': now.toIso8601String(),
    'initialPath': initialPath,
  });

  await prefs.setString('ai_conv_index', jsonEncode(index));
}

String _explanationFor(String fileName, String ext) {
  if (ext == '.jpg' || ext == '.jpeg') {
    return 'Photo file — matches recent gallery query';
  }
  if (ext == '.mp4' || ext == '.mov') {
    return 'Video file — potential duplicate candidate';
  }
  if (ext == '.txt') {
    return 'Text note — indexed for search';
  }
  return 'Media file — matches query';
}

/// Seeds tags onto the given file paths using TagManager.
Future<void> seedTags(List<String> filePaths) async {
  await TagManager.initialize();

  // Create 3 showcase tags
  const tagNames = ['vacation', 'favorite', 'project'];
  for (final tag in tagNames) {
    await TagManager.addStandaloneTag(tag);
  }

  // Tag every file with every tag (show as a rich tag library)
  for (final path in filePaths) {
    for (final tag in tagNames) {
      try {
        await TagManager.addTag(path, tag);
      } catch (_) {}
    }
  }
}

/// Seed a single tag onto a single file path.
Future<void> seedSingleTag(String filePath, String tag) async {
  await TagManager.initialize();
  try {
    await TagManager.addStandaloneTag(tag);
    await TagManager.addTag(filePath, tag);
  } catch (_) {}
}

/// Seeds a small parent/child tag hierarchy for the tree-view showcase.
///
/// Produces:
///   Media
///     ├─ Movies
///     │    └─ Action
///     └─ Photos
///   Travel
///     ├─ Beach
///     └─ Mountains
/// plus a couple of standalone tags so the tree shows mixed roots.
Future<void> seedTagHierarchy(List<String> filePaths) async {
  await TagManager.initialize();
  final hierarchy = TagHierarchyManager.instance;
  await hierarchy.initialize();

  const relationships = <List<String>>[
    ['Media', 'Movies'],
    ['Media', 'Photos'],
    ['Movies', 'Action'],
    ['Travel', 'Beach'],
    ['Travel', 'Mountains'],
  ];

  // Make sure every node exists as a tag first (standalone), then link them.
  final allTags = <String>{
    for (final pair in relationships) ...pair,
    'Favorite',
    'Archive',
  };
  for (final tag in allTags) {
    await TagManager.addStandaloneTag(tag);
  }
  for (final pair in relationships) {
    await hierarchy.addChild(pair[0], pair[1]);
  }

  // Attach a few leaf tags onto files so the library isn't empty.
  for (final path in filePaths.take(3)) {
    await TagManager.addTag(path, 'Beach');
    await TagManager.addTag(path, 'Action');
  }
}

Future<void> seedWallpaperBackdrop(Directory root) async {
  final wallpaperPath = p.join(root.path, 'showcase_wallpaper.jpg');
  seedImage(
    wallpaperPath,
    width: 1920,
    height: 1080,
    palette: SeedPalette.wallpaper,
  );

  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('acrylic_backdrop_mode', 'wallpaper');
  await prefs.setString('acrylic_backdrop_image_path', wallpaperPath);
  await prefs.setDouble('desktop_acrylic_strength', 0.85);
  await prefs.setString('app_theme', 'light');
}

enum SeedPalette { ocean, sunset, forest, violet, wallpaper }

void seedImage(
  String outputPath, {
  int width = 800,
  int height = 600,
  SeedPalette palette = SeedPalette.ocean,
}) {
  final image = img.Image(width: width, height: height);
  final gradient = _gradientFor(palette);

  for (int y = 0; y < height; y++) {
    final t = y / (height - 1);
    final color = _lerpColor(gradient.start, gradient.end, t);
    for (int x = 0; x < width; x++) {
      image.setPixelRgb(x, y, color.r, color.g, color.b);
    }
  }

  final centerX = width / 2;
  final centerY = height / 2;
  final maxDist = math.sqrt(centerX * centerX + centerY * centerY);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final dx = x - centerX;
      final dy = y - centerY;
      final dist = math.sqrt(dx * dx + dy * dy);
      final boost = (1.0 - (dist / maxDist)) * 44;
      final pixel = image.getPixel(x, y);
      image.setPixelRgb(
        x,
        y,
        (pixel.r + boost).clamp(0, 255).toInt(),
        (pixel.g + boost).clamp(0, 255).toInt(),
        (pixel.b + boost).clamp(0, 255).toInt(),
      );
    }
  }

  File(outputPath).writeAsBytesSync(img.encodeJpg(image, quality: 84));
}

void seedVideo(String outputPath) {
  final sample = File(_sampleVideoPath());
  if (sample.existsSync()) {
    sample.copySync(outputPath);
    return;
  }

  const stub = <int>[
    0x00,
    0x00,
    0x00,
    0x18,
    0x66,
    0x74,
    0x79,
    0x70,
    0x69,
    0x73,
    0x6F,
    0x6D,
    0x00,
    0x00,
    0x02,
    0x00,
    0x69,
    0x73,
    0x6F,
    0x6D,
    0x61,
    0x76,
    0x63,
    0x31,
    0x00,
    0x00,
    0x00,
    0x08,
    0x6D,
    0x64,
    0x61,
    0x74,
  ];
  File(outputPath).writeAsBytesSync(stub);
}

String _sampleVideoPath() {
  try {
    final scriptStr = Platform.script.toString();
    final scriptPath = scriptStr.startsWith('file:///')
        ? Uri.parse(scriptStr).toFilePath()
        : scriptStr;
    return p.join(
      p.dirname(scriptPath),
      'samples',
      'file_example_MP4_1920_18MG.mp4',
    );
  } catch (_) {
    return '';
  }
}

class _Rgb {
  final int r;
  final int g;
  final int b;

  const _Rgb(this.r, this.g, this.b);
}

class _Gradient {
  final _Rgb start;
  final _Rgb end;

  const _Gradient(this.start, this.end);
}

_Rgb _lerpColor(_Rgb a, _Rgb b, double t) {
  return _Rgb(
    (a.r + (b.r - a.r) * t).round(),
    (a.g + (b.g - a.g) * t).round(),
    (a.b + (b.b - a.b) * t).round(),
  );
}

_Gradient _gradientFor(SeedPalette palette) {
  switch (palette) {
    case SeedPalette.ocean:
      return const _Gradient(_Rgb(40, 95, 170), _Rgb(90, 180, 220));
    case SeedPalette.sunset:
      return const _Gradient(_Rgb(240, 120, 80), _Rgb(255, 200, 120));
    case SeedPalette.forest:
      return const _Gradient(_Rgb(40, 110, 80), _Rgb(120, 180, 100));
    case SeedPalette.violet:
      return const _Gradient(_Rgb(95, 50, 160), _Rgb(200, 110, 220));
    case SeedPalette.wallpaper:
      return const _Gradient(_Rgb(38, 83, 135), _Rgb(212, 148, 110));
  }
}
