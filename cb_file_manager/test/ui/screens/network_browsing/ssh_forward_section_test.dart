import 'package:cb_file_manager/services/ssh/local_ssh_discovery.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/services/ssh/ssh_tunnel_manager.dart';
import 'package:cb_file_manager/ui/components/common/grid_list_collection.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_sort.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_section.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_workspace_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/ssh/fake_tunnel_link.dart';
import 'network_recovery_test.dart' show host;
import 'ssh_connection_dialog_test.dart' show FixtureSshDiscovery;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<({SshProfileStore store, SshTunnelManager tunnels})> pumpWorkspace(
    WidgetTester tester, {
    required double width,
    bool vietnamese = false,
    bool withRule = true,
  }) async {
    tester.view.physicalSize = Size(width, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = SshProfileStore();
    final link = FakeTunnelLink();
    final tunnels = SshTunnelManager(
      store,
      connect: (_, {trustPrompt, onCancelable}) async => link,
    );
    addTearDown(tunnels.dispose);
    final port = (await tester.runAsync(freePort))!;
    await store.saveProfile(
      const SshProfile(
        id: 'fixture',
        name: 'Development server',
        host: 'dev.example.test',
        username: 'developer',
      ),
    );
    if (withRule) {
      await store.saveForward(
        SshForward(
          id: 'db',
          name: 'Database',
          profileId: 'fixture',
          type: SshForwardType.local,
          bindPort: port,
          targetHost: 'localhost',
          targetPort: 5432,
        ),
      );
    }
    final tabs = TabManagerBloc();
    addTearDown(tabs.close);
    final change = tabs.stream.first;
    tabs.add(AddTab(path: '#ssh'));
    await change;
    final view = GridListViewController();
    final sort = SshHostSortController();
    addTearDown(view.dispose);
    addTearDown(sort.dispose);
    Widget screen(SshSection section) => BlocProvider.value(
      value: tabs,
      child: host(
        SshWorkspaceScreen(
          tabId: tabs.state.activeTabId!,
          section: section,
          store: store,
          tunnels: tunnels,
          viewController: view,
          sortController: sort,
          discovery: FixtureSshDiscovery(
            Future.value(const LocalSshSnapshot()),
          ),
        ),
        vietnamese: vietnamese,
      ),
    );
    await tester.pumpWidget(screen(SshSection.hosts));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ssh-section-forwards')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(const ValueKey('ssh-section-forwards')));
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab?.path, SshSection.forwards.path);
    await tester.pumpWidget(screen(SshSection.forwards));
    await tester.pumpAndSettle();
    return (store: store, tunnels: tunnels);
  }

  for (final vietnamese in [false, true]) {
    for (final width in [320.0, 1200.0]) {
      testWidgets(
        'forward rows vi=$vietnamese $width start and stop a tunnel',
        (tester) async {
          final fixture = await pumpWorkspace(
            tester,
            width: width,
            vietnamese: vietnamese,
          );
          expect(find.text('Database'), findsOneWidget);
          if (width == 1200) {
            await tester.tap(
              find.byKey(const ValueKey('shared-search-action')),
            );
            await tester.pumpAndSettle();
            final search = find.descendant(
              of: find.byKey(const ValueKey('ssh-search')),
              matching: find.byType(EditableText),
            );
            await tester.enterText(search, 'missing-forward');
            await tester.pumpAndSettle();
            expect(find.text('Database'), findsNothing);
            await tester.enterText(search, 'Database');
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('ssh-forward-db')),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(const ValueKey('shared-search-action')),
            );
            await tester.pumpAndSettle();
          }
          expect(find.text('-L'), findsOneWidget);
          expect(find.text(vietnamese ? 'Đã tắt' : 'Stopped'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('ssh-forward-toggle-db')));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          expect(fixture.tunnels.state('db').status, SshTunnelStatus.running);
          expect(
            find.textContaining(vietnamese ? 'Đang chạy' : 'Running'),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('ssh-forward-toggle-db')));
          await tester.pumpAndSettle();
          expect(fixture.tunnels.state('db').status, SshTunnelStatus.stopped);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('the dialog saves a SOCKS rule and warns about open binds', (
    tester,
  ) async {
    final fixture = await pumpWorkspace(tester, width: 1200, withRule: false);
    expect(
      find.text(
        'No port forwards yet. Add one to reach a service through an SSH host.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(GestureDetector, 'Add forward').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('ssh-forward-host')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('developer@dev.example.test').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ssh-forward-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dynamic SOCKS5 (-D)').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ssh-forward-target-host')), findsNothing);

    Finder field(String key) => find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(EditableText),
    );
    await tester.enterText(field('ssh-forward-bind-host'), '0.0.0.0');
    await tester.pump();
    expect(find.textContaining('reachable from other devices'), findsOneWidget);
    await tester.enterText(field('ssh-forward-bind-host'), '127.0.0.1');
    await tester.enterText(field('ssh-forward-bind-port'), '1080');
    await tester.pump();
    expect(find.textContaining('reachable from other devices'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('ssh-forward-save')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final rule = fixture.store.forwards.single;
    expect(rule.type, SshForwardType.dynamic);
    expect(rule.bindAddress, '127.0.0.1:1080');
    expect(find.text('SOCKS5 127.0.0.1:1080'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
