import 'dart:math';
import 'package:cb_file_manager/services/app_insights/app_storage_analyzer.dart';
import 'package:cb_file_manager/services/app_insights/path_root_size_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('drive, UNC and sibling boundaries stay distinct', () {
    final index = PathRootSizeIndex([
      (r'C:\APPS\ALPHA', 100),
      (r'C:\APPS\ALPHA\CACHE', 30),
      (r'C:\APPS\ALPHABET', 200),
      (r'\\SERVER\SHARE\APP', 400),
    ]);
    expect(index.coveredBytes(r'C:\APPS'), 300);
    expect(index.coveredBytes(r'C:\APPS\ALPHA', descendantsOnly: true), 30);
    expect(index.coveredBytes(r'C:\'), 300);
    expect(index.hasAncestor(r'C:\APPS\ALPHABET\CACHE'), isTrue);
    expect(index.hasAncestor(r'C:\APPS\ALPHABETICAL'), isFalse);
    expect(index.coveredBytes(r'\\SERVER\SHARE'), 400);
    expect(index.coveredBytes(r'\\SERVER\SHARE2'), 0);
    expect(index.hasAncestor(r'SERVER\SHARE\APP'), isFalse);
  });

  test('prefix totals equal reference pairwise exclusion for nested roots', () {
    final random = Random(43);
    final paths = <String>{r'C:\', r'\\SERVER\SHARE'};
    for (var i = 0; i < 300; i++) {
      final base = i.isEven ? 'C:' : r'\\SERVER\SHARE';
      paths.add(
        '$base\\${List.generate(1 + random.nextInt(5), (_) => random.nextInt(8)).join(r'\')}',
      );
    }
    final roots = [for (final path in paths) (path, random.nextInt(10000))]
      ..shuffle(random);
    final index = PathRootSizeIndex(roots);
    for (final query in {...paths, r'C:\MISSING', r'C:\1-SIBLING'}) {
      for (final descendantsOnly in [true, false]) {
        final matches = roots
            .where(
              (r) =>
                  (!descendantsOnly || r.$1 != query) &&
                  AppStorageAnalyzer.isSameOrDescendant(r.$1, query),
            )
            .toList();
        final expected = matches
            .where(
              (r) => !matches.any(
                (other) =>
                    other.$1 != r.$1 &&
                    AppStorageAnalyzer.isSameOrDescendant(r.$1, other.$1),
              ),
            )
            .fold(0, (sum, r) => sum + r.$2);
        expect(
          index.coveredBytes(query, descendantsOnly: descendantsOnly),
          expected,
          reason: '$query, descendantsOnly=$descendantsOnly',
        );
      }
      expect(
        index.hasAncestor(query),
        roots.any((r) => AppStorageAnalyzer.isSameOrDescendant(query, r.$1)),
      );
    }
  });
}
