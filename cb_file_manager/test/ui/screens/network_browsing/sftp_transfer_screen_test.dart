import 'dart:async';

import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/ui/screens/ssh/sftp_transfer_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/ssh/memory_transfer_file_system.dart';
import 'network_recovery_test.dart' show host;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<
    ({
      MemoryTransferFileSystem local,
      MemoryTransferFileSystem remote,
      TabManagerBloc tabs,
      List<String> opened,
    })
  >
  pumpScreen(
    WidgetTester tester, {
    required double width,
    bool vietnamese = false,
    String? profileId = 'fixture',
  }) async {
    tester.view.physicalSize = Size(width, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SshProfileStore();
    await store.saveProfile(
      const SshProfile(
        id: 'fixture',
        name: 'Development server',
        host: 'dev.example.test',
        username: 'developer',
      ),
    );
    final local = MemoryTransferFileSystem(homePath: '/home/me')
      ..addFile('/home/me/notes.txt', 'remember')
      ..mkdirs('/home/me/photos');
    final remote = MemoryTransferFileSystem(homePath: '/home/developer')
      ..addFile('/home/developer/server.log', 'started');
    final opened = <String>[];
    final tabs = TabManagerBloc();
    addTearDown(tabs.close);
    final change = tabs.stream.first;
    tabs.add(AddTab(path: '#ssh/transfer/fixture'));
    await change;
    await tester.pumpWidget(
      BlocProvider.value(
        value: tabs,
        child: host(
          SftpTransferScreen(
            tabId: tabs.state.activeTabId!,
            profileId: profileId,
            store: store,
            localFileSystem: local,
            openSession: (profile, _) async {
              opened.add(profile.id);
              return SftpTransferSession(
                fileSystem: remote,
                done: Completer<void>().future,
                close: () {},
              );
            },
          ),
          vietnamese: vietnamese,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (local: local, remote: remote, tabs: tabs, opened: opened);
  }

  for (final vietnamese in [false, true]) {
    for (final width in [320.0, 1200.0]) {
      testWidgets(
        'transfer screen vi=$vietnamese $width puts this computer first and uploads',
        (tester) async {
          final fixture = await pumpScreen(
            tester,
            width: width,
            vietnamese: vietnamese,
          );
          expect(fixture.opened, ['fixture']);
          expect(find.text('notes.txt'), findsOneWidget);
          expect(find.text('server.log'), findsOneWidget);
          final local = tester.getTopLeft(
            find.byKey(const ValueKey('sftp-transfer-local')),
          );
          final remote = tester.getTopLeft(
            find.byKey(const ValueKey('sftp-transfer-remote')),
          );
          if (width >= 720) {
            expect(local.dx, lessThan(remote.dx));
            expect(local.dy, remote.dy);
          } else {
            expect(local.dy, lessThan(remote.dy));
          }
          expect(
            fixture.tabs.state.tabs.single.name,
            'Development server · SFTP',
          );

          await tester.tap(find.text('notes.txt'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('sftp-transfer-send-local')),
          );
          await tester.pumpAndSettle();
          expect(fixture.remote.text('/home/developer/notes.txt'), 'remember');
          expect(find.text('notes.txt'), findsNWidgets(2));
          // Let the success toast expire.
          await tester.pump(const Duration(seconds: 3));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('double-clicking a folder opens it and downloads land there', (
    tester,
  ) async {
    final fixture = await pumpScreen(tester, width: 1200);
    await tester.tap(find.text('photos'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('photos'));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsNothing);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const ValueKey('sftp-transfer-path-local')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      '/home/me/photos',
    );
    await tester.tap(find.text('server.log'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sftp-transfer-send-remote')));
    await tester.pumpAndSettle();
    expect(fixture.local.text('/home/me/photos/server.log'), 'started');
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('without a host the remote pane asks for one', (tester) async {
    final fixture = await pumpScreen(tester, width: 1200, profileId: null);
    expect(fixture.opened, isEmpty);
    expect(
      find.text('Choose a saved SSH host to browse its files over SFTP.'),
      findsOneWidget,
    );
    expect(find.text('notes.txt'), findsOneWidget);
    expect(fixture.tabs.state.tabs.single.name, 'File transfer');
    expect(tester.takeException(), isNull);
  });
}
