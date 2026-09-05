import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/widgets/lazy_video_thumbnail.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('13 ThumbnailLoader suspend registry', () {
    setUp(() {
      ThumbnailLoader.debugClearSuspendRegistry();
    });

    tearDown(() {
      ThumbnailLoader.debugClearSuspendRegistry();
    });

    test('13.01 paths under a suspended prefix are reported suspended', () {
      ThumbnailLoader.suspendTab('tab1', '/home/user/folder');

      expect(
        ThumbnailLoader.isPathSuspended('/home/user/folder/file.mp4'),
        isTrue,
      );
      expect(
        ThumbnailLoader.isPathSuspended('/home/user/other/file.mp4'),
        isFalse,
      );
    });

    test('13.02 resumeTab clears the suspend marker', () {
      ThumbnailLoader.suspendTab('tab1', '/home/user/folder');
      expect(ThumbnailLoader.debugSuspendedTabCount(), 1);

      ThumbnailLoader.resumeTab('tab1');
      expect(ThumbnailLoader.debugSuspendedTabCount(), 0);
      expect(
        ThumbnailLoader.isPathSuspended('/home/user/folder/file.mp4'),
        isFalse,
      );
    });

    test('13.03 multiple tabs can be suspended independently', () {
      ThumbnailLoader.suspendTab('tab1', '/a');
      ThumbnailLoader.suspendTab('tab2', '/b');
      expect(ThumbnailLoader.debugSuspendedTabCount(), 2);

      expect(ThumbnailLoader.isPathSuspended('/a/file'), isTrue);
      expect(ThumbnailLoader.isPathSuspended('/b/file'), isTrue);

      ThumbnailLoader.resumeTab('tab1');
      expect(ThumbnailLoader.isPathSuspended('/a/file'), isFalse);
      expect(ThumbnailLoader.isPathSuspended('/b/file'), isTrue);
    });

    test('13.04 network paths use forward-slash prefix matching', () {
      ThumbnailLoader.suspendTab('tab1', '#network/host/share/folder');
      expect(
        ThumbnailLoader.isPathSuspended('#network/host/share/folder/file'),
        isTrue,
      );
      expect(
        ThumbnailLoader.isPathSuspended('#network/host/share/other/file'),
        isFalse,
      );
    });

    test('13.05 suspending with empty path clears any existing entry', () {
      ThumbnailLoader.suspendTab('tab1', '/a');
      expect(ThumbnailLoader.debugSuspendedTabCount(), 1);

      ThumbnailLoader.suspendTab('tab1', '');
      expect(ThumbnailLoader.debugSuspendedTabCount(), 0);
    });

    test(
      '13.06 isPathSuspended returns false when registry is empty (fast path)',
      () {
        expect(ThumbnailLoader.debugSuspendedTabCount(), 0);
        expect(ThumbnailLoader.isPathSuspended('anything'), isFalse);
      },
    );

    test('13.07 file thumbnails default to cover', () {
      const imageThumbnail = ThumbnailLoader(
        filePath: 'image.jpg',
        isVideo: false,
        isImage: true,
      );
      const videoThumbnail = LazyVideoThumbnail(
        videoPath: 'video.mp4',
        fallbackBuilder: SizedBox.shrink,
      );

      expect(imageThumbnail.fit, BoxFit.cover);
      expect(videoThumbnail.fit, BoxFit.cover);
      expect(
        UserPreferences.instance.fileThumbnailFitMode.value,
        FileThumbnailFitMode.cover,
      );
    });
  });
}
