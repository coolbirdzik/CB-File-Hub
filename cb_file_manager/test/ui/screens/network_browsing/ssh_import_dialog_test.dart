import 'dart:convert';

import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/services/ssh/ssh_client_scanner.dart';
import 'package:cb_file_manager/services/ssh/ssh_import.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_recovery_test.dart' show host;

class FixtureClientScanner extends SshClientScanner {
  final List<SshClientScanResult> results;
  int calls = 0;
  FixtureClientScanner([this.results = const []]);
  @override
  Future<List<SshClientScanResult>> scan({
    String passphrase = '',
    List<SshStoredKey> existingKeys = const [],
  }) async {
    calls++;
    return results;
  }
}

Future<void> openImport(
  WidgetTester tester,
  SshProfileStore store, {
  bool vietnamese = false,
}) async {
  await tester.pumpWidget(
    host(
      Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showSshImportDialog(
              context,
              store,
              scanner: FixtureClientScanner(),
            ),
            child: const Text('Open import'),
          ),
        ),
      ),
      vietnamese: vietnamese,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open import'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(
      CbButton,
      vietnamese ? 'Nhập từ file' : 'Import a file',
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> preview(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.widgetWithText(CbButton, label));
  await tester.runAsync(() async {
    await tester.tap(find.widgetWithText(CbButton, label));
    // Allow the real parser isolate to finish outside the fake widget clock.
    for (var i = 0; i < 100; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'opening import automatically scans apps and saves discovered host with its key',
    (tester) async {
      final store = SshProfileStore();
      final key = SshStoredKey.generate('Discovered key');
      const proxy = SshProxy(
        id: 'proxy',
        name: 'Discovered proxy',
        type: SshProxyType.socks5,
        host: 'proxy.test',
        port: 1080,
        username: 'proxy-user',
        password: 'proxy-secret',
      );
      final profile = SshProfile(
        id: 'discovered',
        name: 'Discovered host',
        host: 'scan.test',
        username: 'deploy',
        keyId: key.id,
        proxyId: proxy.id,
      );
      final scanner = FixtureClientScanner([
        SshClientScanResult(
          'Termius',
          'local Termius',
          SshClientScanStatus.ready,
          SshImportPreview([profile], [key], const [], proxies: const [proxy]),
        ),
        const SshClientScanResult(
          'PuTTY',
          '',
          SshClientScanStatus.notFound,
          SshImportPreview([], [], []),
        ),
      ]);
      await tester.pumpWidget(
        host(
          Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () =>
                    showSshImportDialog(context, store, scanner: scanner),
                child: const Text('Open scan'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open scan'));
      await tester.pumpAndSettle();
      expect(scanner.calls, 1);
      expect(find.text('Discovered host'), findsOneWidget);
      expect(find.text('Discovered key'), findsOneWidget);
      expect(find.text('Discovered proxy'), findsOneWidget);
      expect(find.textContaining('proxy-secret'), findsNothing);
      expect(store.profiles, isEmpty);
      expect(
        find.widgetWithText(CbButton, 'Add export / private key files'),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(CbButton, 'Import selected'));
      await tester.pumpAndSettle();
      expect(store.profiles.single.host, 'scan.test');
      expect(store.profiles.single.keyId, store.keys.single.id);
      expect(store.profiles.single.proxyId, store.proxies.single.id);
      expect(store.proxies.single.password, 'proxy-secret');
    },
  );

  for (final vietnamese in [false, true]) {
    for (final width in [320.0, 1200.0]) {
      testWidgets(
        'import preview and selected save, vi=$vietnamese width=$width',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final store = SshProfileStore();
          await openImport(tester, store, vietnamese: vietnamese);
          final pasteLabel = vietnamese
              ? 'Dán dữ liệu đã xuất'
              : 'Paste exported data';
          await tester.ensureVisible(find.widgetWithText(CbButton, pasteLabel));
          await tester.tap(find.widgetWithText(CbButton, pasteLabel));
          await tester.pumpAndSettle();
          final field = find.byType(TextField).first;
          await tester.ensureVisible(field);
          await tester.enterText(
            field,
            '{"hosts":[{"name":"Import host","host":"import.test","username":"deploy","password":"test-password"}]}',
          );
          await preview(tester, vietnamese ? 'Xem trước' : 'Preview');
          expect(find.text('Import host'), findsOneWidget);
          expect(store.profiles, isEmpty);
          expect(tester.takeException(), isNull);
          final save = find.widgetWithText(
            CbButton,
            vietnamese ? 'Nhập mục đã chọn' : 'Import selected',
          );
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(store.profiles.single.host, 'import.test');
          expect(store.profiles.single.password, 'test-password');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'keychain-only preview imports orphan key without displaying private key in preview',
    (tester) async {
      final store = SshProfileStore();
      final key = SshStoredKey.generate('Termius key');
      await openImport(tester, store);
      await tester.tap(find.widgetWithText(CbButton, 'Paste exported data'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).first,
        jsonEncode({
          'keychain': [
            {'name': 'Termius key', 'private_key': key.pem},
          ],
        }),
      );
      await preview(tester, 'Preview');
      expect(find.text('Termius key'), findsOneWidget);
      expect(find.text(key.fingerprint), findsOneWidget);
      expect(store.keys, isEmpty);
      await tester.ensureVisible(
        find.widgetWithText(CbButton, 'Import selected'),
      );
      await tester.tap(find.widgetWithText(CbButton, 'Import selected'));
      await tester.pumpAndSettle();
      expect(store.keys.single.fingerprint, key.fingerprint);
      expect(store.profiles, isEmpty);
    },
  );

  testWidgets('deselected host is not saved and cancel leaves the vault empty', (
    tester,
  ) async {
    final store = SshProfileStore();
    await openImport(tester, store);
    await tester.tap(find.widgetWithText(CbButton, 'Paste exported data'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '{"hosts":[{"name":"First host","host":"first.test"},{"name":"Second host","host":"second.test"}]}',
    );
    await preview(tester, 'Preview');
    final row = find.widgetWithText(CheckboxListTile, 'Second host');
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CbButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(store.profiles, isEmpty);
    await tester.tap(find.text('Open import'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CbButton, 'Import a file'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CbButton, 'Paste exported data'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '{"hosts":[{"name":"First host","host":"first.test"},{"name":"Second host","host":"second.test"}]}',
    );
    await preview(tester, 'Preview');
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'Second host'),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Second host'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CbButton, 'Import selected'));
    await tester.pumpAndSettle();
    expect(store.profiles.single.host, 'first.test');
  });

  testWidgets('editing source invalidates preview and disables import', (
    tester,
  ) async {
    final store = SshProfileStore();
    await openImport(tester, store);
    await tester.tap(find.widgetWithText(CbButton, 'Paste exported data'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      '{"hosts":[{"host":"first.test"}]}',
    );
    await preview(tester, 'Preview');
    expect(find.text('first.test'), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.enterText(
      find.byType(TextField).first,
      '{"hosts":[{"host":"changed.test"}]}',
    );
    await tester.pumpAndSettle();
    expect(find.text('first.test'), findsNothing);
    expect(
      tester
          .widget<CbButton>(find.widgetWithText(CbButton, 'Import selected'))
          .onPressed,
      isNull,
    );
    expect(store.profiles, isEmpty);
  });
}
