import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/services/pending_file_deletions.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_operations_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_operations_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Navigation extends Fake implements FileNavigationBloc {
  @override
  void add(FileNavigationEvent event) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'delete events mark every target pending until the worker responds',
    () async {
      const channel = MethodChannel('cb_file_manager/file_operations');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final entered = Completer<void>();
      final response = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'deleteItems') {
          entered.complete();
          return response.future;
        }
        return null;
      });
      final progress = OperationProgressController();
      final bloc = FileOperationsBloc(
        navigationBloc: _Navigation(),
        progressController: progress,
        isShowingSearchResults: () => true,
      );
      const file = r'C:\pending-test\file.tmp';
      const folder = r'C:\pending-test\folder';
      try {
        bloc.add(
          const FileOperationsDeleteItems(
            filePaths: [file],
            folderPaths: [folder],
          ),
        );
        await entered.future;
        expect(PendingFileDeletions.instance.contains(file), isTrue);
        expect(PendingFileDeletions.instance.contains(folder), isTrue);
        response.complete(true);
        await bloc.close();
        expect(PendingFileDeletions.instance.contains(file), isFalse);
        expect(PendingFileDeletions.instance.contains(folder), isFalse);
      } finally {
        if (!response.isCompleted) response.complete(true);
        if (!bloc.isClosed) await bloc.close();
        progress.dispose();
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
    skip: !Platform.isWindows,
  );
}
