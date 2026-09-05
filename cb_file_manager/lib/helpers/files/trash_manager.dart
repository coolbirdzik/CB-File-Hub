import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';
import 'recycle_bin_reader.dart' as direct_reader;
import 'windows_file_operations.dart';

const int defaultPermanentDeleteConcurrency = 8;

/// A class that manages the trash bin functionality with platform-specific implementation
class TrashManager {
  static final TrashManager _instance = TrashManager._internal();

  factory TrashManager() => _instance;

  TrashManager._internal();

  /// The name of the internal trash directory (used when native trash is not available)
  static const String trashDirName = '.trash';

  /// The name of the metadata file that stores original paths
  static const String metadataFileName = '.trash_metadata.json';

  /// Get the internal trash directory
  Future<Directory> getTrashDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final trashPath = pathlib.join(appDocDir.path, trashDirName);
    final trashDir = Directory(trashPath);

    // Create the trash directory if it doesn't exist
    if (!await trashDir.exists()) {
      await trashDir.create(recursive: true);
    }

    return trashDir;
  }

  /// Get the metadata file
  Future<File> getMetadataFile() async {
    final trashDir = await getTrashDirectory();
    return File(pathlib.join(trashDir.path, metadataFileName));
  }

  /// Load metadata of trashed files
  Future<Map<String, String>> loadMetadata() async {
    try {
      final metadataFile = await getMetadataFile();

      // If the metadata file doesn't exist, create an empty one
      if (!await metadataFile.exists()) {
        await metadataFile.writeAsString(json.encode({}));
        return {};
      }

      // Read and parse the metadata file
      final String content = await metadataFile.readAsString();
      return Map<String, String>.from(json.decode(content));
    } catch (e) {
      debugPrint('Error loading trash metadata: $e');
      return {};
    }
  }

  /// Save metadata of trashed files
  Future<void> saveMetadata(Map<String, String> metadata) async {
    try {
      final metadataFile = await getMetadataFile();
      await metadataFile.writeAsString(json.encode(metadata));
    } catch (e) {
      debugPrint('Error saving trash metadata: $e');
    }
  }

  /// Get files from the Windows Recycle Bin
  /// Returns a list of SystemTrashItem objects representing files in the Windows Recycle Bin
  Future<List<SystemTrashItem>> getWindowsRecycleBinItems({
    int? offset,
    int? limit,
  }) async {
    if (!Platform.isWindows) {
      return [];
    }

    // Native first: ~10-50x faster than PowerShell because it avoids
    // process spawn, JSON serialization, and runs the COM enumeration
    // in-process on a worker thread.
    final native = await _getRecycleBinItemsNative(
      offset: offset ?? 0,
      limit: limit,
    );
    if (native != null) {
      return native.items;
    }
    return _getRecycleBinItemsPowerShell();
  }

  /// Returns the slice + the total bin size so callers can drive a paged
  /// load. Falls back to PowerShell (with a [total] inferred from the
  /// returned slice) when the native plugin is unavailable.
  Future<RecycleBinPage> getWindowsRecycleBinItemsPage({
    int offset = 0,
    int? limit,
  }) async {
    if (!Platform.isWindows) {
      return const RecycleBinPage(items: [], total: 0);
    }
    final native = await _getRecycleBinItemsNative(
      offset: offset,
      limit: limit,
    );
    if (native != null) {
      return native;
    }
    final fallback = await _getRecycleBinItemsPowerShell();
    return RecycleBinPage(items: fallback, total: fallback.length);
  }

  Future<RecycleBinPage?> _getRecycleBinItemsNative({
    int offset = 0,
    int? limit,
  }) async {
    try {
      final raw = await WindowsFileOperations.enumerateRecycleBin(
        offset: offset,
        limit: limit,
      );
      if (raw == null) return null;

      final items = <SystemTrashItem>[];
      for (final entry in raw.items) {
        final size = entry['size'];
        items.add(
          SystemTrashItem(
            name: (entry['name'] as String?) ?? 'Unknown',
            recycleBinPath: (entry['path'] as String?) ?? '',
            originalPath: (entry['originalPath'] as String?) ?? 'Unknown',
            size: size is int
                ? size
                : size is num
                ? size.toInt()
                : 0,
            trashedDate:
                _parseRecycleBinDate(entry['deletedDate'] as String?) ??
                DateTime.now(),
            isSystemItem: true,
            isFolder: entry['isFolder'] == true,
          ),
        );
      }
      return RecycleBinPage(items: items, total: raw.total);
    } catch (e, st) {
      AppLogger.warning(
        '[TrashManager] Native Recycle Bin enumeration failed: $e',
        stackTrace: st,
      );
      return null;
    }
  }

  DateTime? _parseRecycleBinDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();
    if (s.contains('/') || s.contains('-')) {
      return DateTime.tryParse(s);
    }
    return null;
  }

  Future<List<SystemTrashItem>> _getRecycleBinItemsPowerShell() async {
    List<SystemTrashItem> recycleBinItems = [];

    try {
      // PowerShell fallback for the legacy code path. The script caches
      // the "Original Location" and "Date deleted" property indices once
      // instead of scanning 500 properties per item, and uses
      // -NoLogo/-NoProfile/-NonInteractive to skip ~1-3s of profile load.
      final result = await Process.run('powershell.exe', [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'''
        $ErrorActionPreference = 'Stop'
        $shell = New-Object -ComObject Shell.Application
        $recycleBin = $shell.NameSpace(0xa)

        $origIdx = -1
        $dateIdx = -1
        for ($i = 0; $i -lt 500; $i++) {
            $propName = $recycleBin.GetDetailsOf($null, $i)
            if ($origIdx -lt 0 -and $propName -eq 'Original Location') {
                $origIdx = $i
            } elseif ($dateIdx -lt 0 -and $propName -eq 'Date deleted') {
                $dateIdx = $i
            }
            if ($origIdx -ge 0 -and $dateIdx -ge 0) { break }
        }

        $items = @()
        foreach ($item in $recycleBin.Items()) {
            $originalPath = ''
            if ($origIdx -ge 0) {
                $originalPath = $recycleBin.GetDetailsOf($item, $origIdx)
            }
            $deletedDate = ''
            if ($dateIdx -ge 0) {
                $deletedDate = $recycleBin.GetDetailsOf($item, $dateIdx)
            }

            $items += [PSCustomObject]@{
                Name         = $item.Name
                Path         = $item.Path
                Size         = $item.Size
                OriginalPath = $originalPath
                DeletedDate  = $deletedDate
                IsFolder     = $item.IsFolder
            }
        }

        ConvertTo-Json -InputObject $items -Compress
        ''',
      ]);

      if (result.exitCode != 0) {
        debugPrint('Error accessing Windows Recycle Bin: ${result.stderr}');
        return [];
      }

      // Parse the JSON output
      if (result.stdout.toString().trim().isNotEmpty) {
        final List<dynamic> items = json.decode(result.stdout.toString());

        for (var item in items) {
          DateTime? deletedDate;
          try {
            if (item['DeletedDate'] != null &&
                item['DeletedDate'].toString().isNotEmpty) {
              String dateStr = item['DeletedDate'].toString().trim();
              if (dateStr.contains('/') || dateStr.contains('-')) {
                deletedDate =
                    DateTime.tryParse(dateStr) ??
                    DateTime.now().subtract(const Duration(days: 1));
              } else {
                deletedDate = DateTime.now().subtract(const Duration(days: 1));
              }
            }
          } catch (e) {
            debugPrint('Error parsing deleted date: $e');
            deletedDate = DateTime.now().subtract(const Duration(days: 1));
          }

          int size = 0;
          try {
            if (item['Size'] != null) {
              String sizeStr = item['Size']
                  .toString()
                  .replaceAll(',', '')
                  .replaceAll(' KB', '000')
                  .replaceAll(' MB', '000000')
                  .replaceAll(' bytes', '');
              size = int.tryParse(sizeStr) ?? 0;
            }
          } catch (e) {
            debugPrint('Error parsing size: $e');
          }

          recycleBinItems.add(
            SystemTrashItem(
              name: item['Name'] ?? 'Unknown',
              recycleBinPath: item['Path'] ?? '',
              originalPath: item['OriginalPath'] ?? 'Unknown',
              size: size,
              trashedDate: deletedDate ?? DateTime.now(),
              isSystemItem: true,
              isFolder: item['IsFolder'] == true,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Exception when accessing Windows Recycle Bin: $e');
    }

    return recycleBinItems;
  }

  /// Open Windows Recycle Bin using the system explorer
  Future<bool> openWindowsRecycleBin() async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      final result = await Process.run('explorer.exe', [
        '::{645FF040-5081-101B-9F08-00AA002F954E}',
      ]);
      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error opening Windows Recycle Bin: $e');
      return false;
    }
  }

  /// Empty the Windows Recycle Bin
  Future<bool> emptyWindowsRecycleBin() async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      final result = await Process.run('powershell.exe', [
        '-Command',
        'Clear-RecycleBin -Force',
      ]);

      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error emptying Windows Recycle Bin: $e');
      return false;
    }
  }

  /// Restore a file from the Windows Recycle Bin
  Future<bool> restoreFromWindowsRecycleBin(String recycleBinPath) async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      // Use PowerShell to restore a specific file from the Recycle Bin
      final result = await Process.run('powershell.exe', [
        '-Command',
        '''
        \$shell = New-Object -ComObject Shell.Application
        \$recycleBin = \$shell.NameSpace(0xa)
        
        foreach (\$item in \$recycleBin.Items()) {
            if (\$item.Path -eq '$recycleBinPath') {
                \$item.InvokeVerb("Restore")
                Write-Output "Restored"
                exit 0
            }
        }
        
        Write-Error "Item not found in Recycle Bin"
        exit 1
        ''',
      ]);

      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error restoring from Windows Recycle Bin: $e');
      return false;
    }
  }

  /// Permanently delete a file from the Windows Recycle Bin
  Future<bool> deleteFromWindowsRecycleBin(String recycleBinPath) async {
    if (!Platform.isWindows) {
      return false;
    }

    try {
      final result = await Process.run('powershell.exe', [
        '-Command',
        '''
        \$shell = New-Object -ComObject Shell.Application
        \$recycleBin = \$shell.NameSpace(0xa)
        
        foreach (\$item in \$recycleBin.Items()) {
            if (\$item.Path -eq '$recycleBinPath') {
                Remove-Item -Path "\$(\$item.Path)" -Recurse -Force
                Write-Output "Deleted"
                exit 0
            }
        }
        
        Write-Error "Item not found in Recycle Bin"
        exit 1
        ''',
      ]);

      return result.exitCode == 0;
    } catch (e) {
      debugPrint('Error deleting from Windows Recycle Bin: $e');
      return false;
    }
  }

  /// Move a file to trash using platform-specific mechanisms when possible
  Future<bool> moveToTrash(String filePath) async {
    try {
      final file = File(filePath);
      final dir = Directory(filePath);
      final isDir = await dir.exists();

      if (!await file.exists() && !isDir) {
        debugPrint('File/Directory does not exist: $filePath');
        return false;
      }

      // Try to use platform-specific trash first
      if (await _moveToSystemTrash(filePath)) {
        return true; // Successfully moved to system trash/recycle bin
      }

      // Fallback to internal implementation
      return await _moveToInternalTrash(filePath);
    } catch (e) {
      debugPrint('Error moving file to trash: $e');
      return false;
    }
  }

  /// Move a file to the system's trash/recycle bin
  Future<bool> _moveToSystemTrash(String filePath) async {
    // Windows - Use PowerShell command to move to recycle bin
    if (Platform.isWindows) {
      try {
        final isDir = await Directory(filePath).exists();
        final method = isDir ? 'DeleteDirectory' : 'DeleteFile';
        final escapedPath = filePath.replaceAll("'", "''");

        // Use PowerShell's recycle bin functionality
        final result = await Process.run('powershell.exe', [
          '-Command',
          '''
          Add-Type -AssemblyName Microsoft.VisualBasic
          [Microsoft.VisualBasic.FileIO.FileSystem]::$method('$escapedPath', [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin, [Microsoft.VisualBasic.FileIO.UICancelOption]::ThrowException)
          ''',
        ]);

        if (result.exitCode == 0) {
          debugPrint('File/Folder moved to Windows Recycle Bin: $filePath');
          return true;
        } else {
          debugPrint('Error moving to Windows Recycle Bin: ${result.stderr}');
          return false;
        }
      } catch (e) {
        debugPrint('Exception when moving to Windows Recycle Bin: $e');
        return false;
      }
    }

    // macOS - Use AppleScript to move to Trash
    if (Platform.isMacOS) {
      try {
        final result = await Process.run('osascript', [
          '-e',
          'tell application "Finder" to delete POSIX file "$filePath"',
        ]);

        if (result.exitCode == 0) {
          debugPrint('File moved to macOS Trash: $filePath');
          return true;
        } else {
          debugPrint('Error moving to macOS Trash: ${result.stderr}');
          return false;
        }
      } catch (e) {
        debugPrint('Exception when moving to macOS Trash: $e');
        return false;
      }
    }

    // Linux - Use 'gio trash' command if available
    if (Platform.isLinux) {
      try {
        // Check if gio is available
        final checkGio = await Process.run('which', ['gio']);
        if (checkGio.exitCode == 0) {
          final result = await Process.run('gio', ['trash', filePath]);

          if (result.exitCode == 0) {
            debugPrint('File moved to Linux Trash using gio: $filePath');
            return true;
          } else {
            debugPrint('Error moving to Linux Trash: ${result.stderr}');
            return false;
          }
        }

        // Try trash-cli as an alternative
        final checkTrashCli = await Process.run('which', ['trash-put']);
        if (checkTrashCli.exitCode == 0) {
          final result = await Process.run('trash-put', [filePath]);

          if (result.exitCode == 0) {
            debugPrint('File moved to Linux Trash using trash-cli: $filePath');
            return true;
          } else {
            debugPrint('Error moving to Linux Trash: ${result.stderr}');
            return false;
          }
        }
      } catch (e) {
        debugPrint('Exception when moving to Linux Trash: $e');
        return false;
      }
    }

    // No native implementation available or failed
    return false;
  }

  /// Move a file or directory to our internal trash directory (fallback implementation)
  Future<bool> _moveToInternalTrash(String filePath) async {
    try {
      final trashDir = await getTrashDirectory();

      // Generate a unique name to avoid conflicts in trash
      final fileName = pathlib.basename(filePath);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final trashFileName = '${timestamp}_$fileName';
      final trashFilePath = pathlib.join(trashDir.path, trashFileName);

      final dir = Directory(filePath);
      if (await dir.exists()) {
        // Move directory: rename (same filesystem) or copy+delete
        try {
          await dir.rename(trashFilePath);
        } catch (_) {
          await _copyDirectory(dir, Directory(trashFilePath));
          await dir.delete(recursive: true);
        }
      } else {
        final file = File(filePath);
        // Move file to trash
        await file.copy(trashFilePath);
        await file.delete();
      }

      // Update metadata
      final metadata = await loadMetadata();
      metadata[trashFileName] = filePath;
      await saveMetadata(metadata);

      debugPrint('Item moved to internal trash: $filePath');
      return true;
    } catch (e) {
      debugPrint('Error moving item to internal trash: $e');
      return false;
    }
  }

  /// Recursively copy a directory and its contents.
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = pathlib.join(
        destination.path,
        pathlib.basename(entity.path),
      );
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  /// Move multiple files to trash.
  ///
  /// On Windows, this uses a single native `IFileOperation` batch call which
  /// is dramatically faster than the per-file PowerShell fallback. Returns
  /// the set of paths that were successfully moved to the Recycle Bin.
  ///
  /// The work is split into chunks of [chunkSize] so the caller can show
  /// progress via [onChunkDone] (called after each chunk with the number of
  /// items processed and the total).
  Future<Set<String>> moveMultipleToTrashBatched(
    List<String> filePaths, {
    int chunkSize = 200,
    void Function(String currentPath, int done, int total)? onChunkStart,
    void Function(int done, int total)? onChunkDone,
    Duration? timeoutOverride,
  }) async {
    if (filePaths.isEmpty) return <String>{};

    if (Platform.isWindows && WindowsFileOperations.isAvailable) {
      return _runDeleteBatch(
        filePaths,
        permanent: false,
        chunkSize: chunkSize,
        onChunkStart: onChunkStart,
        onChunkDone: onChunkDone,
        timeoutOverride: timeoutOverride,
      );
    }

    final succeeded = <String>{};
    int done = 0;
    for (final path in filePaths) {
      if (await moveToTrash(path)) {
        succeeded.add(path);
      }
      done++;
      onChunkDone?.call(done, filePaths.length);
    }
    return succeeded;
  }

  /// Permanently delete multiple files/folders directly with bounded
  /// concurrency.
  ///
  /// Permanent deletion does not need Recycle Bin or Shell integration.
  /// Direct filesystem calls avoid the COM startup cost and long Shell
  /// timeouts that made Shift+Delete feel slow, especially for one small file.
  /// Returns the set of paths that were successfully deleted.
  Future<Set<String>> deleteMultiplePermanently(
    List<String> filePaths, {
    int chunkSize = 200,
    void Function(String currentPath, int done, int total)? onChunkStart,
    void Function(int done, int total)? onChunkDone,
    void Function(String path, Object error)? onError,
    Duration? timeoutOverride,
  }) async {
    if (filePaths.isEmpty) return <String>{};

    final succeeded = <String>{};
    var nextIndex = 0;
    var done = 0;
    final concurrency = chunkSize
        .clamp(1, defaultPermanentDeleteConcurrency)
        .toInt();

    Future<void> worker() async {
      while (nextIndex < filePaths.length) {
        final index = nextIndex++;
        final path = filePaths[index];
        onChunkStart?.call(path, done, filePaths.length);

        try {
          final type = await FileSystemEntity.type(path, followLinks: false);
          switch (type) {
            case FileSystemEntityType.directory:
              await Directory(path).delete(recursive: true);
              break;
            case FileSystemEntityType.file:
              await File(path).delete();
              break;
            case FileSystemEntityType.link:
              await Link(path).delete();
              break;
            case FileSystemEntityType.notFound:
              // Deletion is idempotent. A path that disappeared between the
              // confirmation dialog and this worker is already deleted.
              break;
            default:
              throw FileSystemException(
                'Unsupported filesystem entity type',
                path,
              );
          }
          succeeded.add(path);
        } catch (e, st) {
          onError?.call(path, e);
          AppLogger.warning(
            '[TrashManager] Direct permanent delete failed: $path',
            error: e,
            stackTrace: st,
          );
        } finally {
          done++;
          onChunkDone?.call(done, filePaths.length);
        }
      }
    }

    await Future.wait(
      List.generate(
        concurrency.clamp(1, filePaths.length).toInt(),
        (_) => worker(),
      ),
    );
    return succeeded;
  }

  /// Retries an already-approved permanent deletion through Windows Shell
  /// with an explicit elevation request. No ownership or ACL changes are made.
  Future<Set<String>> retryPermanentDeleteAsAdministrator(
    List<String> failedPaths,
  ) async {
    if (!Platform.isWindows || failedPaths.isEmpty) return <String>{};

    final exactPaths = failedPaths.toSet().toList(growable: false);
    await WindowsFileOperations.deleteItems(
      sources: exactPaths,
      permanent: true,
      silent: true,
      requireElevation: true,
      timeout: const Duration(minutes: 2),
    );

    final succeeded = <String>{};
    for (final path in exactPaths) {
      if (_isPathGoneAfterDelete(path)) succeeded.add(path);
    }
    return succeeded;
  }

  /// Drives the Windows IFileOperation batch in chunks. Trusts the native
  /// return code: a successful batch marks every path in the chunk as
  /// succeeded; a failed batch is degraded to per-item native calls so a
  /// single bad path in the chunk does not lose the rest.
  Future<Set<String>> _runDeleteBatch(
    List<String> filePaths, {
    required bool permanent,
    required int chunkSize,
    void Function(String currentPath, int done, int total)? onChunkStart,
    void Function(int done, int total)? onChunkDone,
    Duration? timeoutOverride,
  }) async {
    final succeeded = <String>{};
    final total = filePaths.length;
    final size = chunkSize <= 0 ? total : chunkSize;
    final batchTimeout =
        timeoutOverride ??
        (permanent ? const Duration(seconds: 20) : const Duration(seconds: 2));
    final singleTimeout =
        timeoutOverride ??
        (permanent ? const Duration(seconds: 10) : const Duration(seconds: 1));

    for (int start = 0; start < total; start += size) {
      final end = (start + size < total) ? start + size : total;
      final chunk = filePaths.sublist(start, end);
      final action = permanent ? 'permanent delete' : 'move to Recycle Bin';
      final stopwatch = Stopwatch()..start();
      AppLogger.info(
        '[TrashManager] Starting native $action batch | range=${start + 1}-$end/$total | chunkSize=${chunk.length} | first=${chunk.first}'
        '${chunk.length > 1 ? ' | last=${chunk.last}' : ''}',
      );
      onChunkStart?.call(chunk.first, start, total);

      final ok = await WindowsFileOperations.deleteItems(
        sources: chunk,
        permanent: permanent,
        silent: true,
        timeout: batchTimeout,
      );
      stopwatch.stop();
      AppLogger.info(
        '[TrashManager] Finished native $action batch | range=${start + 1}-$end/$total | ok=$ok | elapsedMs=${stopwatch.elapsedMilliseconds} | first=${chunk.first}',
      );

      if (ok) {
        succeeded.addAll(chunk);
      } else {
        // Native IFileOperation can occasionally time out even though the path
        // has already disappeared from its original location. This applies to
        // both permanent delete and move-to-Recycle-Bin, because the original
        // path is gone in both success cases.
        final gone = chunk.where(_isPathGoneAfterDelete).toSet();
        if (gone.isNotEmpty) {
          succeeded.addAll(gone);
          AppLogger.warning(
            '[TrashManager] Native $action reported failure but ${gone.length}/${chunk.length} path(s) were already gone from the source location; treating them as success | first=${gone.first}',
          );
        }
        if (gone.length == chunk.length) {
          onChunkDone?.call(end, total);
          if (end < total) {
            await Future<void>.delayed(Duration.zero);
          }
          continue;
        }
      }

      if (!ok && chunk.length > 1 && permanent) {
        AppLogger.warning(
          '[TrashManager] Native $action batch failed; retrying per item | range=${start + 1}-$end/$total | first=${chunk.first}',
        );
        // Batch failed — degrade to per-item native call so a single bad
        // path does not lose the whole chunk.
        for (final p in chunk) {
          final singleStopwatch = Stopwatch()..start();
          AppLogger.info(
            '[TrashManager] Retrying native $action for single path: $p',
          );
          final single = await WindowsFileOperations.deleteItems(
            sources: [p],
            permanent: permanent,
            silent: true,
            timeout: singleTimeout,
          );
          singleStopwatch.stop();
          AppLogger.info(
            '[TrashManager] Finished single-path native $action | ok=$single | elapsedMs=${singleStopwatch.elapsedMilliseconds} | path=$p',
          );
          if (single || _isPathGoneAfterDelete(p)) {
            succeeded.add(p);
          }
        }
      } else if (!ok) {
        AppLogger.warning(
          '[TrashManager] Native $action failed | range=${start + 1}-$end/$total | first=${chunk.first}',
        );
      }

      onChunkDone?.call(end, total);

      // Yield back to the event loop between chunks so Flutter can repaint
      // progress indicators during long-running delete/trash operations.
      if (end < total) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return succeeded;
  }

  bool _isPathGoneAfterDelete(String path) {
    try {
      return FileSystemEntity.typeSync(path, followLinks: false) ==
          FileSystemEntityType.notFound;
    } catch (_) {
      // If the shell/native layer deleted the path while metadata/stat calls are
      // racing, err on the side of considering it gone rather than surfacing a
      // false delete failure.
      return true;
    }
  }

  /// Move multiple files to trash
  Future<int> moveMultipleToTrash(List<String> filePaths) async {
    final succeeded = await moveMultipleToTrashBatched(filePaths);
    return succeeded.length;
  }

  /// Restore a file from trash
  Future<bool> restoreFromTrash(String trashFileName) async {
    // For items in our internal trash
    try {
      final metadata = await loadMetadata();
      final originalPath = metadata[trashFileName];

      if (originalPath == null) {
        debugPrint('Original path not found for: $trashFileName');
        return false;
      }

      final trashDir = await getTrashDirectory();
      final trashFilePath = pathlib.join(trashDir.path, trashFileName);
      final trashFile = File(trashFilePath);
      final trashDirectory = Directory(trashFilePath);
      final bool isDir = await trashDirectory.exists();
      final bool isFile = await trashFile.exists();

      if (!isDir && !isFile) {
        debugPrint('Item not found in trash: $trashFileName');

        // Clean up metadata anyway
        metadata.remove(trashFileName);
        await saveMetadata(metadata);

        return false;
      }

      // Check if the destination directory exists
      final destDir = Directory(pathlib.dirname(originalPath));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }

      // Check if the original item already exists (avoid accidental overwrite)
      String targetPath = originalPath;

      if (isDir) {
        if (await Directory(originalPath).exists()) {
          final baseName = pathlib.basename(originalPath);
          final parentDir = pathlib.dirname(originalPath);
          targetPath = pathlib.join(parentDir, '$baseName (recovered)');
        }
        // Restore the directory
        try {
          await trashDirectory.rename(targetPath);
        } catch (_) {
          await _copyDirectory(trashDirectory, Directory(targetPath));
          await trashDirectory.delete(recursive: true);
        }
      } else {
        final originalFile = File(originalPath);
        if (await originalFile.exists()) {
          // Generate a new name with (recovered) suffix
          final extension = pathlib.extension(originalPath);
          final nameWithoutExtension = pathlib.basenameWithoutExtension(
            originalPath,
          );
          final directory = pathlib.dirname(originalPath);
          targetPath = pathlib.join(
            directory,
            '$nameWithoutExtension (recovered)$extension',
          );
        }
        // Restore the file
        await trashFile.copy(targetPath);
        await trashFile.delete();
      }

      // Update metadata
      metadata.remove(trashFileName);
      await saveMetadata(metadata);

      return true;
    } catch (e) {
      debugPrint('Error restoring file from trash: $e');
      return false;
    }
  }

  /// Permanently delete a file from trash
  Future<bool> deleteFromTrash(String trashFileName) async {
    // This could be a Windows Recycle Bin path or an internal trash item
    // Check if it looks like a Windows Recycle Bin path
    if (Platform.isWindows && trashFileName.contains(':\\')) {
      return deleteFromWindowsRecycleBin(trashFileName);
    }

    // Otherwise handle as internal trash item
    try {
      final trashDir = await getTrashDirectory();
      final trashFilePath = pathlib.join(trashDir.path, trashFileName);
      final trashFile = File(trashFilePath);
      final trashDirectory = Directory(trashFilePath);

      if (await trashDirectory.exists()) {
        await trashDirectory.delete(recursive: true);
      } else if (await trashFile.exists()) {
        await trashFile.delete();
      }

      // Update metadata
      final metadata = await loadMetadata();
      metadata.remove(trashFileName);
      await saveMetadata(metadata);

      return true;
    } catch (e) {
      debugPrint('Error deleting item from trash: $e');
      return false;
    }
  }

  /// Empty the trash (delete all files)
  Future<bool> emptyTrash() async {
    bool success = true;

    // Empty Windows Recycle Bin if on Windows
    if (Platform.isWindows) {
      bool winSuccess = await emptyWindowsRecycleBin();
      if (!winSuccess) {
        success = false;
        debugPrint('Failed to empty Windows Recycle Bin');
      }
    }

    // Also empty our internal trash
    try {
      final trashDir = await getTrashDirectory();

      // List all files in the trash directory
      final entities = await trashDir.list().toList();

      // Delete all files except the metadata file
      for (final entity in entities) {
        if (entity is File &&
            pathlib.basename(entity.path) != metadataFileName) {
          await entity.delete();
        }
      }

      // Reset metadata
      await saveMetadata({});
    } catch (e) {
      debugPrint('Error emptying internal trash: $e');
      success = false;
    }

    return success;
  }

  /// Get the list of files in trash with their metadata
  /// Combines both internal trash items and system trash items on Windows
  Future<List<TrashItem>> getTrashItems() async {
    // Run internal trash and Windows Recycle Bin queries in parallel
    final results = await Future.wait([
      _getInternalTrashItems(),
      if (Platform.isWindows)
        getWindowsRecycleBinItems()
      else
        Future.value(<SystemTrashItem>[]),
    ]);

    final List<TrashItem> allTrashItems = List.from(
      results[0] as List<TrashItem>,
    );

    // Convert SystemTrashItems to TrashItems
    if (Platform.isWindows) {
      final recycleBinItems = results[1] as List<SystemTrashItem>;
      for (final item in recycleBinItems) {
        allTrashItems.add(
          TrashItem(
            trashFileName: item.recycleBinPath,
            originalPath: item.originalPath,
            actualFilePath: item
                .recycleBinPath, // For system trash, use the recycle bin path
            size: item.size,
            trashedDate: item.trashedDate,
            isSystemTrashItem: true,
            displayName: item.name,
            isFolder: item.isFolder,
          ),
        );
      }
    }

    // Sort by date trashed (newest first)
    allTrashItems.sort((a, b) => b.trashedDate.compareTo(a.trashedDate));

    return allTrashItems;
  }

  /// Streamed variant of [getTrashItems] for the trash bin UI.
  ///
  /// Yields chunks as they become available so a screen with thousands of
  /// recycle-bin entries can render the first batch immediately and append
  /// the rest progressively.
  ///
  /// Order of emission is tuned for fastest first paint:
  ///  1. A tiny first page (default [firstPageSize] = 50) of the Windows
  ///     Recycle Bin — typically arrives in well under a second.
  ///  2. Internal-trash items in parallel — emitted as soon as their
  ///     stats finish.
  ///  3. The remaining Recycle Bin pages with [pageSize] entries each.
  Stream<List<TrashItem>> getTrashItemsStreaming({
    int firstPageSize = 50,
    int pageSize = 500,
  }) async* {
    final overall = Stopwatch()..start();
    AppLogger.info('[TrashManager] Stream start');
    // Kick off internal-trash collection in parallel; do NOT await it
    // before the first Recycle Bin page so we never let internal-trash
    // I/O delay first paint.
    final internalFuture = _getInternalTrashItems();

    if (Platform.isWindows) {
      // PRIMARY PATH: read $Recycle.Bin\<SID>\$I* files directly. This
      // bypasses the Shell.Application COM enumeration entirely, which
      // is what made the trash bin tab feel slow — `IShellDispatch.
      // Items()` materialises the full namespace before returning the
      // first entry, so paged COM calls cannot stream items as they
      // are read. Reading $I* files lets us yield each entry the
      // moment its 544-byte metadata is parsed.
      final t1 = Stopwatch()..start();
      final buffer = <SystemTrashItem>[];
      var emittedCount = 0;
      var directReadFailed = false;
      try {
        await for (final item in direct_reader.streamRecycleBinEntries()) {
          buffer.add(item);
          // Emit small chunks early, larger chunks once the screen has
          // rendered. The first chunk is intentionally tiny so the user
          // sees rows within ~50 ms; subsequent chunks are bigger to
          // amortise rebuild cost.
          final flushAt = emittedCount == 0
              ? firstPageSize
              : (emittedCount < firstPageSize * 8
                    ? firstPageSize * 2
                    : pageSize);
          if (buffer.length >= flushAt) {
            yield _convertSystemTrashItems(buffer);
            emittedCount += buffer.length;
            buffer.clear();
            // Give the event loop a tick so the UI can paint the new
            // rows between chunks.
            await Future<void>.delayed(Duration.zero);
          }
        }
      } catch (e, st) {
        AppLogger.warning(
          '[TrashManager] Direct \$Recycle.Bin reader failed, will fall back to COM: $e',
          stackTrace: st,
        );
        directReadFailed = true;
      }
      // Flush any remainder.
      if (buffer.isNotEmpty) {
        yield _convertSystemTrashItems(buffer);
        emittedCount += buffer.length;
        buffer.clear();
      }
      t1.stop();
      AppLogger.info(
        '[TrashManager] Stream direct reader finished | items=$emittedCount | elapsedMs=${t1.elapsedMilliseconds} | failed=$directReadFailed',
      );

      // Drain internal trash now (it has been running in parallel).
      final t2 = Stopwatch()..start();
      final internal = await internalFuture;
      t2.stop();
      AppLogger.info(
        '[TrashManager] Stream internal trash | items=${internal.length} | elapsedMs=${t2.elapsedMilliseconds}',
      );
      if (internal.isNotEmpty) {
        internal.sort((a, b) => b.trashedDate.compareTo(a.trashedDate));
        yield internal;
      }

      // Fallback: if the direct reader threw and produced nothing, fall
      // back to the legacy COM enumeration so the user is never left
      // looking at an empty bin when there is data they could see.
      if (directReadFailed && emittedCount == 0) {
        AppLogger.info(
          '[TrashManager] Falling back to COM enumeration after direct reader failure',
        );
        final fullPage = await getWindowsRecycleBinItemsPage(offset: 0);
        if (fullPage.items.isNotEmpty) {
          yield _convertSystemTrashItems(fullPage.items);
        }
      }

      overall.stop();
      AppLogger.info(
        '[TrashManager] Stream complete | totalElapsedMs=${overall.elapsedMilliseconds}',
      );
      return;
    }

    // Non-Windows: just emit internal trash when it is ready.
    final internal = await internalFuture;
    if (internal.isNotEmpty) {
      internal.sort((a, b) => b.trashedDate.compareTo(a.trashedDate));
      yield internal;
    }
    overall.stop();
    AppLogger.info(
      '[TrashManager] Stream complete (non-Windows) | totalElapsedMs=${overall.elapsedMilliseconds}',
    );
  }

  List<TrashItem> _convertSystemTrashItems(List<SystemTrashItem> items) {
    return [
      for (final item in items)
        TrashItem(
          trashFileName: item.recycleBinPath,
          originalPath: item.originalPath,
          actualFilePath: item.recycleBinPath,
          size: item.size,
          trashedDate: item.trashedDate,
          isSystemTrashItem: true,
          displayName: item.name,
          isFolder: item.isFolder,
        ),
    ];
  }

  /// Get items from internal trash directory with parallel stat operations
  Future<List<TrashItem>> _getInternalTrashItems() async {
    try {
      final trashDir = await getTrashDirectory();
      final metadata = await loadMetadata();

      // List all files in the trash directory
      final entities = await trashDir.list().toList();

      // Filter valid entities first
      final validEntities = entities.where((entity) {
        final fileName = pathlib.basename(entity.path);
        if (fileName == metadataFileName) return false;
        return entity is Directory || entity is File;
      }).toList();

      // Retrieve all file stats in parallel
      final statFutures = validEntities.map((entity) => entity.stat()).toList();
      final stats = await Future.wait(statFutures);

      // Build TrashItem list
      final List<TrashItem> items = [];
      for (int i = 0; i < validEntities.length; i++) {
        final entity = validEntities[i];
        final fileStat = stats[i];
        final fileName = pathlib.basename(entity.path);
        final originalPath = metadata[fileName] ?? 'Unknown';

        items.add(
          TrashItem(
            trashFileName: fileName,
            originalPath: originalPath,
            actualFilePath: entity.path, // The actual path in trash directory
            size: fileStat.size,
            trashedDate: DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(fileName.split('_').first) ?? 0,
            ),
            isSystemTrashItem: false,
            isFolder: entity is Directory,
          ),
        );
      }

      return items;
    } catch (e) {
      debugPrint('Error getting internal trash items: $e');
      return [];
    }
  }

  /// Check if trash is empty
  Future<bool> isTrashEmpty() async {
    final items = await getTrashItems();
    return items.isEmpty;
  }

  /// Get the total size of all files in trash
  Future<int> getTrashSize() async {
    final items = await getTrashItems();
    return items.fold<int>(0, (sum, item) => sum + item.size);
  }
}

