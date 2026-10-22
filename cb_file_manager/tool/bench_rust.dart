// Run from cb_file_manager; see docs/quality/03-rust-benchmarks.md.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cb_file_manager/helpers/core/text_utils.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_tree_node.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_native/cb_native.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _query = 'bo nao';

Future<void> main(List<String> args) async {
  if (args.length == 3 && args.first == '--prepare') {
    await _prepare(Directory(args[1]).absolute, File(args[2]).absolute);
    return;
  }
  if (args.length < 3 || args.length > 4) {
    stderr.writeln(
      'Usage: bench_rust <corpus> <hash-file> <output.json> [rounds=5]\n'
      '       bench_rust --prepare <new-corpus> <new-hash-file>',
    );
    exitCode = 64;
    return;
  }
  if (!Platform.isWindows || !CbNative.isAvailable) {
    throw StateError('Windows and a loaded cb_native library are required.');
  }
  final root = Directory(args[0]).absolute.path;
  final hashFile = File(args[1]).absolute;
  final rounds = args.length == 4 ? int.parse(args[3]) : 5;
  if (rounds < 3) throw ArgumentError('Use at least three measured rounds.');
  if (!Directory(root).existsSync() || !hashFile.existsSync()) {
    throw ArgumentError('Corpus and hash file must already exist.');
  }
  final samples = <Map<String, Object>>[];
  final summaries = <Map<String, Object>>[];

  Future<void> compare(
    String task,
    Future<Map<String, Object>> Function(bool native) run,
  ) async {
    Map<String, Object>? expected;
    final times = <bool, List<int>>{false: [], true: []};
    // One untimed warm-up per implementation, then alternate who goes first.
    for (var round = 0; round <= rounds; round++) {
      for (final native in round.isEven ? [false, true] : [true, false]) {
        final value = await run(native);
        final elapsedUs = value.remove('elapsed_us')! as int;
        expected ??= value;
        if (jsonEncode(value) != jsonEncode(expected)) {
          throw StateError('$task parity failed: $value != $expected');
        }
        if (round == 0) continue;
        times[native]!.add(elapsedUs);
        final sample = <String, Object>{
          'task': task,
          'round': round,
          'engine': native ? 'rust' : 'dart',
          'microseconds': elapsedUs,
          'result': value,
        };
        samples.add(sample);
        stdout.writeln(jsonEncode(sample));
      }
    }
    int median(List<int> values) {
      final sorted = [...values]..sort();
      final middle = sorted.length ~/ 2;
      return sorted.length.isOdd
          ? sorted[middle]
          : ((sorted[middle - 1] + sorted[middle]) / 2).round();
    }

    final dartUs = median(times[false]!);
    final rustUs = median(times[true]!);
    final summary = <String, Object>{
      'task': task,
      'dart_median_us': dartUs,
      'rust_median_us': rustUs,
      'dart_over_rust': dartUs / rustUs,
      'dart_min_us': times[false]!.reduce(min),
      'dart_max_us': times[false]!.reduce(max),
      'rust_min_us': times[true]!.reduce(min),
      'rust_max_us': times[true]!.reduce(max),
      'result': expected!,
    };
    summaries.add(summary);
    stdout.writeln(jsonEncode(summary));
  }

  await compare('disk_cleaner_full_scan', (native) => _scan(root, native));
  await compare('recursive_name_search', (native) => _search(root, native));
  await compare('sha256', (native) async {
    final sw = Stopwatch()..start();
    final digest = native
        ? Digest((await NativeHash.sha256File(hashFile.path))!)
        : await sha256.bind(hashFile.openRead()).first;
    sw.stop();
    return {'elapsed_us': sw.elapsedMicroseconds, 'sha256': digest.toString()};
  });

  final report = <String, Object>{
    'schema': 1,
    'date_utc': DateTime.now().toUtc().toIso8601String(),
    'os': Platform.operatingSystemVersion,
    'dart': Platform.version,
    'processors': Platform.numberOfProcessors,
    'native_available': CbNative.isAvailable,
    'corpus': root,
    'hash_file': hashFile.path,
    'hash_bytes': await hashFile.length(),
    'query': _query,
    'rounds': rounds,
    'warmups_per_engine_per_task': 1,
    'cache': 'warm OS cache; no app result reuse; alternating engine order',
    'disk_scan': {
      'max_depth': 20,
      'min_display_entry_bytes': defaultMinDisplayEntryBytes,
      'max_children_per_directory': defaultMaxChildrenPerDirectory,
      'junk_rules': 0,
      'incremental': false,
      'includes': 'isolate startup, scan, tree processing and result transfer',
      'excludes': 'Flutter frame rendering',
    },
    'summaries': summaries,
    'samples': samples,
  };
  final output = File(args[2]);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln('Report: ${output.absolute.path}');
}

