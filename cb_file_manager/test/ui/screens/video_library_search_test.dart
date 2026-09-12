import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'dart:io';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_file_surface.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/video_library/video_library_files_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/components/search_bar.dart'
    as search;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import 'network_browsing/network_recovery_test.dart' show host;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb-library-search-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          // This widget test exercises metadata, not background debug-log IO.
          if (call.method == 'getTemporaryDirectory') return null;
          return root.path;
        });
    locator.registerSingleton(OperationProgressController());
    await TagManager.initialize();
  });
  tearDownAll(() async {
    await DirectoryWatcherService.instance.stopWatching();
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await locator.reset();
    await root.delete(recursive: true);
  });

  testWidgets('refresh retains query and removes deleted video from search', (
    tester,
  ) async {
    final service = VideoLibraryService();
    final media = await tester.runAsync(() async {
      final directory = await Directory(path.join(root.path, 'media')).create();
      await File(path.join(directory.path, 'holiday.mp4')).writeAsBytes([0]);
      await File(path.join(directory.path, 'other.mp4')).writeAsBytes([0]);
      return directory;
    });
    final library = await tester.runAsync(
      () => service.createLibrary(
        name: 'Search refresh',
        directories: [media!.path],
      ),
    );
    await tester.pumpWidget(host(VideoLibraryFilesScreen(library: library!)));

    BrowserLikeFileSurface surface() => tester.widget<BrowserLikeFileSurface>(
      find.byType(BrowserLikeFileSurface),
    );
    Future<void> waitFor(bool Function() predicate) async {
      for (var i = 0; i < 150 && !predicate(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(predicate(), isTrue);
    }

    await waitFor(
      () =>
          find.byType(BrowserLikeFileSurface).evaluate().isNotEmpty &&
          surface().visiblePaths.length == 2,
    );
    final bar = surface().searchBar as search.SearchBar;
    bar.onSearchWithOptions!('holiday', false);
    await waitFor(() => surface().visiblePaths.length == 1);
    // Let the separate live search source finish before mutating the filesystem.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    final deleted = File(path.join(media!.path, 'holiday.mp4'));
    await tester.runAsync(deleted.delete);
    surface().onRefresh!();
    await waitFor(() => surface().visiblePaths.isEmpty);
    expect((surface().searchBar as search.SearchBar).initialQuery, 'holiday');
    await tester.pumpWidget(const SizedBox.shrink());
    // Drain real filesystem completions and their fake-async continuations.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });
}
