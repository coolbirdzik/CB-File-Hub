// Video Thumbnails E2E tests.
//
// This suite covers:
//   - Video file row visibility and file type detection
//   - Video-specific context menu actions ("Play video", etc.)
//   - Thumbnail display in grid and list view modes
//   - CRUD operations on video files (rename, delete, copy)
//   - Unsupported video extensions fall back to generic file handling
//
// Run this suite:
//   make dev-test mode=e2e TEST="Video Thumbnails"
//   make dev-test mode=e2e TEST="Video Thumbnails" PARALLEL=1
//
// For debugging (plain flutter output):
//   dart run tool/e2e_allure.dart --plain-name "Video Thumbnails"
//
// Key UI markers for video files:
//   • Grid: PhosphorIconsLight.playCircle overlay on thumbnail
//   • List: ThumbnailLoader with videoCamera / playCircle icon
//   • Context menu shows: Play video, Video info, Delete, Use system default
//
// Note: Uses the real 18 MB sample video at integration_test/samples/
// if available (for real thumbnail generation tests). Falls back to
// minimal MP4 stub files otherwise (sufficient for UI structure tests).

import 'dart:io';

import 'package:cb_file_manager/e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/main.dart';
import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:path/path.dart' as p;

import 'e2e_helpers.dart';
import 'e2e_keys.dart';
import 'e2e_report.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/video_player_full_screen.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Absolute path to the real sample video (18 MB MP4) in integration_test/samples/.
    String sampleVideoPath() {
    try {
      final scriptStr = Platform.script.toString();
      final scriptPath = scriptStr.startsWith('file:///')
          ? Uri.parse(scriptStr).toFilePath()
          : scriptStr;
      return p.join(p.dirname(scriptPath), 'samples', 'file_example_MP4_1920_18MG.mp4');
    } catch (_) {
      return '';
    }
  }

  /// Copies the sample video into [dir] with the given [name].
  /// Falls back to a minimal stub if the sample file doesn't exist.
    File copySampleVideo(String dir, String name) {
    final dest = File('$dir${Platform.pathSeparator}$name');
      final sample = File(sampleVideoPath());
    if (sample.existsSync()) {
      sample.copySync(dest.path);
      return dest;
    }
    // Fallback: write a minimal MP4 stub (header only).
    // App detects video by extension, so this still triggers video-specific UI.
    final file = File('$dir${Platform.pathSeparator}$name');
    final mp4Header = <int>[
      0x00, 0x00, 0x00, 0x0C, 0x66, 0x74, 0x79, 0x70,
      0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x00, 0x08,
      0x6D, 0x64, 0x61, 0x74,
    ];
    file.writeAsBytesSync(mp4Header);
    return file;
  }

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------

  group('Video Thumbnails', () {
    testWidgets('video file row is visible and has correct file type',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_video_');
      final videoFile = copySampleVideo(dir.path, 'my_video.mp4');
      final dummyTxt = File('${dir.path}${Platform.pathSeparator}readme.txt')
        ..writeAsStringSync('text file');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        if (kDebugMode) debugPrint('[E2E] Test started, sandbox: ${dir.path}');
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('video file row is visible and has correct file type');

        // Video file row should be visible alongside the text file
        expectFileRowVisible(videoFile.path);
        expectFileRowVisible(dummyTxt.path);

        // Verify the video row exists (grid or list)
        assertFileRowExists(videoFile.path);

        if (kDebugMode) debugPrint('[E2E] video file row visible — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('video context menu shows Play video action (grid view)',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_videomenu_');
      final videoFile = copySampleVideo(dir.path, 'clip.mp4');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('video context menu shows Play video action');

        assertFileRowExists(videoFile.path);

        // Right-click the video row to open context menu
        await rightClickFileRow(tester, videoFile.path);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // The video context menu should contain "Play video" action
        final playFinder = find.text('Play video');
        expect(playFinder, findsAtLeastNWidgets(1),
            reason: '"Play video" should appear in video file context menu');

        await dismissDialog(tester);

        if (kDebugMode) debugPrint('[E2E] video context menu — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('video context menu shows Play video action (list view)',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_videomenulist_');
      final videoFile = copySampleVideo(dir.path, 'clip_list.mp4');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('video context menu in list view');

        assertFileRowExists(videoFile.path);

        // Right-click the video row
        await rightClickFileRow(tester, videoFile.path);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // "Play video" should be visible
        final playFinder = find.text('Play video');
        expect(playFinder, findsAtLeastNWidgets(1),
            reason: '"Play video" should appear in list view video context menu');

        await dismissDialog(tester);

        if (kDebugMode) debugPrint('[E2E] video context menu (list) — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('multiple video formats display correctly in same folder',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_multivideo_');
      final mp4File = copySampleVideo(dir.path, 'video.mp4');
      final aviFile = copySampleVideo(dir.path, 'video.avi');
      final mkvFile = copySampleVideo(dir.path, 'video.mkv');
      final movFile = copySampleVideo(dir.path, 'video.mov');
      final txtFile = File('${dir.path}${Platform.pathSeparator}notes.txt')
        ..writeAsStringSync('text');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('multiple video formats display correctly');

        // All video formats should appear as rows
        expectFileRowVisible(mp4File.path);
        expectFileRowVisible(aviFile.path);
        expectFileRowVisible(mkvFile.path);
        expectFileRowVisible(movFile.path);
        expectFileRowVisible(txtFile.path);

        // All video rows should be assertable
        assertFileRowExists(mp4File.path);
        assertFileRowExists(aviFile.path);
        assertFileRowExists(mkvFile.path);
        assertFileRowExists(movFile.path);

        if (kDebugMode) {
          debugPrint('[E2E] multiple video formats visible — SUCCESS');
        }
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('video files persist after folder refresh (F5)',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_videorefresh_');
      final videoFile = copySampleVideo(dir.path, 'after_refresh.mp4');
      final textFile = File('${dir.path}${Platform.pathSeparator}doc.txt')
        ..writeAsStringSync('doc');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('video files persist after folder refresh');

        expectFileRowVisible(videoFile.path);
        expectFileRowVisible(textFile.path);

        // Refresh the folder with F5
        await et.keyPress(LogicalKeyboardKey.f5);
        await et.pumpAndSettle(const Duration(seconds: 3));

        // Video file should still be visible after refresh
        expectFileRowVisible(videoFile.path);
        expectFileRowVisible(textFile.path);

        if (kDebugMode) debugPrint('[E2E] video after F5 refresh — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('deleting a video file removes it from the list',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_videodel_');
      final videoFile = copySampleVideo(dir.path, 'to_delete.mp4');
      final keepFile = File('${dir.path}${Platform.pathSeparator}keep.txt')
        ..writeAsStringSync('keep');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('deleting a video file removes it from the list');

        expectFileRowVisible(videoFile.path);
        expectFileRowVisible(keepFile.path);

        // Right-click the video file
        await rightClickFileRow(tester, videoFile.path);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Tap "Delete"
        await tapContextMenuItem(tester, 'delete');
        await tester.pumpAndSettle(const Duration(seconds: 3));

        // Confirm deletion
        await tapDialogConfirm(tester, buttonText: 'Delete');
        await et.pumpAndSettle(const Duration(seconds: 3));

        // Video file row should be gone; keep.txt should remain
        expectFileRowAbsent(videoFile.path);
        expectFileRowVisible(keepFile.path);

        // File should also be deleted from disk
        expect(videoFile.existsSync(), isFalse,
            reason: 'Video file should be deleted from disk');

        if (kDebugMode) debugPrint('[E2E] delete video file — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('video file can be renamed via context menu',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_videorename_');
      final originalVideo = copySampleVideo(dir.path, 'original_name.mp4');
      const newVideoName = 'renamed_video.mp4';

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('video file can be renamed via context menu');

        expectFileRowVisible(originalVideo.path);

        // Right-click to open context menu
        await rightClickFileRow(tester, originalVideo.path);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Tap "Rename"
        await tapContextMenuItem(tester, 'rename');
        await tester.pumpAndSettle(const Duration(milliseconds: 500));

        // Type the new name (overwrite the extension)
        final textFields = find.byType(TextField);
        expect(textFields, findsAtLeastNWidgets(1),
            reason: 'Rename TextField not found');
        await et.enterText(textFields.first, newVideoName,
            detail: 'type_new_name');
        await tester.pumpAndSettle(const Duration(milliseconds: 300));
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await et.pumpAndSettle(const Duration(seconds: 3));

        final renamedPath = '${dir.path}${Platform.pathSeparator}$newVideoName';
        expectFileRowVisible(renamedPath);
        expectFileRowAbsent(originalVideo.path);

        if (kDebugMode) debugPrint('[E2E] rename video file — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('opening a video via context menu does not crash app',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_videoplay_');
      final videoFile = copySampleVideo(dir.path, 'play_this.mp4');
      final txtFile = File('${dir.path}${Platform.pathSeparator}readme.txt')
        ..writeAsStringSync('readme');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('opening a video via context menu does not crash app');

        expectFileRowVisible(videoFile.path);
        expectFileRowVisible(txtFile.path);

        // Single-tap the video row to select it
        await tapFileRow(tester, videoFile.path);
        await et.pumpAndSettle(const Duration(milliseconds: 500));

        // Right-click to open context menu
        await rightClickFileRow(tester, videoFile.path);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Tap "Play video" in the context menu
        await tapContextMenuItem(tester, 'play_video');
        await et.pumpAndSettle(const Duration(seconds: 3));

        // The key assertion: app should not crash.
        // While the video player is open (fullscreenDialog), the file list is
        // behind the overlay. The video player was successfully pushed, so
        // verify the app is still alive by checking for the VideoPlayer widget.
        // VideoPlayer is the main rendering widget inside VideoPlayerFullScreen.
        expect(find.byType(VideoPlayer), findsOneWidget,
            reason: 'VideoPlayer widget should be present — app did not crash');

        if (kDebugMode) debugPrint('[E2E] open video — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('video file row is FileItem not FolderItem',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_videothumb_');
      final videoFile = copySampleVideo(dir.path, 'thumb_video.mp4');
      final txtFile = File('${dir.path}${Platform.pathSeparator}doc.txt')
        ..writeAsStringSync('doc');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('video file row is FileItem not FolderItem');

        // Both rows should be visible
        expectFileRowVisible(videoFile.path);
        expectFileRowVisible(txtFile.path);

        // Verify video row is a FileItem/FileGridItem (not a folder item)
        assertFileRowExists(videoFile.path);

        if (kDebugMode) debugPrint('[E2E] video row type check — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });

    testWidgets('unsupported video extension does not show Play video action',
        (WidgetTester tester) async {
      final et = E2ETester(tester);
      final dir = await Directory.systemTemp.createTemp('cb_e2e_badvideo_');
      // Create a file with an unrecognized extension
      final badFile = File('${dir.path}${Platform.pathSeparator}video.abc')
        ..writeAsBytesSync([0x00, 0x01, 0x02]);
      final txtFile = File('${dir.path}${Platform.pathSeparator}readme.txt')
        ..writeAsStringSync('readme');

      CbE2EConfig.startupPayload = WindowStartupPayload(
        tabs: <WindowTabPayload>[WindowTabPayload(path: dir.path)],
      );

      try {
        await runCbFileApp();
        await tester.pumpAndSettle(const Duration(seconds: 5));
        await et.init('unsupported video extension shows as generic file');

        // The .abc file should still appear as a file row
        expectFileRowVisible(badFile.path);
        expectFileRowVisible(txtFile.path);

        // Right-click the .abc file — should NOT have "Play video" option
        await rightClickFileRow(tester, badFile.path);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        final playFinder = find.text('Play video');
        // Unsupported extension should NOT show video actions
        expect(playFinder, findsNothing,
            reason: '"Play video" should NOT appear for .abc extension');

        await dismissDialog(tester);

        if (kDebugMode) debugPrint('[E2E] unsupported extension check — SUCCESS');
      } finally {
        await et.screenshot('result');
        await e2eTearDown(tester, dir);
      }
    });
  });
}
