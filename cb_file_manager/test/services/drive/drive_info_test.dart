import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriveInfo.normalizeWindowsRoot', () {
    test('normalizes drive letter paths', () {
      expect(DriveInfo.normalizeWindowsRoot('c:'), 'C:\\');
      expect(DriveInfo.normalizeWindowsRoot('D:/'), 'D:\\');
      expect(DriveInfo.normalizeWindowsRoot('e:\\data'), 'E:\\');
    });
  });

  group('DriveInfo.isWindowsSystemDrive', () {
    test('detects system drive from env letter', () {
      expect(
        DriveInfo.isWindowsSystemDrive('C:\\', systemDrive: 'C:'),
        isTrue,
      );
      expect(
        DriveInfo.isWindowsSystemDrive('D:\\', systemDrive: 'C:'),
        isFalse,
      );
      expect(
        DriveInfo.isWindowsSystemDrive('c:', systemDrive: 'C:\\'),
        isTrue,
      );
    });
  });

  group('DriveSpaceInfo', () {
    test('computes used and ratio from total/free', () {
      final space = DriveSpaceInfo.fromTotalFree(1000, 250);
      expect(space.usedBytes, 750);
      expect(space.usageRatio, closeTo(0.75, 0.0001));
      expect(space.hasDetails, isTrue);
    });

    test('empty has no details', () {
      expect(const DriveSpaceInfo.empty().hasDetails, isFalse);
    });
  });

  group('DriveInfo grouping', () {
    test('maps kinds to groups and sort order', () {
      expect(
        const DriveInfo(path: 'C:\\', displayName: 'C', kind: DriveKind.fixed)
            .group,
        DriveGroup.fixed,
      );
      expect(
        const DriveInfo(
          path: 'E:\\',
          displayName: 'USB',
          kind: DriveKind.removable,
        ).group,
        DriveGroup.removable,
      );
      expect(DriveInfo.groupSortOrder(DriveGroup.fixed), 0);
      expect(DriveInfo.groupSortOrder(DriveGroup.removable), 1);
    });
  });
}
