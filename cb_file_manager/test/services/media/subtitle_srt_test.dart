import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/files/file_attributes.dart';
import 'package:cb_file_manager/services/media/subtitle_cache.dart';
import 'package:cb_file_manager/services/media/subtitle_srt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as pathlib;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('formatSrt', () {
    test('writes numbered CRLF cues with SubRip timestamps', () {
      final srt = formatSrt([
        LocalSubtitleCue(3723004, 3725500, 'こんにちは', 'Xin chào'),
        LocalSubtitleCue(0, 1500, 'Hi', 'Chào'),
      ], bilingual: false);
      expect(
        srt,
        '1\r\n00:00:00,000 --> 00:00:01,500\r\nChào\r\n\r\n'
        '2\r\n01:02:03,004 --> 01:02:05,500\r\nXin chào\r\n\r\n',
      );
    });

    test('removes overlap left by chunks on both sides of a seek', () {
      final srt = formatSrt([
        LocalSubtitleCue(49200, 52000, 'b', 'second'),
        LocalSubtitleCue(44000, 50000, 'a', 'first'),
        LocalSubtitleCue(49500, 49900, 'c', 'contained'),
      ], bilingual: false);
      expect(srt, contains('00:00:44,000 --> 00:00:50,000\r\nfirst'));
      expect(srt, contains('00:00:50,000 --> 00:00:52,000\r\nsecond'));
      expect(srt, isNot(contains('contained')));
    });

    test('bilingual cues keep the original above and drop blank lines', () {
      final srt = formatSrt([
        LocalSubtitleCue(0, 1000, 'Hello\n\nthere', 'Xin chào'),
        LocalSubtitleCue(1000, 2000, 'Same', 'Same'),
        LocalSubtitleCue(2000, 3000, '', '   '),
      ], bilingual: true);
      expect(srt, contains('Hello\r\nthere\r\nXin chào\r\n\r\n'));
      expect(
        srt,
        contains('2\r\n00:00:01,000 --> 00:00:02,000\r\nSame\r\n\r\n'),
      );
      expect(srt, isNot(contains('3\r\n')));
    });

    test('bytes start with a UTF-8 byte order mark', () {
      final bytes = srtBytes('1\r\n');
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), '1\r\n');
    });
  });

  test('sidecar names and local sources', () {
    expect(
      subtitleSrtFileName(pathlib.join('a', 'Phim hay.2024.mkv'), 'vi'),
      'Phim hay.2024.vi.srt',
    );
    expect(subtitleSrtFileName('movie.mp4', 'zh-Hant'), 'movie.zh-Hant.srt');
    expect(subtitleLocalVideoPath('http://127.0.0.1:8080/x.mkv'), isNull);
    expect(subtitleLocalVideoPath(null), isNull);
    final local = pathlib.join(Directory.systemTemp.path, 'x.mkv');
    expect(subtitleLocalVideoPath(local), local);
  });

  group('SubtitleSrtWriter', () {
    late Directory folder;
    late String video;
    late SharedPreferences prefs;
    final hiddenCalls = <(String, bool)>[];
    setUp(() async {
      folder = await Directory.systemTemp.createTemp('srt-writer-');
      video = pathlib.join(folder.path, 'movie.mkv');
      await File(video).writeAsBytes([1, 2, 3]);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      hiddenCalls.clear();
    });
    tearDown(() => folder.delete(recursive: true));

    SubtitleSrtWriter writer() => SubtitleSrtWriter(
      prefs,
      setHidden: (path, hidden) async => hiddenCalls.add((path, hidden)),
    );

    test('Subs mode writes into Subs/ and leaves the video alone', () async {
      final videoStat = await File(video).stat();
      final result = await writer().write(
        videoPath: video,
        language: 'vi',
        mode: SubtitleFileMode.subsFolder,
        bytes: srtBytes('1\r\n'),
      );
      expect(result.path, pathlib.join(folder.path, 'Subs', 'movie.vi.srt'));
      expect(result.changed, isTrue);
      expect(await File(result.path).readAsBytes(), srtBytes('1\r\n'));
      expect(await File(video).readAsBytes(), [1, 2, 3]);
      expect((await File(video).stat()).modified, videoStat.modified);
      expect(hiddenCalls, isEmpty);
      final leftovers = await Directory(
        pathlib.join(folder.path, 'Subs'),
      ).list().map((e) => pathlib.basename(e.path)).toList();
      expect(leftovers, ['movie.vi.srt']);
    });

    test('a foreign subtitle file is never replaced', () async {
      final mine = pathlib.join(folder.path, 'movie.vi.srt');
      await File(mine).writeAsString('user subtitles');
      final result = await writer().write(
        videoPath: video,
        language: 'vi',
        mode: SubtitleFileMode.besideHidden,
        bytes: srtBytes('ai'),
      );
      expect(result.path, pathlib.join(folder.path, 'movie.vi.ai.srt'));
      expect(await File(mine).readAsString(), 'user subtitles');
      expect(hiddenCalls.last, (result.path, true));
    });

    test(
      'own files are rewritten, identical content is left untouched',
      () async {
        final first = await writer().write(
          videoPath: video,
          language: 'vi',
          mode: SubtitleFileMode.besideHidden,
          bytes: srtBytes('one'),
        );
        expect(first.path, pathlib.join(folder.path, 'movie.vi.srt'));
        final same = await writer().write(
          videoPath: video,
          language: 'vi',
          mode: SubtitleFileMode.besideHidden,
          bytes: srtBytes('one'),
        );
        expect(same.changed, isFalse);
        hiddenCalls.clear();
        final next = await writer().write(
          videoPath: video,
          language: 'vi',
          mode: SubtitleFileMode.besideHidden,
          bytes: srtBytes('two'),
        );
        expect(next.path, first.path);
        expect(next.changed, isTrue);
        expect(await File(next.path).readAsBytes(), srtBytes('two'));
        // The old file is unhidden before replacement, then hidden again.
        expect(hiddenCalls, [(first.path, false), (first.path, true)]);
      },
    );

    test(
      'the hidden sidecar really carries the Windows hidden attribute',
      () async {
        final written = await SubtitleSrtWriter(prefs).write(
          videoPath: video,
          language: 'vi',
          mode: SubtitleFileMode.besideHidden,
          bytes: srtBytes('one'),
        );
        expect(FileAttributes.describe(written.path, null), contains('H'));
        FileAttributes.invalidate(written.path);
        // Replacing a hidden file must still work.
        final again = await SubtitleSrtWriter(prefs).write(
          videoPath: video,
          language: 'vi',
          mode: SubtitleFileMode.besideHidden,
          bytes: srtBytes('two'),
        );
        expect(await File(again.path).readAsBytes(), srtBytes('two'));
        expect(FileAttributes.describe(again.path, null), contains('H'));
        FileAttributes.invalidate(again.path);
      },
      skip: Platform.isWindows ? false : 'Windows hidden attribute',
    );

    test('hidden mode is not offered where no hidden attribute exists', () {
      expect(
        SubtitleFileMode.available.contains(SubtitleFileMode.besideHidden),
        Platform.isWindows || Platform.isMacOS,
      );
    });
  });
}
