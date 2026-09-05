import 'dart:io';

import 'package:cb_file_manager/helpers/files/file_icon_helper.dart';
import 'package:cb_file_manager/ui/widgets/compact_file_list_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Compact RAR row uses the Windows associated app icon', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('cb-list-icon-');
    final app = File('${directory.path}/WinRAR.exe')..writeAsBytesSync([]);
    addTearDown(() => directory.deleteSync(recursive: true));
    const channel = MethodChannel('cb_file_manager/app_icon');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'getAssociatedAppPath':
          expect(call.arguments['extension'], '.rar');
          return app.path;
        case 'extractIconFromFile':
          expect(call.arguments['exePath'], app.path);
          return {
            'iconData': Uint8List.fromList([20, 40, 60, 255]),
            'width': 1,
            'height': 1,
          };
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    // Resolve native image decoding outside the fake test clock.
    final appIcon = await tester.runAsync(
      () => FileIconHelper.getIconForFile(File('archive.rar'), size: 20),
    );
    expect(calls.map((call) => call.method), [
      'getAssociatedAppPath',
      'extractIconFromFile',
    ]);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 260,
            child: CompactFileListContent(path: 'archive.RAR'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byWidget(appIcon!), findsOneWidget);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(calls, hasLength(2));
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
