import 'dart:io';
import 'package:cb_file_manager/helpers/files/windows_app_icon.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cb_file_manager/app_icon');
  final calls = <MethodCall>[];
  var registered = true;
  setUp(() {
    calls.clear();
    registered = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'registerTorrentAssociations'
              ? registered
              : true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'default apps action registers this executable then opens Windows chooser',
    () async {
      expect(await WindowsAppIcon.openTorrentDefaultSettings(), isTrue);
      expect(calls.map((c) => c.method), [
        'registerTorrentAssociations',
        'openTorrentDefaultSettings',
      ]);
      expect(
        (calls.first.arguments as Map)['exePath'],
        Platform.resolvedExecutable,
      );
      expect(
        (calls.first.arguments as Map).containsKey('setAsDefault'),
        isFalse,
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'registration failure is visible and does not launch a misleading chooser',
    () async {
      registered = false;
      expect(await WindowsAppIcon.openTorrentDefaultSettings(), isFalse);
      expect(calls.map((c) => c.method), ['registerTorrentAssociations']);
    },
    skip: !Platform.isWindows,
  );
}
