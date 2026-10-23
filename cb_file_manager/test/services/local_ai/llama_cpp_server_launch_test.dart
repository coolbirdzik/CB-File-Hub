import 'dart:io';

import 'package:cb_file_manager/services/local_ai/llama_cpp_server_launch.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(LlamaCppServerLaunch.channel, null);
  });

  test(
    'Android launches the APK native executable with bounded CPU settings',
    () async {
      final nativeDir = Directory.systemTemp.path;
      final serverPath =
          '$nativeDir${Platform.pathSeparator}libcb_llama_server.so';
      messenger.setMockMethodCallHandler(LlamaCppServerLaunch.channel, (
        call,
      ) async {
        expect(call.method, 'getLlamaServerPath');
        return serverPath;
      });
      final launch = await LlamaCppServerLaunch.resolve(
        platform: TargetPlatform.android,
        desktopExecutableName: 'llama-server.exe',
      );
      expect(launch.executablePath, serverPath);
      expect(launch.workingDirectory, nativeDir);
      expect(launch.environment, {'LD_LIBRARY_PATH': nativeDir});
      final args = launch.arguments(
        modelPath: '/data/user/0/app/files/model with spaces.gguf',
        port: 12345,
        contextTokens: 8192,
        gpuLayers: 99,
      );
      expect(
        args[args.indexOf('-m') + 1],
        '/data/user/0/app/files/model with spaces.gguf',
      );
      expect(args[args.indexOf('--host') + 1], '127.0.0.1');
      expect(args[args.indexOf('-ngl') + 1], '0');
      expect(args[args.indexOf('-c') + 1], '8192');
      expect(args[args.indexOf('--parallel') + 1], '1');
      expect(args[args.indexOf('--batch-size') + 1], '128');
      expect(args[args.indexOf('--ubatch-size') + 1], '128');
      expect(args[args.indexOf('--cache-ram') + 1], '0');
    },
  );

  test(
    'Windows retains the isolated Vulkan runtime and configured GPU layers',
    () async {
      final launch = await LlamaCppServerLaunch.resolve(
        platform: TargetPlatform.windows,
        desktopExecutableName: 'llama-server.exe',
      );
      final sep = Platform.pathSeparator;
      expect(
        launch.executablePath,
        endsWith('${sep}llama${sep}llama-server.exe'),
      );
      expect(launch.environment, isNull);
      final args = launch.arguments(
        modelPath: 'model.gguf',
        port: 12345,
        contextTokens: 16384,
        gpuLayers: 42,
      );
      expect(args[args.indexOf('-ngl') + 1], '42');
      expect(args, isNot(contains('--batch-size')));
    },
  );

  test(
    'macOS resolves the signed bundle helper and retains Metal offload',
    () async {
      final nativeDir = Directory.systemTemp.path;
      final serverPath = '$nativeDir${Platform.pathSeparator}llama-server';
      messenger.setMockMethodCallHandler(LlamaCppServerLaunch.channel, (
        call,
      ) async {
        expect(call.method, 'getLlamaServerPath');
        return serverPath;
      });
      final launch = await LlamaCppServerLaunch.resolve(
        platform: TargetPlatform.macOS,
        desktopExecutableName: 'llama-server.exe',
      );
      expect(launch.executablePath, serverPath);
      expect(launch.workingDirectory, nativeDir);
      expect(launch.environment, isNull);
      final args = launch.arguments(
        modelPath: '/Users/test/Library/Application Support/model.gguf',
        port: 12345,
        contextTokens: 8192,
        gpuLayers: 99,
      );
      expect(args[args.indexOf('-ngl') + 1], '99');
      expect(args, isNot(contains('--batch-size')));
    },
  );

  test('an old macOS app explains that its helper must be installed', () async {
    await expectLater(
      LlamaCppServerLaunch.resolve(
        platform: TargetPlatform.macOS,
        desktopExecutableName: 'llama-server.exe',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('macOS'),
        ),
      ),
    );
  });

  test('macOS surfaces its minimum OS requirement', () async {
    messenger.setMockMethodCallHandler(LlamaCppServerLaunch.channel, (_) async {
      throw PlatformException(
        code: 'LLAMA_OS_UNSUPPORTED',
        message: 'Requires macOS 13.3',
      );
    });
    await expectLater(
      LlamaCppServerLaunch.resolve(
        platform: TargetPlatform.macOS,
        desktopExecutableName: 'llama-server.exe',
      ),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'LLAMA_OS_UNSUPPORTED',
        ),
      ),
    );
  });

  test(
    'an old Android APK explains that reinstalling the native runtime is needed',
    () async {
      await expectLater(
        LlamaCppServerLaunch.resolve(
          platform: TargetPlatform.android,
          desktopExecutableName: 'llama-server.exe',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Rebuild and reinstall'),
          ),
        ),
      );
    },
  );

  test(
    'Android reports native runtime errors instead of trying a Windows exe',
    () async {
      messenger.setMockMethodCallHandler(LlamaCppServerLaunch.channel, (
        _,
      ) async {
        throw PlatformException(
          code: 'LLAMA_RUNTIME_MISSING',
          message: 'Missing Android runtime',
        );
      });
      await expectLater(
        LlamaCppServerLaunch.resolve(
          platform: TargetPlatform.android,
          desktopExecutableName: 'llama-server.exe',
        ),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'LLAMA_RUNTIME_MISSING',
          ),
        ),
      );
    },
  );

  test('Android rejects an empty executable path', () async {
    messenger.setMockMethodCallHandler(
      LlamaCppServerLaunch.channel,
      (_) async => '',
    );
    await expectLater(
      LlamaCppServerLaunch.resolve(
        platform: TargetPlatform.android,
        desktopExecutableName: 'llama-server.exe',
      ),
      throwsStateError,
    );
  });
}
