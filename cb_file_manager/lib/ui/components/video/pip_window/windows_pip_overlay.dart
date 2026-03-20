import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../video_player/video_player_utils.dart';

/// Modeless, draggable PiP overlay for Windows (in‑process), using media_kit.
///
/// This avoids launching a second process and behaves like a floating dialog
/// that can be dragged within the app window.
class WindowsPipOverlay {
  static OverlayEntry? _entry;

  static bool get isShowing => _entry != null;

  static void close() {
    _entry?.remove();
    _entry = null;
  }

  static void show(
    BuildContext context, {
    required Map<String, dynamic> args,
    required void Function({
      required int positionMs,
      required double volume,
      required bool playing,
    }) onClose,
  }) {
    if (_entry != null) return;
    final entry = OverlayEntry(builder: (_) {
      return _WindowsPipOverlayWidget(
        args: args,
        onClose: onClose,
        onRemove: close,
      );
    });
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }
}

class _WindowsPipOverlayWidget extends StatefulWidget {
  final Map<String, dynamic> args;
  final void Function(
      {required int positionMs,
      required double volume,
      required bool playing}) onClose;
  final VoidCallback onRemove;
  const _WindowsPipOverlayWidget({
    Key? key,
    required this.args,
    required this.onClose,
    required this.onRemove,
  }) : super(key: key);

  @override
  State<_WindowsPipOverlayWidget> createState() =>
      _WindowsPipOverlayWidgetState();
}

class _WindowsPipOverlayWidgetState extends State<_WindowsPipOverlayWidget> {
  Player? _player;
  VideoController? _controller;
  bool _isPlaying = true;
  Offset _offset = const Offset(24, 24);
  Size _size = const Size(384, 216); // 16:9
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<int?>? _wSub;
  StreamSubscription<int?>? _hSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int? _videoW;
  int? _videoH;
  String? _openError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    MediaKit.ensureInitialized();

    _player = Player();
    _controller = VideoController(
      _player!,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: !Platform.isWindows,
      ),
    );

    final type = (widget.args['sourceType'] as String?) ?? 'url';
    var src = (widget.args['source'] as String?) ?? '';
    final positionMs = (widget.args['positionMs'] as int?) ?? 0;
    final initialVolume = (widget.args['volume'] as num?)?.toDouble();
    final shouldPlay = widget.args['playing'] == null
        ? true
        : (widget.args['playing'] == true);

    if (Platform.isWindows) {
      if (type == 'smb') {
        src = _normalizeToFileUri(_smbToUnc(src));
      } else if (type == 'file') {
        src = _normalizeToFileUri(src);
      }
    }

    try {
      await _player!.open(Media(src));
    } catch (e) {
      setState(() => _openError = '$e');
    }

    _posSub = _player!.stream.position.listen((d) {
      setState(() => _position = d);
    });
    _durSub = _player!.stream.duration.listen((d) {
      setState(() => _duration = d);
    });
    _wSub = _player!.stream.width.listen((w) {
      _videoW = w;
      _applyAspectFromVideo();
    });
    _hSub = _player!.stream.height.listen((h) {
      _videoH = h;
      _applyAspectFromVideo();
    });

    if (positionMs > 0) {
      unawaited(_player!.seek(Duration(milliseconds: positionMs)));
    }
    if (initialVolume != null) {
      unawaited(_player!.setVolume(initialVolume.clamp(0.0, 100.0)));
    }
    if (shouldPlay) {
      unawaited(_player!.play());
    } else {
      unawaited(_player!.pause());
    }
    setState(() => _isPlaying = shouldPlay);
  }

  void _applyAspectFromVideo() {
    final w = _videoW ?? 0;
    final h = _videoH ?? 0;
    if (w > 0 && h > 0) {
      final ratio = w / h;
      final newH = _size.width / ratio;
      setState(() => _size = Size(_size.width, newH));
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _wSub?.cancel();
    _hSub?.cancel();
    _controller = null;
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final maxX = mq.size.width - _size.width - 8;
    final maxY = mq.size.height - _size.height - 8;
    final clamped = Offset(
      _offset.dx.clamp(8.0, maxX),
      _offset.dy.clamp(8.0, maxY),
    );

    final List<Widget> innerChildren = [];
    if (_controller != null) {
      innerChildren.add(
        Positioned.fill(
          child: Video(
            controller: _controller!,
            controls: NoVideoControls,
            fill: Colors.black,
          ),
        ),
      );
    }

    // Top bar
    innerChildren.add(
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {},
          onPanUpdate: (d) {
            setState(() {
              _offset = _offset + d.delta;
            });
          },
          onPanEnd: (_) {},
          child: Container(
            height: 28,
            color: Colors.black.withValues(alpha: 0.45),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.pictureInpicture,
                    color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (widget.args['fileName'] as String?) ?? 'PiP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
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
                      size: 16),
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
                      color: Colors.white, size: 16),
                  onPressed: () {
                    final pos = _position.inMilliseconds;
                    final vol = (_player?.state.volume ?? 100).toDouble();
                    final playing = _player?.state.playing ?? _isPlaying;
                    widget.onRemove();
                    widget.onClose(
                        positionMs: pos, volume: vol, playing: playing);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Bottom controls
    innerChildren.add(
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            Text(VideoPlayerUtils.formatDuration(_position),
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(width: 6),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: _duration.inMilliseconds == 0
                      ? 0
                      : _position.inMilliseconds.toDouble(),
                  min: 0,
                  max: (_duration.inMilliseconds == 0
                          ? 1
                          : _duration.inMilliseconds)
                      .toDouble(),
                  activeColor: Colors.white,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(
                      () => _position = Duration(milliseconds: v.toInt())),
                  onChangeEnd: (v) =>
                      _player?.seek(Duration(milliseconds: v.toInt())),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(VideoPlayerUtils.formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(width: 8),
            const Icon(PhosphorIconsLight.speakerHigh,
                color: Colors.white70, size: 14),
            SizedBox(
              width: 80,
              child: Slider(
                value:
                    ((_player?.state.volume ?? 100).clamp(0, 100)).toDouble(),
                min: 0,
                max: 100,
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChanged: (v) async {
                  await _player?.setVolume(v);
                  setState(() {});
                },
              ),
            ),
          ]),
        ),
      ),
    );

    if (_openError != null) {
      innerChildren.add(
        Positioned(
          left: 8,
          right: 8,
          bottom: 40,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Lỗi mở video: $_openError',
              style: const TextStyle(color: Colors.white, fontSize: 11),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: false,
      child: Stack(children: [
        Positioned(
          left: clamped.dx,
          top: clamped.dy,
          width: _size.width,
          height: _size.height,
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16.0),
                border: Border.all(color: Colors.white24, width: 1),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black54, blurRadius: 8, spreadRadius: 2),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16.0),
                child: Stack(children: innerChildren),
              ),
            ),
          ),
        ),
      ]),
    );
  }

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
        return Uri.file(path, windows: true).toString();
      }
      return path;
    } catch (_) {
      return path;
    }
  }
}
