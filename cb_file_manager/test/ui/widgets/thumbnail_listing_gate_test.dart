import 'package:cb_file_manager/ui/widgets/thumbnail_listing_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'overlapping scans release independently and only block their folder',
    () async {
      final gate = ThumbnailListingGate();
      final folder = path.absolute('first');
      final source = path.join(folder, 'photo.jpg');
      final releaseFirst = gate.pause(folder: folder);
      final releaseSecond = gate.pause(folder: folder);
      var called = 0;
      gate.whenReady(() => called++, source: source);
      expect(gate.isReadyFor(path.absolute('other', 'photo.jpg')), isTrue);
      expect(gate.isReadyFor(source), isFalse);
      releaseFirst();
      releaseFirst();
      await Future<void>.delayed(Duration.zero);
      expect(called, 0);
      releaseSecond();
      await Future<void>.delayed(Duration.zero);
      expect(called, 1);
      expect(gate.isReady, isTrue);
    },
  );

  test(
    'a new scan before callbacks flush keeps its thumbnails deferred',
    () async {
      final gate = ThumbnailListingGate();
      final folder = path.absolute('folder');
      final source = path.join(folder, 'video.mp4');
      var called = false;
      final release = gate.pause(folder: folder);
      gate.whenReady(() => called = true, source: source);
      release();
      final releaseNewScan = gate.pause(folder: folder);
      await Future<void>.delayed(Duration.zero);
      expect(called, isFalse);
      releaseNewScan();
      await Future<void>.delayed(Duration.zero);
      expect(called, isTrue);
    },
  );

  test('legacy readiness cannot unlock an active listing token', () async {
    final gate = ThumbnailListingGate();
    final release = gate.pause();
    gate.setLegacyReady(false);
    gate.setLegacyReady(true);
    expect(gate.isReady, isFalse);
    release();
    expect(gate.isReady, isTrue);
  });
}
