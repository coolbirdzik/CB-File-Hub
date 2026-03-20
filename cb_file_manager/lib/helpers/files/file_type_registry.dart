import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Enum representing different file categories
enum FileCategory {
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

/// Data class containing metadata for a file type
class FileTypeInfo {
  final FileCategory category;
  final IconData icon;
  final Color color;
  final String mimeType;
  final List<String> extensions;

  const FileTypeInfo({
    required this.category,
    required this.icon,
    required this.color,
    required this.mimeType,
    required this.extensions,
  });
}

/// Registry system for managing file type metadata
/// Provides a centralized, data-driven approach to file type handling
class FileTypeRegistry {
  // Private constructor to prevent instantiation
  FileTypeRegistry._();

  /// Complete registry of file types mapped by extension
  static final Map<String, FileTypeInfo> _registry = {
    // Image files
    '.jpg': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/jpeg',
      extensions: ['.jpg', '.jpeg'],
    ),
    '.jpeg': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/jpeg',
      extensions: ['.jpg', '.jpeg'],
    ),
    '.png': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/png',
      extensions: ['.png'],
    ),
    '.gif': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/gif',
      extensions: ['.gif'],
    ),
    '.bmp': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/bmp',
      extensions: ['.bmp'],
    ),
    '.webp': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/webp',
      extensions: ['.webp'],
    ),
    '.tiff': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/tiff',
      extensions: ['.tiff', '.tif'],
    ),
    '.tif': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/tiff',
      extensions: ['.tiff', '.tif'],
    ),
    '.svg': const FileTypeInfo(
      category: FileCategory.image,
      icon: PhosphorIconsLight.image,
      color: Colors.green,
      mimeType: 'image/svg+xml',
      extensions: ['.svg'],
    ),

    // Video files
    '.mp4': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/mp4',
      extensions: ['.mp4'],
    ),
    '.avi': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/x-msvideo',
      extensions: ['.avi'],
    ),
    '.mkv': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/x-matroska',
      extensions: ['.mkv'],
    ),
    '.mov': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/quicktime',
      extensions: ['.mov'],
    ),
    '.wmv': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/x-ms-wmv',
      extensions: ['.wmv'],
    ),
    '.flv': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/x-flv',
      extensions: ['.flv'],
    ),
    '.webm': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/webm',
      extensions: ['.webm'],
    ),
    '.m4v': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/x-m4v',
      extensions: ['.m4v'],
    ),
    '.3gp': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/3gpp',
      extensions: ['.3gp'],
    ),
    '.ogv': const FileTypeInfo(
      category: FileCategory.video,
      icon: PhosphorIconsLight.videoCamera,
      color: Colors.red,
      mimeType: 'video/ogg',
      extensions: ['.ogv'],
    ),

    // Audio files
    '.mp3': const FileTypeInfo(
      category: FileCategory.audio,
      icon: PhosphorIconsLight.musicNote,
      color: Colors.blue,
      mimeType: 'audio/mpeg',
      extensions: ['.mp3'],
    ),
    '.wav': const FileTypeInfo(
      category: FileCategory.audio,
      icon: PhosphorIconsLight.musicNote,
      color: Colors.blue,
      mimeType: 'audio/wav',
      extensions: ['.wav'],
    ),
    '.flac': const FileTypeInfo(
      category: FileCategory.audio,
      icon: PhosphorIconsLight.musicNote,
      color: Colors.blue,
      mimeType: 'audio/flac',
      extensions: ['.flac'],
    ),
    '.aac': const FileTypeInfo(
      category: FileCategory.audio,
      icon: PhosphorIconsLight.musicNote,
      color: Colors.blue,
      mimeType: 'audio/aac',
      extensions: ['.aac'],
    ),
    '.ogg': const FileTypeInfo(
      category: FileCategory.audio,
      icon: PhosphorIconsLight.musicNote,
      color: Colors.blue,
      mimeType: 'audio/ogg',
      extensions: ['.ogg'],
    ),
    '.wma': const FileTypeInfo(
      category: FileCategory.audio,
      icon: PhosphorIconsLight.musicNote,
      color: Colors.blue,
      mimeType: 'audio/x-ms-wma',
      extensions: ['.wma'],
    ),
    '.m4a': const FileTypeInfo(
      category: FileCategory.audio,
      icon: PhosphorIconsLight.musicNote,
      color: Colors.blue,
      mimeType: 'audio/mp4',
      extensions: ['.m4a'],
    ),

    // PDF
    '.pdf': FileTypeInfo(
      category: FileCategory.pdf,
      icon: PhosphorIconsLight.file,
      color: Colors.red.shade700,
      mimeType: 'application/pdf',
      extensions: const ['.pdf'],
    ),

    // Document files
    '.doc': const FileTypeInfo(
      category: FileCategory.document,
      icon: PhosphorIconsLight.fileText,
      color: Colors.indigo,
      mimeType: 'application/msword',
      extensions: ['.doc'],
    ),
    '.docx': const FileTypeInfo(
      category: FileCategory.document,
      icon: PhosphorIconsLight.fileText,
      color: Colors.indigo,
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      extensions: ['.docx'],
    ),
    '.rtf': const FileTypeInfo(
      category: FileCategory.document,
      icon: PhosphorIconsLight.fileText,
      color: Colors.indigo,
      mimeType: 'application/rtf',
      extensions: ['.rtf'],
    ),
    '.odt': const FileTypeInfo(
      category: FileCategory.document,
      icon: PhosphorIconsLight.fileText,
      color: Colors.indigo,
      mimeType: 'application/vnd.oasis.opendocument.text',
      extensions: ['.odt'],
    ),
    '.pages': const FileTypeInfo(
      category: FileCategory.document,
      icon: PhosphorIconsLight.fileText,
      color: Colors.indigo,
      mimeType: 'application/x-iwork-pages-sffpages',
      extensions: ['.pages'],
    ),

    // Spreadsheet files
    '.xls': FileTypeInfo(
      category: FileCategory.spreadsheet,
      icon: PhosphorIconsLight.squaresFour,
      color: Colors.green.shade700,
      mimeType: 'application/vnd.ms-excel',
      extensions: const ['.xls'],
    ),
    '.xlsx': FileTypeInfo(
      category: FileCategory.spreadsheet,
      icon: PhosphorIconsLight.squaresFour,
      color: Colors.green.shade700,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      extensions: const ['.xlsx'],
    ),
    '.csv': FileTypeInfo(
      category: FileCategory.spreadsheet,
      icon: PhosphorIconsLight.squaresFour,
      color: Colors.green.shade700,
      mimeType: 'text/csv',
      extensions: const ['.csv'],
    ),
    '.ods': FileTypeInfo(
      category: FileCategory.spreadsheet,
      icon: PhosphorIconsLight.squaresFour,
      color: Colors.green.shade700,
      mimeType: 'application/vnd.oasis.opendocument.spreadsheet',
      extensions: const ['.ods'],
    ),
    '.numbers': FileTypeInfo(
      category: FileCategory.spreadsheet,
      icon: PhosphorIconsLight.squaresFour,
      color: Colors.green.shade700,
      mimeType: 'application/x-iwork-numbers-sffnumbers',
      extensions: const ['.numbers'],
    ),

    // Presentation files
    '.ppt': const FileTypeInfo(
      category: FileCategory.presentation,
      icon: PhosphorIconsLight.desktop,
      color: Colors.orange,
      mimeType: 'application/vnd.ms-powerpoint',
      extensions: ['.ppt'],
    ),
    '.pptx': const FileTypeInfo(
      category: FileCategory.presentation,
      icon: PhosphorIconsLight.desktop,
      color: Colors.orange,
      mimeType:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      extensions: ['.pptx'],
    ),
    '.odp': const FileTypeInfo(
      category: FileCategory.presentation,
      icon: PhosphorIconsLight.desktop,
      color: Colors.orange,
      mimeType: 'application/vnd.oasis.opendocument.presentation',
      extensions: ['.odp'],
    ),
    '.key': const FileTypeInfo(
      category: FileCategory.presentation,
      icon: PhosphorIconsLight.desktop,
      color: Colors.orange,
      mimeType: 'application/x-iwork-keynote-sffkey',
      extensions: ['.key'],
    ),

    // Archive files
    '.zip': FileTypeInfo(
      category: FileCategory.archive,
      icon: PhosphorIconsLight.archive,
      color: Colors.amber.shade700,
      mimeType: 'application/zip',
      extensions: const ['.zip'],
    ),
    '.rar': FileTypeInfo(
      category: FileCategory.archive,
      icon: PhosphorIconsLight.archive,
      color: Colors.amber.shade700,
      mimeType: 'application/x-rar-compressed',
      extensions: const ['.rar'],
    ),
    '.7z': FileTypeInfo(
      category: FileCategory.archive,
      icon: PhosphorIconsLight.archive,
      color: Colors.amber.shade700,
      mimeType: 'application/x-7z-compressed',
      extensions: const ['.7z'],
    ),
    '.tar': FileTypeInfo(
      category: FileCategory.archive,
      icon: PhosphorIconsLight.archive,
      color: Colors.amber.shade700,
      mimeType: 'application/x-tar',
      extensions: const ['.tar'],
    ),
    '.gz': FileTypeInfo(
      category: FileCategory.archive,
      icon: PhosphorIconsLight.archive,
      color: Colors.amber.shade700,
      mimeType: 'application/gzip',
      extensions: const ['.gz'],
    ),
    '.bz2': FileTypeInfo(
      category: FileCategory.archive,
      icon: PhosphorIconsLight.archive,
      color: Colors.amber.shade700,
      mimeType: 'application/x-bzip2',
      extensions: const ['.bz2'],
    ),

    // Text files
    '.txt': const FileTypeInfo(
      category: FileCategory.text,
      icon: PhosphorIconsLight.fileText,
      color: Colors.blueGrey,
      mimeType: 'text/plain',
      extensions: ['.txt'],
    ),
    '.md': const FileTypeInfo(
      category: FileCategory.text,
      icon: PhosphorIconsLight.fileText,
      color: Colors.blueGrey,
      mimeType: 'text/markdown',
      extensions: ['.md'],
    ),
    '.json': const FileTypeInfo(
      category: FileCategory.text,
      icon: PhosphorIconsLight.fileText,
      color: Colors.blueGrey,
      mimeType: 'application/json',
      extensions: ['.json'],
    ),
    '.xml': const FileTypeInfo(
      category: FileCategory.text,
      icon: PhosphorIconsLight.fileText,
      color: Colors.blueGrey,
      mimeType: 'application/xml',
      extensions: ['.xml'],
    ),

    // Code files
    '.js': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/javascript',
      extensions: ['.js'],
    ),
    '.html': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/html',
      extensions: ['.html'],
    ),
    '.css': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/css',
      extensions: ['.css'],
    ),
    '.py': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-python',
      extensions: ['.py'],
    ),
    '.java': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-java-source',
      extensions: ['.java'],
    ),
    '.c': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-c',
      extensions: ['.c'],
    ),
    '.cpp': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-c++',
      extensions: ['.cpp'],
    ),
    '.h': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-c',
      extensions: ['.h'],
    ),
    '.cs': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-csharp',
      extensions: ['.cs'],
    ),
    '.php': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-php',
      extensions: ['.php'],
    ),
    '.rb': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-ruby',
      extensions: ['.rb'],
    ),
    '.dart': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'application/dart',
      extensions: ['.dart'],
    ),
    '.swift': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-swift',
      extensions: ['.swift'],
    ),
    '.kt': const FileTypeInfo(
      category: FileCategory.code,
      icon: PhosphorIconsLight.code,
      color: Colors.teal,
      mimeType: 'text/x-kotlin',
      extensions: ['.kt'],
    ),

    // APK
    '.apk': const FileTypeInfo(
      category: FileCategory.apk,
      icon: PhosphorIconsLight.deviceMobile,
      color: Colors.green,
      mimeType: 'application/vnd.android.package-archive',
      extensions: ['.apk'],
    ),

    // Other executable/package formats (categorized as unknown)
    '.aab': const FileTypeInfo(
      category: FileCategory.unknown,
      icon: PhosphorIconsLight.file,
      color: Colors.grey,
      mimeType: 'application/octet-stream',
      extensions: ['.aab'],
    ),
    '.ipa': const FileTypeInfo(
      category: FileCategory.unknown,
      icon: PhosphorIconsLight.file,
      color: Colors.grey,
      mimeType: 'application/octet-stream',
      extensions: ['.ipa'],
    ),
    '.exe': const FileTypeInfo(
      category: FileCategory.unknown,
      icon: PhosphorIconsLight.file,
      color: Colors.grey,
      mimeType: 'application/x-msdownload',
      extensions: ['.exe'],
    ),
    '.msi': const FileTypeInfo(
      category: FileCategory.unknown,
      icon: PhosphorIconsLight.file,
      color: Colors.grey,
      mimeType: 'application/x-msi',
      extensions: ['.msi'],
    ),
    '.deb': const FileTypeInfo(
      category: FileCategory.unknown,
      icon: PhosphorIconsLight.file,
      color: Colors.grey,
      mimeType: 'application/x-debian-package',
      extensions: ['.deb'],
    ),
    '.rpm': const FileTypeInfo(
      category: FileCategory.unknown,
      icon: PhosphorIconsLight.file,
      color: Colors.grey,
      mimeType: 'application/x-rpm',
      extensions: ['.rpm'],
    ),
    '.dmg': const FileTypeInfo(
      category: FileCategory.unknown,
      icon: PhosphorIconsLight.file,
      color: Colors.grey,
      mimeType: 'application/x-apple-diskimage',
      extensions: ['.dmg'],
    ),
  };

  /// Get complete file type information for an extension
  /// Returns null if extension is not found in registry
  static FileTypeInfo? getInfo(String extension) {
    if (extension.isEmpty) return null;
    final normalizedExt = _normalizeExtension(extension);
    return _registry[normalizedExt];
  }

  /// Get the file category for an extension
  /// Returns FileCategory.unknown if extension is not found
  static FileCategory getCategory(String extension) {
    final info = getInfo(extension);
    return info?.category ?? FileCategory.unknown;
  }

  /// Get the icon for an extension
  /// Returns default file icon if extension is not found
  static IconData getIcon(String extension) {
    final info = getInfo(extension);
    return info?.icon ?? PhosphorIconsLight.file;
  }

  /// Get the color for an extension
  /// Returns grey if extension is not found
  static Color getColor(String extension) {
    final info = getInfo(extension);
    return info?.color ?? Colors.grey;
  }

  /// Get the MIME type for an extension
  /// Returns 'application/octet-stream' if extension is not found
  static String getMimeType(String extension) {
    final info = getInfo(extension);
    return info?.mimeType ?? 'application/octet-stream';
  }

  /// Check if an extension belongs to a specific category
  static bool isCategory(String extension, FileCategory category) {
    return getCategory(extension) == category;
  }

  /// Normalize extension to lowercase with leading dot
  static String _normalizeExtension(String extension) {
    final ext = extension.toLowerCase().trim();
    return ext.startsWith('.') ? ext : '.$ext';
  }

  /// Get all registered extensions
  static List<String> getAllExtensions() {
    return _registry.keys.toList();
  }

  /// Get all extensions for a specific category
  static List<String> getExtensionsForCategory(FileCategory category) {
    return _registry.entries
        .where((entry) => entry.value.category == category)
        .map((entry) => entry.key)
        .toList();
  }
}
