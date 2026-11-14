import 'dart:io';

import 'package:cb_file_manager/services/windowing/desktop_windowing_service.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/utils/video_output_folder_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _AppWindows extends DesktopWindowingService {
  bool peerAvailable = true;
  bool creationSucceeds = true;
  bool? allowedSameProcess;
  List<WindowTabPayload>? requestedTabs;
  List<WindowTabPayload>? createdTabs;

  @override
  Future<bool> openFoldersInExistingWindow(
    List<WindowTabPayload> tabs, {
    bool allowSameProcess = false,
  }) async {
    requestedTabs = tabs;
    allowedSameProcess = allowSameProcess;
    return peerAvailable;
  }

  @override
  Future<bool> openNewWindow({
    List<WindowTabPayload> tabs = const [],
    Offset? sourcePointerPosition,
    Offset dragAnchor = kDefaultTabTearOffAnchor,
    bool startDragging = false,
  }) async {
    createdTabs = tabs;
    return creationSucceeds;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const outputName = "phim’s đêm_2.mkv";
  late Directory folder;
  setUp(
    () async =>
        folder = await Directory.systemTemp.createTemp('cb-output-tab-'),
  );
  tearDown(() => folder.delete(recursive: true));

  test(
    'peer IPC selects the exported filename and rejects highlight paths',
    () async {
      const native = MethodChannel('cb_file_manager/window_utils');
      const manager = MethodChannel('window_manager');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(native, (_) async => true);
      messenger.setMockMethodCallHandler(
        manager,
        (call) async => call.method == 'isMinimized' ? false : null,
      );
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final receiver = DesktopWindowingService.forTesting(registryPort: port);
      final sender = DesktopWindowingService.forTesting(registryPort: port);
      final tabs = TabManagerBloc();
      addTearDown(() async {
        await sender.dispose();
        await receiver.dispose();
        await tabs.close();
        messenger.setMockMethodCallHandler(native, null);
        messenger.setMockMethodCallHandler(manager, null);
      });
      await receiver.attachTabBloc(tabs);
      // Peer registration happens asynchronously after attaching the tab bloc.
      List<DesktopWindowInfo> peers = [];
      for (var attempt = 0; attempt < 100 && peers.isEmpty; attempt++) {
        peers = await sender.listWindows();
        if (peers.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      }
      expect(peers, hasLength(1));
      final opened = tabs.stream.first;
      expect(
        await sender.openFoldersInExistingWindow([
          WindowTabPayload(path: folder.path, highlightedFileName: outputName),
        ], allowSameProcess: true),
        isTrue,
      );
      await opened;
      expect(tabs.state.activeTab!.path, folder.path);
      expect(tabs.state.activeTab!.highlightedFileName, outputName);
      expect(
        await sender.openFoldersInExistingWindow([
          WindowTabPayload(
            path: folder.path,
            highlightedFileName: '../outside.mkv',
          ),
        ], allowSameProcess: true),
        isFalse,
      );
      expect(tabs.state.tabs, hasLength(1));
    },
  );

  test(
    'player routes output to an existing app window, including another engine in the same process',
    () async {
      final windows = _AppWindows();
      expect(
        await windows.openFolderInNewTab(
          folder.path,
          highlightedFileName: outputName,
        ),
        isTrue,
      );
      expect(windows.requestedTabs!.single.path, p.normalize(folder.path));
      expect(windows.allowedSameProcess, isTrue);
      expect(windows.requestedTabs!.single.highlightedFileName, outputName);
      expect(windows.createdTabs, isNull);
    },
  );

  test(
    'no browser window creates an app window with the result folder tab',
    () async {
      final windows = _AppWindows()..peerAvailable = false;
      expect(
        await windows.openFolderInNewTab(
          folder.path,
          highlightedFileName: outputName,
        ),
        isTrue,
      );
      expect(windows.createdTabs!.single.path, p.normalize(folder.path));
      expect(
        WindowTabPayload.fromJson(
          windows.createdTabs!.single.toJson(),
        ).highlightedFileName,
        outputName,
      );
    },
  );

  test('unavailable app windows return failure', () async {
    final windows = _AppWindows()
      ..peerAvailable = false
      ..creationSucceeds = false;
    expect(
      await windows.openFolderInNewTab(
        folder.path,
        highlightedFileName: outputName,
      ),
      isFalse,
    );
  });

  test('missing output folder never opens a window', () async {
    final windows = _AppWindows();
    expect(
      await windows.openFolderInNewTab(p.join(folder.path, 'missing')),
      isFalse,
    );
    expect(windows.requestedTabs, isNull);
    expect(windows.createdTabs, isNull);
  });

  testWidgets(
    'local player opens and selects a fresh tab even when that folder is already open',
    (tester) async {
      final tabs = TabManagerBloc();
      addTearDown(tabs.close);
      final initial = tabs.stream.first;
      tabs.add(AddTab(path: folder.path));
      await tester.pump();
      await initial;
      final firstId = tabs.state.activeTabId;
      final windows = _AppWindows();
      Future<void>? opening;
      await tester.pumpWidget(
        BlocProvider.value(
          value: tabs,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    opening = openVideoOutputFolderInApp(
                      context,
                      folder.path,
                      highlightedFileName: outputName,
                      windows: windows,
                    );
                  },
                  child: const Text('Open output'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Open output'));
        await opening!;
      });
      await tester.pumpAndSettle();
      expect(tabs.state.tabs, hasLength(2));
      expect(tabs.state.activeTabId, isNot(firstId));
      expect(tabs.state.activeTab!.path, folder.path);
      expect(tabs.state.activeTab!.highlightedFileName, outputName);
      expect(windows.requestedTabs, isNull);
      expect(windows.createdTabs, isNull);
    },
  );

  testWidgets(
    'fullscreen player returns to the browser after opening its output tab',
    (tester) async {
      final tabs = TabManagerBloc();
      addTearDown(tabs.close);
      Future<void>? opening;
      await tester.pumpWidget(
        BlocProvider.value(
          value: tabs,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (context) => Scaffold(
                        body: TextButton(
                          onPressed: () async {
                            opening = openVideoOutputFolderInApp(
                              context,
                              folder.path,
                              highlightedFileName: outputName,
                            );
                          },
                          child: const Text('Open output'),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Browser'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Browser'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Open output'));
        await opening!;
      });
      await tester.pumpAndSettle();
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Open output'), findsNothing);
      expect(tabs.state.activeTab!.path, folder.path);
      expect(tabs.state.activeTab!.highlightedFileName, outputName);
    },
  );

  testWidgets(
    'dedicated player routes through the app service and keeps its own route',
    (tester) async {
      final windows = _AppWindows();
      Future<void>? opening;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  opening = openVideoOutputFolderInApp(
                    context,
                    folder.path,
                    highlightedFileName: outputName,
                    windows: windows,
                  );
                },
                child: const Text('Player output'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Player output'));
        await opening!;
      });
      await tester.pumpAndSettle();
      expect(windows.requestedTabs!.single.path, folder.path);
      expect(windows.requestedTabs!.single.highlightedFileName, outputName);
      expect(find.text('Player output'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
