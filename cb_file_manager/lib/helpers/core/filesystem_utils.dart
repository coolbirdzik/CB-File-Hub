// dart
import 'dart:async';
import 'dart:io';
import 'dart:ffi';

// packages
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as pathlib;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart' as win32;
import 'package:ffi/ffi.dart';

// local files
import 'io_extensions.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';

String storageRootPath = "/storage/emulated/0/";

enum Sorting { type, size, date, alpha, typeDate, typeSize }

/// Return all **paths**
Future<List<Directory>> getStorageList() async {
  // Fix for null safety - handle nullable return value
  List<Directory> paths = await getExternalStorageDirectories() ?? [];
  List<Directory> filteredPaths = []; // Use list literal instead of constructor
  for (Directory dir in paths) {
    filteredPaths
        .add(await getExternalStorageWithoutDataDir(dir.absolute.path));
  }
  return filteredPaths;
}

/// This function aims to get path like: `/storage/emulated/0/`
/// not like `/storage/emulated/0/Android/data/package.name.example/files`
Future<Directory> getExternalStorageWithoutDataDir(
    String unfilteredPath) async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String subPath =
      pathlib.join("Android", "data", packageInfo.packageName, "files");
  if (unfilteredPath.contains(subPath)) {
    String filteredPath = unfilteredPath.split(subPath).first;
    return Directory(filteredPath);
  } else {
    return Directory(unfilteredPath);
  }
}

/// keepHidden: show files that start with .
Future<List<FileSystemEntity>> getFoldersAndFiles(String path,
    {changeCurrentPath = true,
    Sorting sortedBy = Sorting.type,
    reverse = false,
    recursive = false,
    keepHidden = false}) async {
  Directory dir = Directory(path);
  List<FileSystemEntity> files = [];
  try {
    files = await dir.list(recursive: recursive).toList();

    // Create a new list to avoid type issues
    List<FileSystemEntity> typedFiles = [];

    for (var fsEntity in files) {
      String fsPath = fsEntity.path.toString();
      if (FileSystemEntity.isDirectorySync(fsPath)) {
        typedFiles.add(Directory(fsEntity.absolute.path.toString()));
      } else {
        typedFiles.add(File(fsEntity.absolute.path.toString()));
      }
    }

    files = typedFiles;

    // Removing hidden files & folders from the list
    if (!keepHidden) {
      debugPrint("filesystem->getFoldersAndFiles: excluding hidden");
      files.removeWhere((FileSystemEntity test) {
        return test.basename().startsWith('.') == true;
      });
    }
  } on FileSystemException {
    return [];
  }
  return sort(files, sortedBy, reverse: reverse);
}

/// keepHidden: show files that start with .
Stream<List<FileSystemEntity>> fileStream(String path,
    {changeCurrentPath = true,
    Sorting sortedBy = Sorting.type,
    reverse = false,
    recursive = false,
    keepHidden = false}) async* {
  Directory path0 = Directory(path);
  List<FileSystemEntity> files = []; // Use list literal
  try {
    // Checking if the target directory contains files inside or not!
    // so that [StreamBuilder] won't emit the same old data if there are
    // no elements inside that directory.
    if (path0.listSync(recursive: recursive).isNotEmpty) {
      if (!keepHidden) {
        yield* path0.list(recursive: recursive).transform(
            StreamTransformer.fromHandlers(
                handleData: (FileSystemEntity data, sink) {
          debugPrint("filsytem_utils -> fileStream: $data");
          files.add(data);
          sink.add(files);
        }));
      } else {
        yield* path0.list(recursive: recursive).transform(
            StreamTransformer.fromHandlers(
                handleData: (FileSystemEntity data, sink) {
          debugPrint("filsytem_utils -> fileStream: $data");
          if (data.basename().startsWith('.')) {
            files.add(data);
            sink.add(files);
          }
        }));
      }
    } else {
      yield [];
    }
  } on FileSystemException {
    yield [];
  }
}

