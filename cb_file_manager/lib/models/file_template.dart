import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Brand identifiers for file templates
enum FileTemplateBrand { generic, microsoft, libre, wps, google }

/// Category for organizing file templates
enum FileTemplateCategory {
  document,
  spreadsheet,
  presentation,
  image,
  video,
  audio,
  archive,
  code,
  text,
  pdf,
  other,
}

/// Represents a file template with its metadata
class FileTemplate {
  final String extension;
  final String mimeType;
  final FileTemplateCategory category;
  final String displayNameKey; // localization key
  final FileTemplateBrand brand;
  final IconData icon;
  final List<String> brandKeywords; // Used for brand detection
  final String? defaultFileName; // Default name (without extension)

  const FileTemplate({
    required this.extension,
    required this.mimeType,
    required this.category,
    required this.displayNameKey,
    required this.brand,
    required this.icon,
    this.brandKeywords = const [],
    this.defaultFileName,
  });

  String get brandLabel {
    switch (brand) {
      case FileTemplateBrand.microsoft:
        return 'Microsoft';
      case FileTemplateBrand.libre:
        return 'LibreOffice';
      case FileTemplateBrand.wps:
        return 'WPS Office';
      case FileTemplateBrand.google:
        return 'Google';
      case FileTemplateBrand.generic:
        return '';
    }
  }

  bool get hasBrandBadge => brand != FileTemplateBrand.generic;
}

