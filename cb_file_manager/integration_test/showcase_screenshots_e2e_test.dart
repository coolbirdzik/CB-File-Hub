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
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
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

/// True when the showcase run targets a phone/tablet shell instead of the
/// desktop shell.
final bool kShowcaseMobileTarget = Platform.isAndroid || Platform.isIOS;

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

  // The desktop scenes below rely on the multi-pane desktop shell (AI side
  // panel, tag tree, disk cleaner). On phones the app renders a completely
  // different shell, so mobile targets get their own scene list instead.
  if (kShowcaseMobileTarget) {
    registerMobileShowcase();
    return;
  }

  group('Showcase', () {
    testWidgets('file browser', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_files_');
      final media = await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop();

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

        await switchToGridView(tester, et);

        // Select an image so the preview pane on the right renders content
        // instead of its "Select a file to preview" placeholder.
        final heroTile = find.text(p.basename(media.heroImage));
        if (heroTile.evaluate().isNotEmpty) {
          await et.tap(heroTile.first, detail: 'select_hero_image');
          await tester.pumpAndSettle(const Duration(seconds: 2));
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
      await seedWallpaperBackdrop();

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
      await seedWallpaperBackdrop();

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
      await seedWallpaperBackdrop();
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
      await seedWallpaperBackdrop();
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
      await seedWallpaperBackdrop();
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
      await seedWallpaperBackdrop();
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
      await seedWallpaperBackdrop();
      await seedTags(media.images);

      CbE2EConfig.startupPayload = const WindowStartupPayload(
        tabs: [WindowTabPayload(path: '#tags')],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('showcase tag tagged files');

        // Selecting a leaf tag loads its files into the panel on the right.
        await tester.pumpAndSettle(const Duration(seconds: 2));
        final tagRow = find.text('vacation');
        if (tagRow.evaluate().isNotEmpty) {
          await et.tap(tagRow.first, detail: 'open_tagged_files');
          await tester.pumpAndSettle(const Duration(seconds: 3));
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
      await seedWallpaperBackdrop();
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

        // The tree is a GenericTreeView with `expandOnRowTap: true`, so tapping
        // a parent row expands it. Walk down the seeded hierarchy so the promo
        // frame shows a real parent/child structure rather than collapsed roots.
        for (final parent in const <String>['Media', 'Movies', 'Travel']) {
          final row = find.text(parent);
          if (row.evaluate().isEmpty) continue;
          await et.tap(row.first, detail: 'expand_$parent');
          await tester.pumpAndSettle(const Duration(milliseconds: 800));
        }

        // Land on a leaf that owns files so the row thumbnails and the tagged
        // file panel both have content.
        final leaf = find.text('Beach');
        if (leaf.evaluate().isNotEmpty) {
          await et.tap(leaf.first, detail: 'select_leaf_tag');
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    // -------------------------------------------------------------------------
    // 10. Disk cleaner — scan results
    // -------------------------------------------------------------------------
    testWidgets('disk cleaner', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_showcase_cleaner_');
      await seedShowcaseLibrary(dir);
      await seedWallpaperBackdrop();

      CbE2EConfig.startupPayload = const WindowStartupPayload(
        tabs: [WindowTabPayload(path: '#cb-agent-cleaner')],
      );

      try {
        await runCbFileApp();
        await tester.pump(const Duration(seconds: 5));
        await et.init('showcase disk cleaner');
        await tester.pump(const Duration(seconds: 2));

        await et.screenshot('result');
        await et.pass();
      } finally {
        await e2eTearDown(tester, dir);
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Mobile showcase
//
// Four hero frames that mirror the four mobile promo slots produced by
// `scripts/make_promo_images.py`: home, file grid, tabs, tags.
// ---------------------------------------------------------------------------

/// Settles the widget tree, but gives up after [timeout] instead of hanging.
///
/// Mobile scenes render video thumbnails whose placeholder keeps animating
/// while the decoder works, so a plain `pumpAndSettle` can block for its full
/// ten minute default before failing the run. Capturing a still-loading frame
/// is far better than losing the whole capture.
Future<void> settleOrPump(
  WidgetTester tester, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      timeout,
    );
  } catch (_) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Creates the throwaway folder a mobile scene browses.
///
/// `Directory.systemTemp` resolves to the app's internal cache on Android, and
/// the phone file browser lists nothing there — it works from the device's
/// storage volumes. The app's own external files directory is a real volume
/// path and needs no runtime permission, so scenes seed into that instead.
Future<Directory> createMobileShowcaseDir(String prefix) async {
  if (!Platform.isAndroid) {
    return Directory.systemTemp.createTemp(prefix);
  }
  try {
    final external =
        await E2ESandboxPaths.platformProvider.getExternalStoragePath();
    if (external != null && external.isNotEmpty) {
      final base = Directory(p.join(external, 'showcase'))
        ..createSync(recursive: true);
      return await base.createTemp(prefix);
    }
  } catch (_) {
    // Fall back to the temp dir below.
  }
  return Directory.systemTemp.createTemp(prefix);
}

/// Pumps in real time until [finder] matches, or [timeout] elapses.
///
/// `pumpAndSettle` only waits for animations; a folder listing arriving from a
/// platform channel needs wall-clock time, which is why the phone file grid was
/// captured empty.
Future<bool> waitForVisible(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (finder.evaluate().isNotEmpty) return true;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }
  return finder.evaluate().isNotEmpty;
}

void registerMobileShowcase() {
  group('Mobile showcase', () {
    testWidgets('mobile home', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await createMobileShowcaseDir('cb_mobile_home_');
      await seedShowcaseLibrary(dir);
      await seedMobileAppearance();

      CbE2EConfig.startupPayload = const WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: '#home')],
      );

      try {
        await runCbFileApp();
        await settleOrPump(tester, timeout: const Duration(seconds: 12));
        await et.init('mobile home');
        await settleOrPump(tester);

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('mobile file grid', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await createMobileShowcaseDir('cb_mobile_grid_');
      final media = await seedShowcaseLibrary(dir);
      await seedMobileAppearance();

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: media.photos.path)],
      );

      try {
        await runCbFileApp();
        await settleOrPump(tester, timeout: const Duration(seconds: 12));
        await et.init('mobile file grid');
        // Mobile defaults to the grid view mode, so once the listing lands the
        // thumbnails are already on screen; give them time to decode too.
        await waitForVisible(tester, find.text(p.basename(media.heroPhoto)));
        await settleOrPump(tester, timeout: const Duration(seconds: 10));

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('mobile tabs', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await createMobileShowcaseDir('cb_mobile_tabs_');
      final media = await seedShowcaseLibrary(dir);
      await seedMobileAppearance();

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[
          const WindowTabPayload(path: '#home'),
          WindowTabPayload(path: media.photos.path),
          WindowTabPayload(path: media.movies.path),
        ],
      );

      try {
        await runCbFileApp();
        await settleOrPump(tester, timeout: const Duration(seconds: 12));
        await et.init('mobile tabs');

        // The tab counter in the address bar opens the full-screen tab manager.
        final tabCounter = find.ancestor(
          of: find.byWidgetPredicate(
            (Widget widget) =>
                widget is Icon &&
                widget.icon == PhosphorIconsLight.file &&
                widget.size == 16,
          ),
          matching: find.byType(InkWell),
        );
        if (tabCounter.evaluate().isNotEmpty) {
          await et.tap(tabCounter.first, detail: 'open_tab_manager');
          await settleOrPump(tester, timeout: const Duration(seconds: 10));
        }

        await et.screenshot('result');
      } finally {
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('mobile tags', (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await createMobileShowcaseDir('cb_mobile_tags_');
      final media = await seedShowcaseLibrary(dir);
      await seedMobileAppearance();
      await seedTags(media.images);

      CbE2EConfig.startupPayload = const WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: '#tags')],
      );

      try {
        await runCbFileApp();
        await settleOrPump(tester, timeout: const Duration(seconds: 12));
        await et.init('mobile tags');
        await settleOrPump(tester);

        await et.screenshot('result');
        await et.pass();
      } finally {
        await e2eTearDown(tester, dir);
      }
    });
  });
}

/// Mobile has no acrylic wallpaper backdrop, so it only needs the theme pinned
/// so every captured frame matches the desktop showcase.
Future<void> seedMobileAppearance() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('app_theme', 'light');
  // The app defaults to Vietnamese; pin English so the mobile frames match the
  // desktop ones the same promo run is built from.
  await prefs.setString('selected_language', 'en');
  // The E2E teardown clears this key, so without re-seeding it the theme
  // onboarding route covers the app on every scene after the first.
  await prefs.setBool('theme_onboarding_completed_v1', true);
}

/// Switches the active folder view to the thumbnail grid via the shared action
/// bar's view-mode menu (the eye button). No-op when the menu is unavailable.
Future<void> switchToGridView(WidgetTester tester, E2ETester et) async {
  final eyeIcon = find.byIcon(PhosphorIconsLight.eye);
  if (eyeIcon.evaluate().isEmpty) return;

  await et.tap(eyeIcon.first, detail: 'view_mode_menu');
  await tester.pumpAndSettle(const Duration(seconds: 1));

  final gridItem = find.descendant(
    of: find.byType(PopupMenuItem<ViewMode>),
    matching: find.byIcon(PhosphorIconsLight.squaresFour),
  );
  if (gridItem.evaluate().isEmpty) {
    // Menu never opened — close whatever is on screen and keep the list view.
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    return;
  }

  await et.tap(gridItem.first, detail: 'grid_view_mode');
  await tester.pumpAndSettle(const Duration(seconds: 3));
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

  /// First image inside `Photos/`, for scenes whose tab opens that folder.
  String get heroPhoto => images.firstWhere(
        (path) => p.isWithin(photos.path, path),
        orElse: () => images.first,
      );
}

Future<ShowcaseMedia> seedShowcaseLibrary(Directory root) async {
  final movies = Directory(p.join(root.path, 'Movies'))..createSync();
  final photos = Directory(p.join(root.path, 'Photos'))..createSync();
  final albums = Directory(p.join(root.path, 'Albums'))..createSync();

  // A promo frame reads as an empty app when the seeded folder only holds a
  // handful of files, so the library is deliberately dense and uses names a
  // real photo/video library would have.
  const rootImages = <_SeedImage>[
    _SeedImage('cover_ocean.jpg', 1600, 900, SeedPalette.ocean),
    _SeedImage('cover_sunset.jpg', 1600, 900, SeedPalette.sunset),
    _SeedImage('cover_forest.jpg', 1600, 900, SeedPalette.forest),
    _SeedImage('cover_night_city.jpg', 1600, 900, SeedPalette.violet),
  ];
  const photoImages = <_SeedImage>[
    _SeedImage('beach_sunrise.jpg', 1600, 1067, SeedPalette.sunset),
    _SeedImage('harbour_lights.jpg', 1600, 1067, SeedPalette.ocean),
    _SeedImage('forest_trail.jpg', 1400, 1050, SeedPalette.forest),
    _SeedImage('city_rooftops.jpg', 1600, 1067, SeedPalette.violet),
    _SeedImage('desert_dunes.jpg', 1500, 1000, SeedPalette.sunset),
    _SeedImage('lake_reflection.jpg', 1600, 1067, SeedPalette.ocean),
    _SeedImage('mountain_ridge.jpg', 1400, 1050, SeedPalette.forest),
    _SeedImage('night_market.jpg', 1500, 1000, SeedPalette.violet),
    _SeedImage('vacation_01.jpg', 1200, 900, SeedPalette.forest),
    _SeedImage('vacation_02.jpg', 1200, 900, SeedPalette.violet),
  ];
  const movieImages = <_SeedImage>[
    _SeedImage('poster_northern_lights.jpg', 800, 1200, SeedPalette.ocean),
    _SeedImage('poster_desert_run.jpg', 800, 1200, SeedPalette.sunset),
    _SeedImage('poster_deep_forest.jpg', 800, 1200, SeedPalette.forest),
    _SeedImage('poster_after_dark.jpg', 800, 1200, SeedPalette.violet),
  ];

  final images = <String>[];
  for (final entry in <MapEntry<Directory, List<_SeedImage>>>[
    MapEntry(root, rootImages),
    MapEntry(photos, photoImages),
    MapEntry(movies, movieImages),
  ]) {
    for (final spec in entry.value) {
      final path = p.join(entry.key.path, spec.name);
      seedImage(path,
          width: spec.width, height: spec.height, palette: spec.palette);
      images.add(path);
    }
  }

  final videos = <String>[
    p.join(root.path, 'trailer.mp4'),
    p.join(root.path, 'teaser_cut.mp4'),
    p.join(movies.path, 'feature_film.mp4'),
    p.join(movies.path, 'behind_the_scenes.mp4'),
    p.join(photos.path, 'timelapse_sunset.mp4'),
  ];
  for (final video in videos) {
    seedVideo(video);
  }

  File(p.join(albums.path, 'curation_notes.txt')).writeAsStringSync(
      'Weekend picks, favorite scenes, and smart album rules.');
  File(p.join(albums.path, 'shot_list.txt')).writeAsStringSync(
      'Golden hour at the harbour, rooftop skyline, night market crowd.');
  File(p.join(root.path, 'README.txt')).writeAsStringSync(
      'Showcase media library generated for screenshot automation.');
  File(p.join(root.path, 'export_settings.json'))
      .writeAsStringSync('{"format":"jpeg","quality":92,"longEdge":2560}');

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
  const albumName = 'Weekend Picks';

  // Every scene in a run shares one sandbox database, so the album a previous
  // scene created is still there. Album names are unique, so reuse it rather
  // than making the name unique with a timestamp — that suffix ends up on
  // screen in the gallery and album promo frames.
  final existing = await AlbumService.instance.getAllAlbums();
  final matches = existing.where((album) => album.name == albumName);

  final int albumId;
  if (matches.isNotEmpty) {
    albumId = matches.first.id;
  } else {
    final album = await AlbumService.instance.createAlbum(
      name: albumName,
      description: 'Curated images and videos for showcase screenshots',
      coverImagePath: media.heroImage,
      colorTheme: 'blue',
    );
    if (album == null) {
      throw StateError('Failed to create showcase album');
    }
    albumId = album.id;
  }

  await AlbumService.instance.addFilesToAlbum(
    albumId,
    <String>[...media.images, ...media.videos],
  );
  await FeaturedAlbumsService.instance.addToFeatured(albumId);
  return albumId;
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

  // Attach files to every node so the tree rows render real thumbnails
  // instead of bare colour dots, and the tagged-file panel is never empty.
  final assignable = filePaths.toList();
  if (assignable.isNotEmpty) {
    final nodes = allTags.toList()..sort();
    for (var i = 0; i < assignable.length; i++) {
      final tag = nodes[i % nodes.length];
      await TagManager.addTag(assignable[i], tag);
      if (i < 6) {
        await TagManager.addTag(assignable[i], 'Beach');
      }
      if (i < 4) {
        await TagManager.addTag(assignable[i], 'Action');
      }
    }
  }
}

Future<void> seedWallpaperBackdrop({String theme = 'light'}) async {
  // Deliberately outside the seeded library: that folder is what the file
  // browser scenes render, and a stray wallpaper file would be captured in the
  // promo frame alongside the real media.
  final backdropDir = Directory(
    p.join(Directory.systemTemp.path, 'cb_showcase_backdrop'),
  )..createSync(recursive: true);
  final wallpaperPath = p.join(backdropDir.path, 'showcase_wallpaper.jpg');
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
  await prefs.setString('app_theme', theme);
  await prefs.setString('selected_language', 'en');
}

/// One generated placeholder image in the showcase library.
class _SeedImage {
  final String name;
  final int width;
  final int height;
  final SeedPalette palette;

  const _SeedImage(this.name, this.width, this.height, this.palette);
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
  const sampleName = 'file_example_MP4_1920_18MG.mp4';
  final candidates = <String>[];

  try {
    final scriptStr = Platform.script.toString();
    final scriptPath = scriptStr.startsWith('file:///')
        ? Uri.parse(scriptStr).toFilePath()
        : scriptStr;
    candidates.add(p.join(p.dirname(scriptPath), 'samples', sampleName));
  } catch (_) {
    // Platform.script is not always a usable file URI; fall through.
  }

  // `flutter test` runs from the Flutter project root, where the sample lives
  // next to the integration tests. Without this the videos fall back to a 32
  // byte stub and every video tile renders as an empty placeholder.
  candidates.add(
    p.join(Directory.current.path, 'integration_test', 'samples', sampleName),
  );

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return '';
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
