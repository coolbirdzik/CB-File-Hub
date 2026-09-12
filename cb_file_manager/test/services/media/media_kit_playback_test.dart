import 'dart:io';
import 'package:cb_file_manager/services/media/media_kit_playback.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

class DelayedPlayer extends mk.PlatformPlayer {
  DelayedPlayer() : super(configuration: const mk.PlayerConfiguration());
  final commands = <String>[];
  void loadMetadata(Duration duration) {
    state = state.copyWith(duration: duration);
    durationController.add(duration);
  }

  @override
  Future<void> play() async => commands.add('play');
  @override
  Future<void> pause() async => commands.add('pause');
  @override
  Future<void> seek(Duration position) async =>
      commands.add('seek:${position.inSeconds}');
}

void main() {
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
}
