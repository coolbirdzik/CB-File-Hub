import 'dart:convert';
import 'dart:io';
import 'package:cb_file_manager/services/ai/agent_tag_tools.dart';
import 'package:cb_file_manager/services/ai/agent_tool_catalog.dart';
import 'package:cb_file_manager/services/ai/tool_executor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class MemoryAgentTags extends AgentTagStore {
  final values = <String, List<String>>{};
  @override
  Future<List<String>> all() async =>
      values.values.expand((v) => v).toSet().toList();
  @override
  Future<List<String>> read(String path) async => List.of(values[path] ?? []);
  @override
  Future<List<String>> search(String tag) async => values.entries
      .where((e) => e.value.any((t) => t.toLowerCase() == tag.toLowerCase()))
      .map((e) => e.key)
      .toList();
  @override
  Future<bool> write(String path, List<String> tags) async {
    values[path] = List.of(tags);
    return true;
  }
}

void main() {
  late Directory sandbox;
  late ToolExecutor executor;
  late MemoryAgentTags tags;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('cb-agent-tools-');
    tags = MemoryAgentTags();
    executor = ToolExecutor(tagStore: tags)
      ..beginTurn(currentPath: sandbox.path, isCancelled: () => false);
  });
  tearDown(() async {
    await sandbox.delete(recursive: true);
  });
  Future<Map<String, dynamic>> run(
    String name,
    Map<String, dynamic> args,
  ) async {
    final result = await executor.execute(
      ToolCall(name: name, arguments: args),
    );
    expect(result.success, true, reason: result.output);
    return jsonDecode(result.output) as Map<String, dynamic>;
  }

  Future<File> file(String name, String text) async =>
      File(p.join(sandbox.path, name))..writeAsStringSync(text);

  test(
    'listing follows every page beyond old 200 entry cap; cursors bind filters',
    () async {
      for (var i = 0; i < 225; i++) {
        await file('item-$i.txt', 'x');
      }
      var page = await run('list_directory', {'limit': 30});
      final paths = <String>{};
      while (true) {
        paths.addAll(
          (page['items'] as List).map((item) => item['path'] as String),
        );
        expect(page['scope_complete'], true);
        if (page['next_cursor'] == null) break;
        final cursor = page['next_cursor'];
        final bad = await executor.execute(
          ToolCall(
            name: 'list_directory',
            arguments: {'cursor': cursor, 'pattern': 'changed'},
          ),
        );
        expect(bad.success, false);
        page = await run('list_directory', {'limit': 30, 'cursor': cursor});
      }
      expect(paths, hasLength(225));
    },
  );
  test(
    'search combines name and extension; text search and read support continuation',
    () async {
      await file(
        'report.txt',
        List.generate(120, (i) => 'line $i needle').join('\n'),
      );
      await file('report.csv', 'needle');
      await file('other.txt', 'other');
      final result = await run('search_files', {
        'query': 'report',
        'extension': 'txt',
      });
      expect(result['items'], hasLength(1));
      expect((result['items'] as List).first['size_bytes'], isA<int>());
      final search = await run('search_content', {
        'query': 'needle',
        'extension': 'txt',
        'limit': 20,
      });
      expect(search['matched_in_scan'], 120);
      expect(search['next_cursor'], isNotNull);
      final read = await run('read_file', {
        'path': 'report.txt',
        'start_line': 51,
        'max_lines': 25,
      });
      expect(read['lines'].first['text'], 'line 50 needle');
      expect(read['next_start_line'], 76);
    },
  );
  test(
    'checksums distinguish same-size content and binary read refuses data',
    () async {
      await file('one.txt', 'same');
      await file('two.txt', 'same');
      await file('three.txt', 'diff');
      final one = await run('file_checksum', {'path': 'one.txt'});
      expect(
        (await run('file_checksum', {'path': 'two.txt'}))['sha256'],
        one['sha256'],
      );
      expect(
        (await run('file_checksum', {'path': 'three.txt'}))['sha256'],
        isNot(one['sha256']),
      );
      await File(p.join(sandbox.path, 'binary.bin')).writeAsBytes([0, 1, 2]);
      expect(
        (await executor.execute(
          const ToolCall(name: 'read_file', arguments: {'path': 'binary.bin'}),
        )).success,
        false,
      );
    },
  );
  test(
    'common file operations preserve tags and refuse accidental overwrite',
    () async {
      final source = await file('source.txt', 'keep');
      tags.values[source.path] = ['Work'];
      await run('create_directory', {'path': 'organized'});
      await run('copy_file', {
        'source': 'source.txt',
        'destination': 'organized/copy.txt',
      });
      await run('move_file', {
        'source': 'source.txt',
        'destination': 'organized/moved.txt',
      });
      expect(await source.exists(), false);
      expect(tags.values[p.join(sandbox.path, 'organized', 'moved.txt')], [
        'Work',
      ]);
      expect(tags.values[source.path], isEmpty);
      final collision = await executor.execute(
        const ToolCall(
          name: 'copy_file',
          arguments: {
            'source': 'organized/moved.txt',
            'destination': 'organized/copy.txt',
          },
        ),
      );
      expect(collision.success, false);
      final overwrite = await executor.execute(
        const ToolCall(
          name: 'write_file',
          arguments: {'path': 'organized/copy.txt', 'content': 'oops'},
        ),
      );
      expect(overwrite.success, false);
      expect(
        await File(
          p.join(sandbox.path, 'organized', 'copy.txt'),
        ).readAsString(),
        'keep',
      );
    },
  );
  test(
    'tags are paged, scoped to folder, and updates preserve unrelated tags',
    () async {
      final f = await file('tagged.txt', 'hello');
      tags.values[f.path] = ['Work', 'Keep'];
      tags.values[p.join(sandbox.parent.path, 'outside.txt')] = ['Work'];
      final search = await run('search_by_tag', {'tag': '#Work'});
      expect(search['items'], hasLength(1));
      expect(
        (await run('search_by_tag', {'tag': 'Work', 'global': true}))['items'],
        hasLength(2),
      );
      final updated = await run('update_file_tags', {
        'path': 'tagged.txt',
        'add': ['Reviewed'],
        'remove': ['work'],
      });
      expect(updated['tags'], ['Keep', 'Reviewed']);
      expect((await run('list_all_tags', {'query': 'review'}))['items'], [
        {'tag': 'Reviewed'},
      ]);
    },
  );
  test(
    'cancellation blocks a pending mutation and invalid tools return repairable errors',
    () async {
      executor.beginTurn(currentPath: sandbox.path, isCancelled: () => true);
      final stopped = await executor.execute(
        const ToolCall(
          name: 'write_file',
          arguments: {'path': 'stop.txt', 'content': 'x'},
        ),
      );
      expect(stopped.success, false);
      expect(await File(p.join(sandbox.path, 'stop.txt')).exists(), false);
      expect(
        AgentToolCatalog.validate('write_file', {'path': 'x'}),
        contains('content'),
      );
      expect(
        AgentToolCatalog.validate('delete_file', {
          'path': 'x',
          'paths': ['y'],
        }),
        isNotNull,
      );
      expect(
        ToolExecutor.parseToolCalls(
          '{"name":"unknown_tool","arguments":{"nested":{"text":"a } b"}}}',
        ).single.arguments['nested'],
        {'text': 'a } b'},
      );
    },
  );
}
