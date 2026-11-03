import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/services/ssh/ssh_profile_store.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_connection_status.dart';
import 'package:cb_file_manager/ui/screens/ssh/ssh_host_list_item.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('host click selects, double click and Enter open, menu edits', (
    tester,
  ) async {
    var selected = 0;
    var opened = 0;
    var openedInNewTab = 0;
    var edited = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 270,
            height: 40,
            child: SshHostListItem(
              name: 'Development server',
              description: 'developer@dev.example.test:2222',
              isDesktop: true,
              isSelected: false,
              onSelect: () => selected++,
              onOpen: () => opened++,
              onOpenInNewTab: () => openedInNewTab++,
              onBrowse: () {},
              menuTooltip: 'More options',
              terminalTooltip: 'Open terminal',
              browseTooltip: 'Browse SFTP',
              menuBuilder: (_) => [
                PopupMenuItem<void>(
                  onTap: () => edited++,
                  child: const Text('Edit'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Development server'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected, 1);
    expect(opened, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(opened, 1);
    await tester.tap(find.text('Development server'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Development server'));
    expect(opened, 2);
    await tester.tap(
      find.text('Development server'),
      buttons: kMiddleMouseButton,
    );
    expect(openedInNewTab, 1);
    expect(
      tester
          .widget<PopupMenuButton<void>>(find.byType(PopupMenuButton<void>))
          .popUpAnimationStyle,
      AnimationStyle.noAnimation,
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(edited, 1);
    expect(tester.takeException(), isNull);
  });

  Widget card({
    String name = 'Development server',
    SshConnectionStatus? status,
  }) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 280,
          height: SshHostListItem.gridExtent,
          child: SshHostListItem(
            name: name,
            description: 'developer@dev.example.test:2222',
            isDesktop: true,
            isSelected: false,
            isGrid: true,
            group: 'Production',
            routeLabel: 'Proxy: Office',
            viaProxy: true,
            connectionStatus: status,
            onSelect: () {},
            onOpen: () {},
            onBrowse: () {},
            menuTooltip: 'More options',
            terminalTooltip: 'Open terminal',
            browseTooltip: 'Browse SFTP',
            menuBuilder: (_) => const [],
          ),
        ),
      ),
    ),
  );

  testWidgets('grid card wraps a long name onto a second line', (tester) async {
    const long = 'Production database primary replica in Singapore region';
    await tester.pumpWidget(card(name: long));
    final name = tester.renderObject<RenderParagraph>(find.text(long));
    final lineHeight = name.getFullHeightForCaret(
      const TextPosition(offset: 0),
    );
    expect(name.size.height, closeTo(lineHeight * 2, 1));
    expect(find.text('Proxy: Office'), findsOneWidget);
    expect(find.text('Production'), findsOneWidget);

    // A short name keeps one line and the lines below stay put.
    final addressTop = tester.getTopLeft(
      find.text('developer@dev.example.test:2222'),
    );
    await tester.pumpWidget(card(name: 'Dev'));
    expect(
      tester.getTopLeft(find.text('developer@dev.example.test:2222')),
      addressTop,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid card shows proxy and SSH steps on one line', (
    tester,
  ) async {
    await tester.pumpWidget(
      card(
        status: const SshConnectionStatus(
          phase: SshConnectPhase.authenticating,
          failed: true,
        ),
      ),
    );
    expect(find.text('Proxy'), findsOneWidget);
    expect(find.text('SSH Authentication failed'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Proxy')).dy,
      tester.getCenter(find.text('SSH Authentication failed')).dy,
    );
    expect(find.text('Proxy: Office'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('connection status splits proxy and SSH steps', () {
    final tr = EnglishLocalizations();
    const tunneling = SshConnectionStatus(
      phase: SshConnectPhase.proxyNegotiating,
    );
    expect(tunneling.proxy, SshStepState.active);
    expect(tunneling.ssh, SshStepState.idle);
    expect(tunneling.proxyLabel(tr), 'Opening tunnel…');

    const authFailed = SshConnectionStatus(
      phase: SshConnectPhase.authenticating,
      failed: true,
    );
    expect(authFailed.proxy, SshStepState.done);
    expect(authFailed.ssh, SshStepState.failed);
    expect(authFailed.sshLabel(tr), 'Authentication failed');

    const connected = SshConnectionStatus(phase: SshConnectPhase.connected);
    expect(connected.ssh, SshStepState.done);
    expect(const SshConnectionStatus(failed: true).ssh, SshStepState.failed);
    expect(const SshConnectionStatus().isIdle, isTrue);
  });

  testWidgets('connection steps stay compact and explain both in a tooltip', (
    tester,
  ) async {
    Future<void> pump(SshConnectionStatus status, SshProxy? proxy) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                child: Row(
                  children: [
                    Flexible(
                      child: SshConnectionSteps(
                        status: status,
                        proxy: proxy,
                        address: 'developer@dev.example.test:2222',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    String step(String key) => tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Text),
          ),
        )
        .textSpan!
        .toPlainText();
    String tooltip() => tester.widget<Tooltip>(find.byType(Tooltip)).message!;

    await pump(
      const SshConnectionStatus(
        phase: SshConnectPhase.proxyNegotiating,
        failed: true,
      ),
      const SshProxy(
        id: 'office',
        name: 'Office gateway behind the corporate firewall',
        type: SshProxyType.socks5,
        host: '10.0.0.1',
        port: 1080,
        username: 'proxy-user',
        password: 'proxy-secret',
      ),
    );
    expect(step('ssh-step-proxy'), 'Proxy Connection failed');
    expect(step('ssh-step-ssh'), 'SSH');
    expect(
      tester.getCenter(find.byKey(const ValueKey('ssh-step-proxy'))).dy,
      tester.getCenter(find.byKey(const ValueKey('ssh-step-ssh'))).dy,
    );
    expect(tooltip(), contains('SOCKS5 10.0.0.1:1080'));
    expect(tooltip(), contains('SSH: Not connected'));
    expect(tooltip(), isNot(contains('proxy-secret')));
    expect(tooltip(), isNot(contains('proxy-user')));
    expect(tester.takeException(), isNull);

    await pump(
      const SshConnectionStatus(phase: SshConnectPhase.authenticating),
      null,
    );
    expect(find.byKey(const ValueKey('ssh-step-proxy')), findsNothing);
    expect(step('ssh-step-ssh'), 'SSH Authenticating…');
    expect(tooltip(), contains('Proxy: Direct connection'));
    expect(tester.takeException(), isNull);
  });
}
