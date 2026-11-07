import 'dart:io';

import '../../app_insights/app_insights_models.dart';

/// Executables running when the snapshot was taken, to keep the caches of
/// open apps.
///
/// macOS gives full executable paths, matched against the app bundle. Linux
/// gives full paths too, but Electron apps start through a wrapper
/// (`/usr/bin/slack` runs `/usr/lib/slack/slack`) and Flatpak apps run
/// inside a sandbox, so file names and the Flatpak app id on the command
/// line also count. Windows gives image names only (`tasklist`), compared
/// with the app's known executables and the `.exe` files at the top of its
/// install folder. A failed snapshot is [unknown]: every app then counts as
/// running, so nothing that depends on an app being closed is offered.
class RunningProcesses {
  final String operatingSystem;

  /// Full paths (macOS, Linux) or lower-case image names (Windows).
  final List<String> executables;

  /// Linux command lines, NUL separators replaced by spaces.
  final List<String> commandLines;
  final bool unknown;

  const RunningProcesses({
    required this.operatingSystem,
    required this.executables,
    this.commandLines = const [],
    this.unknown = false,
  });

  const RunningProcesses.unknown(this.operatingSystem)
    : executables = const [],
      commandLines = const [],
      unknown = true;

  static RunningProcesses snapshot() {
    final os = Platform.operatingSystem;
    try {
      if (Platform.isMacOS) {
        final result = Process.runSync('ps', ['-axo', 'comm=']);
        if (result.exitCode != 0) return RunningProcesses.unknown(os);
        return RunningProcesses(
          operatingSystem: os,
          executables: [
            for (final line in '${result.stdout}'.split('\n'))
              if (line.trim().startsWith('/')) line.trim(),
          ],
        );
      }
      if (Platform.isLinux) {
        final executables = <String>[];
        final commandLines = <String>[];
        for (final entry in Directory('/proc').listSync(followLinks: false)) {
          final name = entry.path.substring(entry.path.lastIndexOf('/') + 1);
          if (int.tryParse(name) == null) continue;
          try {
            executables.add(Link('${entry.path}/exe').targetSync());
          } on FileSystemException {
            // Another user's process.
          }
          try {
            final bytes = File('${entry.path}/cmdline').readAsBytesSync();
            commandLines.add(
              String.fromCharCodes([for (final b in bytes) b == 0 ? 32 : b]),
            );
          } on FileSystemException {
            // Ended meanwhile.
          }
        }
        return RunningProcesses(
          operatingSystem: os,
          executables: executables,
          commandLines: commandLines,
        );
      }
      if (Platform.isWindows) {
        final result = Process.runSync('tasklist', ['/FO', 'CSV', '/NH']);
        if (result.exitCode != 0) return RunningProcesses.unknown(os);
        return RunningProcesses(
          operatingSystem: os,
          executables: [
            for (final line in '${result.stdout}'.split('\n'))
              if (line.startsWith('"'))
                line.substring(1, line.indexOf('"', 1)).toLowerCase(),
          ],
        );
      }
    } on Object {
      return RunningProcesses.unknown(os);
    }
    return RunningProcesses.unknown(os);
  }

  /// [installExecutables] are the `.exe` files at the top of the app's
  /// install folder (Windows), read by the caller.
  bool runs(
    InstalledAppInfo app, {
    Iterable<String> installExecutables = const [],
  }) {
    if (unknown) return true;
    if (operatingSystem == 'windows') {
      final names = {
        for (final path in [...app.executablePaths, ...installExecutables])
          _basename(path).toLowerCase(),
      };
      return executables.any(names.contains);
    }
    final bundle = app.installLocation;
    final prefix = bundle == null || bundle.isEmpty
        ? null
        : (bundle.endsWith('/') ? bundle : '$bundle/');
    final exact = app.executablePaths.toSet();
    if (executables.any(
      (exe) =>
          exact.contains(exe) || (prefix != null && exe.startsWith(prefix)),
    )) {
      return true;
    }
    if (operatingSystem != 'linux') return false;
    final names = {for (final path in exact) _basename(path)};
    if (executables.any((exe) => names.contains(_basename(exe)))) return true;
    // Flatpak: `bwrap ... --args ... org.example.App` and the app's own
    // processes carry the app id.
    final id = app.packageFamilyName;
    return id != null &&
        id.split('.').length >= 3 &&
        commandLines.any((line) => line.contains(id));
  }

  static String _basename(String path) =>
      path.substring(path.lastIndexOf(RegExp(r'[\\/]')) + 1);
}
