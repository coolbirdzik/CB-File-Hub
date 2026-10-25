import 'dart:io';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/directory_watcher_service.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Recursive search runs in Rust when package:cb_native is built and falls
/// back to the Dart walker for regexes Rust cannot compile. Both paths must
/// return the same entries with the same types.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late Directory tree;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_native_search_');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    locator.registerSingleton(OperationProgressController());

    tree = await Directory(p.join(root.path, 'tree')).create();
    final nested = await Directory(
      p.join(tree.path, 'Phim Bổ Não', 'deep'),
    ).create(recursive: true);
    await File(p.join(nested.path, 'bo_nao_part1.mkv')).writeAsString('');
    await File(p.join(nested.path, 'unrelated.txt')).writeAsString('');
    await File(p.join(tree.path, 'BO-NAO (final).mp4')).writeAsString('');
    await File(p.join(tree.path, 'other.mp4')).writeAsString('');
  });

  tearDownAll(() async {
    // The singleton watch cancels its Windows handle asynchronously. Wait for
    // that cancellation before removing the test-owned directory tree.
    await DirectoryWatcherService.instance.stopWatching();
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await locator.reset();
    await root.delete(recursive: true);
  });

  Future<Map<String, Type>> search(String query, {bool useRegex = false}) =>
      _runSearch(tree, query, useRegex: useRegex);

  test('finds folded matches in nested folders', () async {
    expect(await search('bo nao'), {
      'Phim Bổ Não': Directory,
      'bo_nao_part1.mkv': File,
      'BO-NAO (final).mp4': File,
    });
  });

  test('regex Rust supports and one only Dart supports agree', () async {
    // Rust's regex crate has no lookbehind, so this runs the Dart walker.
    final dartOnly = await search(r'(?<=^bo.nao).*\.mkv$', useRegex: true);
    expect(dartOnly, {'bo_nao_part1.mkv': File});
    final native = await search(r'^bo.nao.*\.mkv$', useRegex: true);
    expect(native, dartOnly);
  });
}

Future<Map<String, Type>> _runSearch(
  Directory folder,
  String query, {
  required bool useRegex,
}) async {
  final bloc = FolderListBloc();
  try {
    bloc.add(FolderListLoad(folder.path));
    await bloc.stream
        .firstWhere((s) => !s.isLoading && s.files.isNotEmpty)
        .timeout(const Duration(seconds: 10));
    bloc.add(SearchByFileName(query, recursive: true, useRegex: useRegex));
    final state = await bloc.stream
        .firstWhere((s) => !s.isLoading && s.currentSearchQuery == query)
        .timeout(const Duration(seconds: 10));
    return {
      for (final entity in state.searchResults)
        p.basename(entity.path): entity is Directory ? Directory : File,
    };
  } finally {
    await bloc.close();
  }
}
