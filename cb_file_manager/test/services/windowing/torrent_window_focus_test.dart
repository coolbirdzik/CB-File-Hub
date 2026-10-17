import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/windowing/desktop_windowing_service.dart';
import 'package:cb_file_manager/services/windowing/windows_native_tab_drag_drop_service.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
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

  test(
    'peer acknowledges and switches tabs before slow OS focus finishes',
    () async {
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final receiver = DesktopWindowingService.forTesting(registryPort: port);
      final tabs = TabManagerBloc();
      final focusGate = Completer<void>();
      messenger.setMockMethodCallHandler(manager, (call) async {
        if (call.method == 'isMinimized') return false;
        if (call.method == 'show') await focusGate.future;
        return null;
      });
      addTearDown(() async {
        if (!focusGate.isCompleted) focusGate.complete();
        await receiver.dispose();
        await tabs.close();
      });
      final homeAdded = tabs.stream.first;
      tabs.add(AddTab(path: '#home'));
      await homeAdded;
      await receiver.attachTabBloc(tabs);
      // Heartbeat registration is intentionally asynchronous.
      List<DesktopWindowInfo> windows = [];
      for (var attempt = 0; attempt < 100 && windows.isEmpty; attempt++) {
        windows = await receiver.listWindows();
        if (windows.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      expect(windows, hasLength(1));
      final sender = _AssociationService(windows);
      final switched = tabs.stream.firstWhere(
        (state) => state.activeTab?.path == '#torrents',
      );
      expect(
        await sender
            .openTorrentSourcesInExistingWindow([
              'magnet:?xt=urn:btih:${'5' * 40}',
            ])
            .timeout(const Duration(seconds: 1)),
        isTrue,
      );
      await switched;
      expect(tabs.state.tabs, hasLength(2));
      expect(focusGate.isCompleted, isFalse);
      focusGate.complete();
    },
  );

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

  test(
    'native fast handoff forwards sources and rejects malformed requests',
    () async {
      final tabs = TabManagerBloc();
      final received = <List<String>>[];
      WindowsNativeTabDragDropService.initialize(tabs);
      WindowsNativeTabDragDropService.onTorrentSources = received.add;
      addTearDown(() async {
        WindowsNativeTabDragDropService.onTorrentSources = null;
        await tabs.close();
      });
      Future<void> deliver(Object? arguments) async {
        await messenger.handlePlatformMessage(
          native.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onNativeTorrentSources', arguments),
          ),
          (_) {},
        );
      }

      final sources = [
        'magnet:?xt=urn:btih:${'6' * 40}',
        r'C:\Downloads\example.torrent',
      ];
      await deliver(sources);
      await deliver([]);
      await deliver(['ordinary.txt']);
      await deliver([sources.first, 7]);
      await deliver(List.filled(101, sources.first));
      expect(received, [sources]);
    },
  );
}