/// search for files and folder in current directory & sub-directories,
/// and return [File] or [Directory]
///
/// [path]: start point
///
/// [query]: regex or simple string
Future<List<FileSystemEntity>> search(String path, String query,
    {bool matchCase = false, recursive = true, bool hidden = false}) async {
  int start = DateTime.now().millisecondsSinceEpoch;

  List<FileSystemEntity> entities =
      await getFoldersAndFiles(path, recursive: recursive, keepHidden: hidden);

  // Cải thiện cách tìm kiếm để hoạt động tốt hơn với thư mục
  List<FileSystemEntity> results = entities.where((entity) {
    // Lấy tên của thực thể mà không bao gồm đường dẫn
    String name = pathlib.basename(entity.path).toLowerCase();
    String searchQuery = query.toLowerCase();

    // Kiểm tra nếu tên chứa truy vấn tìm kiếm
    bool matches = name.contains(searchQuery);

    // Log kết quả tìm kiếm để dễ debug
    if (matches) {
      debugPrint(
          "Found matching entity: ${entity.path}, type: ${entity is Directory ? 'Directory' : 'File'}");
    }

    return matches;
  }).toList();

  int end = DateTime.now().millisecondsSinceEpoch;
  debugPrint(
      "Search completed in ${end - start} ms, found ${results.length} items (${results.whereType<Directory>().length} directories)");

  return results;
}

/// search for files and folder in current directory & sub-directories,
/// and return [File] or [Directory]
///
/// `path`: start point
/// `query`: regex or simple string
Stream<List<FileSystemEntity>> searchStream(String path, String query,
    {bool matchCase = false, recursive = true, bool hidden = false}) async* {
  yield* fileStream(path, recursive: recursive)
      .transform(StreamTransformer.fromHandlers(handleData: (data, sink) {
    // Filtering
    data.retainWhere(
        (test) => test.basename().toLowerCase().contains(query.toLowerCase()));
    sink.add(data);
  }));
}

Future<int> getFreeSpace(String path) async {
  MethodChannel platform = const MethodChannel('samples.flutter.dev/battery');
  int freeSpace = await platform.invokeMethod("getFreeStorageSpace");
  return freeSpace;
}

/// Create folder by path
/// * i.e: `.createFolderByPath("/storage/emulated/0/", "folder name" )`
///
/// Supply path alone to create by already combined path, or path + filename
/// to be combined
Future<Directory> createFolderByPath(String path, {String? folderName}) async {
  debugPrint("filesystem_utils->createFolderByPath: $folderName @ $path");
  Directory directory;

  directory = Directory(pathlib.join(path, folderName ?? ''));

  try {
    if (!directory.existsSync()) {
      directory.create();
    } else {
      throw const FileSystemException("File already exists");
    }
    return directory;
  } catch (e) {
    throw FileSystemException(e.toString());
  }
}

/// This function returns every [Directory] in th path
List<Directory> splitPathToDirectories(String path) {
  List<Directory> splittedPath = []; // Use list literal
  Directory pathDir = Directory(path);
  splittedPath.add(pathDir);
  for (int i = 0; i < pathlib.split(path).length; i++) {
    splittedPath.add(pathDir.parent);
    pathDir = pathDir.parent;
  }
  return splittedPath.reversed.toList();
}

Future<List<FileSystemEntity>> sort(List<FileSystemEntity> elements, Sorting by,
    {bool reverse = false}) async {
  try {
    switch (by) {
      case Sorting.type:
        if (!reverse) {
          return elements
            ..sort((f1, f2) {
              bool isDir1 =
                  FileSystemEntity.isDirectorySync(f1.path.toString());
              bool isDir2 =
                  FileSystemEntity.isDirectorySync(f2.path.toString());
              return isDir1 == isDir2 ? 0 : (isDir1 ? -1 : 1);
            });
        } else {
          return (elements..sort()).reversed.toList();
        }
      default:
        return elements..sort();
    }
  } catch (e) {
    return [];
  }
}

