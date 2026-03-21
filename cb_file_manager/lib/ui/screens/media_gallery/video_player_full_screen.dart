import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as pathlib;
import 'package:window_manager/window_manager.dart';

import 'package:cb_file_manager/ui/components/video/video_player/video_info_dialog.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_player_app_bar.dart';

class VideoPlayerFullScreen extends StatefulWidget {
  /// Local file (use when path is available, e.g. file:// on Android).
  final File? file;

  /// Android content:// URI when opened via "Open with" / default app.
  final String? contentUri;

  VideoPlayerFullScreen({
    Key? key,
    this.file,
    this.contentUri,
  })  : assert(file != null || (contentUri != null && contentUri.isNotEmpty)),
        super(key: key);

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
  Map<String, dynamic>? _videoMetadata;
  bool _isFullScreen = false;
  bool _showAppBar = true; // Control app bar visibility
  bool _inAndroidPip = false;
  Timer? _uiEnforceTimer;
  Timer? _overlayHideTimer;
  static const Duration _overlayAutoHideDuration = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    // On mobile, show full UI (both status bar and nav bar)
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
      // Also force style after first frame to avoid being overridden
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      });
      // Ensure Flutter re-applies overlays automatically while this route is on top
      RendererBinding.instance.renderViews.first.automaticSystemUiAdjustment = true;
      // Re-assert overlays for a short period in case platform view toggles them off
      int attempts = 0;
      _uiEnforceTimer?.cancel();
      _uiEnforceTimer =
          Timer.periodic(const Duration(milliseconds: 400), (t) async {
        attempts++;
        if (!mounted || _isFullScreen || attempts > 10) {
          t.cancel();
          return;
        }
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
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
      _showOverlaysTemporarily();
    });
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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    // Keep automatic adjustment enabled for underlying screens
    RendererBinding.instance.renderViews.first.automaticSystemUiAdjustment = true;
    _uiEnforceTimer?.cancel();
    _overlayHideTimer?.cancel();
    super.dispose();
  }

  bool _shouldAutoHideOverlays() {
    if (Platform.isAndroid || Platform.isIOS) return false;
    if (_inAndroidPip) return false;
    return true;
  }

  void _showOverlaysTemporarily() {
    if (!_shouldAutoHideOverlays()) return;

    if (mounted) {
      setState(() => _showAppBar = true);
    }

    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(_overlayAutoHideDuration, () {
      if (!mounted) return;
      if (!_shouldAutoHideOverlays()) return;
      setState(() => _showAppBar = false);
    });
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
                  title: widget.file != null
                      ? pathlib.basename(widget.file!.path)
                      : _shortName(widget.contentUri),
                  actions: [
                    if (widget.file != null)
                      IconButton(
                        icon: const Icon(PhosphorIconsLight.info,
                            color: Colors.white70),
                        onPressed: () => _showVideoInfo(context),
                      ),
                  ],
                  onClose: null,
                  // Default: pop when in a route, else exit(0)
                  showWindowControls: true,
                  blurAmount: 12.0,
                  opacity: 0.6,
                )),
      extendBody: true,
      extendBodyBehindAppBar: false,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Center(
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _showOverlaysTemporarily(),
          onPointerMove: (_) => _showOverlaysTemporarily(),
          child: _buildPlayer(context),
        ),
      ),
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
    if (Platform.isAndroid || Platform.isIOS) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    }
  }

  void _onVideoError(String errorMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Lỗi: $errorMessage')),
    );
  }

  void _onFullScreenChanged() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      _showAppBar = true;
    });
    _showOverlaysTemporarily();
  }

  void _onControlVisibilityChanged() {
    _showOverlaysTemporarily();
  }

  Widget _buildPlayer(BuildContext context) {
    if (widget.file != null) {
      return VideoPlayer.file(
        file: widget.file!,
        autoPlay: true,
        showControls: true,
        allowFullScreen: true,
        onVideoInitialized: _onVideoInitialized,
        onError: _onVideoError,
        onFullScreenChanged: _onFullScreenChanged,
        onControlVisibilityChanged: _onControlVisibilityChanged,
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
    if (widget.file == null) return;
    showDialog(
      context: context,
      builder: (context) => VideoInfoDialog(
        file: widget.file!,
        videoMetadata: _videoMetadata,
      ),
    );
  }
}
