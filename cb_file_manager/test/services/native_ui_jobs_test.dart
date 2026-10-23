import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cb_file_manager/helpers/core/batch_file_probe.dart';
import 'package:cb_file_manager/helpers/core/path_directory_suggestions.dart';
import 'package:cb_file_manager/services/album_auto_rule_service.dart';
import 'package:cb_file_manager/services/smart_album_scanner.dart';
import 'package:cb_file_manager/services/thumbnail_cache_cleaner.dart';
import 'package:cb_file_manager/ui/utils/preview_syntax_highlighter.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class RemoteFile extends Fake implements File {
  RemoteFile(this.path);
  @override
  final String path;
  @override
  Future<bool> exists() async => true;
}

void main() {
  final nativeSkip = CbNative.isAvailable ? null : 'Rust library not built';
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('cb_ui_jobs_'),
  );
  tearDown(() => root.delete(recursive: true));

  Future<File> makeFile(String name, {int size = 4, int age = 0}) async {
    final file = File(p.normalize(p.join(root.path, name)));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List.filled(size, 42));
    await file.setLastModified(
      DateTime(2025, 1, 10).subtract(Duration(days: age)),
    );
    return file;
  }

  test(
    'native prefix suggestions filter before limiting and count direct children',
    () async {
      await Directory(p.join(root.path, 'Alpha')).create();
      await Directory(p.join(root.path, 'Another')).create();
      await Directory(p.join(root.path, 'Beta')).create();
      await makeFile('Apple.txt');
      await makeFile('Beta/nested/deep.txt');
      final matches = await NativeUiJobs.suggestDirectories(
        root.path,
        'a',
        limit: 8,
        caseInsensitive: true,
      );
      expect(matches, isNotNull);
      expect(matches!.map(p.basename), unorderedEquals(['Alpha', 'Another']));
      expect(
        await NativeUiJobs.suggestDirectories(
          root.path,
          'a',
          limit: 8,
          caseInsensitive: false,
        ),
        isEmpty,
      );
      expect(
        (await NativeUiJobs.suggestDirectories(
          root.path,
          '',
          limit: 1,
          caseInsensitive: true,
        ))!.length,
        1,
      );
      expect(
        await NativeUiJobs.countChildren([
          root.path,
          p.join(root.path, 'Beta'),
          p.join(root.path, 'absent'),
        ]),
        [4, 1, null],
      );
    },
    skip: nativeSkip,
  );

  for (final native in [true, false]) {
    test(
      'path suggestions only return matching directories, native=$native',
      () async {
        await Directory(p.join(root.path, 'Ảnh đẹp')).create();
        await makeFile('Ảnh file.jpg');
        final result = await suggestPathDirectories(
          p.join(root.path, 'Ảnh'),
          useNative: native,
        );
        expect(result.map(p.basename), ['Ảnh đẹp']);
        expect(
          await suggestPathDirectories(
            p.join(root.path, 'missing', ''),
            useNative: native,
          ),
          isEmpty,
        );
        expect(
          await suggestPathDirectories(root.path, limit: 0, useNative: native),
          isEmpty,
        );
      },
    );

    test(
      'cache expiry/count/byte budgets preserve newer files, native=$native',
      () async {
        final oldest = await makeFile('old.jpg', size: 5, age: 8);
        final middle = await makeFile('middle.jpg', size: 6, age: 2);
        final newest = await makeFile('new.jpg', size: 7);
        await makeFile('nested/keep.jpg', age: 20);
        final plan = await ThumbnailCacheCleaner.plan(
          root.path,
          cutoff: DateTime(2025, 1, 5),
          maxCount: 2,
          maxBytes: 8,
          useNative: native,
        );
        expect(plan.map((e) => e.path), [oldest.path, middle.path]);
        await middle.writeAsString('replacement thumbnail with different size');
        expect(await ThumbnailCacheCleaner.apply(root.path, plan), 1);
        expect(await oldest.exists(), isFalse);
        expect(await middle.exists(), isTrue);
        expect(await newest.exists(), isTrue);
        expect(
          await File(p.join(root.path, 'nested', 'keep.jpg')).exists(),
          isTrue,
        );
      },
    );

    test(
      'smart album rules and Unicode match the original rule API, native=$native',
      () async {
        final files = [
          await makeFile('ẢNH summer.jpg'),
          await makeFile('nested/holiday-end.MP4'),
          await makeFile('exact.png'),
          await makeFile('unmatched.gif'),
          await makeFile('ẢNH summer.txt'),
        ];
        for (final (condition, pattern) in [
          (RuleCondition.contains, 'ảnh'),
          (RuleCondition.startsWith, 'ẢNH'),
          (RuleCondition.endsWith, 'END'),
          (RuleCondition.equals, 'EXACT'),
          (RuleCondition.regex, r'(?=holiday)holiday'),
          (RuleCondition.regex, r'^\w+$'),
          (RuleCondition.regex, r'['),
        ]) {
          final rule = AlbumAutoRule(
            id: 'test',
            name: 'rule',
            albumId: 1,
            albumName: 'album',
            condition: condition,
            pattern: pattern,
            createdAt: DateTime(2025),
          );
          final actual = <String>[];
          await SmartAlbumScanner.scan(
            roots: [root.path],
            rules: [rule],
            onBatch: actual.addAll,
            shouldContinue: () => true,
            useNative: native,
          );
          final expected = files
              .take(4)
              .where((f) => rule.matches(p.basename(f.path)))
              .map((f) => f.path);
          expect(
            actual,
            unorderedEquals(expected),
            reason: '$condition $pattern',
          );
        }
      },
    );

    test(
      'smart album cancellation suppresses later batches, native=$native',
      () async {
        for (var i = 0; i < 100; i++) {
          await makeFile('dir$i/photo.jpg');
        }
        var keepGoing = true;
        var batches = 0;
        await SmartAlbumScanner.scan(
          roots: [root.path],
          rules: [],
          onBatch: (_) {
            batches++;
            keepGoing = false;
          },
          shouldContinue: () => keepGoing,
          useNative: native,
        ).timeout(const Duration(seconds: 5));
        expect(batches, 1);
        await SmartAlbumScanner.scan(
          roots: [root.path],
          rules: [],
          onBatch: (_) => fail('cancelled scan emitted results'),
          shouldContinue: () => false,
          useNative: native,
        );
      },
    );

    test('batch existence preserves duplicate order, native=$native', () async {
      final file = await makeFile('file.txt');
      expect(
        await probeFiles([
          file.path,
          p.join(root.path, 'absent'),
          root.path,
          file.path,
        ], useNative: native),
        [true, false, false, true],
      );
    });

    test(
      'async syntax ranges preserve UTF16 source and work across themes, native=$native',
      () async {
        const source =
            '/* first\nsecond 😀 */\nfn main() { let text = "Ảnh 😀"; }\n';
        final future = PreviewSyntaxHighlighter.tokenize(
          source,
          'main.rs',
          useNative: native,
        );
        expect(
          identical(
            future,
            PreviewSyntaxHighlighter.tokenize(
              source,
              'another.rs',
              useNative: native,
            ),
          ),
          isTrue,
        );
        final tokens = await future;
        var offset = 0;
        for (final token in tokens) {
          expect(token.start, offset);
          expect(token.length, greaterThan(0));
          offset += token.length;
        }
        expect(offset, source.length);
        expect(tokens.any((t) => t.className == 'comment'), isTrue);
        expect(tokens.any((t) => t.className == 'string'), isTrue);
        for (final brightness in Brightness.values) {
          final span = PreviewSyntaxHighlighter.buildHighlightedSpan(
            source: source,
            filePath: 'main.rs',
            baseStyle: const TextStyle(),
            brightness: brightness,
            tokens: tokens,
          );
          expect(span.toPlainText(), source);
        }
      },
    );
  }

  test(
    'cache apply rejects a planned entry outside the owned directory',
    () async {
      final outside = await makeFile('outside.jpg');
      final owned = await Directory(p.join(root.path, 'owned')).create();
      final stat = await outside.stat();
      expect(
        await ThumbnailCacheCleaner.apply(owned.path, [
          NativeCacheEntry(
            outside.path,
            stat.size,
            stat.modified.millisecondsSinceEpoch,
          ),
        ]),
        0,
      );
      expect(await outside.exists(), isTrue);
    },
  );

  test('global tags retain remote File adapters and local order', () async {
    final local = await makeFile('local.txt');
    final remote = RemoteFile('ftp://host/media.jpg');
    final result = await existingTaggedFiles([
      local,
      File(p.join(root.path, 'missing')),
      remote,
      local,
      root,
    ]);
    expect(result, [local, remote, local]);
  });

  test(
    'native cache and smart album jobs return real native results',
    () async {
      final file = await makeFile('photo.jpg', age: 10);
      final plan = await NativeUiJobs.cachePlan(
        root.path,
        cutoffMs: DateTime(2025, 1, 5).millisecondsSinceEpoch,
        maxCount: 20,
        maxBytes: 1000,
      );
      expect(plan, isNotNull);
      expect(plan!.single.path, file.path);
      final matches = <String>[];
      expect(
        await NativeUiJobs.scanSmartAlbum(
          roots: [root.path],
          extensions: ['.jpg'],
          rules: [(0, 'PHOTO')],
          onBatch: matches.addAll,
          shouldContinue: () => true,
        ),
        isTrue,
      );
      expect(matches, [file.path]);
      expect(await NativeUiJobs.tokenize('rust', 'fn main() {}'), isNotEmpty);
      expect(
        await NativeUiJobs.tokenize('unsupported-grammar', 'text'),
        isNull,
      );
    },
    skip: nativeSkip,
  );

  test(
    'native archive index handles implicit parents and invalidates replaced files',
    () async {
      final file = File(p.join(root.path, 'archive.zip'));
      void write(List<String> names) {
        final archive = Archive();
        for (final name in names) {
          archive.addFile(ArchiveFile.bytes(name, [1, 2, 3]));
        }
        file.writeAsBytesSync(ZipEncoder().encodeBytes(archive), flush: true);
      }

      write([
        'docs/z.txt',
        'docs/a.txt',
        'docs/sub/deep.txt',
        'docs2/other.txt',
        'root.txt',
      ]);
      final first = await NativeArchive.children(
        file.path,
        NativeArchiveFormat.zip,
        '',
      );
      expect(first, isNotNull);
      expect(first!.folders, ['docs', 'docs2']);
      expect(first.files, ['root.txt']);
      final nested = await NativeArchive.children(
        file.path,
        NativeArchiveFormat.zip,
        'docs',
      );
      expect(nested!.folders, ['sub']);
      expect(nested.files, ['a.txt', 'z.txt']);
      // A different length forces fingerprint invalidation even on coarse clocks.
      write(['replacement/new-name.txt']);
      final replaced = await NativeArchive.children(
        file.path,
        NativeArchiveFormat.zip,
        '',
      );
      expect(replaced!.folders, ['replacement']);
      expect(replaced.files, isEmpty);
    },
    skip: nativeSkip,
  );
}
