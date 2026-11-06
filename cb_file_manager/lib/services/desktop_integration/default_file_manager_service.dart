import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class FolderDefaultStatus {
  final bool available;
  final bool enabled;
  final bool canRestore;
  final bool partial;
  const FolderDefaultStatus({
    this.available = true,
    this.enabled = false,
    this.canRestore = false,
    this.partial = false,
  });
  factory FolderDefaultStatus.fromMap(Map<Object?, Object?> map) =>
      FolderDefaultStatus(
        available: map['available'] != false,
        enabled: map['enabled'] == true,
        canRestore: map['canRestore'] == true,
        partial: map['partial'] == true,
      );
}

/// Always queries the OS; no saved boolean can claim the app is the default.
class DefaultFileManagerService {
  DefaultFileManagerService({
    String? operatingSystem,
    Future<ProcessResult> Function(String, List<String>)? runProcess,
    Future<Directory> Function()? supportDirectory,
    Map<String, String>? environment,
    String? executable,
  }) : _os = operatingSystem ?? Platform.operatingSystem,
       _runProcess =
           runProcess ??
           ((command, arguments) => Process.run(command, arguments)),
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _environment = environment ?? Platform.environment,
       _executable = executable ?? Platform.resolvedExecutable;
  final String _os;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;
  final Future<Directory> Function() _supportDirectory;
  final Map<String, String> _environment;
  final String _executable;
  static final instance = DefaultFileManagerService();
  static const _windows = MethodChannel('cb_file_manager/app_icon');
  static const _macos = MethodChannel('cb_file_manager/macos_window');
  static const desktopId = 'com.cb.cbfilehub.desktop';
  bool get supported => _os == 'windows' || _os == 'macos' || _os == 'linux';

  Future<FolderDefaultStatus> status() async {
    if (_os == 'linux') {
      final backup = await _backupFile();
      return FolderDefaultStatus(
        enabled: await _linuxDefault() == desktopId,
        canRestore: await backup.exists(),
      );
    }
    if (!supported) return const FolderDefaultStatus();
    final map = await (_os == 'windows' ? _windows : _macos)
        .invokeMapMethod<Object?, Object?>('folderDefaultStatus');
    return FolderDefaultStatus.fromMap(map ?? {});
  }

  Future<void> enable() async {
    if (_os == 'linux') {
      await _withLinuxLock(_enableLinux);
    } else {
      await (_os == 'windows' ? _windows : _macos).invokeMethod<void>(
        'setFolderDefault',
      );
    }
    if (!(await status()).enabled) {
      throw StateError('The operating system did not select CB File Hub.');
    }
  }

  Future<void> restore() async {
    if (_os == 'linux') {
      await _withLinuxLock(_restoreLinux);
    } else {
      await (_os == 'windows' ? _windows : _macos).invokeMethod<void>(
        'restoreFolderDefault',
      );
    }
  }

  Future<void> _restoreLinux() async {
    final backup = await _backupFile();
    if (!await backup.exists()) return;
    final saved = jsonDecode(await backup.readAsString()) as Map;
    // Respect a choice made in another application after ours.
    if (await _linuxDefault() == desktopId) {
      final previous = saved['previous'] as String?;
      if (previous == null || previous.isEmpty || previous == desktopId) {
        throw StateError('The previous folder application is unavailable.');
      }
      await _xdg(['default', previous, 'inode/directory']);
      if (await _linuxDefault() != previous) {
        throw StateError(
          'The previous folder application could not be restored.',
        );
      }
    }
    await backup.delete();
  }

  Future<String> _xdg(List<String> arguments) async {
    final result = await _runProcess('xdg-mime', arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        'xdg-mime',
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    return '${result.stdout}'.trim();
  }

  Future<String> _linuxDefault() =>
      _xdg(['query', 'default', 'inode/directory']);

  Future<File> _backupFile() async => File(
    p.join((await _supportDirectory()).path, 'folder-default-backup.json'),
  );

  Future<void> _enableLinux() async {
    final previous = await _linuxDefault();
    if (previous == desktopId) return;
    final backup = await _backupFile();
    if (await backup.exists()) {
      throw StateError(
        'Restore the previous registration before enabling again.',
      );
    }
    if (previous.isEmpty) {
      throw StateError('No previous folder application was found to restore.');
    }
    final data = _environment['XDG_DATA_HOME'];
    final home = _environment['HOME'];
    if ((data == null || data.isEmpty) && (home == null || home.isEmpty)) {
      throw StateError('The user application directory is unavailable.');
    }
    final desktop = File(
      p.join(
        data == null || data.isEmpty ? p.join(home!, '.local', 'share') : data,
        'applications',
        desktopId,
      ),
    );
    final executable = _executable;
    // Desktop-entry quoting is not shell quoting; escape field-code percent too.
    final escaped = executable
        .replaceAll('\\', '\\\\\\\\')
        .replaceAll('"', r'\\"')
        .replaceAll('`', r'\\`')
        .replaceAll(r'$', r'\\$')
        .replaceAll('%', '%%');
    final tryExecutable = executable
        .replaceAll('\\', r'\\')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    await desktop.parent.create(recursive: true);
    await desktop.writeAsString(
      '[Desktop Entry]\nType=Application\nName=CB File Hub\n'
      'Exec="$escaped" %U\nTerminal=false\nMimeType=inode/directory;\n'
      'TryExec=$tryExecutable\n'
      'Categories=Utility;FileManager;\n',
    );
    if (!await backup.exists()) {
      await backup.parent.create(recursive: true);
      final temporary = File('${backup.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({'previous': previous}),
        flush: true,
      );
      await temporary.rename(backup.path);
    }
    try {
      await _xdg(['default', desktopId, 'inode/directory']);
    } catch (_) {
      if (await _linuxDefault() == desktopId) {
        await _xdg(['default', previous, 'inode/directory']);
      }
      rethrow;
    }
  }

  Future<void> _withLinuxLock(Future<void> Function() action) async {
    final backup = await _backupFile();
    await backup.parent.create(recursive: true);
    final lock = await File('${backup.path}.lock').open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
      await action();
    } finally {
      await lock.close();
    }
  }
}
