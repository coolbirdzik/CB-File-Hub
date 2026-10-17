import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:flutter/rendering.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../utils/route.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as pathlib;
import 'package:window_manager/window_manager.dart';

import 'package:cb_file_manager/ui/components/video/video_player/video_info_dialog.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_app_bar.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_playlist.dart';

class VideoPlayerFullScreen extends StatefulWidget {
  /// Local file (use when path is available, e.g. file:// on Android).
  final File? file;

  /// Android content:// URI when opened via "Open with" / default app.
  final String? contentUri;

  /// Reports the loaded media's `width` / `height` / `duration`.
  final void Function(Map<String, dynamic> metadata)? onVideoMetadata;

  /// Replaces the app bar's default close, which pops the route or exits the
  /// process when the player is the root.
  final VoidCallback? onClose;

  VideoPlayerFullScreen({
    super.key,
    this.file,
    this.contentUri,
    this.onVideoMetadata,
    this.onClose,
  }) : assert(file != null || (contentUri != null && contentUri.isNotEmpty));

  // ignore: library_private_types_in_public_api
  @override
  State<VideoPlayerFullScreen> createState() => _VideoPlayerFullScreenState();
}

String _shortName(String? contentUri) {
  if (contentUri == null || contentUri.isEmpty) return 'Video';
  final u = contentUri.split('/').last;
  return u.isNotEmpty ? u : 'Video';
}

class _VideoPlayerFullScreenState extends State<VideoPlayerFullScreen> {
  /// The file playing now; starts as [VideoPlayerFullScreen.file] and moves
  /// when an entry is picked from the playlist.
  late File? _currentFile = widget.file;
  List<File>? _playlist;
  Map<String, dynamic>? _videoMetadata;
  bool _isFullScreen = false;
  bool _showAppBar = true; // Control app bar visibility
  bool _inAndroidPip = false;
  Timer? _uiEnforceTimer;

