import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/primitives/cb_button.dart';
import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/screens/network_browsing/components/network_navigation_bar.dart';
import 'package:cb_file_manager/ui/screens/system_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_recovery_test.dart' show host;

Finder command(String label) => find.byWidgetPredicate(
  (w) =>
      (w is CbButton && w.tooltip == label) ||
      (w is CbFluentTooltip && w.message == label),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('address editing preserves shares and virtual system destinations', () {
    const path = '#network/SMB/server/Shared Documents/folder/';
    expect(networkAddress(path), 'smb://server/Shared Documents/folder/');
    expect(networkPathFromAddress(networkAddress(path)), path);
    expect(networkPathFromAddress('#smb'), '#smb');
    expect(networkAddress('#smb'), '#smb');
    const sftpPath = '#network/SFTP/dev%40host%3A2222/folder one/a%20.txt';
    expect(networkPathFromAddress(networkAddress(sftpPath)), sftpPath);
    expect(
      networkPathFromAddress('ftp://server/files'),
      '#network/FTP/server/files',
    );
  });

  test('network Up follows the virtual hierarchy', () {
    expect(networkParentPath('#network'), '#home');
    for (final protocol in ['SMB', 'FTP', 'WebDAV']) {
      final root = '#${protocol.toLowerCase()}';
      expect(networkParentPath(root), '#network');
      expect(networkParentPath('#network/$protocol/server/'), root);
      expect(
        networkParentPath('#network/$protocol/server/share/folder/'),
        '#network/$protocol/server/share/',
      );
    }
  });

  for (final path in ['#network', '#smb', '#ftp', '#webdav']) {
    for (final width in [320.0, 1200.0]) {
      testWidgets('$path uses file navigation at width $width', (tester) async {
        tester.view.physicalSize = Size(width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tabs = TabManagerBloc();
        addTearDown(tabs.close);
        var changed = tabs.stream.first;
        tabs.add(AddTab(path: '#home'));
        await changed;
        final id = tabs.state.activeTabId!;
        changed = tabs.stream.first;
        tabs.add(UpdateTabPath(id, path));
        await changed;
        var refreshCount = 0;
        var addCount = 0;
        await tester.pumpWidget(
          BlocProvider.value(
            value: tabs,
            child: host(
              BlocBuilder<TabManagerBloc, TabManagerState>(
                builder: (context, state) {
                  final current = state.activeTab!.path;
                  if (current == '#home') {
                    return const Center(child: Text('Home destination'));
                  }
                  final l10n = AppLocalizations.of(context)!;
                  return SystemScreen(
                    title: 'Network',
                    systemId: current,
                    icon: Icons.computer,
                    tabId: id,
                    showAppBar: true,
                    onRefresh: () => refreshCount++,
                    actions: [
                      CbButton.icon(
                        icon: Icons.refresh,
                        tooltip: l10n.refresh,
                        onPressed: () => refreshCount++,
                      ),
                      CbButton.icon(
                        icon: Icons.add,
                        tooltip: l10n.addConnection,
                        onPressed: () => addCount++,
                      ),
                    ],
                    child: const Column(
                      children: [
                        Text(
                          'Network discovery is disabled',
                          key: ValueKey('content-start'),
                        ),
                        Expanded(
                          child: Center(child: Text('Saved connections')),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(NetworkNavigationBar)),
        )!;
        for (final label in [
          l10n.back,
          l10n.forward,
          l10n.parentFolder,
          l10n.home,
          l10n.refresh,
          l10n.addConnection,
        ]) {
          expect(command(label), findsOneWidget);
        }
        final toolbar = tester.getRect(
          find.byKey(const ValueKey('fluent-browser-toolbar')),
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('content-start'))).top,
          greaterThanOrEqualTo(toolbar.bottom),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.f5);
        expect(refreshCount, 1);
        await tester.tap(command(l10n.addConnection));
        expect(addCount, 1);
        await tester.tap(command(l10n.parentFolder));
        await tester.pumpAndSettle();
        expect(tabs.state.activeTab!.path, networkParentPath(path));
        if (path != '#network') {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          await tester.pumpAndSettle();
          expect(tabs.state.activeTab!.path, path);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
          await tester.pumpAndSettle();
          expect(tabs.state.activeTab!.path, '#network');
          await tester.tap(command(l10n.back));
          await tester.pumpAndSettle();
          expect(tabs.state.activeTab!.path, path);
          await tester.tap(command(l10n.forward));
          await tester.pumpAndSettle();
          expect(tabs.state.activeTab!.path, '#network');
          await tester.tap(command(l10n.home));
          await tester.pumpAndSettle();
        }
        expect(tabs.state.activeTab!.path, '#home');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('network breadcrumbs navigate to the owning tab', (tester) async {
    final tabs = TabManagerBloc();
    addTearDown(tabs.close);
    var changed = tabs.stream.first;
    const path = '#network/SMB/server/share/folder/';
    tabs.add(AddTab(path: path));
    await changed;
    final ownerId = tabs.state.activeTabId!;
    changed = tabs.stream.first;
    tabs.add(AddTab(path: '#home'));
    await changed;
    await tester.pumpWidget(
      BlocProvider.value(
        value: tabs,
        child: host(
          Scaffold(
            body: NetworkNavigationBar(tabId: ownerId, path: path),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final crumbs = tester.widget<BreadcrumbAddressBar>(
      find.byType(BreadcrumbAddressBar),
    );
    expect(crumbs.segments.map((s) => s.label), [
      'Network',
      'SMB',
      'server',
      'share',
      'folder',
    ]);
    crumbs.segments[1].onTap!();
    await tester.pumpAndSettle();
    expect(tabs.state.tabs.first.path, '#smb');
    expect(tabs.state.activeTab!.path, '#home');
    expect(tester.takeException(), isNull);
  });

  testWidgets('SFTP browsing Home returns to the SSH workspace', (
    tester,
  ) async {
    final tabs = TabManagerBloc();
    addTearDown(tabs.close);
    const path = '#network/SFTP/developer%40dev.example.test%3A2222/home/';
    var changed = tabs.stream.first;
    tabs.add(AddTab(path: path));
    await changed;
    final tabId = tabs.state.activeTabId!;
    await tester.pumpWidget(
      BlocProvider.value(
        value: tabs,
        child: host(
          Scaffold(
            body: NetworkNavigationBar(
              tabId: tabId,
              path: path,
              homePath: '#ssh',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(NetworkNavigationBar)),
    )!;
    await tester.tap(command(l10n.home));
    await tester.pumpAndSettle();
    expect(tabs.state.activeTab!.path, '#ssh');
    expect(tester.takeException(), isNull);
  });
}
