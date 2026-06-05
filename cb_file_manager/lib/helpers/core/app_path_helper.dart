/// Helper to manage application cache/temp directories under a single root
/// path called "cb_file_hub" across all platforms.
///
/// Usage:
///   final root = await AppPathHelper.getRootDir();
///   final videoDir = await AppPathHelper.getVideoCacheDir();
///
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPathHelper {
  // Cached root directory instance
  static Directory? _rootDirectory;

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

  /// Get/create the root directory: <base>/cb_file_hub
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

  /// Ensure and return a sub-folder inside the root directory.
  static Future<Directory> _subDir(String name) async {
    final root = await getRootDir();
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Directory for video thumbnails
  static Future<Directory> getVideoCacheDir() => _subDir('video_thumbnails');

  /// Directory for tag thumbnails (extracted from video frames, etc.)
  static Future<Directory> getTagThumbnailDir() => _subDir('tag_thumbnails');

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
