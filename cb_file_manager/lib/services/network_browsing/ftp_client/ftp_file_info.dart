import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as pathlib;
import 'package:intl/intl.dart';

/// Represents a file or directory on an FTP server
class FtpFileInfo implements FileSystemEntity {
  /// The name of the file or directory
  final String name;

  /// The full path of the file or directory
  @override
  final String path;

  /// The size of the file in bytes
  final int size;

  /// The last modified date of the file
  final DateTime? lastModified;

  /// Whether this is a directory
  final bool isDirectory;

  /// File permissions in Unix format (e.g., 'drwxr-xr-x')
  final String? permissions;

  /// Raw listing line for debugging
  final String rawListing;

  FtpFileInfo({
    required this.name,
    required this.path,
    required this.size,
    this.lastModified,
    required this.isDirectory,
    this.permissions,
    required this.rawListing,
  });

  @override
  bool get isAbsolute => path.startsWith('/');

  String get basename => name;

  @override
  FileSystemEntity get absolute => this; // Already absolute in FTP context

  @override
  Directory get parent => Directory(pathlib.dirname(path));

  /// Parses a directory listing in standard Unix-like format
  ///
  /// Example format:
  /// drwxr-xr-x 2 user group 4096 Jan 1 2022 dirname
  /// -rw-r--r-- 1 user group 1234 Jan 1 2022 filename.txt
  static List<FtpFileInfo> parseDirectoryListing(
    String listing, [
    String currentPath = '/',
  ]) {
    final List<FtpFileInfo> result = [];
    final lines = listing.split('\n');

    debugPrint(
      "FTPFileInfo: Parsing ${lines.length} lines from directory listing",
    );

    // Detect the format (Unix, DOS/Windows, etc.)
    bool isUnixFormat = false;
    bool isWindowsFormat = false;
    bool isMSDOSFormat = false;

    // Sample some lines to determine format
    for (var i = 0; i < lines.length && i < 5; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('d') ||
          line.startsWith('-') ||
          line.startsWith('l')) {
        isUnixFormat = true;
      } else if (line.contains('<DIR>')) {
        isWindowsFormat = true;
      } else if (line.contains('/') && RegExp(r'\d+:\d+[AP]M').hasMatch(line)) {
        isMSDOSFormat = true;
      }
    }

