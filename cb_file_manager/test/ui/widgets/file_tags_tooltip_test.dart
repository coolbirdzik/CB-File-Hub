import 'dart:async';

import 'package:cb_file_manager/ui/widgets/file_tags_tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host({
  String path = '/files/sample.txt',
  required Future<List<String>> Function(String) loadTags,
  VoidCallback? onTap,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: FileTagsTooltip(
        path: path,
        loadTags: loadTags,
        child: GestureDetector(
          onTap: onTap,
          child: const SizedBox(width: 160, height: 60, child: Text('file')),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('hover reads and displays every tag without blocking clicks', (
    tester,
  ) async {
    var reads = 0;
    var taps = 0;
    final tags = [
      'work',
      'Việt Nam',
      'a long tag that cannot fit in a compact file row',
      'four',
      'five',
      'six',
    ];
    await tester.pumpWidget(
      host(
        loadTags: (_) async {
          reads++;
          return tags;
        },
        onTap: () => taps++,
      ),
    );
    expect(reads, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('file')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    final message = 'sample.txt\n${tags.map((tag) => '#$tag').join('\n')}';
    expect(reads, 1);
    expect(find.text(message), findsOneWidget);
    await tester.tap(find.text('file'));
    expect(taps, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('late tags from the previous file cannot replace hovered tags', (
    tester,
  ) async {
    final first = Completer<List<String>>();
    final second = Completer<List<String>>();
    Future<List<String>> load(String path) =>
        path.endsWith('sample.txt') ? first.future : second.future;
    await tester.pumpWidget(host(loadTags: load));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('file')));
    await tester.pump();
    await tester.pumpWidget(host(path: '/files/next.txt', loadTags: load));
    second.complete(['current']);
    await tester.pump();
    first.complete(['stale']);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('next.txt\n#current'), findsOneWidget);
    expect(find.textContaining('#stale'), findsNothing);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
