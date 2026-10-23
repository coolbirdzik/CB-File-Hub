import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/usn_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cb_native/cb_native.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';

void main() {
  test(
    'native USN access errors retain Dart fallback and parent IDs',
    () async {
      expect(await NativeJournalParents.read('invalid-drive', 0, 0), isNull);
      final result = await DiskUsnJournalReader.readChangesAsync(
        drivePath: 'invalid-drive',
        previous: const DiskScanJournalCursor(journalId: 0, nextUsn: 0),
      );
      expect(result.isUsable, isFalse);
      expect(result.parentIds, isEmpty);
      const compact = DiskJournalReadResult(
        isUsable: true,
        changedParentIds: [5, 7],
      );
      expect(compact.parentIds, [5, 7]);
    },
  );

  group('DiskUsnJournalReader.canReadChanges', () {
    test('returns false for a path without a drive prefix', () {
      expect(DiskUsnJournalReader.canReadChanges('not-a-drive'), isFalse);
    });

    test('reports a usable capability only when metadata is available', () {
      if (!Platform.isWindows) {
        expect(DiskUsnJournalReader.canReadChanges('/'), isFalse);
        return;
      }

      final drivePath = Directory.current.absolute.path;
      final canRead = DiskUsnJournalReader.canReadChanges(drivePath);

      if (canRead) {
        expect(DiskUsnJournalReader.readCursor(drivePath), isNotNull);
      }
    });
  });
}
