import 'dart:io';

import 'package:cb_file_manager/services/disk_cleaner/usn_journal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
