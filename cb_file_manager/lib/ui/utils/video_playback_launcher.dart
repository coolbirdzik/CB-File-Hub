import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/service_locator.dart';
import '../../helpers/core/user_preferences.dart';
import '../../services/windowing/video_window_service.dart';
import '../screens/media_gallery/video_player_full_screen.dart';
import 'app_busy_cursor.dart';

/// Opens the built-in video player, honouring the desktop
/// "open the player in a new window" preference.
class VideoPlaybackLauncher {
  VideoPlaybackLauncher._();

  /// [onClosed] runs when the player is dismissed (in-window mode) or right
  /// after the separate window was launched (new-window mode).
  ///
  /// [inNewWindow] skips the preference read when the caller already has it.
  static Future<void> open(
    BuildContext context, {
    File? file,
    String? contentUri,
    VoidCallback? onClosed,
    bool forceNewWindow = false,
    bool? inNewWindow,
  }) async {
    assert(file != null || (contentUri != null && contentUri.isNotEmpty));

    if (file != null && VideoWindowService.isSupported) {
      // Independent lookups: issue them together rather than one round trip
      // after another before the player can be reused or spawned.
      final (useNewWindow, parentIsMaximized, parentWindowId) = await (
        inNewWindow != null
            ? Future<bool>.value(inNewWindow)
            : locator<UserPreferences>().getOpenVideoInNewWindow().catchError(
                (_) => true,
              ),
        windowManager.isMaximized().catchError((_) => false),
        windowManager.getId().then<int?>((id) => id).catchError((_) => null),
      ).wait;

      if (useNewWindow || forceNewWindow) {
        final launched = await AppBusyCursor.run(
          () => VideoWindowService.openVideoWindow(
            file.path,
            initiallyMaximized: parentIsMaximized,
            parentWindowId: parentWindowId,
          ),
        );
        if (launched) {
          onClosed?.call();
          return;
        }
        // Falls through to the in-window player when spawning failed.
      }
    }

    if (!context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            VideoPlayerFullScreen(file: file, contentUri: contentUri),
      ),
    );
    onClosed?.call();
  }
}
