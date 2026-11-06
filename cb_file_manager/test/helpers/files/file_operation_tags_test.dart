import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/helpers/files/windows_file_operations.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/file_drag_drop/file_drag_drop_move_service.dart';
import 'package:cb_file_manager/services/windowing/windows_file_clipboard.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_navigation_event.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_operations_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/bloc/file_operations_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingNavigationBloc extends FileNavigationBloc {
  // Transfers are real; suppress unrelated directory scans in this unit test.
  @override
  void add(FileNavigationEvent event) {}
}

class _ExplorerClipboard extends WindowsFileClipboard {
  WindowsFileClipboardSnapshot snapshot = const WindowsFileClipboardSnapshot(
    sequence: 1,
    paths: [],
  );
  Future<WindowsFileClipboardSnapshot?> Function()? onRead;
  int reads = 0;

  @override
  int get sequenceNumber => snapshot.sequence;

  @override
  Future<WindowsFileClipboardSnapshot?> read() async {
    reads++;
    return onRead == null ? snapshot : onRead!();
  }

  void copy(List<String> paths, {bool cut = false}) {
    snapshot = WindowsFileClipboardSnapshot(
      sequence: snapshot.sequence + 1,
      paths: paths,
      isCut: cut,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const operations = MethodChannel('cb_file_manager/file_operations');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late Directory fixture;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_transfer_tags_');
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(paths, (_) async => root.path);
    await TagManager.initialize();
  });

  setUp(() async {
    fixture = await root.createTemp('case_');
    FileOperations().clearClipboard();
    messenger.setMockMethodCallHandler(operations, null);
  });

  tearDownAll(() async {
    FileOperations().clearClipboard();
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    messenger.setMockMethodCallHandler(paths, null);
    messenger.setMockMethodCallHandler(operations, null);
    await root.delete(recursive: true);
  });

  Future<File> taggedFile(String path, List<String> tags) async {
    await Directory(p.dirname(path)).create(recursive: true);
    final file = await File(path).writeAsString('tagged content');
    expect(await TagManager.setTags(path, tags), isTrue);
    return file;
  }

  test(
    'Explorer copy pastes Unicode files and folders with an empty app clipboard',
    () async {
      final source = await taggedFile(p.join(fixture.path, 'ảnh Việt.txt'), [
        'photo',
      ]);
      final folder = await Directory(p.join(fixture.path, 'Thư mục')).create();
      await File(
        p.join(folder.path, 'child.txt'),
      ).writeAsString('folder content');
      final clipboard = _ExplorerClipboard()..copy([source.path, folder.path]);
      final ops = FileOperations.forTesting(clipboard);
      expect(ops.hasClipboardItem, isFalse);
      final destination = await Directory(
        p.join(fixture.path, 'target'),
      ).create();

      await ops.pasteFromClipboard(destination.path);

      expect(
        await File(p.join(destination.path, 'ảnh Việt.txt')).readAsString(),
        'tagged content',
      );
      expect(
        await File(
          p.join(destination.path, 'Thư mục', 'child.txt'),
        ).readAsString(),
        'folder content',
      );
      expect(await source.exists(), isTrue);
      expect(await folder.exists(), isTrue);
      expect(ops.clipboardItems.last, isA<Directory>());
      expect(
        await TagManager.getTags(p.join(destination.path, 'ảnh Việt.txt')),
        ['photo'],
      );
      final another = await Directory(p.join(fixture.path, 'another')).create();
      await ops.pasteFromClipboard(another.path);
      expect(await File(p.join(another.path, 'ảnh Việt.txt')).exists(), isTrue);
      expect(clipboard.reads, 1);
    },
  );

  test('a newer Explorer copy replaces a stale app selection', () async {
    final clipboard = _ExplorerClipboard();
    final ops = FileOperations.forTesting(clipboard);
    ops.cutToClipboard(File('old.txt'));
    clipboard.copy([p.join(fixture.path, 'new.txt')]);

    await ops.syncSystemClipboard();

    expect(ops.clipboardItems.single.path, p.join(fixture.path, 'new.txt'));
    expect(ops.isCutOperation, isFalse);
  });

  test('an app copy wins over an unchanged Explorer clipboard', () async {
    final clipboard = _ExplorerClipboard()..copy(['explorer.txt']);
    final ops = FileOperations.forTesting(clipboard);
    ops.copyToClipboard(File('app.txt'));

    await ops.syncSystemClipboard();

    expect(ops.clipboardItems.single.path, 'app.txt');
    expect(clipboard.reads, 0);
  });

