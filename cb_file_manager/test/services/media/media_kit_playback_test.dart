import 'dart:async';
import 'dart:io';
import 'package:cb_file_manager/services/media/media_kit_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

class DelayedPlayer extends mk.PlatformPlayer {
  DelayedPlayer() : super(configuration: const mk.PlayerConfiguration());
  final commands = <String>[];
  Completer<void>? seekGate;
  Completer<void>? disposeGate;
  final disposeStarted = Completer<void>();

  @override
  Future<void> dispose() async {
    disposeStarted.complete();
    await disposeGate?.future;
    await super.dispose();
  }

  void loadMetadata(Duration duration) {
    state = state.copyWith(duration: duration);
    durationController.add(duration);
  }

  @override
  Future<void> play() async {
    // NativePlayer.play restarts at zero if seek did not clear completed.
    if (state.completed) commands.add('restart:0');
    commands.add('play');
  }

  @override
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> seek(Duration position) async {
    commands.add('seek:${position.inSeconds}');
    await seekGate?.future;
    state = state.copyWith(completed: false);
  }
}

void main() {
  test('engine teardown waits for a player already being disposed', () async {
    final native = DelayedPlayer()..disposeGate = Completer<void>();
    final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
    final disposing = player.dispose();
    await native.disposeStarted.future;
    var released = false;
    final closing = PlaybackPlayer.disposeAll().then((_) => released = true);
    await Future<void>.delayed(Duration.zero);
    try {
      expect(released, isFalse);
    } finally {
      native.disposeGate!.complete();
      await disposing;
      await closing;
    }
    expect(released, isTrue);
  });

  test('seeking back from EOF resumes requested playback', () async {
    final native = DelayedPlayer();
    final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
    addTearDown(player.dispose);
    native.loadMetadata(const Duration(seconds: 30));
    await player.play();
    native.state = native.state.copyWith(completed: true, playing: false);
    await player.seek(const Duration(seconds: 22));
    expect(native.commands, ['play', 'seek:22', 'play']);
    expect(player.state.completed, isFalse);
    expect(player.playRequested, isTrue);
  });

  test('seeking while explicitly paused does not start playback', () async {
    final native = DelayedPlayer();
    final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
    addTearDown(player.dispose);
    native.loadMetadata(const Duration(seconds: 30));
    await player.play();
    await player.pause();
    await player.seek(const Duration(seconds: 5), exact: false);
    expect(native.commands, ['play', 'pause', 'seek:5']);
    expect(player.playRequested, isFalse);
  });

  test(
    'an explicit pause while seeking takes precedence over resume',
    () async {
      final native = DelayedPlayer();
      final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
      addTearDown(player.dispose);
      native.loadMetadata(const Duration(seconds: 30));
      await player.play();
      native.seekGate = Completer<void>();
      final seeking = player.seek(const Duration(seconds: 5));
      await player.pause();
      native.seekGate!.complete();
      await seeking;
      expect(native.commands, ['play', 'seek:5', 'pause']);
      expect(player.playRequested, isFalse);
    },
  );

  test('seek completion after disposal cannot restart playback', () async {
    final native = DelayedPlayer();
    final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
    native.loadMetadata(const Duration(seconds: 30));
    await player.play();
    native.seekGate = Completer<void>();
    final seeking = player.seek(const Duration(seconds: 5));
    await player.dispose();
    native.seekGate!.complete();
    await seeking;
    expect(native.commands, ['play', 'seek:5']);
  });

  test(
    'resume intent survives a second drag before native acknowledgement',
    () async {
      final native = DelayedPlayer();
      final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
      addTearDown(player.dispose);
      await player.play();
      final resumeFirstDrag = player.playRequested;
      await player.pause();
      expect(resumeFirstDrag, isTrue);
      await player.play();
      expect(player.state.playing, isFalse);
      final resumeSecondDrag = player.playRequested;
      await player.pause();
      expect(resumeSecondDrag, isTrue);
      await player.play();
      expect(player.playRequested, isTrue);
      expect(native.commands, ['play', 'pause', 'play', 'pause', 'play']);
    },
  );

  test('toggle honors explicit intent before native acknowledgement', () async {
    final native = DelayedPlayer();
    final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
    addTearDown(player.dispose);
    await player.play();
    await player.playOrPause();
    expect(player.playRequested, isFalse);
    await player.playOrPause();
    expect(player.playRequested, isTrue);
    expect(native.commands, ['play', 'pause', 'play']);
  });

  test(
    'startup seeks wait for metadata and keep the latest requested position',
    () async {
      final native = DelayedPlayer();
      final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
      addTearDown(player.dispose);
      await player.seek(const Duration(seconds: 2));
      await player.seek(const Duration(seconds: 5));
      expect(native.commands, isEmpty);
      native.loadMetadata(const Duration(seconds: 30));
      await Future<void>.delayed(Duration.zero);
      expect(native.commands, ['seek:5']);
    },
  );

  test('decoder choice maps to the playback configuration', () {
    final hardware = PlaybackVideoConfiguration.forDecoder('hardware');
    expect(hardware.enableHardwareAcceleration, isTrue);
    final software = PlaybackVideoConfiguration.forDecoder('software');
    expect(software.enableHardwareAcceleration, isFalse);
    expect(software.gpuDecodeLargeVideos, isFalse);
    // Legacy or missing values behave as auto.
    for (final mode in [null, 'auto', 'unknown']) {
      final auto = PlaybackVideoConfiguration.forDecoder(mode);
      expect(auto.enableHardwareAcceleration, !Platform.isWindows);
      expect(auto.gpuDecodeLargeVideos, Platform.isWindows);
    }
  });

  test('GPU decoder failures are recognised, other errors are not', () {
    expect(
      PlaybackPlayer.isHardwareDecodeError('Failed to create D3D11 Device'),
      isTrue,
    );
    expect(PlaybackPlayer.isHardwareDecodeError('error 0x8007000E'), isTrue);
    expect(PlaybackPlayer.isHardwareDecodeError('No such file'), isFalse);
  });

  test('a corrupt audio packet is recoverable, a missing file is not', () {
    expect(
      PlaybackPlayer.isRecoverableAudioDecodeError('Error decoding audio.'),
      isTrue,
    );
    expect(
      PlaybackPlayer.isRecoverableAudioDecodeError('No such file'),
      isFalse,
    );
    expect(
      PlaybackPlayer.isRecoverableAudioDecodeError('Error decoding video.'),
      isFalse,
    );
  });

  test('keyframe seeks fall back to a regular seek off libmpv', () async {
    final native = DelayedPlayer();
    final player = PlaybackPlayer(player: mk.Player(platformPlayer: native));
    addTearDown(player.dispose);
    native.loadMetadata(const Duration(seconds: 30));
    await player.seek(const Duration(seconds: 7), exact: false);
    expect(native.commands, ['seek:7']);
  });

  test('SMB escaping and authentication reach the source resolver intact', () {
    const url =
        'smb://DOMAIN%3Buser:p%40ss%3Aword%23%25@nas/share/My%20video%23.mp4';
    final source = playbackSourceUri(url);
    expect(source.toString(), url);
    expect(Uri.decodeComponent(source.userInfo), 'DOMAIN;user:p@ss:word#%');
    expect(source.pathSegments.last, 'My video#.mp4');
  });

  test('UNC and Windows paths preserve literal spaces and percent signs', () {
    for (final path in [
      r'\\server\share\Tiếng Việt #100%.mp4',
      r'L:\Video\a #100%.mp4',
    ]) {
      final source = playbackSourceUri(path);
      expect(source.scheme, 'file');
      expect(source.toFilePath(windows: true), path);
    }
  });

  test('HTTP URLs retain their query and fragment', () {
    const url = 'https://host/video.mp4?token=a%2Bb#track';
    expect(playbackSourceUri(url).toString(), url);
  });

  test('media_kit keeps the UNC host when opening a named file URL', () {
    const url = 'file://nas/share/My%20video%23%25.mp4';
    final media = mk.Media(playbackMediaSource(url));
    expect(media.uri.replaceAll('/', r'\'), r'\\nas\share\My video#%.mp4');
  }, skip: !Platform.isWindows);

  test('computeCappedOutputSize downscales 8K video to viewport size', () {
    final capped = PlaybackPlayer.computeCappedOutputSize(
      videoWidth: 7680,
      videoHeight: 3840,
      viewportWidth: 1280,
      viewportHeight: 720,
      devicePixelRatio: 1.5,
    );
    expect(capped, isNotNull);
    expect(capped!.width, 1920);
    expect(capped.height, 960);
    expect(capped.width.isEven, isTrue);
    expect(capped.height.isEven, isTrue);
  });

  test('computeCappedOutputSize does not upscale smaller videos', () {
    final uncapped = PlaybackPlayer.computeCappedOutputSize(
      videoWidth: 1920,
      videoHeight: 1080,
      viewportWidth: 2560,
      viewportHeight: 1440,
      devicePixelRatio: 1.0,
    );
    expect(uncapped, isNull);
  });

  test('computeCappedOutputSize uses viewport aspect when VR is active', () {
    final vrOutput = PlaybackPlayer.computeCappedOutputSize(
      videoWidth: 8192,
      videoHeight: 4096,
      viewportWidth: 1920,
      viewportHeight: 1080,
      devicePixelRatio: 1.0,
      forceViewportSize: true,
    );
    expect(vrOutput, (width: 1920, height: 1080));
  });

  test('isLikelyLargeVideoSource detects 4K and 8K filenames', () {
    expect(
      PlaybackPlayer.isLikelyLargeVideoSource(
        r'P:\Reco\SAVR-1165_8K\489155.com@SAVR-1165_1_8K.mp4',
      ),
      isTrue,
    );
    expect(
      PlaybackPlayer.isLikelyLargeVideoSource('demo_4K_60fps.mkv'),
      isTrue,
    );
    expect(PlaybackPlayer.isLikelyLargeVideoSource('clip_1080p.mp4'), isFalse);
  });

  test('isLikelyLargeVideoSource detects 4K and 8K filenames', () {
    expect(
      PlaybackPlayer.isLikelyLargeVideoSource(
        r'P:\Reco\SAVR-1165_8K\489155.com@SAVR-1165_1_8K.mp4',
      ),
      isTrue,
    );
    expect(PlaybackPlayer.isLikelyLargeVideoSource('demo_4K_60fps.mkv'), isTrue);
    expect(PlaybackPlayer.isLikelyLargeVideoSource('clip_1080p.mp4'), isFalse);
  });
}
