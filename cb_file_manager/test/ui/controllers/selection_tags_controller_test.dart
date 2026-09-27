import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cb_file_manager/ui/controllers/selection_tags_controller.dart';

void main() {
  late Map<String, List<String>> store;
  late List<String> writes;
  late Set<String> rejected;
  late SelectionTagsController controller;

  setUp(() {
    store = {
      'a': ['one', 'Common'],
      'b': ['two', 'common'],
      'c': [],
    };
    writes = [];
    rejected = {};
    controller = SelectionTagsController(
      read: (path) async => List.of(store[path]!),
      write: (path, tags) async {
        writes.add(path);
        if (rejected.contains(path)) return false;
        store[path] = List.of(tags);
        return true;
      },
      changed: (_) {},
      changes: const Stream.empty(),
      createHierarchy: (_, _) async {},
    );
  });
  tearDown(() => controller.dispose());

  test(
    'union counts are case insensitive and edits preserve unique tags',
    () async {
      await controller.select(['a', 'b']);
      expect(controller.counts, {'Common': 2, 'one': 1, 'two': 1});
      await controller.add('one');
      expect(writes, ['b']);
      expect(store['b'], ['two', 'common', 'one']);
      await controller.remove('COMMON');
      expect(store['a'], ['one']);
      expect(store['b'], ['two', 'one']);
    },
  );

  test(
    'single file trims input, rejects duplicates and empty drafts',
    () async {
      await controller.select(['a']);
      await controller.add('  COMMON  ');
      await controller.add('   ');
      expect(writes, isEmpty);
      await controller.add('new tag');
      expect(store['a'], ['one', 'Common', 'new tag']);
    },
  );

  test(
    'retry captures only failed paths even after selection changes',
    () async {
      rejected.add('b');
      await controller.select(['a', 'b']);
      await controller.add('new');
      expect(controller.failures.single.paths, ['b']);
      await controller.select(['c']);
      rejected.clear();
      writes.clear();
      await controller.retry(controller.failures.single);
      expect(writes, ['b']);
      expect(store['c'], isEmpty);
      expect(controller.failures, isEmpty);
      expect(controller.paths, ['c']);
    },
  );

  test(
    'queued writes keep original targets and read the latest tags',
    () async {
      await controller.select(['a']);
      final first = controller.add('first');
      final second = controller.add('second');
      await controller.select(['b']);
      await Future.wait([first, second]);
      expect(store['a'], ['one', 'Common', 'first', 'second']);
      expect(store['b'], ['two', 'common']);
      expect(controller.tagsByPath.keys, ['b']);
      expect(controller.saving, isFalse);
    },
  );

  test(
    'hierarchy assigns children, never implicitly assigns the parent',
    () async {
      final links = <String>[];
      final c = SelectionTagsController(
        read: (path) async => List.of(store[path]!),
        write: (path, tags) async {
          store[path] = List.of(tags);
          return true;
        },
        changed: (_) {},
        changes: const Stream.empty(),
        createHierarchy: (parent, children) async =>
            links.add('$parent:${children.join(',')}'),
      );
      addTearDown(c.dispose);
      await c.select(['a', 'b']);
      await c.add('People:Alice, Bob');
      expect(links, ['People:Alice,Bob']);
      expect(store['a'], ['one', 'Common', 'Alice', 'Bob']);
      expect(store['b'], ['two', 'common', 'Alice', 'Bob']);
      await c.add('People:');
      expect(links, hasLength(1));
    },
  );

  test('late load from old selection cannot overwrite the new one', () async {
    final delayed = Completer<List<String>>();
    final c = SelectionTagsController(
      read: (path) => path == 'a' ? delayed.future : Future.value(['new']),
      changes: const Stream.empty(),
    );
    addTearDown(c.dispose);
    final first = c.select(['a']);
    await c.select(['b']);
    delayed.complete(['old']);
    await first;
    expect(c.tagsByPath, {
      'b': ['new'],
    });
  });

  test(
    'disposal does not cancel a write already authorized for a selection',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final c = SelectionTagsController(
        read: (path) async => [],
        write: (path, tags) async {
          started.complete();
          await finish.future;
          store[path] = tags;
          return true;
        },
        changed: (_) {},
        changes: const Stream.empty(),
      );
      await c.select(['a']);
      final pending = c.add('saved');
      await started.future;
      c.dispose();
      finish.complete();
      await pending;
      expect(store['a'], ['saved']);
    },
  );

  test('read failure is not silently treated as an empty tag list', () async {
    final c = SelectionTagsController(
      read: (_) async => throw StateError('unavailable'),
      changes: const Stream.empty(),
    );
    addTearDown(c.dispose);
    await c.select(['a']);
    expect(c.loadError, isNotNull);
    await c.add('new');
    expect(c.failures.single.paths, ['a']);
  });

  test('two panes editing the same file serialize their deltas', () async {
    final started = Completer<void>();
    final finish = Completer<void>();
    var writeCount = 0;
    SelectionTagsController paneController() => SelectionTagsController(
      read: (path) async => List.of(store[path]!),
      write: (path, tags) async {
        if (++writeCount == 1) {
          started.complete();
          await finish.future;
        }
        store[path] = List.of(tags);
        return true;
      },
      changed: (_) {},
      changes: const Stream.empty(),
    );
    final left = paneController();
    final right = paneController();
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    await left.select(['a']);
    await right.select(['a']);
    final first = left.add('left');
    await started.future;
    final second = right.add('right');
    await Future<void>.delayed(Duration.zero);
    expect(writeCount, 1);
    finish.complete();
    await Future.wait([first, second]);
    expect(store['a'], ['one', 'Common', 'left', 'right']);
  });
}
