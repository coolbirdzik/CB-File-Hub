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
  }

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

  mk.Player get controller => _player;
  mk.PlayerState get state => _player.state;
  mk.PlayerStream get stream => _player.stream;

  /// Playback intent stays synchronous while native state events catch up.
  bool get playRequested => _playRequested;

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
      await native.setProperty(
        'cache-secs',
        (configuration.networkCaching.inMilliseconds / 1000).toString(),
      );
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
  Future<void> seek(Duration position) async {
    // open() returns before mpv has loaded metadata. A restore seek issued
    // immediately afterwards would otherwise be discarded by the decoder.
    if (state.duration == Duration.zero) {
      _pendingSeek = position;
      return;
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
    await _player.dispose();
    if (_proxyUrl case final url?) SmbHttpProxyServer.instance.release(url);
  }

  video.VideoController _configureVideo(PlaybackVideoConfiguration config) {
    if (_videoController == null) {
      _videoController = video.VideoController(
        _player,
        configuration: video.VideoControllerConfiguration(
          enableHardwareAcceleration: config.enableHardwareAcceleration,
          hwdec: config.enableHardwareAcceleration ? 'auto-safe' : 'no',
        ),
      );
    } else if (_player.platform case final mk.NativePlayer native) {
      // Reuse the texture and decoder session when changing preferences.
      unawaited(() async {
        await _videoController!.platform.future;
        if (_disposal == null) {
          await native.setProperty(
            'hwdec',
            config.enableHardwareAcceleration ? 'auto-safe' : 'no',
          );
        }
      }());
    }
    return _videoController!;
  }
}

class PlaybackConfiguration {
  const PlaybackConfiguration({
    this.networkCaching = const Duration(seconds: 1),
    this.looping = false,
  });
  final Duration networkCaching;
  final bool looping;
}

class PlaybackMedia {
  const PlaybackMedia(this.uri);
  final String uri;
}

class PlaybackVideoConfiguration {
  const PlaybackVideoConfiguration({this.enableHardwareAcceleration = false});
  final bool enableHardwareAcceleration;
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
