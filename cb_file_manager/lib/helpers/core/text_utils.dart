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

  /// Fuzzy search with diacritic normalization for all languages
  /// Supports partial matching, word order independence, and special characters
  ///
  /// Examples:
  /// - "bo nao" matches "bổ não" (Vietnamese)
  /// - "cafe" matches "café" (French)
  /// - "uber" matches "über" (German)
  /// - "hello world" matches "world hello" (word order)
  /// - "test_file" matches "test file" (special chars)
  static bool matchesVietnamese(String text, String query) {
    // Normalize both text and query (remove diacritics, lowercase)
    final normalizedText = removeDiacritics(text.toLowerCase());
    final normalizedQuery = removeDiacritics(query.toLowerCase());

    // Remove special characters for better matching
    final cleanText = _cleanString(normalizedText);
    final cleanQuery = _cleanString(normalizedQuery);

    // Split query into words for flexible matching
    final queryWords = cleanQuery
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    // If no words, do simple contains check
    if (queryWords.isEmpty) {
      return cleanText.contains(cleanQuery);
    }

    // Check if all query words exist in text (order independent)
    return queryWords.every((word) => cleanText.contains(word));
  }

  /// Clean string by replacing special characters with spaces
  /// This allows matching "test_file" with "test file"
  static String _cleanString(String text) {
    return text
        .replaceAll(RegExp(r'[_\-\.\(\)\[\]\{\}]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
