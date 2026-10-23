import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final isVideo in [false, true]) {
    test('device paths round-trip opaque album IDs (video: $isVideo)', () {
      for (final id in <String?>[null, 'camera', 'a/b +%2F?ảnh&東京']) {
        final location = DeviceMediaPath(isVideo: isVideo, albumId: id);
        final parsed = DeviceMediaPath.tryParse(location.path)!;
        expect(parsed.isVideo, isVideo);
        expect(parsed.albumId, id);
        expect(parsed.path, location.path);
        expect(parsed.parentPath, isVideo ? '#video' : '#gallery');
      }
    });
  }

  test('unrelated and malformed paths are rejected', () {
    for (final path in [
      '#gallery',
      '#video',
      '#gallery/device-other',
      '#album/5',
      '#gallery/device?album=',
      '#video/device?album=%ZZ',
    ]) {
      expect(DeviceMediaPath.tryParse(path), isNull, reason: path);
    }
  });
}