/// Get all available drives on Windows systems
/// Returns a list of directories representing each drive
/// Now also detects drives that require admin privileges and includes drive labels
Future<List<Directory>> getAllWindowsDrives() async {
  if (!Platform.isWindows) {
    return [];
  }

  List<Directory> drives = [];

  // Check all possible drive letters from A to Z
  for (var i = 65; i <= 90; i++) {
    String driveLetter = String.fromCharCode(i);
    String drivePath = '$driveLetter:\\';

    try {
      Directory drive = Directory(drivePath);

      // First check if the drive exists
      if (await drive.exists()) {
        // Try to test if we can list files as a permission check
        try {
          // Just try to list one file to check permissions
          await drive
              .list(followLinks: false)
              .first
              .timeout(const Duration(milliseconds: 500), onTimeout: () {
            throw TimeoutException('Permission check timed out');
          });

          // If we reach here, we have access
          drives.add(drive);

          // Get drive label and store it in the directory metadata
          String driveLabel = await getDriveLabel(drivePath);
          drive.setProperty('driveLabel', driveLabel);

          debugPrint('Found accessible drive: $drivePath - Label: $driveLabel');
        } catch (permissionError) {
          // Drive exists but we don't have permission
          // Create a special metadata property to mark as protected
          drive = Directory(drivePath);
          drives.add(drive);
          // Add a "tag" to mark this as a protected drive
          drive.setProperty('requiresAdmin', true);

          // Get drive label when possible and store it
          try {
            String driveLabel = await getDriveLabel(drivePath);
            drive.setProperty('driveLabel', driveLabel);
            debugPrint(
                'Found protected drive: $drivePath - Label: $driveLabel (requires admin)');
          } catch (e) {
            debugPrint('Found protected drive: $drivePath (requires admin)');
          }
        }
      }
    } catch (e) {
      // Ignore drives that can't be accessed or don't exist
      debugPrint('Drive not found or cannot be accessed: $drivePath - $e');
    }
  }

  return drives;
}

/// Get the volume label for a Windows drive
Future<String> getDriveLabel(String drivePath) async {
  if (!Platform.isWindows) {
    return '';
  }

  try {
    // Make sure path ends with backslash
    final drive = drivePath.endsWith('\\') ? drivePath : '$drivePath\\';

    // Allocate memory for the buffers
    final volumeNameBuffer = calloc<Uint16>(win32.MAX_PATH + 1).cast<Utf16>();
    final fileSystemNameBuffer =
        calloc<Uint16>(win32.MAX_PATH + 1).cast<Utf16>();

    // Volume serial number
    final volumeSerialNumber = calloc<Uint32>(1);

    // Maximum component length
    final maximumComponentLength = calloc<Uint32>(1);

    // File system flags
    final fileSystemFlags = calloc<Uint32>(1);

    try {
      // Get volume information
      final result = win32.GetVolumeInformation(
        drive.toNativeUtf16(),
        volumeNameBuffer,
        win32.MAX_PATH + 1,
        volumeSerialNumber,
        maximumComponentLength,
        fileSystemFlags,
        fileSystemNameBuffer,
        win32.MAX_PATH + 1,
      );

      String label = '';
      if (result != 0) {
        // Convert the buffer to a Dart string
        label = volumeNameBuffer.toDartString();
      }

      return label;
    } finally {
      // Free allocated memory
      calloc.free(volumeNameBuffer.cast<Uint16>());
      calloc.free(fileSystemNameBuffer.cast<Uint16>());
      calloc.free(volumeSerialNumber);
      calloc.free(maximumComponentLength);
      calloc.free(fileSystemFlags);
    }
  } catch (e) {
    debugPrint('Error getting drive label: $e');
    return '';
  }
}

/// Get additional Android storage locations
/// This includes common paths like /storage/, /mnt/, /system/, /data/, etc.
Future<List<Directory>> getAdditionalAndroidPaths() async {
  if (!Platform.isAndroid) {
    return [];
  }

  final List<Directory> result = [];

  // Include primary internal storage if readable
  try {
    final primary = Directory('/storage/emulated/0');
    if (await primary.exists()) {
      await primary.list().first.timeout(const Duration(milliseconds: 500),
          onTimeout: () {
        throw TimeoutException('Access check timed out');
      });
      result.add(primary);
    }
  } catch (_) {}

  // Include removable/external storages with UUID-like folder names under /storage
  try {
    final Directory storageDir = Directory('/storage');
    if (await storageDir.exists()) {
      final entries = await storageDir.list().toList();
      final uuidPattern = RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$');
      for (final entry in entries) {
        if (entry is Directory) {
          final name = pathlib.basename(entry.path);
          if (name == 'emulated' || name == 'self' || name.isEmpty) {
            continue;
          }
          if (!uuidPattern.hasMatch(name)) {
            continue;
          }
          try {
            await entry.list().first.timeout(const Duration(milliseconds: 500),
                onTimeout: () {
              throw TimeoutException('Access check timed out');
            });
            result.add(entry);
          } catch (_) {}
        }
      }
    }
  } catch (e) {
    debugPrint('Error scanning /storage for external volumes: $e');
  }

  return result;
}

