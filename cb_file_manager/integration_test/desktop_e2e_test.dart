// One desktop entrypoint keeps the Flutter/CMake target stable across suite
// filters. Scoped groups preserve each suite's setup/teardown hooks.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_e2e_test.dart' as app;
import 'breadcrumb_address_bar_overflow_e2e_test.dart' as breadcrumb;
import 'e2e_helpers.dart';
import 'ffmpeg_thumbnail_e2e_test.dart' as ffmpeg;
import 'file_drag_drop_e2e_test.dart' as drag_drop;
import 'media_kit_playback_e2e_test.dart' as playback;
import 'semantics_stability_e2e_test.dart' as semantics;
import 'tooltip_semantics_e2e_test.dart' as tooltip;
import 'torrent_library_e2e_test.dart' as torrent;
import 'video_player_chrome_semantics_e2e_test.dart' as video_semantics;
import 'video_thumbnails_e2e_test.dart' as thumbnails;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerE2EAppSandbox();
  group('app', app.main);
  group('video_thumbnails', thumbnails.main);
  group('media_kit_playback', playback.main);
  group('ffmpeg_thumbnail', ffmpeg.main);
  group('file_drag_drop', drag_drop.main);
  group('breadcrumb_address_bar_overflow', breadcrumb.main);
  group('torrent_library', torrent.main);
  group('semantics_stability', semantics.main);
  group('tooltip_semantics', tooltip.main);
  group('video_player_chrome_semantics', video_semantics.main);
}
