import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileTypeUtils on archive virtual paths', () {
    const archive = r'D:\Code\test-pb.zip';

    test('resolves entry name, extension and type from the inner path', () {
      final entry = ArchivePathUtils.build(
        archiveFile: archive,
        innerPath: 'docs/notes.txt',
      );

      expect(FileTypeUtils.getFileName(entry), 'notes.txt');
      expect(FileTypeUtils.getFileExtension(entry), '.txt');
      expect(FileTypeUtils.getFileNameWithoutExtension(entry), 'notes');
      expect(FileTypeUtils.isTextFile(entry), isTrue);
    });

    test('does not mistake the archive query string for an extension', () {
      final folder = ArchivePathUtils.build(
        archiveFile: archive,
        innerPath: 'test-pb',
      );

      expect(FileTypeUtils.getFileName(folder), 'test-pb');
      expect(FileTypeUtils.getFileExtension(folder), '');
      expect(FileTypeUtils.isArchiveFile(folder), isFalse);
    });
  });

  group('FileTypeUtils.isTextFile', () {
    test('recognizes common code extensions', () {
      expect(FileTypeUtils.isTextFile(r'C:\proj\main.dart'), isTrue);
      expect(FileTypeUtils.isTextFile('/home/app/index.ts'), isTrue);
      expect(FileTypeUtils.isTextFile('/repo/style.css'), isTrue);
      expect(FileTypeUtils.isTextFile('/repo/app.jsx'), isTrue);
      expect(FileTypeUtils.isTextFile('/repo/query.sql'), isTrue);
    });

    test('recognizes plain text extensions', () {
      expect(FileTypeUtils.isTextFile('/docs/readme.md'), isTrue);
      expect(FileTypeUtils.isTextFile('/logs/app.log'), isTrue);
      expect(FileTypeUtils.isTextFile('/data/export.csv'), isTrue);
    });

    test('recognizes extensionless source basenames', () {
      expect(FileTypeUtils.isTextFile('/repo/Makefile'), isTrue);
      expect(FileTypeUtils.isTextFile('/repo/Dockerfile'), isTrue);
    });

    test('rejects binary-like extensions', () {
      expect(FileTypeUtils.isTextFile('/media/photo.jpg'), isFalse);
      expect(FileTypeUtils.isTextFile('/media/video.mp4'), isFalse);
      expect(FileTypeUtils.isTextFile('/backup/archive.zip'), isFalse);
    });
  });

  group('FileTypeUtils.isCodeLikeTextFile', () {
    test('treats source files as code layout', () {
      expect(FileTypeUtils.isCodeLikeTextFile('/proj/main.dart'), isTrue);
      expect(FileTypeUtils.isCodeLikeTextFile('/proj/index.py'), isTrue);
    });

    test('treats plain text as prose layout', () {
      expect(FileTypeUtils.isCodeLikeTextFile('/notes/todo.txt'), isFalse);
      expect(FileTypeUtils.isCodeLikeTextFile('/docs/guide.md'), isFalse);
    });
  });
}
