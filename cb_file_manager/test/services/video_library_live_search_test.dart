import 'dart:io';

import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory testRoot;
  late Directory mediaRoot;

  setUpAll(() async {
    testRoot = await Directory.systemTemp.createTemp(
      'video-library-live-search-',
    );
    mediaRoot = await Directory(
      path.join(testRoot.path, 'media'),
    ).create(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (methodCall) async {
          switch (methodCall.method) {
            case 'getApplicationDocumentsDirectory':
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
              return testRoot.path;
            default:
              return null;
          }
        });
  });

  tearDownAll(() async {
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    await testRoot.delete(recursive: true);
  });

  test(
    'submitted search can reload videos added after the previous listing',
    () async {
      final service = VideoLibraryService();
      final library = await service.createLibrary(
        name: 'Live search library',
        directories: <String>[mediaRoot.path],
      );
      expect(library, isNotNull);

      final firstVideo = File(path.join(mediaRoot.path, 'holiday-first.mp4'));
      await firstVideo.writeAsBytes(const <int>[0]);
      expect(await service.getLibraryFiles(library!.id), <String>[
        firstVideo.path,
      ]);

      final secondVideo = File(path.join(mediaRoot.path, 'holiday-second.mp4'));
      await secondVideo.writeAsBytes(const <int>[0]);

      final refreshedFiles = await service.getLibraryFiles(library.id);
      expect(
        refreshedFiles,
        containsAll(<String>[firstVideo.path, secondVideo.path]),
      );
      expect(refreshedFiles, hasLength(2));
    },
  );
}
