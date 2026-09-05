import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/directory_listing_cache_service.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
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
}