Future<Map<String, Object>> _scan(String root, bool native) async {
  final sw = Stopwatch()..start();
  final handle = await spawnFullDiskScan(
    drivePath: root,
    useNativeScanner: native,
  );
  final progress = handle.progress.listen((_) {});
  final previews = handle.treeSnapshots.listen((_) {});
  final FullDiskScanResult result;
  try {
    result = await handle.future;
    sw.stop();
  } finally {
    await progress.cancel();
    await previews.cancel();
  }
  if (result.scanMode != FullDiskScanMode.full || result.isPartial) {
    throw StateError('Only complete full scans can be compared.');
  }
  final rows = <String>[];
  var directories = 0;
  void visit(DiskTreeNode node, String parent) {
    if (!node.isFile) directories++;
    final key = node.isAggregate ? '$parent/<folded>' : node.fullPath;
    rows.add(
      '$key|${node.isFile}|${node.sizeBytes}|${node.fileCount}'
      '|${node.aggregatedItemCount}|${node.junkCategoryId}',
    );
    for (final child in node.children) {
      visit(child, node.fullPath);
    }
  }

  visit(result.root, '');
  rows.sort();
  return {
    'elapsed_us': sw.elapsedMicroseconds,
    'files': result.root.fileCount,
    'directories_including_root': directories,
    'bytes': result.root.sizeBytes,
    'display_nodes': result.nodeCount,
    'tree_sha256': sha256.convert(utf8.encode(rows.join('\n'))).toString(),
    'coverage_issues': result.coverageIssues.length,
  };
}

Future<Map<String, Object>> _search(String root, bool native) async {
  final sw = Stopwatch()..start();
  final paths = <String>[];
  if (native) {
    final search = NativeSearch.start(
      root: root,
      words: TextUtils.searchWords(_query),
    );
    if (search == null) throw StateError('Native search did not start.');
    final hits = await NativeSearch.collect(search, shouldContinue: () => true);
    if (hits == null) throw StateError('Native search was cancelled.');
    paths.addAll(hits.map((hit) => p.normalize(hit.path)));
  } else {
    // Same name matcher and traversal as FileNavigationBloc._recursiveSearch.
    Future<void> walk(Directory directory) async {
      await for (final entity in directory.list(followLinks: false)) {
        if (TextUtils.matchesSearch(p.basename(entity.path), _query)) {
          paths.add(p.normalize(entity.path));
        }
        if (entity is Directory) await walk(entity);
      }
    }

    await walk(Directory(root));
  }
  sw.stop();
  paths.sort();
  return {
    'elapsed_us': sw.elapsedMicroseconds,
    'hits': paths.length,
    'paths_sha256': sha256.convert(utf8.encode(paths.join('\n'))).toString(),
  };
}

Future<void> _prepare(Directory root, File hashFile) async {
  // Never overwrite an existing directory or input file.
  if (FileSystemEntity.typeSync(root.path) != FileSystemEntityType.notFound ||
      FileSystemEntity.typeSync(hashFile.path) !=
          FileSystemEntityType.notFound) {
    throw ArgumentError('Preparation requires two new paths.');
  }
  await root.create(recursive: true);
  final payload = Uint8List.fromList(List.generate(128, (i) => i));
  for (var group = 0; group < 10; group++) {
    for (var branch = 0; branch < 10; branch++) {
      for (var leaf = 0; leaf < 10; leaf++) {
        final directory = Directory(
          p.join(root.path, 'g$group', 'b$branch', 'd$leaf'),
        );
        await directory.create(recursive: true);
        for (var file = 0; file < 100; file++) {
          final name = file % 10 == 0
              ? 'Bổ_Não_$file.txt'
              : 'document_$file.bin';
          await File(p.join(directory.path, name)).writeAsBytes(payload);
        }
      }
    }
    stdout.writeln('Prepared ${(group + 1) * 10000}/100000 files');
  }
  await hashFile.parent.create(recursive: true);
  final random = Random(42);
  final block = Uint8List.fromList(
    List.generate(1024 * 1024, (_) => random.nextInt(256)),
  );
  final sink = hashFile.openWrite();
  for (var i = 0; i < 256; i++) {
    sink.add(block);
  }
  await sink.close();
  stdout.writeln('Prepared 256 MiB hash input: ${hashFile.path}');
}