/// Get all available storage locations across platforms
/// On Windows: returns all available drives
/// On Android: returns external storage directories and other storage paths
/// On other platforms: returns the application documents directory
Future<List<Directory>> getAllStorageLocations() async {
  List<Directory> storageLocations = [];

  try {
    if (Platform.isWindows) {
      // Get all Windows drives
      storageLocations = await getAllWindowsDrives();
    } else if (Platform.isAndroid) {
      // First try the standard Android storage detection
      try {
        List<Directory> standardPaths = await getStorageList();
        storageLocations.addAll(standardPaths);
      } catch (e) {
        debugPrint('Error getting standard Android storage: $e');
      }

      // Try to add additional Android paths
      try {
        storageLocations.addAll(await getAdditionalAndroidPaths());
      } catch (e) {
        debugPrint('Error getting additional Android paths: $e');
      }
    } else {
      // For other platforms, fallback to application documents directory
      Directory appDocDir = await getApplicationDocumentsDirectory();
      storageLocations.add(appDocDir);
    }
  } catch (e) {
    debugPrint('Error getting storage locations: $e');
    // Fallback to app documents directory
    try {
      Directory appDocDir = await getApplicationDocumentsDirectory();
      storageLocations.add(appDocDir);
    } catch (e) {
      debugPrint('Error getting application documents directory: $e');
    }
  }

  // Remove duplicates using canonicalized paths to avoid aliases (/sdcard vs /storage/emulated/0)
  final uniquePaths = <String>{};
  storageLocations = storageLocations.where((dir) {
    String canonical = dir.path;
    try {
      canonical = Directory(canonical).resolveSymbolicLinksSync();
    } catch (_) {
      // ignore resolve errors
    }
    if (canonical.endsWith(Platform.pathSeparator) && canonical.length > 1) {
      canonical = canonical.substring(0, canonical.length - 1);
    }
    return uniquePaths.add(canonical);
  }).toList();

  return storageLocations;
}

/// Recursively get all videos in a directory and its subdirectories
/// If path is empty, scans common video directories (DCIM, Movies, Downloads)
Future<List<File>> getAllVideos(String path, {bool recursive = true}) async {
  // If path is empty, scan all common video directories
  if (path.isEmpty) {
    List<File> allVideos = [];
    final commonPaths = <String>[
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Movies',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Pictures', // Some videos might be here
    ];

    for (final dirPath in commonPaths) {
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final files = await getAllVideos(dirPath, recursive: true);
          allVideos.addAll(files);
        }
      } catch (e) {
        // Ignore errors for individual directories
        debugPrint('Error scanning $dirPath: $e');
      }
    }
    return allVideos;
  }

  // Normal path - scan the specified directory
  List<FileSystemEntity> allFiles =
      await getFoldersAndFiles(path, recursive: recursive);

  List<File> videoFiles = allFiles.whereType<File>().where((file) {
    return FileTypeUtils.isVideoFile(file.path);
  }).toList();

  return videoFiles;
}

/// Recursively get all images in a directory and its subdirectories
/// If path is empty, scans common image directories (DCIM, Pictures, Downloads)
Future<List<File>> getAllImages(String path, {bool recursive = true}) async {
  // If path is empty, scan all common image directories
  if (path.isEmpty) {
    List<File> allImages = [];
    final commonPaths = <String>[
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Screenshots', // Screenshots folder
    ];

    for (final dirPath in commonPaths) {
      try {
        final dir = Directory(dirPath);
        if (await dir.exists()) {
          final files = await getAllImages(dirPath, recursive: true);
          allImages.addAll(files);
        }
      } catch (e) {
        // Ignore errors for individual directories
        debugPrint('Error scanning $dirPath: $e');
      }
    }
    return allImages;
  }

  // Normal path - scan the specified directory
  List<FileSystemEntity> allFiles =
      await getFoldersAndFiles(path, recursive: recursive);

  List<File> imageFiles = allFiles.whereType<File>().where((file) {
    return FileTypeUtils.isImageFile(file.path);
  }).toList();

  return imageFiles;
}

