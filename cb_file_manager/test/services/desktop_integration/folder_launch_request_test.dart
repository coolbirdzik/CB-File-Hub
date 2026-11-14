import 'dart:io';

import 'package:cb_file_manager/services/desktop_integration/folder_launch_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('folder-launch-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'folder requests carry a Unicode filename through tab serialization',
    () async {
      const name = 'đêm_2.mkv';
      final request = await FolderLaunchRequest.takeArguments(
        ['--open-folder', root.uri.toString()],
        highlightedFiles: {root.path: name},
      );
      expect(request.rejected, isEmpty);
      expect(request.tabs.single.toJson()['highlightedFileName'], name);
    },
  );

  test('highlight accepts filenames only, never paths or traversal', () async {
    for (final name in [
      '',
      '.',
      '..',
      '../outside.mkv',
      r'..\outside.mkv',
      'bad\u0000.mkv',
    ]) {
      final request = await FolderLaunchRequest.takeArguments(
        ['--open-folder', root.path],
        highlightedFiles: {root.path: name},
      );
      expect(request.tabs, isEmpty, reason: name);
      expect(request.rejected, [root.path]);
    }
  });

  test(
    'opens multiple Unicode/spaced folders and deduplicates URI/path pairs',
    () async {
      final first = await Directory(
        p.join(root.path, 'Ảnh riêng 100%'),
      ).create();
      final second = await Directory(
        p.join(root.path, 'other folder'),
      ).create();
      final arguments = [
        first.path,
        first.uri.toString(),
        second.path,
        'movie.mp4',
      ];
      final request = await FolderLaunchRequest.takeArguments(arguments);
      expect(request.tabs.map((tab) => tab.path), [first.path, second.path]);
      expect(request.tabs.map((tab) => tab.name), [
        'Ảnh riêng 100%',
        'other folder',
      ]);
      expect(arguments, ['movie.mp4']);
      expect(request.rejected, isEmpty);
    },
  );

  test(
    'explicit requests reject files, missing paths, relative paths and schemes',
    () async {
      final file = await File(p.join(root.path, 'file.txt')).writeAsString('x');
      final bad = [
        file.path,
        p.join(root.path, 'missing'),
        'relative',
        'smb://host/share',
      ];
      final arguments = ['--open-folder', ...bad];
      final request = await FolderLaunchRequest.takeArguments(arguments);
      expect(request.tabs, isEmpty);
      expect(request.rejected, bad);
      expect(arguments, isEmpty);
    },
  );

  test('Win+E no-path request opens Home', () async {
    final request = await FolderLaunchRequest.takeArguments(['--open-folder']);
    expect(request.requested, isTrue);
    expect(request.tabs.single.path, '#home');
  });

  test('does not URL-decode percent signs in raw paths', () async {
    final folder = await Directory(p.join(root.path, 'a%20b')).create();
    expect(FolderLaunchRequest.normalizeLocation(folder.path), folder.path);
    final request = await FolderLaunchRequest.takeArguments([
      folder.uri.toString(),
    ]);
    expect(request.tabs.single.path, folder.path);
  });

  test('Windows Shell suffix handles roots and trailing slashes', () async {
    if (!Platform.isWindows) return;
    final path = p.rootPrefix(root.path);
    final request = await FolderLaunchRequest.takeArguments([
      '--open-folder',
      '$path\\.',
    ]);
    expect(request.tabs.single.path, p.normalize(path));
  });

  test('malformed file URIs never become paths', () {
    expect(
      FolderLaunchRequest.normalizeLocation('file:///tmp/a?query=1'),
      isNull,
    );
    expect(
      FolderLaunchRequest.normalizeLocation('file:///tmp/a#fragment'),
      isNull,
    );
    expect(
      FolderLaunchRequest.normalizeLocation('https://example.com/folder'),
      isNull,
    );
  });
}
