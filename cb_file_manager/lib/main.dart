import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/tab_manager/core/tab_main_screen.dart';
import 'helpers/tags/tag_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'ui/components/video/pip_window/desktop_pip_window.dart';
import 'helpers/media/media_kit_audio_helper.dart';
import 'helpers/core/user_preferences.dart';
import 'helpers/media/folder_thumbnail_service.dart';
import 'helpers/media/video_thumbnail_helper.dart';
import 'helpers/ui/frame_timing_optimizer.dart';
import 'helpers/tags/batch_tag_manager.dart';
import 'models/database/database_manager.dart';
import 'services/network_credentials_service.dart';
import 'providers/theme_provider.dart';
import 'config/theme_config.dart';
import 'config/fluent_theme_config.dart';
import 'config/design_system_config.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'config/language_controller.dart';
import 'config/languages/app_localizations_delegate.dart';
import 'services/streaming_service_manager.dart';
import 'ui/utils/safe_navigation_wrapper.dart';
import 'ui/utils/desktop_acrylic_backdrop.dart';
import 'core/service_locator.dart';
import 'e2e/cb_e2e_config.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/video_player_full_screen.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'services/windowing/window_startup_payload.dart';
import 'services/windowing/windows_native_tab_drag_drop_service.dart';
import 'services/windowing/window_acrylic_service.dart';
import 'dev/dev_overlay.dart';
// Permission explainer is pushed from TabMainScreen; no direct import needed here

// Global access to test the video thumbnail screen (for development)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Error patterns to suppress (Flutter engine-level noise that doesn't affect functionality)
const List<String> _debugLogSuppressList = <String>[
  'accessibility_bridge.cc', // Windows AXTree update errors
  'Failed to update ui::AXTree',
  'Nodes left pending',
];

/// Launch file path from OS (e.g. double-click when app is default for video)
List<String> _launchPaths = [];

void _handleLaunchFiles() {
  if (_launchPaths.isEmpty) return;
  final p = _launchPaths.removeAt(0);
  if (p.isEmpty) return;
  try {
    final f = File(p);
    if (f.existsSync() && FileTypeUtils.isVideoFile(p)) {
      navigatorKey.currentState?.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => VideoPlayerFullScreen(file: f),
      ));
    }
  } catch (_) {}
}

/// On Android: open video from launch intent (Open with / default app).
Future<void> _handleAndroidLaunchVideo() async {
  if (!Platform.isAndroid) return;
  try {
    final m = await ExternalAppHelper.getLaunchVideoPath();
    final path = m['path'] ?? '';
    final contentUri = m['contentUri'] ?? '';
    if (path.isEmpty && contentUri.isEmpty) return;
    navigatorKey.currentState?.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => path.isNotEmpty
          ? VideoPlayerFullScreen(file: File(path))
          : VideoPlayerFullScreen(contentUri: contentUri),
    ));
  } catch (_) {}
}

bool _shouldSuppressLog(String message) {
  for (final token in _debugLogSuppressList) {
    if (message.contains(token)) {
      return true;
    }
  }
  return false;
}

Future<bool> _resolveInitialNativeBackdropDarkMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final storedTheme = prefs.getString('app_theme')?.trim().toLowerCase();
    if (storedTheme == AppThemeType.dark.name || storedTheme == 'amoled') {
      return true;
    }
    if (storedTheme == AppThemeType.light.name ||
        storedTheme == 'blue' ||
        storedTheme == 'green' ||
        storedTheme == 'purple' ||
        storedTheme == 'orange') {
      return false;
    }
  } catch (_) {}

  return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
      Brightness.dark;
}

void main(List<String> args) {
  _launchPaths = List.from(args);
  runZonedGuarded(() async {
    await runCbFileApp();
  }, (error, stackTrace) {
    debugPrint('Error during app initialization: $error');
  }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) {
    if (!_shouldSuppressLog(line)) {
      parent.print(zone, line);
    }
  }));
}

