/// Helper to manage application cache/temp directories under a single root
/// path called "cb_file_hub" across all platforms.
///
/// Usage:
///   final root = await AppPathHelper.getRootDir();
///   final videoDir = await AppPathHelper.getVideoCacheDir();
///
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPathHelper {
  // Cached root directory instance
  static Directory? _rootDirectory;

  // Cached persistent (non-temp) root directory instance
  static Directory? _persistentRootDirectory;

  /// Return the platform-appropriate base cache directory (temp/support).
  static Future<Directory> _getPlatformCacheBase() async {
    // For mobile platforms we prefer application cache directory to avoid
    // being cleared unexpectedly; fall back to temp if not available.
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // getTemporaryDirectory works fine for cache files and is wiped by the OS
        return await getTemporaryDirectory();
      }
    } catch (_) {
      // Ignore platform detection failures and fall through
    }

    // For desktop or if platform check failed, use system temp dir.
    return await getTemporaryDirectory();
  }

  /// Get/create the root directory: `<base>/cb_file_hub`
  static Future<Directory> getRootDir() async {
    if (_rootDirectory != null) return _rootDirectory!;

    final baseDir = await _getPlatformCacheBase();
    final rootPath = p.join(baseDir.path, 'cb_file_hub');
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    _rootDirectory = rootDir;
    // Store path string for quick synchronous access.
    _rootPath = _rootDirectory!.path;
    return rootDir;
  }

  // Cached root path (may be null until first call)
  static String? _rootPath;

  /// Synchronously return root directory path if already initialized, else null.
  static String? get rootPath => _rootPath;

  /// Get/create the persistent root directory: `<appDocuments>/cb_file_hub`.
  ///
  /// Unlike [getRootDir] (which lives under the OS temp/cache directory and may
  /// be wiped by the OS or a cleaner), this lives under the application
  /// documents directory so its contents survive across sessions. Use it for
  /// data that must not disappear, e.g. tag thumbnails the user has chosen.
  static Future<Directory> getPersistentRootDir() async {
    if (_persistentRootDirectory != null) return _persistentRootDirectory!;

    final baseDir = await getApplicationDocumentsDirectory();
    final rootPath = p.join(baseDir.path, 'cb_file_hub');
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    _persistentRootDirectory = rootDir;
    return rootDir;
  }

  /// Ensure and return a sub-folder inside the root directory.
  static Future<Directory> _subDir(String name) async {
    final root = await getRootDir();
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Ensure and return a sub-folder inside the persistent root directory.
  static Future<Directory> _persistentSubDir(String name) async {
    final root = await getPersistentRootDir();
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Directory for video thumbnails
  static Future<Directory> getVideoCacheDir() => _subDir('video_thumbnails');

  /// Directory for tag thumbnails (extracted from video frames, etc.).
  ///
  /// Stored under the persistent (documents) root rather than the temp/cache
  /// root, since a user-chosen tag thumbnail must survive OS cache cleanup.
  static Future<Directory> getTagThumbnailDir() =>
      _persistentSubDir('tag_thumbnails');

  /// Ensure and return a named sub-folder inside the root directory.
  static Future<Directory> getSubDir(String name) => _subDir(name);

  /// Directory for photo thumbnails
  static Future<Directory> getPhotoCacheDir() => _subDir('photo_thumbnails');

  /// Directory for network (SMB / FTP / WebDAV …) thumbnails
  static Future<Directory> getNetworkCacheDir() =>
      _subDir('network_thumbnails');

  /// Directory for temporary SMB files or other temp downloads
  static Future<Directory> getTempFilesDir() => _subDir('temp_files');
}