  @override
  void initState() {
    super.initState();
    // On mobile, show full UI (both status bar and nav bar)
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
      // Also force style after first frame to avoid being overridden
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
        );
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      });
      // Ensure Flutter re-applies overlays automatically while this route is on top
      RendererBinding.instance.renderViews.first.automaticSystemUiAdjustment =
          true;
      // Re-assert overlays for a short period in case platform view toggles them off
      int attempts = 0;
      _uiEnforceTimer?.cancel();
      _uiEnforceTimer = Timer.periodic(const Duration(milliseconds: 400), (
        t,
      ) async {
        attempts++;
        if (!mounted || _isFullScreen || attempts > 10) {
          t.cancel();
          return;
        }
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
        );
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      });
    }
    // Hide app bar while in Android PiP so PiP captures only the video
    const channel = MethodChannel('cb_file_manager/pip');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        final args = call.arguments;
        bool inPip = false;
        if (args is Map) {
          inPip = args['inPip'] == true;
        }
        if (mounted) {
          setState(() => _inAndroidPip = inPip);
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Inner VideoPlayer drives overlay visibility; just keep app bar visible initially.
      setState(() => _showAppBar = true);
    });
    _loadPlaylist();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerFullScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The video window reuses this widget for a newly opened path.
    if (widget.file?.path != oldWidget.file?.path) {
      _currentFile = widget.file;
      _videoMetadata = null;
      _loadPlaylist();
    }
  }

  Future<void> _loadPlaylist() async {
    final file = _currentFile;
    if (file == null) return;
    final folder = file.parent.path;
    // Reloaded on every switch so a sort changed in the folder view meanwhile
    // carries over. A list for the same folder stays up until then; one for
    // another folder drops out (this runs right before a build).
    if (_playlist?.isNotEmpty != true ||
        !pathlib.equals(_playlist!.first.parent.path, folder)) {
      _playlist = null;
    }
    final items = await VideoPlaylist.fromFolder(file);
    if (!mounted || !identical(_currentFile, file)) return;
    setState(() => _playlist = items);
  }

  /// The playlist entry after [_currentFile], if any.
  File? get _nextVideo {
    final items = _playlist;
    final current = _currentFile;
    if (items == null || current == null) return null;
    final index = items.indexWhere((f) => pathlib.equals(f.path, current.path));
    if (index < 0 || index + 1 >= items.length) return null;
    return items[index + 1];
  }

  void _playNextVideo() {
    final next = _nextVideo;
    if (next != null && mounted) _playFromPlaylist(next);
  }

  void _playFromPlaylist(File file) {
    setState(() {
      _currentFile = file;
      _videoMetadata = null;
    });
    _loadPlaylist();
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      () async {
        try {
          if (Platform.isWindows) {
            const channel = MethodChannel('cb_file_manager/window_utils');
            await channel.invokeMethod('setNativeFullScreen', {
              'isFullScreen': false,
            });
          } else {
            final isFs = await windowManager.isFullScreen();
            if (isFs) {
              await windowManager.setFullScreen(false);
            }
          }
        } catch (_) {}
      }();
    }

    // Restore system UI when leaving video player
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    // Keep automatic adjustment enabled for underlying screens
    RendererBinding.instance.renderViews.first.automaticSystemUiAdjustment =
        true;
    _uiEnforceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = Platform.isAndroid || Platform.isIOS;
    final scaffold = Scaffold(
      // On mobile, avoid extra app bar since parent already has one
      appBar: isMobile
          ? null
          : ((_isFullScreen && !_showAppBar) || _inAndroidPip
                ? null // Hide app bar completely when in fullscreen and _showAppBar is false
                : VideoPlayerAppBar(
                    title: _currentFile != null
                        ? pathlib.basename(_currentFile!.path)
                        : _shortName(widget.contentUri),
                    actions: [
                      if (_currentFile != null)
                        IconButton(
                          icon: const Icon(
                            PhosphorIconsLight.info,
                            color: Colors.white70,
                          ),
                          onPressed: () => _showVideoInfo(context),
                        ),
                    ],
                    // Null keeps the default: pop when in a route, else exit.
                    onClose: widget.onClose,
                    showWindowControls: true,
                    blurAmount: 12.0,
                    opacity: 0.6,
                  )),
      extendBody: true,
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Center(child: _buildPlayer(context)),
    );

    if (isMobile) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: scaffold,
      );
    }

    // Handle Escape at a parent focus node without stealing focus from the player
    // (arrow keys are handled by the inner VideoPlayer Focus node).
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (_isFullScreen) {
            // Let the inner VideoPlayer handle ESC to exit fullscreen first.
            return KeyEventResult.ignored;
          }
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: scaffold,
    );
  }

  void _onVideoInitialized(Map<String, dynamic> metadata) {
    setState(() => _videoMetadata = metadata);
    widget.onVideoMetadata?.call(metadata);
    // A video that followed on in fullscreen keeps the immersive mode.
    if ((Platform.isAndroid || Platform.isIOS) && !_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    }
  }

  void _onVideoError(String errorMessage) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.error(context, l10n.errorWithMessage(errorMessage));
  }

  void _onFullScreenChanged() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      // Hide top bar immediately when entering fullscreen; show it when exiting.
      _showAppBar = !_isFullScreen;
    });
  }

  void _onControlVisibilityChanged(bool visible) {
    if (!mounted) return;
    if (Platform.isAndroid || Platform.isIOS) return;
    if (_inAndroidPip) return;
    // In fullscreen, top bar stays hidden — only the bottom seek bar reacts to mouse/keys.
    if (_isFullScreen) {
      if (_showAppBar) setState(() => _showAppBar = false);
      return;
    }
    if (_showAppBar == visible) return;
    setState(() => _showAppBar = visible);
  }

  Widget _buildPlayer(BuildContext context) {
    final file = _currentFile;
    if (file != null) {
      return VideoPlayer.file(
        // Keyed by source: switching files builds a fresh player instead of
        // tearing down and re-opening the live one (which races pending
        // callbacks into "Player has been disposed").
        key: ValueKey<String>(file.path),
        file: file,
        autoPlay: true,
        showControls: true,
        allowFullScreen: true,
        onVideoInitialized: _onVideoInitialized,
        onError: _onVideoError,
        onFullScreenChanged: _onFullScreenChanged,
        onControlVisibilityChanged: _onControlVisibilityChanged,
        playlist: _playlist,
        onPlaylistItemSelected: _playFromPlaylist,
        hasNextVideo: _nextVideo != null,
        onNextVideo: _playNextVideo,
        // A replacement player picks up the fullscreen state it inherits.
        initiallyFullScreen: _isFullScreen,
        onOpenFolder: (folderPath, highlightedFileName) {
          Navigator.of(context).pop({
            'action': 'openFolder',
            'folderPath': folderPath,
            'highlightedFileName': highlightedFileName,
          });
        },
      );
    }
    return VideoPlayer.url(
      streamingUrl: widget.contentUri!,
      fileName: _shortName(widget.contentUri),
      autoPlay: true,
      showControls: true,
      allowFullScreen: true,
      onVideoInitialized: _onVideoInitialized,
      onError: _onVideoError,
      onFullScreenChanged: _onFullScreenChanged,
      onControlVisibilityChanged: _onControlVisibilityChanged,
    );
  }

  void _showVideoInfo(BuildContext context) {
    final file = _currentFile;
    if (file == null) return;
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) =>
          VideoInfoDialog(file: file, videoMetadata: _videoMetadata),
    );
  }
}
