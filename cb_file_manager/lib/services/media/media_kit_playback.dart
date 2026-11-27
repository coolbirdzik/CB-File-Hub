import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as video;

import '../../helpers/core/path_utils.dart';
import '../network_browsing/desktop_smb_mounts.dart';
import '../network_browsing/smb_service.dart';
import '../streaming/smb_http_proxy_server.dart';
import 'media_language_labels.dart';
import 'subtitle_languages.dart';

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

/// Shared media_kit backend for the main player, PiP and frame picker.
class PlaybackPlayer {
  PlaybackPlayer({
    this.configuration = const PlaybackConfiguration(),
    mk.Player? player,
  }) : _player = player ?? _createPlayer(configuration) {
    _durationSubscription = stream.duration.listen((duration) {
      if (duration > Duration.zero && _pendingSeek != null) {
        final position = _pendingSeek!;
        _pendingSeek = null;
        unawaited(_player.seek(position));
      }
    });
    _sizeSubscriptions = [
      stream.width.listen((_) => _onVideoDimensionsChanged()),
      stream.height.listen((_) => _onVideoDimensionsChanged()),
    ];
    _videoParamsSubscription = stream.videoParams.listen((_) {
      _reapplyDesiredOutputSize();
    });
    // Subscribed before any UI listener, so [fellBackToSoftware] is already
    // set when theirs runs for the same error.
    _errorSubscription = stream.error.listen(_onError);
    _live.add(this);
  }

  static final _live = <PlaybackPlayer>{};

