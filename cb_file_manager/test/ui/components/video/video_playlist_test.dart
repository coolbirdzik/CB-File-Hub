import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/components/video/video_player/video_playlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as pathlib;

void main() {
  group('VideoPlaylist.fromFolder', () {
    late Directory dir;

    // name -> size in bytes
    const files = <String, int>{
      'b 10.mp4': 30,
      'B 2.mkv': 10,
      'a.MP4': 20,
      'notes.txt': 99,
      'cover.jpg': 5,
    };

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cb_playlist_test_');
      for (final entry in files.entries) {
        await File(
          pathlib.join(dir.path, entry.key),
        ).writeAsString('x' * entry.value);
      }
      await Directory(pathlib.join(dir.path, 'sub.mp4')).create();
    });

    tearDown(() => dir.delete(recursive: true));

    Future<List<String>> namesFor(SortOption option) async {
      final current = File(pathlib.join(dir.path, 'B 2.mkv'));
      final items = await VideoPlaylist.fromFolder(current, sortOption: option);
      return items.map((f) => pathlib.basename(f.path)).toList();
    }

    test('lists only sibling videos, by name like the folder view', () async {
      expect(await namesFor(SortOption.nameAsc), <String>[
        'a.MP4',
        'b 10.mp4',
        'B 2.mkv',
      ]);
      expect(await namesFor(SortOption.nameDesc), <String>[
        'B 2.mkv',
        'b 10.mp4',
        'a.MP4',
      ]);
    });

    test('follows a size sort', () async {
      expect(await namesFor(SortOption.sizeDesc), <String>[
        'b 10.mp4',
        'a.MP4',
        'B 2.mkv',
      ]);
    });

    test('falls back to the current file when the folder is missing', () async {
      final current = File(pathlib.join(dir.path, 'missing', 'x.mp4'));
      final items = await VideoPlaylist.fromFolder(
        current,
        sortOption: SortOption.nameAsc,
      );
      expect(items.single.path, current.path);
    });
  });

  group('showVideoPlaylistPanel', () {
    final items = <File>[
      File(pathlib.join('videos', 'one.mp4')),
      File(pathlib.join('videos', 'two.mp4')),
      File(pathlib.join('videos', 'three.mp4')),
    ];

    Future<List<File>> openPanel(WidgetTester tester) async {
      final selected = <File>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showVideoPlaylistPanel(
                    context: context,
                    items: items,
                    currentPath: items.first.path,
                    onSelected: selected.add,
                    thumbnailBuilder: (file, width, height) => SizedBox(
                      key: ValueKey<String>('thumb:${file.path}'),
                      width: width,
                      height: height,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      // The app delegate loads its strings asynchronously.
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlaylistPanel), findsOneWidget);
      for (final file in items) {
        expect(find.byKey(ValueKey<String>('thumb:${file.path}')), findsOne);
      }
      return selected;
    }

    testWidgets('tapping outside closes the panel without a selection', (
      tester,
    ) async {
      final selected = await openPanel(tester);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlaylistPanel), findsNothing);
      expect(selected, isEmpty);
    });

    testWidgets('picking an entry closes the panel and reports it', (
      tester,
    ) async {
      final selected = await openPanel(tester);

      await tester.tap(find.text('three.mp4'));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlaylistPanel), findsNothing);
      expect(selected.single.path, items.last.path);
    });

    testWidgets('picking the playing entry reports nothing', (tester) async {
      final selected = await openPanel(tester);

      await tester.tap(find.text('one.mp4'));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlaylistPanel), findsNothing);
      expect(selected, isEmpty);
    });
  });
}
