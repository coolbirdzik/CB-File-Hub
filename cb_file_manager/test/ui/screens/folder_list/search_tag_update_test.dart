import 'package:cb_file_manager/ui/controllers/selection_tags_controller.dart';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:cb_file_manager/helpers/files/folder_sort_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/components/search_bar.dart'
    as search;
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    hide GlobalMaterialLocalizations, GlobalCupertinoLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_search_tags_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    locator.registerSingleton(OperationProgressController());
    await TagManager.initialize();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await locator.reset();
    await root.delete(recursive: true);
  });

  test(
    'inline tag edits update search membership without a loading reset',
    () async {
      final folder = await Directory(p.join(root.path, 'inline_tags')).create();
      final a = await File(p.join(folder.path, 'a.txt')).writeAsString('a');
      final b = await File(p.join(folder.path, 'b.txt')).writeAsString('b');
      await TagManager.setTags(a.path, ['work', 'keep']);
      await TagManager.setTags(b.path, ['work']);
      final bloc = FolderListBloc();
      final controller = SelectionTagsController();
      try {
        bloc.add(FolderListLoad(folder.path));
        await bloc.stream
            .firstWhere((s) => !s.isLoading && s.files.length == 2)
            .timeout(const Duration(seconds: 10));
        bloc.add(SetTagSearchResults([a, b], 'work'));
        await bloc.stream
            .firstWhere((s) => s.currentSearchTag == 'work')
            .timeout(const Duration(seconds: 10));
        final loadingStates = <bool>[];
        final sub = bloc.stream.listen((s) => loadingStates.add(s.isLoading));
        try {
          await controller.select([a.path]);
          final removed = bloc.stream.firstWhere(
            (s) =>
                s.searchResults.length == 1 &&
                s.searchResults.single.path == b.path,
          );
          await controller.remove('work');
          await removed.timeout(const Duration(seconds: 10));
          expect(await TagManager.getTags(a.path), ['keep']);
          final restored = bloc.stream.firstWhere(
            (s) => s.searchResults.length == 2,
          );
          await controller.add('work');
          await restored.timeout(const Duration(seconds: 10));
          expect(loadingStates, everyElement(isFalse));
          expect(bloc.state.currentSearchTag, 'work');
        } finally {
          await sub.cancel();
        }
      } finally {
        controller.dispose();
        await bloc.close();
      }
    },
  );

  test('virtual tag results follow sort changes and refreshes', () async {
    const tag = 'y tá';
    const tagPath = '#search?tag=y%20t%C3%A1';
    final folder = await Directory(p.join(root.path, 'sort_tags')).create();
    final a = await File(
      p.join(folder.path, 'alpha.txt'),
    ).writeAsString('1234');
    final z = await File(p.join(folder.path, 'zulu.txt')).writeAsString('1');
    await z.setLastModified(DateTime.utc(2025, 1, 1));
    await a.setLastModified(DateTime.utc(2025, 1, 2));
    await TagManager.setTags(a.path, [tag]);
    await TagManager.setTags(z.path, [tag]);
    final hierarchy = TagHierarchyManager.instance;
    expect(await hierarchy.addChild(tag, 'áo'), isTrue);
    expect(await hierarchy.addChild(tag, 'mũ'), isTrue);

    final bloc = FolderListBloc();
    Future<FolderListState> waitForFiles(SortOption sort, List<File> files) =>
        bloc.stream
            .firstWhere((s) {
              final resultFiles = s.searchResults.whereType<File>().toList();
              return !s.isLoading &&
                  s.currentSearchTag == tag &&
                  s.sortOption == sort &&
                  resultFiles.length == files.length &&
                  resultFiles.indexed.every(
                    (e) => e.$2.path == files[e.$1].path,
                  );
            })
            .timeout(const Duration(seconds: 10));

    try {
      final initial = waitForFiles(SortOption.dateDesc, [a, z]);
      bloc.add(
        SearchByTagGlobally(UriUtils.extractTagFromSearchPath(tagPath)!),
      );
      await initial;

      final byName = waitForFiles(SortOption.nameDesc, [z, a]);
      bloc.add(const SetSortOption(SortOption.nameDesc, folderPath: tagPath));
      expect((await byName).searchResults.map((e) => e.path), [
        UriUtils.buildTagSearchPath('mũ'),
        UriUtils.buildTagSearchPath('áo'),
        z.path,
        a.path,
      ]);

      final bySize = waitForFiles(SortOption.sizeDesc, [a, z]);
      bloc.add(const SetSortOption(SortOption.sizeDesc, folderPath: tagPath));
      await bySize;
      expect(
        await FolderSortManager().getFolderSortOption(tagPath),
        SortOption.sizeDesc,
      );

      final m = await File(
        p.join(folder.path, 'middle.txt'),
      ).writeAsString('1234567');
      await TagManager.setTags(m.path, [tag]);
      final refreshed = waitForFiles(SortOption.sizeDesc, [m, a, z]);
      bloc.add(const FolderListRefresh(tagPath));
      await refreshed;
    } finally {
      await bloc.close();
    }
  });

  for (final tagSearch in [false, true]) {
    for (final deleteParent in [false, true]) {
      test(
        '${tagSearch ? 'tag' : 'filename'} results remove deleted ${deleteParent ? 'folder descendants' : 'files'}',
        () async {
          final folder = await Directory(
            p.join(root.path, 'delete_${tagSearch}_$deleteParent'),
          ).create();
          final nested = await Directory(
            p.join(folder.path, 'nested'),
          ).create();
          final deleted = await File(
            p.join(nested.path, 'holiday-one.mp4'),
          ).writeAsString('fixture');
          final retained = await File(
            p.join(folder.path, 'holiday-two.mp4'),
          ).writeAsString('fixture');
          final bloc = FolderListBloc();
          try {
            bloc.add(FolderListLoad(folder.path));
            await bloc.stream
                .firstWhere(
                  (state) => !state.isLoading && state.files.isNotEmpty,
                )
                .timeout(const Duration(seconds: 10));
            if (tagSearch) {
              bloc.add(SetTagSearchResults([deleted, retained], 'videos'));
            } else {
              bloc.add(const SearchByFileName('holiday', recursive: true));
            }
            await bloc.stream
                .firstWhere(
                  (state) =>
                      !state.isLoading && state.searchResults.length == 2,
                )
                .timeout(const Duration(seconds: 10));
            final updated = bloc.stream.firstWhere(
              (state) =>
                  state.searchResults.length == 1 &&
                  state.searchResults.single.path == retained.path,
            );
            // Delete only fixtures created in this test's temporary directory.
            bloc.add(
              FolderListDeleteItems(
                filePaths: deleteParent ? [] : [deleted.path],
                folderPaths: deleteParent ? [nested.path] : [],
                permanent: true,
              ),
            );
            await updated.timeout(const Duration(seconds: 10));
            expect(await deleted.exists(), isFalse);
            expect(await retained.exists(), isTrue);
            expect(
              tagSearch
                  ? bloc.state.currentSearchTag
                  : bloc.state.currentSearchQuery,
              tagSearch ? 'videos' : 'holiday',
            );
            if (tagSearch) expect(bloc.state.searchResultsTotal, 1);

            final tagsUpdated = bloc.stream.firstWhere(
              (state) =>
                  state.fileTags[retained.path]?.contains('favorite') == true,
            );
            await TagManager.addTag(retained.path, 'favorite');
            TagManager.clearCache();
            TagManager.instance.notifyTagChanged(retained.path);
            await tagsUpdated.timeout(const Duration(seconds: 10));
            expect(bloc.state.searchResults.map((file) => file.path), [
              retained.path,
            ]);
            if (!tagSearch) {
              bloc.add(const FolderListFilter('video'));
              await bloc.stream
                  .firstWhere(
                    (state) =>
                        !state.isLoading && state.currentFilter == 'video',
                  )
                  .timeout(const Duration(seconds: 10));
              expect(bloc.state.currentSearchQuery, isNull);
              bloc.add(const SearchByFileName('holiday', recursive: true));
              await bloc.stream
                  .firstWhere(
                    (state) =>
                        !state.isLoading &&
                        state.currentSearchQuery == 'holiday',
                  )
                  .timeout(const Duration(seconds: 10));
              expect(bloc.state.currentFilter, isNull);
              expect(bloc.state.searchResults.single.path, retained.path);
            }
          } finally {
            await bloc.close();
          }
        },
      );
    }
    test(
      '${tagSearch ? 'tag' : 'filename'} results survive tag edits',
      () async {
        final folder = await Directory(
          p.join(root.path, 'videos_$tagSearch'),
        ).create();
        final video = await File(
          p.join(folder.path, 'holiday.mp4'),
        ).writeAsString('');
        await File(p.join(folder.path, 'unrelated.txt')).writeAsString('');
        final bloc = FolderListBloc();
        try {
          bloc.add(FolderListLoad(folder.path));
          await bloc.stream
              .firstWhere(
                (state) => !state.isLoading && state.files.length == 2,
              )
              .timeout(const Duration(seconds: 10));
          if (tagSearch) {
            bloc.add(SetTagSearchResults([video], 'videos'));
          } else {
            bloc.add(const SearchByFileName('holiday'));
          }
          await bloc.stream
              .firstWhere(
                (state) => !state.isLoading && state.searchResults.length == 1,
              )
              .timeout(const Duration(seconds: 10));

          for (final adding in [true, false]) {
            final updated = bloc.stream.firstWhere(
              (state) => adding
                  ? state.fileTags[video.path]?.contains('favorite') == true
                  : !state.fileTags.containsKey(video.path),
            );
            if (adding) {
              await TagManager.addTag(video.path, 'favorite');
            } else {
              await TagManager.removeTag(video.path, 'favorite');
            }
            // The tag dialog invalidates cached metadata and broadcasts after
            // saving; database writes alone do not publish this notification.
            TagManager.clearCache();
            TagManager.instance.notifyTagChanged(video.path);
            await updated.timeout(const Duration(seconds: 10));
            expect(bloc.state.searchResults.map((file) => file.path), [
              video.path,
            ]);
            expect(bloc.state.isLoading, isFalse);
            if (tagSearch) {
              expect(bloc.state.currentSearchTag, 'videos');
            } else {
              expect(bloc.state.currentSearchQuery, 'holiday');
              expect(bloc.state.isSearchByName, isTrue);
            }
          }

          bloc.add(const ClearSearchAndFilters());
          await bloc.stream
              .firstWhere(
                (state) =>
                    state.currentSearchTag == null &&
                    state.currentSearchQuery == null &&
                    state.searchResults.isEmpty,
              )
              .timeout(const Duration(seconds: 10));
          expect(bloc.state.files.length, 2);
        } finally {
          await bloc.close();
        }
      },
    );
  }

  testWidgets('search double-click selects a word without changing the query', (
    tester,
  ) async {
    final queries = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Center(
          child: search.SearchBar(
            currentPath: root.path,
            tabId: 'search-test',
            onCloseSearch: () {},
            initialQuery: 'holiday video',
            onQueryChanged: queries.add,
            showTagSearch: false,
            showTipsButton: false,
            showGlobalSearchToggle: false,
            showRegexToggle: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final position = render.localToGlobal(
      render.getLocalRectForCaret(const TextPosition(offset: 3)).center,
    );
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(position, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(
      editable.controller.selection.textInside(editable.controller.text),
      'holiday',
    );
    expect(queries, isEmpty);
    await tester.enterText(find.byType(TextField), 'new query');
    expect(queries, ['new query']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