  test(
    'replacing Explorer files with text clears the stale file selection',
    () async {
      final clipboard = _ExplorerClipboard()..copy(['explorer.txt']);
      final ops = FileOperations.forTesting(clipboard);
      await ops.syncSystemClipboard();
      clipboard.copy([]);

      await ops.syncSystemClipboard();

      expect(ops.hasClipboardItem, isFalse);
    },
  );

  test('an app copy during the Windows read is preserved', () async {
    final clipboard = _ExplorerClipboard()..copy(['explorer.txt']);
    final ops = FileOperations.forTesting(clipboard);
    clipboard.onRead = () async {
      ops.copyToClipboard(File('new-app.txt'));
      return clipboard.snapshot;
    };

    await ops.syncSystemClipboard();

    expect(ops.clipboardItems.single.path, 'new-app.txt');
  });

  test(
    'a Windows clipboard change during the read retries the newer selection',
    () async {
      final clipboard = _ExplorerClipboard()..copy(['old.txt']);
      final ops = FileOperations.forTesting(clipboard);
      clipboard.onRead = () async {
        final old = clipboard.snapshot;
        clipboard.copy(['new.txt']);
        clipboard.onRead = null;
        return old;
      };

      await ops.syncSystemClipboard();

      expect(ops.clipboardItems.single.path, 'new.txt');
      expect(clipboard.reads, 2);
    },
  );

  test(
    'a failed Windows clipboard read does not paste the stale app selection',
    () async {
      final clipboard = _ExplorerClipboard();
      final ops = FileOperations.forTesting(clipboard);
      ops.copyToClipboard(File('old.txt'));
      clipboard.copy(['new.txt']);
      clipboard.onRead = () async => throw const OSError('Clipboard busy', 5);

      await expectLater(
        ops.pasteFromClipboard(fixture.path),
        throwsA(isA<OSError>()),
      );
    },
  );

  test('Explorer cut moves once and accepts a later copy', () async {
    final source = await taggedFile(p.join(fixture.path, 'cut.txt'), ['move']);
    final next = await taggedFile(p.join(fixture.path, 'next.txt'), ['next']);
    final destination = await Directory(
      p.join(fixture.path, 'target'),
    ).create();
    final clipboard = _ExplorerClipboard()..copy([source.path], cut: true);
    final ops = FileOperations.forTesting(clipboard);

    await ops.pasteFromClipboard(destination.path);
    expect(await source.exists(), isFalse);
    expect(await File(p.join(destination.path, 'cut.txt')).exists(), isTrue);
    await ops.syncSystemClipboard();
    expect(ops.hasClipboardItem, isFalse);
    expect(clipboard.reads, 1);

    clipboard.copy([next.path]);
    await ops.syncSystemClipboard();
    expect(ops.clipboardItems.single.path, next.path);
    expect(ops.isCutOperation, isFalse);
  });

  test(
    'Explorer copy during a cut transfer is available on the next paste',
    () async {
      final source = await taggedFile(p.join(fixture.path, 'cut.txt'), [
        'move',
      ]);
      final next = await taggedFile(p.join(fixture.path, 'next.txt'), ['next']);
      final destination = await Directory(
        p.join(fixture.path, 'target'),
      ).create();
      final clipboard = _ExplorerClipboard()..copy([source.path], cut: true);
      final ops = FileOperations.forTesting(clipboard);

      await ops.pasteFromClipboard(
        destination.path,
        onProgress: (completed, _) {
          if (completed == 0) clipboard.copy([next.path]);
        },
      );
      await ops.syncSystemClipboard();

      expect(await source.exists(), isFalse);
      expect(ops.clipboardItems.single.path, next.path);
      expect(ops.isCutOperation, isFalse);
    },
  );

