import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/services/backup/backup_archive_service.dart';
import 'package:cb_file_manager/services/backup/cloud/cloud_backup_provider.dart';
import 'package:cb_file_manager/services/backup/cloud_backup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Writes a tiny stand-in archive instead of touching the database.
class _FakeArchiveService extends BackupArchiveService {
  _FakeArchiveService() : super(preferences: UserPreferences.instance);

  int exports = 0;

  @override
  Future<String?> exportZip({
    required String outputPath,
    required bool includeSettings,
    required bool includeTags,
  }) async {
    if (!includeSettings && !includeTags) return null;
    exports++;
    await File(outputPath).writeAsString('zip');
    return outputPath;
  }
}

class _FakeProvider extends CloudBackupProvider {
  _FakeProvider(this.id, {this.failWith});

  @override
  final String id;
  final Object? failWith;
  final List<String> uploadedNames = [];

  @override
  String get displayName => id;
  @override
  IconData get icon => Icons.cloud;
  @override
  bool get isConfigured => true;
  @override
  String get remoteFolderName => 'Backups';

  @override
  Future<CloudBackupFile> upload({
    required File file,
    required String name,
  }) async {
    expect(await file.exists(), isTrue);
    if (failWith != null) throw failWith!;
    uploadedNames.add(name);
    return CloudBackupFile(id: '$id/$name', name: name);
  }

  @override
  Future<CloudAccount?> currentAccount() async => null;
  @override
  Future<CloudAccount> connect() => throw UnimplementedError();
  @override
  Future<void> disconnect() async {}
  @override
  Future<List<CloudBackupFile>> listBackups() async => const [];
  @override
  Future<File> download(CloudBackupFile remote, String destinationPath) =>
      throw UnimplementedError();
  @override
  Future<void> delete(CloudBackupFile remote) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (methodCall) async {
          if (methodCall.method == 'getTemporaryDirectory') {
            return Directory.systemTemp.path;
          }
          return null;
        });
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await UserPreferences.instance.init();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  test(
    'uploadToMany builds one archive and isolates provider failures',
    () async {
      final archive = _FakeArchiveService();
      final drive = _FakeProvider('google_drive');
      final dropbox = _FakeProvider(
        'dropbox',
        failWith: CloudBackupException('quota exceeded'),
      );
      final onedrive = _FakeProvider('onedrive');
      final started = <String>[];
      final done = <String>[];

      final results =
          await CloudBackupService(
            archiveService: archive,
            preferences: UserPreferences.instance,
          ).uploadToMany(
            providers: [drive, dropbox, onedrive],
            includeSettings: true,
            includeTags: true,
            onStarted: (provider) => started.add(provider.id),
            onDone: (result) => done.add(result.provider.id),
          );

      expect(archive.exports, 1);
      expect(results.map((result) => result.provider.id), [
        'google_drive',
        'dropbox',
        'onedrive',
      ]);
      expect(results.map((result) => result.succeeded), [true, false, true]);
      expect(results[1].error.toString(), 'quota exceeded');
      expect(started, unorderedEquals(['google_drive', 'dropbox', 'onedrive']));
      expect(done, unorderedEquals(['google_drive', 'dropbox', 'onedrive']));
      // Both drives received the same archive name.
      expect(drive.uploadedNames, onedrive.uploadedNames);
    },
  );

  test('uploadToMany throws when nothing was selected', () async {
    final provider = _FakeProvider('google_drive');
    await expectLater(
      CloudBackupService(
        archiveService: _FakeArchiveService(),
        preferences: UserPreferences.instance,
      ).uploadToMany(
        providers: [provider],
        includeSettings: false,
        includeTags: false,
      ),
      throwsA(isA<CloudBackupException>()),
    );
    expect(provider.uploadedNames, isEmpty);
  });
}
