import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'package:cb_file_manager/services/file_metadata_service.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Metadata extends FileMetadataService {
  Completer<void>? gate;
  Completer<void>? started;
  @override
  Future<int?> getFolderItemCount(String folderPath) async {
    if (started?.isCompleted == false) started!.complete();
    await gate?.future;
    return p.basename(folderPath) == 'z-two' ? 2 : 10;
  }
}

class _Navigation extends FileNavigationBloc {
  _Navigation(Directory root) {
    emit(
      state.copyWith(
        currentPath: root,
        folders: [
          Directory(p.join(root.path, 'a-ten')),
          Directory(p.join(root.path, 'z-two')),
        ],
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FileNavigationBloc bloc;
  late _Metadata metadata;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cb-metadata-navigation-');
    await Directory(p.join(root.path, 'a-ten')).create();
    await Directory(p.join(root.path, 'z-two')).create();
    metadata = _Metadata();
    locator.registerSingleton<FileMetadataService>(metadata);
    bloc = _Navigation(root);
  });
  tearDown(() async {
    if (!bloc.isClosed) await bloc.close();
    await DirectoryWatcherService.instance.stopWatching();
    await locator.unregister<FileMetadataService>();
    await root.delete(recursive: true);
  });

  test('folder sorting waits for metadata and toggles numeric order', () async {
    for (final sort in [SortOption.itemCountAsc, SortOption.itemCountDesc]) {
      final sorted = bloc.stream.firstWhere(
        (s) => !s.isLoading && s.sortOption == sort,
      );
      bloc.add(FileNavigationSetSortOption(sort, persist: false));
      final state = await sorted.timeout(const Duration(seconds: 10));
      expect(
        state.folders.map((e) => p.basename(e.path)),
        sort.ascending ? ['z-two', 'a-ten'] : ['a-ten', 'z-two'],
      );
      expect(state.error, isNull);
    }
  });

  test('a late metadata result cannot replace a newer sort choice', () async {
    final gate = metadata.gate = Completer<void>();
    final started = metadata.started = Completer<void>();
    bloc.add(
      const FileNavigationSetSortOption(
        SortOption.itemCountAsc,
        persist: false,
      ),
    );
    await started.future.timeout(const Duration(seconds: 10));
    final changed = bloc.stream.firstWhere(
      (s) => !s.isLoading && s.sortOption == SortOption.nameDesc,
    );
    bloc.add(
      const FileNavigationSetSortOption(SortOption.nameDesc, persist: false),
    );
    await changed.timeout(const Duration(seconds: 10));
    gate.complete();
    await bloc.close();
    expect(bloc.state.sortOption, SortOption.nameDesc);
    expect(bloc.state.folders.map((e) => p.basename(e.path)), [
      'z-two',
      'a-ten',
    ]);
  });
}
