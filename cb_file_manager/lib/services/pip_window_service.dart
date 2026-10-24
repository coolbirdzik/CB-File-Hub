import 'dart:convert';
import 'dart:io';

import 'windowing/windows_engine_host.dart';

/// Simple PiP window launcher for desktop (Windows-focused).
/// Windows creates an engine in the existing host. Other desktop platforms
/// launch a process with the same PiP startup options.
class PipWindowService {
  static const _envFlag = 'CB_PIP_MODE';
  static const _envArgs = 'CB_PIP_ARGS';

  /// Returns true if the PiP window launch was accepted.
  static Future<bool> openDesktopPipWindow(Map<String, dynamic> args) async {
    try {
      if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
        return false;
      }

      final env = WindowsEngineHost.newWindowEnvironment();
      env[_envFlag] = '1';
      env[_envArgs] = jsonEncode(args);

      env['CB_SECONDARY_WINDOW'] = '1';
      env['CB_WINDOW_ROLE'] = 'pip';
      env.remove('CB_STARTUP_TABS');
      env.remove('CB_VIDEO_WINDOW');
      if (Platform.isWindows) return await WindowsEngineHost.open(env);

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
      if (Platform.isWindows) return false;
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
          environment: WindowsEngineHost.newWindowEnvironment()
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
