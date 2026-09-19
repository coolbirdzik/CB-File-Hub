import 'dart:io';

import 'package:cb_file_manager/ui/screens/folder_list/components/file_grid_item.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/thumbnail_only.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('selecting a grid tile keeps its thumbnail mounted', (
    tester,
  ) async {
    final file = File('/tmp/sample.txt');

    Future<void> pumpTile({required bool isSelected}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180,
                height: 180,
                child: FileGridItem(
                  file: file,
                  isSelected: isSelected,
                  isDesktopMode: true,
                  showFileTags: false,
                  toggleFileSelection:
                      (path, {shiftSelect = false, ctrlSelect = false}) {},
                  toggleSelectionMode: () {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    await pumpTile(isSelected: false);
    final thumbnail = find.byType(ThumbnailOnly);
    final State initial = tester.state(thumbnail);

    // A remount would make a video thumbnail re-read its cache
    // asynchronously and blink for a frame.
    await pumpTile(isSelected: true);
    expect(tester.state(thumbnail), same(initial));
    await pumpTile(isSelected: false);
    expect(tester.state(thumbnail), same(initial));
  });

  testWidgets('double-clicking a grid filename opens the file', (tester) async {
    final file = File('/tmp/sample.txt');
    final openedFiles = <File>[];
    final openedAsVideo = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: FileGridItem(
                file: file,
                isSelected: false,
                isDesktopMode: true,
                showFileTags: false,
                toggleFileSelection:
                    (path, {shiftSelect = false, ctrlSelect = false}) {},
                toggleSelectionMode: () {},
                onFileTap: (openedFile, isVideo) {
                  openedFiles.add(openedFile);
                  openedAsVideo.add(isVideo);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final filename = find.text('sample.txt');
    expect(filename, findsOneWidget);

    await tester.tap(filename);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(filename);
    await tester.pump();

    expect(openedFiles, <File>[file]);
    expect(openedAsVideo, <bool>[false]);
  });
}
