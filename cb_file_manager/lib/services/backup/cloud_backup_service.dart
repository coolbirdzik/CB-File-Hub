import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/services/backup/backup_archive_service.dart';
import 'package:cb_file_manager/services/backup/cloud/cloud_backup_provider.dart';

/// Outcome of pushing one archive to one provider in [CloudBackupService.uploadToMany].
class CloudUploadResult {
  const CloudUploadResult._(this.provider, this.file, this.error);

  final CloudBackupProvider provider;
  final CloudBackupFile? file;
  final Object? error;

  bool get succeeded => error == null;
}

/// Moves backup archives between the app and a cloud drive: build the zip in a
/// temp folder, hand it to the provider, and clean up afterwards.
class CloudBackupService {
  CloudBackupService({
    BackupArchiveService? archiveService,
    UserPreferences? preferences,
  }) : _archive = archiveService ?? BackupArchiveService(),
       _preferences = preferences ?? UserPreferences.instance;

  final BackupArchiveService _archive;
  final UserPreferences _preferences;

  /// Name used for the uploaded archive; the timestamp keeps versions apart.
  static String archiveName() =>
      'cb_file_hub_backup_'
      '${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.zip';

  Future<CloudBackupFile> upload({
    required CloudBackupProvider provider,
    required bool includeSettings,
    required bool includeTags,
  }) async {
    final workDir = await _workDirectory();
    final name = archiveName();
    final localPath = path.join(workDir.path, name);
    try {
      final exported = await _archive.exportZip(
        outputPath: localPath,
        includeSettings: includeSettings,
        includeTags: includeTags,
      );
      if (exported == null) {
        throw CloudBackupException('Nothing was selected to back up');
      }
      return await provider.upload(file: File(exported), name: name);
    } finally {
      await _cleanUp(workDir);
    }
  }

  /// Builds the archive once and uploads it to every provider in parallel.
  ///
  /// A failing drive does not stop the others: each outcome is reported via
  /// [onStarted]/[onDone] as it happens and returned in [providers] order.
  Future<List<CloudUploadResult>> uploadToMany({
    required List<CloudBackupProvider> providers,
    required bool includeSettings,
    required bool includeTags,
    void Function(CloudBackupProvider provider)? onStarted,
    void Function(CloudUploadResult result)? onDone,
  }) async {
    final workDir = await _workDirectory();
    final name = archiveName();
    try {
      final exported = await _archive.exportZip(
        outputPath: path.join(workDir.path, name),
        includeSettings: includeSettings,
        includeTags: includeTags,
      );
      if (exported == null) {
        throw CloudBackupException('Nothing was selected to back up');
      }
      final archive = File(exported);
      return await Future.wait(
        providers.map((provider) async {
          onStarted?.call(provider);
          CloudUploadResult result;
          try {
            final file = await provider.upload(file: archive, name: name);
            result = CloudUploadResult._(provider, file, null);
          } catch (error) {
            result = CloudUploadResult._(provider, null, error);
          }
          onDone?.call(result);
          return result;
        }),
      );
    } finally {
      await _cleanUp(workDir);
    }
  }

  Future<Map<String, dynamic>?> restore({
    required CloudBackupProvider provider,
    required CloudBackupFile remote,
    required bool importSettings,
    required bool importTags,
  }) async {
    final workDir = await _workDirectory();
    try {
      final downloaded = await provider.download(
        remote,
        path.join(
          workDir.path,
          remote.name.isEmpty ? 'backup.zip' : remote.name,
        ),
      );
      return await _archive.importZip(
        archivePath: downloaded.path,
        importSettings: importSettings,
        importTags: importTags,
        restoreSettings: _preferences.restoreAllFrom,
      );
    } finally {
      await _cleanUp(workDir);
    }
  }

  Future<Directory> _workDirectory() async {
    final tempRoot = await getTemporaryDirectory();
    final dir = Directory(
      path.join(
        tempRoot.path,
        'cb_file_hub_cloud_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _cleanUp(Directory dir) async {
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
