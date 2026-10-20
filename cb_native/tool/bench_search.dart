// Compares the native recursive search with a copy of the app's Dart walker
// (FileNavigationBloc._recursiveSearch + TextUtils.matchesSearch).
//
//   dart run tool/bench_search.dart <root> <query> [rounds]
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cb_native/cb_native.dart';
import 'package:diacritic/diacritic.dart';

final _combining = RegExp(
  r'[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]',
  unicode: true,
);

String _searchKey(String value) => removeDiacritics(value.toLowerCase())
    .replaceAll(_combining, '')
    .replaceAll(RegExp(r'[_\-\.\(\)\[\]\{\}]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

List<String> _words(String query) =>
    _searchKey(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

Future<void> _dartWalk(
  Directory dir,
  List<String> words,
  List<String> results,
) async {
  try {
    await for (final entity in dir.list(followLinks: false)) {
      try {
        final path = entity.path;
        final key = _searchKey(
          path.substring(path.lastIndexOf(Platform.pathSeparator) + 1),
        );
        if (words.every(key.contains)) results.add(entity.path);
        if (entity is Directory) await _dartWalk(entity, words, results);
      } catch (_) {}
    }
  } catch (_) {}
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    print('usage: dart run tool/bench_search.dart <root> <query> [rounds]');
    exit(64);
  }
  final root = args[0];
  final words = _words(args[1]);
  final rounds = args.length > 2 ? int.parse(args[2]) : 2;
  if (!CbNative.isAvailable) {
    print('native library unavailable');
    exit(1);
  }

  for (var round = 1; round <= rounds; round++) {
    final dartSw = Stopwatch()..start();
    final dartHits = <String>[];
    await _dartWalk(Directory(root), words, dartHits);
    dartSw.stop();

    final nativeSw = Stopwatch()..start();
    final hits = await NativeSearch.collect(
      NativeSearch.start(root: root, words: words)!,
      shouldContinue: () => true,
      pollInterval: const Duration(milliseconds: 5),
    );
    nativeSw.stop();

    final ratio = dartSw.elapsedMicroseconds / nativeSw.elapsedMicroseconds;
    print(
      'round $round: dart ${dartSw.elapsedMilliseconds}ms '
      '(${dartHits.length} hits)  native ${nativeSw.elapsedMilliseconds}ms '
      '(${hits!.length} hits)  x${ratio.toStringAsFixed(1)}',
    );
  }
}