  /// Disposes every player of this isolate. libmpv's event thread calls back
  /// into the isolate that created the player, so this must finish before an
  /// engine is torn down, or that callback crashes the whole process.
  static Future<void> disposeAll({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_live.isEmpty) return;
    await Future.wait([
      for (final player in _live.toList()) player.dispose(),
    ]).timeout(timeout, onTimeout: () => const []);
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

  /// mpv reports every undecodable audio packet as an error, then carries on
  /// with the next one. A damaged stretch of audio is a glitch, not a reason to
  /// replace the playing video with an error screen.
  static bool isRecoverableAudioDecodeError(String error) =>
      error.toLowerCase().contains('error decoding audio');

  /// Long edge from which [PlaybackVideoConfiguration.gpuDecodeLargeVideos]
  /// switches to hardware decoding and fast 4K/8K render tuning activates.
  static const largeVideoLongEdge = 3840;

  /// Computes a GPU-friendly output texture size capped to the display viewport
  /// so 4K/8K videos do not allocate giant DXGI/EGL surfaces when rendered in a
  /// smaller window. Returns null if no downscaling is needed.
  static ({int width, int height})? computeCappedOutputSize({
    required int videoWidth,
    required int videoHeight,
    required double viewportWidth,
    required double viewportHeight,
    required double devicePixelRatio,
    int maxEdge = 3840,
    bool forceViewportSize = false,
  }) {
    if (videoWidth <= 0 || videoHeight <= 0) return null;
    final dpr = devicePixelRatio.clamp(1.0, 4.0);
    final rawW = (viewportWidth * dpr).round();
    final rawH = (viewportHeight * dpr).round();
    if (rawW <= 0 || rawH <= 0) return null;

    int even(int v) => (v < 2 ? 2 : (v & ~1));

    if (forceViewportSize) {
      // VR projection renders a fresh viewport at display aspect ratio.
      final scale = (rawW > maxEdge || rawH > maxEdge)
          ? maxEdge / (rawW > rawH ? rawW : rawH)
          : 1.0;
      return (
        width: even((rawW * scale).round()),
        height: even((rawH * scale).round()),
      );
    }

    final capW = rawW < maxEdge ? rawW : maxEdge;
    final capH = rawH < maxEdge ? rawH : maxEdge;
    if (videoWidth <= capW && videoHeight <= capH) return null;

    final scaleW = capW / videoWidth;
    final scaleH = capH / videoHeight;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    return (
      width: even((videoWidth * scale).round()),
      height: even((videoHeight * scale).round()),
    );
  }

  static mk.Player _createPlayer(PlaybackConfiguration configuration) {
    mk.MediaKit.ensureInitialized();
    final bytes = configuration.framePreview
        ? 8 * 1024 * 1024
        : configuration.bufferSizeMb.clamp(8, 512) * 1024 * 1024;
    return mk.Player(
      configuration: mk.PlayerConfiguration(
        title: 'CB File Hub',
        bufferSize: bytes,
      ),
    );
  }

  final PlaybackConfiguration configuration;
  final mk.Player _player;
  video.VideoController? _videoController;
  bool _playRequested = false;
  Future<void>? _disposal;
  Uri? _proxyUrl;
  String? _subtitleSource;
  String? _subtitleCacheSource;

  /// Resolved local/UNC/proxy source. Valid only for this player's lifetime.
  String? get subtitleSource => _subtitleSource;

  /// Original identity survives changes to a temporary SMB proxy URL.
  String? get subtitleCacheSource => _subtitleCacheSource ?? subtitleSource;

  /// media_kit retains AudioTrack.auto() in its state. mpv's resolved aid
  /// identifies the actual default track, which need not be the first stream.
  Future<int> subtitleAudioTrackOrdinal() async {
    var id = state.track.audio.id;
    if (_player.platform case final mk.NativePlayer native) {
      try {
        if (await _nativeReady(native) && _disposal == null) {
          id = await native.getProperty('aid', waitForInitialization: false);
        }
      } catch (_) {
        /* Use state during load/teardown. */
      }
    }
    final tracks = state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    final ordinal = tracks.indexWhere((t) => t.id == id);
    return ordinal < 0 ? 0 : ordinal;
  }

  Duration? _pendingSeek;
  String? subtitleAudioLanguageForOrdinal(int ordinal) {
    final tracks = state.tracks.audio
        .where((t) => t.id != 'auto' && t.id != 'no')
        .toList();
    if (ordinal < 0 || ordinal >= tracks.length) return null;
    final name = mediaLanguageEnglishName(tracks[ordinal].language);
    if (name == 'Chinese (Traditional)' || name == 'Chinese (Simplified)') {
      return 'zh';
    }
    for (final language in subtitleSourceLanguages.entries) {
      if (language.value == name) return language.key;
    }
    return null;
  }

  late final StreamSubscription<Duration> _durationSubscription;
  late final List<StreamSubscription<int?>> _sizeSubscriptions;
  late final StreamSubscription<mk.VideoParams> _videoParamsSubscription;
  PlaybackVideoConfiguration? _videoConfiguration;
  bool _largeVideoHwdec = false;
  bool _largeVideoTuned = false;
  int? _desiredOutputWidth;
  int? _desiredOutputHeight;
  int? _lastOutputWidth;
  int? _lastOutputHeight;
  late final StreamSubscription<String> _errorSubscription;
  bool _softwareFallback = false;

  /// Heuristic for filenames that are clearly 4K/8K so Windows `auto` mode
  /// starts on GPU decoding from frame 0 instead of probing on CPU first.
  static bool isLikelyLargeVideoSource(String source) => RegExp(
    r'(?:^|[\s._\-\[\(])(8k|4k|4320p|2160p|uhd)(?:$|[\s._\-\]\)])',
    caseSensitive: false,
  ).hasMatch(source);

  /// True when the active video's long edge is 4K (3840px) or larger.
  bool get isLargeVideo {
    final width = state.width ?? 0;
    final height = state.height ?? 0;
    return (width > height ? width : height) >= largeVideoLongEdge;
  }

  /// Sets a raw libmpv property safely if the native player is ready.
  Future<void> setNativeProperty(String name, String value) async {
    if (_player.platform case final mk.NativePlayer native) {
      try {
        if (!await _nativeReady(native) || _disposal != null) return;
        await native.setProperty(name, value, waitForInitialization: false);
      } catch (e) {
        if (_disposal == null) {
          debugPrint('Could not set mpv property $name=$value: $e');
        }
      }
    }
  }

  /// Updates the demuxer buffer and network cache settings on the live player.
  Future<void> applyBufferSettings({
    required int bufferSizeMb,
    required Duration networkCaching,
  }) async {
    if (_player.platform case final mk.NativePlayer native) {
      try {
        if (!await _nativeReady(native) || _disposal != null) return;
        final clampedMb = bufferSizeMb.clamp(8, 512);
        final maxBytes = clampedMb * 1024 * 1024;
        final backBytes = (clampedMb ~/ 2).clamp(4, 256) * 1024 * 1024;
        final cacheSecs = (networkCaching.inMilliseconds / 1000)
            .clamp(1.0, 120.0)
            .toStringAsFixed(1);
        await native.setProperty(
          'demuxer-max-bytes',
          maxBytes.toString(),
          waitForInitialization: false,
        );
        if (_disposal != null) return;
        await native.setProperty(
          'demuxer-max-back-bytes',
          backBytes.toString(),
          waitForInitialization: false,
        );
        if (_disposal != null) return;
        await native.setProperty(
          'cache-secs',
          cacheSecs,
          waitForInitialization: false,
        );
        if (_disposal != null) return;
        await native.setProperty(
          'demuxer-readahead-secs',
          cacheSecs,
          waitForInitialization: false,
        );
      } catch (e) {
        if (_disposal == null) {
          debugPrint('Could not update buffer settings: $e');
        }
      }
    }
  }

  /// Resizes the native video output texture (e.g. capping 8K video to the
  /// viewport pixel size) while avoiding redundant texture reallocations.
  Future<void> setOutputSize({int? width, int? height}) async {
    _desiredOutputWidth = width;
    _desiredOutputHeight = height;
    final controller = _videoController;
    if (controller == null || _disposal != null) return;
    if (_lastOutputWidth == width && _lastOutputHeight == height) return;
    _lastOutputWidth = width;
    _lastOutputHeight = height;
    try {
      await controller.setSize(width: width, height: height);
    } catch (e) {
      if (_disposal == null) {
        debugPrint('Could not resize video output: $e');
      }
    }
  }

  /// media_kit_video's NativeVideoController listens to `videoParams` and calls
  /// `VideoOutputManager.SetSize(videoWidth, videoHeight)`, which would reset a
  /// capped 8K texture back to 8192x4096. Re-apply our desired size right after.
  void _reapplyDesiredOutputSize() {
    final w = _desiredOutputWidth;
    final h = _desiredOutputHeight;
    final controller = _videoController;
    if (w == null || h == null || controller == null || _disposal != null) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 50), () async {
      if (_disposal != null) return;
      if (_desiredOutputWidth != w || _desiredOutputHeight != h) return;
      try {
        await controller.setSize(width: w, height: h);
      } catch (_) {}
    });
  }

  mk.Player get controller => _player;
  mk.PlayerState get state => _player.state;
  mk.PlayerStream get stream => _player.stream;

  // media_kit checks disposed before awaiting initialization in its raw FFI
  // helpers. Recheck after those awaits, then make the call without another
  // initialization wait; otherwise a closing player can invalidate the handle.
  Future<bool> _nativeReady(mk.NativePlayer native) async {
    if (_disposal != null || native.disposed) return false;
    await native.waitForPlayerInitialization;
    await native.waitForVideoControllerInitializationIfAttached;
    return _disposal == null && !native.disposed;
  }

  /// Samples the active SMB source in bytes per second while listened to.
  Stream<int?> sampleSmbReadSpeed() {
    final proxy = SmbHttpProxyServer.instance;
    final clock = Stopwatch()..start();
    var previousUrl = _proxyUrl;
    var previousBytes = previousUrl == null
        ? 0
        : proxy.bytesRead(previousUrl) ?? 0;
    var previousMicros = 0;

    return Stream<void>.periodic(const Duration(seconds: 1)).asyncMap((
      _,
    ) async {
      if (_disposal != null) return null;
      final micros = clock.elapsedMicroseconds;
      final elapsed = micros - previousMicros;
      previousMicros = micros;
      if (_proxyUrl case final url?) {
        final bytes = proxy.bytesRead(url);
        if (bytes == null) return null;
        final bytesRead = bytes - (previousUrl == url ? previousBytes : 0);
        previousUrl = url;
        previousBytes = bytes;
        return elapsed > 0
            ? (bytesRead * Duration.microsecondsPerSecond / elapsed).round()
            : null;
      }

      // For UNC paths and mounted SMB files, mpv reports input throughput.
      if (_player.platform case final mk.NativePlayer native
          when Uri.tryParse(_subtitleCacheSource ?? '')?.scheme == 'smb') {
        try {
          if (!await _nativeReady(native) || _disposal != null) return null;
          return int.tryParse(
            await native.getProperty(
              'cache-speed',
              waitForInitialization: false,
            ),
          );
        } catch (_) {
          // The property can be unavailable during open or teardown.
        }
      }
      return null;
    }).distinct();
  }

  /// Playback intent stays synchronous while native state events catch up.
  bool get playRequested => _playRequested;

  /// A GPU decode error switched this player to software decoding.
  bool get fellBackToSoftware => _softwareFallback;

  Future<void> open(PlaybackMedia media, {bool play = true}) async {
    if (_disposal != null) return;
    _playRequested = play;
    _pendingSeek = null;
    final previousProxy = _proxyUrl;
    _proxyUrl = null;
    try {
      final uri = playbackSourceUri(media.uri);
      String source = playbackMediaSource(media.uri);
      if (uri.scheme == 'smb') {
        if (Platform.isWindows) {
          if (uri.userInfo.isNotEmpty) {
            final separator = uri.userInfo.indexOf(':');
            final username = Uri.decodeComponent(
              separator < 0
                  ? uri.userInfo
                  : uri.userInfo.substring(0, separator),
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
          final mountedFile = DesktopSmbMount.isSupported
              ? await DesktopSmbMount.resolveFile(uri)
              : null;
          if (mountedFile != null) {
            source = mountedFile;
          } else {
            final proxy = await SmbHttpProxyServer.instance.urlFor(source);
            if (_disposal != null) {
              SmbHttpProxyServer.instance.release(proxy);
              return;
            }
            _proxyUrl = proxy;
            source = _proxyUrl.toString();
          }
        }
      }
      if (_disposal != null) return;
      if (_player.platform case final mk.NativePlayer native) {
        // Pre-enable GPU decoding from frame 0 for sources that are clearly
        // 4K/8K (e.g. `*_8K.mp4`); otherwise reset to the configured decoder
        // until the stream dimensions are known.
        final preEnableGpu =
            (_videoConfiguration?.gpuDecodeLargeVideos ?? false) &&
            !configuration.framePreview &&
            isLikelyLargeVideoSource(media.uri);
        if (_largeVideoHwdec != preEnableGpu) {
          _largeVideoHwdec = preEnableGpu;
          await _applyHwdec();
        }
        if (_largeVideoTuned) {
          _largeVideoTuned = false;
          await _applyLargeVideoRenderTuning(false);
        }
        if (!await _nativeReady(native) || _disposal != null) return;
        await native.setProperty(
          'hwdec-codecs',
          'all',
          waitForInitialization: false,
        );
        if (_disposal != null) return;
        await native.setProperty(
          'vd-lavc-threads',
          '0',
          waitForInitialization: false,
        );
        if (_disposal != null) return;
        final isNetwork =
            uri.scheme == 'smb' ||
            uri.scheme == 'http' ||
            uri.scheme == 'https';
        final effectiveCache =
            isNetwork &&
                configuration.networkCaching < const Duration(seconds: 5)
            ? const Duration(seconds: 5)
            : configuration.networkCaching;
        await native.setProperty(
          'cache-secs',
          (effectiveCache.inMilliseconds / 1000).toString(),
          waitForInitialization: false,
        );
        if (_disposal != null) return;
        await native.setProperty(
          'demuxer-readahead-secs',
          (effectiveCache.inMilliseconds / 1000).toString(),
          waitForInitialization: false,
        );
        if (configuration.framePreview) {
          // Hover previews need a small frame quickly, not sound, exact seeks,
          // or full-quality deblocking/scaling.
          for (final prop in const {
            'aid': 'no',
            'hr-seek': 'no',
            'vd-lavc-fast': 'yes',
            'vd-lavc-skiploopfilter': 'all',
            'vd-lavc-skipframe': 'nonref',
            'scale': 'bilinear',
            'dscale': 'bilinear',
            'dither-depth': 'no',
          }.entries) {
            if (_disposal != null) return;
            await native.setProperty(
              prop.key,
              prop.value,
              waitForInitialization: false,
            );
          }
        }
      }
      if (_disposal != null) return;
      _subtitleSource = source;
      _subtitleCacheSource = media.uri;
      await _player.setPlaylistMode(
        configuration.looping ? mk.PlaylistMode.single : mk.PlaylistMode.none,
      );
      if (_disposal != null) return;
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
    if (_disposal != null) return;
    // open() returns before mpv has loaded metadata. A restore seek issued
    // immediately afterwards would otherwise be discarded by the decoder.
    if (state.duration == Duration.zero) {
      _pendingSeek = position;
      return;
    }
    // After EOF, use media_kit's seek to clear its completed flag before play.
    // A raw keyframe command leaves that flag set, making play restart at zero.
    if (!exact && !state.completed) {
      if (_player.platform case final mk.NativePlayer native) {
        if (!await _nativeReady(native) || _disposal != null) return;
        await native.command([
          'seek',
          (position.inMilliseconds / 1000).toStringAsFixed(3),
          'absolute+keyframes',
        ], waitForInitialization: false);
        return;
      }
    }
    await _player.seek(position);
    await _resumeAfterSeek();
  }

  Future<void> _resumeAfterSeek() async {
    // Reaching EOF during a live seek stops native playback without changing
    // the user's intent. Seeking back must resume it. Read the latest intent:
    // a user pause or disposal while the seek was in flight takes precedence.
    if (_disposal == null && _playRequested && !state.playing) {
      await _player.play();
    }
  }

  Future<void> setVolume(double volume) =>
      _player.setVolume(volume.clamp(0, 100));

  Future<void> setRate(double rate) => _player.setRate(rate);
  Future<void> next() => _player.next();
  Future<void> previous() => _player.previous();
  Future<Uint8List?> screenshot() => _player.screenshot(format: 'image/png');
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    // Keep the player registered until native callbacks have been detached.
    // Engine shutdown may call disposeAll while an individual widget is
    // already disposing its player, and must still await that same future.
    try {
      await _durationSubscription.cancel();
      await _errorSubscription.cancel();
      await _videoParamsSubscription.cancel();
      for (final subscription in _sizeSubscriptions) {
        await subscription.cancel();
      }
      // NativePlayer.dispose acquires a process-wide lock before waiting for
      // the video surface. Wait outside that lock so closing an initializing
      // preview cannot block creation of every subsequent player.
      if (_player.platform case final mk.NativePlayer native) {
        await native.future;
        await native.waitForPlayerInitialization;
        await native.waitForVideoControllerInitializationIfAttached;
      }
      await _player.dispose();
    } finally {
      _live.remove(this);
      if (_proxyUrl case final url?) SmbHttpProxyServer.instance.release(url);
      _proxyUrl = null;
    }
  }

  video.VideoController _configureVideo(PlaybackVideoConfiguration config) {
    _videoConfiguration = config;
    if (_videoController == null) {
      _lastOutputWidth = config.outputWidth;
      _lastOutputHeight = config.outputHeight;
      _videoController = video.VideoController(
        _player,
        configuration: video.VideoControllerConfiguration(
          // The render path is fixed at creation, and hardware decoding is
          // only real with a GPU texture to hand frames to.
          enableHardwareAcceleration:
              config.enableHardwareAcceleration || config.gpuDecodeLargeVideos,
          hwdec: _hwdec,
          width: config.outputWidth,
          height: config.outputHeight,
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
    if (!gpu) return 'no';
    // On Windows with media_kit's ANGLE OpenGL backend, `auto-safe` only tries
    // zero-copy decoders and silently falls back to CPU on 8K 10-bit HEVC when
    // D3D11-EGL interop is unavailable. Include copy-back decoders so NVDEC /
    // D3D11VA hardware ASICs still decode 8K60 instead of pegging the CPU.
    if (!kIsWeb && Platform.isWindows) {
      return 'd3d11va,d3d11va-copy,nvdec-copy,auto-copy';
    }
    return 'auto-safe';
  }

  Future<void> _applyHwdec() async {
    final controller = _videoController;
    if (controller == null) return;
    if (_player.platform case final mk.NativePlayer native) {
      try {
        if (!await _nativeReady(native) || _disposal != null) return;
        await native.setProperty('hwdec', _hwdec, waitForInitialization: false);
      } catch (e) {
        if (_disposal == null) debugPrint('Could not update video decoder: $e');
      }
    }
  }

  void _onVideoDimensionsChanged() {
    _applyLargeVideoDecoder();
    final large = isLargeVideo;
    if (large != _largeVideoTuned && !configuration.framePreview) {
      _largeVideoTuned = large;
      unawaited(_applyLargeVideoRenderTuning(large));
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
    if (large == _largeVideoHwdec) return;
    _largeVideoHwdec = large;
    if (!config.enableHardwareAcceleration) unawaited(_applyHwdec());
  }

  /// Applies lightweight GPU scaling and larger demuxer cache for 4K/8K video
  /// so ANGLE/OpenGL does not choke on high-bitrate 60fps streams.
  Future<void> _applyLargeVideoRenderTuning(bool large) async {
    if (_player.platform case final mk.NativePlayer native) {
      try {
        if (!await _nativeReady(native) || _disposal != null) return;
        final props = large
            ? <String, String>{
                'scale': 'bilinear',
                'dscale': 'bilinear',
                'cscale': 'bilinear',
                'dither-depth': 'no',
                'correct-downscaling': 'no',
                'linear-downscaling': 'no',
                'sigmoid-upscaling': 'no',
                'framedrop': 'vo',
                'demuxer-max-bytes': '${160 * 1024 * 1024}',
                'demuxer-max-back-bytes': '${64 * 1024 * 1024}',
              }
            : <String, String>{
                'scale': 'spline36',
                'dscale': 'mitchell',
                'cscale': 'bilinear',
                'dither-depth': 'auto',
                'framedrop': 'vo',
              };
        for (final entry in props.entries) {
          if (_disposal != null) return;
          await native.setProperty(
            entry.key,
            entry.value,
            waitForInitialization: false,
          );
        }
      } catch (e) {
        if (_disposal == null) {
          debugPrint('Could not apply 4K/8K render tuning: $e');
        }
      }
    }
  }

  /// Recover a failing GPU decoder on the CPU without reopening the media.
  /// Only libmpv's decoder changes; no new D3D11 device or texture is made,
  /// which is what can take down the engine on a failing driver.
  void _onError(String error) {
    if (_softwareFallback || _hwdec == 'no') return;
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
    this.bufferSizeMb = 64,
  });
  final Duration networkCaching;
  final bool looping;

  /// Silent decoder that seeks to keyframes, for seek bar thumbnails.
  final bool framePreview;

  /// Demuxer cache size in megabytes for libmpv.
  final int bufferSizeMb;
}

class PlaybackMedia {
  const PlaybackMedia(this.uri);
  final String uri;
}

class PlaybackVideoConfiguration {
  const PlaybackVideoConfiguration({
    this.enableHardwareAcceleration = false,
    this.gpuDecodeLargeVideos = false,
    this.outputWidth,
    this.outputHeight,
  });
  final bool enableHardwareAcceleration;

  /// Keep software decoding, but use the GPU decoder for 4K and larger.
  final bool gpuDecodeLargeVideos;

  /// Optional fixed texture dimensions (e.g. small hover previews or viewport-
  /// capped 4K/8K output).
  final int? outputWidth;
  final int? outputHeight;

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