/// Shared entry for production [main] and for `integration_test` (with `--dart-define=CB_E2E=true`).
Future<void> runCbFileApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // E2E serialization: block until the previous test's teardown is complete.
  // This prevents DirectoryWatcherService from racing against _deleteDirectorySafe().
  if (kCbE2E) {
    await CbE2EConfig.acquireE2ESemaphore();
    try {
      // Reset HardwareKeyboard state between tests.
      // When test A calls sendKeyUpEvent(ctrlLeft) but ctrlLeft was never pressed
      // by the current test, HardwareKeyboard throws an assertion:
      // "A KeyUpEvent is dispatched, but the state shows that the physical key is not pressed."
      // This can happen when the previous test left key state stale.
      // ignore: invalid_use_of_visible_for_testing_member — explicitly intended for
      // test cleanup; prevents stale key state from previous test causing Flutter
      // assertion failures in the next test.
      // ignore: invalid_use_of_visible_for_testing_member
      HardwareKeyboard.instance.clearState(); // NOLINT
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('theme_onboarding_completed_v1', true);
    } catch (_) {}
  }
  final env = Platform.environment;
  final isDesktopPlatform =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  final isSecondaryWindow =
      env[WindowStartupPayload.envSecondaryWindowKey] == '1';
  final startHidden = env[WindowStartupPayload.envStartHiddenKey] == '1';
  final windowRole =
      (env[WindowStartupPayload.envWindowRoleKey] ?? 'normal').trim();
  final isPip = env['CB_PIP_MODE'] == '1';
  final windowAcrylicService = WindowAcrylicService();
  final initialNativeBackdropDarkMode =
      await _resolveInitialNativeBackdropDarkMode();
  final List<Future<void> Function()> deferredSecondaryInitializers = [];

  if (isDesktopPlatform) {
    try {
      await windowManager.ensureInitialized();
    } catch (_) {}

    if (!isPip) {
      final windowOptions = WindowOptions(
        center: true,
        backgroundColor: Colors.transparent,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: !Platform.isWindows,
        minimumSize: const Size(800, 600),
      );

      try {
        if (isSecondaryWindow) {
          unawaited(windowManager.waitUntilReadyToShow(windowOptions));
        } else {
          await windowManager.waitUntilReadyToShow(windowOptions);
        }
      } catch (_) {}

      if (Platform.isWindows) {
        try {
          await WindowsNativeTabDragDropService.setNativeSystemMenuVisible(
            false,
          );
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
            if (!kCbE2E) {
              await windowManager.maximize();
            }
            await windowManager.show();
            unawaited(windowManager.focus());
            unawaited(windowManager.setResizable(true));
            unawaited(windowManager.setPreventClose(false));
            unawaited(windowManager.setSkipTaskbar(false));
            await WindowsNativeTabDragDropService.setNativeSystemMenuVisible(
              false,
            );
          } catch (_) {}
        }
      }
    }

    if (!isPip && !kCbE2EFast) {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await windowAcrylicService.applyDesktopAcrylicBackground(
          isDesktopPlatform: isDesktopPlatform,
          isPipWindow: isPip,
          isDarkMode: initialNativeBackdropDarkMode,
        );
      } catch (_) {}
    }
  }

  // Configure frame timing and rendering for better performance
  if (isSecondaryWindow && !isPip) {
    try {
      await FrameTimingOptimizer().initialize();
    } catch (_) {}
  } else {
    try {
      await FrameTimingOptimizer().initialize();
    } catch (_) {}
  }

  // Platform-specific optimizations
  if (isDesktopPlatform) {
    SystemChannels.skia
        .invokeMethod<void>('Skia.setResourceCacheMaxBytes', 512 * 1024 * 1024);
  } else if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    SystemChrome.setSystemUIChangeCallback((systemOverlaysAreVisible) async {
      return;
    });
  }

  SchedulerBinding.instance.addPostFrameCallback((_) {
    FrameTimingOptimizer().optimizeImageRendering();
  });

  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 * 1024 * 1024;

  // Initialize Media Kit with proper audio configuration
  MediaKit.ensureInitialized();

  // Initialize our audio helper to ensure sound works
  if (Platform.isWindows && !kCbE2EFast) {
    if (isSecondaryWindow) {
      deferredSecondaryInitializers.add(() async {
        debugPrint('Deferred Windows audio configuration for secondary window');
        await MediaKitAudioHelper.initialize();
      });
    } else {
      debugPrint('Setting up Windows-specific audio configuration');
      await MediaKitAudioHelper.initialize();
    }
  }

  // Initialize streaming service manager
  if (!kCbE2EFast) {
    if (isSecondaryWindow) {
      deferredSecondaryInitializers.add(() async {
        await StreamingServiceManager.initialize();
      });
    } else {
      await StreamingServiceManager.initialize();
    }
  }

  await setupServiceLocator();
  debugPrint('Service locator initialized successfully');

  // Initialize preferences first for theme and language.
  if (isSecondaryWindow && !isPip) {
    deferredSecondaryInitializers.add(() async {
      try {
        final preferences = locator<UserPreferences>();
        await preferences.init();
        debugPrint('Deferred user preferences initialization completed');
      } catch (e) {
        debugPrint('Error initializing user preferences: $e');
      }
    });
    deferredSecondaryInitializers.add(() async {
      await locator<LanguageController>().initialize();
    });
  } else {
    try {
      final preferences = locator<UserPreferences>();
      await preferences.init();
      debugPrint('User preferences initialized successfully');
    } catch (e) {
      debugPrint('Error initializing user preferences: $e');
    }

    await locator<LanguageController>().initialize();
    if (kCbE2E) {
      try {
        await locator<UserPreferences>().setRememberTabWorkspaceEnabled(false);
      } catch (_) {}
    }
  }

  Future<void> initializeDataAndTags() async {
    try {
      final dbManager = locator<DatabaseManager>();
      if (!dbManager.isInitialized()) {
        await dbManager.initialize();
        debugPrint('Database manager initialized successfully');
      } else {
        debugPrint('Database manager already initialized');
      }
      final networkCredService = locator<NetworkCredentialsService>();
      await networkCredService.init();

      await BatchTagManager.initialize();
      await TagManager.initialize();
      debugPrint('Data and tag services initialized successfully');
    } catch (e) {
      debugPrint('Error during data/tag initialization: $e');
    }
  }

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
      await locator<AlbumService>().initialize();
    } catch (e) {
      debugPrint('Error initializing album service: $e');
    }
  }

  if (isSecondaryWindow) {
    deferredSecondaryInitializers.add(initializeDataAndTags);
    if (!kCbE2EFast) {
      deferredSecondaryInitializers.add(initializeHeavyBackgroundServices);
    }
  } else {
    await initializeDataAndTags();
    if (!kCbE2EFast) {
      await initializeHeavyBackgroundServices();
    }
  }

  if (env['CB_PIP_MODE'] == '1' &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    Map<String, dynamic> args = {};
    final raw = env['CB_PIP_ARGS'];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) args = decoded;
      } catch (_) {}
    }
    runApp(MaterialApp(
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      debugShowCheckedModeBanner: false,
      home: DesktopPipWindow(args: args),
    ));
    return;
  }

  final WindowStartupPayload? startupPayload =
      kCbE2E && CbE2EConfig.startupPayload != null
          ? CbE2EConfig.startupPayload
          : WindowStartupPayload.fromEnvironment();
  runApp(
    ChangeNotifierProvider(
      create: (context) => locator<ThemeProvider>(),
      child: CBFileApp(
        startupPayload: startupPayload,
        windowAcrylicService: windowAcrylicService,
      ),
    ),
  );

  if (isSecondaryWindow && deferredSecondaryInitializers.isNotEmpty) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final initializer in deferredSecondaryInitializers) {
        unawaited(initializer());
      }
    });
  }
}

