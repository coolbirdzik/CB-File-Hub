import 'dart:convert';
import 'dart:io';

import 'package:cb_file_manager/services/ai/agent_mobile_tools.dart';
import 'package:cb_file_manager/services/ai/agent_tool_catalog.dart';
import 'package:cb_file_manager/services/ai/agent_workspace.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory sandbox;
  late ToolExecutor executor;
  final opened = <String>[];
  final shared = <List<String>>[];

  setUp(() async {
    AgentToolCatalog.debugIsMobile = true;
    sandbox = await Directory.systemTemp.createTemp('cb-agent-mobile-');
    opened.clear();
    shared.clear();
    executor = ToolExecutor(
      mobileTools: (files) => AgentMobileTools(
        files,
        volumes: () async => [
          AgentStorageVolume(
            path: sandbox.path,
            name: 'Internal storage',
            kind: 'internal',
            totalBytes: 64 << 30,
            freeBytes: 10 << 30,
          ),
        ],
        open: (path) async {
          opened.add(path);
          return null;
        },
        share: (paths) async {
          shared.add(paths);
          return null;
        },
      ),
    )..beginTurn(currentPath: sandbox.path, isCancelled: () => false);
  });

  tearDown(() async {
    AgentToolCatalog.debugIsMobile = null;
    await sandbox.delete(recursive: true);
  });

  Future<ToolResult> call(String name, Map<String, dynamic> args) =>
      executor.execute(ToolCall(name: name, arguments: args));

  Future<Map<String, dynamic>> run(
    String name,
    Map<String, dynamic> args,
  ) async {
    final result = await call(name, args);
    expect(result.success, true, reason: result.output);
    return jsonDecode(result.output) as Map<String, dynamic>;
  }

  File write(String relative, int bytes, {DateTime? modified}) {
    final file = File(p.join(sandbox.path, relative))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List.filled(bytes, 1));
    if (modified != null) file.setLastModifiedSync(modified);
    return file;
  }

  test('phones get phone tools instead of a shell or the desktop Cleaner', () {
    expect(AgentToolCatalog.definitions, contains('list_storage'));
    expect(AgentToolCatalog.definitions, isNot(contains('run_command')));
    expect(
      AgentToolCatalog.definitions,
      isNot(contains('select_cleaner_scan_items')),
    );
    expect(
      AgentToolCatalog.validate('run_command', {'command': 'ls'}),
      contains('Unknown tool'),
    );
    expect(AgentToolCatalog.approvalTools, isNot(contains('clean_disk_junk')));
    expect(AgentToolCatalog.approvalTools, contains('delete_file'));
    expect(
      AgentToolCatalog.prompt(
        workingDirectory: sandbox.path,
        browsingPath: sandbox.path,
        platform: 'android',
      ),
      contains('There is no shell'),
    );

    AgentToolCatalog.debugIsMobile = false;
    expect(AgentToolCatalog.definitions, contains('run_command'));
    expect(AgentToolCatalog.definitions, contains('select_cleaner_scan_items'));
    expect(AgentToolCatalog.definitions, isNot(contains('list_storage')));
  });

  test('a shell request is refused as an unknown tool on a phone', () async {
    final result = await call('run_command', {'command': 'ls'});
    expect(result.success, false);
    expect(result.output, contains('Unknown tool'));
  });

  test(
    'storage lists volumes, space and the standard folders that exist',
    () async {
      Directory(p.join(sandbox.path, 'DCIM')).createSync();
      Directory(p.join(sandbox.path, 'Download')).createSync();

      final storage = await run('list_storage', {});
      final volume = (storage['volumes'] as List).single as Map;
      expect(volume['path'], sandbox.path);
      expect(volume['free_bytes'], 10 << 30);
      expect(volume['folders'], [
        p.join(sandbox.path, 'DCIM'),
        p.join(sandbox.path, 'Download'),
      ]);

      // Drive discovery on a phone lists its volumes, not "/".
      final roots = await run('list_directory', {'path': ''});
      expect((roots['items'] as List).single['path'], sandbox.path);
    },
  );

  test(
    'folder size totals nested files and ranks the largest children',
    () async {
      write('Movies/a.mp4', 3000);
      write('Movies/sub/b.mp4', 2000);
      write('notes.txt', 10);

      final size = await run('folder_size', {});
      expect(size['size_bytes'], 5010);
      expect(size['files'], 3);
      final largest = (size['largest_children'] as List).first as Map;
      expect(largest['path'], p.join(sandbox.path, 'Movies'));
      expect(largest['size_bytes'], 5000);
    },
  );

  test('large and recent file searches sort, filter and page', () async {
    final now = DateTime.now();
    write('big.mp4', 3 << 20, modified: now.subtract(const Duration(days: 30)));
    write('mid.mp4', 2 << 20, modified: now.subtract(const Duration(hours: 2)));
    write('small.jpg', 10, modified: now.subtract(const Duration(days: 1)));

    final large = await run('find_large_files', {'min_size_mb': 1});
    expect((large['items'] as List).map((i) => i['name']), [
      'big.mp4',
      'mid.mp4',
    ]);

    final recent = await run('find_recent_files', {'days': 7});
    expect((recent['items'] as List).map((i) => i['name']), [
      'mid.mp4',
      'small.jpg',
    ]);

    final firstPage = await run('find_large_files', {'limit': 1});
    expect((firstPage['items'] as List).single['name'], 'big.mp4');
    final next = await run('find_large_files', {
      'limit': 1,
      'cursor': firstPage['next_cursor'],
    });
    expect((next['items'] as List).single['name'], 'mid.mp4');
  });

  test('open and share hand only existing files to the system', () async {
    final photo = write('DCIM/photo.jpg', 5);

    await run('open_file', {'path': 'DCIM/photo.jpg'});
    expect(opened, [p.normalize(photo.path)]);

    await run('share_files', {
      'paths': ['DCIM/photo.jpg'],
    });
    expect(shared.single, [p.normalize(photo.path)]);

    final folder = await call('share_files', {
      'paths': ['DCIM'],
    });
    expect(folder.success, false);
    expect(shared, hasLength(1));
  });

  test(
    'Android per-app storage is skipped, not reported as a permission gap',
    () async {
      for (final path in [
        '/storage/emulated/0/Android/data',
        '/storage/emulated/0/Android/data/com.app/files',
        '/storage/1234-ABCD/Android/obb',
        'Could not list /storage/emulated/0/Android/data: Permission denied',
      ]) {
        expect(AgentWorkspace.isAppPrivate(path), isTrue, reason: path);
      }
      for (final path in [
        '/storage/emulated/0/Android/media',
        '/storage/emulated/0/Download/Android/database.db',
        '/storage/emulated/0/DCIM',
      ]) {
        expect(AgentWorkspace.isAppPrivate(path), isFalse, reason: path);
      }

      final refused = await call('find_recent_files', {
        'path': '/storage/emulated/0/Android/data',
      });
      expect(refused.success, isFalse);
      expect(refused.output, contains('private to the app'));

      final prompt = AgentToolCatalog.prompt(
        workingDirectory: sandbox.path,
        browsingPath: sandbox.path,
        platform: 'android',
      );
      expect(prompt, contains('not a permission problem'));
    },
  );
}
