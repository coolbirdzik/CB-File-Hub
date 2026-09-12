import 'package:path/path.dart' as path;

/// Query rules shared by toolbar, mobile search and search dialogs.
abstract final class SearchQuery {
  /// A tag can contain spaces; another # starts the next tag.
  static List<String> tags(String query) =>
      RegExp(r'#([^\s#][^#]*?)(?=\s+#|\s*$)')
          .allMatches(query.trim())
          .map((match) => match.group(1)!.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList();

  /// Deleting a directory also removes its descendants from search results.
  static bool isRemovedPath(String candidate, Iterable<String> deletedPaths) =>
      deletedPaths.any(
        (deleted) =>
            path.equals(deleted, candidate) ||
            path.isWithin(deleted, candidate),
      );
}