    debugPrint(
      "FTPFileInfo: Detected format - Unix: $isUnixFormat, Windows: $isWindowsFormat, MSDOS: $isMSDOSFormat",
    );

    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        continue;
      }

      try {
        // Skip '.' and '..' entries
        if (trimmedLine.contains(' . ') ||
            trimmedLine.contains(' .. ') ||
            trimmedLine == '.' ||
            trimmedLine == '..') {
          debugPrint("FTPFileInfo: Skipping directory entry: $trimmedLine");
          continue;
        }

        FtpFileInfo? fileInfo;

        // Unix-style listing
        // Example: drwxr-xr-x 2 user group 4096 Jan 1 2022 dirname
        if (isUnixFormat &&
            trimmedLine.length > 10 &&
            (trimmedLine.startsWith('d') ||
                trimmedLine.startsWith('-') ||
                trimmedLine.startsWith('l'))) {
          fileInfo = _parseUnixFormat(trimmedLine, currentPath);
        }
        // Windows-style listing (DIR command style)
        // Example: 01-01-22  12:00PM <DIR> dirname
        // Example: 01-01-22  12:00PM 1234 filename.txt
        else if (isWindowsFormat &&
            (trimmedLine.contains('<DIR>') ||
                (trimmedLine.length > 17 && _hasDateTimePrefix(trimmedLine)))) {
          fileInfo = _parseWindowsFormat(trimmedLine, currentPath);
        }
        // MS-DOS style FTP server format
        // Example: 04-27-20  09:09AM       <DIR>          dirname
        // Example: 04-27-20  09:09AM                 1234 filename.txt
        else if (isMSDOSFormat) {
          fileInfo = _parseMSDOSFormat(trimmedLine, currentPath);
        }
        // Try last resort simple format (single file/dir name per line)
        else if (trimmedLine.isNotEmpty) {
          // If we can't determine format, just create an entry with minimal info
          final name = trimmedLine;
          final path = pathlib.join(currentPath, name);
          // Guess if it's a directory (no extension typically)
          final hasExtension = name.contains('.');

          fileInfo = FtpFileInfo(
            name: name,
            path: path,
            size: 0,
            lastModified: null,
            isDirectory: !hasExtension, // Best guess
            permissions: null,
            rawListing: trimmedLine,
          );

          debugPrint("FTPFileInfo: Created simple entry for: $name");
        }

        // Add the parsed file info to the result list
        if (fileInfo != null) {
          result.add(fileInfo);
          debugPrint(
            "FTPFileInfo: Added ${fileInfo.isDirectory ? "directory" : "file"}: ${fileInfo.name}",
          );
        }
      } catch (e) {
        debugPrint("FTPFileInfo: Error parsing listing line: $e");
        debugPrint("FTPFileInfo: Line: $trimmedLine");
        // Continue with next line on error
      }
    }

    debugPrint("FTPFileInfo: Finished parsing. Found ${result.length} items");
    return result;
  }

  /// Splits the listing line into parts, handling spaces in file names
  static List<String> _splitListingParts(String line) {
    final parts = <String>[];
    final regExp = RegExp(r'\S+');
    final matches = regExp.allMatches(line);

    // Extract first 8 parts (up to the month)
    for (int i = 0; i < matches.length && i < 8; i++) {
      parts.add(matches.elementAt(i).group(0)!);
    }

    // The rest is the filename (might contain spaces)
    if (matches.length > 8) {
      final nameStartIndex = matches.elementAt(8).start;
      parts.add(line.substring(nameStartIndex));
    }

    return parts;
  }

  /// Checks if a line has a date-time prefix like Windows FTP servers
  static bool _hasDateTimePrefix(String line) {
    // Check for patterns like MM-DD-YY
    final dateRegExp = RegExp(r'^\d{2}-\d{2}-\d{2}');
    return dateRegExp.hasMatch(line);
  }

  /// Parses date and time in Unix format
  static DateTime? _parseDateTime(String month, String day, String yearOrTime) {
    try {
      final months = {
        'Jan': 1,
        'Feb': 2,
        'Mar': 3,
        'Apr': 4,
        'May': 5,
        'Jun': 6,
        'Jul': 7,
        'Aug': 8,
        'Sep': 9,
        'Oct': 10,
        'Nov': 11,
        'Dec': 12,
      };

      final monthNum = months[month] ?? 1;
      final dayNum = int.tryParse(day) ?? 1;

      // Handle different time/year formats
      int year = DateTime.now().year;
      int hour = 0;
      int minute = 0;

      if (yearOrTime.contains(':')) {
        // Format: "HH:MM"
        final timeParts = yearOrTime.split(':');
        hour = int.tryParse(timeParts[0]) ?? 0;
        minute = int.tryParse(timeParts[1]) ?? 0;
      } else {
        // Format: "YYYY"
        year = int.tryParse(yearOrTime) ?? DateTime.now().year;
      }

      return DateTime(year, monthNum, dayNum, hour, minute);
    } catch (e) {
      debugPrint('Error parsing date: $e');
      return null;
    }
  }

  /// Parses date and time in Windows format
  static DateTime? _parseDateTimeWindows(String date, String time) {
    try {
      // Parse MM-DD-YY format
      final dateParts = date.split('-');
      if (dateParts.length != 3) return null;

      final month = int.tryParse(dateParts[0]) ?? 1;
      final day = int.tryParse(dateParts[1]) ?? 1;

      // Convert 2-digit year to 4-digit
      var year = int.tryParse(dateParts[2]) ?? 0;
      if (year < 100) {
        year += year < 70 ? 2000 : 1900;
      }

      // Parse time (might be in 12-hour format)
      final hasAmPm =
          time.toLowerCase().contains('am') ||
          time.toLowerCase().contains('pm');
      final isPm = time.toLowerCase().contains('pm');

      var timeStr = time;
      if (hasAmPm) {
        timeStr = time.substring(0, time.length - 2);
      }

      final timeParts = timeStr.split(':');
      var hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = timeParts.length > 1
          ? (int.tryParse(timeParts[1]) ?? 0)
          : 0;

      // Adjust for PM
      if (isPm && hour < 12) {
        hour += 12;
      } else if (!isPm && hour == 12) {
        hour = 0;
      }

      return DateTime(year, month, day, hour, minute);
    } catch (e) {
      debugPrint('Error parsing Windows date/time: $e');
      return null;
    }
  }

  // Parse Unix format directory listing
  static FtpFileInfo? _parseUnixFormat(String line, String currentPath) {
    try {
      final parts = _splitListingParts(line);
      if (parts.length < 9) return null; // Not enough parts

      // Parse permissions
      final permissions = parts[0];
      final isDir = permissions.startsWith('d');

      // Parse size
      final size = int.tryParse(parts[4]) ?? 0;

      // Parse date (might be in different formats)
      DateTime? modifiedDate = _parseDateTime(parts[5], parts[6], parts[7]);

      // Extract name (might contain spaces, so join the rest)
      final nameStartIndex = parts.length >= 9 ? 8 : parts.length - 1;
      final name = parts.sublist(nameStartIndex).join(' ');

      // Handle symbolic links
      String fileName = name;
      if (permissions.startsWith('l') && name.contains(' -> ')) {
        fileName = name.split(' -> ')[0];
      }

      // Construct the full path
      final fullPath = pathlib.join(currentPath, fileName);

      return FtpFileInfo(
        name: fileName,
        path: fullPath,
        size: size,
        lastModified: modifiedDate,
        isDirectory: isDir,
        permissions: permissions,
        rawListing: line,
      );
    } catch (e) {
      debugPrint("FTPFileInfo: Error parsing Unix format: $e");
      return null;
    }
  }

  // Parse Windows format directory listing
  static FtpFileInfo? _parseWindowsFormat(String line, String currentPath) {
    try {
      final isDir = line.contains('<DIR>');

      // Split into columns
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) return null;

      // Parse date and time
      DateTime? modifiedDate;
      if (parts.length >= 2) {
        final datePart = parts[0];
        final timePart = parts[1];
        modifiedDate = _parseDateTimeWindows(datePart, timePart);
      }

      // Parse size or <DIR> indicator
      int size = 0;
      int nameStartIndex = 3;

      // Handle different formats
      if (isDir) {
        // Find where the filename starts after <DIR>
        for (int i = 0; i < parts.length; i++) {
          if (parts[i] == '<DIR>') {
            nameStartIndex = i + 1;
            break;
          }
        }
      } else {
        // Find where the size is
        for (int i = 2; i < parts.length; i++) {
          if (int.tryParse(parts[i]) != null) {
            size = int.tryParse(parts[i]) ?? 0;
            nameStartIndex = i + 1;
            break;
          }
        }
      }

      // Extract name (might contain spaces)
      if (nameStartIndex >= parts.length) return null;

      final name = parts.sublist(nameStartIndex).join(' ');

      // Construct the full path
      final fullPath = pathlib.join(currentPath, name);

      return FtpFileInfo(
        name: name,
        path: fullPath,
        size: size,
        lastModified: modifiedDate,
        isDirectory: isDir,
        permissions: isDir ? 'drwxr-xr-x' : '-rw-r--r--', // Default permissions
        rawListing: line,
      );
    } catch (e) {
      debugPrint("FTPFileInfo: Error parsing Windows format: $e");
      return null;
    }
  }

  // Parse MS-DOS format directory listing
  static FtpFileInfo? _parseMSDOSFormat(String line, String currentPath) {
    try {
      // Check if this is a directory entry
      final isDir = line.contains('<DIR>');

      // Try to extract date and time (usually the first two columns)
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) return null;

      // Parse date (first column) and time (second column)
      DateTime? modifiedDate;
      if (parts.length >= 2) {
        final datePart = parts[0];
        final timePart = parts[1];
        modifiedDate = _parseDateTimeWindows(datePart, timePart);
      }

      // Extract size and name
      int size = 0;
      String name = "";

      if (isDir) {
        // Find name after <DIR> marker
        int dirIndex = -1;
        for (int i = 0; i < parts.length; i++) {
          if (parts[i] == '<DIR>') {
            dirIndex = i;
            break;
          }
        }

        if (dirIndex >= 0 && dirIndex < parts.length - 1) {
          name = parts.sublist(dirIndex + 1).join(' ');
        } else {
          // Fallback: try to extract the last part as name
          name = parts.last;
        }
      } else {
        // For files, try to find the size and then the name
        int sizeIndex = -1;
        for (int i = 2; i < parts.length - 1; i++) {
          if (int.tryParse(parts[i]) != null) {
            size = int.tryParse(parts[i]) ?? 0;
            sizeIndex = i;
            break;
          }
        }

        if (sizeIndex >= 0) {
          name = parts.sublist(sizeIndex + 1).join(' ');
        } else {
          // Fallback: take the last part as name
          name = parts.last;
        }
      }

      // If we couldn't extract a name, skip this entry
      if (name.isEmpty) return null;

      // Construct the full path
      final fullPath = pathlib.join(currentPath, name);

      return FtpFileInfo(
        name: name,
        path: fullPath,
        size: size,
        lastModified: modifiedDate,
        isDirectory: isDir,
        permissions: isDir ? 'drwxr-xr-x' : '-rw-r--r--', // Default permissions
        rawListing: line,
      );
    } catch (e) {
      debugPrint("FTPFileInfo: Error parsing MS-DOS format: $e");
      return null;
    }
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) {
    throw UnsupportedError(
      'Delete operation not supported directly on FtpFileInfo',
    );
  }

  @override
  void deleteSync({bool recursive = false}) {
    throw UnsupportedError(
      'Delete operation not supported directly on FtpFileInfo',
    );
  }

  @override
  Future<FileSystemEntity> rename(String newPath) {
    throw UnsupportedError(
      'Rename operation not supported directly on FtpFileInfo',
    );
  }

  @override
  FileSystemEntity renameSync(String newPath) {
    throw UnsupportedError(
      'Rename operation not supported directly on FtpFileInfo',
    );
  }

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) {
    throw UnsupportedError('Watch operation not supported on FtpFileInfo');
  }

  @override
  Future<bool> exists() async {
    return true; // The entity exists if it was returned in the listing
  }

  @override
  bool existsSync() {
    return true; // The entity exists if it was returned in the listing
  }

  @override
  Future<String> resolveSymbolicLinks() async {
    return path; // Symbolic links are already resolved in the path
  }

  @override
  String resolveSymbolicLinksSync() {
    return path; // Symbolic links are already resolved in the path
  }

  @override
  Uri get uri => Uri.file(path);

  @override
  FileStat statSync() {
    // Create a synthetic FileStat
    return _SyntheticFileStat(
      size: size,
      modified: lastModified ?? DateTime.now(),
      accessed: lastModified ?? DateTime.now(),
      changed: lastModified ?? DateTime.now(),
      type: isDirectory
          ? FileSystemEntityType.directory
          : FileSystemEntityType.file,
      mode: 0, // Not used
    );
  }

  @override
  Future<FileStat> stat() async {
    return statSync();
  }

  @override
  String toString() {
    return 'FtpFileInfo{name: $name, path: $path, size: $size, isDirectory: $isDirectory}';
  }
}

/// Synthetic FileStat implementation for FTP files
class _SyntheticFileStat implements FileStat {
  @override
  final DateTime accessed;

  @override
  final DateTime changed;

  @override
  final DateTime modified;

  @override
  final int mode;

  @override
  final int size;

  @override
  final FileSystemEntityType type;

  _SyntheticFileStat({
    required this.size,
    required this.modified,
    required this.accessed,
    required this.changed,
    required this.type,
    required this.mode,
  });

  @override
  String modeString() {
    // Create a simplified mode string
    switch (type) {
      case FileSystemEntityType.directory:
        return 'drwxr-xr-x';
      case FileSystemEntityType.file:
        return '-rw-r--r--';
      case FileSystemEntityType.link:
        return 'lrwxrwxrwx';
      default:
        return '?rwxr-xr-x';
    }
  }

  @override
  String toString() {
    return '''
FileStat: type=$type
          size=$size
          modified=${DateFormat('yyyy-MM-dd HH:mm:ss').format(modified)}''';
  }
}
