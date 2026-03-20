import 'package:diacritic/diacritic.dart';

/// Utility functions for text processing
class TextUtils {
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
