import 'dart:io';
import 'package:path/path.dart' as p;
import '../../helpers/tags/tag_manager.dart';
import 'agent_file_tools.dart';

/// Adapter to the app's existing tag store, also used by file operations.
class AgentTagStore {
  Future<List<String>> all() async {
    await TagManager.initialize();
    return {
      ...await TagManager.getAllUniqueTags(''),
      ...await TagManager.getStandaloneTags(),
    }.toList();
  }

  Future<List<String>> read(String path) async {
    await TagManager.initialize();
    return TagManager.getTags(path);
  }

  Future<List<String>> search(String tag) async {
    await TagManager.initialize();
    return (await TagManager.findFilesByTagGlobally(
      tag,
    )).map((file) => file.path).toList();
  }

  Future<bool> write(String path, List<String> tags) =>
      TagManager.setTags(path, tags);
}

class AgentTagTools {
  static const names = {
    'list_all_tags',
    'get_file_tags',
    'search_by_tag',
    'update_file_tags',
  };
  final AgentTagStore store;
  final AgentFileTools pages;
  AgentTagTools(this.store, this.pages);

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args, {
    required bool Function() isCancelled,
  }) async {
    if (isCancelled()) throw StateError('Operation stopped by user.');
    if (args['cursor'] != null) return pages.page(name, args, null);
    if (name == 'list_all_tags') {
      final query = (args['query'] as String? ?? '')
          .replaceFirst(RegExp(r'^#'), '')
          .toLowerCase();
      final tags =
          (await store.all())
              .where((tag) => tag.toLowerCase().contains(query))
              .toList()
            ..sort();
      return pages.page(
        name,
        args,
        tags.map((tag) => <String, dynamic>{'tag': tag}).toList(),
      );
    }
    final path = args['path'] as String? ?? '';
    if (name == 'search_by_tag') {
      final tag = (args['tag'] as String).replaceFirst(RegExp(r'^#'), '');
      final paths = await store.search(tag);
      final matches =
          paths
              .where(
                (file) =>
                    args['global'] == true ||
                    p.equals(path, file) ||
                    p.isWithin(path, file),
              )
              .toList()
            ..sort();
      return pages.page(
        name,
        args,
        matches
            .map((file) => <String, dynamic>{'path': file, 'tag': tag})
            .toList(),
      );
    }
    if (await FileSystemEntity.type(path) == FileSystemEntityType.notFound) {
      throw FileSystemException('Path not found', path);
    }
    final current = await store.read(path);
    if (name == 'get_file_tags') {
      return {'ok': true, 'path': path, 'tags': current};
    }
    final tags = {for (final tag in current) tag.toLowerCase(): tag};
    for (final tag in (args['remove'] as List? ?? []).cast<String>()) {
      tags.remove(tag.replaceFirst(RegExp(r'^#'), '').trim().toLowerCase());
    }
    for (final tag in (args['add'] as List? ?? []).cast<String>()) {
      final clean = tag.replaceFirst(RegExp(r'^#'), '').trim();
      if (clean.isNotEmpty) tags[clean.toLowerCase()] = clean;
    }
    if (isCancelled()) throw StateError('Operation stopped by user.');
    if (!await store.write(path, tags.values.toList())) {
      throw StateError('Tag store rejected the update.');
    }
    return {'ok': true, 'path': path, 'tags': await store.read(path)};
  }
}
