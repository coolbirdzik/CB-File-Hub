import 'dart:io';
import 'package:cb_file_manager/services/windowing/window_acrylic_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final glassCalls = <MethodCall>[];
  final acrylicCalls = <MethodCall>[];
  const glass = MethodChannel('cb_file_manager/macos_window');
  const acrylic = MethodChannel('cb_file_manager/window_utils');
  setUp(() {
    glassCalls.clear();
    acrylicCalls.clear();
    messenger.setMockMethodCallHandler(glass, (call) async {
      glassCalls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(acrylic, (call) async {
      acrylicCalls.add(call);
      return true;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(glass, null);
    messenger.setMockMethodCallHandler(acrylic, null);
  });

  test(
    'macOS passes live Glass intensity and can return to an opaque window',
    () async {
      final service = WindowAcrylicService(platform: TargetPlatform.macOS);
      for (final strength in [0.0, 1.4, 2.0]) {
        await service.applyDesktopAcrylicBackground(
          isDesktopPlatform: true,
          isPipWindow: false,
          isDarkMode: true,
          strength: strength,
        );
        expect(glassCalls.last.method, 'setGlassBackground');
        expect(glassCalls.last.arguments, {
          'enabled': strength > 0,
          'dark': true,
          'strength': strength,
        });
      }
      expect(acrylicCalls, isEmpty);
    },
  );

  test('Windows branch never invokes macOS Glass', () async {
    await WindowAcrylicService(
      platform: TargetPlatform.windows,
    ).applyDesktopAcrylicBackground(
      isDesktopPlatform: true,
      isPipWindow: false,
      isDarkMode: false,
      strength: 1.4,
    );
    expect(glassCalls, isEmpty);
    if (Platform.isWindows) {
      expect(acrylicCalls.single.method, 'setWindowsSystemBackdrop');
      expect(acrylicCalls.single.arguments, {
        'enabled': true,
        'preferAcrylic': true,
        'isDarkMode': false,
      });
    } else {
      // The Windows bridge also guards itself by the host OS.
      expect(acrylicCalls, isEmpty);
    }
  });

  test('PiP and non-desktop windows never receive a backdrop', () async {
    final service = WindowAcrylicService(platform: TargetPlatform.macOS);
    await service.applyDesktopAcrylicBackground(
      isDesktopPlatform: true,
      isPipWindow: true,
      isDarkMode: false,
    );
    await service.applyDesktopAcrylicBackground(
      isDesktopPlatform: false,
      isPipWindow: false,
      isDarkMode: false,
    );
    expect(glassCalls, isEmpty);
  });
}
