import 'dart:async';
import 'package:cb_file_manager/ui/widgets/selection_geometry_item.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/ui/components/common/grid_list_collection.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/drag_selection_region.dart';

import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/ui/screens/ssh/sftp_transfer_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      ..addFile('/home/developer/server.log', 'started')
      ..mkdirs('/home/developer/backup');
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
            directoryPicker: () async => '/home/me/photos',
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
    final localPath = find.byKey(const ValueKey('sftp-transfer-path-local'));
    expect(
      find.descendant(of: localPath, matching: find.text('photos')),
      findsOneWidget,
    );
    // A crumb goes back up the chain.
    await tester.tap(find.descendant(of: localPath, matching: find.text('me')));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsOneWidget);
    await tester.tap(find.text('photos'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('server.log'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sftp-transfer-send-remote')));
    await tester.pumpAndSettle();
    expect(fixture.local.text('/home/me/photos/server.log'), 'started');
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the local address bar browses for the save folder', (
    tester,
  ) async {
    final fixture = await pumpScreen(tester, width: 1200);
    await tester.tap(find.byKey(const ValueKey('sftp-transfer-browse-local')));
    await tester.pumpAndSettle();
    expect(find.text('notes.txt'), findsNothing);
    await tester.tap(find.text('server.log'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sftp-transfer-send-remote')));
    await tester.pumpAndSettle();
    expect(fixture.local.text('/home/me/photos/server.log'), 'started');
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();
  }

  Future<void> openBackup(WidgetTester tester) async {
    await tester.tap(find.text('backup'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty folder'));
    await tester.pumpAndSettle();
  }

  for (final cut in [false, true]) {
    testWidgets('remote files are ${cut ? 'moved' : 'copied'} by paste', (
      tester,
    ) async {
      final fixture = await pumpScreen(tester, width: 1200);
      await tester.tap(find.text('server.log'));
      await tester.pumpAndSettle();
      await chord(
        tester,
        cut ? LogicalKeyboardKey.keyX : LogicalKeyboardKey.keyC,
      );
      // Pasting next to the original is refused.
      await chord(tester, LogicalKeyboardKey.keyV);
      expect(fixture.remote.files.keys, ['/home/developer/server.log']);
      await openBackup(tester);
      await chord(tester, LogicalKeyboardKey.keyV);
      expect(
        fixture.remote.text('/home/developer/backup/server.log'),
        'started',
      );
      expect(
        fixture.remote.text('/home/developer/server.log'),
        cut ? isNull : 'started',
      );
      expect(find.text('server.log'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('remote items are renamed from the menu and deleted by key', (
    tester,
  ) async {
    final fixture = await pumpScreen(tester, width: 1200);
    fixture.remote.addFile('/home/developer/backup/old.txt', 'old');
    await tester.tap(find.text('server.log'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sftp-transfer-name')),
      'app.log',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(fixture.remote.text('/home/developer/app.log'), 'started');
    expect(fixture.remote.text('/home/developer/server.log'), isNull);
    expect(find.text('app.log'), findsOneWidget);

    await tester.tap(find.text('backup'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(fixture.remote.dirs, contains('/home/developer/backup'));
    await tester.tap(
      find.byKey(const ValueKey('sftp-transfer-confirm-delete')),
    );
    await tester.pumpAndSettle();
    expect(fixture.remote.dirs, isNot(contains('/home/developer/backup')));
    expect(fixture.remote.files.keys, ['/home/developer/app.log']);
    expect(find.text('backup'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('remote rectangle selection deletes every selected entry', (
    tester,
  ) async {
    final fixture = await pumpScreen(tester, width: 1200);
    final remote = find.byKey(const ValueKey('sftp-transfer-remote'));
    final region = find.descendant(
      of: remote,
      matching: find.byType(DragSelectionRegion),
    );
    final rect = tester.getRect(region);
    final gesture = await tester.startGesture(
      rect.bottomRight - const Offset(12, 12),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(rect.topLeft + const Offset(1, 1));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sftp-transfer-confirm-delete')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('sftp-transfer-confirm-delete')),
    );
    await tester.pumpAndSettle();
    expect(fixture.remote.files, isEmpty);
    expect(fixture.remote.dirs, isNot(contains('/home/developer/backup')));
    expect(fixture.local.text('/home/me/notes.txt'), 'remember');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('transfer views and wheel zoom work independently at $width', (
      tester,
    ) async {
      await pumpScreen(tester, width: width);
      final remote = find.byKey(const ValueKey('sftp-transfer-remote'));
      final local = find.byKey(const ValueKey('sftp-transfer-local'));
      FileViewShell shell() => tester
          .widgetList<FileViewShell>(
            find.descendant(of: remote, matching: find.byType(FileViewShell)),
          )
          .single;
      shell().onViewScaleDelta!(1);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<GridListViewToggle>(
              find.descendant(
                of: remote,
                matching: find.byType(GridListViewToggle),
              ),
            )
            .mode,
        ViewMode.list,
      );
      shell().onViewScaleDelta!(1);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sftp-transfer-grid-remote')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<GridListViewToggle>(
              find.descendant(
                of: local,
                matching: find.byType(GridListViewToggle),
              ),
            )
            .mode,
        ViewMode.details,
      );
      final before = tester
          .getSize(
            find
                .ancestor(
                  of: find.text('server.log'),
                  matching: find.byType(SelectionGeometryItem),
                )
                .first,
          )
          .width;
      shell().onViewScaleDelta!(1);
      await tester.pumpAndSettle();
      final after = tester
          .getSize(
            find
                .ancestor(
                  of: find.text('server.log'),
                  matching: find.byType(SelectionGeometryItem),
                )
                .first,
          )
          .width;
      expect(after, greaterThanOrEqualTo(before));
      await tester.tap(
        find.descendant(of: remote, matching: find.byType(GridListViewToggle)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('collection-view-details')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sftp-transfer-grid-remote')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final keyboard in [false, true]) {
    for (final width in [320.0, 1200.0]) {
      testWidgets(
        'transfer ${keyboard ? 'key after toolbar focus' : 'toolbar Delete'} deletes multiple remote items at $width',
        (tester) async {
          final fixture = await pumpScreen(tester, width: width);
          await tester.tap(find.text('backup'));
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.tap(find.text('server.log'));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pumpAndSettle();
          final toolbar = find.byKey(
            const ValueKey('sftp-transfer-delete-remote'),
          );
          if (keyboard) {
            Focus.of(
              tester.element(
                find.descendant(of: toolbar, matching: find.byType(Icon)).first,
              ),
            ).requestFocus();
            await tester.pump();
            await tester.sendKeyEvent(LogicalKeyboardKey.delete);
          } else {
            await tester.tap(toolbar);
          }
          await tester.pumpAndSettle();
          expect(fixture.remote.files.length, 1);
          await tester.tap(
            find.byKey(const ValueKey('sftp-transfer-confirm-delete')),
          );
          await tester.pumpAndSettle();
          expect(fixture.remote.files, isEmpty);
          expect(
            fixture.remote.dirs,
            isNot(contains('/home/developer/backup')),
          );
          expect(fixture.local.text('/home/me/notes.txt'), 'remember');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('the local pane offers no file operations', (tester) async {
    final fixture = await pumpScreen(tester, width: 1200);
    await tester.tap(find.text('notes.txt'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('sftp-transfer-confirm-delete')),
      findsNothing,
    );
    expect(fixture.local.text('/home/me/notes.txt'), 'remember');
    expect(
      find.byKey(const ValueKey('sftp-transfer-more-local')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sftp-transfer-more-remote')),
      findsOneWidget,
    );
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
