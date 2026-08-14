import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Summary of the most recent completed Cleaner scan for one drive.
///
/// This is presentation-only state: it lets the setup screen show what the
/// previous scan found instead of an empty placeholder, and it powers the
/// before/after comparison on the cleaned screen. It is never used as an
/// input to junk classification or deletion selection.
class CleanerLastScanSummary {
  final String drivePath;
  final DateTime scannedAt;
  final int totalBytes;
  final int fileCount;
  final int junkBytes;
  final int cleanableCount;

  /// Free space on the drive at the moment the scan finished.
  final int freeBytes;

  const CleanerLastScanSummary({
    required this.drivePath,
    required this.scannedAt,
    required this.totalBytes,
    required this.fileCount,
    required this.junkBytes,
    required this.cleanableCount,
    required this.freeBytes,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'drivePath': drivePath,
        'scannedAt': scannedAt.toIso8601String(),
        'totalBytes': totalBytes,
        'fileCount': fileCount,
        'junkBytes': junkBytes,
        'cleanableCount': cleanableCount,
        'freeBytes': freeBytes,
      };

  static CleanerLastScanSummary? fromJson(Map<String, dynamic> json) {
    final drivePath = json['drivePath'];
    final scannedAt = json['scannedAt'];
    if (drivePath is! String || scannedAt is! String) return null;
    final parsedAt = DateTime.tryParse(scannedAt);
    if (parsedAt == null) return null;
    int readInt(String key) {
      final value = json[key];
      return value is int ? value : 0;
    }

    return CleanerLastScanSummary(
      drivePath: drivePath,
      scannedAt: parsedAt,
      totalBytes: readInt('totalBytes'),
      fileCount: readInt('fileCount'),
      junkBytes: readInt('junkBytes'),
      cleanableCount: readInt('cleanableCount'),
      freeBytes: readInt('freeBytes'),
    );
  }
}

/// Persists a one-line summary of the last Cleaner scan per drive.
class CleanerLastScanService {
  static const String _keyPrefix = 'cleaner.last_scan.v1.';

  final SharedPreferences _preferences;

  const CleanerLastScanService(this._preferences);

  static String _key(String drivePath) {
    var normalized = drivePath.trim().toUpperCase();
    while (normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return '$_keyPrefix$normalized';
  }

  CleanerLastScanSummary? read(String drivePath) {
    final raw = _preferences.getString(_key(drivePath));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return CleanerLastScanSummary.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(CleanerLastScanSummary summary) async {
    await _preferences.setString(
      _key(summary.drivePath),
      jsonEncode(summary.toJson()),
    );
  }
}
