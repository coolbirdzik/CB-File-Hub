import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cb_file_manager/services/archive/archive_format.dart';
import 'package:cb_file_manager/services/archive/archive_service.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('detectArchiveFormat', () {
    test('detects compound tar extensions', () {
      expect(detectArchiveFormat('/tmp/app.tar.gz'), ArchiveFormat.tarGz);
      expect(detectArchiveFormat('/tmp/app.tgz'), ArchiveFormat.tarGz);
      expect(detectArchiveFormat('/tmp/app.tar.bz2'), ArchiveFormat.tarBz2);
      expect(detectArchiveFormat('/tmp/app.7z'), ArchiveFormat.sevenZip);
      expect(detectArchiveFormat('/tmp/app.rar'), ArchiveFormat.rar);
    });
  });

  group('FileTypeUtils.isArchiveFile', () {
    test('recognizes archive extensions including compound forms', () {
      expect(FileTypeUtils.isArchiveFile('/backup/data.zip'), isTrue);
      expect(FileTypeUtils.isArchiveFile('/backup/data.tar.gz'), isTrue);
      expect(FileTypeUtils.isArchiveFile('/backup/data.7z'), isTrue);
      expect(FileTypeUtils.isArchiveFile('/docs/readme.txt'), isFalse);
    });
  });

  // Rust (package:cb_native) when built, and the Dart / 7-Zip fallback.
  for (final useNative in [true, false]) {
    group('ArchiveService (${useNative ? 'native' : 'Dart'})', () {
      late Directory tempDir;
      late ArchiveService service;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('cb_archive_test_');
        service = ArchiveService(useNative: useNative);
      });

      tearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('lists and extracts zip archives', () async {
        final helloFile = File(p.join(tempDir.path, 'hello.txt'));
        helloFile.writeAsStringSync('hello archive');

        final archivePath = p.join(tempDir.path, 'sample.zip');
        final encoder = ZipFileEncoder();
        encoder.create(archivePath);
        encoder.addFileSync(helloFile);
        encoder.closeSync();

        final entries = await service.listEntries(archivePath);
        expect(entries, isNotEmpty);
        expect(entries.any((e) => p.basename(e.name) == 'hello.txt'), isTrue);

        final dest = p.join(tempDir.path, 'out');
        await service.extractAll(
          archivePath: archivePath,
          destinationDir: dest,
        );
        expect(
          File(p.join(dest, 'hello.txt')).readAsStringSync(),
          'hello archive',
        );
      });

      test('lists and extracts tar.gz, single entries and lone .gz', () async {
        final source = Directory(p.join(tempDir.path, 'src'))
          ..createSync(recursive: true);
        final note = File(p.join(source.path, 'note.txt'))
          ..writeAsStringSync('tar content');

        final archive = Archive()
          ..addFile(ArchiveFile.bytes('docs/note.txt', note.readAsBytesSync()));
        final tarGz = File(p.join(tempDir.path, 'bundle.tar.gz'))
          ..writeAsBytesSync(
            const GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive)),
          );

        final entries = await service.listEntries(tarGz.path);
        expect(entries.map((e) => e.name), contains('docs/note.txt'));

        final all = p.join(tempDir.path, 'all');
        final progress = <(int, int)>[];
        await service.extractAll(
          archivePath: tarGz.path,
          destinationDir: all,
          onProgress: (done, total) => progress.add((done, total)),
        );
        expect(
          File(p.join(all, 'docs', 'note.txt')).readAsStringSync(),
          'tar content',
        );

        final single = p.join(tempDir.path, 'single');
        await service.extractEntry(
          archivePath: tarGz.path,
          entryName: 'docs/note.txt',
          destinationDir: single,
        );
        expect(
          File(p.join(single, 'note.txt')).readAsStringSync(),
          'tar content',
        );

        final gz = File(p.join(tempDir.path, 'plain.txt.gz'))
          ..writeAsBytesSync(const GZipEncoder().encodeBytes([104, 105]));
        await service.extractAll(archivePath: gz.path, destinationDir: all);
        expect(File(p.join(all, 'plain.txt')).readAsStringSync(), 'hi');
      });

      test('listDirectory returns sorted direct children per level', () async {
        final source = Directory(p.join(tempDir.path, 'src'))
          ..createSync(recursive: true);
        final rootFile = File(p.join(source.path, 'root.txt'))
          ..writeAsStringSync('root');
        final docFile = File(p.join(source.path, 'alpha.txt'))
          ..writeAsStringSync('alpha');
        final nestedFile = File(p.join(source.path, 'nested.txt'))
          ..writeAsStringSync('nested');

        final archivePath = p.join(tempDir.path, 'nested.zip');
        final encoder = ZipFileEncoder();
        encoder.create(archivePath);
        encoder.addFileSync(rootFile, 'root.txt');
        encoder.addFileSync(docFile, 'docs/alpha.txt');
        encoder.addFileSync(nestedFile, 'docs/sub/nested.txt');
        encoder.closeSync();

        String buildPath({
          required String archiveFile,
          required String innerPath,
          required String entryName,
          required bool isDirectory,
        }) => innerPath;

        final root = await service.listDirectory(
          archiveFilePath: archivePath,
          buildVirtualPath: buildPath,
        );
        expect(root.folders.map((e) => e.path), ['docs']);
        expect(root.files.map((e) => e.path), ['root.txt']);

        final docs = await service.listDirectory(
          archiveFilePath: archivePath,
          innerPath: 'docs',
          buildVirtualPath: buildPath,
        );
        expect(docs.folders.map((e) => e.path), ['docs/sub']);
        expect(docs.files.map((e) => e.path), ['docs/alpha.txt']);
      });
    });
  }
}
