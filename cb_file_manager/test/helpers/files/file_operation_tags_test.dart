import 'dart:io';

import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/helpers/files/windows_file_operations.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/file_drag_drop/file_drag_drop_move_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

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

  for (final move in [false, true]) {
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
