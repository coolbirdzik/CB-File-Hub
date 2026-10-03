import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as video;

import '../../helpers/core/path_utils.dart';
import '../network_browsing/smb_service.dart';
import '../streaming/smb_http_proxy_server.dart';

/// Preserve literal filename characters, URL escaping and SMB credentials.
Uri playbackSourceUri(String source) {
  final windowsPath =
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(source) || source.startsWith(r'\\');
  if (windowsPath) return Uri.file(source, windows: true);
  final uri = Uri.parse(source);
  return uri.hasScheme ? uri : Uri.file(source, windows: Platform.isWindows);
}

String playbackMediaSource(String source) {
  final uri = playbackSourceUri(source);
  // media_kit's URI parser mistakes named file:// hosts for local paths.
  // Pass native paths so UNC hosts and literal filename characters survive.
  return uri.scheme == 'file'
      ? uri.toFilePath(windows: Platform.isWindows)
      : uri.toString();
}

// TEMP-DIAG
void tempDiag(String message) {
  try {
    File('C:/Users/ngtan/AppData/Local/Temp/claude/l--Code-coolbirdfm-flutter/6b1fa93e-8926-4f83-b6f2-cb13bb1b692d/scratchpad/diag.log').writeAsStringSync(
      '${DateTime.now().toIso8601String()} $message\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

/// Shared media_kit backend for the main player, PiP and frame picker.
class PlaybackPlayer {
  PlaybackPlayer({
    this.configuration = const PlaybackConfiguration(),
    mk.Player? player,
  }) : _player = player ?? _createPlayer() {
    _durationSubscription = stream.duration.listen((duration) {
      if (duration > Duration.zero && _pendingSeek != null) {
        final position = _pendingSeek!;
        _pendingSeek = null;
        unawaited(_player.seek(position));
      }
    });
    _sizeSubscriptions = [
      stream.width.listen((_) => _applyLargeVideoDecoder()),
      stream.height.listen((_) => _applyLargeVideoDecoder()),
    ];
    // Subscribed before any UI listener, so [fellBackToSoftware] is already
    // set when theirs runs for the same error.
    _errorSubscription = stream.error.listen(_onError);
  }

  /// libmpv decoder errors that a software decoder can recover from.
  static bool isHardwareDecodeError(String error) {
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

  /// Long edge from which [PlaybackVideoConfiguration.gpuDecodeLargeVideos]
  /// switches to hardware decoding.
  static const largeVideoLongEdge = 3840;

  static mk.Player _createPlayer() {
    mk.MediaKit.ensureInitialized();
    return mk.Player(
      configuration: const mk.PlayerConfiguration(title: 'CB File Hub'),
    );
  }

  final PlaybackConfiguration configuration;
  final mk.Player _player;
  video.VideoController? _videoController;
  bool _playRequested = false;
  Future<void>? _disposal;
  Uri? _proxyUrl;
  Duration? _pendingSeek;
  late final StreamSubscription<Duration> _durationSubscription;
  late final List<StreamSubscription<int?>> _sizeSubscriptions;
  PlaybackVideoConfiguration? _videoConfiguration;
  bool _largeVideoHwdec = false;
  late final StreamSubscription<String> _errorSubscription;
  bool _softwareFallback = false;

  mk.Player get controller => _player;
  mk.PlayerState get state => _player.state;
  mk.PlayerStream get stream => _player.stream;

  /// Playback intent stays synchronous while native state events catch up.
  bool get playRequested => _playRequested;

  /// A GPU decode error switched this player to software decoding.
  bool get fellBackToSoftware => _softwareFallback;

  Future<void> open(PlaybackMedia media, {bool play = true}) async {
    _playRequested = play;
    _pendingSeek = null;
    final previousProxy = _proxyUrl;
    _proxyUrl = null;
    final uri = playbackSourceUri(media.uri);
    String source = playbackMediaSource(media.uri);
    if (uri.scheme == 'smb') {
      if (Platform.isWindows) {
        if (uri.userInfo.isNotEmpty) {
          final separator = uri.userInfo.indexOf(':');
          final username = Uri.decodeComponent(
            separator < 0 ? uri.userInfo : uri.userInfo.substring(0, separator),
          ).replaceFirst(';', r'\');
          final password = separator < 0
              ? ''
              : Uri.decodeComponent(uri.userInfo.substring(separator + 1));
          // Reuse the same Windows authentication path as SMB browsing. The
          // OS session is shared with browser tabs and PiP; do not disconnect
          // it when an individual decoder closes.
          final result = await SMBService().connect(
            host: uri.host,
            username: username,
            password: password,
          );
          if (!result.success) {
            throw StateError(result.errorMessage ?? 'SMB connection failed');
          }
        }
        source = smbMrlToUnc(source);
      } else {
        _proxyUrl = await SmbHttpProxyServer.instance.urlFor(source);
        source = _proxyUrl.toString();
      }
    }
    if (_disposal != null) return;
    if (_player.platform case final mk.NativePlayer native) {
      // The previous file may have been large; probe the next one with the
      // configured decoder until its size is known.
      if (_largeVideoHwdec) {
        _largeVideoHwdec = false;
        await _applyHwdec();
      }
      await native.setProperty(
        'cache-secs',
        (configuration.networkCaching.inMilliseconds / 1000).toString(),
      );
      if (configuration.framePreview) {
        // Hover previews need a frame quickly, not sound or exact frames.
        await native.setProperty('aid', 'no');
        await native.setProperty('hr-seek', 'no');
      }
    }
    await _player.setPlaylistMode(
      configuration.looping ? mk.PlaylistMode.single : mk.PlaylistMode.none,
    );
    try {
      await _player.open(mk.Media(source), play: play);
    } finally {
      if (previousProxy != null) {
        SmbHttpProxyServer.instance.release(previousProxy);
      }
    }
  }

  Future<void> play() {
    _playRequested = true;
    return _player.play();
  }

  Future<void> pause() {
    _playRequested = false;
    return _player.pause();
  }

  Future<void> playOrPause() =>
      playRequested && !state.completed ? pause() : play();

  /// [exact] false jumps to the nearest keyframe. Precise seeks decode every
  /// frame from the previous keyframe, which stalls high-bitrate 4K scrubbing.
  Future<void> seek(Duration position, {bool exact = true}) async {
    // open() returns before mpv has loaded metadata. A restore seek issued
    // immediately afterwards would otherwise be discarded by the decoder.
    if (state.duration == Duration.zero) {
      _pendingSeek = position;
      return;
    }
    if (!exact) {
      if (_player.platform case final mk.NativePlayer native) {
        await native.command([
          'seek',
          (position.inMilliseconds / 1000).toStringAsFixed(3),
          'absolute+keyframes',
        ]);
        return;
      }
    }
    await _player.seek(position);
  }

  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0, 100));
  Future<void> setRate(double rate) => _player.setRate(rate);
  Future<void> next() => _player.next();
  Future<void> previous() => _player.previous();
  Future<Uint8List?> screenshot() => _player.screenshot(format: 'image/png');
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    await _durationSubscription.cancel();
    await _errorSubscription.cancel();
    for (final subscription in _sizeSubscriptions) {
      await subscription.cancel();
    }
    await _player.dispose();
    if (_proxyUrl case final url?) SmbHttpProxyServer.instance.release(url);
  }

  video.VideoController _configureVideo(PlaybackVideoConfiguration config) {
    _videoConfiguration = config;
    if (_videoController == null) {
      _videoController = video.VideoController(
        _player,
        configuration: video.VideoControllerConfiguration(
          // The render path is fixed at creation, and hardware decoding is
          // only real with a GPU texture to hand frames to.
          enableHardwareAcceleration:
              config.enableHardwareAcceleration || config.gpuDecodeLargeVideos,
          hwdec: _hwdec,
        ),
      );
    } else {
      // Reuse the texture and decoder session when changing preferences. An
      // explicit choice also retries a decoder that fell back earlier.
      _softwareFallback = false;
      unawaited(_applyHwdec());
    }
    return _videoController!;
  }

  String get _hwdec {
    final config = _videoConfiguration;
    if (config == null || _softwareFallback) return 'no';
    final gpu =
        config.enableHardwareAcceleration ||
        (config.gpuDecodeLargeVideos && _largeVideoHwdec);
    return gpu ? 'auto-safe' : 'no';
  }

  Future<void> _applyHwdec() async {
    final controller = _videoController;
    if (controller == null) return;
    if (_player.platform case final mk.NativePlayer native) {
      await controller.platform.future;
      if (_disposal == null) {
        tempDiag('hwdec -> $_hwdec (large=$_largeVideoHwdec fallback=$_softwareFallback) frame=${configuration.framePreview}'); // TEMP-DIAG
        await native.setProperty('hwdec', _hwdec);
      }
    }
  }

  /// 4K software decoding needs hundreds of ms per precise seek when keyframes
  /// are sparse; the GPU decoder lands on the same frame several times faster.
  void _applyLargeVideoDecoder() {
    final config = _videoConfiguration;
    if (config == null || !config.gpuDecodeLargeVideos) return;
    final width = state.width ?? 0;
    final height = state.height ?? 0;
    if (width == 0 || height == 0) return;
    final large = (width > height ? width : height) >= largeVideoLongEdge;
    tempDiag('size ${width}x$height large=$large was=$_largeVideoHwdec'); // TEMP-DIAG
    if (large == _largeVideoHwdec) return;
    _largeVideoHwdec = large;
    if (!config.enableHardwareAcceleration) unawaited(_applyHwdec());
  }

  /// Recover a failing GPU decoder on the CPU without reopening the media.
  /// Only libmpv's decoder changes; no new D3D11 device or texture is made,
  /// which is what can take down the engine on a failing driver.
  void _onError(String error) {
    if (_softwareFallback || _hwdec == 'no') return;
    tempDiag('error: $error'); // TEMP-DIAG
    if (!isHardwareDecodeError(error)) return;
    _softwareFallback = true;
    unawaited(_applyHwdec());
  }
}

class PlaybackConfiguration {
  const PlaybackConfiguration({
    this.networkCaching = const Duration(seconds: 1),
    this.looping = false,
    this.framePreview = false,
  });
  final Duration networkCaching;
  final bool looping;

  /// Silent decoder that seeks to keyframes, for seek bar thumbnails.
  final bool framePreview;
}

class PlaybackMedia {
  const PlaybackMedia(this.uri);
  final String uri;
}

class PlaybackVideoConfiguration {
  const PlaybackVideoConfiguration({
    this.enableHardwareAcceleration = false,
    this.gpuDecodeLargeVideos = false,
  });
  final bool enableHardwareAcceleration;

  /// Keep software decoding, but use the GPU decoder for 4K and larger.
  final bool gpuDecodeLargeVideos;

  /// Maps the persisted `video_decoder` choice: 'auto', 'hardware' or
  /// 'software'.
  factory PlaybackVideoConfiguration.forDecoder(String? mode) => switch (mode) {
    'hardware' => const PlaybackVideoConfiguration(
      enableHardwareAcceleration: true,
    ),
    'software' => const PlaybackVideoConfiguration(),
    // The default picks per platform. GPU decoding has crashed some Windows
    // drivers, so there it is only used for 4K, where CPU seeks are too slow.
    // Elsewhere the platform decoder (MediaCodec, VideoToolbox, VA-API via
    // auto-safe) is reliable and far cheaper than the CPU, notably on mobile.
    _ when !kIsWeb && Platform.isWindows => const PlaybackVideoConfiguration(
      gpuDecodeLargeVideos: true,
    ),
    _ => const PlaybackVideoConfiguration(enableHardwareAcceleration: true),
  };
}

class PlaybackVideoController {
  PlaybackVideoController(
    this.player, {
    PlaybackVideoConfiguration configuration =
        const PlaybackVideoConfiguration(),
  }) : controller = player._configureVideo(configuration);
  final PlaybackPlayer player;
  final video.VideoController controller;
}

class PlaybackVideo extends StatelessWidget {
  const PlaybackVideo({
    super.key,
    required this.controller,
    this.fill = Colors.black,
    this.fit = BoxFit.contain,
  });
  final PlaybackVideoController controller;
  final Color fill;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => video.Video(
    controller: controller.controller,
    fill: fill,
    fit: fit,
    controls: video.NoVideoControls,
    pauseUponEnteringBackgroundMode: false,
    resumeUponEnteringForegroundMode: false,
  );
}