/// All available file templates
final List<FileTemplate> allFileTemplates = [
  // ── Generic / Always available ─────────────────────────────────────────────
  _generic(
    'txt',
    'text/plain',
    FileTemplateCategory.text,
    'fileTypeTxt',
    PhosphorIconsLight.fileText,
  ),
  _generic(
    'rtf',
    'application/rtf',
    FileTemplateCategory.document,
    'fileTypeRtf',
    PhosphorIconsLight.fileText,
  ),
  _generic(
    'md',
    'text/markdown',
    FileTemplateCategory.text,
    'fileTypeMarkdown',
    PhosphorIconsLight.fileCode,
  ),
  _generic(
    'json',
    'application/json',
    FileTemplateCategory.code,
    'fileTypeJson',
    PhosphorIconsLight.bracketsCurly,
  ),
  _generic(
    'html',
    'text/html',
    FileTemplateCategory.code,
    'fileTypeHtml',
    PhosphorIconsLight.code,
  ),
  _generic(
    'css',
    'text/css',
    FileTemplateCategory.code,
    'fileTypeCss',
    PhosphorIconsLight.paintBrush,
  ),
  _generic(
    'dart',
    'application/dart',
    FileTemplateCategory.code,
    'fileTypeDart',
    PhosphorIconsLight.code,
  ),
  _generic(
    'py',
    'text/x-python',
    FileTemplateCategory.code,
    'fileTypePython',
    PhosphorIconsLight.fileCode,
  ),
  _generic(
    'js',
    'application/javascript',
    FileTemplateCategory.code,
    'fileTypeJavaScript',
    PhosphorIconsLight.code,
  ),
  _generic(
    'ts',
    'text/typescript',
    FileTemplateCategory.code,
    'fileTypeTypeScript',
    PhosphorIconsLight.code,
  ),
  _generic(
    'java',
    'text/x-java',
    FileTemplateCategory.code,
    'fileTypeJava',
    PhosphorIconsLight.code,
  ),
  _generic(
    'cpp',
    'text/x-c++src',
    FileTemplateCategory.code,
    'fileTypeCpp',
    PhosphorIconsLight.code,
  ),
  _generic(
    'c',
    'text/x-csrc',
    FileTemplateCategory.code,
    'fileTypeC',
    PhosphorIconsLight.code,
  ),
  _generic(
    'go',
    'text/x-go',
    FileTemplateCategory.code,
    'fileTypeGo',
    PhosphorIconsLight.code,
  ),
  _generic(
    'rs',
    'text/x-rust',
    FileTemplateCategory.code,
    'fileTypeRust',
    PhosphorIconsLight.code,
  ),
  _generic(
    'xml',
    'application/xml',
    FileTemplateCategory.code,
    'fileTypeXml',
    PhosphorIconsLight.code,
  ),
  _generic(
    'yaml',
    'text/yaml',
    FileTemplateCategory.code,
    'fileTypeYaml',
    PhosphorIconsLight.code,
  ),
  _generic(
    'sh',
    'application/x-sh',
    FileTemplateCategory.code,
    'fileTypeShell',
    PhosphorIconsLight.terminal,
  ),
  _generic(
    'csv',
    'text/csv',
    FileTemplateCategory.spreadsheet,
    'fileTypeCsv',
    PhosphorIconsLight.table,
  ),
  _generic(
    'png',
    'image/png',
    FileTemplateCategory.image,
    'fileTypePng',
    PhosphorIconsLight.image,
  ),
  _generic(
    'bmp',
    'image/bmp',
    FileTemplateCategory.image,
    'fileTypeBmp',
    PhosphorIconsLight.image,
  ),
  _generic(
    'jpg',
    'image/jpeg',
    FileTemplateCategory.image,
    'fileTypeJpeg',
    PhosphorIconsLight.image,
  ),
  _generic(
    'gif',
    'image/gif',
    FileTemplateCategory.image,
    'fileTypeGif',
    PhosphorIconsLight.image,
  ),
  _generic(
    'svg',
    'image/svg+xml',
    FileTemplateCategory.image,
    'fileTypeSvg',
    PhosphorIconsLight.image,
  ),
  _generic(
    'mp3',
    'audio/mpeg',
    FileTemplateCategory.audio,
    'fileTypeMp3',
    PhosphorIconsLight.musicNote,
  ),
  _generic(
    'wav',
    'audio/wav',
    FileTemplateCategory.audio,
    'fileTypeWav',
    PhosphorIconsLight.musicNote,
  ),
  _generic(
    'ogg',
    'audio/ogg',
    FileTemplateCategory.audio,
    'fileTypeOgg',
    PhosphorIconsLight.musicNote,
  ),
  _generic(
    'mp4',
    'video/mp4',
    FileTemplateCategory.video,
    'fileTypeMp4',
    PhosphorIconsLight.videoCamera,
  ),
  _generic(
    'avi',
    'video/x-msvideo',
    FileTemplateCategory.video,
    'fileTypeAvi',
    PhosphorIconsLight.videoCamera,
  ),
  _generic(
    'mkv',
    'video/x-matroska',
    FileTemplateCategory.video,
    'fileTypeMkv',
    PhosphorIconsLight.videoCamera,
  ),
  _generic(
    'mov',
    'video/quicktime',
    FileTemplateCategory.video,
    'fileTypeMov',
    PhosphorIconsLight.videoCamera,
  ),
  _generic(
    'zip',
    'application/zip',
    FileTemplateCategory.archive,
    'fileTypeZip',
    PhosphorIconsLight.fileZip,
  ),
  _generic(
    'rar',
    'application/x-rar-compressed',
    FileTemplateCategory.archive,
    'fileTypeRar',
    PhosphorIconsLight.fileZip,
  ),
  _generic(
    '7z',
    'application/x-7z-compressed',
    FileTemplateCategory.archive,
    'fileType7z',
    PhosphorIconsLight.fileZip,
  ),
  _generic(
    'tar',
    'application/x-tar',
    FileTemplateCategory.archive,
    'fileTypeTar',
    PhosphorIconsLight.fileZip,
  ),
  _generic(
    'gz',
    'application/gzip',
    FileTemplateCategory.archive,
    'fileTypeGzip',
    PhosphorIconsLight.fileZip,
  ),

  // ── PDF ────────────────────────────────────────────────────────────────────
  _generic(
    'pdf',
    'application/pdf',
    FileTemplateCategory.pdf,
    'fileTypePdf',
    PhosphorIconsLight.filePdf,
  ),

  // ── Microsoft Office (brand-specific) ──────────────────────────────────────
  _ms(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'Word Document',
    'fileTypeWord',
  ),
  _ms(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'Excel Spreadsheet',
    'fileTypeExcel',
  ),
  _ms(
    'pptx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'PowerPoint Presentation',
    'fileTypePowerPoint',
  ),
  _ms('doc', 'application/msword', 'Word Document (Legacy)', 'fileTypeWord'),
  _ms(
    'xls',
    'application/vnd.ms-excel',
    'Excel Spreadsheet (Legacy)',
    'fileTypeExcel',
  ),
  _ms(
    'ppt',
    'application/vnd.ms-powerpoint',
    'PowerPoint (Legacy)',
    'fileTypePowerPoint',
  ),

  // ── LibreOffice (brand-specific) ───────────────────────────────────────────
  _libre('odt', 'application/vnd.oasis.opendocument.text', 'ODT Document'),
  _libre(
    'ods',
    'application/vnd.oasis.opendocument.spreadsheet',
    'ODS Spreadsheet',
  ),
  _libre(
    'odp',
    'application/vnd.oasis.opendocument.presentation',
    'ODP Presentation',
  ),
  _libre('odg', 'application/vnd.oasis.opendocument.graphics', 'ODG Drawing'),
  _libre('odc', 'application/vnd.oasis.opendocument.chart', 'ODC Chart'),
  _libre('odf', 'application/vnd.oasis.opendocument.formula', 'ODF Formula'),

  // ── WPS Office (brand-specific) ─────────────────────────────────────────────
  _wps('wps', 'application/vnd.ms-works', 'WPS Document'),
  _wps('et', 'application/vnd.ms-excel', 'ET Spreadsheet'),
  _wps('dps', 'application/vnd.ms-powerpoint', 'DPS Presentation'),

  // ── Google Docs/Sheets (brand-specific) ─────────────────────────────────────
  _google('gdoc', 'application/vnd.google-apps.document', 'Google Doc'),
  _google('gsheet', 'application/vnd.google-apps.spreadsheet', 'Google Sheet'),
  _google(
    'gslides',
    'application/vnd.google-apps.presentation',
    'Google Slides',
  ),
];