  for (final move in [false, true]) {
    test(
      'Dart ${move ? 'move' : 'copy'} keeps its inputs when clipboard changes',
      () async {
        final source = await taggedFile(p.join(fixture.path, 'a.txt'), [
          'work',
        ]);
        final other = await taggedFile(p.join(fixture.path, 'b.txt'), [
          'other',
        ]);
        final destination = await Directory(
          p.join(fixture.path, 'target'),
        ).create();
        final ops = FileOperations();
        if (move) {
          ops.cutToClipboard(source);
        } else {
          ops.copyToClipboard(source);
        }
        final result = await ops.pasteFromClipboard(
          destination.path,
          onProgress: (completed, _) {
            if (completed != 0) return;
            if (move) {
              ops.copyToClipboard(other);
            } else {
              ops.cutToClipboard(other);
            }
          },
        );

        expect(await source.exists(), !move);
        expect(await File(result.single.path).readAsString(), 'tagged content');
        expect(await TagManager.getTags(result.single.path), ['work']);
        expect(ops.clipboardItems.map((item) => item.path), [other.path]);
        expect(ops.isCutOperation, !move);
        expect(await other.exists(), isTrue);
      },
    );

    test(
      'Dart ${move ? 'move' : 'copy'} carries file tags to a unique name',
      () async {
        final source = await taggedFile(
          p.join(fixture.path, 'source', 'a.txt'),
          ['work', 'Việt Nam'],
        );
        final destination = await Directory(
          p.join(fixture.path, 'target'),
        ).create();
        final existing = await taggedFile(p.join(destination.path, 'a.txt'), [
          'existing',
        ]);
        // A missing native plugin exercises the production Dart fallback.
        final ops = FileOperations();
        if (move) {
          ops.cutToClipboard(source);
        } else {
          ops.copyToClipboard(source);
        }
        final result = await ops.pasteFromClipboard(destination.path);
        expect(result.single.path, p.join(destination.path, 'a_1.txt'));
        expect(await File(result.single.path).readAsString(), 'tagged content');
        expect(
          await TagManager.getTags(result.single.path),
          unorderedEquals(['work', 'Việt Nam']),
        );
        expect(
          await TagManager.getTags(source.path),
          move ? isEmpty : unorderedEquals(['work', 'Việt Nam']),
        );
        expect(await source.exists(), !move);
        expect(await TagManager.getTags(existing.path), ['existing']);
        // Verify the persisted metadata independently of the tag cache.
        expect(
          await DatabaseManager.getInstance().getTagsForFile(
            result.single.path,
          ),
          unorderedEquals(['work', 'Việt Nam']),
        );
      },
    );

    test(
      'Dart ${move ? 'move' : 'copy'} carries folder and nested file tags',
      () async {
        final source = await Directory(p.join(fixture.path, 'album')).create();
        final child = await taggedFile(
          p.join(source.path, 'nested', 'photo.jpg'),
          ['photo'],
        );
        await TagManager.setTags(source.path, ['album']);
        final sibling = await taggedFile(
          p.join(fixture.path, 'album-other', 'photo.jpg'),
          ['other'],
        );
        final destination = await Directory(
          p.join(fixture.path, 'target'),
        ).create();
        final ops = FileOperations();
        if (move) {
          ops.cutToClipboard(source);
        } else {
          ops.copyToClipboard(source);
        }
        final result = await ops.pasteFromClipboard(destination.path);
        expect(await TagManager.getTags(result.single.path), ['album']);
        expect(
          await TagManager.getTags(
            p.join(result.single.path, 'nested', 'photo.jpg'),
          ),
          ['photo'],
        );
        expect(
          await TagManager.getTags(child.path),
          move ? isEmpty : ['photo'],
        );
        expect(
          await TagManager.getTags(source.path),
          move ? isEmpty : ['album'],
        );
        expect(await TagManager.getTags(sibling.path), ['other']);
      },
    );

    test(
      'native ${move ? 'move' : 'copy'} uses actual names and keeps skipped tags on cancellation',
      () async {
        final source = await taggedFile(
          p.join(fixture.path, 'source', 'a.txt'),
          ['work'],
        );
        final skipped = await taggedFile(
          p.join(fixture.path, 'source', 'b.txt'),
          ['skip'],
        );
        final destination = await Directory(
          p.join(fixture.path, 'target'),
        ).create();
        final existing = await taggedFile(p.join(destination.path, 'a.txt'), [
          'existing',
        ]);
        final actual = p.join(destination.path, 'a (2).txt');
        messenger.setMockMethodCallHandler(operations, (call) async {
          expect(call.method, move ? 'moveItems' : 'copyItems');
          expect((call.arguments as Map)['returnResults'], isTrue);
          await source.copy(actual);
          if (move) await source.delete();
          return {
            'success': false,
            'items': [
              {'source': source.path, 'destination': actual},
            ],
          };
        });
        final success = await WindowsFileOperations.transferItems(
          sources: [source.path, skipped.path],
          destination: destination.path,
          isMove: move,
        );
        expect(success, isFalse);
        expect(await TagManager.getTags(actual), ['work']);
        expect(await TagManager.getTags(existing.path), ['existing']);
        expect(await TagManager.getTags(skipped.path), ['skip']);
        expect(
          await TagManager.getTags(source.path),
          move ? isEmpty : ['work'],
        );
        expect(
          await TagManager.getTags(p.join(destination.path, 'b.txt')),
          isEmpty,
        );
      },
    );
  }

