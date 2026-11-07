import 'dart:io';
import 'package:path/path.dart' as p;

/// Standalone Dart for subprocess protocol fixtures, independent of PATH/batch
/// wrappers. flutter_tester lives beneath the same engine cache as dart-sdk.
String dartExecutable() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (true) {
    final candidate = File(
      p.join(
        dir.path,
        'dart-sdk',
        'bin',
        Platform.isWindows ? 'dart.exe' : 'dart',
      ),
    );
    if (candidate.existsSync()) return candidate.path;
    if (dir.parent.path == dir.path) throw StateError('Dart SDK not found');
    dir = dir.parent;
  }
}
