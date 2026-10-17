import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/windowing/desktop_windowing_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _AssociationService extends DesktopWindowingService {
  final List<DesktopWindowInfo> windows;

  _AssociationService(this.windows);

  @override
  Future<List<DesktopWindowInfo>> listWindows() async => windows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('cb_file_manager/window_utils');
  const manager = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <String>[];
  final grants = <Object?>[];
  var minimized = false;
  String? failingMethod;

  setUp(() {
    calls.clear();
    grants.clear();
    minimized = false;
    failingMethod = null;
    messenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call.method);
      if (call.method == 'allowForegroundWindow') grants.add(call.arguments);
      return true;
    });
    messenger.setMockMethodCallHandler(manager, (call) async {
      calls.add(call.method);
      if (call.method == failingMethod) {
        throw PlatformException(code: 'unavailable');
      }
      if (call.method == 'isMinimized') return minimized;
      if (call.method == 'restore') minimized = false;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(manager, null);
  });

  test('window registry preserves PID and accepts older registrations', () {
    const window = DesktopWindowInfo(
      windowId: 'existing',
      port: 1234,
      title: 'Torrent',
      tabCount: 2,
      processId: 4321,
    );
    expect(DesktopWindowInfo.fromJson(window.toJson()).processId, 4321);
    final old = window.toJson()..remove('processId');
    expect(DesktopWindowInfo.fromJson(old).processId, isNull);
  });

  for (final source in [
    r'C:\Downloads\example.torrent',
    'magnet:?xt=urn:btih:${'1' * 40}',
  ]) {
    test(
      'association grants foreground permission before forwarding $source',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final received = <Map<String, dynamic>>[];
        final subscription = server.listen((socket) async {
          final line = await socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first;
          calls.add('delivered');
          received.add(jsonDecode(line) as Map<String, dynamic>);
          socket.write('${jsonEncode({'type': 'ok'})}\n');
          await socket.flush();
          await socket.close();
        });
        addTearDown(() async {
          await subscription.cancel();
          await server.close();
        });
        final service = _AssociationService([
          DesktopWindowInfo(
            windowId: 'existing',
            port: server.port,
            title: 'Torrent',
            tabCount: 2,
            processId: 4321,
          ),
        ]);

        expect(
          await service.openTorrentSourcesInExistingWindow([source]),
          isTrue,
        );
        expect(received.single['sources'], [source]);
        expect(received.single['type'], 'open_torrent_sources');
        if (Platform.isWindows) {
          expect(grants, [
            {'any': false, 'pid': 4321},
          ]);
          expect(calls, ['allowForegroundWindow', 'delivered']);
        }
      },
    );
  }

  test('minimized shell restores before showing and taking focus', () async {
    minimized = true;
    await DesktopWindowingService.focusTorrentWindow();
    expect(minimized, isFalse);
    expect(calls, [
      'isMinimized',
      'restore',
      'show',
      'focus',
      if (Platform.isWindows) 'forceActivateWindow',
    ]);
  });

  test('visible or maximized shell takes focus without restoring', () async {
    await DesktopWindowingService.focusTorrentWindow();
    expect(calls, [
      'isMinimized',
      'show',
      'focus',
      if (Platform.isWindows) 'forceActivateWindow',
    ]);
  });

  test('native activation still runs when plugin focus fails', () async {
    failingMethod = 'focus';
    await DesktopWindowingService.focusTorrentWindow();
    if (Platform.isWindows) expect(calls.last, 'forceActivateWindow');
  });
}
