import 'package:diacritic/diacritic.dart';

/// Utility functions for text processing
class TextUtils {
  static final RegExp _combiningDiacritics = RegExp(
    r'[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\ufe20-\ufe2f]',
    unicode: true,
  );

  /// A-Z ordering that groups accented Latin names with their base letters.
  /// Handles both precomposed accents and combining diacritics without changing
  /// display names. Other scripts retain their Unicode ordering; this is not
  /// locale-specific collation. Original spelling breaks ties consistently.
  static int compareAlphabetically(String a, String b) {
    String sortKey(String value) => removeDiacritics(
      value.toLowerCase(),
    ).replaceAll(_combiningDiacritics, '');

    final result = sortKey(a).compareTo(sortKey(b));
    if (result != 0) return result;
    final spelling = a.toLowerCase().compareTo(b.toLowerCase());
    return spelling != 0 ? spelling : a.compareTo(b);
  }

  /// Produces the canonical form used by every user-facing search.
  ///
  /// Accented and decomposed Unicode characters are folded to their base
  /// forms, then compared case-insensitively. For example, both `chào` and
  /// `cha\u0300o` become `chao`.
  static String normalizeForSearch(String value) {
    return removeDiacritics(
      value.toLowerCase(),
    ).replaceAll(_combiningDiacritics, '');
  }

  /// Persistable search key with the same separator rules as [matchesSearch].
  static String searchKey(String value) =>
      _cleanString(normalizeForSearch(value));

  /// Fuzzy Unicode search used by every user-facing search surface.
  /// Supports partial matching, word order independence, and special characters
  ///
  /// Examples:
  /// - "bo nao" matches "bổ não" (Vietnamese)
  /// - "cafe" matches "café" (French)
  /// - "uber" matches "über" (German)
  /// - "hello world" matches "world hello" (word order)
  /// - "test_file" matches "test file" (special chars)
  static bool matchesSearch(String text, String query) {
    final cleanText = searchKey(text);
    final queryWords = searchWords(query);

    // No words means the cleaned query is empty, which every text contains.
    if (queryWords.isEmpty) return true;

    // Check if all query words exist in text (order independent)
    return queryWords.every((word) => cleanText.contains(word));
  }

  /// The words [matchesSearch] requires, each already a [searchKey]. A text
  /// matches when its [searchKey] contains all of them; the native search
  /// (package:cb_native) receives exactly this list.
  static List<String> searchWords(String query) => searchKey(
    query,
  ).split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList();

  /// Backwards-compatible name for older file-search callers.
  static bool matchesVietnamese(String text, String query) =>
      matchesSearch(text, query);

  /// Clean string by replacing special characters with spaces
  /// This allows matching "test_file" with "test file"
  static String _cleanString(String text) {
    return text
        .replaceAll(RegExp(r'[_\-\.\(\)\[\]\{\}]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