// Navigate directly to home screen - updated to use the tabbed interface
void goHome(BuildContext context) {
  try {
    if (!context.mounted) {
      debugPrint('Context not mounted, cannot navigate');
      return;
    }

    final route = MaterialPageRoute(
      builder: (_) => const TabMainScreen(),
    );

    Navigator.of(context, rootNavigator: true)
        .pushAndRemoveUntil(route, (r) => false);
  } catch (e) {
    debugPrint('Error navigating home: $e');
    runApp(CBFileApp(
      windowAcrylicService: WindowAcrylicService(),
    ));
  }
}

class CBFileApp extends StatefulWidget {
  final WindowStartupPayload? startupPayload;
  final WindowAcrylicService windowAcrylicService;
  const CBFileApp({
    Key? key,
    this.startupPayload,
    required this.windowAcrylicService,
  }) : super(key: key);

  @override
  State<CBFileApp> createState() => _CBFileAppState();
}

class _CBFileAppState extends State<CBFileApp>
    with WidgetsBindingObserver, WindowListener {
  final LanguageController _languageController = locator<LanguageController>();
  int _acrylicSyncGeneration = 0;
  bool? _lastAppliedNativeBackdropDarkMode;
  AcrylicBackdropMode? _lastBackdropMode;
  ValueNotifier<Locale>? _localeNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) {
      windowManager.addListener(this);
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      FrameTimingOptimizer().optimizeBeforeHeavyOperation();
    });

    if (Platform.isWindows) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _handleLaunchFiles();
      });
    }
    if (Platform.isAndroid) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _handleAndroidLaunchVideo();
      });
    }

    _localeNotifier = _languageController.languageNotifier;
    _localeNotifier?.addListener(() {
      setState(() {});
    });

    if (_useDesktopAcrylicVisuals) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final themeProvider = context.read<ThemeProvider>();
        _triggerAcrylicReapplyBurst(
          includeImmediate: true,
          forcedIsDarkMode: _resolveNativeBackdropDarkMode(themeProvider),
        );
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      _handleAndroidLaunchVideo();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _localeNotifier?.removeListener(() {});
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (!mounted) return;
    _triggerAcrylicReapplyBurst(
      includeImmediate: true,
      forcedIsDarkMode:
          _resolveNativeBackdropDarkMode(context.read<ThemeProvider>()),
    );
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted) return;
    _triggerAcrylicReapplyBurst(
      includeImmediate: true,
      forcedIsDarkMode:
          _resolveNativeBackdropDarkMode(context.read<ThemeProvider>()),
    );
  }

  @override
  void onWindowRestore() {
    if (!mounted) return;
    _triggerAcrylicReapplyBurst(
      includeImmediate: true,
      forcedIsDarkMode:
          _resolveNativeBackdropDarkMode(context.read<ThemeProvider>()),
    );
  }

  bool get _useDesktopFluentShell =>
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      DesignSystemConfig.enableFluentDesktopShell &&
      !DesignSystemConfig.enableLegacyMaterialDesktopShell;

  bool get _useDesktopAcrylicVisuals =>
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      DesignSystemConfig.enableDesktopAcrylicWindowBackground;

  ThemeData _resolveMaterialLightTheme(ThemeProvider provider) {
    final isDarkTheme = provider.currentTheme == AppThemeType.dark;
    return isDarkTheme
        ? ThemeConfig.getLightTheme(accentColor: provider.currentAccentColor)
        : provider.themeData;
  }

  ThemeData _resolveMaterialDarkTheme(ThemeProvider provider) {
    final isDarkTheme = provider.currentTheme == AppThemeType.dark;
    return isDarkTheme
        ? provider.themeData
        : ThemeConfig.getDarkTheme(accentColor: provider.currentAccentColor);
  }

  fluent.FluentThemeData _resolveFluentLightTheme(ThemeProvider provider) {
    final isDarkTheme = provider.currentTheme == AppThemeType.dark;
    return isDarkTheme
        ? FluentThemeConfig.getTheme(
            AppThemeType.light,
            accentColor: provider.currentAccentColor,
            acrylicStrength: provider.desktopAcrylicStrength,
          )
        : provider.fluentThemeData;
  }

  fluent.FluentThemeData _resolveFluentDarkTheme(ThemeProvider provider) {
    final isDarkTheme = provider.currentTheme == AppThemeType.dark;
    return isDarkTheme
        ? provider.fluentThemeData
        : FluentThemeConfig.getTheme(
            AppThemeType.dark,
            accentColor: provider.currentAccentColor,
            acrylicStrength: provider.desktopAcrylicStrength,
          );
  }

  ThemeData _createDesktopAcrylicMaterialBridgeTheme(
    ThemeData baseTheme,
    Brightness brightness,
    double strength,
  ) {
    final double normalizedStrength = strength.clamp(0.0, 2.0).toDouble();
    final bool isLightMode = brightness == Brightness.light;
    const Color fluentLightBackground2 = Color(0xFFF3F4F7);
    const Color fluentLightBackground3 = Color(0xFFFFFFFF);

    double opacityByStrength({
      required double solidAtMin,
      required double glassAtMax,
    }) {
      return solidAtMin + (glassAtMax - solidAtMin) * normalizedStrength;
    }

    final scaffoldOpacity = brightness == Brightness.dark
        ? opacityByStrength(solidAtMin: 0.90, glassAtMax: 0.34)
        : opacityByStrength(solidAtMin: 0.99, glassAtMax: 0.92);
    final appBarOpacity = brightness == Brightness.dark
        ? opacityByStrength(solidAtMin: 0.94, glassAtMax: 0.46)
        : opacityByStrength(solidAtMin: 0.99, glassAtMax: 0.93);
    final surfaceOpacity = brightness == Brightness.dark
        ? opacityByStrength(solidAtMin: 0.88, glassAtMax: 0.40)
        : opacityByStrength(solidAtMin: 0.99, glassAtMax: 0.90);
    final containerOpacity = brightness == Brightness.dark
        ? opacityByStrength(solidAtMin: 0.84, glassAtMax: 0.36)
        : opacityByStrength(solidAtMin: 0.98, glassAtMax: 0.88);
    final lowContainerOpacity = brightness == Brightness.dark
        ? opacityByStrength(solidAtMin: 0.80, glassAtMax: 0.32)
        : opacityByStrength(solidAtMin: 0.98, glassAtMax: 0.86);
    final lowestContainerOpacity = brightness == Brightness.dark
        ? opacityByStrength(solidAtMin: 0.76, glassAtMax: 0.28)
        : opacityByStrength(solidAtMin: 0.97, glassAtMax: 0.84);

    final colorScheme = baseTheme.colorScheme;
    const Color lightSurfaceBase = fluentLightBackground3;
    const Color lightContainerBase = fluentLightBackground2;
    final Color effectiveSurfaceBase =
        isLightMode ? lightSurfaceBase : colorScheme.surface;
    final Color effectiveContainerBase =
        isLightMode ? lightContainerBase : colorScheme.surfaceContainer;

    final bridgedColorScheme = colorScheme.copyWith(
      surface: effectiveSurfaceBase.withValues(alpha: surfaceOpacity),
      surfaceBright:
          (isLightMode ? lightSurfaceBase : colorScheme.surfaceBright)
              .withValues(alpha: surfaceOpacity),
      surfaceDim: (isLightMode ? lightContainerBase : colorScheme.surfaceDim)
          .withValues(alpha: surfaceOpacity),
      surfaceContainer:
          effectiveContainerBase.withValues(alpha: containerOpacity),
      surfaceContainerHigh:
          effectiveContainerBase.withValues(alpha: containerOpacity),
      surfaceContainerHighest:
          effectiveContainerBase.withValues(alpha: containerOpacity),
      surfaceContainerLow:
          effectiveSurfaceBase.withValues(alpha: lowContainerOpacity),
      surfaceContainerLowest:
          effectiveSurfaceBase.withValues(alpha: lowestContainerOpacity),
      inverseSurface:
          colorScheme.inverseSurface.withValues(alpha: surfaceOpacity),
      surfaceTint: Colors.transparent,
    );

    final cardColor =
        effectiveContainerBase.withValues(alpha: containerOpacity);
    final dialogColor = effectiveContainerBase;
    final menuColor =
        effectiveContainerBase.withValues(alpha: containerOpacity);

    return baseTheme.copyWith(
      colorScheme: bridgedColorScheme,
      scaffoldBackgroundColor:
          baseTheme.scaffoldBackgroundColor.withValues(alpha: scaffoldOpacity),
      canvasColor: baseTheme.canvasColor.withValues(alpha: scaffoldOpacity),
      cardColor: cardColor,
      cardTheme: baseTheme.cardTheme.copyWith(
        color: cardColor,
      ),
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: dialogColor,
      ),
      popupMenuTheme: baseTheme.popupMenuTheme.copyWith(
        color: menuColor,
      ),
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: dialogColor,
        modalBackgroundColor: dialogColor,
      ),
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: (baseTheme.appBarTheme.backgroundColor ??
                baseTheme.scaffoldBackgroundColor)
            .withValues(alpha: appBarOpacity),
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  bool _resolveNativeBackdropDarkMode(ThemeProvider provider) {
    if (provider.themeMode == ThemeMode.dark) {
      return true;
    }
    if (provider.themeMode == ThemeMode.light) {
      return provider.currentTheme == AppThemeType.dark;
    }
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  void _triggerAcrylicReapplyBurst({
    bool includeImmediate = false,
    bool? forcedIsDarkMode,
  }) {
    if (!Platform.isWindows || !_useDesktopAcrylicVisuals) return;
    final themeProvider = context.read<ThemeProvider>();
    if (themeProvider.isWallpaperMode) {
      _disableNativeBackdrop();
      return;
    }
    final bool isDarkMode =
        forcedIsDarkMode ?? _resolveNativeBackdropDarkMode(themeProvider);
    _lastAppliedNativeBackdropDarkMode = isDarkMode;

    final int generation = ++_acrylicSyncGeneration;
    final List<int> delaysMs = <int>[
      if (includeImmediate) 0,
      80,
      180,
      320,
      560,
    ];

    for (final int delayMs in delaysMs) {
      unawaited(
        Future<void>.delayed(Duration(milliseconds: delayMs), () async {
          if (!mounted || generation != _acrylicSyncGeneration) return;
          if (Platform.isWindows) {
            try {
              await WindowsNativeTabDragDropService.setNativeSystemMenuVisible(
                false,
              );
            } catch (_) {}
          }
          try {
            await widget.windowAcrylicService.applyDesktopAcrylicBackground(
              isDesktopPlatform: true,
              isPipWindow: false,
              isDarkMode: isDarkMode,
            );
          } catch (_) {}
        }),
      );
    }
  }

  void _disableNativeBackdrop() {
    if (!Platform.isWindows) return;
    unawaited(
      WindowsNativeTabDragDropService.setWindowsSystemBackdrop(
        enabled: false,
      ),
    );
  }

  Widget _buildMaterialHostApp(ThemeProvider themeProvider) {
    final lightTheme = _resolveMaterialLightTheme(themeProvider);
    final darkTheme = _resolveMaterialDarkTheme(themeProvider);
    final acrylicStrength = themeProvider.desktopAcrylicStrength;
    final resolvedLightTheme = _useDesktopAcrylicVisuals
        ? _createDesktopAcrylicMaterialBridgeTheme(
            lightTheme,
            Brightness.light,
            acrylicStrength,
          )
        : lightTheme;
    final resolvedDarkTheme = _useDesktopAcrylicVisuals
        ? _createDesktopAcrylicMaterialBridgeTheme(
            darkTheme,
            Brightness.dark,
            acrylicStrength,
          )
        : darkTheme;

    return MaterialApp(
      title: 'CB File Hub',
      home: TabMainScreen(startupPayload: widget.startupPayload),
      navigatorKey: navigatorKey,
      theme: resolvedLightTheme,
      darkTheme: resolvedDarkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      locale: _languageController.currentLocale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('vi', ''),
        Locale('en', ''),
      ],
      builder: (context, child) {
        final wrappedChild = child ?? const SizedBox.shrink();
        if (!_useDesktopAcrylicVisuals) return wrappedChild;
        return DesktopAcrylicBackdrop(
          brightness: Theme.of(context).brightness,
          child: wrappedChild,
        );
      },
    );
  }

  Widget _buildFluentHostApp(ThemeProvider themeProvider) {
    return fluent.FluentApp(
      title: 'CB File Hub',
      home: TabMainScreen(startupPayload: widget.startupPayload),
      navigatorKey: navigatorKey,
      theme: _resolveFluentLightTheme(themeProvider),
      darkTheme: _resolveFluentDarkTheme(themeProvider),
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      locale: _languageController.currentLocale,
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        fluent.FluentLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('vi', ''),
        Locale('en', ''),
      ],
      builder: (context, child) {
        // FluentApp does not insert [ScaffoldMessenger]; MaterialApp does. Several
        // screens (e.g. [TabbedFolderListScreen]) and [NavigationController] use
        // [ScaffoldMessenger.of] for snackbars — wrap so those lookups succeed.
        final shell = ScaffoldMessenger(
          child: child ?? const SizedBox.shrink(),
        );
        final brightness = fluent.FluentTheme.of(context).brightness;
        final resolvedTheme = brightness == Brightness.dark
            ? _resolveMaterialDarkTheme(themeProvider)
            : _resolveMaterialLightTheme(themeProvider);
        if (!_useDesktopAcrylicVisuals) {
          return shell;
        }
        final materialTheme = _createDesktopAcrylicMaterialBridgeTheme(
          resolvedTheme,
          brightness,
          themeProvider.desktopAcrylicStrength,
        );

        return Theme(
          data: materialTheme,
          child: DesktopAcrylicBackdrop(
            brightness: brightness,
            child: shell,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final bool isDarkMode = _resolveNativeBackdropDarkMode(themeProvider);
    final backdropMode = themeProvider.backdropMode;

    if (_useDesktopAcrylicVisuals && Platform.isWindows) {
      final modeChanged =
          _lastBackdropMode != null && _lastBackdropMode != backdropMode;
      final darkModeChanged = _lastAppliedNativeBackdropDarkMode != isDarkMode;

      if (modeChanged || darkModeChanged) {
        _lastAppliedNativeBackdropDarkMode = isDarkMode;
        _lastBackdropMode = backdropMode;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _triggerAcrylicReapplyBurst(
            includeImmediate: true,
            forcedIsDarkMode: isDarkMode,
          );
        });
      }
      _lastBackdropMode ??= backdropMode;
    }

    final appContent = SafeNavigationWrapper(
      child: _useDesktopFluentShell
          ? _buildFluentHostApp(themeProvider)
          : _buildMaterialHostApp(themeProvider),
    );
    final app =
        isDevOverlayEnabled ? DevOverlay(child: appContent) : appContent;

    if (Platform.isWindows) {
      return ExcludeSemantics(child: app);
    }
    return app;
  }
}
