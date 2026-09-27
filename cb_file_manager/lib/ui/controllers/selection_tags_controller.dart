import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/ui/widgets/tag_input_helpers.dart';

typedef ReadFileTags = Future<List<String>> Function(String path);
typedef WriteFileTags = Future<bool> Function(String path, List<String> tags);

/// Applies deltas to a captured selection, never replacing a batch with its
/// union of tags. The queue survives selection changes and widget disposal.
class SelectionTagsController extends ChangeNotifier {
  SelectionTagsController({
    ReadFileTags? read,
    WriteFileTags? write,
    void Function(String)? changed,
    Future<void> Function(String, List<String>)? createHierarchy,
    Stream<String>? changes,
  }) : _read = read ?? TagManager.getTags,
       _write =
           write ??
           ((path, tags) => TagManager.setTags(path, tags, notify: false)),
       _changed =
           changed ??
           ((path) =>
               TagManager.instance.notifyTagChanged('preserve_scroll:$path')),
       _createHierarchy =
           createHierarchy ??
           ((parent, children) async {
             final manager = TagHierarchyManager.instance;
             await manager.initialize();
             await createHierarchyRelationships(
               manager,
               parent,
               children,
               throwOnFailure: true,
             );
           }) {
    _subscription = (changes ?? TagManager.onTagChanged).listen((_) {
      _refreshTimer?.cancel();
      _refreshTimer = Timer(const Duration(milliseconds: 100), () {
        if (!saving) unawaited(reload());
      });
    });
  }

  final ReadFileTags _read;
  final WriteFileTags _write;
  final void Function(String) _changed;
  final Future<void> Function(String, List<String>) _createHierarchy;
  StreamSubscription<String>? _subscription;
  Timer? _refreshTimer;
  // Serialize inline writes across tabs and split panes as well.
  static Future<void>? _queue;
  bool _disposed = false;
  int _generation = 0;
  int revision = 0;
  int _pending = 0;
  List<String> paths = const [];
  Map<String, List<String>> tagsByPath = {};
  bool loading = false;
  Object? loadError;
  final List<TagEditFailure> failures = [];
  bool get saving => _pending > 0;

  static String normalize(String tag) => tag.trim().toLowerCase();

  Map<String, int> get counts {
    final names = <String, String>{};
    final counts = <String, int>{};
    for (final tags in tagsByPath.values) {
      for (final tag in tags) {
        names.putIfAbsent(normalize(tag), () => tag);
      }
      for (final tag in tags.map(normalize).toSet()) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final sorted = counts.keys.toList()..sort();
    return {for (final tag in sorted) names[tag]!: counts[tag]!};
  }

  bool isCommon(String tag) =>
      paths.isNotEmpty &&
      tagsByPath.length == paths.length &&
      tagsByPath.values.every(
        (tags) => tags.any((t) => normalize(t) == normalize(tag)),
      );

  Future<void> select(Iterable<String> selected) async {
    final next = selected.toSet().toList()..sort();
    if (listEquals(paths, next)) return;
    paths = List.unmodifiable(next);
    // Keep the previous tags on screen until the new ones load (the editor
    // dims and locks them meanwhile) so switching files does not flash.
    await reload();
  }

  Future<void> reload() async {
    if (_disposed) return;
    final generation = ++_generation;
    final selected = paths;
    loading = selected.isNotEmpty;
    loadError = null;
    _emit();
    final loaded = <String, List<String>>{};
    Object? error;
    for (final path in selected) {
      try {
        loaded[path] = await _read(path);
      } catch (e) {
        error = e;
      }
      if (_disposed || generation != _generation) return;
    }
    revision++;
    tagsByPath = loaded;
    loading = false;
    loadError = error;
    _emit();
  }

  Future<void> add(String input) {
    final value = input.trim();
    if (value.isEmpty || paths.isEmpty) return Future.value();
    final parsed = parseHierarchyInput(value);
    if (parsed != null && !parsed.isValid) return Future.value();
    final tags = parsed?.childNames ?? [value];
    return _enqueue(
      TagEditFailure(paths, tags, false, parent: parsed?.parentName),
    );
  }

  Future<void> remove(String tag) =>
      _enqueue(TagEditFailure(paths, [tag], true));

  Future<void> retry(TagEditFailure failure) {
    failures.remove(failure);
    return _enqueue(failure);
  }

  Future<void> _enqueue(TagEditFailure edit) {
    if (edit.paths.isEmpty) return Future.value();
    _pending++;
    _emit();
    final previous = _queue;
    final operation = previous == null
        ? Future<void>.microtask(() => _apply(edit))
        : previous.then((_) => _apply(edit));
    _queue = operation;
    // Release an idle queue rather than retaining a completed Future and its
    // originating zone (particularly important across widget-test lifetimes).
    unawaited(
      operation.whenComplete(() {
        if (identical(_queue, operation)) _queue = null;
      }),
    );
    return operation;
  }

  Future<void> _apply(TagEditFailure edit) async {
    final failed = <String>[];
    try {
      if (edit.parent != null) await _createHierarchy(edit.parent!, edit.tags);
      for (final path in edit.paths) {
        try {
          // Read at execution time so other tags, including edits from dialogs,
          // are preserved. Do not use the potentially stale panel snapshot.
          final current = await _read(path);
          final next = List<String>.from(current);
          for (final tag in edit.tags) {
            if (edit.remove) {
              next.removeWhere((t) => normalize(t) == normalize(tag));
            } else if (!next.any((t) => normalize(t) == normalize(tag))) {
              next.add(tag.trim());
            }
          }
          if (!listEquals(current, next)) {
            if (!await _write(path, next)) {
              failed.add(path);
              continue;
            }
            _changed(path);
          }
        } catch (_) {
          failed.add(path);
        }
      }
    } catch (_) {
      failed.addAll(edit.paths);
    } finally {
      if (failed.isNotEmpty) {
        failures.add(
          TagEditFailure(failed, edit.tags, edit.remove, parent: edit.parent),
        );
      }
      _pending--;
      if (!_disposed) await reload();
    }
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _refreshTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}

class TagEditFailure {
  TagEditFailure(
    Iterable<String> paths,
    Iterable<String> tags,
    this.remove, {
    this.parent,
  }) : paths = List.unmodifiable(paths),
       tags = List.unmodifiable(tags);
  final List<String> paths;
  final List<String> tags;
  final bool remove;
  final String? parent;
}
