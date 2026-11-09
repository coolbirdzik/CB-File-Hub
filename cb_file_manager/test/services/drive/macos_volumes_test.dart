import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/services/disk_cleaner/macos_cleaner_platform.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:cb_file_manager/services/drive/macos_volumes.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _boot = <String, Object?>{
  'path': '/',
  'label': 'Macintosh HD',
  'filesystem': 'APFS',
  'totalBytes': 1000,
  'freeBytes': 400,
  'isRoot': true,
  'isLocal': true,
  'isInternal': true,
  'isRemovable': false,
  'isEjectable': false,
};
const _external = <String, Object?>{
  'path': '/Volumes/My SSD',
  'label': 'My SSD',
  'filesystem': 'ExFAT',
  'totalBytes': 2000,
  'freeBytes': 1500,
  'isRoot': false,
  'isLocal': true,
  'isInternal': false,
  'isRemovable': true,
  'isEjectable': true,
};
const _share = <String, Object?>{
  'path': '/Volumes/Team',
  'label': 'Team',
  'isRoot': false,
  'isLocal': false,
};
const _partition = <String, Object?>{
  'path': '/Volumes/Data Two',
  'label': 'Data Two',
  'isRoot': false,
  'isLocal': true,
  'isInternal': true,
};

void _answerWith(Future<Object?> Function(MethodCall call) handler) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(MacosCleanerPlatform.channel, handler);
  addTearDown(
    () =>
        messenger.setMockMethodCallHandler(MacosCleanerPlatform.channel, null),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MacosVolume', () {
    test('the boot volume is a fixed system drive at /', () {
      final drive = MacosVolume.fromMap(_boot).toDrive();
      expect(drive.path, '/');
      expect(drive.displayName, 'Macintosh HD');
      expect(drive.kind, DriveKind.fixed);
      expect(drive.isSystemVolume, isTrue);
      expect(drive.isPrimary, isTrue);
      expect(drive.filesystem, 'APFS');
      expect(drive.space.usedBytes, 600);
    });

    test('external disks are removable, shares are network', () {
      expect(MacosVolume.fromMap(_external).kind, DriveKind.removable);
      expect(MacosVolume.fromMap(_share).kind, DriveKind.network);
      expect(MacosVolume.fromMap(_partition).kind, DriveKind.fixed);
    });

    test('offers no action the Mac path cannot perform', () {
      final drive = MacosVolume.fromMap(_external).toDrive();
      expect(drive.isRemovable, isTrue);
      expect(drive.canEject, isFalse);
      expect(drive.canRename, isFalse);
    });

    test('an unnamed volume shows its path', () {
      final volume = MacosVolume.fromMap(const {'path': '/Volumes/X'});
      expect(volume.displayName, '/Volumes/X');
      expect(volume.isRoot, isFalse);
    });
  });

  group('MacosVolumes.list', () {
    test('puts the boot volume first, then local, external, network', () async {
      _answerWith((call) async {
        expect(call.method, 'getMountedVolumes');
        return [_share, _external, _partition, _boot];
      });
      final volumes = await MacosVolumes.list();
      expect(volumes.map((volume) => volume.path), [
        '/',
        '/Volumes/Data Two',
        '/Volumes/My SSD',
        '/Volumes/Team',
      ]);
    });

    test('keeps the boot volume when the native list fails', () async {
      _answerWith((call) async => throw PlatformException(code: 'failed'));
      final volumes = await MacosVolumes.list();
      expect(volumes.single.path, '/');
      expect(volumes.single.isRoot, isTrue);
    });

    test('ignores rows without a path', () async {
      _answerWith(
        (call) async => [
          {'label': 'broken'},
          _boot,
        ],
      );
      expect((await MacosVolumes.list()).single.path, '/');
    });
  });

  group('on macOS', () {
    final skip = Platform.isMacOS ? false : 'macOS only';

    test('storage locations are the volumes, with their names', () async {
      _answerWith((call) async => [_external, _boot]);
      final locations = await getAllStorageLocations();
      expect(locations.map((dir) => dir.path), ['/', '/Volumes/My SSD']);
      expect(locations.first.volumeLabel, 'Macintosh HD');
      expect(locations.last.volumeLabel, 'My SSD');
      expect(locations.last.volumeKind, DriveKind.removable);
    }, skip: skip);

    test('the sidebar follows mounts and unmounts', () async {
      final mounts = StreamController<void>();
      addTearDown(mounts.close);
      var rows = <Map<String, Object?>>[_boot];
      _answerWith((call) async => rows);
      final drawer = DrawerCubit(volumeChanges: mounts.stream);
      addTearDown(drawer.close);

      rows = [_boot, _external];
      mounts.add(null);
      final mounted = await drawer.stream.firstWhere(
        (state) => state.storageLocations.length == 2,
      );
      expect(mounted.storageLocations.last.path, '/Volumes/My SSD');

      rows = [_boot];
      mounts.add(null);
      final unmounted = await drawer.stream.firstWhere(
        (state) => state.storageLocations.length == 1,
      );
      expect(unmounted.storageLocations.single.path, '/');
    }, skip: skip);
  });
}
