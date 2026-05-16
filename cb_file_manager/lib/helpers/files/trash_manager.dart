import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathlib;
import 'package:path_provider/path_provider.dart';

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
  Future<List<SystemTrashItem>> getWindowsRecycleBinItems() async {
    if (!Platform.isWindows) {
      return [];
    }

    List<SystemTrashItem> recycleBinItems = [];

    try {
      // Use PowerShell to access the Recycle Bin through COM objects
      final result = await Process.run('powershell.exe', [
        '-Command',
        '''
        \$shell = New-Object -ComObject Shell.Application
        \$recycleBin = \$shell.NameSpace(0xa) # 0xa is the Recycle Bin
        
        \$items = @()
        foreach (\$item in \$recycleBin.Items()) {
            \$name = \$item.Name
            \$path = \$item.Path
            \$size = \$item.Size
            
            # Get the original path from extended property
            \$originalPath = ""
            for (\$i = 0; \$i -lt 500; \$i++) {
                \$propName = \$recycleBin.GetDetailsOf(\$null, \$i)
                if (\$propName -eq "Original Location") {
                    \$originalPath = \$recycleBin.GetDetailsOf(\$item, \$i)
                    break
                }
            }
            
            # Get delete date from extended property
            \$deletedDate = ""
            for (\$i = 0; \$i -lt 500; \$i++) {
                \$propName = \$recycleBin.GetDetailsOf(\$null, \$i)
                if (\$propName -eq "Date deleted") {
                    \$deletedDate = \$recycleBin.GetDetailsOf(\$item, \$i)
                    break
                }
            }
            
            \$items += [PSCustomObject]@{
                Name = \$name
                Path = \$path
                Size = \$size
                OriginalPath = \$originalPath
                DeletedDate = \$deletedDate
                IsFolder = \$item.IsFolder
            }
        }
        
        ConvertTo-Json -InputObject \$items
        '''
      ]);

      if (result.exitCode != 0) {
        debugPrint('Error accessing Windows Recycle Bin: ${result.stderr}');
        return [];
      }

      // Parse the JSON output
      if (result.stdout.toString().trim().isNotEmpty) {
        final List<dynamic> items = json.decode(result.stdout.toString());

        for (var item in items) {
          // Convert PowerShell date format to DateTime
          DateTime? deletedDate;
          try {
            if (item['DeletedDate'] != null &&
                item['DeletedDate'].toString().isNotEmpty) {
              // PowerShell date format can vary, try common formats
              String dateStr = item['DeletedDate'].toString().trim();

              // Try to handle various date formats
              if (dateStr.contains('/') || dateStr.contains('-')) {
                deletedDate = DateTime.tryParse(dateStr) ??
                    DateTime.now()
                        .subtract(const Duration(days: 1)); // Fallback
              } else {
                // If no specific date found, use a default recent date
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
              // Try to parse the size
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

          recycleBinItems.add(SystemTrashItem(
              name: item['Name'] ?? 'Unknown',
              recycleBinPath: item['Path'] ?? '',
              originalPath: item['OriginalPath'] ?? 'Unknown',
              size: size,
              trashedDate: deletedDate ?? DateTime.now(),
              isSystemItem: true,
              isFolder: item['IsFolder'] == true));
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
      final result = await Process.run(
          'explorer.exe', ['::{645FF040-5081-101B-9F08-00AA002F954E}']);
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
      final result = await Process.run(
          'powershell.exe', ['-Command', 'Clear-RecycleBin -Force']);

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
        '''
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
        '''
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
          '''
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
          'tell application "Finder" to delete POSIX file "$filePath"'
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
      final newPath =
          pathlib.join(destination.path, pathlib.basename(entity.path));
      if (entity is File) {
        await entity.copy(newPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      }
    }
  }

  /// Move multiple files to trash
  Future<int> moveMultipleToTrash(List<String> filePaths) async {
    int successCount = 0;

    for (final path in filePaths) {
      if (await moveToTrash(path)) {
        successCount++;
      }
    }

    return successCount;
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
          final nameWithoutExtension =
              pathlib.basenameWithoutExtension(originalPath);
          final directory = pathlib.dirname(originalPath);
          targetPath = pathlib.join(
              directory, '$nameWithoutExtension (recovered)$extension');
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

    final List<TrashItem> allTrashItems =
        List.from(results[0] as List<TrashItem>);

    // Convert SystemTrashItems to TrashItems
    if (Platform.isWindows) {
      final recycleBinItems = results[1] as List<SystemTrashItem>;
      for (final item in recycleBinItems) {
        allTrashItems.add(TrashItem(
          trashFileName: item.recycleBinPath,
          originalPath: item.originalPath,
          actualFilePath:
              item.recycleBinPath, // For system trash, use the recycle bin path
          size: item.size,
          trashedDate: item.trashedDate,
          isSystemTrashItem: true,
          displayName: item.name,
          isFolder: item.isFolder,
        ));
      }
    }

    // Sort by date trashed (newest first)
    allTrashItems.sort((a, b) => b.trashedDate.compareTo(a.trashedDate));

    return allTrashItems;
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

        items.add(TrashItem(
          trashFileName: fileName,
          originalPath: originalPath,
          actualFilePath: entity.path, // The actual path in trash directory
          size: fileStat.size,
          trashedDate: DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(fileName.split('_').first) ?? 0),
          isSystemTrashItem: false,
          isFolder: entity is Directory,
        ));
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
