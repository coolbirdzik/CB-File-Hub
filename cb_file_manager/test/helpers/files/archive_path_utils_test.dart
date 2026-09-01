import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArchivePathUtils', () {
    test('builds and parses archive browse paths', () {
      const archive = r'C:\data\backup.zip';
      final root = ArchivePathUtils.build(archiveFile: archive);
      expect(ArchivePathUtils.isArchiveBrowsePath(root), isTrue);

      final parsed = ArchivePathUtils.parse(root);
      expect(parsed?.archiveFile, archive);
      expect(parsed?.innerPath, '');

      final nested = ArchivePathUtils.build(
        archiveFile: archive,
        innerPath: 'docs/readme.txt',
      );
      expect(ArchivePathUtils.parse(nested)?.innerPath, 'docs/readme.txt');
      expect(ArchivePathUtils.isArchiveEntryPath(nested), isTrue);
    });

    test('resolves parent paths like Explorer', () {
      const archive = r'C:\data\backup.zip';
      final nested = ArchivePathUtils.build(
        archiveFile: archive,
        innerPath: 'docs/images',
      );
      expect(
        ArchivePathUtils.parentBrowsePath(nested),
        ArchivePathUtils.build(archiveFile: archive, innerPath: 'docs'),
      );
      expect(
        ArchivePathUtils.parentBrowsePath(
          ArchivePathUtils.build(archiveFile: archive, innerPath: 'docs'),
        ),
        ArchivePathUtils.build(archiveFile: archive),
      );
    });

    test('resolves entry labels instead of the raw virtual path', () {
      const archive = r'D:\Code\test-pb.zip';

      expect(
        ArchivePathUtils.entryDisplayName(
          ArchivePathUtils.build(archiveFile: archive, innerPath: 'test-pb'),
        ),
        'test-pb',
      );
      expect(
        ArchivePathUtils.entryDisplayName(
          ArchivePathUtils.build(
            archiveFile: archive,
            innerPath: 'docs/readme.txt',
          ),
        ),
        'readme.txt',
      );
      expect(
        ArchivePathUtils.entryDisplayName(
          ArchivePathUtils.build(archiveFile: archive),
        ),
        'test-pb.zip',
      );
      expect(ArchivePathUtils.entryDisplayName(r'D:\Code\plain.txt'), isNull);
    });
  });
}
