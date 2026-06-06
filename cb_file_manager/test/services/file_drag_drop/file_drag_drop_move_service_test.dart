import 'dart:io';

import 'package:cb_file_manager/services/file_drag_drop/file_drag_drop_move_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('FileDragDropMoveService.createMovePlan', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('cb_drag_drop_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('rejects moving a folder onto itself', () {
      final folder = Directory(p.join(tempDir.path, 'folder'))..createSync();

      final plan = FileDragDropMoveService.createMovePlan(
        sources: <String>[folder.path],
        destination: folder.path,
      );

      expect(plan.rejection, FileDragDropMoveRejection.selfDrop);
    });

    test('rejects moving a folder into its own descendant', () {
      final parent = Directory(p.join(tempDir.path, 'parent'))..createSync();
      final child = Directory(p.join(parent.path, 'child'))..createSync();

      final plan = FileDragDropMoveService.createMovePlan(
        sources: <String>[parent.path],
        destination: child.path,
      );

      expect(plan.rejection, FileDragDropMoveRejection.descendantDrop);
    });

    test('treats same-parent drops as no-op', () {
      final source = File(p.join(tempDir.path, 'file.txt'))
        ..writeAsStringSync('');

      final plan = FileDragDropMoveService.createMovePlan(
        sources: <String>[source.path],
        destination: tempDir.path,
      );

      expect(plan.rejection, FileDragDropMoveRejection.sameParent);
    });

    test('rejects virtual and network paths', () {
      final plan = FileDragDropMoveService.createMovePlan(
        sources: const <String>['#network/smb/server/share/file.txt'],
        destination: tempDir.path,
      );

      expect(plan.rejection, FileDragDropMoveRejection.nonLocalPath);
    });
  });
}
