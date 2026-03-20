import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';

/// Utility class for checking file types
/// Now delegates to FileTypeRegistry for all file type detection
///
/// Example usage for localized file type labels:
/// ```dart
/// // In a widget with BuildContext:
/// final label = FileTypeUtils.getFileTypeLabel(context, '.jpg');
/// // Returns "JPEG Image" in English or "Ảnh JPEG" in Vietnamese
/// ```
class FileTypeUtils {
  /// Check if a file is an image based on its extension
  static bool isImageFile(String filePath) {
    final extension = getFileExtension(filePath);
    return FileTypeRegistry.isCategory(extension, FileCategory.image);
  }

  /// Check if a file is a video based on its extension
  static bool isVideoFile(String filePath) {
    final extension = getFileExtension(filePath);
    return FileTypeRegistry.isCategory(extension, FileCategory.video);
  }

  /// Check if a file is an image or video (media file)
  static bool isMediaFile(String filePath) {
    return isImageFile(filePath) || isVideoFile(filePath);
  }

  /// Check if a file is an audio file
  static bool isAudioFile(String filePath) {
    final extension = getFileExtension(filePath);
    return FileTypeRegistry.isCategory(extension, FileCategory.audio);
  }

  /// Get the file extension from a path
  static String getFileExtension(String filePath) {
    final fileName = filePath.split('/').last.split('\\').last;
    final lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex == -1) return '';
    return fileName.substring(lastDotIndex).toLowerCase();
  }

  /// Get the file name without extension
  static String getFileNameWithoutExtension(String filePath) {
    final fileName = filePath.split('/').last.split('\\').last;
    final lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex == -1) return fileName;
    return fileName.substring(0, lastDotIndex);
  }

  /// Check if a file is a document
  static bool isDocumentFile(String filePath) {
    final extension = getFileExtension(filePath);
    return FileTypeRegistry.isCategory(extension, FileCategory.document) ||
        FileTypeRegistry.isCategory(extension, FileCategory.pdf);
  }

  /// Check if a file is a spreadsheet
  static bool isSpreadsheetFile(String filePath) {
    final extension = getFileExtension(filePath);
    return FileTypeRegistry.isCategory(extension, FileCategory.spreadsheet);
  }

  /// Check if a file is a presentation
  static bool isPresentationFile(String filePath) {
    final extension = getFileExtension(filePath);
    return FileTypeRegistry.isCategory(extension, FileCategory.presentation);
  }

  /// Check if a file is an archive/compressed file
  static bool isArchiveFile(String filePath) {
    final extension = getFileExtension(filePath);
    return FileTypeRegistry.isCategory(extension, FileCategory.archive);
  }

  /// Get the file type category
  static String getFileTypeCategory(String filePath) {
    final extension = getFileExtension(filePath);
    final category = FileTypeRegistry.getCategory(extension);

    switch (category) {
      case FileCategory.image:
        return 'image';
      case FileCategory.video:
        return 'video';
      case FileCategory.audio:
        return 'audio';
      case FileCategory.document:
      case FileCategory.pdf:
        return 'document';
      case FileCategory.spreadsheet:
        return 'spreadsheet';
      case FileCategory.presentation:
        return 'presentation';
      case FileCategory.archive:
        return 'archive';
      default:
        return 'other';
    }
  }

  /// Get human-readable file type label with i18n support
  /// Requires BuildContext to access localization
  /// Returns localized file type labels in English or Vietnamese
  static String getFileTypeLabel(
    BuildContext context,
    String extension,
  ) {
    if (extension.isEmpty) {
      return AppLocalizations.of(context)!.fileTypeGeneric;
    }

    // Remove the dot if present
    if (extension.startsWith('.')) {
      extension = extension.substring(1);
    }

    final upperExtension = extension.toUpperCase();
    final localizations = AppLocalizations.of(context)!;

    switch (upperExtension) {
      case 'JPG':
      case 'JPEG':
        return localizations.fileTypeJpeg;
      case 'PNG':
        return localizations.fileTypePng;
      case 'GIF':
        return localizations.fileTypeGif;
      case 'BMP':
        return localizations.fileTypeBmp;
      case 'TIFF':
        return localizations.fileTypeTiff;
      case 'WEBP':
        return localizations.fileTypeWebp;
      case 'SVG':
        return localizations.fileTypeSvg;
      case 'MP4':
        return localizations.fileTypeMp4;
      case 'AVI':
        return localizations.fileTypeAvi;
      case 'MOV':
        return localizations.fileTypeMov;
      case 'WMV':
        return localizations.fileTypeWmv;
      case 'FLV':
        return localizations.fileTypeFlv;
      case 'MKV':
        return localizations.fileTypeMkv;
      case 'MP3':
        return localizations.fileTypeMp3;
      case 'WAV':
        return localizations.fileTypeWav;
      case 'AAC':
        return localizations.fileTypeAac;
      case 'FLAC':
        return localizations.fileTypeFlac;
      case 'OGG':
        return localizations.fileTypeOgg;
      case 'PDF':
        return localizations.fileTypePdf;
      case 'DOCX':
      case 'DOC':
        return localizations.fileTypeWord;
      case 'XLSX':
      case 'XLS':
        return localizations.fileTypeExcel;
      case 'PPTX':
      case 'PPT':
        return localizations.fileTypePowerPoint;
      case 'TXT':
        return localizations.fileTypeTxt;
      case 'RTF':
        return localizations.fileTypeRtf;
      case 'ZIP':
        return localizations.fileTypeZip;
      case 'RAR':
        return localizations.fileTypeRar;
      case '7Z':
        return localizations.fileType7z;
      default:
        return localizations.fileTypeWithExtension(upperExtension);
    }
  }
}
