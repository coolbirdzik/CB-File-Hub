import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_backup_provider.dart';
import 'dropbox_backup_provider.dart';
import 'google_drive_backup_provider.dart';
import 'onedrive_backup_provider.dart';

/// The cloud drives CB File Hub can back up to, plus the one the user picked.
class CloudBackupRegistry {
  CloudBackupRegistry._();

  static final CloudBackupRegistry instance = CloudBackupRegistry._();

  static const String _selectedProviderKey = 'cb_cloud_backup_provider';

  /// Local folder mode: the archive is written to a directory that a desktop
  /// sync client (Drive for desktop, OneDrive, Dropbox, ...) already mirrors.
  static const String localFolderId = 'local_folder';

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

  Future<String?> selectedProviderId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedProviderKey);
  }

  Future<void> setSelectedProviderId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedProviderKey, id);
  }
}
