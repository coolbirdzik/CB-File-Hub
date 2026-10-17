import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'empty internal trash deletes nested folders and orphan metadata',
    () async {
      final temp = await Directory.systemTemp.createTemp('cb_empty_internal_');
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TempPathProvider(temp.path);
      try {
        final manager = TrashManager();
        final trash = await manager.getTrashDirectory();
        final folder = await Directory(
          p.join(trash.path, 'folder', 'nested'),
        ).create(recursive: true);
        await File(p.join(folder.path, 'file.txt')).writeAsString('nested');
        await File(p.join(trash.path, 'file.txt')).writeAsString('file');
        await manager.saveMetadata({
          'folder': 'original_folder',
          'file.txt': 'original_file',
          'missing.txt': 'orphan',
        });
        final errors = <String>[];
        expect(
          await manager.emptyInternalTrash(
            onError: (path, error) {
              errors.add('$path: $error');
            },
          ),
          isTrue,
        );
        expect(errors, isEmpty);
        expect((await trash.list().toList()).map((e) => p.basename(e.path)), [
          TrashManager.metadataFileName,
        ]);
        expect(
          json.decode(await (await manager.getMetadataFile()).readAsString()),
          isEmpty,
        );
      } finally {
        PathProviderPlatform.instance = previous;
        await temp.delete(recursive: true);
      }
    },
  );
}
