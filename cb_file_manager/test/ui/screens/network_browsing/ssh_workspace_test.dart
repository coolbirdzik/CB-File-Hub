import 'package:cb_file_manager/ui/components/common/grid_list_collection.dart';
import 'package:cb_file_manager/ui/widgets/adaptive_file_list.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_workspace_screen.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_list_item.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_sort.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_dialog.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_recovery_test.dart' show host;
import 'ssh_connection_dialog_test.dart' show FixtureSshDiscovery;
import 'package:cb_file_manager/services/ssh/local_ssh_discovery.dart';

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CB_SSH_CAPTURE')) return;
    for (final entry in {
      'Inter': 'assets/fonts/Inter-Regular.ttf',
      'Segoe UI': 'assets/fonts/Inter-Regular.ttf',
      'packages/phosphor_flutter/PhosphorLight':
          'third_party/phosphor_flutter/lib/fonts/Phosphor-Light.ttf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(
          entry.value,
        ).readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
      );
      await loader.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final language in ['en', 'vi']) {
    for (final width in [320.0, 1200.0]) {
      for (final sftp in [false, true]) {
        testWidgets(
          'SSH workspace $language $width sftp=$sftp keeps controls accessible',
          (tester) async {
            tester.view.physicalSize = Size(width, 650);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final store = SshProfileStore();
            final key = SshStoredKey.generate('Work key');
            await store.saveKey(key);
            await store.saveProfile(
              SshProfile(
                id: 'fixture',
                name: 'Development server',
                host: 'dev.example.test',
                username: 'developer',
                port: 2222,
                group: 'Development',
                keyId: key.id,
              ),
            );
            final tabs = TabManagerBloc();
            addTearDown(tabs.close);
            final change = tabs.stream.first;
            tabs.add(AddTab(path: sftp ? '#sftp' : '#ssh'));
            await change;
            final capture = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: capture,
                child: BlocProvider.value(
                  value: tabs,
                  child: host(
                    SshWorkspaceScreen(
                      tabId: tabs.state.activeTabId!,
                      sftpOnly: sftp,
                      store: store,
                      viewController: GridListViewController(),
                      sortController: SshHostSortController(),
                      discovery: FixtureSshDiscovery(
                        Future.value(const LocalSshSnapshot()),
                      ),
                    ),
                    vietnamese: language == 'vi',
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('Development server'), findsOneWidget);
            if (const bool.fromEnvironment('CB_SSH_CAPTURE') &&
                language == 'en' &&
                width == 1200 &&
                !sftp) {
              await tester.runAsync(() async {
                final boundary =
                    capture.currentContext!.findRenderObject()
                        as RenderRepaintBoundary;
                final image = await boundary.toImage();
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  'build/network-layout-review/ssh-workspace.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
            }
            final beforeSelection = tester.getTopLeft(
              find.text('Development server'),
            );
            await tester.tap(find.text('Development server'));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<SshHostListItem>(
                    find.byKey(const ValueKey('fixture')),
                  )
                  .isSelected,
              isTrue,
            );
            expect(
              tester.getTopLeft(find.text('Development server')),
              beforeSelection,
              reason:
                  'Selecting must not shift the target between double clicks',
            );
            await tester.tapAt(Offset(width - 16, 620));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<SshHostListItem>(
                    find.byKey(const ValueKey('fixture')),
                  )
                  .isSelected,
              isFalse,
            );
            expect(find.byType(PopupMenuButton<void>), findsOneWidget);
            await tester.tap(
              find.byKey(const ValueKey('collection-view-list')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('grid-list-collection-list')),
              findsOneWidget,
            );
            expect(find.byType(AdaptiveFileList), findsOneWidget);
            expect(find.text('Development server'), findsOneWidget);
            await tester.tap(
              find.byKey(const ValueKey('collection-view-grid')),
            );
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('grid-list-collection-grid')),
              findsOneWidget,
            );
            expect(find.byType(AdaptiveFileList), findsNothing);
            expect(find.byType(GridView), findsOneWidget);
            expect(find.byType(CbSurface), findsOneWidget);
            expect(find.text('Development server'), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (!sftp) {
              await tester.tap(find.byKey(const ValueKey('ssh-section-keys')));
              await tester.pumpAndSettle();
              expect(find.text('Work key'), findsOneWidget);
              expect(tester.takeException(), isNull);
              await tester.tap(
                find.byKey(const ValueKey('ssh-section-known-hosts')),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
          },
        );
      }
    }
  }
  testWidgets(
    'unsaved config hosts stay out of Hosts while local keys remain available',
    (tester) async {
      final store = SshProfileStore();
      final tabs = TabManagerBloc();
      addTearDown(tabs.close);
      final change = tabs.stream.first;
      tabs.add(AddTab(path: '#ssh'));
      await change;
      final discovery = FixtureSshDiscovery(
        Future.value(
          const LocalSshSnapshot(
            hosts: [
              LocalSshHost(
                alias: 'Local dev',
                host: 'dev.example.test',
                username: 'developer',
              ),
            ],
            keys: [LocalSshKey('/fixture/dev_key')],
          ),
        ),
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: tabs,
          child: host(
            SshWorkspaceScreen(
              tabId: tabs.state.activeTabId!,
              store: store,
              discovery: discovery,
              viewController: GridListViewController(),
              sortController: SshHostSortController(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Local dev'), findsNothing);
      expect(
        // Secondary actions collapse to icon buttons at this width.
        find.byWidgetPredicate(
          (w) => w is CbButton && w.tooltip == 'Import private key',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('ssh-section-keys')));
      await tester.pumpAndSettle();
      expect(find.text('dev_key'), findsOneWidget);
      expect(store.keys, isEmpty);
      expect(store.profiles, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('host sort menu orders naturally, flips and persists', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SshProfileStore();
    for (final (id, name, group) in [
      ('a', 'web10', 'Alpha'),
      ('b', 'web2', 'Beta'),
      ('c', 'db1', 'Gamma'),
    ]) {
      await store.saveProfile(
        SshProfile(
          id: id,
          name: name,
          host: '$name.example.test',
          username: 'ops',
          group: group,
        ),
      );
    }
    final saved = <String>[];
    final sort = SshHostSortController(save: (value) async => saved.add(value));
    final tabs = TabManagerBloc();
    addTearDown(tabs.close);
    final change = tabs.stream.first;
    tabs.add(AddTab(path: '#ssh'));
    await change;
    await tester.pumpWidget(
      BlocProvider.value(
        value: tabs,
        child: host(
          SshWorkspaceScreen(
            tabId: tabs.state.activeTabId!,
            store: store,
            discovery: FixtureSshDiscovery(
              Future.value(const LocalSshSnapshot()),
            ),
            viewController: GridListViewController(),
            sortController: sort,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    List<String> order() {
      final names = ['web10', 'web2', 'db1'];
      Offset at(String name) => tester.getTopLeft(find.text(name));
      return names..sort((a, b) {
        final (pa, pb) = (at(a), at(b));
        return pa.dy != pb.dy ? pa.dy.compareTo(pb.dy) : pa.dx.compareTo(pb.dx);
      });
    }

    // Default keeps the old group-then-name order.
    expect(order(), ['web10', 'web2', 'db1']);
    Future<void> pick(SshHostSortField field) async {
      await tester.tap(find.byKey(const ValueKey('ssh-host-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('ssh-host-sort-${field.name}')));
      await tester.pumpAndSettle();
    }

    await pick(SshHostSortField.name);
    expect(order(), ['db1', 'web2', 'web10']);
    await pick(SshHostSortField.name);
    expect(order(), ['web10', 'web2', 'db1']);
    expect(saved, ['name:asc', 'name:desc']);
    expect(tester.takeException(), isNull);
  });
  test('host sort restores a saved order and ignores unknown values', () async {
    final restored = SshHostSortController(load: () async => 'host:desc');
    await restored.initialize();
    expect(restored.field, SshHostSortField.host);
    expect(restored.ascending, isFalse);
    final unknown = SshHostSortController(load: () async => 'size:asc');
    await unknown.initialize();
    expect(unknown.field, SshHostSortField.group);
    expect(unknown.ascending, isTrue);
  });
  testWidgets(
    'unknown or changed SSH fingerprint requires an explicit decision',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(
          Material(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await promptSshHostTrust(
                    context,
                    'localhost',
                    2222,
                    'ssh-ed25519',
                    'SHA256:new',
                    'SHA256:previous',
                  );
                },
                child: const Text('Verify'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.text('SSH host key changed'), findsOneWidget);
      expect(find.text('SHA256:new'), findsOneWidget);
      expect(result, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );
}