/// Class to manage file operations like copy, cut, paste, rename
class FileOperations {
  // Singleton instance
  static final FileOperations _instance = FileOperations._internal();
  factory FileOperations() => _instance;
  FileOperations._internal();

  // Store the current clipboard items (for copy/cut operations)
  List<FileSystemEntity> _clipboardItems = [];
  bool _isCut = false; // Flag to determine if operation is cut or copy

  // Getter to check if clipboard has items
  bool get hasClipboardItem => _clipboardItems.isNotEmpty;

  // Getter to check if clipboard operation is cut
  bool get isClipboardItemCut => _isCut;

  // Alias for isClipboardItemCut for more intuitive API
  bool get isCutOperation => _isCut;

  // Getter for the number of items in clipboard
  int get clipboardItemCount => _clipboardItems.length;

  // Getter for the clipboard items
  List<FileSystemEntity> get clipboardItems =>
      List.unmodifiable(_clipboardItems);

  // Getter for single clipboard item (for backward compatibility)
  FileSystemEntity? get clipboardItem =>
      _clipboardItems.isNotEmpty ? _clipboardItems.first : null;

  // Set clipboard with file or folder
  void copyToClipboard(FileSystemEntity entity) {
    _clipboardItems = [entity];
    _isCut = false;
  }

  // Set clipboard with multiple files or folders
  void copyFilesToClipboard(List<FileSystemEntity> entities) {
    _clipboardItems = List.from(entities);
    _isCut = false;
  }

  // Set clipboard for cut operation
  void cutToClipboard(FileSystemEntity entity) {
    _clipboardItems = [entity];
    _isCut = true;
  }

  // Set clipboard for cut operation with multiple files
  void cutFilesToClipboard(List<FileSystemEntity> entities) {
    _clipboardItems = List.from(entities);
    _isCut = true;
  }

  // Clear clipboard after operation
  void clearClipboard() {
    _clipboardItems = [];
    _isCut = false;
  }

  // Paste files or folders from clipboard to destination using Windows native operations when available
  Future<List<FileSystemEntity>> pasteFromClipboard(
    String destinationPath, {
    void Function(int completed, int total)? onProgress,
  }) async {
    if (_clipboardItems.isEmpty) return [];

    // On Windows, try to use native file operations with progress dialog
    if (Platform.isWindows) {
      final nativeResult = await _pasteWithWindowsNative(destinationPath);
      if (nativeResult != null) {
        // Native operation was used (success or cancelled)
        if (_isCut && nativeResult) {
          clearClipboard();
        }
        // Return empty list since Windows handles the operation
        // The files are already copied/moved
        return [];
      }
      // Fall through to Dart implementation if native failed
    }

    return _pasteWithDart(destinationPath, onProgress: onProgress);
  }

  // Try Windows native paste operation
  Future<bool?> _pasteWithWindowsNative(String destinationPath) async {
    try {
      // Dynamic import to avoid issues on non-Windows platforms
      final sources = _clipboardItems.map((e) => e.path).toList();

      // Use process to call the native method channel
      const channel = MethodChannel('cb_file_manager/file_operations');
      final methodName = _isCut ? 'moveItems' : 'copyItems';

      final result = await channel.invokeMethod<bool>(
        methodName,
        {
          'sources': sources,
          'destination': destinationPath,
        },
      );

      return result;
    } catch (e) {
      debugPrint('Windows native file operation failed: $e');
      return null; // null means fallback to Dart implementation
    }
  }

