import 'package:cb_file_manager/services/drive/android_storage_volumes.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/services/drive/drive_inventory_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidStorageVolume.fromMap', () {
    test('parses required and optional fields', () {
      final volume = AndroidStorageVolume.fromMap(<String, dynamic>{
        'path': '/storage/XXXX-YYYY',
        'label': 'SD card',
        'uuid': 'XXXX-YYYY',
        'description': 'SD card',
        'isPrimary': false,
        'isRemovable': true,
        'canEject': true,
        'totalBytes': 1000,
        'freeBytes': 400,
        'filesystem': 'exfat',
      });

      expect(volume.path, '/storage/XXXX-YYYY');
      expect(volume.label, 'SD card');
      expect(volume.canEject, isTrue);
      expect(volume.totalBytes, 1000);
      expect(volume.freeBytes, 400);
    });

    test('tolerates missing optional fields', () {
      final volume = AndroidStorageVolume.fromMap(<String, dynamic>{
        'path': '/storage/emulated/0',
        'isPrimary': true,
        'isRemovable': false,
      });
      expect(volume.path, '/storage/emulated/0');
      expect(volume.label, isEmpty);
      expect(volume.canEject, isFalse);
    });
  });

  group('DriveInventoryService cache', () {
    test('invalidate clears freshness', () {
      DriveInventoryService.invalidateCache();
      expect(DriveInventoryService.hasFreshCache, isFalse);
      expect(DriveInventoryService.cachedSnapshot, isNull);
    });
  });

  group('DriveInfo system eject eligibility helpers', () {
    test('system volumes must not be ejectable by policy', () {
      const system = DriveInfo(
        path: 'C:\\',
        displayName: 'C:\\',
        kind: DriveKind.fixed,
        isSystemVolume: true,
        canEject: false,
      );
      const usb = DriveInfo(
        path: 'E:\\',
        displayName: 'USB',
        kind: DriveKind.removable,
        isRemovable: true,
        canEject: true,
        isSystemVolume: false,
      );
      expect(system.canEject, isFalse);
      expect(usb.canEject, isTrue);
    });
  });
}
