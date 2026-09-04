import 'package:cb_file_manager/helpers/core/path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('smbMrlToUnc', () {
    test('converts an IPv4 SMB URI to a valid UNC path', () {
      expect(
        smbMrlToUnc('smb://192.168.1.210/Reco/video.mkv'),
        r'\\192.168.1.210\Reco\video.mkv',
      );
    });

    test('decodes path segments without changing valid filename characters', () {
      expect(
        smbMrlToUnc(
          'smb://192.168.1.210/Reco/169bbs.com%40CAWD-890_%5B4K%5D.mkv',
        ),
        r'\\192.168.1.210\Reco\169bbs.com@CAWD-890_[4K].mkv',
      );
    });

    test('keeps invalid or non-SMB input unchanged', () {
      expect(smbMrlToUnc('https://example.com/video.mkv'),
          'https://example.com/video.mkv');
    });
  });
}
