import 'dart:io';

import 'package:cb_file_manager/services/desktop_integration/default_file_manager_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late DefaultFileManagerService linux;
  late String selected;
  late bool rejectChange;
  late List<List<String>> commands;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('folder-default-service-');
    selected = 'previous.desktop';
    rejectChange = false;
    commands = [];
    linux = DefaultFileManagerService(
      operatingSystem: 'linux',
      environment: {'XDG_DATA_HOME': p.join(root.path, 'data')},
      executable: '/opt/CB File Hub/100%/cb-file-hub',
      supportDirectory: () async => root,
      runProcess: (command, arguments) async {
        expect(command, 'xdg-mime');
        commands.add(List.of(arguments));
        if (arguments.first == 'query') {
          return ProcessResult(1, 0, '$selected\n', '');
        }
        if (rejectChange) return ProcessResult(1, 4, '', 'policy denied');
        selected = arguments[1];
        return ProcessResult(1, 0, '', '');
      },
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'Linux advertises directory/URI support and restores prior application',
    () async {
      expect((await linux.status()).enabled, isFalse);
      await linux.enable();
      expect((await linux.status()).enabled, isTrue);
      final desktop = File(
        p.join(
          root.path,
          'data',
          'applications',
          DefaultFileManagerService.desktopId,
        ),
      );
      final contents = await desktop.readAsString();
      expect(
        contents,
        contains('Exec="/opt/CB File Hub/100%%/cb-file-hub" %U\n'),
      );
      expect(contents, contains('MimeType=inode/directory;'));
      await linux.enable();
      await linux.restore();
      expect(selected, 'previous.desktop');
      expect((await linux.status()).canRestore, isFalse);
    },
  );

  test('Linux restore preserves a later choice made by another app', () async {
    await linux.enable();
    selected = 'later.desktop';
    commands.clear();
    await linux.restore();
    expect(selected, 'later.desktop');
    expect(commands.where((args) => args.first == 'default'), isEmpty);
    expect((await linux.status()).canRestore, isFalse);
  });

  test(
    'failed Linux change remains recoverable and does not report enabled',
    () async {
      rejectChange = true;
      await expectLater(linux.enable(), throwsA(isA<ProcessException>()));
      expect((await linux.status()).enabled, isFalse);
      expect((await linux.status()).canRestore, isTrue);
      await linux.restore();
      expect(selected, 'previous.desktop');
    },
  );

  test(
    'Linux cannot overwrite a pending backup after an external change',
    () async {
      await linux.enable();
      selected = 'later.desktop';
      await expectLater(linux.enable(), throwsStateError);
      await linux.restore();
      expect(selected, 'later.desktop');
    },
  );

  for (final platform in ['windows', 'macos']) {
    test(
      '$platform delegates to the OS and verifies effective state',
      () async {
        final channel = MethodChannel(
          platform == 'windows'
              ? 'cb_file_manager/app_icon'
              : 'cb_file_manager/macos_window',
        );
        var active = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'setFolderDefault') active = true;
              if (call.method == 'restoreFolderDefault') active = false;
              return {'enabled': active, 'canRestore': active};
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final service = DefaultFileManagerService(operatingSystem: platform);
        await service.enable();
        expect((await service.status()).enabled, isTrue);
        await service.restore();
        expect((await service.status()).enabled, isFalse);
      },
    );
  }
}
