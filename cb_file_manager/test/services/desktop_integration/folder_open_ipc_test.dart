import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/windowing/desktop_windowing_service.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const native = MethodChannel('cb_file_manager/window_utils');
  const manager = MethodChannel('window_manager');
  late Directory root;
  late DesktopWindowingService receiver;
  late TabManagerBloc tabs;
  late int peerPort;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(native, (_) async => null);
    messenger.setMockMethodCallHandler(
      manager,
      (call) async => call.method == 'isMinimized' ? false : null,
    );
    root = await Directory.systemTemp.createTemp('folder-open-ipc-');
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    receiver = DesktopWindowingService.forTesting(registryPort: port);
    tabs = TabManagerBloc();
    final initial = tabs.stream.first;
    tabs.add(AddTab(path: '#home'));
    await initial;
    await receiver.attachTabBloc(tabs);
    List<DesktopWindowInfo> windows = [];
    for (var i = 0; i < 100 && windows.isEmpty; i++) {
      windows = await receiver.listWindows();
      if (windows.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    peerPort = windows.single.port;
  });

  tearDown(() async {
    await receiver.dispose();
    await tabs.close();
    await root.delete(recursive: true);
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(manager, null);
  });

  Future<Map<String, dynamic>> send(
    List<String> paths, {
    String? executable,
  }) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, peerPort);
    socket.writeln(
      jsonEncode({
        'type': 'open_folders',
        'executable': executable ?? Platform.resolvedExecutable,
        'paths': paths,
      }),
    );
    await socket.flush();
    final response = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    socket.destroy();
    return jsonDecode(response) as Map<String, dynamic>;
  }

  test(
    'existing window receives a validated directory through real peer sockets',
    () async {
      final changed = tabs.stream.firstWhere(
        (state) => state.activeTab?.path == root.path,
      );
      expect((await send([root.uri.toString()]))['type'], 'ok');
      await changed;
      expect(tabs.state.activeTab!.path, root.path);
    },
  );

  test(
    'rejects another executable and inaccessible folder without opening tabs',
    () async {
      expect(
        (await send([root.path], executable: 'different-copy'))['type'],
        'error',
      );
      expect((await send(['${root.path}/missing']))['type'], 'error');
      expect(tabs.state.tabs, hasLength(1));
    },
  );
}
