import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../helpers/core/user_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

class DesktopPipWindow extends StatefulWidget {
  final Map<String, dynamic> args;
  const DesktopPipWindow({Key? key, required this.args}) : super(key: key);

  @override
  State<DesktopPipWindow> createState() => _DesktopPipWindowState();
}

class _DesktopPipWindowState extends State<DesktopPipWindow>
    with WindowListener {
  Player? _player;
  VideoController? _controller;
  bool _isPlaying = true;
  Timer? _saveDebounce;
  StreamSubscription<int?>? _videoWSub;
  StreamSubscription<int?>? _videoHSub;
  int? _videoW;
  int? _videoH;
  bool _initialAspectApplied = false;
  // Throttle aspect ratio updates to avoid jank when stream starts
  Timer? _aspectDebounce;
  double? _lastAspect;
  bool _firstFrameReady = false;
  bool _readyToShow = false;
  bool _windowShown = false;
  Timer? _firstFrameGuard;
  Timer? _fallbackDecodeGuard;

  // Playback performance settings (loaded from UserPreferences)
  bool _hardwareAcceleration = true;
  int _bufferSizeMB = 10;

  // Overlay controls
  bool _showOverlay = true;
  Timer? _overlayHideTimer;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _seeking = false;
  int? _pendingInitialSeekMs;
  bool _initialSyncApplied = false;

  // IPC back to main window
  Socket? _ipc;
  String? _ipcToken;
  String? _openError;

  @override
  void initState() {
    super.initState();
    _initWindow();
    _initPlayer();
    _initIpc();
  }

  Future<void> _initWindow() async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    // Restore last PiP size if available; otherwise use a comfortable default.
    final prefs = await SharedPreferences.getInstance();
    final savedW = prefs.getDouble('pip_w');
    final savedH = prefs.getDouble('pip_h');

    const Size defaultSize = Size(384, 216); // 16:9, reasonably sized
    const Size minSize = Size(240, 135); // 16:9, small but usable
    final Size initialSize = (savedW != null &&
            savedH != null &&
            savedW >= minSize.width &&
            savedH >= minSize.height)
        ? Size(savedW, savedH)
        : defaultSize;

    final options = WindowOptions(
      size: initialSize,
      minimumSize: minSize,
      center: true,
      backgroundColor: Colors.black,
      skipTaskbar: false,
      // Hide native title bar & frame for a clean PiP look.
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options);
    // Enforce aspect ratio during resize so PiP keeps its proportions.
    try {
      final aspect = initialSize.width / initialSize.height;
      await windowManager.setAspectRatio(aspect);
    } catch (_) {
      // If not supported on a platform/version, just continue without it.
    }
    await windowManager.setAlwaysOnTop(true);
    // Show the window early so video backends can create rendering surfaces
    // reliably on Windows before the first frame.
    _readyToShow = true;
    try {
      await windowManager.show();
    } catch (_) {}

    final title = (widget.args['fileName'] as String?) ?? 'PiP';
    // setTitle is safe even with hidden title bar
    await windowManager.setTitle('PiP - $title');

    // Safety fallback: if first frame detection doesn't trigger (e.g., paused
    // at start or backend delays), make sure the window still becomes visible.
    // We'll still fade in from black, so UX remains acceptable.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_windowShown) {
        _showWindowIfReady(force: true);
      }
    });
  }

  Future<void> _initPlayer() async {
    MediaKit.ensureInitialized();
    // Load video performance settings from UserPreferences if available
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      _hardwareAcceleration = await prefs.getVideoPlayerBool(
              'hardware_acceleration',
              defaultValue: !Platform.isWindows) ??
          !Platform.isWindows;
      _bufferSizeMB =
          await prefs.getVideoPlayerInt('buffer_size', defaultValue: 10) ?? 10;
    } catch (_) {
      // Fallback to defaults if preferences are unavailable in PiP process
      _hardwareAcceleration = !Platform.isWindows;
      _bufferSizeMB = 10;
    }

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: (_bufferSizeMB > 0 ? _bufferSizeMB : 10) * 1024 * 1024,
      ),
    );
    _controller = VideoController(
      _player!,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: _hardwareAcceleration,
      ),
    );

    final type = (widget.args['sourceType'] as String?) ?? 'url';
    final src = (widget.args['source'] as String?) ?? '';
    final positionMs = (widget.args['positionMs'] as int?) ?? 0;
    final initialVolume = (widget.args['volume'] as num?)?.toDouble();
    final shouldPlay = widget.args['playing'] == null
        ? true
        : (widget.args['playing'] == true);

    String openSrc = src;
    if (Platform.isWindows) {
      if (type == 'smb') {
        openSrc = _normalizeToFileUri(_smbToUnc(src));
      } else if (type == 'file') {
        // Use explicit file:// URI to avoid edge-cases with backslashes.
        openSrc = _normalizeToFileUri(src);
      }
    }

    try {
      debugPrint('[PiP] Opening source type=$type src=$openSrc');
      await _player!.open(Media(openSrc));
    } catch (e) {
      debugPrint('[PiP] Failed to open media: $e');
      if (mounted) setState(() => _openError = '$e');
    }
    // Listen for video dimension updates to keep window aspect ratio in sync.
    _videoWSub = _player!.stream.width.listen((w) {
      _videoW = w;
      // debugPrint('[PiP] video width: $w');
      _maybeApplyVideoAspectRatio();
      _checkFirstFrameReady();
    });
    _videoHSub = _player!.stream.height.listen((h) {
      _videoH = h;
      // debugPrint('[PiP] video height: $h');
      _maybeApplyVideoAspectRatio();
      _checkFirstFrameReady();
    });
    // Listen for playback position & duration for seekbar updates.
    _posSub = _player!.stream.position.listen((p) {
      if (!_seeking) {
        setState(() => _position = p);
      }
    });
    _durSub = _player!.stream.duration.listen((d) {
      setState(() => _duration = d);
      _tryApplyInitialSeek();
    });
    _pendingInitialSeekMs = positionMs > 0 ? positionMs : null;
    // Apply seek asynchronously to avoid delaying first frame
    unawaited(_tryApplyInitialSeek());
    if (initialVolume != null) {
      try {
        await _player!.setVolume(initialVolume.clamp(0.0, 100.0));
      } catch (_) {}
    }
    // Start playback immediately if requested to get first frame sooner
    try {
      if (shouldPlay) {
        await _player!.play();
        _armFirstFrameGuard();
      } else {
        await _player!.pause();
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isPlaying = shouldPlay;
      });
    }
    // In case we already have a frame ready by now, ensure window shows.
    _showWindowIfReady();

    // If the first frame still doesn't arrive after a short delay, retry with
    // software decoding (disable hardware acceleration) which can help on some
    // Windows GPU/driver setups.
    _fallbackDecodeGuard?.cancel();
    _fallbackDecodeGuard = Timer(const Duration(seconds: 2), () async {
      if (!mounted || _firstFrameReady || !_hardwareAcceleration) return;
      try {
        // Recreate controller with hardware acceleration disabled
        _controller = VideoController(
          _player!,
          configuration: const VideoControllerConfiguration(
            enableHardwareAcceleration: false,
          ),
        );
        setState(() {});
        // Give it another short window to produce a frame
        _armFirstFrameGuard();
        Future.delayed(const Duration(seconds: 1), () {
          _showWindowIfReady(force: true);
        });
      } catch (_) {}
    });
  }

  Future<void> _tryApplyInitialSeek({bool forceAwait = false}) async {
    if (_initialSyncApplied) return;
    if (_player == null) return;
    final ms = _pendingInitialSeekMs;
    if (ms == null || ms <= 0) {
      _initialSyncApplied = true;
      return;
    }
    Future<void> doSeek() async {
      try {
        await _player!.seek(Duration(milliseconds: ms));
        _pendingInitialSeekMs = null;
        _initialSyncApplied = true;
      } catch (_) {}
    }

    if (forceAwait) {
      await doSeek();
    } else {
      unawaited(doSeek());
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _saveDebounce?.cancel();
    _firstFrameGuard?.cancel();
    _videoWSub?.cancel();
    _videoHSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _overlayHideTimer?.cancel();
    _controller = null;
    _player?.dispose();
    _fallbackDecodeGuard?.cancel();
    // Best-effort send final state
    _sendState(closing: true);
    try {
      _ipc?.destroy();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Listener(
      onPointerHover: (_) => _bumpOverlay(),
      onPointerMove: (_) => _bumpOverlay(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleOverlay,
        onPanStart: (details) async {
          // Always allow window dragging, but check if we're over interactive elements
          // when overlay is visible
          if (_showOverlay) {
            // Check if the tap is over interactive elements (top bar or bottom controls)
            final RenderBox? renderBox =
                context.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final localPosition =
                  renderBox.globalToLocal(details.globalPosition);
              final size = renderBox.size;

              // Top bar area (first 36 pixels)
              final topBarRect = Rect.fromLTWH(0, 0, size.width, 36);
              // Bottom controls area (last 60 pixels)
              final bottomControlsRect =
                  Rect.fromLTWH(0, size.height - 60, size.width, 60);

              // If tap is in interactive areas, don't start dragging
              if (topBarRect.contains(localPosition) ||
                  bottomControlsRect.contains(localPosition)) {
                return;
              }
            }
          }

          // Start window dragging
          try {
            await windowManager.startDragging();
          } catch (_) {}
        },
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              // Solid black background
              const Positioned.fill(child: ColoredBox(color: Colors.black)),

              // Render the video as soon as the controller exists.
              // Keep a loading indicator over it until first frame is detected.
              if (_controller != null)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: Video(
                      controller: _controller!,
                      controls: NoVideoControls,
                      fill: Colors.black,
                    ),
                  ),
                ),

              // Minimal loader until first frame
              if (!_firstFrameReady)
                const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white60),
                  ),
                ),

              // If there is an opening error, show it as a small banner.
              if (_openError != null)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: _showOverlay ? 48 : 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Lỗi mở video: $_openError',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 3,
                    ),
                  ),
                ),

              // Overlay controls: build only when needed to minimize init cost
              if (_showOverlay)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _buildTopBar(context),
                  ),
                ),
              if (_showOverlay)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _buildBottomControls(context),
                  ),
                ),

              // Bottom-right resize handle for frameless window.
              if (_showOverlay)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeUpLeftDownRight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) async {
                        try {
                          await windowManager
                              .startResizing(ResizeEdge.bottomRight);
                        } catch (_) {}
                      },
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: const Icon(
                          PhosphorIconsLight.cornersOut,
                          size: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final mq = MediaQuery.maybeOf(context) ??
        MediaQueryData.fromView(
            WidgetsBinding.instance.platformDispatcher.views.first);
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    return MediaQuery(
      data: mq,
      child: Localizations(
        locale: locale,
        delegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        child: Theme(
          data:
              ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
          child: Material(color: Colors.black, child: content),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final title = (widget.args['fileName'] as String?) ?? 'PiP';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) async {
        try {
          await windowManager.startDragging();
        } catch (_) {}
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        height: 36,
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.66)),
        child: Row(
          children: [
            const SizedBox(width: 4),
            const Icon(PhosphorIconsLight.pictureInpicture,
                color: Colors.white70, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: Icon(
                  _isPlaying
                      ? PhosphorIconsLight.pause
                      : PhosphorIconsLight.play,
                  color: Colors.white,
                  size: 18),
              onPressed: () async {
                if (_player == null) return;
                if (_player!.state.playing) {
                  await _player!.pause();
                  setState(() => _isPlaying = false);
                } else {
                  await _player!.play();
                  setState(() => _isPlaying = true);
                }
              },
            ),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(PhosphorIconsLight.x,
                  color: Colors.white, size: 18),
              onPressed: () async {
                try {
                  await windowManager.close();
                } catch (_) {
                  if (context.mounted) {
                    Navigator.of(context).maybePop();
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Persist PiP window size so next launch restores it
  Future<void> _saveCurrentSize() async {
    try {
      final size = await windowManager.getSize();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('pip_w', size.width);
      await prefs.setDouble('pip_h', size.height);
    } catch (_) {}
  }

  void _scheduleSaveSize() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), _saveCurrentSize);
  }

  void _maybeApplyVideoAspectRatio() async {
    if (!mounted) return;
    final w = _videoW;
    final h = _videoH;
    if (w != null && h != null && w > 0 && h > 0) {
      // Apply aspect ratio once, then avoid updating repeatedly to reduce jank
      final ratio = w / h;
      if (_initialAspectApplied) return;
      if (_lastAspect != null && (ratio - _lastAspect!).abs() < 0.005) return;
      _lastAspect = ratio;
      _aspectDebounce?.cancel();
      _aspectDebounce = Timer(const Duration(milliseconds: 120), () async {
        try {
          await windowManager.setAspectRatio(ratio);
          _initialAspectApplied = true;
          final current = await windowManager.getSize();
          const min = Size(240, 135);
          double newW = current.width;
          double newH = newW / ratio;
          if (newH < min.height) {
            newH = min.height;
            newW = newH * ratio;
          }
          await windowManager.setSize(Size(newW, newH));
        } catch (_) {}
      });
    }
  }

  void _checkFirstFrameReady() {
    if (_firstFrameReady) return;
    final w = _videoW ?? 0;
    final h = _videoH ?? 0;
    if (w > 0 && h > 0) {
      setState(() => _firstFrameReady = true);
      _showWindowIfReady();
      _firstFrameGuard?.cancel();
    }
  }

  // Safety: if backend doesn't report width/height quickly, still show after a short delay
  void _armFirstFrameGuard() {
    _firstFrameGuard?.cancel();
    _firstFrameGuard = Timer(const Duration(milliseconds: 300), () {
      if (mounted && !_firstFrameReady) {
        setState(() => _firstFrameReady = true);
        _showWindowIfReady();
      }
    });
  }

  void _showWindowIfReady({bool force = false}) async {
    if (!_readyToShow || _windowShown) return;
    if (!force && !_firstFrameReady) return;
    try {
      await windowManager.show();
      await windowManager.focus();
      _windowShown = true;
    } catch (_) {
      // ignore
    }
  }

  // Overlay helpers
  void _bumpOverlay() {
    if (!_showOverlay) setState(() => _showOverlay = true);
    _overlayHideTimer?.cancel();
    _overlayHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
    if (_showOverlay) _bumpOverlay();
  }

  Widget _buildBottomControls(BuildContext context) {
    int totalMs = _duration.inMilliseconds;
    if (totalMs < 0) totalMs = 0;
    int posMs = _position.inMilliseconds;
    if (posMs < 0) posMs = 0;
    if (posMs > totalMs) posMs = totalMs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seekbar row with compact volume
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  _isPlaying
                      ? PhosphorIconsLight.pauseCircle
                      : PhosphorIconsLight.playCircle,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () async {
                  if (_player == null) return;
                  if (_player!.state.playing) {
                    await _player!.pause();
                    setState(() => _isPlaying = false);
                  } else {
                    await _player!.play();
                    setState(() => _isPlaying = true);
                  }
                },
              ),
              const SizedBox(width: 8),
              Text(_formatTime(_position),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    value: totalMs == 0 ? 0 : posMs.toDouble(),
                    min: 0,
                    max: (totalMs == 0 ? 1 : totalMs).toDouble(),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white24,
                    onChangeStart: (_) => _seeking = true,
                    onChanged: (v) {
                      setState(
                          () => _position = Duration(milliseconds: v.toInt()));
                    },
                    onChangeEnd: (v) async {
                      _seeking = false;
                      if (_player != null) {
                        await _player!.seek(Duration(milliseconds: v.toInt()));
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(_formatTime(_duration),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(width: 8),
              const Icon(PhosphorIconsLight.speakerHigh,
                  color: Colors.white, size: 18),
              const SizedBox(width: 4),
              SizedBox(
                width: 90,
                child: Slider(
                  value:
                      ((_player?.state.volume ?? 100).clamp(0, 100)).toDouble(),
                  min: 0,
                  max: 100,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (v) async {
                    if (_player != null) {
                      await _player!.setVolume(v);
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // WindowListener overrides
  @override
  void onWindowResized() {
    _scheduleSaveSize();
  }

  @override
  void onWindowClose() {
    // Best-effort save; may not always complete before process exit
    unawaited(_saveCurrentSize());
    _sendState(closing: true);
  }

  // Helpers copied from main player to support SMB -> UNC on Windows
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

  String _normalizeToFileUri(String path) {
    try {
      if (Platform.isWindows) {
        // Use Uri.file to handle both local and UNC paths correctly.
        final uri = Uri.file(path, windows: true);
        return uri.toString();
      }
      return path;
    } catch (_) {
      return path;
    }
  }
}

extension _IpcHelpers on _DesktopPipWindowState {
  Future<void> _initIpc() async {
    final port = widget.args['ipcPort'];
    final token = widget.args['ipcToken'];
    if (port is int && token is String) {
      _ipcToken = token;
      try {
        final sock = await Socket.connect(InternetAddress.loopbackIPv4, port,
            timeout: const Duration(seconds: 2));
        _ipc = sock;
        // hello
        _ipc!.writeln(jsonEncode({
          'type': 'hello',
          'token': _ipcToken,
        }));
      } catch (_) {
        // ignore
      }
    }
  }

  void _sendState({bool closing = false}) {
    if (_ipc == null || _ipcToken == null) return;
    final msg = <String, dynamic>{
      'type': closing ? 'closing' : 'state',
      'token': _ipcToken,
      'positionMs': _position.inMilliseconds,
      'volume': (_player?.state.volume ?? 100).toDouble(),
      'playing': _player?.state.playing ?? _isPlaying,
    };
    try {
      _ipc!.writeln(jsonEncode(msg));
    } catch (_) {}
  }
}
