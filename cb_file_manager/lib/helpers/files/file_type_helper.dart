import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';

/// Legacy enum maintained for backward compatibility.
///
/// New code should use [FileCategory] from [FileTypeRegistry] instead.
enum FileType {
  image,
  video,
  audio,
  document,
  pdf,
  archive,
  code,
  spreadsheet,
  presentation,
  text,
  apk,
  unknown,
}

/// Helper class for file type operations.
///
/// This class is kept only as a thin adapter around [FileTypeRegistry] for
/// compatibility with existing call sites. New code should access
/// [FileTypeRegistry] directly.
class FileTypeHelper {
  // Check if the file is an image based on extension
  static bool isImage(String extension) {
    return FileTypeRegistry.isCategory(extension, FileCategory.image);
  }

  // Check if the file is a video based on extension
  static bool isVideo(String extension) {
    return FileTypeRegistry.isCategory(extension, FileCategory.video);
  }

  // Check if the file is an audio based on extension
  static bool isAudio(String extension) {
    return FileTypeRegistry.isCategory(extension, FileCategory.audio);
  }

  // Check if the file is a document based on extension
  static bool isDocument(String extension) {
    return FileTypeRegistry.isCategory(extension, FileCategory.document);
  }

  // Get file type based on extension
  static FileType getFileType(String extension) {
    if (extension.isEmpty) return FileType.unknown;

    // Delegate to registry
    final category = FileTypeRegistry.getCategory(extension);

    // Map FileCategory to legacy FileType enum
    return _mapCategoryToFileType(category);
  }

  // Get icon for file type (legacy method)
  static IconData getIconForFileType(FileType type) {
    // Convert FileType to FileCategory and use registry
    final category = _mapFileTypeToCategory(type);
    final exts = FileTypeRegistry.getExtensionsForCategory(category);
    return FileTypeRegistry.getIcon(exts.isEmpty ? '' : exts.first);
  }

  // Get color for file type (legacy method)
  static Color getColorForFileType(FileType type) {
    // Convert FileType to FileCategory and use registry
    final category = _mapFileTypeToCategory(type);
    final exts = FileTypeRegistry.getExtensionsForCategory(category);
    return FileTypeRegistry.getColor(exts.isEmpty ? '' : exts.first);
  }

  // Get icon directly from extension (preferred method)
  static IconData getIconForExtension(String extension) {
    return FileTypeRegistry.getIcon(extension);
  }

  // Get color directly from extension (preferred method)
  static Color getColorForExtension(String extension) {
    return FileTypeRegistry.getColor(extension);
  }

  // Map FileCategory to legacy FileType enum
  static FileType _mapCategoryToFileType(FileCategory category) {
    switch (category) {
      case FileCategory.image:
        return FileType.image;
      case FileCategory.video:
        return FileType.video;
      case FileCategory.audio:
        return FileType.audio;
      case FileCategory.document:
        return FileType.document;
      case FileCategory.pdf:
        return FileType.pdf;
      case FileCategory.archive:
        return FileType.archive;
      case FileCategory.code:
        return FileType.code;
      case FileCategory.spreadsheet:
        return FileType.spreadsheet;
      case FileCategory.presentation:
        return FileType.presentation;
      case FileCategory.text:
        return FileType.text;
      case FileCategory.apk:
        return FileType.apk;
      case FileCategory.unknown:
        return FileType.unknown;
    }
  }

  // Map legacy FileType enum to FileCategory
  static FileCategory _mapFileTypeToCategory(FileType type) {
    switch (type) {
      case FileType.image:
        return FileCategory.image;
      case FileType.video:
        return FileCategory.video;
      case FileType.audio:
        return FileCategory.audio;
      case FileType.document:
        return FileCategory.document;
      case FileType.pdf:
        return FileCategory.pdf;
      case FileType.archive:
        return FileCategory.archive;
      case FileType.code:
        return FileCategory.code;
      case FileType.spreadsheet:
        return FileCategory.spreadsheet;
      case FileType.presentation:
        return FileCategory.presentation;
      case FileType.text:
        return FileCategory.text;
      case FileType.apk:
        return FileCategory.apk;
      case FileType.unknown:
        return FileCategory.unknown;
    }
  }
}