  test('a completed move preserves a newer cut clipboard', () async {
    final source = await taggedFile(p.join(fixture.path, 'a.txt'), ['work']);
    final next = await taggedFile(p.join(fixture.path, 'b.txt'), ['next']);
    final destination = await Directory(
      p.join(fixture.path, 'target'),
    ).create();
    final ops = FileOperations();
    messenger.setMockMethodCallHandler(operations, (call) async {
      ops.cutToClipboard(next);
      final target = p.join(destination.path, p.basename(source.path));
      await source.rename(target);
      return {
        'success': true,
        'items': [
          {'source': source.path, 'destination': target},
        ],
      };
    });
    ops.cutToClipboard(source);
    await ops.pasteFromClipboard(destination.path);
    expect(ops.clipboardItems.map((item) => item.path), [next.path]);
    expect(ops.isCutOperation, isTrue);
    expect(await source.exists(), isFalse);
    expect(await next.exists(), isTrue);
    expect(await TagManager.getTags(p.join(destination.path, 'a.txt')), [
      'work',
    ]);
  }, skip: !Platform.isWindows);

  test(
    'paste tasks overlap and finish independently in the same bloc',
    () async {
      final first = await taggedFile(p.join(fixture.path, 'a.txt'), ['copy']);
      final second = await taggedFile(p.join(fixture.path, 'b.txt'), ['move']);
      final third = await taggedFile(p.join(fixture.path, 'c.txt'), ['next']);
      final firstTarget = await Directory(p.join(fixture.path, 'one')).create();
      final secondTarget = await Directory(
        p.join(fixture.path, 'two'),
      ).create();
      final started = [Completer<void>(), Completer<void>()];
      final release = [Completer<void>(), Completer<void>()];
      var calls = 0;
      messenger.setMockMethodCallHandler(operations, (call) async {
        final index = calls++;
        final args = call.arguments as Map;
        final source = (args['sources'] as List).single as String;
        final destination = p.join(
          args['destination'] as String,
          p.basename(source),
        );
        expect(call.method, index == 0 ? 'copyItems' : 'moveItems');
        expect(source, index == 0 ? first.path : second.path);
        started[index].complete();
        await release[index].future;
        if (call.method == 'moveItems') {
          await File(source).rename(destination);
        } else {
          await File(source).copy(destination);
        }
        return {
          'success': true,
          'items': [
            {'source': source, 'destination': destination},
          ],
        };
      });
      final navigation = _RecordingNavigationBloc();
      final progress = OperationProgressController();
      final bloc = FileOperationsBloc(
        navigationBloc: navigation,
        progressController: progress,
      );
      addTearDown(() async {
        for (final gate in release) {
          if (!gate.isCompleted) gate.complete();
        }
        await bloc.close();
        await navigation.close();
        progress.dispose();
      });
      final ops = FileOperations();
      ops.copyToClipboard(first);
      bloc.add(FileOperationsPaste(firstTarget.path));
      await started[0].future.timeout(const Duration(seconds: 5));

      ops.cutToClipboard(second);
      bloc.add(FileOperationsPaste(secondTarget.path));
      // Both calls must reach the backend before either is allowed to finish.
      await started[1].future.timeout(const Duration(seconds: 5));
      expect(progress.runningCount, 2);
      expect(bloc.state.isProcessing, isTrue);

      final firstFinished = bloc.stream.firstWhere(
        (s) => s.clipboardRevision == 1,
      );
      release[0].complete();
      await firstFinished.timeout(const Duration(seconds: 5));
      expect(progress.runningCount, 1);
      expect(bloc.state.isProcessing, isTrue);
      expect(ops.clipboardItems.map((item) => item.path), [second.path]);
      expect(ops.isCutOperation, isTrue);

      ops.copyToClipboard(third);
      final allFinished = bloc.stream.firstWhere((s) => !s.isProcessing);
      release[1].complete();
      await allFinished.timeout(const Duration(seconds: 5));
      expect(progress.runningCount, 0);
      expect(progress.finishedEntries, hasLength(2));
      expect(ops.clipboardItems.map((item) => item.path), [third.path]);
      expect(ops.isCutOperation, isFalse);
      expect(await first.exists(), isTrue);
      expect(await second.exists(), isFalse);
      expect(await TagManager.getTags(p.join(firstTarget.path, 'a.txt')), [
        'copy',
      ]);
      expect(await TagManager.getTags(p.join(secondTarget.path, 'b.txt')), [
        'move',
      ]);
      expect(
        await File(p.join(firstTarget.path, 'a.txt')).readAsString(),
        'tagged content',
      );
      expect(
        await File(p.join(secondTarget.path, 'b.txt')).readAsString(),
        'tagged content',
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'native whole-folder move transfers descendants and honors nested renames',
    () async {
      final source = await Directory(p.join(fixture.path, 'album')).create();
      final child = await taggedFile(p.join(source.path, 'photo.jpg'), [
        'photo',
      ]);
      await TagManager.setTags(source.path, ['album']);
      final destination = await Directory(
        p.join(fixture.path, 'target'),
      ).create();
      final target = p.join(destination.path, 'album');
      messenger.setMockMethodCallHandler(operations, (call) async {
        await source.rename(target);
        await File(
          p.join(target, 'photo.jpg'),
        ).rename(p.join(target, 'photo (2).jpg'));
        await taggedFile(p.join(target, 'photo.jpg'), ['existing']);
        return {
          'success': true,
          'items': [
            {'source': source.path, 'destination': target},
            {
              'source': child.path,
              'destination': p.join(target, 'photo (2).jpg'),
            },
          ],
        };
      });
      expect(
        await WindowsFileOperations.transferItems(
          sources: [source.path],
          destination: destination.path,
          isMove: true,
        ),
        isTrue,
      );
      expect(await TagManager.getTags(target), ['album']);
      expect(await TagManager.getTags(p.join(target, 'photo (2).jpg')), [
        'photo',
      ]);
      expect(await TagManager.getTags(p.join(target, 'photo.jpg')), [
        'existing',
      ]);
      expect(await TagManager.getTags(child.path), isEmpty);
    },
  );

  test(
    'native folder copy transfers only completed children during a merge',
    () async {
      final source = await Directory(p.join(fixture.path, 'album')).create();
      final copied = await taggedFile(p.join(source.path, 'photo.jpg'), [
        'photo',
      ]);
      final skipped = await taggedFile(p.join(source.path, 'skip.jpg'), [
        'source-only',
      ]);
      await TagManager.setTags(source.path, ['album']);
      final destination = await Directory(
        p.join(fixture.path, 'target'),
      ).create();
      final target = await Directory(
        p.join(destination.path, 'album'),
      ).create();
      final existing = await taggedFile(p.join(target.path, 'skip.jpg'), [
        'existing',
      ]);
      final actual = p.join(target.path, 'photo (2).jpg');
      messenger.setMockMethodCallHandler(operations, (call) async {
        await copied.copy(actual);
        return {
          'success': true,
          'items': [
            {'source': source.path, 'destination': target.path},
            {'source': copied.path, 'destination': actual},
          ],
        };
      });
      expect(
        await WindowsFileOperations.transferItems(
          sources: [source.path],
          destination: destination.path,
          isMove: false,
        ),
        isTrue,
      );
      expect(await TagManager.getTags(target.path), ['album']);
      expect(await TagManager.getTags(actual), ['photo']);
      expect(await TagManager.getTags(existing.path), ['existing']);
      expect(await TagManager.getTags(skipped.path), ['source-only']);
      expect(await TagManager.getTags(copied.path), ['photo']);
    },
  );

  test('drag move retains tags for a file and a whole folder', () async {
    final source = await taggedFile(p.join(fixture.path, 'a.txt'), ['work']);
    final folder = await Directory(p.join(fixture.path, 'album')).create();
    final child = await taggedFile(p.join(folder.path, 'nested', 'photo.jpg'), [
      'photo',
    ]);
    final destination = await Directory(
      p.join(fixture.path, 'target'),
    ).create();
    messenger.setMockMethodCallHandler(operations, (call) async {
      final items = <Map<String, String>>[];
      for (final path in (call.arguments as Map)['sources'] as List) {
        final target = p.join(destination.path, p.basename(path as String));
        if (Directory(path).existsSync()) {
          await Directory(path).rename(target);
        } else {
          await File(path).rename(target);
        }
        items.add({'source': path, 'destination': target});
      }
      return {'success': true, 'items': items};
    });
    expect(
      await FileDragDropMoveService.move(
        sources: [source.path, folder.path],
        destination: destination.path,
      ),
      FileDragDropMoveRejection.none,
    );
    expect(await TagManager.getTags(p.join(destination.path, 'a.txt')), [
      'work',
    ]);
    expect(
      await TagManager.getTags(
        p.join(destination.path, 'album', 'nested', 'photo.jpg'),
      ),
      ['photo'],
    );
    expect(await TagManager.getTags(source.path), isEmpty);
    expect(await TagManager.getTags(child.path), isEmpty);
  });
}