// Helper factories
FileTemplate _generic(
  String ext,
  String mimeType,
  FileTemplateCategory category,
  String displayNameKey,
  IconData icon, {
  String? defaultName,
}) {
  return FileTemplate(
    extension: '.$ext',
    mimeType: mimeType,
    category: category,
    displayNameKey: displayNameKey,
    brand: FileTemplateBrand.generic,
    icon: icon,
    defaultFileName: defaultName ?? ext.toUpperCase(),
  );
}

FileTemplate _ms(
  String ext,
  String mimeType,
  String displayName,
  String displayNameKey,
) {
  return FileTemplate(
    extension: '.$ext',
    mimeType: mimeType,
    category: _msCategory(ext),
    displayNameKey: displayNameKey,
    brand: FileTemplateBrand.microsoft,
    icon: _msIcon(ext),
    brandKeywords: _msKeywords(ext),
  );
}

FileTemplate _libre(String ext, String mimeType, String displayName) {
  return FileTemplate(
    extension: '.$ext',
    mimeType: mimeType,
    category: _libreCategory(ext),
    displayNameKey: _libreKey(ext),
    brand: FileTemplateBrand.libre,
    icon: _libreIcon(ext),
    brandKeywords: const ['libreoffice', 'soffice'],
  );
}

String _libreKey(String ext) {
  switch (ext) {
    case 'odt':
      return 'fileTypeLibreDoc';
    case 'ods':
      return 'fileTypeLibreSheet';
    case 'odp':
      return 'fileTypeLibrePresentation';
    case 'odg':
      return 'fileTypeLibreDraw';
    case 'odc':
      return 'fileTypeLibreChart';
    case 'odf':
      return 'fileTypeLibreFormula';
    default:
      return 'fileTypeLibreDoc';
  }
}

FileTemplate _wps(String ext, String mimeType, String displayName) {
  return FileTemplate(
    extension: '.$ext',
    mimeType: mimeType,
    category: _wpsCategory(ext),
    displayNameKey: _wpsKey(ext),
    brand: FileTemplateBrand.wps,
    icon: _wpsIcon(ext),
    brandKeywords: const ['wps', 'wpsoffice', 'kingsoft'],
  );
}

String _wpsKey(String ext) {
  switch (ext) {
    case 'wps':
      return 'fileTypeWpsDoc';
    case 'et':
      return 'fileTypeWpsSheet';
    case 'dps':
      return 'fileTypeWpsPresentation';
    default:
      return 'fileTypeWpsDoc';
  }
}

FileTemplate _google(String ext, String mimeType, String displayName) {
  return FileTemplate(
    extension: '.$ext',
    mimeType: mimeType,
    category: _googleCategory(ext),
    displayNameKey: _googleKey(ext),
    brand: FileTemplateBrand.google,
    icon: _googleIcon(ext),
    brandKeywords: const ['com.google.android.apps'],
  );
}

