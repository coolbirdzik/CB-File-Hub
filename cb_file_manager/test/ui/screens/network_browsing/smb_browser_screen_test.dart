import 'dart:async';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/services/network_browsing/network_discovery_service.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_registry.dart';
import 'package:cb_file_manager/ui/screens/network_browsing/smb_browser_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'network_recovery_test.dart' show host;

void main() {
  testWidgets('SMB scan status and results fit a short viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 385);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final discovery = _TestDiscovery();
    final tabs = TabManagerBloc();
    addTearDown(discovery.devices.close);
    addTearDown(tabs.close);

    await tester.pumpWidget(
      host(
        BlocProvider.value(
          value: tabs,
          child: SMBBrowserScreen(
            tabId: 'smb',
            discoveryService: discovery,
            registry: NetworkServiceRegistry.withServices([]),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final screen = find.byType(SMBBrowserScreen);
    final l10n = AppLocalizations.of(tester.element(screen))!;
    final scrollable = find.descendant(
      of: screen,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );

    final device = NetworkDevice(
      ipAddress: '192.0.2.1',
      name: 'Test SMB server',
      type: NetworkDeviceType.smb,
      hasSmbPort: true,
    );
    discovery.devices.add(device);
    discovery.scan.complete([device]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.scrollUntilVisible(
      find.text(device.name),
      100,
      scrollable: scrollable,
    );
    expect(find.text(device.name).hitTestable(), findsOneWidget);
    expect(find.text(l10n.foundDevicesCount(1)).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestDiscovery extends Fake implements NetworkDiscoveryService {
  final devices = StreamController<NetworkDevice>.broadcast();
  final scan = Completer<List<NetworkDevice>>();

  @override
  Stream<NetworkDevice> get deviceStream => devices.stream;

  @override
  Future<List<NetworkDevice>> scanNetwork() => scan.future;

  @override
  void cancelScan() {}
}
