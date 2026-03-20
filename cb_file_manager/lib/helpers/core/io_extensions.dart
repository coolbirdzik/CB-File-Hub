/*
 This code is used to extend dart:io library, 
 to add extra functionality to avoid repeating code
*/

// dart
import 'dart:io';

// packages
import 'package:path/path.dart' as path;

/// Extension methods for File objects
extension FileExtension on File {
  /// Get the file extension without the dot (.)
  String extension() {
    return path.extension(this.path).replaceAll('.', '');
  }

  /// Get the basename of the file (filename with extension)
  String basename() {
    return path.basename(this.path);
  }

  /// Get the filename without extension
  String basenameWithoutExtension() {
    return path.basenameWithoutExtension(this.path);
  }

  /// Get the parent directory path
  String parent() {
    return path.dirname(this.path);
  }

  /// Get the file size in a human-readable format
  Future<String> readableSize() async {
    try {
      final stat = await this.stat();
      final size = stat.size;

      if (size < 1024) {
        return '$size B';
      } else if (size < 1024 * 1024) {
        return '${(size / 1024).toStringAsFixed(1)} KB';
      } else if (size < 1024 * 1024 * 1024) {
        return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
      } else {
        return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
      }
    } catch (e) {
      return 'Unknown size';
    }
  }
}

/// Extension methods for Directory objects
extension DirectoryExtension on Directory {
  /// Get the basename of the directory (last part of the path)
  String basename() {
    return path.basename(this.path);
  }

  /// Get the parent directory path
  String parent() {
    return path.dirname(this.path);
  }

  /// Count files in the directory (non-recursive)
  Future<int> fileCount() async {
    try {
      final files = await list().where((entity) => entity is File).toList();
      return files.length;
    } catch (e) {
      return 0;
    }
  }

  /// Count all entities (files and directories) in the directory (non-recursive)
  Future<int> entityCount() async {
    try {
      final entities = await list().toList();
      return entities.length;
    } catch (e) {
      return 0;
    }
  }
}

/// Extension methods for FileSystemEntity objects
extension FileSystemEntityExtension on FileSystemEntity {
  /// Get the basename of the entity (last part of the path)
  String basename() {
    return this.path.split(Platform.isWindows ? r'\' : '/').last;
  }

  /// Check if the entity is a directory
  Future<bool> isDirectory() async {
    return await FileSystemEntity.isDirectory(this.path);
  }

  /// Check if the entity is a file
  Future<bool> isFile() async {
    return await FileSystemEntity.isFile(this.path);
  }
}

/// Extension method to store and retrieve properties on Directory objects
extension DirectoryProperties on Directory {
  // A static map to store properties for directories - using path as a key
  static final Map<String, Map<String, dynamic>> _properties = {};

  // Set a property on a directory
  void setProperty(String key, dynamic value) {
    if (!_properties.containsKey(this.path)) {
      _properties[this.path] = {};
    }
    _properties[this.path]![key] = value;
  }

  // Get a property from a directory
  dynamic getProperty(String key, {dynamic defaultValue}) {
    if (_properties.containsKey(this.path) &&
        _properties[this.path]!.containsKey(key)) {
      return _properties[this.path]![key];
    }
    return defaultValue;
  }

  // Check if a directory requires admin privileges
  bool get requiresAdmin => getProperty('requiresAdmin', defaultValue: false);
}
