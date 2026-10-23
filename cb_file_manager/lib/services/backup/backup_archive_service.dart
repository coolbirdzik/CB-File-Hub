import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:cb_native/cb_native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';

/// Creates and restores the selectable CB File Hub backup archive.
class BackupArchiveService {
  BackupArchiveService({
    DatabaseManager? databaseManager,
    UserPreferences? preferences,
    this.useNative = true,
  }) : _databaseManager = databaseManager ?? DatabaseManager.getInstance(),
       _preferences = preferences ?? UserPreferences.instance;

  final DatabaseManager _databaseManager;
  final UserPreferences _preferences;
  final bool useNative;

  Future<String?> exportZip({
    required String outputPath,
    required bool includeSettings,
    required bool includeTags,
  }) async {
    if (!includeSettings && !includeTags) return null;

    final tempRoot = await getTemporaryDirectory();
    final workDir = Directory(
      path.join(
        tempRoot.path,
        'cb_file_hub_backup_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await workDir.create(recursive: true);

    try {
      final manifest = <String, dynamic>{
        'format': 'cb_file_hub_backup',
        'version': 1,
        'components': <String, bool>{
          'settings': includeSettings,
          'tags': includeTags,
        },
        'createdAt': DateTime.now().toIso8601String(),
      };
      final files = <String>[];
      final manifestPath = path.join(workDir.path, 'manifest.json');
      await File(manifestPath).writeAsString(jsonEncode(manifest));
      files.add(manifestPath);

      if (includeSettings) {
        final settingsPath = path.join(workDir.path, 'settings.json');
        await File(settingsPath).writeAsString(
          const JsonEncoder.withIndent(
            '  ',
          ).convert(_preferences.getAllSettings()),
        );
        files.add(settingsPath);
      }

      if (includeTags) {
        final tagsPath = path.join(workDir.path, 'tags.json');
        final exported = await _databaseManager.exportDatabase(
          customPath: tagsPath,
        );
        if (exported == null) return null;
        files.add(tagsPath);
      }

      final created =
          useNative &&
          await NativeArchive.createZip(outputPath, {
            for (final file in files) file: path.basename(file),
          });
      if (!created) {
        await Isolate.run(() {
          final encoder = ZipFileEncoder()..create(outputPath);
          try {
            for (final file in files) {
              encoder.addFileSync(File(file), path.basename(file));
            }
          } finally {
            encoder.closeSync();
          }
        });
      }
      return outputPath;
    } finally {
      if (await workDir.exists()) await workDir.delete(recursive: true);
    }
  }

  Future<Map<String, dynamic>?> inspect(String archivePath) async {
    final bytes = await _readMember(archivePath, 'manifest.json');
    if (bytes == null) return null;
    final manifest = jsonDecode(utf8.decode(bytes));
    if (manifest is! Map) return null;
    return Map<String, dynamic>.from(manifest);
  }

  Future<Map<String, dynamic>?> importZip({
    required String archivePath,
    required bool importSettings,
    required bool importTags,
    required Future<void> Function(Map<String, Object?>) restoreSettings,
  }) async {
    if (!importSettings && !importTags) return null;
    var settingsCount = 0;
    var importedTagCount = 0;

    if (importSettings) {
      final bytes = await _readMember(archivePath, 'settings.json');
      if (bytes != null) {
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map) {
          final settings = Map<String, Object?>.from(decoded);
          await restoreSettings(settings);
          settingsCount = settings.length;
        }
      }
    }

    if (importTags) {
      final bytes = await _readMember(archivePath, 'tags.json');
      if (bytes != null) {
        final tempRoot = await getTemporaryDirectory();
        final tagsPath = path.join(
          tempRoot.path,
          'cb_file_hub_import_${DateTime.now().microsecondsSinceEpoch}.json',
        );
        try {
          await File(tagsPath).writeAsBytes(bytes);
          final imported = await _databaseManager.importDatabase(
            tagsPath,
            skipFileExistenceCheck: true,
          );
          if (imported) importedTagCount = 1;
        } finally {
          final tempFile = File(tagsPath);
          if (await tempFile.exists()) await tempFile.delete();
        }
      }
    }

    return {
      'settingsCount': settingsCount,
      'importedTagCount': importedTagCount,
    };
  }

  Future<Uint8List?> _readMember(String archivePath, String name) async {
    if (useNative) {
      final member = await NativeArchive.readZipEntry(archivePath, name);
      if (member != null) return member.bytes;
    }
    return Isolate.run(() {
      final input = InputFileStream(archivePath);
      try {
        final archive = ZipDecoder().decodeStream(input);
        final member = archive.findFile(name);
        return member == null ? null : Uint8List.fromList(member.content);
      } finally {
        input.closeSync();
      }
    });
  }
}
