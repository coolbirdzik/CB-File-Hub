import 'dart:io';

import 'package:cb_file_manager/services/windowing/desktop_windowing_service.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('cb_file_manager/window_utils');
  const manager = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(native, null);
    messenger.setMockMethodCallHandler(manager, null);
  });

  test('a torn-off window appears with its tab drawn, then lets the source '
      'close it', () async {
    final events = <String>[];
    late TabManagerBloc tabs;
    messenger.setMockMethodCallHandler(native, (call) async {
      events.add(
        call.method == 'holdTabWindowHidden'
            ? 'hold:${call.arguments}'
            : call.method,
      );
      return true;
    });
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (call.method == 'show') {
        events.add('show tabs=${tabs.state.tabs.length}');
      }
      if (call.method == 'isMinimized') return false;
      return null;
    });

    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final receiver = DesktopWindowingService.forTesting(registryPort: port);
    final sender = DesktopWindowingService.forTesting(registryPort: port);
    tabs = TabManagerBloc();
    addTearDown(() async {
      await receiver.dispose();
      await tabs.close();
    });
    await receiver.attachTabBloc(tabs);
    List<DesktopWindowInfo> windows = [];
    for (var attempt = 0; attempt < 100 && windows.isEmpty; attempt++) {
      windows = await receiver.listWindows();
      if (windows.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
    expect(windows, hasLength(1));
    events.clear();

    final shown = await sender.requestShowWindow(
      windows.single,
      tabs: const [WindowTabPayload(path: '#video-library/1', name: 'av')],
      dragAnchor: const Offset(140, 27),
    );
    events.add('source closes tab');

    expect(shown, isTrue);
    expect(tabs.state.tabs.map((t) => t.name), ['av']);
    final relevant = events
        // Activation follows the reply and may race it.
        .where((e) => e != 'focus' && e != 'forceActivateWindow')
        .takeWhile((e) => e != 'source closes tab')
        .toList();
    expect(
      relevant,
      Platform.isWindows
          ? [
              // Cloaked first, so nothing half-drawn is ever on screen.
              'hold:true',
              'startTabWindowDrag',
              'show tabs=1',
              'hold:false',
            ]
          : ['show tabs=1'],
    );
    // The reply that lets the source close the tab comes after the reveal.
    expect(
      events.indexOf('source closes tab'),
      greaterThan(events.indexOf('show tabs=1')),
    );
  });

  test(
    'a spare readied during a tab drag is revealed in place or returned',
    () async {
      final events = <String>[];
      late TabManagerBloc tabs;
      messenger.setMockMethodCallHandler(native, (call) async {
        events.add(switch (call.method) {
          'holdTabWindowHidden' => 'hold:${call.arguments}',
          // Shown without activation: the source still holds the drag.
          'showWindowInactive' =>
            'showWindowInactive tabs=${tabs.state.tabs.length}',
          'placeWindowClientAt' =>
            'place:${(call.arguments as Map)['x']},${(call.arguments as Map)['y']}',
          _ => call.method,
        });
        if (call.method == 'getTopLevelWindowHandle') return 0x1234;
        return true;
      });
      messenger.setMockMethodCallHandler(manager, (call) async {
        switch (call.method) {
          case 'show':
            events.add(
              'show inactive=${(call.arguments as Map?)?['inactive']} '
              'tabs=${tabs.state.tabs.length}',
            );
          case 'hide':
          case 'setSkipTaskbar':
            events.add(call.method);
          case 'isMinimized':
          case 'isVisible':
            return false;
        }
        return null;
      });

      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = reservation.port;
      await reservation.close();
      final spare = DesktopWindowingService.forTesting(
        registryPort: port,
        windowRole: 'spare',
      );
      final source = DesktopWindowingService.forTesting(registryPort: port);
      tabs = TabManagerBloc();
      addTearDown(() async {
        await spare.dispose();
        await tabs.close();
      });
      await spare.attachTabBloc(tabs);
      for (var attempt = 0; attempt < 100; attempt++) {
        final windows = await source.listWindows();
        if (windows.any((w) => w.role == 'spare')) break;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      events.clear();

      const moved = [WindowTabPayload(path: '#video-library/1', name: 'av')];
      var window = await source.prepareTearOffWindow(moved);
      expect(window, isNotNull);
      // Handed to the drag preview for the native swap on release.
      expect(window!.windowHandle, Platform.isWindows ? 0x1234 : isNull);
      expect(tabs.state.tabs.map((t) => t.name), ['av']);
      // Busy now: a second tear-off cannot take the same window.
      expect(await source.prepareTearOffWindow(moved), isNull);
      expect(
        events,
        Platform.isWindows
            ? [
                'hold:true',
                'showWindowInactive tabs=1',
                'setSkipTaskbar',
                'getTopLevelWindowHandle',
              ]
            : ['showWindowInactive tabs=1'],
      );

      // Dropped back on a tab strip: the spare empties and hides again.
      events.clear();
      await source.discardPreparedWindow(window.window);
      await Future<void>.delayed(Duration.zero);
      expect(tabs.state.tabs, isEmpty);
      expect(events.where((e) => e != 'hold:false'), ['hide']);

      // Dropped on empty space: placed under the preview, then uncloaked.
      window = await source.prepareTearOffWindow(moved);
      expect(window, isNotNull);
      events.clear();
      expect(
        await source.revealPreparedWindow(
          window!.window,
          const Offset(300, 200),
        ),
        isTrue,
      );
      events.add('source drops preview');
      for (var i = 0; i < 20 && !events.contains('setSkipTaskbar'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final reveal = events
          .where((e) => e != 'focus' && e != 'forceActivateWindow')
          .toList();
      // On screen before the reply; the taskbar entry is not waited for.
      if (Platform.isWindows) {
        expect(reveal.take(2), ['place:300.0,200.0', 'hold:false']);
        expect(
          reveal.indexOf('setSkipTaskbar'),
          greaterThan(reveal.indexOf('hold:false')),
        );
      }
      expect(reveal, contains('setSkipTaskbar'));
      expect(
        reveal.indexOf('source drops preview'),
        greaterThan(reveal.indexOf('hold:false')),
      );
      expect(await source.prepareTearOffWindow(moved), isNull);
    },
    // Preparing a cloaked spare uses Win32 window handles and is deliberately
    // unavailable on Linux/macOS. Generic window showing is covered above.
    skip: !Platform.isWindows,
  );

  test('non-Windows does not prepare a native tab-drag spare', () async {
    final source = DesktopWindowingService.forTesting(registryPort: 0);
    expect(
      await source.prepareTearOffWindow(const [
        WindowTabPayload(path: '#home', name: 'Home'),
      ]),
      isNull,
    );
  }, skip: Platform.isWindows);
}
