import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/services/disk_cleaner/cleaner_models.dart';
import 'package:cb_file_manager/services/disk_cleaner/disk_cleaner_service.dart';
import 'package:cb_file_manager/services/disk_cleaner/full_disk_scan_isolate.dart';
import 'package:cb_file_manager/services/disk_cleaner/editor_storage/editor_root_sizes.dart';
import 'package:cb_file_manager/services/disk_cleaner/editor_storage/editor_storage_analyzer.dart';
import 'package:cb_file_manager/services/disk_cleaner/editor_storage/editor_storage_models.dart';
import 'package:cb_native/cb_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Records what reaches the Trash without touching anything.
class _Trash implements TrashManager {
  final moved = <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<Set<String>> moveMultipleToTrashBatched(
    List<String> filePaths, {
    int chunkSize = 200,
    void Function(String, int, int)? onChunkStart,
    void Function(int, int)? onChunkDone,
    Duration? timeoutOverride,
    void Function(String, Object)? onError,
  }) async {
    moved.addAll(filePaths);
    return filePaths.toSet();
  }
}

void main() {
  late Directory home;
  late String data;
  late String extensions;
  late String project;
  // Everything written by the fixture is older than a day at this time,
  // except files stamped with it.
  final now = DateTime.now().add(const Duration(days: 3));

  void write(String path, int bytes, {DateTime? modified}) {
    final file = File(path)..createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0));
    if (modified != null) file.setLastModifiedSync(modified);
  }

  void json(String path, Object value) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(value));
  }

  void extension(String folder, {Map<String, Object>? manifest, int? bytes}) {
    final dir = p.join(extensions, folder);
    if (manifest != null) json(p.join(dir, 'package.json'), manifest);
    write(p.join(dir, 'main.js'), bytes ?? 10);
  }

  setUp(() {
    home = Directory.systemTemp.createTempSync('cb_editor_storage_');
    data = p.join(home.path, 'Library', 'Application Support', 'Code');
    extensions = p.join(home.path, '.vscode', 'extensions');
    project = p.join(home.path, 'project');
    Directory(project).createSync(recursive: true);

    json(p.join(extensions, 'extensions.json'), [
      {'relativeLocation': 'pub.active-1.0.0'},
      {
        'location': {'path': p.join(extensions, 'pub.loc-2.0.0')},
      },
    ]);
    json(p.join(extensions, '.obsolete'), {'pub.active-0.9.0': true});
    extension(
      'pub.active-1.0.0',
      manifest: {
        'publisher': 'Pub',
        'name': 'Active',
        'version': '1.0.0',
        'displayName': '%ext.name%',
        'icon': 'images/icon.png',
      },
      bytes: 100,
    );
    write(p.join(extensions, 'pub.active-1.0.0', 'images', 'icon.png'), 4);
    json(p.join(extensions, 'pub.active-1.0.0', 'package.nls.json'), {
      'ext.name': 'Active Extension',
    });
    // No manifest left: identified by its folder name.
    write(p.join(extensions, 'pub.active-0.9.0', 'old.js'), 50);
    extension(
      'pub.loc-2.0.0',
      // An icon outside the extension's folder is ignored.
      manifest: {
        'publisher': 'pub',
        'name': 'loc',
        'version': '2.0.0',
        'icon': '../pub.active-1.0.0/images/icon.png',
      },
    );
    extension(
      'pub.profiled-1.0.0',
      manifest: {'publisher': 'pub', 'name': 'profiled', 'version': '1.0.0'},
    );
    extension(
      'pub.stray-1.0.0',
      manifest: {'publisher': 'pub', 'name': 'stray', 'version': '1.0.0'},
    );

    File(p.join(data, 'code.lock'))
      ..createSync(recursive: true)
      ..writeAsStringSync('4242');
    write(p.join(data, 'Cache', 'Cache_Data', 'f'), 30);
    write(p.join(data, 'CachedExtensionVSIXs', 'old'), 40);
    write(p.join(data, 'CachedExtensionVSIXs', 'new'), 5, modified: now);
    write(p.join(data, 'logs', '20260101T000000', 'main.log'), 7);
    write(p.join(data, 'logs', '20260102T000000', 'main.log'), 3);
    write(p.join(data, 'Crashpad', 'completed', 'a.dmp'), 9);
    write(p.join(data, 'Crashpad', 'completed', 'b.dmp'), 9, modified: now);
    write(p.join(data, 'Crashpad', 'settings.dat'), 2);
    write(p.join(data, 'WebStorage', '1', 'x'), 11);
    write(p.join(data, 'Backups', 'unsaved'), 8);
    final user = p.join(data, 'User');
    write(p.join(user, 'History', 'h1', 'entries.json'), 13);
    write(p.join(user, 'settings.json'), 3);
    write(p.join(user, 'globalStorage', 'pub.active', 'state'), 17);
    write(p.join(user, 'globalStorage', 'vscode.git', 'state'), 19);
    write(p.join(user, 'globalStorage', 'state.vscdb'), 4);
    json(p.join(user, 'profiles', 'p1', 'extensions.json'), [
      {'relativeLocation': 'pub.profiled-1.0.0'},
    ]);
    write(p.join(user, 'profiles', 'p1', 'globalStorage', 'pub.loc', 'x'), 21);
    write(p.join(user, 'profiles', 'p1', 'settings.json'), 2);

    final workspaces = p.join(user, 'workspaceStorage');
    json(p.join(workspaces, 'present', 'workspace.json'), {
      'folder': Uri.file(project).toString(),
    });
    write(p.join(workspaces, 'present', 'pub.active', 'cache'), 23);
    write(p.join(workspaces, 'present', 'state.vscdb'), 1);
    json(p.join(workspaces, 'gone', 'workspace.json'), {
      'folder': Uri.file(p.join(home.path, 'deleted-project')).toString(),
    });
    write(p.join(workspaces, 'gone', 'state.vscdb'), 6);
    json(p.join(workspaces, 'remote', 'workspace.json'), {
      'folder': 'vscode-remote://ssh-remote+box/home/me',
    });
    json(p.join(workspaces, 'unplugged', 'workspace.json'), {
      'folder': 'file:///Volumes/CbNoSuchDisk7f3a/project',
    });
    write(p.join(workspaces, 'no-json', 'state.vscdb'), 1);
  });

  tearDown(() => home.deleteSync(recursive: true));

  Future<EditorStorageReport> analyze({
    bool running = true,
    EditorRootSizer sizer = dartEditorRootSizes,
  }) async {
    final reports = await EditorStorageAnalyzer(
      environment: EditorStorageEnvironment(
        operatingSystem: 'macos',
        home: home.path,
      ),
      sizer: sizer,
      now: () => now,
      isProcessAlive: (pid) => running && pid == 4242,
    ).analyze();
    expect(reports, hasLength(1));
    return reports.single;
  }

  EditorDataUsage dataOf(EditorStorageReport report, EditorDataKind kind) =>
      report.data.singleWhere((d) => d.kind == kind);

  test('extensions: profiles, obsolete versions and their storage', () async {
    final report = await analyze();
    expect(report.editor.dataFolder, 'Code');
    expect(report.isRunning, isTrue);
    final byFolder = {for (final e in report.extensions) p.basename(e.path): e};
    expect(byFolder.keys, {
      'pub.active-1.0.0',
      'pub.active-0.9.0',
      'pub.loc-2.0.0',
      'pub.profiled-1.0.0',
      'pub.stray-1.0.0',
    });
    final active = byFolder['pub.active-1.0.0']!;
    expect(active.id, 'pub.active');
    expect(active.displayName, 'Active Extension');
    expect(active.status, EditorExtensionStatus.installed);
    expect(active.installBytes, 100 + 4 + jsonBytes(active.path));
    expect(active.iconPath, p.join(active.path, 'images', 'icon.png'));
    expect(byFolder['pub.loc-2.0.0']!.iconPath, isNull);
    expect(active.globalStorageBytes, 17);
    expect(active.workspaceStorageBytes, 23);

    final old = byFolder['pub.active-0.9.0']!;
    expect((old.id, old.version), ('pub.active', '0.9.0'));
    expect(old.status, EditorExtensionStatus.obsolete);
    expect(old.isCleanable, isTrue);
    // Storage stays with the installed version.
    expect(old.globalStorageBytes, 0);

    expect(
      byFolder['pub.profiled-1.0.0']!.status,
      EditorExtensionStatus.installed,
    );
    expect(byFolder['pub.loc-2.0.0']!.globalStorageBytes, 21);
    expect(
      byFolder['pub.stray-1.0.0']!.status,
      EditorExtensionStatus.unregistered,
    );
    expect(report.orphanedExtensionData.single.id, 'vscode.git');
    expect(report.orphanedExtensionData.single.bytes, 19);
  });

  test('workspace storage is classified by its target', () async {
    final report = await analyze();
    final byName = {for (final w in report.workspaces) p.basename(w.path): w};
    expect(byName['present']!.status, EditorWorkspaceStatus.present);
    expect(byName['present']!.target, project);
    // The extension's share is part of the workspace folder.
    expect(
      byName['present']!.bytes,
      23 + 1 + jsonBytes(byName['present']!.path),
    );
    expect(byName['gone']!.status, EditorWorkspaceStatus.missing);
    expect(byName['gone']!.isCleanable, isTrue);
    expect(byName['remote']!.status, EditorWorkspaceStatus.unknown);
    expect(byName['unplugged']!.status, EditorWorkspaceStatus.offline);
    expect(byName['no-json']!.status, EditorWorkspaceStatus.unknown);
    expect(report.workspaces.where((w) => w.isCleanable).map((w) => w.path), [
      byName['gone']!.path,
    ]);
  });

  test('data kinds and what of them is cleanable', () async {
    final running = await analyze();
    expect(dataOf(running, EditorDataKind.cache).bytes, 30);
    // A running editor keeps its caches.
    expect(dataOf(running, EditorDataKind.cache).cleanable, isEmpty);
    final vsix = dataOf(running, EditorDataKind.extensionDownloads);
    expect(vsix.bytes, 45);
    expect(vsix.cleanable.map((t) => p.basename(t.path)), ['old']);
    final logs = dataOf(running, EditorDataKind.logs);
    expect(logs.bytes, 10);
    // The newest session is the one the editor writes to.
    expect(logs.cleanable.map((t) => p.basename(t.path)), ['20260101T000000']);
    final crash = dataOf(running, EditorDataKind.crashReports);
    expect(crash.bytes, 9 + 9 + 2);
    expect(crash.cleanable.map((t) => p.basename(t.path)), ['a.dmp']);
    expect(dataOf(running, EditorDataKind.webStorage).cleanable, isEmpty);
    expect(dataOf(running, EditorDataKind.localHistory).bytes, 13);
    expect(dataOf(running, EditorDataKind.localHistory).cleanable, isEmpty);
    expect(dataOf(running, EditorDataKind.other).paths, [
      p.join(data, 'Backups'),
    ]);
    expect(running.safeBytes, 50 + 40 + 7 + 9);

    final closed = await analyze(running: false);
    expect(
      dataOf(closed, EditorDataKind.cache).cleanable.single.path,
      p.join(data, 'Cache'),
    );
    expect(closed.safeBytes, running.safeBytes + 30);
  });

  test('nothing is written to the editor folders', () async {
    List<(String, int)> snapshot() => [
      for (final entity in home.listSync(recursive: true))
        if (entity is File)
          (entity.path, entity.lastModifiedSync().millisecondsSinceEpoch),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final before = snapshot();
    await analyze();
    expect(snapshot(), before);
  });

  test('without a registry every extension counts as installed', () async {
    File(p.join(extensions, 'extensions.json')).deleteSync();
    final report = await analyze();
    expect(report.extensions.map((e) => e.status).toSet(), {
      EditorExtensionStatus.installed,
    });
  });

  test('every cleanable target reaches the Trash as a whole', () async {
    final report = await analyze(running: false);
    final targets = [
      for (final e in report.extensions)
        if (e.isCleanable) e.path,
      for (final d in report.data)
        for (final t in d.cleanable) t.path,
      for (final w in report.workspaces)
        if (w.isCleanable) w.path,
    ];
    expect(targets, hasLength(6));
    final trash = _Trash();
    final result =
        await DiskCleanerService.forTesting(
          fullDiskScanSpawner: spawnFullDiskScan,
          trashManager: trash,
        ).cleanJunk(
          items: [
            for (final path in targets)
              JunkItem(
                path: path,
                sizeBytes: 1,
                categoryId: 'selected_item',
                isUserSelected: true,
              ),
          ],
          permanent: false,
        );
    expect(result.skippedUnsafe, isEmpty);
    expect(trash.moved, unorderedEquals(targets));
  });

  test('the native sizer agrees with the Dart walk', () async {
    final native = await analyze(sizer: editorRootSizes);
    final dart = await analyze();
    expect(native.totalBytes, dart.totalBytes);
    expect(
      native.extensions.map((e) => (e.path, e.totalBytes)).toList(),
      dart.extensions.map((e) => (e.path, e.totalBytes)).toList(),
    );
    final link = p.join(home.path, 'link');
    Link(link).createSync(project);
    final sizes = await NativeFs.rootSizes([link, p.join(home.path, 'none')]);
    final dartSizes = await dartEditorRootSizes([
      link,
      p.join(home.path, 'none'),
    ]);
    expect(
      sizes!.map((s) => (s.bytes, s.exists)).toList(),
      dartSizes.map((s) => (s.bytes, s.exists)).toList(),
    );
  }, skip: CbNative.isAvailable ? null : 'Rust library not built');
}

/// Bytes of the `package.json` / `package.nls.json` / `workspace.json` the
/// fixture wrote into [folder].
int jsonBytes(String folder) =>
    ['package.json', 'package.nls.json', 'workspace.json']
        .map((name) => File(p.join(folder, name)))
        .where((f) => f.existsSync())
        .fold(0, (sum, file) => sum + file.lengthSync());
