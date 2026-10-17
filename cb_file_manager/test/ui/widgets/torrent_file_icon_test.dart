import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/helpers/files/file_icon_helper.dart';
import 'package:cb_file_manager/ui/widgets/compact_file_list_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('cb_file_manager/app_icon');
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(FileIconHelper.clearCache);
  tearDown(() {
    FileIconHelper.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<String, Object> pixels(int color) => {
    '.torrent': {
      'iconData': Uint8List.fromList([color, 40, 60, 255]),
      'width': 1,
      'height': 1,
    },
  };

  testWidgets(
    'cold torrent rows use the Windows association icon even for a virtual path',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        expect(call.method, 'extractIconsForExtensions');
        expect(call.arguments['extensions'], ['.torrent']);
        expect(call.arguments['iconSize'], 20);
        return pixels(20);
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 260,
              child: CompactFileListContent(path: '#torrents/hash.TORRENT'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(calls, hasLength(1));
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );

  test(
    'large torrent pages share one native lookup and refresh replaces the cached icon',
    () async {
      final gate = Completer<Map<String, Object>>();
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls++;
            return calls == 1 ? gate.future : pixels(200);
          });
      final icons = List.generate(
        80,
        (i) => FileIconHelper.getIconForFile(File('$i.torrent'), size: 20),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      gate.complete(pixels(20));
      final loaded = await Future.wait(icons);
      expect(loaded.every((icon) => identical(icon, loaded.first)), isTrue);
      FileIconHelper.invalidateExtension('.torrent');
      final refreshed = await FileIconHelper.getIconForFile(
        File('0.torrent'),
        size: 20,
      );
      expect(calls, 2);
      expect(identical(refreshed, loaded.first), isFalse);
    },
    skip: !Platform.isWindows,
  );
}