String _googleKey(String ext) {
  switch (ext) {
    case 'gdoc':
      return 'fileTypeGoogleDoc';
    case 'gsheet':
      return 'fileTypeGoogleSheet';
    case 'gslides':
      return 'fileTypeGoogleSlides';
    default:
      return 'fileTypeGoogleDoc';
  }
}

FileTemplateCategory _msCategory(String ext) {
  switch (ext) {
    case 'docx':
    case 'doc':
      return FileTemplateCategory.document;
    case 'xlsx':
    case 'xls':
      return FileTemplateCategory.spreadsheet;
    case 'pptx':
    case 'ppt':
      return FileTemplateCategory.presentation;
    default:
      return FileTemplateCategory.document;
  }
}

IconData _msIcon(String ext) {
  switch (ext) {
    case 'docx':
    case 'doc':
      return PhosphorIconsLight.fileDoc;
    case 'xlsx':
    case 'xls':
      return PhosphorIconsLight.fileXls;
    case 'pptx':
    case 'ppt':
      return PhosphorIconsLight.filePpt;
    default:
      return PhosphorIconsLight.fileText;
  }
}

List<String> _msKeywords(String ext) {
  switch (ext) {
    case 'docx':
    case 'doc':
      return [
        'winword',
        'office',
        'microsoft.word',
        'com.microsoft.office.word',
      ];
    case 'xlsx':
    case 'xls':
      return [
        'excel',
        'office',
        'microsoft.excel',
        'com.microsoft.office.excel',
      ];
    case 'pptx':
    case 'ppt':
      return [
        'powerpnt',
        'office',
        'microsoft.powerpoint',
        'com.microsoft.office.powerpoint',
      ];
    default:
      return ['office', 'microsoft'];
  }
}

FileTemplateCategory _libreCategory(String ext) {
  switch (ext) {
    case 'odt':
      return FileTemplateCategory.document;
    case 'ods':
      return FileTemplateCategory.spreadsheet;
    case 'odp':
      return FileTemplateCategory.presentation;
    case 'odg':
      return FileTemplateCategory.image;
    case 'odc':
      return FileTemplateCategory.spreadsheet;
    case 'odf':
      return FileTemplateCategory.document;
    default:
      return FileTemplateCategory.document;
  }
}

IconData _libreIcon(String ext) {
  switch (ext) {
    case 'odt':
      return PhosphorIconsLight.fileDoc;
    case 'ods':
      return PhosphorIconsLight.fileXls;
    case 'odp':
      return PhosphorIconsLight.filePpt;
    case 'odg':
      return PhosphorIconsLight.imageSquare;
    case 'odc':
      return PhosphorIconsLight.chartLine;
    case 'odf':
      return PhosphorIconsLight.function;
    default:
      return PhosphorIconsLight.fileText;
  }
}

FileTemplateCategory _wpsCategory(String ext) {
  switch (ext) {
    case 'wps':
      return FileTemplateCategory.document;
    case 'et':
      return FileTemplateCategory.spreadsheet;
    case 'dps':
      return FileTemplateCategory.presentation;
    default:
      return FileTemplateCategory.document;
  }
}

IconData _wpsIcon(String ext) {
  switch (ext) {
    case 'wps':
      return PhosphorIconsLight.fileDoc;
    case 'et':
      return PhosphorIconsLight.fileXls;
    case 'dps':
      return PhosphorIconsLight.filePpt;
    default:
      return PhosphorIconsLight.fileText;
  }
}

FileTemplateCategory _googleCategory(String ext) {
  switch (ext) {
    case 'gdoc':
      return FileTemplateCategory.document;
    case 'gsheet':
      return FileTemplateCategory.spreadsheet;
    case 'gslides':
      return FileTemplateCategory.presentation;
    default:
      return FileTemplateCategory.document;
  }
}

IconData _googleIcon(String ext) {
  switch (ext) {
    case 'gdoc':
      return PhosphorIconsLight.fileDoc;
    case 'gsheet':
      return PhosphorIconsLight.fileXls;
    case 'gslides':
      return PhosphorIconsLight.filePpt;
    default:
      return PhosphorIconsLight.fileText;
  }
}
