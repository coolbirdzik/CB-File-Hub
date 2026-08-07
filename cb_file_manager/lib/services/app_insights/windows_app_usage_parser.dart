import 'dart:typed_data';

/// Parsed UserAssist evidence before it is matched to an installed app.
class ParsedUserAssistRecord {
  final String decodedTarget;
  final DateTime lastOpenedAt;

  const ParsedUserAssistRecord({
    required this.decodedTarget,
    required this.lastOpenedAt,
  });
}

/// Pure parsing helpers for Windows usage evidence.
class WindowsAppUsageParser {
  static const int _modernUserAssistRecordLength = 72;
  static const int _lastExecutionFileTimeOffset = 60;
  static const int _windowsToUnixEpochMicroseconds = 11644473600000000;

  const WindowsAppUsageParser();

  /// Decodes the ROT13 value names stored in the UserAssist Count key.
  String decodeRot13(String value) {
    final codeUnits = value.codeUnits.map((unit) {
      if (unit >= 65 && unit <= 90) {
        return 65 + ((unit - 65 + 13) % 26);
      }
      if (unit >= 97 && unit <= 122) {
        return 97 + ((unit - 97 + 13) % 26);
      }
      return unit;
    });
    return String.fromCharCodes(codeUnits);
  }

  /// Parses the modern 72-byte Windows UserAssist record.
  ///
  /// Bytes 60..67 contain a little-endian FILETIME. Short records and invalid
  /// FILETIME values are ignored instead of being treated as ancient usage.
  DateTime? parseModernUserAssistLastOpened(Uint8List data) {
    if (data.length < _modernUserAssistRecordLength) return null;
    final byteData = ByteData.sublistView(data);
    final low = byteData.getUint32(
      _lastExecutionFileTimeOffset,
      Endian.little,
    );
    final high = byteData.getUint32(
      _lastExecutionFileTimeOffset + 4,
      Endian.little,
    );
    final fileTimeTicks = (high << 32) | low;
    if (fileTimeTicks <= 0) return null;

    final unixMicroseconds =
        (fileTimeTicks ~/ 10) - _windowsToUnixEpochMicroseconds;
    if (unixMicroseconds <= 0) return null;
    try {
      return DateTime.fromMicrosecondsSinceEpoch(
        unixMicroseconds,
        isUtc: true,
      );
    } on ArgumentError {
      return null;
    }
  }

  ParsedUserAssistRecord? parseUserAssistRecord(
    String encodedName,
    Uint8List data,
  ) {
    final lastOpenedAt = parseModernUserAssistLastOpened(data);
    if (lastOpenedAt == null) return null;
    final target = decodeRot13(encodedName).trim();
    if (target.isEmpty) return null;
    return ParsedUserAssistRecord(
      decodedTarget: target,
      lastOpenedAt: lastOpenedAt,
    );
  }

  /// Extracts the executable name from a Prefetch filename.
  ///
  /// The trailing eight hexadecimal characters are the Windows Prefetch hash.
  /// The executable portion may itself contain hyphens, so the match is
  /// anchored at the end of the filename.
  String? executableNameFromPrefetch(String fileName) {
    final match = RegExp(
      r'^(.+)-[0-9a-f]{8}\.pf$',
      caseSensitive: false,
    ).firstMatch(fileName.trim());
    final executable = match?.group(1)?.trim();
    if (executable == null || executable.isEmpty) return null;
    return executable.toLowerCase().endsWith('.exe')
        ? executable
        : '$executable.exe';
  }
}
