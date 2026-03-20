import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:flutter/painting.dart' show PaintingBinding;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../services/album_service.dart';
import '../services/windowing/windows_native_tab_drag_drop_service.dart';
import '../services/windowing/window_acrylic_service.dart';
import '../helpers/ui/frame_timing_optimizer.dart';
import '../helpers/media/folder_thumbnail_service.dart';
import '../helpers/media/video_thumbnail_helper.dart';
import '../helpers/media/media_kit_audio_helper.dart';
import '../helpers/tags/batch_tag_manager.dart';
import '../helpers/tags/tag_manager.dart';
import '../core/service_locator.dart';
import '../models/database/database_manager.dart';
import '../services/network_credentials_service.dart';
import 'app_constants.dart';

/// Resolves whether native system backdrop should be dark or light at startup.
Future<bool> resolveInitialNativeBackdropDarkMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('app_theme')?.trim().toLowerCase() ?? '';
    if (stored == 'dark' || stored == 'amoled') return true;
    if (stored == 'light' ||
        stored == 'blue' ||
        stored == 'green' ||
        stored == 'purple' ||
        stored == 'orange') {
      return false;
    }
  } catch (_) {}
  return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;
}

/// Applies desktop window-level configuration (size, title bar, maximize).
Future<void> initializeDesktopWindow({
  required bool isSecondaryWindow,
  required bool isPip,
  required bool startHidden,
  required String windowRole,
}) async {
  if (isPip) return;

  try {
    await windowManager.ensureInitialized();
  } catch (_) {}

  final windowOptions = WindowOptions(
    center: true,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: !Platform.isWindows,
    minimumSize: const Size(windowMinimumWidth, windowMinimumHeight),
  );

  try {
    if (isSecondaryWindow) {
      unawaited(windowManager.waitUntilReadyToShow(windowOptions));
    } else {
      await windowManager.waitUntilReadyToShow(windowOptions);
    }
  } catch (_) {}

  if (!Platform.isWindows) return;

  try {
    await WindowsNativeTabDragDropService.setNativeSystemMenuVisible(false);
  } catch (_) {}

  if (isSecondaryWindow) {
    if (startHidden || windowRole == 'spare') {
      try {
        await windowManager.setSkipTaskbar(true);
        await windowManager.hide();
      } catch (_) {}
    } else {
      try {
        await windowManager.setSkipTaskbar(false);
        await windowManager.show();
        await windowManager.focus();
        await WindowsNativeTabDragDropService.forceActivateWindow();
        unawaited(windowManager.center());
      } catch (_) {}
    }
  } else {
    try {
      await windowManager.maximize();
      await windowManager.show();
      unawaited(windowManager.focus());
      unawaited(windowManager.setResizable(true));
      unawaited(windowManager.setPreventClose(false));
      unawaited(windowManager.setSkipTaskbar(false));
      await WindowsNativeTabDragDropService.setNativeSystemMenuVisible(false);
    } catch (_) {}
  }
}

/// Applies native acrylic/mica backdrop after window is ready.
Future<void> applyDesktopAcrylic({
  required WindowAcrylicService windowAcrylicService,
  required bool isDesktopPlatform,
  required bool isPipWindow,
  required bool isDarkMode,
}) async {
  if (isPipWindow) return;
  try {
    await Future<void>.delayed(acrylicBurstDelayStep);
    await windowAcrylicService.applyDesktopAcrylicBackground(
      isDesktopPlatform: isDesktopPlatform,
      isPipWindow: isPipWindow,
      isDarkMode: isDarkMode,
    );
  } catch (_) {}
}

/// Configures frame timing, Skia cache, and mobile system UI.
Future<void> initializeRenderingAndPerformance({
  required bool isDesktopPlatform,
  required bool isSecondaryWindow,
  required bool isPip,
}) async {
  // Frame timing optimizer
  if (isSecondaryWindow && !isPip) {
    FrameTimingOptimizer().initialize();
  } else {
    await FrameTimingOptimizer().initialize();
  }

  if (isDesktopPlatform) {
    // Increase Skia texture cache for desktop image-heavy workloads
    SystemChannels.skia.invokeMethod<void>(
        'Skia.setResourceCacheMaxBytes', skiaResourceCacheMaxBytes);
  } else if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    SystemChrome.setSystemUIChangeCallback((_) async {});
  }

  // Image cache tuning for scrolling performance
  PaintingBinding.instance.imageCache.maximumSize = imageCacheMaximumSize;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      imageCacheMaximumSizeBytes;

  // Optimize image rendering after first frame
  SchedulerBinding.instance.addPostFrameCallback((_) {
    FrameTimingOptimizer().optimizeImageRendering();
  });
}

/// Initializes MediaKit and Windows-specific audio.
Future<void> initializeMediaKit({
  required bool isSecondaryWindow,
  required bool isPip,
}) async {
  if (isSecondaryWindow && !isPip) {
    MediaKit.ensureInitialized();
  } else {
    MediaKit.ensureInitialized();
  }

  if (Platform.isWindows) {
    if (isSecondaryWindow) {
      debugPrint('Deferred Windows audio configuration for secondary window');
      await MediaKitAudioHelper.initialize();
    } else {
      debugPrint('Setting up Windows-specific audio configuration');
      await MediaKitAudioHelper.initialize();
    }
  }
}

/// Initializes core data services: database, network credentials, and tags.
Future<void> initializeDataAndTags() async {
  try {
    final db = locator<DatabaseManager>();
    if (!db.isInitialized()) {
      await db.initialize();
      debugPrint('Database manager initialized successfully');
    } else {
      debugPrint('Database manager already initialized');
    }
    await locator<NetworkCredentialsService>().init();
    await BatchTagManager.initialize();
    await TagManager.initialize();
    debugPrint('Data and tag services initialized successfully');
  } catch (e) {
    debugPrint('Error during data/tag initialization: $e');
  }
}

/// Initializes heavier background services: thumbnails, albums.
Future<void> initializeHeavyBackgroundServices() async {
  try {
    await locator<FolderThumbnailService>().initialize();
  } catch (e) {
    debugPrint('Error initializing folder thumbnail service: $e');
  }

  try {
    debugPrint('Initializing video thumbnail cache system');
    await VideoThumbnailHelper.initializeCache();
    if (kDebugMode) {
      VideoThumbnailHelper.setVerboseLogging(true);
    }
  } catch (e) {
    debugPrint('Error initializing video thumbnail cache: $e');
  }

  try {
    // ignore: depend_on_referenced_packages
    final albumService = locator<AlbumService>();
    await albumService.initialize();
  } catch (e) {
    debugPrint('Error initializing album service: $e');
  }
}

/// Decodes PiP arguments from the environment.
Map<String, dynamic> decodePipArgs(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return {};
}
