import 'dart:convert';

import 'package:cb_file_manager/services/windowing/video_window_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(VideoWindowService.resetForTesting);

  test('later video reuses the existing player process', () async {
    final launches = <Map<String, String>>[];
    final reuseRequests = <String>[];
    var playerExists = false;
    VideoWindowService.reuseRequesterForTesting = (filePath) async {
      reuseRequests.add(filePath);
      return playerExists;
    };
    VideoWindowService.processLauncherForTesting = ({
      required executable,
      required arguments,
      required environment,
      required workingDirectory,
    }) async {
      launches.add(Map<String, String>.from(environment));
      playerExists = true;
    };

    expect(
      await VideoWindowService.openVideoWindow(
        'C:\\Videos\\one.mp4',
        initiallyMaximized: true,
      ),
      isTrue,
    );
    expect(await VideoWindowService.openVideoWindow('C:\\Videos\\two.mp4'),
        isTrue);

    expect(reuseRequests, <String>[
      r'C:\Videos\one.mp4',
      r'C:\Videos\two.mp4',
    ]);
    expect(launches, hasLength(1));
    expect(
      jsonDecode(launches[0][VideoWindowService.envArgsKey]!)['path'],
      r'C:\Videos\one.mp4',
    );
    expect(
      launches.single[VideoWindowService.envInitiallyMaximizedKey],
      '1',
    );
  });
}
