import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/ssh/local_ssh_discovery.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_proxy_dialog.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_dialog.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_recovery_test.dart' show host;
import 'ssh_connection_dialog_test.dart' show FixtureSshDiscovery;

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  for (final vi in [false, true]) {
    for (final width in [320.0, 1200.0]) {
      testWidgets(
        'create proxy vi=$vi width=$width and retain it in host editor',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = SshProfileStore();
          await tester.pumpWidget(
            host(
              Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => showSshProxyDialog(context, store),
                    child: const Text('Open proxy'),
                  ),
                ),
              ),
              vietnamese: vi,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open proxy'));
          await tester.pumpAndSettle();
          final values = [
            'Work proxy',
            'proxy.example.test',
            '1080',
            'proxy-user',
            'fixture-password',
          ];
          for (var i = 0; i < values.length; i++) {
            final field = find.byType(TextField).at(i);
            await tester.ensureVisible(field);
            await tester.enterText(field, values[i]);
          }
          expect(
            tester.widget<TextField>(find.byType(TextField).last).obscureText,
            isTrue,
          );
          final saveLabel = vi ? 'Lưu lại' : 'Save';
          await tester.tap(find.widgetWithText(CbButton, saveLabel));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final proxy = store.proxies.single;
          expect(proxy.host, 'proxy.example.test');
          expect(proxy.username, 'proxy-user');
          expect(proxy.password, 'fixture-password');
          final profile = SshProfile(
            id: 'host',
            name: 'Server',
            host: 'server.test',
            username: 'deploy',
            proxyId: proxy.id,
          );
          await store.saveProfile(profile);
          await tester.pumpWidget(
            host(
              Scaffold(
                body: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => RouteUtils.showAcrylicDialog(
                      context: context,
                      builder: (_) => SshHostDialog(
                        profile: profile,
                        store: store,
                        discovery: FixtureSshDiscovery(
                          Future.value(const LocalSshSnapshot()),
                        ),
                      ),
                    ),
                    child: const Text('Open host'),
                  ),
                ),
              ),
              vietnamese: vi,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Open host'));
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CbSelect<String>>(
                  find.byKey(const ValueKey('ssh-proxy')),
                )
                .value,
            proxy.id,
          );
          await tester.tap(find.widgetWithText(CbButton, saveLabel));
          await tester.pumpAndSettle();
          expect(store.profiles.single.proxyId, proxy.id);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
