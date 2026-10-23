import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:cb_native/cb_native.dart';
import 'package:path/path.dart' as p;
import '../helpers/files/file_type_registry.dart';
import 'album_auto_rule_service.dart';

/// Snapshot rules once, then stream paths from native workers (or an isolate
/// for Dart regex rules). Both routes are cancellable.
class SmartAlbumScanner {
  static Future<void> scan({
    required List<String> roots,
    required List<AlbumAutoRule> rules,
    required void Function(List<String>) onBatch,
    required bool Function() shouldContinue,
    void Function(int processed, int matched)? onProgress,
    bool useNative = true,
  }) async {
    final active = [
      for (final r in rules)
        if (r.isActive) (r.condition.index, r.pattern),
    ];
    final extensions = [
      ...FileTypeRegistry.getExtensionsForCategory(FileCategory.image),
      ...FileTypeRegistry.getExtensionsForCategory(FileCategory.video),
    ];
    if (!shouldContinue()) return;
    if (useNative) {
      final handled = await NativeUiJobs.scanSmartAlbum(
        roots: roots,
        extensions: extensions,
        rules: active,
        onBatch: onBatch,
        shouldContinue: shouldContinue,
        onProgress: onProgress,
      );
      if (handled != null || !shouldContinue()) return;
    }
    final port = ReceivePort();
    final done = Completer<void>();
    final subscription = port.listen((dynamic message) {
      if (message is List && message.first == 'batch' && shouldContinue()) {
        final paths = (message[1] as List).cast<String>();
        if (paths.isNotEmpty) onBatch(paths);
        onProgress?.call(message[2] as int, message[3] as int);
      } else if (message == 'done') {
        if (!done.isCompleted) done.complete();
      } else if ((message == null || message == 'exit') && !done.isCompleted) {
        done.completeError(
          StateError('Smart album worker exited before completion'),
        );
      } else if (message is List &&
          message.first != 'batch' &&
          !done.isCompleted) {
        done.completeError(
          StateError('Smart album scan failed: ${message.first}'),
        );
      }
    });
    Isolate? worker;
    Timer? timer;
    try {
      worker = await Isolate.spawn(
        _scan,
        (port.sendPort, roots, extensions, active),
        onExit: port.sendPort,
        onError: port.sendPort,
      );
      // onExit sends null; normal completion sends 'done' first.
      timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!shouldContinue() && !done.isCompleted) {
          worker?.kill(priority: Isolate.immediate);
          done.complete();
        }
      });
      await done.future;
    } finally {
      timer?.cancel();
      worker?.kill(priority: Isolate.immediate);
      await subscription.cancel();
      port.close();
    }
  }

  static void _scan(
    (SendPort, List<String>, List<String>, List<(int, String)>) args,
  ) {
    final (port, roots, extensions, rawRules) = args;
    final rules = [
      for (final (kind, pattern) in rawRules) _Rule(kind, pattern),
    ];
    final allowed = extensions.toSet();
    final stack = [...roots.reversed];
    var processed = 0, matched = 0;
    var batch = <String>[];
    void flush() {
      port.send(['batch', batch, processed, matched]);
      batch = [];
    }

    while (stack.isNotEmpty) {
      final root = stack.removeLast();
      try {
        for (final entry in Directory(root).listSync(followLinks: false)) {
          if (entry is Directory) {
            stack.add(entry.path);
            continue;
          }
          if (entry is! File) continue;
          processed++;
          final name = p.basename(entry.path);
          final dot = name.lastIndexOf('.');
          if (dot >= 0 && allowed.contains(name.substring(dot).toLowerCase())) {
            final base = p.basenameWithoutExtension(name).toLowerCase();
            if (rules.isEmpty || rules.any((r) => r.matches(base))) {
              batch.add(entry.path);
              matched++;
            }
          }
          if (batch.length >= 64 || processed % 256 == 0) flush();
        }
      } on FileSystemException {
        /* Match the view's previous best-effort walk. */
      }
    }
    flush();
    port.send('done');
  }
}

class _Rule {
  _Rule(this.kind, String pattern) : pattern = pattern.toLowerCase() {
    if (kind == RuleCondition.regex.index) {
      try {
        regex = RegExp(pattern, caseSensitive: false);
      } on FormatException {
        regex = null;
      }
    }
  }
  final int kind;
  final String pattern;
  RegExp? regex;
  bool matches(String name) => switch (kind) {
    0 => name.contains(pattern),
    1 => name.startsWith(pattern),
    2 => name.endsWith(pattern),
    3 => name == pattern,
    4 => regex?.hasMatch(name) ?? false,
    _ => false,
  };
}
