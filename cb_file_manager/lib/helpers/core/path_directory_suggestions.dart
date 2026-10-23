import 'dart:io';
import 'package:cb_native/cb_native.dart';
import 'package:path/path.dart' as p;

Future<List<String>> suggestPathDirectories(
  String query, {
  int limit = 8,
  bool useNative = true,
}) async {
  if (limit <= 0) return [];
  final normalized = Platform.isWindows ? query.replaceAll('/', r'\') : query;
  final endsWithSeparator = normalized.endsWith(p.separator);
  final parent = endsWithSeparator ? normalized : p.dirname(normalized);
  final prefix = endsWithSeparator ? '' : p.basename(normalized);
  if (parent.isEmpty || parent == '.') return [];
  if (useNative) {
    final result = await NativeUiJobs.suggestDirectories(
      parent,
      prefix,
      limit: limit,
      caseInsensitive: Platform.isWindows,
    );
    if (result != null) return result;
  }
  final matches = <String>[];
  final key = Platform.isWindows ? prefix.toLowerCase() : prefix;
  try {
    await for (final entity in Directory(parent).list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path);
      if ((Platform.isWindows ? name.toLowerCase() : name).startsWith(key)) {
        matches.add(entity.path);
        if (matches.length >= limit) break;
      }
    }
  } on FileSystemException {
    return [];
  }
  return matches;
}
