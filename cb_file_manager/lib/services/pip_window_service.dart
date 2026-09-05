import 'dart:convert';
import 'dart:io';

/// Simple PiP window launcher for desktop (Windows-focused).
/// Spawns a new process of the app with environment variables
/// used by main.dart to boot into a small PiP window.
class PipWindowService {
  static const _envFlag = 'CB_PIP_MODE';
  static const _envArgs = 'CB_PIP_ARGS';

  /// Launch a PiP window as a separate process on Windows.
  /// Returns true if the process was started successfully.
  static Future<bool> openDesktopPipWindow(Map<String, dynamic> args) async {
    try {
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
        return false;
      }

      final env = Map<String, String>.from(Platform.environment);
      env[_envFlag] = '1';
      env[_envArgs] = jsonEncode(args);

      // Resolve current runner executable and use its directory as CWD.
      // Forward only safe args (filter out debug service flags that can collide).
      final executable = Platform.resolvedExecutable;
      final workingDir = File(executable).parent.path;
      final filteredArgs = Platform.executableArguments
          .where((a) {
            final al = a.toLowerCase();
            return !(al.startsWith('--vm-service') ||
                al.startsWith('--observatory-port') ||
                al.startsWith('--dds-port') ||
                al.startsWith('--devtools-server-address'));
          })
          .toList(growable: false);

      await Process.start(
        executable,
        filteredArgs,
        environment: env,
        workingDirectory: workingDir,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      // As a fallback, try again with current executable arguments but
      // filter out common debug flags that can cause port collisions.
      try {
        final executable = Platform.resolvedExecutable;
        final workingDir = File(executable).parent.path;
        final filteredArgs = Platform.executableArguments
            .where((a) {
              final al = a.toLowerCase();
              return !(al.startsWith('--vm-service') ||
                  al.startsWith('--observatory-port') ||
                  al.startsWith('--dds-port') ||
                  al.startsWith('--devtools-server-address'));
            })
            .toList(growable: false);
        await Process.start(
          executable,
          filteredArgs,
          environment: Map<String, String>.from(Platform.environment)
            ..[_envFlag] = '1'
            ..[_envArgs] = jsonEncode(args),
          workingDirectory: workingDir,
          mode: ProcessStartMode.detached,
        );
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}
