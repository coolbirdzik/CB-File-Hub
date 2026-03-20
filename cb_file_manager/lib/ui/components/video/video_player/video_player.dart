// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart' hide SubtitleTrack;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player/video_player.dart' as exo;
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as pathlib;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:gal/gal.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/image_viewer_screen.dart';
// Windows PiP uses a separate OS window (external process).

import '../../../../services/pip_window_service.dart';
import '../pip_window/windows_pip_overlay.dart';
import '../../../../services/streaming/smb_http_proxy_server.dart';
import 'package:cb_file_manager/ui/state/video_ui_state.dart';

import '../../../../helpers/files/file_type_registry.dart';
import '../../../../helpers/core/user_preferences.dart';
import '../../../../helpers/network/win32_smb_helper.dart';
import '../../streaming/stream_speed_indicator.dart';
import '../../streaming/buffer_info_widget.dart';
import '../../../utils/route.dart';
import '../../../../config/languages/app_localizations.dart';
import '../../../tab_manager/core/tab_manager.dart';
import 'video_player_advanced_menu.dart';
import 'video_player_control_buttons.dart';
import 'video_player_dialogs.dart';
import 'video_player_fast_seek.dart';
import 'video_player_loading.dart';
import 'video_player_models.dart';
import 'video_player_seek_slider.dart';
import 'video_player_utils.dart';

part 'video_player.volume.dart';
part 'video_player.vlc_smb.dart';

/// Unified video player component supporting multiple media sources
/// Consolidates functionality from CustomVideoPlayer and StreamingMediaPlayer
class VideoPlayer extends StatefulWidget {
  // Media source properties
  final File? file;
  final String? streamingUrl;
  final String? smbMrl;
  final Stream<List<int>>? fileStream;

  // Media metadata
  final String fileName;
  final FileCategory? fileType;

  // Playback configuration
  final bool autoPlay;
  final bool looping;
  final bool showControls;
  final bool allowFullScreen;
  final bool allowMuting;
  final bool allowPlaybackSpeedChanging;

  // Callback functions
  final Function(Map<String, dynamic>)? onVideoInitialized;
  final Function(String)? onError;
  final VoidCallback? onNextVideo;
  final VoidCallback? onPreviousVideo;
  final VoidCallback? onClose;
  final VoidCallback? onControlVisibilityChanged;
  final VoidCallback? onFullScreenChanged;
  final VoidCallback? onInitialized;
  final Function(String folderPath, String highlightedFileName)? onOpenFolder;

  // Navigation state
  final bool hasNextVideo;
  final bool hasPreviousVideo;

  // UI configuration
  final bool showStreamingSpeed;
  final VoidCallback? onToggleStreamingSpeed;

  const VideoPlayer._({
    Key? key,
    this.file,
    this.streamingUrl,
    this.smbMrl,
    this.fileStream,
    required this.fileName,
    this.fileType,
    this.autoPlay = true,
    this.looping = false,
    this.showControls = true,
    this.allowFullScreen = true,
    this.allowMuting = true,
    this.allowPlaybackSpeedChanging = true,
    this.onVideoInitialized,
    this.onError,
    this.onNextVideo,
    this.onPreviousVideo,
    this.onClose,
    this.onControlVisibilityChanged,
    this.onFullScreenChanged,
    this.onInitialized,
    this.onOpenFolder,
    this.hasNextVideo = false,
    this.hasPreviousVideo = false,
    this.showStreamingSpeed = false,
    this.onToggleStreamingSpeed,
  })  : assert(
          file != null ||
              streamingUrl != null ||
              smbMrl != null ||
              fileStream != null,
          'At least one media source must be provided',
        ),
        super(key: key);

  /// Constructor for local file playback
  VideoPlayer.file({
    Key? key,
    required File file,
    bool autoPlay = true,
    bool looping = false,
    bool showControls = true,
    bool allowFullScreen = true,
    bool allowMuting = true,
    bool allowPlaybackSpeedChanging = true,
    Function(Map<String, dynamic>)? onVideoInitialized,
    Function(String)? onError,
    VoidCallback? onNextVideo,
    VoidCallback? onPreviousVideo,
    VoidCallback? onControlVisibilityChanged,
    VoidCallback? onFullScreenChanged,
    VoidCallback? onInitialized,
    Function(String folderPath, String highlightedFileName)? onOpenFolder,
    bool hasNextVideo = false,
    bool hasPreviousVideo = false,
    bool showStreamingSpeed = false,
    VoidCallback? onToggleStreamingSpeed,
  }) : this._(
          key: key,
          file: file,
          fileName: pathlib.basename(file.path),
          fileType: FileTypeRegistry.getCategory(
              VideoPlayerUtils.extensionFromPath(file.path)),
          autoPlay: autoPlay,
          looping: looping,
          showControls: showControls,
          allowFullScreen: allowFullScreen,
          allowMuting: allowMuting,
          allowPlaybackSpeedChanging: allowPlaybackSpeedChanging,
          onVideoInitialized: onVideoInitialized,
          onError: onError,
          onNextVideo: onNextVideo,
          onPreviousVideo: onPreviousVideo,
          onControlVisibilityChanged: onControlVisibilityChanged,
          onFullScreenChanged: onFullScreenChanged,
          onInitialized: onInitialized,
          onOpenFolder: onOpenFolder,
          hasNextVideo: hasNextVideo,
          hasPreviousVideo: hasPreviousVideo,
          showStreamingSpeed: showStreamingSpeed,
          onToggleStreamingSpeed: onToggleStreamingSpeed,
        );

  /// Constructor for streaming URL playback
  VideoPlayer.url({
    Key? key,
    required String streamingUrl,
    required String fileName,
    FileCategory? fileType,
    bool autoPlay = true,
    bool looping = false,
    bool showControls = true,
    bool allowFullScreen = true,
    bool allowMuting = true,
    bool allowPlaybackSpeedChanging = true,
    Function(Map<String, dynamic>)? onVideoInitialized,
    Function(String)? onError,
    VoidCallback? onClose,
    VoidCallback? onControlVisibilityChanged,
    VoidCallback? onFullScreenChanged,
    VoidCallback? onInitialized,
    bool showStreamingSpeed = false,
    VoidCallback? onToggleStreamingSpeed,
  }) : this._(
          key: key,
          streamingUrl: streamingUrl,
          fileName: fileName,
          fileType: fileType ??
              FileTypeRegistry.getCategory(
                  VideoPlayerUtils.extensionFromPath(fileName)),
          autoPlay: autoPlay,
          looping: looping,
          showControls: showControls,
          allowFullScreen: allowFullScreen,
          allowMuting: allowMuting,
          allowPlaybackSpeedChanging: allowPlaybackSpeedChanging,
          onVideoInitialized: onVideoInitialized,
          onError: onError,
          onClose: onClose,
          onControlVisibilityChanged: onControlVisibilityChanged,
          onFullScreenChanged: onFullScreenChanged,
          onInitialized: onInitialized,
          showStreamingSpeed: showStreamingSpeed,
          onToggleStreamingSpeed: onToggleStreamingSpeed,
        );

  /// Constructor for SMB MRL playback
  VideoPlayer.smb({
    Key? key,
    required String smbMrl,
    required String fileName,
    FileCategory? fileType,
    bool autoPlay = true,
    bool looping = false,
    bool showControls = true,
    bool allowFullScreen = true,
    bool allowMuting = true,
    bool allowPlaybackSpeedChanging = true,
    Function(Map<String, dynamic>)? onVideoInitialized,
    Function(String)? onError,
    VoidCallback? onClose,
    VoidCallback? onControlVisibilityChanged,
    VoidCallback? onFullScreenChanged,
    VoidCallback? onInitialized,
    bool showStreamingSpeed = false,
    VoidCallback? onToggleStreamingSpeed,
  }) : this._(
          key: key,
          smbMrl: smbMrl,
          fileName: fileName,
          fileType: fileType ??
              FileTypeRegistry.getCategory(
                  VideoPlayerUtils.extensionFromPath(fileName)),
          autoPlay: autoPlay,
          looping: looping,
          showControls: showControls,
          allowFullScreen: allowFullScreen,
          allowMuting: allowMuting,
          allowPlaybackSpeedChanging: allowPlaybackSpeedChanging,
          onVideoInitialized: onVideoInitialized,
          onError: onError,
          onClose: onClose,
          onControlVisibilityChanged: onControlVisibilityChanged,
          onFullScreenChanged: onFullScreenChanged,
          onInitialized: onInitialized,
          showStreamingSpeed: showStreamingSpeed,
          onToggleStreamingSpeed: onToggleStreamingSpeed,
        );

  /// Constructor for file stream playback
  VideoPlayer.stream({
    Key? key,
    required Stream<List<int>> fileStream,
    required String fileName,
    FileCategory? fileType,
    bool autoPlay = true,
    bool looping = false,
    bool showControls = true,
    bool allowFullScreen = true,
    bool allowMuting = true,
    bool allowPlaybackSpeedChanging = true,
    Function(Map<String, dynamic>)? onVideoInitialized,
    Function(String)? onError,
    VoidCallback? onClose,
    VoidCallback? onControlVisibilityChanged,
    VoidCallback? onFullScreenChanged,
    VoidCallback? onInitialized,
    bool showStreamingSpeed = false,
    VoidCallback? onToggleStreamingSpeed,
  }) : this._(
          key: key,
          fileStream: fileStream,
          fileName: fileName,
          fileType: fileType ??
              FileTypeRegistry.getCategory(
                  VideoPlayerUtils.extensionFromPath(fileName)),
          autoPlay: autoPlay,
          looping: looping,
          showControls: showControls,
          allowFullScreen: allowFullScreen,
          allowMuting: allowMuting,
          allowPlaybackSpeedChanging: allowPlaybackSpeedChanging,
          onVideoInitialized: onVideoInitialized,
          onError: onError,
          onClose: onClose,
          onControlVisibilityChanged: onControlVisibilityChanged,
          onFullScreenChanged: onFullScreenChanged,
          onInitialized: onInitialized,
          showStreamingSpeed: showStreamingSpeed,
          onToggleStreamingSpeed: onToggleStreamingSpeed,
        );

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends _VideoPlayerVolumeHost
    with WidgetsBindingObserver, _VideoPlayerVolumeMixin {
  // Media Kit controllers
  Player? _player;
  VideoController? _videoController;

  // VLC for mobile/Android
  VlcPlayerController? _vlcController;
  exo.VideoPlayerController?
      _exoController; // ExoPlayer for Android PiP fallback
  // Fallback timer if VLC fails to start on Android
  Timer? _vlcStartupFallback;
  Timer? _vlcAutoPlayTimer;
  bool _vlcAutoPlayRequested = false;
  int _vlcAutoPlayAttempts = 0;

  // RepaintBoundary key for screenshot capture
  final GlobalKey _screenshotKey = GlobalKey();

  // State variables
  bool _isLoading = true;
  bool _hasError = false;
  bool _isFullScreen = false;
  bool _isDesktopFullScreenToggleInProgress = false;
  bool _desktopWasMaximizedBeforeFullScreen = false;
  bool? _desktopWasResizableBeforeFullScreen;
  Rect? _desktopBoundsBeforeFullScreen;
  bool _isPlaying = false;
  @override
  bool _isMuted = false;
  String _errorMessage = '';
  double _savedVolume = 70.0;
  bool _showControls = true;
  final bool _showSpeedIndicator = false;
  bool _useFlutterVlc = false;

  bool get _useVlcControls => _useFlutterVlc && _vlcController != null;
  bool get _useExoControls =>
      !_useVlcControls &&
      _exoController != null &&
      _exoController!.value.isInitialized;

  // Seeking state to prevent loading indicator during seek
  bool _isSeeking = false;
  Timer? _seekingTimer;

  // New advanced features state
  final List<SubtitleTrack> _subtitleTracks = [];
  int? _selectedSubtitleTrack = -1;
  double _playbackSpeed = 1.0;
  bool _isPictureInPicture = false;
  bool _isAndroidPip = false;
  // When true, do not render the video surface to avoid texture overlay over new routes (Android)
  bool _suspendVideoSurface = false;

  // PiP IPC (desktop): server to receive state back from PiP window
  ServerSocket? _pipServer;
  Socket? _pipClient;
  StreamSubscription<Socket>? _pipServerSub;
  StreamSubscription<String>? _pipMsgSub;
  String? _pipToken;

  // Video filters
  double _brightness = 0.0; // -1.0 to 1.0
  double _contrast = 0.0; // -1.0 to 1.0
  double _saturation = 0.0; // -1.0 to 1.0

  // Sleep timer
  Timer? _sleepTimer;
  Duration? _sleepDuration;

  // Video statistics - placeholder for future use
  Timer? _statsUpdateTimer;

  // Video player settings
  String _selectedCodec = 'auto'; // auto, h264, h265, vp9, av1
  bool _hardwareAcceleration = true;
  String _videoDecoder = 'auto'; // auto, software, hardware
  String _audioDecoder = 'auto'; // auto, software, hardware
  int _bufferSize = 10; // MB
  int _networkTimeout = 30; // seconds
  String _subtitleEncoding = 'utf-8';
  String _videoOutputFormat = 'auto'; // auto, yuv420p, rgb24
  String _videoScaleMode =
      'contain'; // cover, contain, fill, fitWidth, fitHeight, none, scaleDown

  // Timers
  Timer? _initializationTimeout;
  Timer? _hideControlsTimer;
  static const Duration _controlsAutoHideDuration = Duration(seconds: 3);

  // Streaming state
  Stream<List<int>>? _currentStream;
  StreamController<List<int>>? _streamController;
  int _totalBytesBuffered = 0;
  int _chunkCountBuffered = 0;

  // Progressive buffering state
  File? _tempFile;
  RandomAccessFile? _tempRaf;
  StreamSubscription<List<int>>? _bufferSub;
  int _bytesWritten = 0;
  bool _playerOpenedFromTemp = false;
  Timer? _noDataTimer;
  DateTime? _firstDataTime;

  // VLC state
  bool _vlcListenerAttached = false;
  bool _vlcInitNotified = false;
  bool _vlcMetaNotified = false;
  bool _vlcInitVolumeHookAttached = false;
  bool _vlcVirtualDisplay = true; // Use virtual display first on Android
  HwAcc _vlcHwAcc =
      HwAcc.auto; // Use auto instead of full for better compatibility
  Timer? _vlcRenderFallback;
  int _vlcRenderFallbackAttempts = 0;
  double _vlcAspectRatio = 16 / 9;
  double _vlcVolume = 70.0;
  double _lastVolume = 70.0;
  bool _isRestoringVolume = false;
  Map<String, dynamic>?
      _vlcPendingRestore; // {pos: Duration, vol: double0..1or0..100, playing: bool}
  bool _vlcPendingRestoreApplied = false;

  Map<String, dynamic>? _videoMetadata;

  // Fast forward/rewind state (long press on mobile, hold arrow on desktop)
  bool _isFastSeeking = false;
  bool _fastSeekingForward = true; // true = forward, false = backward
  Timer? _fastSeekTimer;
  int _fastSeekSeconds = 5; // Current seek amount, increases over time
  int _fastSeekTicks = 0; // Count of seek ticks to accelerate

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VideoUiState.notifyPlayerMounted();

    // Ensure system UI is visible when video player starts (not fullscreen)
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
      // Explicitly set light status bar icons to ensure visibility on dark backgrounds
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      // Guard against plugins or platform views hiding system UI unexpectedly
      SystemChrome.setSystemUIChangeCallback((visible) async {
        if (!mounted) return;
        if (!_isFullScreen && visible == false) {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
              overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
        }
      });
    }

