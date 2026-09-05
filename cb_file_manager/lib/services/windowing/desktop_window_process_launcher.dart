import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

class DesktopWindowProcessLauncher {
  static Future<bool> openWindow({
    List<WindowTabPayload> tabs = const <WindowTabPayload>[],
    int? activeIndex,
    bool startHidden = false,
    String windowRole = 'normal',
    double? initialPositionX,
    double? initialPositionY,
    bool startDragging = false,
  }) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return false;
    }

    try {
      final executable = Platform.resolvedExecutable;
      final workingDir = File(executable).parent.path;

      final env = Map<String, String>.from(Platform.environment);
      env[WindowStartupPayload.envSecondaryWindowKey] = '1';
      env[WindowStartupPayload.envStartHiddenKey] = startHidden ? '1' : '0';
      env[WindowStartupPayload.envWindowRoleKey] = windowRole;
      env[WindowStartupPayload.envStartDraggingKey] = startDragging ? '1' : '0';
      if (initialPositionX != null && initialPositionY != null) {
        env[WindowStartupPayload.envWindowPositionXKey] = '$initialPositionX';
        env[WindowStartupPayload.envWindowPositionYKey] = '$initialPositionY';
      }

      if (tabs.isNotEmpty) {
        final payload = <String, dynamic>{
          'tabs': tabs.map((t) => t.toJson()).toList(growable: false),
          'activeIndex': ?activeIndex,
        };
        env[WindowStartupPayload.envTabsKey] = jsonEncode(payload);
      }

      final lowerExecutable = executable.toLowerCase();
      final isDartRuntime =
          lowerExecutable.endsWith(r'\dart.exe') ||
          lowerExecutable.endsWith('/dart');
      final launchArgs = isDartRuntime
          ? Platform.executableArguments
                .where((a) {
                  final al = a.toLowerCase();
                  return !(al.startsWith('--vm-service') ||
                      al.startsWith('--observatory-port') ||
                      al.startsWith('--dds-port') ||
                      al.startsWith('--devtools-server-address'));
                })
                .toList(growable: false)
          : const <String>[];

      await Process.start(
        executable,
        launchArgs,
        environment: env,
        workingDirectory: workingDir,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e, st) {
      AppLogger.warning(
        'Failed to open a new window.',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Spawn một cửa sổ progress riêng biệt (role='progress').
  /// [ipcPort]: port của [ProgressWindowIpcServer] trong process cha.
  /// [title]: tiêu đề hiển thị trên progress window.
  /// [total]: tổng số items (0 = indeterminate).
  static Future<bool> openProgressWindow({
    required int ipcPort,
    required String title,
    required int total,
    bool isIndeterminate = false,
  }) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return false;
    }

    try {
      final executable = Platform.resolvedExecutable;
      final workingDir = File(executable).parent.path;

      final env = Map<String, String>.from(Platform.environment);
      env[WindowStartupPayload.envSecondaryWindowKey] = '1';
      env[WindowStartupPayload.envStartHiddenKey] = '0';
      env[WindowStartupPayload.envWindowRoleKey] = 'progress';
      env[WindowStartupPayload.envProgressIpcPortKey] = '$ipcPort';
      env[WindowStartupPayload.envProgressTitleKey] = title;
      env[WindowStartupPayload.envProgressTotalKey] = '$total';
      env[WindowStartupPayload.envProgressIndeterminateKey] = isIndeterminate
          ? '1'
          : '0';

      final lowerExecutable = executable.toLowerCase();
      final isDartRuntime =
          lowerExecutable.endsWith(r'\dart.exe') ||
          lowerExecutable.endsWith('/dart');
      final launchArgs = isDartRuntime
          ? Platform.executableArguments
                .where((a) {
                  final al = a.toLowerCase();
                  return !(al.startsWith('--vm-service') ||
                      al.startsWith('--observatory-port') ||
                      al.startsWith('--dds-port') ||
                      al.startsWith('--devtools-server-address'));
                })
                .toList(growable: false)
          : const <String>[];

      await Process.start(
        executable,
        launchArgs,
        environment: env,
        workingDirectory: workingDir,
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (e, st) {
      AppLogger.warning(
        'Failed to open progress window.',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }
}
