import 'package:path/path.dart' as p;

/// Supported archive container formats.
enum ArchiveFormat {
  zip,
  tar,
  tarGz,
  tarBz2,
  tarXz,
  gzip,
  bzip2,
  sevenZip,
  rar,
  unknown,
}

/// Detects archive format from a file path (supports compound extensions).
ArchiveFormat detectArchiveFormat(String filePath) {
  final lower = p.basename(filePath).toLowerCase();

  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    return ArchiveFormat.tarGz;
  }
  if (lower.endsWith('.tar.bz2') ||
      lower.endsWith('.tbz2') ||
      lower.endsWith('.tbz')) {
    return ArchiveFormat.tarBz2;
  }
  if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
    return ArchiveFormat.tarXz;
  }

  switch (p.extension(lower)) {
    case '.zip':
      return ArchiveFormat.zip;
    case '.tar':
      return ArchiveFormat.tar;
    case '.gz':
      return ArchiveFormat.gzip;
    case '.bz2':
      return ArchiveFormat.bzip2;
    case '.7z':
      return ArchiveFormat.sevenZip;
    case '.rar':
      return ArchiveFormat.rar;
    default:
      return ArchiveFormat.unknown;
  }
}

/// Whether the format can be listed/extracted with the pure-Dart [archive] package.
bool isDartArchiveFormat(ArchiveFormat format) {
  switch (format) {
    case ArchiveFormat.zip:
    case ArchiveFormat.tar:
    case ArchiveFormat.tarGz:
    case ArchiveFormat.tarBz2:
    case ArchiveFormat.tarXz:
    case ArchiveFormat.gzip:
    case ArchiveFormat.bzip2:
      return true;
    case ArchiveFormat.sevenZip:
    case ArchiveFormat.rar:
    case ArchiveFormat.unknown:
      return false;
  }
}
