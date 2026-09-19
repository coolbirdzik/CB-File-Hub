import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../services/media/media_kit_playback.dart';
import 'video_player_utils.dart';

/// Decodes seek bar hover frames on a second, silent player so the main
/// player's position and decoder are never touched. The decoder opens lazily
/// on the first hover and stays open until [dispose].
class VideoSeekPreviewController extends ChangeNotifier {
  VideoSeekPreviewController({
    required this.source,
    required this.enableHardwareAcceleration,
  });

  final String source;
  final bool enableHardwareAcceleration;

  PlaybackPlayer? _player;
  PlaybackVideoController? _video;
  Timer? _seekThrottle;
  Duration? _pendingSeek;
  bool _disposed = false;

  /// Null until the first [seek] opens the preview decoder.
  PlaybackVideoController? get video => _video;

  void seek(Duration position) {
    if (_disposed) return;
    if (_player == null) _open();
    _pendingSeek = position;
    if (_seekThrottle == null) _flushSeek();
  }

  void _open() {
    final player = PlaybackPlayer(
      configuration: const PlaybackConfiguration(framePreview: true),
    );
    _player = player;
    _video = PlaybackVideoController(
      player,
      configuration: PlaybackVideoConfiguration(
        enableHardwareAcceleration: enableHardwareAcceleration,
      ),
    );
    notifyListeners();
    unawaited(
      player.open(PlaybackMedia(source), play: false).catchError((Object e) {
        debugPrint('VideoSeekPreview: failed to open $source: $e');
      }),
    );
  }

  void _flushSeek() {
    final target = _pendingSeek;
    _pendingSeek = null;
    final player = _player;
    if (target == null || player == null) return;
    unawaited(player.seek(target));
    // Keyframe seeks are cheap, but hover events arrive faster than frames can
    // be shown. Keep only the newest position between flushes.
    _seekThrottle = Timer(const Duration(milliseconds: 60), () {
      _seekThrottle = null;
      if (!_disposed) _flushSeek();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _seekThrottle?.cancel();
    final player = _player;
    _player = null;
    _video = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}

/// Floats a frame and timestamp above a seek bar while a mouse hovers it.
///
/// A pressed pointer hides the preview: dragging already previews on the main
/// video surface, so a second frame would only cover it.
class VideoSeekHoverPreview extends StatefulWidget {
  const VideoSeekHoverPreview({
    super.key,
    required this.duration,
    required this.child,
    this.frames,
    this.videoAspectRatio,
    this.onHoverChanged,
  });

  final Duration duration;

  /// Null shows only the timestamp, e.g. for audio or unseekable streams.
  final VideoSeekPreviewController? frames;
  final double? videoAspectRatio;
  final ValueChanged<bool>? onHoverChanged;

  /// A Material [Slider] filling this widget's width.
  final Widget child;

  /// Material [Slider] pads its track by the default overlay radius.
  static const double trackInset = 24;

  @override
  State<VideoSeekHoverPreview> createState() => _VideoSeekHoverPreviewState();
}

class _VideoSeekHoverPreviewState extends State<VideoSeekHoverPreview> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();
  double _hoverX = 0;
  double _width = 0;
  bool _pressed = false;
  bool _showing = false;

  Duration get _hoverPosition {
    final track = _width - 2 * VideoSeekHoverPreview.trackInset;
    if (track <= 0) return Duration.zero;
    var fraction = ((_hoverX - VideoSeekHoverPreview.trackInset) / track).clamp(
      0.0,
      1.0,
    );
    if (Directionality.of(context) == TextDirection.rtl) {
      fraction = 1 - fraction;
    }
    return widget.duration * fraction;
  }

  void _onHover(PointerHoverEvent event) {
    if (_pressed || widget.duration <= Duration.zero) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    setState(() {
      _width = box.size.width;
      _hoverX = event.localPosition.dx.clamp(0.0, _width);
    });
    widget.frames?.seek(_hoverPosition);
    _setShowing(true);
  }

  void _setShowing(bool showing) {
    if (_showing == showing) return;
    _showing = showing;
    showing ? _portal.show() : _portal.hide();
    widget.onHoverChanged?.call(showing);
  }

  @override
  void dispose() {
    // The tree is locked while unmounting; report the hover end afterwards.
    // The portal is already detached here, so rely on our own flag.
    final callback = widget.onHoverChanged;
    if (_showing && callback != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => callback(false));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildOverlay,
      child: CompositedTransformTarget(
        link: _link,
        child: Listener(
          onPointerDown: (_) {
            _pressed = true;
            _setShowing(false);
          },
          onPointerUp: (_) => _pressed = false,
          onPointerCancel: (_) => _pressed = false,
          child: MouseRegion(
            onHover: _onHover,
            onExit: (_) => _setShowing(false),
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final frames = widget.frames;
    final frameWidth = (_width * 0.22).clamp(128.0, 240.0);
    final aspectRatio = (widget.videoAspectRatio ?? 16 / 9).clamp(0.5, 2.5);
    final cardWidth = frames == null ? 72.0 : frameWidth;
    // Keep the card over the bar instead of spilling past the player edges.
    final centerX = _width <= cardWidth
        ? _width / 2
        : _hoverX.clamp(cardWidth / 2, _width - cardWidth / 2);

    final timeLabel = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          VideoPlayerUtils.formatDuration(_hoverPosition),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );

    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        // Just above the track line, clear of the slider thumb.
        targetAnchor: Alignment.centerLeft,
        followerAnchor: Alignment.bottomCenter,
        offset: Offset(centerX, -14),
        child: IgnorePointer(
          child: ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (frames != null)
                  Container(
                    width: frameWidth,
                    height: frameWidth / aspectRatio,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 8),
                      ],
                    ),
                    child: ListenableBuilder(
                      listenable: frames,
                      builder: (context, _) => switch (frames.video) {
                        final video? => PlaybackVideo(controller: video),
                        null => const SizedBox.expand(),
                      },
                    ),
                  ),
                const SizedBox(height: 4),
                timeLabel,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
