import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../../config/language_controller.dart';
import '../../../config/languages/app_localizations_delegate.dart';
import '../../../config/theme_config.dart';
import '../../../core/service_locator.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/windowing/video_window_service.dart';
import '../../../services/windowing/windows_native_tab_drag_drop_service.dart';
import 'video_player_full_screen.dart';

/// Root of the single dedicated video player window (desktop).
///
/// Later open requests arrive over IPC and replace [_currentPath] while this
/// process and its maximize/fullscreen state remain unchanged.
class VideoWindowApp extends StatefulWidget {
  final String initialPath;

  const VideoWindowApp({super.key, required this.initialPath});

  @override
  State<VideoWindowApp> createState() => _VideoWindowAppState();
}

class _VideoWindowAppState extends State<VideoWindowApp> {
  final LanguageController _languageController = locator<LanguageController>();
  late String _currentPath = widget.initialPath;
  bool _didFitWindow = false;

  @override
  void initState() {
    super.initState();
    _languageController.languageNotifier.addListener(_onLanguageChanged);
    VideoWindowService.startPlayerIpcServer(_playPath);
  }

  @override
  void dispose() {
    _languageController.languageNotifier.removeListener(_onLanguageChanged);
    VideoWindowService.stopPlayerIpcServer();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _playPath(String path) {
    if (!mounted || path.trim().isEmpty) return;
    setState(() => _currentPath = path);
    _bringToFront();
  }

  /// Focuses the player without changing a visible maximized/fullscreen state.
  Future<void> _bringToFront() async {
    try {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
        if (Platform.isWindows) {
          await WindowsNativeTabDragDropService.forceActivateWindow();
        }
      } else if (!await windowManager.isVisible()) {
        await windowManager.show();
      }
      await windowManager.focus();
    } catch (_) {}
  }

  /// Sizes the window to the video's aspect ratio.
  Future<void> _fitWindowToVideo(Map<String, dynamic> metadata) async {
    if (_didFitWindow) return;
    _didFitWindow = true;

    final width = (metadata['width'] as num?)?.toDouble() ?? 0;
    final height = (metadata['height'] as num?)?.toDouble() ?? 0;
    if (width <= 0 || height <= 0) return;

    try {
      if (await windowManager.isMaximized()) return;
      if (await windowManager.isFullScreen()) return;

      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final dpr = view.devicePixelRatio <= 0 ? 1.0 : view.devicePixelRatio;
      final screenWidth = view.display.size.width / dpr;
      final screenHeight = view.display.size.height / dpr;

      final scale = math.min(
        1.0,
        math.min(screenWidth * 0.85 / width, screenHeight * 0.85 / height),
      );
      // 800x600 is the window minimum set at startup; going below it is a no-op.
      final targetWidth = math.max(width * scale, 800.0);
      final targetHeight = math.max(height * scale, 600.0);

      await windowManager.setSize(Size(targetWidth, targetHeight));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeProvider>.value(
      value: locator<ThemeProvider>(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          final isDarkTheme = themeProvider.currentTheme == AppThemeType.dark;
          final lightTheme = isDarkTheme
              ? ThemeConfig.getLightTheme(
                  accentColor: themeProvider.currentAccentColor,
                  fontColor: themeProvider.currentFontColor,
                  uiFont: themeProvider.currentUiFont,
                )
              : themeProvider.themeData;
          final darkTheme = isDarkTheme
              ? themeProvider.themeData
              : ThemeConfig.getDarkTheme(
                  accentColor: themeProvider.currentAccentColor,
                  fontColor: themeProvider.currentFontColor,
                  uiFont: themeProvider.currentUiFont,
                );

          return MaterialApp(
            title: 'CB File Hub',
            debugShowCheckedModeBanner: false,
            theme: lightTheme,
            darkTheme: darkTheme,
            themeMode: themeProvider.themeMode,
            locale: _languageController.currentLocale,
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('vi', ''), Locale('en', '')],
            // Keep the same route/window; VideoPlayerFullScreen updates the
            // source from didUpdateWidget when this path changes.
            home: VideoPlayerFullScreen(
              file: File(_currentPath),
              onVideoMetadata: _fitWindowToVideo,
            ),
          );
        },
      ),
    );
  }
}
