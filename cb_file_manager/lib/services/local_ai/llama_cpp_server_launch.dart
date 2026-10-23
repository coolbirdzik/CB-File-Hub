import 'dart:io';

import 'package:flutter/services.dart';

/// Resolves installed code, never a downloaded binary in writable app storage.
class LlamaCppServerLaunch {
  static const channel = MethodChannel('cb_file_manager/local_ai');

  final String executablePath;
  final bool isAndroid;

  const LlamaCppServerLaunch({
    required this.executablePath,
    required this.isAndroid,
  });

  String get workingDirectory => File(executablePath).parent.path;

  Map<String, String>? get environment =>
      isAndroid ? {'LD_LIBRARY_PATH': workingDirectory} : null;

  List<String> arguments({
    required String modelPath,
    required int port,
    required int contextTokens,
    required int gpuLayers,
  }) => [
    '-m',
    modelPath,
    '--host',
    '127.0.0.1',
    '--port',
    '$port',
    '-c',
    '$contextTokens',
    '-ngl',
    isAndroid ? '0' : '$gpuLayers',
    '--no-ui',
    if (isAndroid) ...[
      // One chat slot and bounded scratch buffers on memory-limited devices.
      '--parallel', '1',
      '--batch-size', '128',
      '--ubatch-size', '128',
      '--cache-ram', '0',
    ],
  ];

  static Future<LlamaCppServerLaunch> resolve({
    required TargetPlatform platform,
    required String desktopExecutableName,
  }) async {
    if (platform == TargetPlatform.android ||
        platform == TargetPlatform.macOS) {
      final osName = platform == TargetPlatform.android ? 'Android' : 'macOS';
      String? path;
      try {
        path = await channel.invokeMethod<String>('getLlamaServerPath');
      } on MissingPluginException {
        throw StateError(
          '$osName local AI runtime is unavailable. Rebuild and reinstall '
          '${platform == TargetPlatform.android ? 'the APK' : 'the app'}.',
        );
      }
      if (path == null || path.isEmpty) {
        throw StateError(
          '$osName local AI runtime returned no executable path.',
        );
      }
      return LlamaCppServerLaunch(
        executablePath: path,
        isAndroid: platform == TargetPlatform.android,
      );
    }
    // Windows isolates llama's Vulkan loader from Flutter's app-root DLLs.
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    return LlamaCppServerLaunch(
      executablePath: '$exeDir${sep}llama$sep$desktopExecutableName',
      isAndroid: false,
    );
  }
}
