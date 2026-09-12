import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('FFmpeg Thumbnails', () {
    // The sample interleaves more than 30 audio/video packets before the
    // first frame is available after seeking. Counting audio as frames
    // regresses this.
    testWidgets('native FFmpeg decodes interleaved local thumbnails', (
      tester,
    ) async {
      final source = File(
        '${Directory.current.path}/integration_test/samples/file_example_MP4_1920_18MG.mp4',
      );
      expect(source.existsSync(), isTrue);
      final output = await Directory.systemTemp.createTemp(
        'cb_ffmpeg_thumbnail_',
      );
      try {
        for (final percentage in [10.0, 50.0, 90.0]) {
          final target = '${output.path}/$percentage.png';
          final result = await const MethodChannel('fc_native_video_thumbnail')
              .invokeMethod<String>('generateThumbnailAtPercentage', {
                'srcFile': source.path,
                'destFile': target,
                'width': 320,
                'format': 'png',
                'percentage': percentage,
                'quality': 90,
              });
          expect(result, target);
          final codec = await ui.instantiateImageCodec(
            await File(target).readAsBytes(),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThan(100));
          final pixels = await frame.image.toByteData();
          expect(pixels!.buffer.asUint8List().toSet().length, greaterThan(16));
          frame.image.dispose();
          codec.dispose();
        }
      } finally {
        await output.delete(recursive: true);
      }
    }, skip: !Platform.isWindows);
  });
}
