import 'dart:io';

import 'package:cb_file_manager/services/windowing/torrent_options_window_anchor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const windowChannel = MethodChannel('window_manager');
  const placementChannel = MethodChannel(
    'cb_file_manager/torrent_options_window',
  );
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'getId':
          return 7654;
        case 'getBounds':
          return {'x': -1600.0, 'y': 120.0, 'width': 1000.0, 'height': 800.0};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(placementChannel, (call) async {
      calls.add(call);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(windowChannel, null);
    messenger.setMockMethodCallHandler(placementChannel, null);
  });

  test(
    'captures the calling window without primary-monitor coordinates',
    () async {
      final anchor = await TorrentOptionsWindowAnchor.capture();
      final received = TorrentOptionsWindowAnchor.fromJson(anchor.toJson());
      if (Platform.isWindows) {
        expect(received.windowId, 7654);
        expect(received.bounds, isNull);
        expect(calls.single.method, 'getId');
      } else {
        expect(received.bounds, const Rect.fromLTWH(-1600, 120, 1000, 800));
      }
    },
  );

  test(
    'positions against the live Windows parent instead of window-manager centering',
    () async {
      const anchor = TorrentOptionsWindowAnchor(windowId: 7654);
      await anchor.place();
      expect(calls, hasLength(1));
      expect(calls.single.method, 'centerOnParent');
      expect(calls.single.arguments, {'parentWindowId': 7654});
    },
    skip: !Platform.isWindows,
  );

  test('unavailable parent delegates to native monitor fallback', () async {
    const anchor = TorrentOptionsWindowAnchor();
    await anchor.place();
    expect(calls.single.method, 'centerOnParent');
    expect(calls.single.arguments, {'parentWindowId': null});
  }, skip: !Platform.isWindows);

  test('closed parent lookup does not prevent opening a form', () async {
    messenger.setMockMethodCallHandler(windowChannel, (_) async {
      throw PlatformException(code: 'window_closed');
    });
    final anchor = await TorrentOptionsWindowAnchor.capture();
    expect(anchor.windowId, isNull);
    expect(anchor.bounds, isNull);
  });
}
