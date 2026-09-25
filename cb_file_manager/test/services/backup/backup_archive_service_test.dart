import 'dart:io';

import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/services/backup/backup_archive_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );

  late Directory tempDir;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (methodCall) async {
          switch (methodCall.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return Directory.systemTemp.path;
            default:
              return null;
          }
        });
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme': 'dark',
      'grid_size': 4,
      'show_hidden': true,
    });
    await UserPreferences.instance.init();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cb_backup_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('exports nothing when no component is selected', () async {
    final result = await BackupArchiveService().exportZip(
      outputPath: path.join(tempDir.path, 'empty.zip'),
      includeSettings: false,
      includeTags: false,
    );

    expect(result, isNull);
    expect(File(path.join(tempDir.path, 'empty.zip')).existsSync(), isFalse);
  });

  test('settings round-trip through the archive', () async {
    final service = BackupArchiveService();
    final archivePath = path.join(tempDir.path, 'backup.zip');

    final exported = await service.exportZip(
      outputPath: archivePath,
      includeSettings: true,
      includeTags: false,
    );
    expect(exported, archivePath);

    final manifest = await service.inspect(archivePath);
    expect(manifest?['format'], 'cb_file_hub_backup');
    expect(manifest?['components'], {'settings': true, 'tags': false});

    Map<String, Object?>? restored;
    final summary = await service.importZip(
      archivePath: archivePath,
      importSettings: true,
      importTags: true,
      restoreSettings: (settings) async => restored = settings,
    );

    expect(restored, containsPair('theme', 'dark'));
    expect(restored, containsPair('grid_size', 4));
    expect(restored, containsPair('show_hidden', true));
    expect(summary?['settingsCount'], restored!.length);
    // The archive has no tags.json, so asking for tags imports nothing.
    expect(summary?['importedTagCount'], 0);
  });

  test('inspect returns null for a zip without a manifest', () async {
    final archivePath = path.join(tempDir.path, 'foreign.zip');
    // Minimal valid empty zip: end-of-central-directory record only.
    await File(archivePath).writeAsBytes([
      0x50, 0x4b, 0x05, 0x06, //
      ...List<int>.filled(18, 0),
    ]);

    expect(await BackupArchiveService().inspect(archivePath), isNull);
  });
}