/// A single page returned by [TrashManager.getWindowsRecycleBinItemsPage].
///
/// `items` is the slice (up to `limit` entries starting at the requested
/// offset). `total` is the **total** number of entries currently in the
/// Windows Recycle Bin, regardless of slice size, so callers can drive a
/// progressive load.
class RecycleBinPage {
  final List<SystemTrashItem> items;
  final int total;

  const RecycleBinPage({required this.items, required this.total});
}

/// Represents a file in the trash (either internal or system trash)
class TrashItem {
  final String
  trashFileName; // Identifier for the file (filename for internal, full path for system)
  final String originalPath;
  final String
  actualFilePath; // The actual path to the file in trash (for thumbnail generation)
  final int size;
  final DateTime trashedDate;
  final bool isSystemTrashItem; // Whether this item is from the system trash
  final String?
  displayName; // Optional display name, used for system trash items
  final bool isFolder; // Whether this item is a folder/directory

  TrashItem({
    required this.trashFileName,
    required this.originalPath,
    required this.actualFilePath,
    required this.size,
    required this.trashedDate,
    this.isSystemTrashItem = false,
    this.displayName,
    this.isFolder = false,
  });

  String get displayNameValue =>
      displayName ??
      (isSystemTrashItem
          ? pathlib.basename(trashFileName)
          : trashFileName.substring(trashFileName.indexOf('_') + 1));
}

/// Represents a file in the system trash/recycle bin
class SystemTrashItem {
  final String name;
  final String recycleBinPath; // Path in the recycle bin
  final String originalPath;
  final int size;
  final DateTime trashedDate;
  final bool isSystemItem;
  final bool isFolder; // Whether this item is a folder/directory

  SystemTrashItem({
    required this.name,
    required this.recycleBinPath,
    required this.originalPath,
    required this.size,
    required this.trashedDate,
    this.isSystemItem = true,
    this.isFolder = false,
  });
}
