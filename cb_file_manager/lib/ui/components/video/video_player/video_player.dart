// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/services/media/media_kit_playback.dart';
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
import '../../streaming/stream_speed_indicator.dart';
import '../../streaming/buffer_info_widget.dart';
import '../../../utils/route.dart';
import '../../../../config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import '../../../tab_manager/core/tab_manager.dart';
import 'video_player_advanced_menu.dart';
import 'video_player_control_buttons.dart';
import 'video_player_dialogs.dart';
import 'video_player_fast_seek.dart';
import 'video_player_loading.dart';
import 'video_player_models.dart';
import 'video_player_seek_preview.dart';
import 'video_player_seek_slider.dart';
import 'video_player_utils.dart';

part 'video_player.volume.dart';
part 'video_player.settings.dart';

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
  final ValueChanged<bool>? onControlVisibilityChanged;
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
    super.key,
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
  }) : assert(
         file != null ||
             streamingUrl != null ||
             smbMrl != null ||
             fileStream != null,
         'At least one media source must be provided',
       );

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
    ValueChanged<bool>? onControlVisibilityChanged,
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
           VideoPlayerUtils.extensionFromPath(file.path),
         ),
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
    ValueChanged<bool>? onControlVisibilityChanged,
    VoidCallback? onFullScreenChanged,
    VoidCallback? onInitialized,
    bool showStreamingSpeed = false,
    VoidCallback? onToggleStreamingSpeed,
  }) : this._(
         key: key,
         streamingUrl: streamingUrl,
         fileName: fileName,
         fileType:
             fileType ??
             FileTypeRegistry.getCategory(
               VideoPlayerUtils.extensionFromPath(fileName),
             ),
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
    ValueChanged<bool>? onControlVisibilityChanged,
    VoidCallback? onFullScreenChanged,
    VoidCallback? onInitialized,
    bool showStreamingSpeed = false,
    VoidCallback? onToggleStreamingSpeed,
  }) : this._(
         key: key,
         smbMrl: smbMrl,
         fileName: fileName,
         fileType:
             fileType ??
             FileTypeRegistry.getCategory(
               VideoPlayerUtils.extensionFromPath(fileName),
             ),
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
    ValueChanged<bool>? onControlVisibilityChanged,
    VoidCallback? onFullScreenChanged,
    VoidCallback? onInitialized,
    bool showStreamingSpeed = false,
    VoidCallback? onToggleStreamingSpeed,
  }) : this._(
         key: key,
         fileStream: fileStream,
         fileName: fileName,
         fileType:
             fileType ??
             FileTypeRegistry.getCategory(
               VideoPlayerUtils.extensionFromPath(fileName),
             ),
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

class _VideoPlayerState extends _VideoPlayerSettingsHost
    with
        WidgetsBindingObserver,
        _VideoPlayerVolumeMixin,
        _VideoPlayerSettingsMixin {
  // media_kit controllers
  @override
  PlaybackPlayer? _player;
  @override
  PlaybackVideoController? _videoController;

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
  @override
  double _savedVolume = 70.0;
  bool _showControls = true;
  final bool _showSpeedIndicator = false;

  // Persist a software-decoding preference only once after a GPU error.
  bool _hwDecodeFallbackAttempted = false;

  // Seeking state to prevent loading indicator during seek
  bool _isSeeking = false;
  Timer? _seekingTimer;
  Duration? _seekDragPosition;
  Timer? _seekPreviewTimer;
  Duration? _pendingSeekPreview;
  bool _resumeAfterSeekDrag = false;

  // Seek bar hover thumbnails, decoded apart from the main player.
  VideoSeekPreviewController? _seekHoverFrames;
  bool _isHoveringSeekBar = false;

  // New advanced features state
  @override
  final List<SubtitleTrack> _subtitleTracks = [];
  @override
  int? _selectedSubtitleTrack = -1;
  @override
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
  @override
  double _brightness = 0.0; // -1.0 to 1.0
  @override
  double _contrast = 0.0; // -1.0 to 1.0
  @override
  double _saturation = 0.0; // -1.0 to 1.0

  // Sleep timer
  Timer? _sleepTimer;
  @override
  Duration? _sleepDuration;

  // Video statistics - placeholder for future use
  Timer? _statsUpdateTimer;

  // Video player settings
  @override
  String _selectedCodec = 'auto'; // auto, h264, h265, vp9, av1
  @override
  // Preserve the established Windows software-decoding default.
  bool _hardwareAcceleration = kIsWeb ? true : !Platform.isWindows;
  @override
  String _videoDecoder = 'auto'; // auto, software, hardware
  @override
  String _audioDecoder = 'auto'; // auto, software, hardware
  @override
  int _bufferSize = 10; // MB
  @override
  int _networkTimeout = 30; // seconds
  @override
  String _subtitleEncoding = 'utf-8';
  @override
  String _videoOutputFormat = 'auto'; // auto, yuv420p, rgb24
  @override
  String _videoScaleMode = 'contain'; // cover, contain, fill, fitWidth, fitHeight, none, scaleDown

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

  @override
  double _lastVolume = 70.0;
  @override
  bool _isRestoringVolume = false;

  Map<String, dynamic>? _videoMetadata;
  bool _hasNotifiedInitialization = false;

  // Clicking the player focuses it, so its keys work when it's embedded
  // (e.g. the file preview pane) and autofocus didn't apply.
  final FocusNode _keyboardFocusNode = FocusNode(
    debugLabel: 'video-player-keyboard',
  );

  // Fast forward/rewind state (long press on mobile, hold arrow on desktop)
  bool _isFastSeeking = false;
  bool _fastSeekingForward = true; // true = forward, false = backward
  Timer? _fastSeekTimer;
  int _fastSeekSeconds = 5; // Current seek amount, increases over time
  int _fastSeekTicks = 0; // Count of seek ticks to accelerate
  // Seek speed: 0=slow, 1=medium, 2=fast — loaded from preferences
  @override
  int _videoSeekSpeed = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    VideoUiState.notifyPlayerMounted();

    // Ensure system UI is visible when video player starts (not fullscreen)
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
      // Explicitly set light status bar icons to ensure visibility on dark backgrounds
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      // Guard against plugins or platform views hiding system UI unexpectedly
      SystemChrome.setSystemUIChangeCallback((visible) async {
        if (!mounted) return;
        if (!_isFullScreen && visible == false) {
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
          );
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
        onClose:
            ({
              required int positionMs,
              required double volume,
              required bool playing,
            }) async {
              try {
                if (_player != null) {
                  await _player!.seek(Duration(milliseconds: positionMs));
                  await _player!.setVolume(volume.clamp(0.0, 100.0));
                  if (playing) {
                    await _player!.play();
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
        final l10n = AppLocalizations.of(context)!;
        AppToast.success(context, l10n.pipOverlayEnabled);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VideoUiState.notifyPlayerDisposed();
    _disposeResources();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startHideControlsTimer();
    }
  }

  void _disposeResources() {
    try {
      _hideControlsTimer?.cancel();

      _initializationTimeout?.cancel();
      _noDataTimer?.cancel();
      _bufferSub?.cancel();
      _sleepTimer?.cancel();
      _statsUpdateTimer?.cancel();
      _seekingTimer?.cancel();
      _seekPreviewTimer?.cancel();
      _seekPreviewTimer = null;
      _pendingSeekPreview = null;
      _seekDragPosition = null;
      _resumeAfterSeekDrag = false;
      _isSeeking = false;
      _seekHoverFrames?.dispose();
      _seekHoverFrames = null;
      _isHoveringSeekBar = false;
      _fastSeekTimer?.cancel();
      _isFastSeeking = false;
      _tempRaf?.close();
      _tempFile?.delete();
      // Clear video controller reference before disposing the player
      _videoController = null;
      _player?.dispose();
      _player = null;

      _streamController?.close();

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
              if (_player != null) {
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

  /// Applies the persisted hardware decoding preference to libmpv.
  @override
  PlaybackVideoConfiguration _buildVideoControllerConfig() {
    return PlaybackVideoConfiguration(
      enableHardwareAcceleration: _hardwareAcceleration,
    );
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = '';
      });

      // Fresh initialization: allow a software-decoding fallback attempt again
      // for this media source.
      _hwDecodeFallbackAttempted = false;
      _hasNotifiedInitialization = false;

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

      // Seek speed is already loaded by _loadSettings, which runs first.
      final (savedVolume, savedMuted) = await (
        userPreferences.getVideoPlayerVolume(),
        userPreferences.getVideoPlayerMute(),
      ).wait;
      _lastVolume = savedVolume > 0 ? savedVolume : _lastVolume;

      setState(() {
        _savedVolume = savedVolume.clamp(0.0, 100.0);

        _isMuted = savedMuted;
      });

      debugPrint(
        'Loaded volume preferences - volume: ${_savedVolume.toStringAsFixed(1)}, muted: $_isMuted',
      );

      // Avoid early player volume stream events overriding restored volume during initialization.
      _isRestoringVolume = true;

      {
        if (_player == null) {
          _player = PlaybackPlayer(
            configuration: PlaybackConfiguration(
              networkCaching: const Duration(seconds: 1),
              looping: widget.looping,
            ),
          );
          _videoController = PlaybackVideoController(
            _player!,
            configuration: _buildVideoControllerConfig(),
          );
          _setupPlayerEventListeners();
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

  void _setupPlayerEventListeners() {
    if (_player == null) return;

    // Track buffering state - but ignore buffering during seek to prevent UI flicker
    _player!.stream.buffering.listen((buffering) {
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

    // Persist only user changes (in the volume mixin). media_kit's initial default
    // volume must not overwrite the restored volume or mute preference.
    _player!.stream.volume.listen((_) {
      if (mounted) setState(() {});
    });
    _player!.stream.duration.listen((duration) {
      if (mounted && duration > Duration.zero) _extractVideoMetadata();
    });
    _player!.stream.width.listen((width) {
      if (mounted && width != null) _extractVideoMetadata();
    });

    // Track errors
    _player!.stream.error.listen((error) {
      debugPrint('Player error: $error');

      // Hardware (D3D11/Direct3D) decoding can fail on some Windows
      // GPUs/drivers or under GPU-memory pressure. We do NOT attempt to
      // recreate the VideoController inline here: that would trigger another
      // D3D11 device creation against an already-failing GPU/driver and can
      // tear down the entire Flutter engine ("Lost connection to device").
      //
      // Instead, persist software decoding for next time and surface a clear
      // error so the user just needs to reopen the video.
      // A missing/unavailable audio device (no sound card, disabled output,
      // headless CI runner) does not stop mpv from decoding and playing
      // video — it just plays silently. Surfacing this as a fatal error
      // would replace working video controls with an error screen over
      // something the user cannot even hear is wrong.
      if (_isAudioDeviceError(error)) {
        return;
      }

      if (_isHardwareDecodeError(error)) {
        _persistSoftwareDecodingPreference();
        if (mounted && !_hasError) {
          setState(() {
            _hasError = true;
            _errorMessage =
                'Video card ran out of memory while decoding this video. '
                'Hardware acceleration has been disabled — please reopen the '
                'video to retry with software decoding.\n\n'
                'Original error: $error';
          });
          widget.onError?.call(_errorMessage);
        }
        return;
      }

      if (mounted && !_hasError) {
        setState(() {
          _hasError = true;
          _errorMessage = error;
        });
        widget.onError?.call(_errorMessage);
      }
    });
  }

  /// Returns true if [error] looks like a hardware/GPU decoding failure that
  /// could be resolved by falling back to software decoding.
  bool _isAudioDeviceError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('audio device') || lower.contains('no sound');
  }

  bool _isHardwareDecodeError(String error) {
    final lower = error.toLowerCase();
    return lower.contains('d3d11') ||
        lower.contains('direct3d') ||
        lower.contains('d3derr') ||
        lower.contains('0x8007000e') || // E_OUTOFMEMORY
        lower.contains('0x8876086a') || // D3DERR_NOTAVAILABLE
        lower.contains('hardware') ||
        lower.contains('hwdec') ||
        lower.contains('gpu');
  }

  /// Persists `hardware_acceleration=false` and `video_decoder=software` so the
  /// next playback session on this machine skips the failing hardware path.
  /// Does not touch the live player/controller — see notes in the error
  /// listener above for why we avoid creating new GPU resources here.
  void _persistSoftwareDecodingPreference() {
    if (_hwDecodeFallbackAttempted) return;
    _hwDecodeFallbackAttempted = true;
    debugPrint(
      'VideoPlayer: persisting software decoding preference after HW failure',
    );
    () async {
      try {
        final prefs = UserPreferences.instance;
        await prefs.init();
        await prefs.setVideoPlayerBool('hardware_acceleration', false);
        await prefs.setVideoPlayerString('video_decoder', 'software');
        // Update in-memory state so a manual settings reopen reflects reality.
        if (mounted) {
          _hardwareAcceleration = false;
          _videoDecoder = 'software';
        }
      } catch (e) {
        debugPrint('VideoPlayer: failed to persist software decoding pref: $e');
      }
    }();
  }

  Future<void> _openMediaSource() async {
    if (widget.file != null) {
      // Local file playback
      await _player!.open(
        PlaybackMedia(widget.file!.path),
        play: widget.autoPlay,
      );
      if (widget.autoPlay) {
        await _player!.play();
      }
    } else if (widget.streamingUrl != null) {
      // Streaming URL playback
      await _player!.open(
        PlaybackMedia(widget.streamingUrl!),
        play: widget.autoPlay,
      );
      if (widget.autoPlay) {
        await _player!.play();
      }
    } else if (widget.smbMrl != null) {
      // Direct SMB playback uses the same media_kit backend as local files.
      {
        await _openSmbMrl();
      }
    } else if (widget.fileStream != null) {
      // File stream playback
      await _openFileStream();
    }

    // Metadata comes from the native media_kit event streams.
  }

  Future<void> _openSmbMrl() async {
    // Preserve authentication and escaping for the shared SMB source resolver.
    await _player!.open(PlaybackMedia(widget.smbMrl!), play: widget.autoPlay);
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
    if (_player != null &&
        (_player!.state.duration > Duration.zero ||
            _player!.state.width != null)) {
      _initializationTimeout?.cancel();
      _videoMetadata = {
        'duration': _player!.state.duration,
        'width': _player!.state.width,
        'height': _player!.state.height,
      };

      widget.onVideoInitialized?.call(_videoMetadata!);
      if (!_hasNotifiedInitialization) {
        _hasNotifiedInitialization = true;
        widget.onInitialized?.call();
      }
    }
  }

  Future<void> _startProgressiveBufferingAndPlay(
    Stream<List<int>> source, {
    int initialBufferBytes = 2 * 1024 * 1024,
    int flushEveryBytes = 512 * 1024,
  }) async {
    final tempDir = Directory.systemTemp;
    _tempFile = File(
      '${tempDir.path}/temp_media_${DateTime.now().millisecondsSinceEpoch}',
    );

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

    _bufferSub = source.listen(
      (chunk) async {
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
              'VideoPlayer: Opening from temp with ${_formatBytes(_bytesWritten)} buffered',
            );
            try {
              await _player!.open(PlaybackMedia(_tempFile!.path));
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
      },
      onError: (e) async {
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
      },
      onDone: () async {
        debugPrint(
          'VideoPlayer: Buffer done at ${_formatBytes(_bytesWritten)}',
        );
        try {
          await _tempRaf?.flush();
          await _tempRaf?.close();
        } catch (_) {}
        _tempRaf = null;
        if (!_playerOpenedFromTemp && _tempFile != null) {
          try {
            await _player!.open(PlaybackMedia(_tempFile!.path));
            if (widget.autoPlay) {
              await _player!.play();
            }
          } catch (e) {
            debugPrint('VideoPlayer: Open on done error: $e');
          }
        }
      },
      cancelOnError: true,
    );
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
    final Widget playerWidget = widget.file != null
        ? _buildLocalFilePlayer()
        : _buildStreamingPlayer();
    return playerWidget;
  }

  Widget _buildLocalFilePlayer() {
    return _videoController == null
        ? const Center(child: CircularProgressIndicator(color: Colors.white))
        : _hasError
        ? _buildErrorWidget(_errorMessage)
        : Focus(
            focusNode: _keyboardFocusNode,
            autofocus: true,
            onKeyEvent: (node, event) => _handleKeyEvent(event),
            onFocusChange: (focused) {
              if (!focused) _stopFastSeeking();
            },
            child: Listener(
              onPointerDown: (_) => _keyboardFocusNode.requestFocus(),
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
                        onDoubleTap: widget.allowFullScreen
                            ? _toggleFullScreen
                            : null,
                        child: _buildPrimaryVideoSurface(),
                      ),
                      if (_isLoading)
                        Positioned.fill(
                          child: IgnorePointer(child: _buildLoadingWidget()),
                        ),
                      if (!_isAndroidPip &&
                          widget.showControls &&
                          _showControls)
                        _buildCustomControls(),
                    ],
                  ),
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
      borderRadius: _isFullScreen
          ? BorderRadius.zero
          : BorderRadius.circular(16.0),
      child: RepaintBoundary(child: surface),
    );
  }

  Widget _buildStreamingPlayer() {
    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      onFocusChange: (focused) {
        if (!focused) _stopFastSeeking();
      },
      child: Listener(
        onPointerDown: (_) => _keyboardFocusNode.requestFocus(),
        child: _buildPlayerBody(),
      ),
    );
  }

  Widget _buildPlayerBody() {
    if (_hasError) {
      return _buildErrorWidget(_errorMessage);
    }

    if (_videoController == null) {
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
    // On Android we prefer media_kit for all sources

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _showControlsWithTimer();
      },
      onDoubleTap: _toggleFullScreen,
      child: Stack(
        // Hidden desktop overlays are SizedBox.shrink(). Without tight
        // constraints they collapse this Stack (and its positioned media_kit surface)
        // to zero when the controls hide, even though playback keeps running.
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _buildVideoWidget()),
          if (_isLoading)
            Positioned.fill(child: IgnorePointer(child: _buildLoadingWidget())),
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

    // Check for media_kit player first (works on all platforms)
    if (_videoController != null) {
      return RepaintBoundary(
        key: _screenshotKey,
        child: Visibility(
          visible: !_suspendVideoSurface,
          maintainState: true,
          child: PlaybackVideo(
            controller: _videoController!,

            fill: Colors.black,
            fit: boxFit,
          ),
        ),
      );
    } else {
      return _buildLoadingWidget();
    }
  }

  // Initialize Exo for Android as a media_kit fallback (non-PiP & PiP)

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

  /// Single unified loading: same minimal spinner for init and for video placeholder.
  /// Avoids "big" VideoPlayerLoadingWidget + a second different loading in SMB/media_kit mode.
  Widget _buildLoadingWidget() {
    return const Center(child: CircularProgressIndicator(color: Colors.white));
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
        if (_videoController != null)
          SizedBox(
            width: 1,
            height: 1,
            child: PlaybackVideo(controller: _videoController!),
          ),
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
                child: const Icon(
                  PhosphorIconsLight.musicNote,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                widget.fileName,
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: Colors.white),
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
              icon: const Icon(
                PhosphorIconsLight.skipBack,
                color: Colors.white,
                size: 32,
              ),
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
              icon: const Icon(
                PhosphorIconsLight.skipForward,
                color: Colors.white,
                size: 32,
              ),
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
          StreamSpeedIndicator(stream: _currentStream, label: 'Stream Speed'),
          const SizedBox(height: 12),
          BufferInfoWidget(stream: _currentStream, label: 'Buffer Info'),
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

    // Our timer owns repetition; consume platform repeats as well.
    if (event is KeyRepeatEvent &&
        (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
            event.logicalKey == LogicalKeyboardKey.arrowRight)) {
      return KeyEventResult.handled;
    }

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
    widget.onControlVisibilityChanged?.call(true);
  }

  bool _isCurrentlyPlaying() {
    return _player?.state.playing ?? false;
  }

  bool _shouldAutoHideControls() {
    if (!widget.showControls) return false;
    if (_isAndroidPip) return false;
    if (_isSeeking || _isFastSeeking || _isHoveringSeekBar) return false;
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
        widget.onControlVisibilityChanged?.call(false);
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
            await windowManager.setResizable(
              _desktopWasResizableBeforeFullScreen!,
            );
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
          _desktopWasMaximizedBeforeFullScreen = await windowManager
              .isMaximized();
          _desktopWasResizableBeforeFullScreen = await windowManager
              .isResizable();
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
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
        );
        // Restore light status bar icons after exiting fullscreen
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      }
      widget.onFullScreenChanged?.call();
    }
  }

  void _togglePlayPause() async {
    if (_player != null) {
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

    const safetyBuffer = Duration(seconds: 1);

    if (_player != null) {
      final currentPosition = _player!.state.position;
      final dur = _player!.state.duration;
      final maxPos = dur - safetyBuffer < Duration.zero
          ? Duration.zero
          : dur - safetyBuffer;
      final newPosition = currentPosition + Duration(seconds: seconds);
      final seekPosition = newPosition > maxPos ? maxPos : newPosition;
      await _player!.seek(seekPosition);
    }

    _showControlsWithTimer();
  }

  void _seekBackward([int seconds = 10]) async {
    _startSeeking();

    if (_player != null) {
      final currentPosition = _player!.state.position;
      final newPosition = currentPosition - Duration(seconds: seconds);
      final seekPosition = newPosition < Duration.zero
          ? Duration.zero
          : newPosition;
      await _player!.seek(seekPosition);
    }

    _showControlsWithTimer();
  }

  // Fast seeking methods (hold arrow on desktop, long press on mobile)
  // Accelerated seeking: aggressive acceleration, tick every 100ms
  // Normal: 3s -> 5s -> 10s -> 20s -> 30s -> 60s -> 2m -> 5m -> 10m
  // With Ctrl: 30s -> 60s -> 2m -> 5m -> 10m -> 20m
  void _startFastSeeking({required bool forward, bool withCtrl = false}) {
    if (_isFastSeeking || _player == null) return;

    // Use the same paused, live frame previews as a slider drag. Repeated
    // seeks while playing can starve media_kit's decoder of a reference clock.
    _startSeekDrag();
    _seekDragPosition = _player!.state.position;

    _fastSeekTicks = 0;
    _fastSeekSeconds = withCtrl ? 30 : 3;

    setState(() {
      _isFastSeeking = true;
      _fastSeekingForward = forward;
    });

    // Perform initial seek
    _advanceFastSeek();

    // Tick every 100ms for responsive previews
    _fastSeekTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_isFastSeeking) {
        _fastSeekTimer?.cancel();
        return;
      }

      // Hold the boundary preview until release instead of resuming into EOF
      // while the user still has the key/finger down.
      final currentPos = _seekDragPosition ?? Duration.zero;
      final totalDuration = _player?.state.duration ?? Duration.zero;

      if (_fastSeekingForward &&
          currentPos >= totalDuration - const Duration(seconds: 1)) {
        return;
      }
      if (!_fastSeekingForward && currentPos <= Duration.zero) {
        return;
      }

      _fastSeekTicks++;

      // Scale tick by speed: slow=0 → climbs 2.5× slower, fast=2 → climbs 2.5× faster
      final double tickMultiplier = _videoSeekSpeed == 0
          ? 0.4
          : (_videoSeekSpeed == 2 ? 2.5 : 1.0);
      final int scaledTick = (tickMultiplier > 1.0
          ? (_fastSeekTicks * tickMultiplier).round()
          : (tickMultiplier < 1.0
                ? (_fastSeekTicks * tickMultiplier).ceil()
                : _fastSeekTicks));

      if (withCtrl) {
        // Ctrl+Arrow: aggressive (10 ticks = 1s real time)
        // 0-0.5s: 30s, 0.5-1.5s: 60s, 1.5-3s: 2m
        // 3-5s: 5m, 5-7s: 10m, 7s+: 20m
        if (scaledTick > 70) {
          _fastSeekSeconds = 1200; // 20 minutes
        } else if (scaledTick > 50) {
          _fastSeekSeconds = 600; // 10 minutes
        } else if (scaledTick > 30) {
          _fastSeekSeconds = 300; // 5 minutes
        } else if (scaledTick > 15) {
          _fastSeekSeconds = 120; // 2 minutes
        } else if (scaledTick > 5) {
          _fastSeekSeconds = 60; // 1 minute
        } else {
          _fastSeekSeconds = 30;
        }
      } else {
        // Normal arrow: acceleration (10 ticks = 1s real time)
        // 0-0.3s: 3s, 0.3-1s: 5s, 1-2s: 10s, 2-3s: 20s
        // 3-4s: 30s, 4-5.5s: 60s, 5.5-7s: 2m
        // 7-9s: 5m, 9s+: 10m
        if (scaledTick > 90) {
          _fastSeekSeconds = 600; // 10 minutes
        } else if (scaledTick > 70) {
          _fastSeekSeconds = 300; // 5 minutes
        } else if (scaledTick > 55) {
          _fastSeekSeconds = 120; // 2 minutes
        } else if (scaledTick > 40) {
          _fastSeekSeconds = 60;
        } else if (scaledTick > 30) {
          _fastSeekSeconds = 30;
        } else if (scaledTick > 20) {
          _fastSeekSeconds = 20;
        } else if (scaledTick > 10) {
          _fastSeekSeconds = 10;
        } else if (scaledTick > 3) {
          _fastSeekSeconds = 5;
        } else {
          _fastSeekSeconds = 3;
        }
      }

      _advanceFastSeek();

      // Update UI to show current speed
      if (mounted) setState(() {});
    });

    _showControlsWithTimer();
  }

  void _advanceFastSeek() {
    final player = _player;
    if (player == null) return;
    // media_kit position events lag behind the 100ms repeat timer. Accumulate from
    // the requested position so every tick actually advances the preview.
    final current = _seekDragPosition ?? player.state.position;
    final delta = Duration(
      seconds: _fastSeekingForward ? _fastSeekSeconds : -_fastSeekSeconds,
    );
    final maxMs = (player.state.duration.inMilliseconds - 1000).clamp(
      0,
      player.state.duration.inMilliseconds,
    );
    _seekDuringDrag(
      (current + delta).inMilliseconds.clamp(0, maxMs).toDouble(),
    );
  }

  void _stopFastSeeking() {
    _fastSeekTimer?.cancel();
    _fastSeekTimer = null;

    if (_isFastSeeking) {
      _finishSeekDrag();
      setState(() {
        _isFastSeeking = false;
        _fastSeekSeconds = 5;
        _fastSeekTicks = 0;
      });
    }
  }

  void _increaseVolume() async {
    final current = (_player?.state.volume ?? _savedVolume);
    await _setVolumeFromUser((current + 5).clamp(0.0, 100.0));
  }

  void _decreaseVolume() async {
    final current = (_player?.state.volume ?? _savedVolume);
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
      return _buildDesktopControls();
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
        if (_showControls) Center(child: _buildPlayPauseButton()),

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
                    StreamBuilder<Duration>(
                      stream: _player!.stream.position,
                      builder: (context, snap) {
                        final pos = _seekDisplayPosition(
                          snap.data ?? Duration.zero,
                        );
                        return Text(
                          VideoPlayerUtils.formatDuration(pos),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 8),

                    // Slider expanded
                    Expanded(child: _buildMobileSeekSlider()),

                    const SizedBox(width: 8),

                    // Duration
                    Text(
                      VideoPlayerUtils.formatDuration(_player!.state.duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
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

  // Slider used by mobile controls with support for media_kit
  Widget _buildMobileSeekSlider() {
    {
      return _withSeekHoverPreview(
        StreamBuilder<Duration>(
          stream: _player!.stream.position,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final duration = _player!.state.duration;
            final maxMs = duration.inMilliseconds <= 0
                ? 1
                : duration.inMilliseconds;
            final value = _seekSliderValue(position, maxMs);
            return VideoPlayerSeekSlider(
              value: value,
              min: 0,
              max: maxMs.toDouble(),
              onChangeStart: _startSeekDrag,
              onChanged: _seekDuringDrag,
              onChangeEnd: _finishSeekDrag,
            );
          },
        ),
      );
    }
  }

  Widget _withSeekHoverPreview(Widget seekSlider) {
    final state = _player!.state;
    final width = state.width ?? 0;
    final height = state.height ?? 0;
    final hasVideo = width > 0 && height > 0;
    return VideoSeekHoverPreview(
      duration: state.duration,
      frames: hasVideo ? _seekHoverFramesForSource() : null,
      videoAspectRatio: hasVideo ? width / height : null,
      onHoverChanged: _setSeekBarHovered,
      child: seekSlider,
    );
  }

  VideoSeekPreviewController? _seekHoverFramesForSource() {
    // A progressive fileStream cannot be opened by a second decoder.
    final source = widget.file?.path ?? widget.streamingUrl ?? widget.smbMrl;
    if (source == null) return null;
    return _seekHoverFrames ??= VideoSeekPreviewController(
      source: source,
      enableHardwareAcceleration: _hardwareAcceleration,
    );
  }

  void _setSeekBarHovered(bool hovered) {
    if (!mounted || _isHoveringSeekBar == hovered) return;
    _isHoveringSeekBar = hovered;
    // Keep the bar on screen while the user reads a thumbnail.
    if (hovered) {
      _hideControlsTimer?.cancel();
    } else {
      _startHideControlsTimer();
    }
  }

  // Mobile-only compact volume toggle button (no inline slider)
  Widget _buildVolumeButtonOnly() {
    if (_player != null) {
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

  Widget _buildDesktopControls() {
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
                  // Material Slider owns an OverlayPortal for its value
                  // indicator. Keep that traversal anchor separate while
                  // playback continuously updates the control row.
                  child: _withSeekHoverPreview(
                    Semantics(
                      container: true,
                      child: StreamBuilder<Duration>(
                        stream: _player!.stream.position,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration = _player!.state.duration;
                          final maxMs = duration.inMilliseconds <= 0
                              ? 1
                              : duration.inMilliseconds;
                          final value = _seekSliderValue(position, maxMs);
                          return Semantics(
                            container: true,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2.5,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7,
                                ),
                              ),
                              child: Slider(
                                value: value,
                                min: 0,
                                max: maxMs.toDouble(),
                                activeColor: Colors.white,
                                inactiveColor: Colors.white24,
                                onChangeStart: (_) => _startSeekDrag(),
                                onChanged: _seekDuringDrag,
                                onChangeEnd: (value) => _finishSeekDrag(
                                  Duration(milliseconds: value.toInt()),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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
                    StreamBuilder<Duration>(
                      stream: _player!.stream.position,
                      builder: (context, snapshot) {
                        final p = _seekDisplayPosition(
                          snapshot.data ?? Duration.zero,
                        );
                        return Text(
                          VideoPlayerUtils.formatDuration(p),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 8),
                    seekSlider,
                    const SizedBox(width: 8),

                    // Duration
                    Text(
                      VideoPlayerUtils.formatDuration(_player!.state.duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(width: 8),
                    if (showSecondaryActions && widget.allowMuting)
                      _buildVolumeControl(),
                    if (showSecondaryActions) ...[
                      const SizedBox(width: 4),
                      _buildAdvancedControlsMenu(),
                    ],
                    ?fullScreenButton,
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
    if (_player != null) {
      return StreamBuilder<bool>(
        stream: _player!.stream.playing,
        initialData: _isPlaying,
        builder: (context, snapshot) {
          final isPlaying = snapshot.data ?? _player!.state.playing;
          return VideoPlayerControlButton(
            icon: isPlaying
                ? PhosphorIconsLight.pause
                : PhosphorIconsLight.play,
            onPressed: _togglePlayPause,
            size: 40,
            padding: 10,
            enabled: true,
          );
        },
      );
    } else {
      return const VideoPlayerControlButton(
        icon: PhosphorIconsLight.play,
        onPressed: null,
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
        if (_player != null)
          Builder(
            builder: (context) {
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
            },
          )
        else
          const SizedBox.shrink(),
        if (!_isFullScreen ||
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS))
          SizedBox(
            width: 80,
            child: VideoPlayerVolumeSlider(
              value: _isMuted ? 0.0 : _savedVolume,
              onChanged: (v) => _setVolumeFromUser(v),
            ),
          ),
      ],
    );
  }

  void _showAudioTrackDialog() {
    RouteUtils.showAcrylicDialog(
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
    final wasPlaying = _player?.state.playing ?? false;

    try {
      Uint8List? screenshotBytes;
      String? screenshotPath;

      debugPrint('========== SCREENSHOT CAPTURE DEBUG ==========');

      debugPrint('_player: ${_player != null}');
      debugPrint('_videoController: ${_videoController != null}');

      // Pause video momentarily to stabilize frame and ensure proper rendering
      if (wasPlaying) {
        debugPrint('Pausing video to stabilize frame for screenshot...');
        if (_player != null) {
          await _player!.pause();
        }
        // Wait for pause to take effect and frame to render
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Try to capture screenshot based on active player
      // If still null, try media_kit API screenshot
      if (_player != null && _videoController != null) {
        debugPrint('Attempting media_kit screenshot...');
        try {
          screenshotBytes = await _player!.screenshot();
          if (screenshotBytes != null) {
            debugPrint(
              'media_kit screenshot successful: ${screenshotBytes.length} bytes',
            );
          } else {
            debugPrint('media_kit screenshot returned null');
          }
        } catch (e) {
          debugPrint('media_kit screenshot failed: $e');
        }
      }

      // Final fallback: RepaintBoundary (any platform)
      if (screenshotBytes == null) {
        try {
          final boundary =
              _screenshotKey.currentContext?.findRenderObject()
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
              final byteData = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (byteData != null) {
                screenshotBytes = byteData.buffer.asUint8List();
                debugPrint(
                  'RepaintBoundary screenshot successful: ${screenshotBytes.length} bytes',
                );
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
            'Captured bytes not directly decodable; attempting PNG re-encode...',
          );
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
        'Final screenshotBytes: ${screenshotBytes != null ? "${screenshotBytes.length} bytes" : "null"}',
      );
      debugPrint('========== END SCREENSHOT CAPTURE DEBUG ==========');

      // If we got screenshot bytes, save them
      if (screenshotBytes != null && screenshotBytes.isNotEmpty) {
        debugPrint(
          'Screenshot captured, size: ${screenshotBytes.length} bytes',
        );

        // Validate screenshot is not completely black/empty by checking file size
        // Completely black images are usually very small (~< 500 bytes)
        if (screenshotBytes.length < 500) {
          debugPrint(
            'Screenshot rejected: File too small (${screenshotBytes.length} bytes - likely black/empty image)',
          );
          if (mounted) {
            AppToast.error(context, localizations.screenshotFailed);
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
              screenshotsDir = Directory(
                pathlib.join(
                  (await getApplicationDocumentsDirectory()).path,
                  'Screenshots',
                ),
              );
            }

            if (!await screenshotsDir.exists()) {
              await screenshotsDir.create(recursive: true);
            }

            final screenshotFile = File(
              pathlib.join(screenshotsDir.path, fileName),
            );
            debugPrint(
              '💾 Saving screenshot bytes: ${screenshotBytes.length} bytes to ${screenshotFile.path}',
            );
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
              await Gal.putImage(
                screenshotFile.path,
                album: 'VideoScreenshots',
              );
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
            final screenshotDir =
                await getDownloadsDirectory() ??
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

          AppToast.show(
            context,
            '${localizations.screenshotSaved}\n$filePath',
            icon: PhosphorIconsLight.checkCircle,
            accentColor: theme.colorScheme.primary,
            duration: const Duration(seconds: 5),
            actionLabel: localizations.viewImage,
            onAction: () => _openScreenshotImage(filePath),
          );
        }
      } else {
        // Screenshot failed - show helpful message
        debugPrint('Screenshot capture failed - no bytes captured');
        if (mounted) {
          {
            AppToast.error(context, localizations.screenshotFailed);
          }
        }
      }
    } catch (e) {
      debugPrint('Error taking screenshot: $e');
      if (mounted) {
        AppToast.error(context, localizations.screenshotFailed);
      }
    } finally {
      // Resume video if it was playing before screenshot
      if (wasPlaying) {
        try {
          debugPrint('Resuming video playback after screenshot...');
          if (_player != null) {
            await _player!.play();
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
        screenshotsDir = Directory(
          pathlib.join(
            (await getApplicationDocumentsDirectory()).path,
            'Screenshots',
          ),
        );
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
                '🗑️ Deleted black screenshot: ${file.path} ($fileSize bytes)',
              );
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
          AppToast.error(
            context,
            localizations.screenshotFileNotFound,
            duration: const Duration(seconds: 3),
          );
        }
        return;
      }

      bool opened = false;

      // Mobile: open directly via Navigator and temporarily hide the video surface to avoid texture overlay
      if (Platform.isAndroid) {
        final wasPlaying = _player?.state.playing == true || false;
        try {
          await _suspendVideoForRoutePush();

          // Load image bytes before opening viewer
          debugPrint('📂 Loading screenshot from: $filePath');
          final imageFile = File(filePath);
          final exists = await imageFile.exists();
          debugPrint('   File exists: $exists');
          final imageBytes = await imageFile.readAsBytes();
          debugPrint('   ✅ Loaded ${imageBytes.length} bytes');
          // Verify bytes are valid image data (PNG signature: 89 50 4E 47)
          if (imageBytes.length > 4) {
            final isPng =
                imageBytes[0] == 0x89 &&
                imageBytes[1] == 0x50 &&
                imageBytes[2] == 0x4E &&
                imageBytes[3] == 0x47;
            debugPrint('   Is valid PNG: $isPng');
          }

          if (mounted) {
            await Navigator.of(context, rootNavigator: true).push(
              CbFullBleedPageRoute(
                builder: (_) =>
                    ImageViewerScreen(file: imageFile, imageBytes: imageBytes),
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
        final wasPlaying = _player?.state.playing == true || false;
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
            final isPng =
                imageBytes[0] == 0x89 &&
                imageBytes[1] == 0x50 &&
                imageBytes[2] == 0x4E &&
                imageBytes[3] == 0x47;
            debugPrint('   Is valid PNG: $isPng');
          }

          // Ensure one frame renders without the video texture before pushing new route
          await Future.delayed(const Duration(milliseconds: 50));
          if (mounted) {
            await Navigator.of(context, rootNavigator: true).push(
              CbFullBleedPageRoute(
                builder: (_) =>
                    ImageViewerScreen(file: imageFile, imageBytes: imageBytes),
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
          'TabManager.openTab failed (TabManagerBloc not in context): $e',
        );
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
              CbFullBleedPageRoute(
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
            AppToast.error(
              context,
              localizations.screenshotCannotOpenTab,
              duration: const Duration(seconds: 3),
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
        AppToast.error(
          context,
          '${localizations.screenshotErrorOpeningFolder}: ${e.toString()}',
          duration: const Duration(seconds: 3),
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
          }
        } catch (_) {
          // Fallback to 16:9 if we can't get dimensions
          w = 16;
          h = 9;
        }

        // Pause Flutter-side playback to avoid double audio; native player will take over in PiP.
        try {
          if (_player != null && _player!.state.playing) {
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
            final uri = await SmbHttpProxyServer.instance.urlFor(
              widget.smbMrl!,
            );
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
                : 0,
            'playing': true,
            'volume': _player != null
                ? (_player!.state.volume.clamp(0.0, 100.0) / 100.0)
                : (_savedVolume / 100.0),
          });

          if (result == true) {
            debugPrint('PiP entered successfully');
          } else {
            debugPrint('PiP entry failed');
            if (mounted) {
              setState(() => _isAndroidPip = false);
              final l10n = AppLocalizations.of(context)!;
              AppToast.error(context, l10n.pipAndroidEnableFailed);
            }
          }
        } catch (e) {
          debugPrint('PiP method call error: $e');
          if (mounted) {
            setState(() => _isAndroidPip = false);
            final l10n = AppLocalizations.of(context)!;
            AppToast.error(context, l10n.pipError(e.toString()));
          }
        }
      } catch (e) {
        debugPrint('PIP error: $e');
        if (mounted) {
          setState(() => _isAndroidPip = false);
          final l10n = AppLocalizations.of(context)!;
          AppToast.error(context, l10n.pipError(e.toString()));
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
        preferExternal =
            await up.getVideoPlayerBool(
              'windows_pip_external',
              defaultValue: true,
            ) ??
            true;
      } catch (_) {}
      final positionMs = _player != null
          ? _player!.state.position.inMilliseconds
          : 0;
      final volume = _player != null
          ? (_player!.state.volume).clamp(0.0, 100.0)
          : _savedVolume;
      final playing = _player != null ? _player!.state.playing : false;

      String? sourceType;
      String? source;
      if (widget.streamingUrl != null && widget.streamingUrl!.isNotEmpty) {
        sourceType = 'url';
        source = widget.streamingUrl!;
      } else if (widget.file != null) {
        sourceType = 'file';
        source = widget.file!.path;
      } else if (widget.smbMrl != null) {
        sourceType = 'smb';
        source = widget.smbMrl!;
      }

      if (sourceType == null || source == null || source.isEmpty) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          AppToast.warning(context, l10n.pipNoSource);
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
                }
              } catch (_) {}
              if (mounted) {
                setState(() => _isPictureInPicture = true);
                final l10n = AppLocalizations.of(context)!;
                AppToast.success(context, l10n.pipOpenedInSeparateWindow);
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
      final l10n = AppLocalizations.of(context)!;
      AppToast.info(context, l10n.pipNotSupportedOnPlatform);
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
            .listen(
              _handlePipMessage,
              onDone: () {
                _closePipIpc();
              },
              onError: (e) {
                _closePipIpc();
              },
            );
      });
      return {'port': server.port, 'token': _pipToken!};
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

  @override
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

  @override
  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    setState(() {
      _sleepDuration = null;
    });
  }

  Future<void> _pauseVideo() async {
    if (_player != null) {
      await _player!.pause();
      setState(() {
        _isPlaying = false;
      });
    }
  }

  Duration _seekDisplayPosition(Duration playbackPosition) =>
      _seekDragPosition ?? playbackPosition;

  double _seekSliderValue(Duration playbackPosition, int maxMs) =>
      _seekDisplayPosition(
        playbackPosition,
      ).inMilliseconds.clamp(0, maxMs).toDouble();

  void _startSeekDrag() {
    final player = _player;
    // A preceding drag may have requested play while media_kit still reports its
    // temporary pause. Capture the requested mode, not that stale snapshot.
    _resumeAfterSeekDrag = player?.playRequested ?? false;
    _seekingTimer?.cancel();
    _hideControlsTimer?.cancel();
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;
    _pendingSeekPreview = null;
    setState(() {
      _isSeeking = true;
      _seekDragPosition = null;
    });
    if (player != null) unawaited(player.pause());
  }

  void _seekDuringDrag(double value) {
    final target = Duration(milliseconds: value.toInt());
    setState(() => _seekDragPosition = target);

    _pendingSeekPreview = target;
    if (_seekPreviewTimer == null) _flushSeekPreview();
  }

  void _flushSeekPreview() {
    final target = _pendingSeekPreview;
    _pendingSeekPreview = null;
    final player = _player;
    if (target == null || player == null) return;
    unawaited(player.seek(target));

    // Seeking this often is only safe because _startSeekDrag pauses first: a
    // paused input reacquires its clock between seeks, where a playing one
    // cannot and strands the decoder in "no reference clock". Always keep the
    // newest pointer position, including when the user holds the thumb still.
    _seekPreviewTimer = Timer(const Duration(milliseconds: 80), () {
      _seekPreviewTimer = null;
      if (mounted) _flushSeekPreview();
    });
  }

  void _finishSeekDrag([Duration? finalPosition]) {
    _seekPreviewTimer?.cancel();
    _seekPreviewTimer = null;
    _pendingSeekPreview = null;
    final target = finalPosition ?? _seekDragPosition;
    final player = _player;
    if (target != null && player != null) unawaited(player.seek(target));
    if (_resumeAfterSeekDrag && player != null) unawaited(player.play());
    _resumeAfterSeekDrag = false;

    _seekingTimer?.cancel();
    _seekingTimer = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() {
        _isSeeking = false;
        _seekDragPosition = null;
      });
      _startHideControlsTimer();
    });
  }

  /// Starts the seeking state to prevent UI flickering during seek operations.
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

  // Keep the native view mounted while an image route covers the player.
  Future<void> _suspendVideoForRoutePush() async {
    await _pauseVideo();
    if (mounted) setState(() => _suspendVideoSurface = true);
  }

  Future<void> _resumeVideoAfterRoutePop({bool resumePlaying = false}) async {
    if (mounted) setState(() => _suspendVideoSurface = false);
    if (resumePlaying) await _player?.play();
  }
}
