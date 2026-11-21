import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cb_file_manager/ui/controllers/selection_tags_controller.dart';

/// Adding one tag from the properties pane must not fan out into repeated
/// reloads (each one rebuilds the whole pane and reloads the tag catalog).
void main() {
  test(
    'a single add reloads once, even though its own change event returns',
    () async {
      final store = <String, List<String>>{
        'a': ['one'],
      };
      var reads = 0;
      final events = StreamController<String>.broadcast(sync: false);
      addTearDown(events.close);
      final c = SelectionTagsController(
        read: (path) async {
          reads++;
          return List.of(store[path]!);
        },
        write: (path, tags) async {
          store[path] = List.of(tags);
          return true;
        },
        // Mirrors the real wiring: writing a file broadcasts a tag change that
        // the controller itself also listens to.
        changed: (path) => events.add('preserve_scroll:$path'),
        changes: events.stream,
      );
      addTearDown(c.dispose);
      await c.select(['a']);
      final revisionBefore = c.revision;
      reads = 0;
      var notifications = 0;
      c.addListener(() => notifications++);

      await c.add('two');
      // Let the 100ms self-triggered refresh window elapse.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(store['a'], ['one', 'two']);
      expect(
        notifications,
        2,
        reason: 'optimistic chip + one notification when the edit settles',
      );
      expect(
        c.revision - revisionBefore,
        1,
        reason: 'one confirmation reload, no echo reload',
      );
      expect(reads, 2, reason: '1 read for the delta + 1 confirmation read');
    },
  );

  test('a change made elsewhere still refreshes the controller', () async {
    final store = <String, List<String>>{
      'a': ['one'],
    };
    final events = StreamController<String>.broadcast();
    addTearDown(events.close);
    final c = SelectionTagsController(
      read: (path) async => List.of(store[path]!),
      changes: events.stream,
    );
    addTearDown(c.dispose);
    await c.select(['a']);
    store['a'] = ['one', 'external'];
    events.add('preserve_scroll:a');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(c.tagsByPath['a'], ['one', 'external']);
  });
}