  // Dart implementation of paste with progress callback
  // Dart implementation of paste with progress callback
  Future<List<FileSystemEntity>> _pasteWithDart(
    String destinationPath, {
    void Function(int completed, int total)? onProgress,
  }) async {
    List<FileSystemEntity> results = [];
    final total = _clipboardItems.length;
    int completed = 0;

    onProgress?.call(0, total);

    try {
      for (final item in _clipboardItems) {
        final filename = pathlib.basename(item.path);
        final newPath = pathlib.join(destinationPath, filename);

        // Check if destination already exists
        bool exists =
            await File(newPath).exists() || await Directory(newPath).exists();

        // Create a unique name if destination exists
        String uniquePath = newPath;
        if (exists) {
          int counter = 1;
          String extension = '';
          String baseName = filename;

          // Handle file extensions
          if (item is File) {
            extension = pathlib.extension(filename);
            baseName = pathlib.basenameWithoutExtension(filename);
          }

          // Find a unique name
          while (exists) {
            String newName = '${baseName}_$counter$extension';
            uniquePath = pathlib.join(destinationPath, newName);
            exists = await File(uniquePath).exists() ||
                await Directory(uniquePath).exists();
            counter++;
          }
        }

        // Perform the operation based on entity type and operation type
        FileSystemEntity? result;

        if (item is File) {
          final file = item;

          // Check if source file exists
          if (!await file.exists()) {
            debugPrint('Source file does not exist: ${file.path}');
            completed++;
            onProgress?.call(completed, total);
            continue;
          }

          if (_isCut) {
            // Move operation - try rename first (faster for same drive)
            try {
              result = await file.rename(uniquePath);
            } catch (e) {
              // rename() fails across different drives/filesystems
              // Fall back to copy + delete
              debugPrint('rename() failed, falling back to copy+delete: $e');
              result =
                  await File(uniquePath).writeAsBytes(await file.readAsBytes());
              await file.delete();
            }
          } else {
            // Copy operation
            result =
                await File(uniquePath).writeAsBytes(await file.readAsBytes());
          }
        } else if (item is Directory) {
          final directory = item;

          // Check if source directory exists
          if (!await directory.exists()) {
            debugPrint('Source directory does not exist: ${directory.path}');
            completed++;
            onProgress?.call(completed, total);
            continue;
          }

          final newDirectory = Directory(uniquePath);

          // Create the new directory
          await newDirectory.create(recursive: true);

          // Copy all contents recursively
          await for (final entity in directory.list(recursive: true)) {
            final relativePath =
                pathlib.relative(entity.path, from: directory.path);
            final newEntityPath = pathlib.join(newDirectory.path, relativePath);

            if (entity is File) {
              // Create parent directories if needed
              final newEntityParent = Directory(pathlib.dirname(newEntityPath));
              if (!await newEntityParent.exists()) {
                await newEntityParent.create(recursive: true);
              }

              // Copy the file
              await File(newEntityPath)
                  .writeAsBytes(await entity.readAsBytes());
            } else if (entity is Directory) {
              // Create directory
              await Directory(newEntityPath).create(recursive: true);
            }
          }

          result = newDirectory;

          // If cut operation, delete original directory
          if (_isCut) {
            try {
              await directory.delete(recursive: true);
            } catch (e) {
              debugPrint('Failed to delete original directory after move: $e');
            }
          }
        }

        if (result != null) {
          results.add(result);
        }

        // Update progress after each item
        completed++;
        onProgress?.call(completed, total);
      }

      // Clear clipboard if it was a cut operation
      if (_isCut) {
        clearClipboard();
      }

      return results;
    } catch (e) {
      debugPrint('Error during paste operation: $e');
      onProgress?.call(total, total); // Complete progress on error
      return results; // Return whatever was successfully pasted
    }
  }

  // Rename a file or folder
  Future<FileSystemEntity?> rename(
      FileSystemEntity entity, String newName) async {
    try {
      final directory = pathlib.dirname(entity.path);
      final newPath = pathlib.join(directory, newName);

      // Check if destination already exists
      bool exists =
          await File(newPath).exists() || await Directory(newPath).exists();

      if (exists) {
        throw const FileSystemException(
            'A file or folder with this name already exists');
      }

      // Perform rename operation
      return await entity.rename(newPath);
    } catch (e) {
      debugPrint('Error during rename operation: $e');
      return null;
    }
  }
}
