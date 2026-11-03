import 'dart:io';

import 'package:cb_file_manager/services/ssh/sftp_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'memory_transfer_file_system.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cb_sftp_transfer_');
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<TransferReport> copy(
    TransferFileSystem from,
    List<TransferEntry> sources,
    TransferFileSystem to,
    String destination, {
    TransferConflictPolicy? policy,
    void Function(TransferProgress)? onProgress,
    void Function(SftpTransferTask)? onTask,
  }) {
    late SftpTransferTask task;
    task = SftpTransferTask(
      from: from,
      to: to,
      sources: sources,
      destination: destination,
      resolveConflicts: (_) async => policy,
      progressInterval: Duration.zero,
      onProgress: (progress) {
        onProgress?.call(progress);
        onTask?.call(task);
      },
    );
    return task.run();
  }

  test('uploads a local folder tree recursively with byte progress', () async {
    final local = LocalTransferFileSystem();
    final docs = Directory(p.join(temp.path, 'docs'));
    await Directory(p.join(docs.path, 'nested')).create(recursive: true);
    await File(p.join(docs.path, 'a.txt')).writeAsString('alpha');
    await File(p.join(docs.path, 'nested', 'b.txt')).writeAsString('bravo!');
    final remote = MemoryTransferFileSystem(homePath: '/srv')..mkdirs('/srv');
    final progress = <TransferProgress>[];
    final sources = (await local.list(temp.path));
    final report = await copy(
      local,
      sources,
      remote,
      '/srv',
      onProgress: progress.add,
    );
    expect(report.failures, isEmpty);
    expect(report.cancelled, isFalse);
    expect(report.transferred, 2);
    expect(remote.text('/srv/docs/a.txt'), 'alpha');
    expect(remote.text('/srv/docs/nested/b.txt'), 'bravo!');
    expect(progress.last.bytesDone, 11);
    expect(progress.last.bytesTotal, 11);
    expect(progress.last.filesDone, 2);
    expect(
      progress.map((e) => e.bytesDone).toList(),
      orderedEquals([...progress.map((e) => e.bytesDone)]..sort()),
      reason: 'Per-file writer progress is cumulative, not a delta',
    );
  });

  test('downloads into a local folder and lists it back', () async {
    final remote = MemoryTransferFileSystem()
      ..addFile('/home/dev/report.txt', 'quarterly')
      ..addFile('/home/dev/logs/app.log', 'boot');
    final local = LocalTransferFileSystem();
    final report = await copy(
      remote,
      await remote.list('/home/dev'),
      local,
      temp.path,
    );
    expect(report.failures, isEmpty);
    expect(
      await File(p.join(temp.path, 'report.txt')).readAsString(),
      'quarterly',
    );
    expect(
      await File(p.join(temp.path, 'logs', 'app.log')).readAsString(),
      'boot',
    );
    final names = (await local.list(temp.path)).map((e) => e.name).toSet();
    expect(names, {'report.txt', 'logs'});
    expect(local.parent(temp.path), p.dirname(temp.path));
  });

  test('skips linked folders instead of following them', () async {
    final tree = Directory(p.join(temp.path, 'tree'));
    await tree.create();
    await File(p.join(tree.path, 'real.txt')).writeAsString('x');
    try {
      await Link(p.join(tree.path, 'loop')).create(temp.path);
    } on FileSystemException {
      markTestSkipped('Creating symbolic links needs Developer Mode here');
      return;
    }
    final local = LocalTransferFileSystem();
    final listed = await local.list(tree.path);
    expect(listed.singleWhere((e) => e.name == 'loop').isLink, isTrue);
    final remote = MemoryTransferFileSystem();
    final report = await copy(
      local,
      (await local.list(temp.path)).where((e) => e.name == 'tree').toList(),
      remote,
      '/',
    );
    expect(report.failures, isEmpty);
    expect(remote.text('/tree/real.txt'), 'x');
    expect(remote.dirs.where((d) => d.contains('loop')), isEmpty);
  });

  test('reports names Windows cannot store and keeps going', () async {
    final remote = MemoryTransferFileSystem()
      ..addFile('/in/ok.txt', 'fine')
      ..addFile('/in/a:b.txt', 'colon')
      ..addFile('/in/NUL.txt', 'device')
      ..addFile('/in/trailing.', 'dot');
    final windows = MemoryTransferFileSystem(paths: p.windows, root: r'C:\');
    final report = await copy(
      remote,
      await remote.list('/in'),
      windows,
      r'C:\',
    );
    expect(windows.text(r'C:\ok.txt'), 'fine');
    expect(report.transferred, 1);
    expect(
      report.failures.map((f) => (p.posix.basename(f.path), f.kind)),
      unorderedEquals([
        ('a:b.txt', TransferFailureKind.invalidName),
        ('NUL.txt', TransferFailureKind.invalidName),
        ('trailing.', TransferFailureKind.invalidName),
      ]),
    );
  });

  test('names differing only by case are not merged on Windows', () async {
    final remote = MemoryTransferFileSystem()
      ..addFile('/in/README.md', 'upper')
      ..addFile('/in/Readme.md', 'mixed');
    final windows = MemoryTransferFileSystem(paths: p.windows, root: r'C:\');
    final report = await copy(
      remote,
      await remote.list('/in'),
      windows,
      r'C:\',
    );
    expect(report.transferred, 1);
    expect(report.failures.single.kind, TransferFailureKind.caseConflict);
    expect(windows.files, hasLength(1));
  });

  group('existing destination items', () {
    late MemoryTransferFileSystem source, target;
    setUp(() {
      source = MemoryTransferFileSystem()
        ..addFile('/src/note.txt', 'new note')
        ..addFile('/src/docs/new.txt', 'added');
      target = MemoryTransferFileSystem()
        ..addFile('/dst/note.txt', 'old note')
        ..addFile('/dst/docs/keep.txt', 'kept');
    });

    test('skip keeps existing files and merges folders', () async {
      final report = await copy(
        source,
        await source.list('/src'),
        target,
        '/dst',
        policy: TransferConflictPolicy.skip,
      );
      expect(report.skipped, 1);
      expect(target.text('/dst/note.txt'), 'old note');
      expect(target.text('/dst/docs/keep.txt'), 'kept');
      expect(target.text('/dst/docs/new.txt'), 'added');
    });

    test('replace overwrites files and merges folders', () async {
      final report = await copy(
        source,
        await source.list('/src'),
        target,
        '/dst',
        policy: TransferConflictPolicy.replace,
      );
      expect(report.transferred, 2);
      expect(target.text('/dst/note.txt'), 'new note');
      expect(target.text('/dst/docs/keep.txt'), 'kept');
    });

    test('dismissing the question cancels before writing', () async {
      final report = await copy(
        source,
        await source.list('/src'),
        target,
        '/dst',
      );
      expect(report.cancelled, isTrue);
      expect(target.text('/dst/note.txt'), 'old note');
      expect(target.files.containsKey('/dst/docs/new.txt'), isFalse);
    });

    test('a file where a folder goes is reported, not replaced', () async {
      target.addFile('/dst/docs2', 'a file');
      source.addFile('/src2/docs2/inner.txt', 'x');
      final report = await copy(
        source,
        await source.list('/src2'),
        target,
        '/dst',
        policy: TransferConflictPolicy.replace,
      );
      expect(report.failures.single.kind, TransferFailureKind.typeConflict);
      expect(target.text('/dst/docs2'), 'a file');
    });
  });

  test('cancel stops the batch and removes the partial file', () async {
    final source = MemoryTransferFileSystem()
      ..addFile('/src/big.bin', 'x' * 64)
      ..addFile('/src/later.bin', 'y' * 8);
    final target = MemoryTransferFileSystem();
    final report = await copy(
      source,
      await source.list('/src'),
      target,
      '/',
      onTask: (task) {
        if (target.files['/big.bin']?.isNotEmpty ?? false) task.cancel();
      },
    );
    expect(report.cancelled, isTrue);
    expect(target.files, isEmpty);
  });

  test('Windows drive list sits above every drive root', () async {
    final local = LocalTransferFileSystem(
      paths: p.windows,
      listDrives: () async => [r'C:\', r'D:\'],
    );
    expect(local.parent(r'C:\'), '');
    expect(local.parent(''), isNull);
    final drives = await local.list('');
    expect(drives.map((d) => (d.name, d.path)), [
      ('C:', r'C:\'),
      ('D:', r'D:\'),
    ]);
  });
}
