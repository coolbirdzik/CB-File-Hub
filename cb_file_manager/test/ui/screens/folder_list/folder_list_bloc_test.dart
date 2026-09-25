import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!locator.isRegistered<OperationProgressController>()) {
      locator.registerSingleton(OperationProgressController());
    }
  });

  test('duplicate drive load cannot put facade back into loading', () async {
    final root = await Directory.systemTemp.createTemp('cb_nav_duplicate_');
    final bloc = FolderListBloc();
    var repeated = false;
    StreamSubscription? subscription;

    try {
      await File(
        '${root.path}${Platform.pathSeparator}visible.txt',
      ).writeAsString('visible');
      DirectoryListingCacheService.instance.clearAll();

      subscription = bloc.stream.listen((state) {
        if (!repeated &&
            state.currentPath.path == root.path &&
            !state.isLoading &&
            state.files.isNotEmpty) {
          repeated = true;
          bloc.add(FolderListLoad(root.path));
        }
      });

      bloc.add(FolderListLoad(root.path));
      await bloc.stream.firstWhere(
        (state) =>
            repeated &&
            state.currentPath.path == root.path &&
            !state.isLoading &&
            state.files.isNotEmpty,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(repeated, isTrue);
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.files.single.path, endsWith('visible.txt'));
    } finally {
      await subscription?.cancel();
      await bloc.close();
      DirectoryListingCacheService.instance.clearAll();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
  group('delete while showing search results', () {
    Future<void> expectDeleteKeepsResultsWithoutRescan(
      Future<void> Function(FolderListBloc bloc, List<File> files) showResults,
    ) async {
      final root = await Directory.systemTemp.createTemp('cb_search_delete_');
      final bloc = FolderListBloc();
      final states = <FolderListState>[];
      StreamSubscription? subscription;

      try {
        final keep = File('${root.path}${Platform.pathSeparator}keep.txt');
        final gone = File('${root.path}${Platform.pathSeparator}gone.txt');
        await keep.writeAsString('keep');
        await gone.writeAsString('gone');
        DirectoryListingCacheService.instance.clearAll();

        await showResults(bloc, [keep, gone]);
        subscription = bloc.stream.listen(states.add);

        bloc.add(
          FolderListDeleteItems(filePaths: [gone.path], permanent: true),
        );
        await bloc.stream.firstWhere(
          (state) => state.searchResults.length == 1,
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(await gone.exists(), isFalse);
        expect(bloc.state.searchResults.single.path, keep.path);
        expect(states.any((state) => state.isRefreshing), isFalse);
        expect(bloc.state.isLoading, isFalse);
      } finally {
        await subscription?.cancel();
        await bloc.close();
        DirectoryListingCacheService.instance.clearAll();
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      }
    }

    test('filename search removes the item without rescanning the folder', () {
      return expectDeleteKeepsResultsWithoutRescan((bloc, files) async {
        bloc.add(FolderListLoad(files.first.parent.path));
        await bloc.stream.firstWhere(
          (state) => !state.isLoading && state.files.length == files.length,
        );
        bloc.add(const SearchByFileName('.txt'));
        await bloc.stream.firstWhere(
          (state) => state.searchResults.length == files.length,
        );
      });
    });

    test('tag search removes the item without rescanning the drive root', () {
      return expectDeleteKeepsResultsWithoutRescan((bloc, files) async {
        bloc.add(SetTagSearchResults(files, 'demo'));
        await bloc.stream.firstWhere(
          (state) => state.searchResults.length == files.length,
        );
      });
    });
  });
}
