import 'package:cb_file_manager/design_system/desktop_acrylic_theme_bridge.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'dart:async';
import 'package:dartssh2/dartssh2.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_registry.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/ui/screens/network_browsing/network_connection_dialog.dart';
import 'package:cb_file_manager/services/ssh/local_ssh_discovery.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_recovery_test.dart' show host;

class FixtureSshDiscovery extends LocalSshDiscovery {
  final Future<LocalSshSnapshot> result;
  FixtureSshDiscovery(this.result);
  @override
  Future<LocalSshSnapshot> scan() => result;
}

const snapshot = LocalSshSnapshot(
  hosts: [
    LocalSshHost(
      alias: 'work',
      host: 'work.example.test',
      username: 'developer',
      port: 2222,
      identityFiles: ['/fixture/work_key'],
    ),
  ],
  keys: [LocalSshKey('/fixture/work_key')],
);

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CB_SSH_CAPTURE')) return;
    for (final entry in {
      'MaterialIcons':
          '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf',
      'Inter': 'assets/fonts/Inter-Regular.ttf',
      'Segoe UI': 'assets/fonts/Inter-Regular.ttf',
      'packages/phosphor_flutter/PhosphorLight':
          'third_party/phosphor_flutter/lib/fonts/Phosphor-Light.ttf',
    }.entries) {
      final loader = FontLoader(entry.key);
      loader.addFont(
        File(entry.value).readAsBytes().then(ByteData.sublistView),
      );
      await loader.load();
    }
  });
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  for (final vi in [false, true]) {
    for (final width in [320.0, 1200.0]) {
      testWidgets('SSH modal autofill and key controls width=$width vi=$vi', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = SshProfileStore();
        final capture = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: capture,
            child: host(
              Theme(
                data: createDesktopAcrylicMaterialBridgeTheme(
                  baseTheme: const bool.fromEnvironment('CB_SSH_DARK_CAPTURE')
                      ? ThemeConfig.getDarkTheme()
                      : ThemeConfig.getLightTheme(),
                  brightness: const bool.fromEnvironment('CB_SSH_DARK_CAPTURE')
                      ? Brightness.dark
                      : Brightness.light,
                  strength: 1.25,
                  preferTransparentBackdrop: true,
                ),
                child: SshHostDialog(
                  store: store,
                  discovery: FixtureSshDiscovery(Future.value(snapshot)),
                  localHost: snapshot.hosts.single,
                ),
              ),
              vietnamese: vi,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('work.example.test'), findsOneWidget);
        expect(find.text('2222'), findsOneWidget);
        expect(find.text('developer'), findsOneWidget);
        expect(find.text('work_key · ~/.ssh'), findsOneWidget);
        if (const bool.fromEnvironment('CB_SSH_CAPTURE') &&
            width == 1200 &&
            vi) {
          await tester.runAsync(() async {
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final picture = await boundary.toImage();
            final bytes = await picture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              const bool.fromEnvironment('CB_SSH_DARK_CAPTURE')
                  ? 'build/network-layout-review/ssh-connection-dialog-dark.png'
                  : 'build/network-layout-review/ssh-connection-dialog.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            picture.dispose();
          });
        }
        final generate = find.widgetWithText(
          CbButton,
          vi ? 'Tạo key Ed25519' : 'Generate Ed25519 key',
        );
        // Find the visible localized control without relying on the screen's scroll position.
        final buttons = find.byType(CbButton);
        expect(buttons, findsAtLeastNWidgets(3));
        expect(tester.takeException(), isNull);
        // Creating a key in the connection form selects it immediately.
        final create = generate;
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        final input = find.byType(TextField).last;
        await tester.enterText(input, 'New developer key');
        await tester.tap(
          find.widgetWithText(CbButton, vi ? 'Lưu lại' : 'Save').last,
        );
        await tester.pumpAndSettle();
        expect(store.keys.single.name, 'New developer key');
        expect(find.text('New developer key'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final service in ['SMB', 'FTP', 'WebDAV']) {
    for (final width in [320.0, 1200.0]) {
      testWidgets('Network connection modal $service at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          host(
            NetworkConnectionDialog(
              initialService: service,
              registry: NetworkServiceRegistry.withServices([]),
            ),
            vietnamese: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
  testWidgets('imports a config-selected encrypted key and saves its host', (
    tester,
  ) async {
    final store = SshProfileStore();
    final key = SshStoredKey.generate('local');
    final pair = SSHKeyPair.fromPem(key.pem).single as OpenSSHEd25519KeyPair;
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('cb-ssh-key-ui-'),
    );
    addTearDown(() => directory!.delete(recursive: true));
    final file = File('${directory!.path}/encrypted_key');
    await tester.runAsync(
      () => file.writeAsString(pair.toPem(passphrase: 'fixture-passphrase')),
    );
    final discovery = FixtureSshDiscovery(
      Future.value(
        LocalSshSnapshot(
          hosts: [
            LocalSshHost(
              alias: 'dev',
              host: 'dev.example.test',
              username: 'developer',
              identityFiles: [file.path],
            ),
          ],
          keys: [LocalSshKey(file.path)],
        ),
      ),
    );
    await tester.pumpWidget(
      host(
        Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => SshHostDialog(
                  store: store,
                  discovery: discovery,
                  localHost: LocalSshHost(
                    alias: 'dev',
                    host: 'dev.example.test',
                    username: 'developer',
                    identityFiles: [file.path],
                  ),
                ),
              ),
              child: const Text('Open connection'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CbButton, 'Save'));
    // The silent import of the encrypted key reads the file, then falls back
    // to the import dialog.
    for (
      var attempt = 0;
      attempt < 50 && find.text(file.path).evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text(file.path), findsOneWidget);
    final passphrase = find.byWidgetPredicate(
      (w) => w is TextField && w.obscureText,
    );
    await tester.enterText(passphrase, 'fixture-passphrase');
    await tester.tap(find.widgetWithText(CbButton, 'Save').last);
    for (var attempt = 0; attempt < 50 && store.profiles.isEmpty; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Could not save the key. Check the file, format and passphrase, then try again.',
      ),
      findsNothing,
    );
    expect(store.keys, hasLength(1));
    expect(store.keys.single.fingerprint, key.fingerprint);
    expect(store.profiles.single.keyId, store.keys.single.id);
    expect(store.profiles.single.host, 'dev.example.test');
    expect(store.profiles.single.password, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('invalid host and port stay in the form and show inline errors', (
    tester,
  ) async {
    final store = SshProfileStore();
    await tester.pumpWidget(
      host(
        SshHostDialog(
          store: store,
          discovery: FixtureSshDiscovery(
            Future.value(const LocalSshSnapshot()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(CbTextField);
    await tester.enterText(fields.at(0), 'ssh://invalid/host');
    await tester.enterText(fields.at(1), '70000');
    await tester.tap(find.widgetWithText(CbButton, 'Save'));
    await tester.pumpAndSettle();
    expect(store.profiles, isEmpty);
    expect(find.byType(Dialog), findsOneWidget);
    final hostField = tester.widget<CbTextField>(fields.at(0));
    final portField = tester.widget<CbTextField>(fields.at(1));
    expect(hostField.errorText, isNotEmpty);
    expect(portField.errorText, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'late discovery never overwrites manually entered connection details',
    (tester) async {
      final complete = Completer<LocalSshSnapshot>();
      await tester.pumpWidget(
        host(
          SshHostDialog(
            store: SshProfileStore(),
            discovery: FixtureSshDiscovery(complete.future),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byType(CbTextField).first,
        'manual.example.test',
      );
      complete.complete(snapshot);
      await tester.pumpAndSettle();
      expect(find.text('manual.example.test'), findsOneWidget);
      expect(find.text('work.example.test'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