    // Load settings first, then initialize the player so configuration is applied
    _loadSettings().whenComplete(_initializePlayer);
    _setupAndroidPipChannelListener();
  }

  void _showWindowsOverlayPip(
    BuildContext context, {
    required String sourceType,
    required String source,
    required String fileName,
    required int positionMs,
    required double volume,
    required bool playing,
  }) async {
    // Pause current playback to avoid double audio while overlay plays
    try {
      if (_player != null && _player!.state.playing) {
        await _player!.pause();
      } else if (_vlcController != null && _vlcController!.value.isPlaying) {
        await _vlcController!.pause();
      }
    } catch (_) {}

    if (context.mounted) {
      WindowsPipOverlay.show(
        context,
        args: {
          'sourceType': sourceType,
          'source': source,
          'fileName': fileName,
          'positionMs': positionMs,
          'volume': volume,
          'playing': playing,
        },
        onClose: (
            {required int positionMs,
            required double volume,
            required bool playing}) async {
          try {
            if (_player != null) {
              await _player!.seek(Duration(milliseconds: positionMs));
              await _player!.setVolume(volume.clamp(0.0, 100.0));
              if (playing) {
                await _player!.play();
              }
            } else if (_vlcController != null) {
              await _vlcController!.seekTo(Duration(milliseconds: positionMs));
              await _vlcController!.setVolume(volume.toInt());
              if (playing) {
                await _vlcController!.play();
              }
            }
          } catch (_) {}
          if (mounted) {
            setState(() => _isPictureInPicture = false);
          }
        },
      );

      if (mounted) {
        setState(() => _isPictureInPicture = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã bật PiP overlay trong ứng dụng')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VideoUiState.notifyPlayerDisposed();
    _disposeResources();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _kickVlcPlayback(reason: 'resume');
    }
  }

  void _disposeResources() {
    try {
      _hideControlsTimer?.cancel();
      _vlcStartupFallback?.cancel();
      _vlcAutoPlayTimer?.cancel();
      _vlcRenderFallback?.cancel();
      _initializationTimeout?.cancel();
      _noDataTimer?.cancel();
      _bufferSub?.cancel();
      _sleepTimer?.cancel();
      _statsUpdateTimer?.cancel();
      _seekingTimer?.cancel();
      _fastSeekTimer?.cancel();
      _tempRaf?.close();
      _tempFile?.delete();
      // Clear video controller reference before disposing the player
      _videoController = null;
      _player?.dispose();
      _vlcController?.dispose();
      _exoController?.dispose();
      _streamController?.close();
      _vlcAutoPlayRequested = false;
      _vlcAutoPlayAttempts = 0;
      // Close PiP IPC if any
      _pipMsgSub?.cancel();
      _pipServerSub?.cancel();
      _pipClient?.destroy();
      _pipServer?.close();
    } catch (e) {
      debugPrint('Error disposing resources: $e');
    }
    // Reset global fullscreen flag if needed
    try {
      if (VideoUiState.isFullscreen.value == true) {
        VideoUiState.isFullscreen.value = false;
      }
    } catch (_) {}
  }

  void _setupAndroidPipChannelListener() {
    if (!kIsWeb && Platform.isAndroid) {
      const channel = MethodChannel('cb_file_manager/pip');
      channel.setMethodCallHandler((call) async {
        debugPrint('PiP channel method call: ${call.method}');

        if (call.method == 'onPipChanged') {
          final args = call.arguments;
          bool inPip = false;
          if (args is Map) {
            inPip = args['inPip'] == true;
          }

          debugPrint('PiP state changed: $inPip');

          if (mounted) {
            setState(() {
              _isAndroidPip = inPip;
            });
          }

          if (inPip) {
            debugPrint('Entering Android PiP mode');
          } else {
            debugPrint('Exiting Android PiP mode');
            // Try to restore state from native PiP payload if provided
            try {
              int posMs = 0;
              bool playing = false;
              double? volume;
              if (args is Map) {
                posMs = (args['positionMs'] as num?)?.toInt() ?? 0;
                playing = args['playing'] == true;
                volume = (args['volume'] as num?)?.toDouble();
              }
              if (_vlcController != null) {
                if (posMs > 0) {
                  await _vlcController!.seekTo(Duration(milliseconds: posMs));
                }
                if (volume != null) {
                  await _vlcController!.setVolume((volume * 100).toInt());
                }
                if (playing) {
                  await _vlcController!.play();
                }
              } else if (_player != null) {
                if (posMs > 0) {
                  await _player!.seek(Duration(milliseconds: posMs));
                }
                if (volume != null) {
                  await _player!.setVolume((volume * 100).clamp(0.0, 100.0));
                }
                if (playing) {
                  await _player!.play();
                }
              }
            } catch (e) {
              debugPrint('Restore after PiP error: $e');
            }
          }
        }
      });
    }
  }

  @override
  void didUpdateWidget(VideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reinitialize if media source changed
    if (_hasMediaSourceChanged(oldWidget)) {
      _disposeResources();
      _initializePlayer();
    }
  }

  bool _hasMediaSourceChanged(VideoPlayer oldWidget) {
    return oldWidget.file?.path != widget.file?.path ||
        oldWidget.streamingUrl != widget.streamingUrl ||
        oldWidget.smbMrl != widget.smbMrl ||
        oldWidget.fileStream != widget.fileStream;
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = '';
      });

      _initializationTimeout = Timer(const Duration(seconds: 30), () {
        if (_isLoading && mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = 'Video initialization timed out after 30 seconds';
          });
          widget.onError?.call(_errorMessage);
        }
      });

      // Load saved volume and mute preferences
      final userPreferences = UserPreferences.instance;
      await userPreferences.init();

      final savedVolume = await userPreferences.getVideoPlayerVolume();
      _lastVolume = savedVolume > 0 ? savedVolume : _lastVolume;
      final savedMuted = await userPreferences.getVideoPlayerMute();

      setState(() {
        _savedVolume = savedVolume.clamp(0.0, 100.0);
        _vlcVolume = _savedVolume;
        _isMuted = savedMuted;
      });

      debugPrint(
          'Loaded volume preferences - volume: ${_savedVolume.toStringAsFixed(1)}, muted: $_isMuted');

      // Avoid early player volume stream events overriding restored volume during initialization.
      _isRestoringVolume = true;

      // On Android, use Media Kit player by default for better screenshot support.
      // VLC player cannot capture screenshots via RepaintBoundary.
      // Exception: use VLC for SMB on Android because media_kit does not support smb://
      if (!kIsWeb && Platform.isAndroid) {
        _useFlutterVlc = (widget.smbMrl != null);
        if (!_useFlutterVlc) {
          // Don't return - continue to initialize Media Kit player below
        }
      }

      if (_useFlutterVlc) {
        // Reset VLC render settings on each initialization
        // Prefer full hardware acceleration for high bitrate SMB videos.
        _vlcHwAcc = HwAcc.full;
        _vlcVirtualDisplay = Platform.isAndroid;
        _vlcRenderFallbackAttempts = 0;
        _vlcRenderFallback?.cancel();
        if (_player != null) {
          _videoController = null;
          _player?.dispose();
          _player = null;
        }
      } else {
        // Initialize media_kit player for desktop or general use (and now Android too)
        if (_player == null) {
          _player = Player(
            configuration: PlayerConfiguration(
              // Use configured buffer size (MB) loaded from preferences
              bufferSize: (_bufferSize > 0 ? _bufferSize : 10) * 1024 * 1024,
            ),
          );
          _videoController = VideoController(
            _player!,
            configuration: VideoControllerConfiguration(
              enableHardwareAcceleration: _hardwareAcceleration,
            ),
          );
          _setupPlayerEventListeners(userPreferences);
        }
      }

      // Open media based on source type
      await _openMediaSource();

      // Apply saved volume preferences with multiple attempts
      await _applyVolumeSettings();
      _isRestoringVolume = false;

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing player: $e');
      _isRestoringVolume = false;
      if (mounted) {
        setState(() {
          _errorMessage = 'Error initializing player: $e';
          _isLoading = false;
          _hasError = true;
        });
        widget.onError?.call(_errorMessage);
      }
    }
  }

  void _setupPlayerEventListeners(UserPreferences prefs) {
    if (_player == null) return;

    // Track buffering state - but ignore buffering during seek to prevent UI flicker
    _player!.stream.buffering.listen((buffering) {
      if (_useFlutterVlc) {
        return;
      }
      if (!_isSeeking && mounted) {
        setState(() {
          _isLoading = buffering;
        });
      }
    });

    // Track play state changes
    _player!.stream.playing.listen((playing) {
      if (mounted && _isPlaying != playing) {
        setState(() {
          _isPlaying = playing;
        });
        if (playing) {
          _startHideControlsTimer();
        } else {
          _hideControlsTimer?.cancel();
          _showControlsWithTimer();
        }
      }
    });

    // Track volume changes for mute state and preferences
    _player!.stream.volume.listen((volume) {
      if (!mounted || _isRestoringVolume) return;

      final isMutedNow = volume <= 0.1;

      // Save volume preference if not muted and volume changed significantly
      if (!isMutedNow && (_savedVolume - volume).abs() > 0.5) {
        setState(() {
          _savedVolume = volume;
          _vlcVolume = volume;
          if (volume > 0.1) _lastVolume = volume;
        });

        prefs.setVideoPlayerVolume(volume).then((_) {
          debugPrint('Saved volume preference: ${volume.toStringAsFixed(1)}');
        });
      }

      // Save mute state when it changes
      if (_isMuted != isMutedNow) {
        setState(() {
          _isMuted = isMutedNow;
        });

        prefs.setVideoPlayerMute(isMutedNow).then((_) {
          debugPrint('Saved mute state: $isMutedNow');
        });
      }
    });

    // Track errors
    _player!.stream.error.listen((error) {
      debugPrint('Player error: $error');
      if (mounted && !_hasError) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
        widget.onError?.call(_errorMessage);
      }
    });
  }

  Future<void> _openMediaSource() async {
    if (widget.file != null) {
      // Local file playback
      await _player!.open(Media(widget.file!.path));
      if (widget.autoPlay) {
        await _player!.play();
      }
    } else if (widget.streamingUrl != null) {
      // Streaming URL playback
      await _player!.open(Media(widget.streamingUrl!));
      if (widget.autoPlay) {
        await _player!.play();
      }
    } else if (widget.smbMrl != null) {
      // SMB MRL playback. On Android, _useFlutterVlc is true and VLC opens in _buildVlcPlayer
      if (!_useFlutterVlc) {
        await _openSmbMrl();
      }
    } else if (widget.fileStream != null) {
      // File stream playback
      await _openFileStream();
    }

    // Extract video metadata after opening
    await Future.delayed(const Duration(milliseconds: 300));
    _extractVideoMetadata();
  }

  Future<void> _openSmbMrl() async {
    debugPrint('VideoPlayer: Opening SMB MRL: ${widget.smbMrl}');

    if (!kIsWeb && Platform.isWindows) {
      // On Windows desktop, convert SMB to UNC path
      final uncPath = _smbToUnc(widget.smbMrl!);
      final fileUri = _normalizeToFileUri(uncPath);
      debugPrint('VideoPlayer: Converted SMB to UNC: $uncPath');
      debugPrint('VideoPlayer: Using file URI: $fileUri');

      try {
        await _player!
            .open(Media(fileUri))
            .timeout(const Duration(seconds: 12));
        if (widget.autoPlay) {
          await _player!.play();
        }
        debugPrint('VideoPlayer: file URI opened successfully');
      } on TimeoutException catch (_) {
        debugPrint('VideoPlayer: Open timed out, trying temp file fallback...');
        await _openWithTempFileFallback(uncPath);
      } catch (e) {
        debugPrint(
            'VideoPlayer: Open failed: $e, trying temp file fallback...');
        await _openWithTempFileFallback(uncPath);
      }
    } else {
      // Test SMB URL format
      _testSmbUrlFormat(widget.smbMrl!);

      final media = Media(
        widget.smbMrl!,
        httpHeaders: {
          'User-Agent': 'VLC/3.0.0 LibVLC/3.0.0',
        },
        extras: {
          'load-unsafe-playlists': '',
          'network-caching': '3000',
          'file-caching': '3000',
        },
      );

      try {
        await _player!.open(media).timeout(const Duration(seconds: 10));
        if (widget.autoPlay) {
          await _player!.play();
        }
        debugPrint('VideoPlayer: SMB MRL opened successfully');
      } on TimeoutException catch (_) {
        debugPrint('VideoPlayer: Direct SMB timed out');
        await _openWithHttpProxy();
      } catch (e) {
        debugPrint('VideoPlayer: Direct SMB failed: $e');
        await _openWithHttpProxy();
      }
    }
  }

  Future<void> _openFileStream() async {
    // Progressive buffering: start playback after initial buffer
    _streamController = StreamController<List<int>>.broadcast();
    _currentStream = _streamController!.stream;
    debugPrint('VideoPlayer: Starting progressive buffering...');
    // Respect configured initial buffer size (MB)
    final initialBytes = (_bufferSize > 0 ? _bufferSize : 10) * 1024 * 1024;
    await _startProgressiveBufferingAndPlay(
      widget.fileStream!,
      initialBufferBytes: initialBytes,
    );
  }

  void _extractVideoMetadata() {
    if (_player != null) {
      _videoMetadata = {
        'duration': _player!.state.duration,
        'width': _player!.state.width,
        'height': _player!.state.height,
      };

      widget.onVideoInitialized?.call(_videoMetadata!);
      widget.onInitialized?.call();
    }
  }

  // Convert smb:// URL to Windows UNC path
  String _smbToUnc(String smbUrl) {
    try {
      final uri = Uri.parse(smbUrl);
      final host = uri.host;
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (host.isEmpty || segs.isEmpty) {
        return smbUrl.replaceFirst('smb://', r'\\').replaceAll('/', r'\\');
      }
      final path = segs.join(r'\\');
      return r'\\' + host + r'\\' + path;
    } catch (_) {
      return smbUrl.replaceFirst('smb://', r'\\').replaceAll('/', r'\\');
    }
  }

  // Normalize Windows paths to file:// URI for media_kit/mpv
  String _normalizeToFileUri(String path) {
    if (Platform.isWindows) {
      if (path.startsWith('\\\\')) {
        // UNC: \\server\share\path -> file://server/share/path
        final cleaned = path.replaceAll('\\', '/');
        final withoutLeading =
            cleaned.startsWith('//') ? cleaned.substring(2) : cleaned;
        return 'file://$withoutLeading';
      }
      // Local drive: C:\path -> file:///C:/path
      final cleaned = path.replaceAll('\\', '/');
      return 'file:///$cleaned';
    }
    return path;
  }

  void _testSmbUrlFormat(String url) {
    debugPrint('=== VideoPlayer SMB URL Test ===');
    debugPrint('URL: $url');

    if (!url.startsWith('smb://')) {
      debugPrint('❌ ERROR: URL does not start with smb://');
      return;
    }

    try {
      final uri = Uri.parse(url);
      debugPrint('✅ URL parsing successful');
      debugPrint('Scheme: ${uri.scheme}');
      debugPrint('Host: ${uri.host}');
      debugPrint('Port: ${uri.port}');
      debugPrint('Path: ${uri.path}');
      debugPrint('User info: ${uri.userInfo}');

      if (uri.path.contains('%')) {
        debugPrint('⚠️ WARNING: URL contains encoded characters');
        debugPrint('Decoded path: ${Uri.decodeComponent(uri.path)}');
      }

      if (uri.userInfo.isNotEmpty) {
        debugPrint('✅ URL contains credentials');
        final parts = uri.userInfo.split(':');
        if (parts.length == 2) {
          debugPrint('Username: ${parts[0]}');
          debugPrint('Password: ${'*' * parts[1].length}');
        }
      } else {
        debugPrint('⚠️ WARNING: URL does not contain credentials');
      }
    } catch (e) {
      debugPrint('❌ ERROR: Failed to parse URL: $e');
    }

    debugPrint('=== End VideoPlayer SMB URL Test ===');
  }

  Future<void> _openWithHttpProxy() async {
    try {
      debugPrint('VideoPlayer: Opening SMB via HTTP proxy...');

      if (mounted) {
        setState(() {
          _errorMessage =
              'Direct SMB streaming failed. HTTP proxy fallback not implemented yet.';
          _isLoading = false;
          _hasError = true;
        });
      }
    } catch (e) {
      debugPrint('VideoPlayer: HTTP proxy error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'HTTP proxy error: $e';
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _openWithTempFileFallback(String uncPath) async {
    if (kIsWeb || !Platform.isWindows) {
      await _openWithHttpProxy();
      return;
    }
    if (_player == null) return;

    try {
      debugPrint('VideoPlayer: _openWithTempFileFallback for $uncPath');
      final helper = Win32SmbHelper();

      // Try buffered stream approach first
      try {
        final bufferedStream = helper.createBufferedStream(uncPath);
        // Start playback only after sufficient initial buffer based on settings
        final initialBytes = (_bufferSize > 0 ? _bufferSize : 10) * 1024 * 1024;
        await _startProgressiveBufferingAndPlay(
          bufferedStream,
          initialBufferBytes: initialBytes,
        );
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      } catch (e) {
        debugPrint('VideoPlayer: Buffered stream failed: $e');
      }

      // Fallback to copying to temp file
      try {
        final tempPath = await helper.uncPathToTempFile(uncPath,
            highPriority: true, maxBytes: 32 * 1024 * 1024);
        if (tempPath != null) {
          await _player!.open(Media(tempPath));
          if (widget.autoPlay) {
            await _player!.play();
          }
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('VideoPlayer: Temp copy failed: $e');
      }

      await _openWithHttpProxy();
    } catch (e) {
      debugPrint('VideoPlayer: _openWithTempFileFallback error: $e');
      await _openWithHttpProxy();
    }
  }

  Future<void> _startProgressiveBufferingAndPlay(
    Stream<List<int>> source, {
    int initialBufferBytes = 2 * 1024 * 1024,
    int flushEveryBytes = 512 * 1024,
  }) async {
    final tempDir = Directory.systemTemp;
    _tempFile = File(
        '${tempDir.path}/temp_media_${DateTime.now().millisecondsSinceEpoch}');

    try {
      _tempRaf = await _tempFile!.open(mode: FileMode.write);
    } catch (e) {
      debugPrint('VideoPlayer: Error opening temp file: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Cannot create temp file: $e';
          _hasError = true;
        });
      }
      return;
    }

    _bytesWritten = 0;
    _playerOpenedFromTemp = false;
    _firstDataTime = null;
    int bytesSinceFlush = 0;

    _noDataTimer?.cancel();
    _noDataTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_firstDataTime == null) return;
      final since = DateTime.now().difference(_firstDataTime!);
      if (since > const Duration(seconds: 30) && _bytesWritten == 0) {
        debugPrint('VideoPlayer: No data for 30s');
        if (mounted) {
          setState(() {
            _errorMessage = 'No data received from stream.';
            _hasError = true;
          });
        }
      }
    });

    _bufferSub = source.listen((chunk) async {
      if (chunk.isEmpty) return;
      _firstDataTime ??= DateTime.now();

      try {
        await _tempRaf!.writeFrom(chunk);
        _bytesWritten += chunk.length;
        bytesSinceFlush += chunk.length;

        if (mounted) {
          setState(() {
            _totalBytesBuffered = _bytesWritten;
            _chunkCountBuffered += 1;
          });
        }
        _streamController?.add(chunk);

        if (bytesSinceFlush >= flushEveryBytes) {
          await _tempRaf!.flush();
          bytesSinceFlush = 0;
        }

        if (!_playerOpenedFromTemp && _bytesWritten >= initialBufferBytes) {
          _playerOpenedFromTemp = true;
          try {
            await _tempRaf!.flush();
          } catch (_) {}
          debugPrint(
              'VideoPlayer: Opening from temp with ${_formatBytes(_bytesWritten)} buffered');
          try {
            await _player!.open(Media(_tempFile!.path));
            if (widget.autoPlay) {
              await _player!.play();
            }
          } catch (e) {
            debugPrint('VideoPlayer: Open error: $e');
            if (mounted) {
              setState(() {
                _errorMessage = 'Error opening playback: $e';
                _hasError = true;
              });
            }
          }
        }
      } catch (e) {
        debugPrint('VideoPlayer: Write error: $e');
        if (mounted) {
          setState(() {
            _errorMessage = 'Error writing temp data: $e';
            _hasError = true;
          });
        }
      }
    }, onError: (e) async {
      debugPrint('VideoPlayer: Buffer error: $e');
      try {
        await _tempRaf?.flush();
        await _tempRaf?.close();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _errorMessage = 'Stream data error: $e';
          _hasError = true;
        });
      }
    }, onDone: () async {
      debugPrint('VideoPlayer: Buffer done at ${_formatBytes(_bytesWritten)}');
      try {
        await _tempRaf?.flush();
        await _tempRaf?.close();
      } catch (_) {}
      _tempRaf = null;
      if (!_playerOpenedFromTemp && _tempFile != null) {
        try {
          await _player!.open(Media(_tempFile!.path));
          if (widget.autoPlay) {
            await _player!.play();
          }
        } catch (e) {
          debugPrint('VideoPlayer: Open on done error: $e');
        }
      }
    }, cancelOnError: true);
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    } else {
      return '$bytes B';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the appropriate player widget (it already shows its own loading when needed)
    final Widget playerWidget =
        widget.file != null ? _buildLocalFilePlayer() : _buildStreamingPlayer();
    return playerWidget;
  }

  Widget _buildLocalFilePlayer() {
    if (_useFlutterVlc) {
      // On Android, render the VLC-based player directly (no internal Scaffold/AppBar)
      return _buildVlcPlayer();
    }

    return _isLoading
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : _hasError
            ? _buildErrorWidget(_errorMessage)
            : Focus(
                autofocus: true,
                onKeyEvent: (node, event) => _handleKeyEvent(event),
                child: MouseRegion(
                  onHover: (_) {
                    _showControlsWithTimer();
                  },
                  child: GestureDetector(
                    onTap: () {
                      _showControlsWithTimer();
                    },
                    child: Stack(
                      children: [
                        GestureDetector(
                          onDoubleTap:
                              widget.allowFullScreen ? _toggleFullScreen : null,
                          child: _buildPrimaryVideoSurface(),
                        ),
                        if (!_isAndroidPip &&
                            widget.showControls &&
                            _showControls)
                          _buildCustomControls(),
                      ],
                    ),
                  ),
                ),
              );
  }

  // Tránh clip tròn trên desktop để giảm jank; cô lập bề mặt video bằng RepaintBoundary
  Widget _buildPrimaryVideoSurface() {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final surface = _buildVideoWidget();
    if (isDesktop) {
      // No rounded corners on desktop to prevent expensive saveLayer while playing
      return RepaintBoundary(child: surface);
    }
    return ClipRRect(
      borderRadius:
          _isFullScreen ? BorderRadius.zero : BorderRadius.circular(16.0),
      child: RepaintBoundary(child: surface),
    );
  }

  Widget _buildStreamingPlayer() {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: _buildPlayerBody(),
    );
  }

  Widget _buildPlayerBody() {
    if (_hasError) {
      return _buildErrorWidget(_errorMessage);
    }

    if (_isLoading && !_useFlutterVlc) {
      return _buildLoadingWidget();
    }

    return _buildPlayer();
  }

  Widget _buildPlayer() {
    if (widget.fileType == FileCategory.video) {
      return _buildVideoPlayer();
    } else {
      return _buildAudioPlayer();
    }
  }

  Widget _buildVideoPlayer() {
    // On Android we prefer VLC for all sources
    if (_useFlutterVlc) {
      return _buildVlcPlayer();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _showControlsWithTimer();
      },
      onDoubleTap: _toggleFullScreen,
      child: Stack(
        children: [
          Positioned.fill(
            child: _buildVideoWidget(),
          ),
          if (widget.showControls && _showControls) _buildCustomControls(),
          if (_showSpeedIndicator && _currentStream != null)
            _buildSpeedIndicatorOverlay(),
          _buildFastSeekGestureOverlay(),
          _buildFastSeekIndicator(),
        ],
      ),
    );
  }

  Widget _buildVideoWidget() {
    final boxFit = VideoPlayerUtils.getBoxFitFromString(_videoScaleMode);

    // If suspended (e.g., navigating to image viewer on Android), hide the texture surface
    if (_suspendVideoSurface) {
      return const ColoredBox(color: Colors.black);
    }

    // Check for Media Kit player first (works on all platforms)
    if (_videoController != null) {
      return RepaintBoundary(
        key: _screenshotKey,
        child: Video(
          controller: _videoController!,
          controls: NoVideoControls,
          fill: Colors.black,
          fit: boxFit,
        ),
      );
    } else if (_vlcController != null) {
      return RepaintBoundary(
        key: _screenshotKey,
        child: _buildVlcSurface(),
      );
    } else {
      // Show loading widget when VLC controller is not ready
      return _buildLoadingWidget();
    }
  }

  void _scheduleVlcAutoPlayKick({required bool autoPlay}) {
    if (!autoPlay) return;
    _vlcAutoPlayRequested = true;
    _vlcAutoPlayAttempts = 0;
    _vlcAutoPlayTimer?.cancel();
    _vlcController?.addOnInitListener(() {
      _kickVlcPlayback(reason: 'init');
    });
    _vlcAutoPlayTimer = Timer(
      const Duration(milliseconds: 800),
      () {
        _kickVlcPlayback(reason: 'timer');
      },
    );
  }

  void _scheduleVlcRenderFallback() {
    if (!Platform.isAndroid) return;
    _vlcRenderFallback?.cancel();
    _vlcRenderFallback = Timer(const Duration(seconds: 2), () async {
      if (!mounted) {
        return;
      }
      final controller = _vlcController;
      if (controller == null) {
        return;
      }
      final v = controller.value;
      final noVideoOutput = v.size.width <= 0 || v.size.height <= 0;
      if (v.isInitialized && !noVideoOutput) {
        return;
      }
      if (_vlcRenderFallbackAttempts >= 2) {
        return;
      }
      _vlcRenderFallbackAttempts += 1;
      try {
        await controller.dispose();
      } catch (_) {}
      _vlcController = null;
      _vlcListenerAttached = false;
      _vlcInitNotified = false;
      _vlcMetaNotified = false;
      _vlcInitVolumeHookAttached = false;

      // Fallback 1: keep virtual display but relax hardware acceleration.
      // Fallback 2: switch to hybrid composition (virtualDisplay=false).
      if (_vlcRenderFallbackAttempts == 1) {
        _vlcHwAcc = HwAcc.auto;
        _vlcVirtualDisplay = true;
      } else {
        _vlcHwAcc = HwAcc.auto;
        _vlcVirtualDisplay = false;
      }

      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _kickVlcPlayback({required String reason}) async {
    if (!_vlcAutoPlayRequested) return;
    final controller = _vlcController;
    if (controller == null) {
      return;
    }
    final v = controller.value;
    if (!v.isInitialized) {
      _vlcAutoPlayAttempts += 1;
      if (_vlcAutoPlayAttempts < 6) {
        _vlcAutoPlayTimer?.cancel();
        _vlcAutoPlayTimer = Timer(
          const Duration(milliseconds: 700),
          () => _kickVlcPlayback(reason: 'wait_init'),
        );
      } else {
        _vlcAutoPlayRequested = false;
      }
      return;
    }
    if (v.isPlaying) {
      _vlcAutoPlayRequested = false;
      return;
    }
    try {
      await controller.play();
    } catch (_) {
      // Best-effort.
    }
    if (_vlcAutoPlayRequested) {
      _vlcAutoPlayAttempts += 1;
      if (_vlcAutoPlayAttempts < 6) {
        _vlcAutoPlayTimer?.cancel();
        _vlcAutoPlayTimer = Timer(
          const Duration(milliseconds: 700),
          () => _kickVlcPlayback(reason: 'retry'),
        );
      } else {
        _vlcAutoPlayRequested = false;
      }
    }
  }

  Widget _buildVlcPlayer() {
    // If suspended (e.g., navigating to image viewer on Android), hide the texture surface
    if (_suspendVideoSurface) {
      return const ColoredBox(color: Colors.black);
    }
    // Initialize VLC controller lazily for the active Android source type
    if (_vlcController == null) {
      _vlcListenerAttached = false;
      _vlcInitNotified = false;
      _vlcMetaNotified = false;
      _vlcInitVolumeHookAttached = false;
      // Initialize VLC controller based on source type
      if (widget.smbMrl != null) {
        _vlcController = _createSmbVlcController(
          smbMrl: widget.smbMrl!,
          useUserInfoInUrl: false,
          // Defer playback until after the platform view/controller initialization completes.
          // This avoids cases where audio starts but the video output is not attached yet.
          autoPlay: false,
        );
        _scheduleVlcAutoPlayKick(autoPlay: widget.autoPlay);
        _scheduleVlcRenderFallback();
      } else if (widget.streamingUrl != null) {
        // HTTP/HTTPS or other stream URL
        _vlcController = VlcPlayerController.network(
          widget.streamingUrl!,
          hwAcc: HwAcc.full,
          autoPlay: widget.autoPlay,
          options: VlcPlayerOptions(
            advanced: VlcAdvancedOptions([
              '--network-caching=1000',
            ]),
            video: VlcVideoOptions([
              '--android-display-chroma=RV32',
            ]),
          ),
        );
      } else if (widget.file != null) {
        // Local file
        _vlcController = VlcPlayerController.file(
          widget.file!,
          hwAcc: HwAcc.full,
          autoPlay: widget.autoPlay,
          options: VlcPlayerOptions(
            video: VlcVideoOptions([
              '--android-display-chroma=RV32',
            ]),
          ),
        );
      }

      if (_vlcController != null && !_vlcInitVolumeHookAttached) {
        _vlcInitVolumeHookAttached = true;
        _vlcController!.addOnInitListener(() {
          _applyVolumeToActiveController(updateUi: false);
        });
      }

      // Arm a short fallback in case VLC fails to render on some devices
      if (Platform.isAndroid && widget.smbMrl == null) {
        _vlcStartupFallback?.cancel();
        _vlcStartupFallback = Timer(const Duration(seconds: 3), () async {
          if (!mounted) return;
          final notReady = _vlcController == null ||
              !_vlcController!.value.isInitialized ||
              _vlcController!.value.size.width == 0;
          if (notReady) {
            debugPrint('VLC not ready, falling back to Exo');
            await _initExoFallback();
            if (mounted) setState(() {});
          }
        });
      }
    }

    if (_vlcController == null) {
      return _buildLoadingWidget();
    }

    if (!_vlcListenerAttached) {
      _vlcListenerAttached = true;
      // Keep listener minimal to avoid frequent full widget rebuilds.
      _vlcController!.addListener(() {
        final v = _vlcController!.value;
        _notifyVlcReady(v);
        if (v.size.width > 0 && v.size.height > 0) {
          final nextAspect = v.size.width / v.size.height;
          if ((nextAspect - _vlcAspectRatio).abs() > 0.01) {
            if (mounted) {
              setState(() {
                _vlcAspectRatio = nextAspect;
              });
            } else {
              _vlcAspectRatio = nextAspect;
            }
          }
        }
        final hasMediaInfo = v.duration > Duration.zero ||
            (v.size.width > 0 && v.size.height > 0);
        if (_isLoading && (v.isInitialized || v.isPlaying || hasMediaInfo)) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
        if (_vlcAutoPlayRequested && v.isPlaying) {
          _vlcAutoPlayRequested = false;
        }
        if (v.hasError && !_hasError) {
          final msg = v.errorDescription.isNotEmpty
              ? v.errorDescription
              : 'VLC playback error';
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = msg;
            });
          }
          widget.onError?.call(msg);
          return;
        }
        // Apply pending restore once after controller is producing values.
        if (_vlcPendingRestore != null && !_vlcPendingRestoreApplied) {
          final restore = _vlcPendingRestore!;
          final pos = (restore['pos'] as Duration?) ?? Duration.zero;
          final vol = (restore['vol'] as num?)?.toDouble(); // 0..1
          final playing = restore['playing'] == true;
          Future.microtask(() async {
            try {
              if (pos > Duration.zero) await _vlcController!.seekTo(pos);
            } catch (_) {}
            try {
              if (vol != null) {
                await _vlcController!.setVolume((vol * 100).toInt());
              }
            } catch (_) {}
            try {
              if (playing) {
                await _vlcController!.play();
              } else {
                await _vlcController!.pause();
              }
            } catch (_) {}
            _vlcPendingRestoreApplied = true;
            _vlcPendingRestore = null;
            if (mounted) {
              // Mark once for controls state that depends on restore flags.
              setState(() {});
            }
          });
        }
      });
      _notifyVlcReady(_vlcController!.value);
    }

    // Prefer Exo output when available: in Android PiP or as runtime fallback
    if (_exoController != null && _exoController!.value.isInitialized) {
      final ar = _exoController!.value.aspectRatio > 0
          ? _exoController!.value.aspectRatio
          : (16 / 9);
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _showControlsWithTimer();
              },
              onDoubleTap: _toggleFullScreen,
              child: Container(color: Colors.black),
            ),
          ),
          Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Ensure we have valid constraints
                if (constraints.maxWidth.isInfinite ||
                    constraints.maxHeight.isInfinite) {
                  return SizedBox(
                    width: 400,
                    height: 225,
                    child: exo.VideoPlayer(_exoController!),
                  );
                }
                return AspectRatio(
                  aspectRatio: ar,
                  child: exo.VideoPlayer(_exoController!),
                );
              },
            ),
          ),
          if (widget.showControls && _showControls) _buildCustomControls(),
          _buildFastSeekGestureOverlay(),
          _buildFastSeekIndicator(),
        ],
      );
    } else if (_isAndroidPip) {
      return const ColoredBox(color: Colors.black);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            key: _screenshotKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _showControlsWithTimer();
              },
              onDoubleTap: _toggleFullScreen,
              child: Container(
                color: Colors.black,
                child: _buildVlcSurface(),
              ),
            ),
          ),
        ),
        if (widget.showControls && !_isAndroidPip && _showControls)
          _buildCustomControls(),
        _buildFastSeekGestureOverlay(),
        _buildFastSeekIndicator(),
      ],
    );
  }

  // Initialize Exo for Android as a VLC fallback (non-PiP & PiP)
  Future<void> _initExoFallback() async {
    if (!Platform.isAndroid) return;
    if (_exoController != null) return;

    try {
      exo.VideoPlayerController controller;
      if (widget.file != null) {
        controller = exo.VideoPlayerController.file(widget.file!);
      } else if (widget.streamingUrl != null) {
        controller = exo.VideoPlayerController.networkUrl(
            Uri.parse(widget.streamingUrl!));
      } else if (widget.smbMrl != null) {
        // Use local HTTP proxy for SMB to ensure Exo compatibility
        try {
          final proxied =
              await SmbHttpProxyServer.instance.urlFor(widget.smbMrl!);
          controller = exo.VideoPlayerController.networkUrl(proxied);
        } catch (e) {
          debugPrint('Exo fallback: proxy failed: $e');
          return;
        }
      } else if (widget.fileStream != null) {
        // Not supported directly by Exo; keep VLC path for streams
        debugPrint('Exo fallback: stream source not supported, skipping');
        return;
      } else {
        return;
      }

      await controller.initialize();
      if (widget.autoPlay) {
        await controller.play();
      }
      _exoController = controller;
    } catch (e) {
      debugPrint('Exo fallback init failed: $e');
    }
  }

  // UI Helper Methods
  Widget _buildErrorWidget(String message) {
    return VideoPlayerErrorWidget(
      message: message,
      onRetry: () {
        setState(() {
          _hasError = false;
          _isLoading = true;
        });
        _initializePlayer();
      },
    );
  }

  /// Single unified loading: same minimal spinner for init and for VlcPlayer placeholder.
  /// Avoids "big" VideoPlayerLoadingWidget + a second different loading in SMB/VLC mode.
  Widget _buildLoadingWidget() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }

  Widget _buildVlcPlaceholder() {
    return const SizedBox.shrink();
  }

  Widget _buildVlcSurface() {
    if (_vlcController == null) {
      return _buildLoadingWidget();
    }
    return Center(
      child: AspectRatio(
        aspectRatio: _vlcAspectRatio,
        child: VlcPlayer(
          key: ValueKey(
            'vlc-${_vlcController.hashCode}-${_vlcVirtualDisplay ? 'vd' : 'hc'}-${_vlcHwAcc.name}',
          ),
          controller: _vlcController!,
          aspectRatio: _vlcAspectRatio,
          placeholder: _buildVlcPlaceholder(),
          virtualDisplay: _vlcVirtualDisplay,
        ),
      ),
    );
  }

  void _notifyVlcReady(VlcPlayerValue v) {
    final hasMediaInfo =
        v.duration > Duration.zero || (v.size.width > 0 && v.size.height > 0);
    final ready = v.isInitialized || v.isPlaying || hasMediaInfo;
    if (!_vlcInitNotified && ready) {
      _vlcInitNotified = true;
      widget.onInitialized?.call();
    }
    if (!_vlcMetaNotified && hasMediaInfo) {
      _vlcMetaNotified = true;
      _videoMetadata = {
        'duration': v.duration,
        'width': v.size.width,
        'height': v.size.height,
      };
      widget.onVideoInitialized?.call(_videoMetadata!);
    }
  }

  Widget _buildFastSeekGestureOverlay() {
    return FastSeekGestureOverlay(
      onRewindStart: () => _startFastSeeking(forward: false),
      onRewindEnd: _stopFastSeeking,
      onForwardStart: () => _startFastSeeking(forward: true),
      onForwardEnd: _stopFastSeeking,
    );
  }

  Widget _buildFastSeekIndicator() {
    return FastSeekIndicator(
      isFastSeeking: _isFastSeeking,
      fastSeekSeconds: _fastSeekSeconds,
      fastSeekingForward: _fastSeekingForward,
    );
  }

  Widget _buildAudioPlayer() {
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Icon(PhosphorIconsLight.musicNote,
                    size: 80, color: Colors.white),
              ),
              const SizedBox(height: 32),
              Text(
                widget.fileName,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _buildAudioControls(),
            ],
          ),
        ),
        if (_showSpeedIndicator && _currentStream != null)
          _buildSpeedIndicatorOverlay(),
      ],
    );
  }

  Widget _buildAudioControls() {
    if (_player == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<bool>(
      stream: _player!.stream.playing,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => _player!.previous(),
              icon: const Icon(PhosphorIconsLight.skipBack,
                  color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: () => _player!.playOrPause(),
              icon: Icon(
                isPlaying
                    ? PhosphorIconsLight.pauseCircle
                    : PhosphorIconsLight.playCircle,
                color: Colors.white,
                size: 64,
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: () => _player!.next(),
              icon: const Icon(PhosphorIconsLight.skipForward,
                  color: Colors.white, size: 32),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSpeedIndicatorOverlay() {
    return Positioned(
      top: 16,
      right: 16,
      child: Column(
        children: [
          StreamSpeedIndicator(
            stream: _currentStream,
            label: 'Stream Speed',
          ),
          const SizedBox(height: 12),
          BufferInfoWidget(
            stream: _currentStream,
            label: 'Buffer Info',
          ),
          const SizedBox(height: 12),
          Container(
            width: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.black.withValues(alpha: 0.9),
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Debug Info',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Buffered: ${_formatBytes(_totalBytesBuffered)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                Text(
                  'Chunks: $_chunkCountBuffered',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                Text(
                  'Stream Active: ${_streamController != null ? "Yes" : "No"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Event Handlers
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;

    if (event is KeyDownEvent) {
      // Ctrl+Left/Right for 1 minute seek (desktop)
      // Ctrl+Arrow for fast seeking with higher initial speed (starts at 60s)
      if (isCtrlPressed && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _startFastSeeking(forward: false, withCtrl: true);
        return KeyEventResult.handled;
      } else if (isCtrlPressed &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _startFastSeeking(forward: true, withCtrl: true);
        return KeyEventResult.handled;
      }
      // Spacebar for pause/play
      else if (event.logicalKey == LogicalKeyboardKey.space) {
        _togglePlayPause();
        return KeyEventResult.handled;
      }
      // Arrow keys for seeking (hold for continuous seek)
      else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _startFastSeeking(forward: false, withCtrl: false);
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _startFastSeeking(forward: true, withCtrl: false);
        return KeyEventResult.handled;
      }
      // Arrow up/down for volume
      else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        _increaseVolume();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _decreaseVolume();
        return KeyEventResult.handled;
      }
      // M for mute/unmute
      else if (event.logicalKey == LogicalKeyboardKey.keyM) {
        _toggleMute();
        return KeyEventResult.handled;
      }
      // F for fullscreen
      else if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _toggleFullScreen();
        return KeyEventResult.handled;
      }
      // Escape to exit fullscreen
      else if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_isFullScreen) {
          _toggleFullScreen();
          return KeyEventResult.handled;
        }
      }
    } else if (event is KeyUpEvent) {
      // Stop fast seeking when arrow key is released
      if ((event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) &&
          _isFastSeeking) {
        _stopFastSeeking();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _showControlsWithTimer() {
    if (_isAndroidPip) return;
    if (!mounted) return;
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
    widget.onControlVisibilityChanged?.call();
  }

  bool _isCurrentlyPlaying() {
    if (_useVlcControls) {
      return _vlcController?.value.isPlaying ?? false;
    }
    if (_useExoControls) {
      return _exoController?.value.isPlaying ?? false;
    }
    return _player?.state.playing ?? false;
  }

  bool _shouldAutoHideControls() {
    if (!widget.showControls) return false;
    if (_isAndroidPip) return false;
    if (_isSeeking || _isFastSeeking) return false;
    return _isCurrentlyPlaying();
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!_shouldAutoHideControls()) return;
    _hideControlsTimer = Timer(_controlsAutoHideDuration, () {
      if (mounted && _shouldAutoHideControls()) {
        setState(() {
          _showControls = false;
        });
        widget.onControlVisibilityChanged?.call();
      }
    });
  }

  Future<void> _toggleFullScreen() async {
    if (!widget.allowFullScreen) return;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Desktop platforms - use window_manager
      if (_isDesktopFullScreenToggleInProgress) return;
      _isDesktopFullScreenToggleInProgress = true;
      try {
        if (Platform.isWindows) {
          const channel = MethodChannel('cb_file_manager/window_utils');
          final entering = !_isFullScreen;
          await channel.invokeMethod('setNativeFullScreen', {
            'isFullScreen': entering,
          });

          setState(() {
            _isFullScreen = entering;
            _showControls = true;
            _startHideControlsTimer();
          });
          widget.onFullScreenChanged?.call();
          return;
        }

        bool isFullScreen = await windowManager.isFullScreen();
        if (isFullScreen) {
          await windowManager.setFullScreen(false);

          // Allow platform-side size refresh to settle before restoring bounds.
          await Future<void>.delayed(const Duration(milliseconds: 60));

          if (_desktopWasResizableBeforeFullScreen != null) {
            await windowManager
                .setResizable(_desktopWasResizableBeforeFullScreen!);
          } else {
            await windowManager.setResizable(true);
          }

          if (_desktopWasMaximizedBeforeFullScreen) {
            await windowManager.maximize();
          } else if (_desktopBoundsBeforeFullScreen != null) {
            await windowManager.setBounds(_desktopBoundsBeforeFullScreen!);
          }

          _desktopWasMaximizedBeforeFullScreen = false;
          _desktopWasResizableBeforeFullScreen = null;
          _desktopBoundsBeforeFullScreen = null;
        } else {
          _desktopWasMaximizedBeforeFullScreen =
              await windowManager.isMaximized();
          _desktopWasResizableBeforeFullScreen =
              await windowManager.isResizable();
          _desktopBoundsBeforeFullScreen = await windowManager.getBounds();

          await windowManager.setFullScreen(true);
        }

        await windowManager.focus();
        setState(() {
          _isFullScreen = !isFullScreen;
          _showControls = true;
          _startHideControlsTimer();
        });
        widget.onFullScreenChanged?.call();
      } catch (e) {
        debugPrint('Error toggling fullscreen: $e');
      } finally {
        _isDesktopFullScreenToggleInProgress = false;
      }
    } else {
      // Mobile platforms - use system chrome
      setState(() {
        _isFullScreen = !_isFullScreen;
        VideoUiState.isFullscreen.value = _isFullScreen;
        _showControls = true;
        _startHideControlsTimer();
      });

      if (_isFullScreen) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        // Hide all system UI in fullscreen (immersive experience)
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        // Restore both status bar and nav bar
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
        // Restore light status bar icons after exiting fullscreen
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      }
      widget.onFullScreenChanged?.call();
    }
  }

  void _togglePlayPause() async {
    if (_useVlcControls) {
      final playing = _vlcController!.value.isPlaying;
      if (playing) {
        await _vlcController!.pause();
      } else {
        await _vlcController!.play();
      }
      _showControlsWithTimer();
      if (mounted) setState(() {});
    } else if (_useExoControls) {
      final playing = _exoController!.value.isPlaying;
      if (playing) {
        await _exoController!.pause();
      } else {
        await _exoController!.play();
      }
      _showControlsWithTimer();
      if (mounted) setState(() {});
    } else if (_player != null) {
      if (_player!.state.playing) {
        await _player!.pause();
      } else {
        await _player!.play();
      }
      _showControlsWithTimer();
      if (mounted) setState(() {});
    }
  }

  void _seekForward([int seconds = 10]) async {
    _startSeeking();

    if (_useVlcControls) {
      final pos = _vlcController!.value.position;
      final targetMs = (pos.inMilliseconds + (seconds * 1000));
      await _vlcController!.seekTo(Duration(milliseconds: targetMs));
    } else if (_useExoControls) {
      final pos = _exoController!.value.position;
      final target = pos + Duration(seconds: seconds);
      await _exoController!.seekTo(target);
    } else if (_player != null) {
      final currentPosition = _player!.state.position;
      final newPosition = currentPosition + Duration(seconds: seconds);
      final seekPosition = newPosition > _player!.state.duration
          ? _player!.state.duration
          : newPosition;
      await _player!.seek(seekPosition);
    }

    _showControlsWithTimer();
  }

  void _seekBackward([int seconds = 10]) async {
    _startSeeking();

    if (_useVlcControls) {
      final v = _vlcController!.value;
      final targetMs = (v.position.inMilliseconds - (seconds * 1000));
      await _vlcController!.seekTo(
          Duration(milliseconds: targetMs.clamp(0, v.duration.inMilliseconds)));
    } else if (_useExoControls) {
      final pos = _exoController!.value.position;
      final target = pos - Duration(seconds: seconds);
      await _exoController!
          .seekTo(target < Duration.zero ? Duration.zero : target);
    } else if (_player != null) {
      final currentPosition = _player!.state.position;
      final newPosition = currentPosition - Duration(seconds: seconds);
      final seekPosition =
          newPosition < Duration.zero ? Duration.zero : newPosition;
      await _player!.seek(seekPosition);
    }

    _showControlsWithTimer();
  }

  // Fast seeking methods (hold arrow on desktop, long press on mobile)
  // Speed increases the longer you hold
  // Normal: 5s -> 10s -> 15s -> 30s -> 60s -> 2m -> 5m
  // With Ctrl: starts at 60s -> 2m -> 5m -> 10m
  void _startFastSeeking({required bool forward, bool withCtrl = false}) {
    if (_isFastSeeking) return;

    _fastSeekTicks = 0;
    // Ctrl starts at 60s, normal starts at 5s
    _fastSeekSeconds = withCtrl ? 60 : 5;

    setState(() {
      _isFastSeeking = true;
      _fastSeekingForward = forward;
    });

    // Perform initial seek
    if (forward) {
      _seekForward(_fastSeekSeconds);
    } else {
      _seekBackward(_fastSeekSeconds);
    }

    // Continue seeking every 200ms while held, speed increases over time
    _fastSeekTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted || !_isFastSeeking) {
        _fastSeekTimer?.cancel();
        return;
      }

      _fastSeekTicks++;

      if (withCtrl) {
        // Ctrl+Arrow: faster progression
        // 0-10 ticks (0-2s): 60s, 11-20 ticks (2-4s): 2m
        // 21-30 ticks (4-6s): 5m, 31+ ticks (6s+): 10m
        if (_fastSeekTicks > 30) {
          _fastSeekSeconds = 600; // 10 minutes
        } else if (_fastSeekTicks > 20) {
          _fastSeekSeconds = 300; // 5 minutes
        } else if (_fastSeekTicks > 10) {
          _fastSeekSeconds = 120; // 2 minutes
        } else {
          _fastSeekSeconds = 60; // 1 minute
        }
      } else {
        // Normal arrow: gradual progression
        // 0-5 ticks (0-1s): 5s, 6-15 ticks (1-3s): 10s, 16-25 ticks (3-5s): 15s
        // 26-35 ticks (5-7s): 30s, 36-50 ticks (7-10s): 60s
        // 51-70 ticks (10-14s): 2m, 71+ ticks (14s+): 5m
        if (_fastSeekTicks > 70) {
          _fastSeekSeconds = 300; // 5 minutes
        } else if (_fastSeekTicks > 50) {
          _fastSeekSeconds = 120; // 2 minutes
        } else if (_fastSeekTicks > 35) {
          _fastSeekSeconds = 60;
        } else if (_fastSeekTicks > 25) {
          _fastSeekSeconds = 30;
        } else if (_fastSeekTicks > 15) {
          _fastSeekSeconds = 15;
        } else if (_fastSeekTicks > 5) {
          _fastSeekSeconds = 10;
        } else {
          _fastSeekSeconds = 5;
        }
      }

      if (_fastSeekingForward) {
        _seekForward(_fastSeekSeconds);
      } else {
        _seekBackward(_fastSeekSeconds);
      }

      // Update UI to show current speed
      if (mounted) setState(() {});
    });

    _showControlsWithTimer();
  }

  void _stopFastSeeking() {
    _fastSeekTimer?.cancel();
    _fastSeekTimer = null;

    if (_isFastSeeking) {
      setState(() {
        _isFastSeeking = false;
        _fastSeekSeconds = 5;
        _fastSeekTicks = 0;
      });
    }
  }

  void _increaseVolume() async {
    final current = _useVlcControls
        ? _vlcController!.value.volume.toDouble()
        : _useExoControls
            ? (_exoController!.value.volume * 100.0)
            : (_player?.state.volume ?? _savedVolume);
    await _setVolumeFromUser((current + 5).clamp(0.0, 100.0));
  }

  void _decreaseVolume() async {
    final current = _useVlcControls
        ? _vlcController!.value.volume.toDouble()
        : _useExoControls
            ? (_exoController!.value.volume * 100.0)
            : (_player?.state.volume ?? _savedVolume);
    await _setVolumeFromUser((current - 5).clamp(0.0, 100.0));
  }

  void _toggleMute() async {
    await _toggleMuteFromUser();
  }

  // Custom Controls
  Widget _buildCustomControls() {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (isDesktop) {
      return _buildPipStyleControls();
    }
    // Mobile-specific redesigned controls
    return _buildMobileControls();
  }

  // New: Mobile-focused overlay controls with cleaner layout & working bindings
  Widget _buildMobileControls() {
    return Stack(
      children: [
        // Top gradient
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            ignoring: true,
            child: Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Center play/pause
        if (_showControls)
          Center(
            child: _buildPlayPauseButton(),
          ),

        // Bottom controls
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Current time
                    _useVlcControls
                        ? ValueListenableBuilder<VlcPlayerValue>(
                            valueListenable: _vlcController!,
                            builder: (context, v, _) {
                              return Text(
                                VideoPlayerUtils.formatDuration(v.position),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              );
                            },
                          )
                        : _useExoControls
                            ? ValueListenableBuilder<exo.VideoPlayerValue>(
                                valueListenable: _exoController!,
                                builder: (context, v, _) {
                                  return Text(
                                    VideoPlayerUtils.formatDuration(v.position),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  );
                                },
                              )
                            : StreamBuilder<Duration>(
                                stream: _player!.stream.position,
                                builder: (context, snap) {
                                  final pos = snap.data ?? Duration.zero;
                                  return Text(
                                    VideoPlayerUtils.formatDuration(pos),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  );
                                },
                              ),

                    const SizedBox(width: 8),

                    // Slider expanded
                    Expanded(child: _buildMobileSeekSlider()),

                    const SizedBox(width: 8),

                    // Duration
                    _useVlcControls
                        ? ValueListenableBuilder<VlcPlayerValue>(
                            valueListenable: _vlcController!,
                            builder: (context, v, _) {
                              final dur = v.duration.inMilliseconds <= 0
                                  ? '--:--'
                                  : VideoPlayerUtils.formatDuration(v.duration);
                              return Text(
                                dur,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              );
                            },
                          )
                        : _useExoControls
                            ? ValueListenableBuilder<exo.VideoPlayerValue>(
                                valueListenable: _exoController!,
                                builder: (context, v, _) {
                                  return Text(
                                    VideoPlayerUtils.formatDuration(v.duration),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  );
                                },
                              )
                            : Text(
                                VideoPlayerUtils.formatDuration(
                                    _player!.state.duration),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    VideoPlayerControlButton(
                      icon: PhosphorIconsLight.skipBack,
                      onPressed: () => _seekBackward(10),
                      tooltip: 'Rewind 10s',
                    ),
                    const SizedBox(width: 4),
                    _buildPlayPauseButton(),
                    const SizedBox(width: 4),
                    VideoPlayerControlButton(
                      icon: PhosphorIconsLight.skipForward,
                      onPressed: () => _seekForward(10),
                      tooltip: 'Forward 10s',
                    ),
                    const Spacer(),
                    if (widget.allowMuting) _buildVolumeButtonOnly(),
                    const SizedBox(width: 6),
                    _buildAdvancedControlsMenu(),
                    if (widget.allowFullScreen) ...[
                      const SizedBox(width: 6),
                      VideoPlayerControlButton(
                        icon: _isFullScreen
                            ? PhosphorIconsLight.cornersIn
                            : PhosphorIconsLight.cornersOut,
                        onPressed: _toggleFullScreen,
                        enabled: true,
                        tooltip: _isFullScreen
                            ? 'Exit fullscreen'
                            : 'Enter fullscreen',
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Slider used by mobile controls with support for VLC/Exo/MediaKit
  Widget _buildMobileSeekSlider() {
    void onSeekEnd() {
      _seekingTimer?.cancel();
      _seekingTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _isSeeking = false);
      });
    }

    if (_useVlcControls) {
      return ValueListenableBuilder<VlcPlayerValue>(
        valueListenable: _vlcController!,
        builder: (context, v, _) {
          final durMs = v.duration.inMilliseconds;
          final posMs = v.position.inMilliseconds;
          final hasDuration = durMs > 0;
          final maxMs = hasDuration ? durMs : (posMs > 0 ? posMs + 1000 : 1);
          final value = posMs.clamp(0, maxMs).toDouble();
          return VideoPlayerSeekSlider(
            value: value,
            min: 0,
            max: maxMs.toDouble(),
            onChangeStart:
                hasDuration ? () => setState(() => _isSeeking = true) : null,
            onChanged: hasDuration
                ? (vv) =>
                    _vlcController?.seekTo(Duration(milliseconds: vv.toInt()))
                : null,
            onChangeEnd: hasDuration ? onSeekEnd : null,
          );
        },
      );
    } else if (_useExoControls) {
      return ValueListenableBuilder<exo.VideoPlayerValue>(
        valueListenable: _exoController!,
        builder: (context, v, _) {
          final maxMs =
              v.duration.inMilliseconds <= 0 ? 1 : v.duration.inMilliseconds;
          final value = v.position.inMilliseconds.clamp(0, maxMs).toDouble();
          return VideoPlayerSeekSlider(
            value: value,
            min: 0,
            max: maxMs.toDouble(),
            onChangeStart: () => setState(() => _isSeeking = true),
            onChanged: (vv) =>
                _exoController!.seekTo(Duration(milliseconds: vv.toInt())),
            onChangeEnd: onSeekEnd,
          );
        },
      );
    } else {
      return StreamBuilder<Duration>(
        stream: _player!.stream.position,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final duration = _player!.state.duration;
          final maxMs =
              duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
          final value = position.inMilliseconds.clamp(0, maxMs).toDouble();
          return VideoPlayerSeekSlider(
            value: value,
            min: 0,
            max: maxMs.toDouble(),
            onChangeStart: () => setState(() => _isSeeking = true),
            onChanged: (v) => _player!.seek(Duration(milliseconds: v.toInt())),
            onChangeEnd: onSeekEnd,
          );
        },
      );
    }
  }

  // Mobile-only compact volume toggle button (no inline slider)
  Widget _buildVolumeButtonOnly() {
    if (_useVlcControls) {
      return ValueListenableBuilder<VlcPlayerValue>(
        valueListenable: _vlcController!,
        builder: (context, v, _) {
          final vol = v.volume; // 0..100
          final isMuted = vol <= 0;
          return VideoPlayerControlButton(
            icon: isMuted
                ? PhosphorIconsLight.speakerSlash
                : (vol < 50
                    ? PhosphorIconsLight.speakerLow
                    : PhosphorIconsLight.speakerHigh),
            onPressed: _toggleMute,
            enabled: true,
            tooltip: isMuted ? 'Unmute' : 'Mute',
          );
        },
      );
    } else if (_useExoControls) {
      return ValueListenableBuilder<exo.VideoPlayerValue>(
        valueListenable: _exoController!,
        builder: (context, v, _) {
          final vol = v.volume; // 0..1
          final isMuted = vol <= 0.001;
          return VideoPlayerControlButton(
            icon: isMuted
                ? PhosphorIconsLight.speakerSlash
                : (vol < 0.5
                    ? PhosphorIconsLight.speakerLow
                    : PhosphorIconsLight.speakerHigh),
            onPressed: _toggleMute,
            enabled: true,
            tooltip: isMuted ? 'Unmute' : 'Mute',
          );
        },
      );
    } else if (_player != null) {
      return StreamBuilder<double>(
        stream: _player!.stream.volume,
        initialData: _savedVolume,
        builder: (context, snapshot) {
          final volume = snapshot.data ?? _savedVolume;
          final isMuted = volume <= 0.1;
          return VideoPlayerControlButton(
            icon: isMuted
                ? PhosphorIconsLight.speakerSlash
                : volume < 50
                    ? PhosphorIconsLight.speakerLow
                    : PhosphorIconsLight.speakerHigh,
            onPressed: _toggleMute,
            enabled: true,
            tooltip: isMuted ? 'Unmute' : 'Mute',
          );
        },
      );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildPipStyleControls() {
    // Bottom overlay with: Play/Pause, currentTime, slider, duration, volume, menu, fullscreen
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xB3000000)],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fullScreenButton = widget.allowFullScreen
                    ? VideoPlayerControlButton(
                        icon: _isFullScreen
                            ? PhosphorIconsLight.cornersIn
                            : PhosphorIconsLight.cornersOut,
                        onPressed: _toggleFullScreen,
                        enabled: true,
                        tooltip: _isFullScreen
                            ? 'Exit fullscreen'
                            : 'Enter fullscreen',
                      )
                    : null;

                final seekSlider = Expanded(
                  child: _useVlcControls
                      ? ValueListenableBuilder<VlcPlayerValue>(
                          valueListenable: _vlcController!,
                          builder: (context, v, _) {
                            final durMs = v.duration.inMilliseconds;
                            final hasDuration = durMs > 0;
                            final maxMs = hasDuration
                                ? durMs
                                : (v.position.inMilliseconds > 0
                                    ? v.position.inMilliseconds + 1000
                                    : 1);
                            final value = v.position.inMilliseconds
                                .clamp(0, maxMs)
                                .toDouble();
                            return Slider(
                              value: value,
                              min: 0,
                              max: maxMs.toDouble(),
                              activeColor: Colors.white,
                              inactiveColor: Colors.white24,
                              onChangeStart:
                                  hasDuration ? (_) => _isSeeking = true : null,
                              onChanged: hasDuration
                                  ? (vv) async {
                                      await _vlcController?.seekTo(
                                          Duration(milliseconds: vv.toInt()));
                                    }
                                  : null,
                              onChangeEnd: hasDuration
                                  ? (_) {
                                      _seekingTimer?.cancel();
                                      _seekingTimer = Timer(
                                          const Duration(milliseconds: 200),
                                          () {
                                        if (mounted) _isSeeking = false;
                                      });
                                    }
                                  : null,
                            );
                          },
                        )
                      : _useExoControls
                          ? ValueListenableBuilder<exo.VideoPlayerValue>(
                              valueListenable: _exoController!,
                              builder: (context, v, _) {
                                final maxMs = v.duration.inMilliseconds <= 0
                                    ? 1
                                    : v.duration.inMilliseconds;
                                final value = v.position.inMilliseconds
                                    .clamp(0, maxMs)
                                    .toDouble();
                                return Slider(
                                  value: value,
                                  min: 0,
                                  max: maxMs.toDouble(),
                                  activeColor: Colors.white,
                                  inactiveColor: Colors.white24,
                                  onChangeStart: (_) => _isSeeking = true,
                                  onChanged: (vv) async {
                                    await _exoController!.seekTo(
                                        Duration(milliseconds: vv.toInt()));
                                  },
                                  onChangeEnd: (_) {
                                    _seekingTimer?.cancel();
                                    _seekingTimer = Timer(
                                        const Duration(milliseconds: 200), () {
                                      if (mounted) _isSeeking = false;
                                    });
                                  },
                                );
                              },
                            )
                          : StreamBuilder<Duration>(
                              stream: _player!.stream.position,
                              builder: (context, snapshot) {
                                final position = snapshot.data ?? Duration.zero;
                                final duration = _player!.state.duration;
                                final maxMs = duration.inMilliseconds <= 0
                                    ? 1
                                    : duration.inMilliseconds;
                                final value = position.inMilliseconds
                                    .clamp(0, maxMs)
                                    .toDouble();
                                return SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 2.5,
                                    thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 7),
                                  ),
                                  child: Slider(
                                    value: value,
                                    min: 0,
                                    max: maxMs.toDouble(),
                                    activeColor: Colors.white,
                                    inactiveColor: Colors.white24,
                                    onChangeStart: (_) => _isSeeking = true,
                                    onChanged: (v) async {
                                      final target =
                                          Duration(milliseconds: v.toInt());
                                      await _player!.seek(target);
                                    },
                                    onChangeEnd: (_) {
                                      _seekingTimer?.cancel();
                                      _seekingTimer = Timer(
                                          const Duration(milliseconds: 200),
                                          () {
                                        if (mounted) _isSeeking = false;
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                );

                final width = constraints.maxWidth;
                if (width < 520) {
                  return Row(
                    children: [
                      _buildPlayPauseButton(),
                      const SizedBox(width: 8),
                      seekSlider,
                      if (fullScreenButton != null) ...[
                        const SizedBox(width: 8),
                        fullScreenButton,
                      ],
                    ],
                  );
                }

                final showSecondaryActions = width >= 760;

                return Row(
                  children: [
                    // Play / Pause
                    _buildPlayPauseButton(),
                    const SizedBox(width: 8),

                    // Current time
                    if (_useVlcControls)
                      ValueListenableBuilder<VlcPlayerValue>(
                        valueListenable: _vlcController!,
                        builder: (context, v, _) {
                          return Text(
                            VideoPlayerUtils.formatDuration(v.position),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          );
                        },
                      )
                    else if (_useExoControls)
                      ValueListenableBuilder<exo.VideoPlayerValue>(
                        valueListenable: _exoController!,
                        builder: (context, v, _) {
                          return Text(
                            VideoPlayerUtils.formatDuration(v.position),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          );
                        },
                      )
                    else
                      StreamBuilder<Duration>(
                        stream: _player!.stream.position,
                        builder: (context, snapshot) {
                          final p = snapshot.data ?? Duration.zero;
                          return Text(
                            VideoPlayerUtils.formatDuration(p),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          );
                        },
                      ),

                    const SizedBox(width: 8),
                    seekSlider,
                    const SizedBox(width: 8),

                    // Duration
                    _useVlcControls
                        ? ValueListenableBuilder<VlcPlayerValue>(
                            valueListenable: _vlcController!,
                            builder: (context, v, _) {
                              final dur = v.duration.inMilliseconds <= 0
                                  ? '--:--'
                                  : VideoPlayerUtils.formatDuration(v.duration);
                              return Text(
                                dur,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              );
                            },
                          )
                        : _useExoControls
                            ? ValueListenableBuilder<exo.VideoPlayerValue>(
                                valueListenable: _exoController!,
                                builder: (context, v, _) {
                                  return Text(
                                    VideoPlayerUtils.formatDuration(v.duration),
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 12),
                                  );
                                },
                              )
                            : Text(
                                VideoPlayerUtils.formatDuration(
                                    _player!.state.duration),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),

                    const SizedBox(width: 8),
                    if (showSecondaryActions && widget.allowMuting)
                      _buildVolumeControl(),
                    if (showSecondaryActions) ...[
                      const SizedBox(width: 4),
                      _buildAdvancedControlsMenu(),
                    ],
                    if (fullScreenButton != null) fullScreenButton,
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayPauseButton() {
    if (_useVlcControls) {
      return ValueListenableBuilder<VlcPlayerValue>(
        valueListenable: _vlcController!,
        builder: (context, v, _) {
          return VideoPlayerControlButton(
            icon: v.isPlaying
                ? PhosphorIconsLight.pause
                : PhosphorIconsLight.play,
            onPressed: _togglePlayPause,
            size: 40,
            padding: 10,
            enabled: true,
          );
        },
      );
    } else if (_useExoControls) {
      return ValueListenableBuilder<exo.VideoPlayerValue>(
        valueListenable: _exoController!,
        builder: (context, v, _) {
          return VideoPlayerControlButton(
            icon: v.isPlaying
                ? PhosphorIconsLight.pause
                : PhosphorIconsLight.play,
            onPressed: _togglePlayPause,
            size: 40,
            padding: 10,
            enabled: true,
          );
        },
      );
    } else if (_player != null) {
      return StreamBuilder<bool>(
        stream: _player!.stream.playing,
        initialData: _isPlaying,
        builder: (context, snapshot) {
          final isPlaying = snapshot.data ?? _player!.state.playing;
          return VideoPlayerControlButton(
            icon:
                isPlaying ? PhosphorIconsLight.pause : PhosphorIconsLight.play,
            onPressed: _togglePlayPause,
            size: 40,
            padding: 10,
            enabled: true,
          );
        },
      );
    } else {
      // Fallback: No player initialized yet, show loading state
      return const VideoPlayerControlButton(
        icon: PhosphorIconsLight.play,
        onPressed: null, // Disabled
        size: 40,
        padding: 10,
        enabled: false,
      );
    }
  }

  Widget _buildVolumeControl() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_useVlcControls)
          ValueListenableBuilder<VlcPlayerValue>(
            valueListenable: _vlcController!,
            builder: (context, v, _) {
              final vol = v.volume; // 0..100
              final isMuted = vol <= 0;
              return VideoPlayerControlButton(
                icon: isMuted
                    ? PhosphorIconsLight.speakerSlash
                    : (vol < 50
                        ? PhosphorIconsLight.speakerLow
                        : PhosphorIconsLight.speakerHigh),
                onPressed: _toggleMute,
                enabled: true,
                tooltip: isMuted ? 'Unmute' : 'Mute',
              );
            },
          )
        else if (_useExoControls)
          ValueListenableBuilder<exo.VideoPlayerValue>(
            valueListenable: _exoController!,
            builder: (context, v, _) {
              final vol = v.volume; // 0..1
              final isMuted = vol <= 0.001;
              return VideoPlayerControlButton(
                icon: isMuted
                    ? PhosphorIconsLight.speakerSlash
                    : (vol < 0.5
                        ? PhosphorIconsLight.speakerLow
                        : PhosphorIconsLight.speakerHigh),
                onPressed: _toggleMute,
                enabled: true,
                tooltip: isMuted ? 'Unmute' : 'Mute',
              );
            },
          )
        else if (_player != null)
          Builder(builder: (context) {
            final volume = _isMuted ? 0.0 : _savedVolume;
            final isMuted = volume <= 0.1;
            return VideoPlayerControlButton(
              icon: isMuted
                  ? PhosphorIconsLight.speakerSlash
                  : volume < 50
                      ? PhosphorIconsLight.speakerLow
                      : PhosphorIconsLight.speakerHigh,
              onPressed: _toggleMute,
              enabled: true,
              tooltip: isMuted ? 'Unmute' : 'Mute',
            );
          })
        else
          const SizedBox.shrink(),
        if (!_isFullScreen ||
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
          SizedBox(
            width: 80,
            child: _useVlcControls
                ? ValueListenableBuilder<VlcPlayerValue>(
                    valueListenable: _vlcController!,
                    builder: (context, v, _) {
                      return VideoPlayerVolumeSlider(
                        value: v.volume.toDouble(),
                        onChanged: (val) => _setVolumeFromUser(val),
                      );
                    },
                  )
                : _useExoControls
                    ? ValueListenableBuilder<exo.VideoPlayerValue>(
                        valueListenable: _exoController!,
                        builder: (context, v, _) {
                          return VideoPlayerVolumeSlider(
                            value: v.volume * 100,
                            onChanged: (val) => _setVolumeFromUser(val),
                          );
                        },
                      )
                    : VideoPlayerVolumeSlider(
                        value: _isMuted ? 0.0 : _savedVolume,
                        onChanged: (v) => _setVolumeFromUser(v),
                      ),
          ),
      ],
    );
  }

  void _showAudioTrackDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Audio Tracks'),
        content: const Text('Audio track selection will be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _takeScreenshot() async {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // Track if video was playing before we pause it for screenshot
    final wasPlaying =
        _player?.state.playing ?? _vlcController?.value.isPlaying ?? false;

    try {
      Uint8List? screenshotBytes;
      String? screenshotPath;

      debugPrint('========== SCREENSHOT CAPTURE DEBUG ==========');
      debugPrint('_useFlutterVlc: $_useFlutterVlc');
      debugPrint('_vlcController: ${_vlcController != null}');
      debugPrint('_player: ${_player != null}');
      debugPrint('_videoController: ${_videoController != null}');

      // Pause video momentarily to stabilize frame and ensure proper rendering
      if (wasPlaying) {
        debugPrint('Pausing video to stabilize frame for screenshot...');
        if (_player != null) {
          await _player!.pause();
        } else if (_vlcController != null) {
          await _vlcController!.pause();
        }
        // Wait for pause to take effect and frame to render
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Try to capture screenshot based on active player
      // On mobile, prefer RepaintBoundary first to avoid platform texture issues
      if ((Platform.isAndroid || Platform.isIOS)) {
        debugPrint('Mobile: attempting RepaintBoundary screenshot first...');
        try {
          final boundary = _screenshotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
          debugPrint('Mobile RepaintBoundary found: ${boundary != null}');
          if (boundary != null) {
            // Ensure a fresh frame has been painted
            await Future.delayed(const Duration(milliseconds: 32));
            if (mounted) {
              final pixelRatio = MediaQuery.of(context).devicePixelRatio;
              final image = await boundary.toImage(
                pixelRatio: pixelRatio.clamp(1.0, 3.0),
              );
              final byteData =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              if (byteData != null) {
                screenshotBytes = byteData.buffer.asUint8List();
                debugPrint(
                    'Mobile RepaintBoundary screenshot successful: ${screenshotBytes.length} bytes');
              }
            }
          }
        } catch (e) {
          debugPrint('Mobile RepaintBoundary screenshot failed: $e');
        }
      }

      // VLC surface capture via RepaintBoundary (if still not captured)
      if (screenshotBytes == null && _useFlutterVlc && _vlcController != null) {
        debugPrint('Attempting VLC screenshot via RepaintBoundary...');
        try {
          final boundary = _screenshotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
          debugPrint('RepaintBoundary found: ${boundary != null}');
          if (boundary != null) {
            // Ensure the latest frame is painted before capturing
            await Future.delayed(const Duration(milliseconds: 16));
            if (mounted) {
              final pixelRatio = MediaQuery.of(context).devicePixelRatio;
              final image = await boundary.toImage(
                pixelRatio: pixelRatio.clamp(1.0, 3.0),
              );
              debugPrint('Image captured: ${image.width}x${image.height}');
              final byteData =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              if (byteData != null) {
                screenshotBytes = byteData.buffer.asUint8List();
                debugPrint(
                    'VLC screenshot successful: ${screenshotBytes.length} bytes');
              }
            }
          }
        } catch (e) {
          debugPrint('VLC screenshot failed: $e');
        }
      }

      // If still null, try media_kit API screenshot
      if (screenshotBytes == null &&
          _player != null &&
          _videoController != null) {
        debugPrint('Attempting media_kit screenshot...');
        try {
          screenshotBytes = await _player!.screenshot();
          if (screenshotBytes != null) {
            debugPrint(
                'Media kit screenshot successful: ${screenshotBytes.length} bytes');
          } else {
            debugPrint('Media kit screenshot returned null');
          }
        } catch (e) {
          debugPrint('Media kit screenshot failed: $e');
        }
      }

      // Final fallback: RepaintBoundary (any platform)
      if (screenshotBytes == null) {
        try {
          final boundary = _screenshotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
          debugPrint('RepaintBoundary fallback available: ${boundary != null}');
          if (boundary != null) {
            // Ensure the latest frame is painted before capturing
            await Future.delayed(const Duration(milliseconds: 16));
            if (mounted) {
              final pixelRatio = MediaQuery.of(context).devicePixelRatio;
              final image = await boundary.toImage(
                pixelRatio: pixelRatio.clamp(1.0, 3.0),
              );
              final byteData =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              if (byteData != null) {
                screenshotBytes = byteData.buffer.asUint8List();
                debugPrint(
                    'RepaintBoundary screenshot successful: ${screenshotBytes.length} bytes');
              }
            }
          }
        } catch (e) {
          debugPrint('RepaintBoundary screenshot fallback failed: $e');
        }
      }

      // Validate screenshot can be decoded; if not, try re-encoding to PNG
      if (screenshotBytes != null) {
        bool canDecode = true;
        try {
          // Validate by attempting to instantiate an image codec
          await ui.instantiateImageCodec(screenshotBytes);
        } catch (_) {
          canDecode = false;
        }
        if (!canDecode) {
          debugPrint(
              'Captured bytes not directly decodable; attempting PNG re-encode...');
          try {
            final decoded = img.decodeImage(screenshotBytes);
            if (decoded != null) {
              screenshotBytes = Uint8List.fromList(img.encodePng(decoded));
              // Test again
              try {
                await ui.instantiateImageCodec(screenshotBytes);
                canDecode = true;
                debugPrint('PNG re-encode successful.');
              } catch (e) {
                debugPrint('PNG re-encode still not decodable: $e');
              }
            } else {
              debugPrint('image.decodeImage returned null; cannot re-encode.');
            }
          } catch (e) {
            debugPrint('Error during PNG re-encode: $e');
          }
        }
      }

      debugPrint(
          'Final screenshotBytes: ${screenshotBytes != null ? "${screenshotBytes.length} bytes" : "null"}');
      debugPrint('========== END SCREENSHOT CAPTURE DEBUG ==========');

      // If we got screenshot bytes, save them
      if (screenshotBytes != null && screenshotBytes.isNotEmpty) {
        debugPrint(
            'Screenshot captured, size: ${screenshotBytes.length} bytes');

        // Validate screenshot is not completely black/empty by checking file size
        // Completely black images are usually very small (~< 500 bytes)
        if (screenshotBytes.length < 500) {
          debugPrint(
              'Screenshot rejected: File too small (${screenshotBytes.length} bytes - likely black/empty image)');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Capture failed: Image appears to be empty. Try again.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }

        if (Platform.isAndroid || Platform.isIOS) {
          // Save to user's Pictures folder on mobile devices
          try {
            final timestamp = DateTime.now()
                .toIso8601String()
                .replaceAll(':', '-')
                .replaceAll('.', '-');
            final fileName = 'screenshot_$timestamp.png';

            // Save to user's Pictures directory (visible in file manager)
            Directory screenshotsDir;

            if (Platform.isAndroid) {
              // On Android, get actual Pictures directory using path_provider
              // This gives us the standard Pictures folder that's accessible
              final directory = await getExternalStorageDirectory();
              if (directory == null) {
                throw Exception('Cannot access external storage');
              }
              // Navigate up from /Android/data/app-id to /sdcard
              final parts = directory.path.split('/');
              final sdcard = parts.take(parts.length - 3).join('/');
              screenshotsDir = Directory('$sdcard/Pictures/VideoScreenshots');
            } else {
              // iOS: Use Documents directory
              screenshotsDir = Directory(pathlib.join(
                (await getApplicationDocumentsDirectory()).path,
                'Screenshots',
              ));
            }

            if (!await screenshotsDir.exists()) {
              await screenshotsDir.create(recursive: true);
            }

            final screenshotFile =
                File(pathlib.join(screenshotsDir.path, fileName));
            debugPrint(
                '💾 Saving screenshot bytes: ${screenshotBytes.length} bytes to ${screenshotFile.path}');
            await screenshotFile.writeAsBytes(screenshotBytes, flush: true);

            // Ensure file is fully written to disk
            await Future.delayed(const Duration(milliseconds: 200));

            // Verify file is readable
            final fileSize = await screenshotFile.length();
            debugPrint('✅ Screenshot file verified: $fileSize bytes on disk');
            screenshotPath = screenshotFile.path;
            debugPrint('📁 Screenshot path: $screenshotPath');

            // Also save to gallery with Gal package for easy access
            try {
              await Gal.putImage(screenshotFile.path,
                  album: 'VideoScreenshots');
              debugPrint('Screenshot also saved to gallery album');
            } catch (e) {
              debugPrint('Warning: Could not add to gallery: $e');
              // Continue anyway - file is already saved
            }
          } catch (e) {
            debugPrint('Failed to save screenshot: $e');
            throw Exception('Không thể lưu ảnh: $e');
          }
        } else {
          // Desktop: Save to downloads directory
          try {
            final screenshotDir = await getDownloadsDirectory() ??
                await getApplicationDocumentsDirectory();
            final timestamp = DateTime.now()
                .toIso8601String()
                .replaceAll(':', '-')
                .replaceAll('.', '-');
            final fileName = 'screenshot_$timestamp.png';
            final file = File(pathlib.join(screenshotDir.path, fileName));

            await file.writeAsBytes(screenshotBytes);
            screenshotPath = file.path;
            debugPrint('Screenshot saved to: $screenshotPath');
          } catch (e) {
            debugPrint('Failed to write screenshot file: $e');
            throw Exception('Không thể lưu file ảnh: $e');
          }
        }

        // Show success message with path
        if (mounted) {
          final filePath = screenshotPath; // Non-null local variable

          // Cleanup: Delete old black/small screenshot files that are < 1KB
          _cleanupOldBlackScreenshots();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        PhosphorIconsLight.checkCircle,
                        color: theme.colorScheme.primary,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        localizations.screenshotSaved,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    filePath,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              action: SnackBarAction(
                label: 'Xem ảnh',
                textColor: theme.colorScheme.primary,
                onPressed: () => _openScreenshotImage(filePath),
              ),
            ),
          );
        }
      } else {
        // Screenshot failed - show helpful message
        debugPrint('Screenshot capture failed - no bytes captured');
        if (mounted) {
          if (_useFlutterVlc) {
            // VLC player doesn't support screenshot on Android
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Chụp ảnh màn hình không khả dụng với VLC player.\nVui lòng chuyển sang Media Kit player trong cài đặt.',
                ),
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Đóng',
                  onPressed: () {},
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(localizations.screenshotFailed)),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error taking screenshot: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizations.screenshotFailed)),
        );
      }
    } finally {
      // Resume video if it was playing before screenshot
      if (wasPlaying) {
        try {
          debugPrint('Resuming video playback after screenshot...');
          if (_player != null) {
            await _player!.play();
          } else if (_vlcController != null) {
            await _vlcController!.play();
          }
          debugPrint('✅ Video resumed');
        } catch (e) {
          debugPrint('Failed to resume video: $e');
        }
      }
    }
  }

  /// Cleanup old black or empty screenshot files (< 1KB) from VideoScreenshots folder
  Future<void> _cleanupOldBlackScreenshots() async {
    try {
      Directory screenshotsDir;

      if (Platform.isAndroid) {
        final directory = await getExternalStorageDirectory();
        if (directory == null) {
          debugPrint('Cannot access external storage for cleanup');
          return;
        }
        // Navigate to actual Pictures folder
        final parts = directory.path.split('/');
        final sdcard = parts.take(parts.length - 3).join('/');
        screenshotsDir = Directory('$sdcard/Pictures/VideoScreenshots');
      } else {
        // iOS
        screenshotsDir = Directory(pathlib.join(
          (await getApplicationDocumentsDirectory()).path,
          'Screenshots',
        ));
      }

      if (!await screenshotsDir.exists()) return;

      final files = screenshotsDir.listSync();
      int deletedCount = 0;

      for (final file in files) {
        if (file is File && file.path.endsWith('.png')) {
          try {
            final fileSize = await file.length();
            // Delete files < 1KB (likely black/empty captures)
            if (fileSize < 1024) {
              await file.delete();
              deletedCount++;
              debugPrint(
                  '🗑️ Deleted black screenshot: ${file.path} ($fileSize bytes)');
            }
          } catch (e) {
            debugPrint('Could not delete old screenshot: $e');
          }
        }
      }

      if (deletedCount > 0) {
        debugPrint('Cleaned up $deletedCount old black screenshot(s)');
      }
    } catch (e) {
      debugPrint('Error during screenshot cleanup: $e');
    }
  }

  Future<void> _openScreenshotImage(String filePath) async {
    final localizations = AppLocalizations.of(context)!;
    try {
      debugPrint('========== SCREENSHOT OPEN IMAGE DEBUG ==========');
      debugPrint('Attempting to open image in new tab: $filePath');

      // Validate existence
      final file = File(filePath);
      final exists = await file.exists();
      debugPrint('File exists: $exists');

      if (!exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localizations.screenshotFileNotFound),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      bool opened = false;

      // Mobile: open directly via Navigator and temporarily hide the video surface to avoid texture overlay
      if (Platform.isAndroid) {
        final wasPlaying = _player?.state.playing == true ||
            (_vlcController?.value.isPlaying == true);
        try {
          await _suspendVideoForRoutePush();
          if (mounted) {
            try {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            } catch (_) {}
          }

          // Load image bytes before opening viewer
          debugPrint('📂 Loading screenshot from: $filePath');
          final imageFile = File(filePath);
          final exists = await imageFile.exists();
          debugPrint('   File exists: $exists');
          final imageBytes = await imageFile.readAsBytes();
          debugPrint('   ✅ Loaded ${imageBytes.length} bytes');
          // Verify bytes are valid image data (PNG signature: 89 50 4E 47)
          if (imageBytes.length > 4) {
            final isPng = imageBytes[0] == 0x89 &&
                imageBytes[1] == 0x50 &&
                imageBytes[2] == 0x4E &&
                imageBytes[3] == 0x47;
            debugPrint('   Is valid PNG: $isPng');
          }

          if (mounted) {
            await Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => ImageViewerScreen(
                  file: imageFile,
                  imageBytes: imageBytes,
                ),
              ),
            );
          }
          return;
        } catch (e, stack) {
          debugPrint('Navigator push ImageViewerScreen failed (Android): $e');
          debugPrint('Stack trace: $stack');
        } finally {
          // Restore video after returning from ImageViewerScreen
          await _resumeVideoAfterRoutePop(resumePlaying: wasPlaying);
        }
      }

      if (Platform.isIOS) {
        final wasPlaying = _player?.state.playing == true ||
            (_vlcController?.value.isPlaying == true);
        try {
          // Pause playback and hide video surface (prevents texture overlay above pushed route)
          await _pauseVideo();
          if (mounted) {
            setState(() {
              _suspendVideoSurface = true;
            });
          }

          // Load image bytes before opening viewer
          debugPrint('📂 Loading screenshot (iOS) from: $filePath');
          final imageFile = File(filePath);
          final exists = await imageFile.exists();
          debugPrint('   File exists: $exists');
          final imageBytes = await imageFile.readAsBytes();
          debugPrint('   ✅ Loaded ${imageBytes.length} bytes');
          // Verify bytes are valid image data
          if (imageBytes.length > 4) {
            final isPng = imageBytes[0] == 0x89 &&
                imageBytes[1] == 0x50 &&
                imageBytes[2] == 0x4E &&
                imageBytes[3] == 0x47;
            debugPrint('   Is valid PNG: $isPng');
          }

          // Ensure one frame renders without the video texture before pushing new route
          await Future.delayed(const Duration(milliseconds: 50));
          if (mounted) {
            await Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => ImageViewerScreen(
                  file: imageFile,
                  imageBytes: imageBytes,
                ),
              ),
            );
          }
        } catch (e, stackTrace) {
          debugPrint('Navigator push ImageViewerScreen failed (mobile): $e');
          debugPrint('Stack trace: $stackTrace');
        } finally {
          if (mounted) {
            setState(() {
              _suspendVideoSurface = false;
            });
          }
          // Optionally resume playback
          try {
            if (wasPlaying) {
              if (_player != null) {
                await _player!.play();
              } else if (_vlcController != null) {
                await _vlcController!.play();
              }
            }
          } catch (_) {}
        }
        return;
      }

      // Try to find TabManagerBloc in the widget tree
      try {
        if (mounted) {
          // Check if TabManagerBloc is available in the context
          BlocProvider.of<TabManagerBloc>(context, listen: false);
          // If we got here, TabManagerBloc is available
          final encoded = Uri.encodeComponent(filePath);
          final routePath = '#image?path=$encoded';

          TabNavigator.openTab(
            context,
            routePath,
            // Let SystemScreenRouter update tab title to the image file name
          );
          opened = true;
          debugPrint('SUCCESS: Opened image tab via TabManager: $routePath');
        }
      } catch (e, stackTrace) {
        debugPrint(
            'TabManager.openTab failed (TabManagerBloc not in context): $e');
        debugPrint('Stack trace: $stackTrace');
        // Continue to fallback methods
      }

      debugPrint('After TabManager attempt, opened: $opened');

      if (!opened) {
        // Fallback: push in-app image viewer route
        debugPrint('Attempting fallback: Navigator push ImageViewerScreen');
        try {
          if (mounted) {
            await Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (_) => ImageViewerScreen(file: File(filePath)),
              ),
            );
            opened = true;
            debugPrint('SUCCESS: Opened image via Navigator push');
          }
        } catch (e, stackTrace) {
          debugPrint('Navigator push ImageViewerScreen failed: $e');
          debugPrint('Stack trace: $stackTrace');
        }
      }

      if (!opened) {
        // Last resort: open with system handler
        try {
          final result = await OpenFilex.open(filePath);
          debugPrint('OpenFilex result: ${result.type} - ${result.message}');
          // Check if the result indicates success
          opened = result.type.toString().contains('done');
        } catch (e) {
          debugPrint('OpenFilex failed: $e');
        }
      }

      if (!opened) {
        // Final fallback: try to launch file URI
        try {
          final uri = Uri.file(filePath);
          final can = await canLaunchUrl(uri);
          if (can) {
            await launchUrl(uri);
            opened = true;
          } else {
            throw 'Cannot launch file URI';
          }
        } catch (e) {
          debugPrint('Launch file URI failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localizations.screenshotCannotOpenTab),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }

      debugPrint('========== END SCREENSHOT OPEN IMAGE DEBUG ==========');
    } catch (e, st) {
      debugPrint('========== SCREENSHOT OPEN IMAGE ERROR ==========');
      debugPrint('ERROR: $e');
      debugPrint(st.toString());
      debugPrint('========== END ERROR ==========');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${localizations.screenshotErrorOpeningFolder}: ${e.toString()}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Advanced controls menu với popup menu để giảm số nút trên thanh điều khiển
  Widget _buildAdvancedControlsMenu() {
    return VideoPlayerAdvancedMenu(
      onScreenshot: _takeScreenshot,
      onAudioTracks: _showAudioTrackDialog,
      onSubtitles: _showSubtitleDialog,
      onSpeed: _showPlaybackSpeedDialog,
      onPip: _togglePictureInPicture,
      onFilters: _showVideoFiltersDialog,
      onSleepTimer: _showSleepTimerDialog,
      onSettings: _showSettingsDialog,
      hasSubtitles: _subtitleTracks.isNotEmpty,
      playbackSpeed: _playbackSpeed,
      isPictureInPicture: _isPictureInPicture,
      sleepDuration: _sleepDuration,
    );
  }

  void _showSubtitleDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Subtitles'),
        content: SubtitleDialogContent(
          tracks: _subtitleTracks,
          selected: _selectedSubtitleTrack,
          onSelect: (v) => setState(() => _selectedSubtitleTrack = v),
        ),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showPlaybackSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Playback Speed'),
        content: PlaybackSpeedDialogContent(
          current: _playbackSpeed,
          onSelect: (v) {
            setState(() => _playbackSpeed = v);
            _setPlaybackSpeed(v);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showVideoFiltersDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Video Filters'),
          content: VideoFiltersDialogContent(
            brightness: _brightness,
            contrast: _contrast,
            saturation: _saturation,
            onBrightnessChanged: (v) {
              setState(() => _brightness = v);
              setDialogState(() {});
            },
            onContrastChanged: (v) {
              setState(() => _contrast = v);
              setDialogState(() {});
            },
            onSaturationChanged: (v) {
              setState(() => _saturation = v);
              setDialogState(() {});
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  _brightness = 1.0;
                  _contrast = 1.0;
                  _saturation = 1.0;
                });
                setDialogState(() {});
              },
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => RouteUtils.safePopDialog(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sleep Timer'),
        content: SleepTimerDialogContent(
          selected: _sleepDuration,
          onSelect: (v) {
            if (v == null) {
              _cancelSleepTimer();
            } else {
              _setSleepTimer(v);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => RouteUtils.safePopDialog(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Video Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Codec Selection
                const Text('Codec:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _selectedCodec,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'h264', child: Text('H.264')),
                    DropdownMenuItem(value: 'h265', child: Text('H.265/HEVC')),
                    DropdownMenuItem(value: 'vp9', child: Text('VP9')),
                    DropdownMenuItem(value: 'av1', child: Text('AV1')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        _selectedCodec = value;
                      });
                      setState(() {
                        _selectedCodec = value;
                      });
                      _saveSettings();
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Video Scale Mode
                const Text('Video Scale Mode:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _videoScaleMode,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'cover', child: Text('Cover (Fill & Crop)')),
                    DropdownMenuItem(
                        value: 'contain', child: Text('Contain (Fit All)')),
                    DropdownMenuItem(
                        value: 'fill', child: Text('Fill (Stretch)')),
                    DropdownMenuItem(
                        value: 'fitWidth', child: Text('Fit Width')),
                    DropdownMenuItem(
                        value: 'fitHeight', child: Text('Fit Height')),
                    DropdownMenuItem(
                        value: 'none', child: Text('None (Original Size)')),
                    DropdownMenuItem(
                        value: 'scaleDown', child: Text('Scale Down')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        _videoScaleMode = value;
                      });
                      setState(() {
                        _videoScaleMode = value;
                      });
                      _saveSettings();
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Hardware Acceleration
                SwitchListTile(
                  title: const Text('Hardware Acceleration'),
                  subtitle: const Text('Use GPU for video decoding'),
                  value: _hardwareAcceleration,
                  onChanged: (value) {
                    setDialogState(() {
                      _hardwareAcceleration = value;
                      _videoDecoder = value ? 'hardware' : 'software';
                    });
                    setState(() {
                      _hardwareAcceleration = value;
                      _videoDecoder = value ? 'hardware' : 'software';
                      if (_player != null) {
                        // Recreate video controller so the change takes effect
                        _videoController = VideoController(
                          _player!,
                          configuration: VideoControllerConfiguration(
                            enableHardwareAcceleration: _hardwareAcceleration,
                          ),
                        );
                      }
                    });
                    _saveSettings();
                  },
                ),

                // Video Decoder
                const Text('Video Decoder:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _videoDecoder,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(
                        value: 'software', child: Text('Software')),
                    DropdownMenuItem(
                        value: 'hardware', child: Text('Hardware')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        _videoDecoder = value;
                        if (value == 'software') {
                          _hardwareAcceleration = false;
                        } else if (value == 'hardware') {
                          _hardwareAcceleration = true;
                        }
                      });
                      setState(() {
                        _videoDecoder = value;
                        if (value == 'software') {
                          _hardwareAcceleration = false;
                        } else if (value == 'hardware') {
                          _hardwareAcceleration = true;
                        }
                        if (_player != null) {
                          _videoController = VideoController(
                            _player!,
                            configuration: VideoControllerConfiguration(
                              enableHardwareAcceleration: _hardwareAcceleration,
                            ),
                          );
                        }
                      });
                      _saveSettings();
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Audio Decoder
                const Text('Audio Decoder:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _audioDecoder,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(
                        value: 'software', child: Text('Software')),
                    DropdownMenuItem(
                        value: 'hardware', child: Text('Hardware')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        _audioDecoder = value;
                      });
                      setState(() {
                        _audioDecoder = value;
                      });
                      _saveSettings();
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Buffer Size
                VideoPlayerLabeledSlider(
                  label: 'Buffer Size: ${_bufferSize}MB',
                  value: _bufferSize.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  onChanged: (value) {
                    setDialogState(() {
                      _bufferSize = value.round();
                    });
                    setState(() {
                      _bufferSize = value.round();
                    });
                    _saveSettings();
                  },
                ),

                // Network Timeout
                VideoPlayerLabeledSlider(
                  label: 'Network Timeout: ${_networkTimeout}s',
                  value: _networkTimeout.toDouble(),
                  min: 5,
                  max: 120,
                  divisions: 23,
                  onChanged: (value) {
                    setDialogState(() {
                      _networkTimeout = value.round();
                    });
                    setState(() {
                      _networkTimeout = value.round();
                    });
                    _saveSettings();
                  },
                ),

                // Subtitle Encoding
                const Text('Subtitle Encoding:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _subtitleEncoding,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'utf-8', child: Text('UTF-8')),
                    DropdownMenuItem(value: 'utf-16', child: Text('UTF-16')),
                    DropdownMenuItem(
                        value: 'iso-8859-1', child: Text('ISO-8859-1')),
                    DropdownMenuItem(
                        value: 'windows-1252', child: Text('Windows-1252')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        _subtitleEncoding = value;
                      });
                      setState(() {
                        _subtitleEncoding = value;
                      });
                      _saveSettings();
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Video Output Format
                const Text('Video Output Format:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<String>(
                  value: _videoOutputFormat,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('Auto')),
                    DropdownMenuItem(value: 'yuv420p', child: Text('YUV420P')),
                    DropdownMenuItem(value: 'rgb24', child: Text('RGB24')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        _videoOutputFormat = value;
                      });
                      setState(() {
                        _videoOutputFormat = value;
                      });
                      _saveSettings();
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _resetSettings();
                setDialogState(() {});
              },
              child: const Text('Reset to Default'),
            ),
            TextButton(
              onPressed: () => RouteUtils.safePopDialog(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  // Helper methods for advanced features
  void _setPlaybackSpeed(double speed) {
    if (_player != null) {
      _player!.setRate(speed);
    } else if (_vlcController != null) {
      _vlcController!.setPlaybackSpeed(speed);
    }
  }

  Future<void> _togglePictureInPicture() async {
    // Android: enter native Picture-in-Picture
    if (Platform.isAndroid) {
      try {
        const channel = MethodChannel('cb_file_manager/pip');

        // Determine aspect ratio from current video if possible
        int w = 16;
        int h = 9;
        try {
          if (_player != null) {
            final pw = _player!.state.width;
            final ph = _player!.state.height;
            if (pw != null && ph != null && pw > 0 && ph > 0) {
              w = pw;
              h = ph;
            }
          } else if (_vlcController != null) {
            // For VLC, use default 16:9 ratio as fallback
            // VLC doesn't expose video dimensions easily
            w = 16;
            h = 9;
          }
        } catch (_) {
          // Fallback to 16:9 if we can't get dimensions
          w = 16;
          h = 9;
        }

        // Pause Flutter-side playback to avoid double audio; native player will take over in PiP.
        try {
          if (_vlcController != null && _vlcController!.value.isPlaying) {
            await _vlcController!.pause();
          } else if (_player != null && _player!.state.playing) {
            await _player!.pause();
          }
        } catch (_) {}
        // Set Android PiP state before entering PiP mode so UI hides overlays
        setState(() => _isAndroidPip = true);

        // Build source info for native PiP player
        String sourceTypeForPip = 'url';
        String sourceForPip = '';
        if (widget.file != null) {
          sourceTypeForPip = 'file';
          sourceForPip = widget.file!.path;
        } else if (widget.streamingUrl != null) {
          sourceTypeForPip = 'url';
          sourceForPip = widget.streamingUrl!;
        } else if (widget.smbMrl != null) {
          try {
            final uri =
                await SmbHttpProxyServer.instance.urlFor(widget.smbMrl!);
            sourceTypeForPip = 'url';
            sourceForPip = uri.toString();
          } catch (_) {}
        }

        try {
          final result = await channel.invokeMethod('enterPip', {
            'width': w,
            'height': h,
            // Provide native with source so it can render independently of Flutter
            'sourceType': sourceTypeForPip,
            'source': sourceForPip,
            'positionMs': _player != null
                ? _player!.state.position.inMilliseconds
                : _vlcController!.value.position.inMilliseconds,
            'playing': true,
            'volume': _player != null
                ? (_player!.state.volume.clamp(0.0, 100.0) / 100.0)
                : (_vlcVolume.clamp(0.0, 100.0) / 100.0),
          });

          if (result == true) {
            debugPrint('PiP entered successfully');
          } else {
            debugPrint('PiP entry failed');
            if (mounted) {
              setState(() => _isAndroidPip = false);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Không thể bật PiP trên Android')),
              );
            }
          }
        } catch (e) {
          debugPrint('PiP method call error: $e');
          if (mounted) {
            setState(() => _isAndroidPip = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi PiP: $e')),
            );
          }
        }
      } catch (e) {
        debugPrint('PIP error: $e');
        if (mounted) {
          setState(() => _isAndroidPip = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi PiP: $e')),
          );
        }
      }
      return;
    }

    // Desktop (Windows): prefer external window; fallback to overlay if needed
    if (Platform.isWindows) {
      // Read user preference: default to external PiP window
      bool preferExternal = true;
      try {
        final up = UserPreferences.instance;
        await up.init();
        preferExternal = await up.getVideoPlayerBool('windows_pip_external',
                defaultValue: true) ??
            true;
      } catch (_) {}
      final positionMs = _player != null
          ? _player!.state.position.inMilliseconds
          : _vlcController!.value.position.inMilliseconds;
      final volume = _player != null
          ? (_player!.state.volume).clamp(0.0, 100.0)
          : _vlcVolume.clamp(0.0, 100.0);
      final playing = _player != null
          ? _player!.state.playing
          : _vlcController!.value.isPlaying;

      String? sourceType;
      String? source;
      if (widget.streamingUrl != null && widget.streamingUrl!.isNotEmpty) {
        sourceType = 'url';
        source = widget.streamingUrl!;
      } else if (widget.file != null) {
        sourceType = 'file';
        source = widget.file!.path;
      } else if (widget.smbMrl != null) {
        try {
          final uri = await SmbHttpProxyServer.instance.urlFor(widget.smbMrl!);
          sourceType = 'url';
          source = uri.toString();
        } catch (_) {
          sourceType = 'smb';
          source = widget.smbMrl!;
        }
      }

      if (sourceType == null || source == null || source.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không có nguồn video để mở PiP')),
          );
        }
        return;
      }

      if (preferExternal) {
        // Attempt external PiP window process first
        // Start IPC server for PiP -> main sync
        _startPipIpcServer().then((ipc) {
          final args = <String, dynamic>{
            'sourceType': sourceType,
            'source': source,
            'fileName': widget.fileName,
            'positionMs': positionMs,
            'volume': volume,
            'playing': playing,
          };
          if (ipc != null) {
            args['ipcPort'] = ipc['port'];
            args['ipcToken'] = ipc['token'];
          }

          final ok = PipWindowService.openDesktopPipWindow(args);
          ok.then((started) async {
            if (started) {
              // Pause current playback to avoid double audio
              try {
                if (_player != null && _player!.state.playing) {
                  await _player!.pause();
                } else if (_vlcController != null &&
                    _vlcController!.value.isPlaying) {
                  await _vlcController!.pause();
                }
              } catch (_) {}
              if (mounted) {
                setState(() => _isPictureInPicture = true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã mở PiP ở cửa sổ riêng')),
                );
              }
            } else {
              // External failed: close IPC and fallback to overlay
              _closePipIpc();
              if (mounted) {
                _showWindowsOverlayPip(
                  context,
                  sourceType: sourceType!,
                  source: source!,
                  fileName: widget.fileName,
                  positionMs: positionMs,
                  volume: volume,
                  playing: playing,
                );
              }
            }
          });
        });
        return;
      }

      // Prefer overlay per user setting
      if (mounted) {
        _showWindowsOverlayPip(
          context,
          sourceType: sourceType,
          source: source,
          fileName: widget.fileName,
          positionMs: positionMs,
          volume: volume,
          playing: playing,
        );
      }
      return;
    }

    // Other platforms: not implemented yet
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PiP chưa hỗ trợ trên nền tảng này'),
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _startPipIpcServer() async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _pipServer = server;
      _pipToken = _generateIpcToken();
      _pipServerSub = server.listen((client) {
        _pipClient = client;
        // Expect line-delimited UTF8 JSON
        _pipMsgSub = client
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(_handlePipMessage, onDone: () {
          _closePipIpc();
        }, onError: (e) {
          _closePipIpc();
        });
      });
      return {
        'port': server.port,
        'token': _pipToken!,
      };
    } catch (e) {
      debugPrint('Failed to start PiP IPC server: $e');
      _closePipIpc();
      return null;
    }
  }

  void _closePipIpc() {
    try {
      _pipMsgSub?.cancel();
      _pipServerSub?.cancel();
      _pipClient?.destroy();
      _pipServer?.close();
    } catch (_) {}
    _pipMsgSub = null;
    _pipServerSub = null;
    _pipClient = null;
    _pipServer = null;
    _pipToken = null;
    if (mounted) {
      setState(() {
        _isPictureInPicture = false;
      });
    }
  }

  void _handlePipMessage(String line) async {
    try {
      final data = jsonDecode(line);
      if (data is! Map) return;
      final token = data['token'];
      if (token != _pipToken) return; // ignore unknown
      final type = data['type'] as String?;
      if (type == 'closing') {
        final pos = (data['positionMs'] as num?)?.toInt() ?? 0;
        final vol = (data['volume'] as num?)?.toDouble();
        final playing = data['playing'] == true;
        // Apply state
        try {
          if (_player != null) {
            await _player!.seek(Duration(milliseconds: pos));
            if (vol != null) await _player!.setVolume(vol.clamp(0.0, 100.0));
            if (playing) {
              await _player!.play();
            } else {
              await _player!.pause();
            }
          } else if (_vlcController != null) {
            await _vlcController!.seekTo(Duration(milliseconds: pos));
            if (vol != null) {
              await _vlcController!.setVolume(vol.toInt());
            }
            if (playing) {
              await _vlcController!.play();
            } else {
              await _vlcController!.pause();
            }
          }
        } catch (e) {
          debugPrint('Failed applying PiP state: $e');
        }
      }
      if (type == 'closing') {
        // Focus main window and cleanup IPC
        try {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            await windowManager.focus();
          }
        } catch (_) {}
        _closePipIpc();
      }
    } catch (e) {
      debugPrint('Invalid PiP IPC message: $e');
    }
  }

  String _generateIpcToken() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = (ts ^ (ts << 7)) & 0x7FFFFFFF;
    return r.toRadixString(36) + ts.toRadixString(36);
  }

  void _setSleepTimer(Duration duration) {
    _cancelSleepTimer();
    setState(() {
      _sleepDuration = duration;
    });

    _sleepTimer = Timer(duration, () {
      if (mounted) {
        _pauseVideo();
        setState(() {
          _sleepDuration = null;
        });
      }
    });
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    setState(() {
      _sleepDuration = null;
    });
  }

  // Settings management methods
  Future<void> _saveSettings() async {
    try {
      final userPreferences = UserPreferences.instance;
      await userPreferences.init();

      // Save video player settings using new methods
      await userPreferences.setVideoPlayerString('video_codec', _selectedCodec);
      await userPreferences.setVideoPlayerBool(
          'hardware_acceleration', _hardwareAcceleration);
      await userPreferences.setVideoPlayerString(
          'video_decoder', _videoDecoder);
      await userPreferences.setVideoPlayerString(
          'audio_decoder', _audioDecoder);
      await userPreferences.setVideoPlayerInt('buffer_size', _bufferSize);
      await userPreferences.setVideoPlayerInt(
          'network_timeout', _networkTimeout);
      await userPreferences.setVideoPlayerString(
          'subtitle_encoding', _subtitleEncoding);
      await userPreferences.setVideoPlayerString(
          'video_output_format', _videoOutputFormat);
      await userPreferences.setVideoPlayerString(
          'video_scale_mode', _videoScaleMode);

      debugPrint('Video player settings saved successfully');
    } catch (e) {
      debugPrint('Error saving video player settings: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final userPreferences = UserPreferences.instance;
      await userPreferences.init();

      // Load video player settings with defaults using new methods
      _selectedCodec = await userPreferences.getVideoPlayerString('video_codec',
              defaultValue: 'auto') ??
          'auto';
      _hardwareAcceleration = await userPreferences.getVideoPlayerBool(
              'hardware_acceleration',
              defaultValue: true) ??
          true;
      _videoDecoder = await userPreferences
              .getVideoPlayerString('video_decoder', defaultValue: 'auto') ??
          'auto';
      _audioDecoder = await userPreferences
              .getVideoPlayerString('audio_decoder', defaultValue: 'auto') ??
          'auto';
      _bufferSize = await userPreferences.getVideoPlayerInt('buffer_size',
              defaultValue: 10) ??
          10;
      _networkTimeout = await userPreferences
              .getVideoPlayerInt('network_timeout', defaultValue: 30) ??
          30;
      _subtitleEncoding = await userPreferences.getVideoPlayerString(
              'subtitle_encoding',
              defaultValue: 'utf-8') ??
          'utf-8';
      _videoOutputFormat = await userPreferences.getVideoPlayerString(
              'video_output_format',
              defaultValue: 'auto') ??
          'auto';
      _videoScaleMode = await userPreferences.getVideoPlayerString(
              'video_scale_mode',
              defaultValue: 'contain') ??
          'contain';

      // Keep hardware acceleration in sync with explicit decoder choice
      if (_videoDecoder == 'software') {
        _hardwareAcceleration = false;
      } else if (_videoDecoder == 'hardware') {
        _hardwareAcceleration = true;
      }

      debugPrint('Video player settings loaded successfully');
    } catch (e) {
      debugPrint('Error loading video player settings: $e');
    }
  }

  void _resetSettings() {
    setState(() {
      _selectedCodec = 'auto';
      _hardwareAcceleration = true;
      _videoDecoder = 'auto';
      _audioDecoder = 'auto';
      _bufferSize = 10;
      _networkTimeout = 30;
      _subtitleEncoding = 'utf-8';
      _videoOutputFormat = 'auto';
      _videoScaleMode = 'contain';
    });
    _saveSettings();
  }

  Future<void> _pauseVideo() async {
    if (_player != null) {
      await _player!.pause();
      setState(() {
        _isPlaying = false;
      });
    } else if (_vlcController != null) {
      await _vlcController!.pause();
    }
  }

  /// Starts the seeking state to prevent UI flickering during seek operations
  void _startSeeking() {
    if (!_isSeeking) {
      setState(() {
        _isSeeking = true;
      });
    }

    // Cancel existing timer
    _seekingTimer?.cancel();

    // Set timer to end seeking state after a brief delay
    _seekingTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isSeeking = false;
        });
      }
    });
  }

  // Temporarily tear down platform video views to avoid overlay issues on Android when pushing routes.
  Future<void> _suspendVideoForRoutePush() async {
    try {
      await _pauseVideo();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _suspendVideoSurface = true;
      });
    }
    if (Platform.isAndroid) {
      try {
        await _exoController?.pause();
      } catch (_) {}
      try {
        await _vlcController?.pause();
      } catch (_) {}
      try {
        await _vlcController?.dispose();
      } catch (_) {}
      _vlcController = null;
      try {
        await _exoController?.dispose();
      } catch (_) {}
      _exoController = null;
      try {
        // no dispose needed for VideoController
      } catch (_) {}
      _videoController = null;
    }
    // Ensure one frame is rendered without any platform views
    await Future.delayed(const Duration(milliseconds: 16));
  }

  // Restore video output after returning from pushed routes.
  Future<void> _resumeVideoAfterRoutePop({bool resumePlaying = false}) async {
    if (mounted) {
      setState(() {
        _suspendVideoSurface = false;
      });
    }

    // On Android, we need to rebuild controllers after they were disposed during suspend
    if (Platform.isAndroid) {
      // Check if we were using VLC before suspension
      final needsVlcRestore = _useFlutterVlc && _vlcController == null;
      // Check if we were using Media Kit before suspension
      final needsMediaKitRestore =
          !_useFlutterVlc && _videoController == null && _player != null;

      if (needsVlcRestore) {
        try {
          // Re-initialize VLC controller based on source type
          if (widget.smbMrl != null) {
            _vlcController = _createSmbVlcController(
              smbMrl: widget.smbMrl!,
              useUserInfoInUrl: false,
              autoPlay: false,
            );
            _scheduleVlcAutoPlayKick(autoPlay: resumePlaying);
          } else if (widget.streamingUrl != null) {
            // HTTP/HTTPS or other stream URL
            _vlcController = VlcPlayerController.network(
              widget.streamingUrl!,
              hwAcc: HwAcc.full,
              autoPlay: resumePlaying,
              options: VlcPlayerOptions(
                advanced: VlcAdvancedOptions([
                  '--network-caching=1000',
                ]),
                video: VlcVideoOptions([
                  '--android-display-chroma=RV32',
                ]),
              ),
            );
          } else if (widget.file != null) {
            // Local file
            _vlcController = VlcPlayerController.file(
              widget.file!,
              hwAcc: HwAcc.full,
              autoPlay: resumePlaying,
              options: VlcPlayerOptions(
                video: VlcVideoOptions([
                  '--android-display-chroma=RV32',
                ]),
              ),
            );
          }

          debugPrint('VLC controller restored after route pop');
          _vlcListenerAttached = false; // Reset listener flag
          _vlcInitVolumeHookAttached = false;
          if (_vlcController != null) {
            _vlcInitVolumeHookAttached = true;
            _vlcController!.addOnInitListener(() {
              _applyVolumeToActiveController(updateUi: false);
            });
          }
          if (mounted) {
            setState(() {}); // Trigger rebuild to render new VLC controller
          }
        } catch (e) {
          debugPrint('Error restoring VLC controller: $e');
        }
        return;
      } else if (needsMediaKitRestore) {
        // Re-create media_kit video controller
        try {
          _videoController = VideoController(
            _player!,
            configuration: VideoControllerConfiguration(
              enableHardwareAcceleration: _hardwareAcceleration,
            ),
          );
          debugPrint('Media Kit VideoController restored after route pop');
          if (mounted) {
            setState(() {}); // Trigger rebuild
          }
        } catch (e) {
          debugPrint('Error restoring Media Kit VideoController: $e');
        }
      }

      // Resume playback if needed
      if (resumePlaying) {
        try {
          if (_player != null) {
            await _player!.play();
          } else if (_vlcController != null) {
            await _vlcController!.play();
          }
        } catch (e) {
          debugPrint('Error resuming playback: $e');
        }
      }
      return;
    }

    // Desktop: Re-create media_kit video controller if needed
    if (_player != null && _videoController == null) {
      try {
        _videoController = VideoController(
          _player!,
          configuration: VideoControllerConfiguration(
            enableHardwareAcceleration: _hardwareAcceleration,
          ),
        );
      } catch (_) {}
    }
    if (resumePlaying) {
      try {
        if (_player != null) {
          await _player!.play();
        } else if (_vlcController != null) {
          await _vlcController!.play();
        }
      } catch (_) {}
    }
  }
}
