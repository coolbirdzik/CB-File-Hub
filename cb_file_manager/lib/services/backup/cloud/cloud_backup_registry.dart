import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_backup_provider.dart';
import 'dropbox_backup_provider.dart';
import 'google_drive_backup_provider.dart';
import 'onedrive_backup_provider.dart';

/// How this device last backed up to one provider, kept so the screen can say
/// when a drive was last synced and why the latest attempt failed.
class CloudSyncRecord {
  const CloudSyncRecord({
    this.succeededAt,
    this.fileName,
    this.failedAt,
    this.error,
  });

  /// Last successful upload, kept even when a later attempt fails.
  final DateTime? succeededAt;
  final String? fileName;

  /// Set only while the most recent attempt is a failure.
  final DateTime? failedAt;
  final String? error;

  bool get lastAttemptFailed => error != null;

  CloudSyncRecord succeeded(DateTime at, String? fileName) =>
      CloudSyncRecord(succeededAt: at, fileName: fileName);

  CloudSyncRecord failed(DateTime at, String error) => CloudSyncRecord(
    succeededAt: succeededAt,
    fileName: fileName,
    failedAt: at,
    error: error,
  );

  Map<String, dynamic> toJson() => {
    'succeededAt': succeededAt?.toIso8601String(),
    'fileName': fileName,
    'failedAt': failedAt?.toIso8601String(),
    'error': error,
  };

  factory CloudSyncRecord.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) =>
        DateTime.tryParse((json[key] as String?) ?? '');
    return CloudSyncRecord(
      succeededAt: date('succeededAt'),
      fileName: json['fileName'] as String?,
      failedAt: date('failedAt'),
      error: json['error'] as String?,
    );
  }
}

/// The cloud drives CB File Hub can back up to, and how each last synced.
class CloudBackupRegistry {
  CloudBackupRegistry._();

  static final CloudBackupRegistry instance = CloudBackupRegistry._();

  static const String _lastSyncKeyPrefix = 'cb_cloud_backup_last_sync_';

  late final List<CloudBackupProvider> providers = [
    GoogleDriveBackupProvider(),
    DropboxBackupProvider(),
    OneDriveBackupProvider(),
  ];

  /// Providers whose OAuth client id was compiled into this build.
  List<CloudBackupProvider> get configuredProviders =>
      providers.where((provider) => provider.isConfigured).toList();

  CloudBackupProvider? byId(String? id) {
    if (id == null) return null;
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  Future<CloudSyncRecord?> lastSync(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_lastSyncKeyPrefix$providerId');
    if (raw == null) return null;
    try {
      return CloudSyncRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLastSync(String providerId, CloudSyncRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_lastSyncKeyPrefix$providerId',
      jsonEncode(record.toJson()),
    );
  }
}
