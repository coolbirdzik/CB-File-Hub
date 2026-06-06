/// Utility functions for safe URI operations
class UriUtils {
  /// Safely decode a URI component with fallback to original string
  static String safeDecodeComponent(String encoded) {
    try {
      return Uri.decodeComponent(encoded);
    } catch (e) {
      // If decoding fails, return the original string
      return encoded;
    }
  }

  /// Safely encode a URI component
  static String safeEncodeComponent(String decoded) {
    try {
      return Uri.encodeComponent(decoded);
    } catch (e) {
      // If encoding fails, return the original string
      return decoded;
    }
  }

  /// Build a tag search path with proper encoding.
  static String buildTagSearchPath(String tag) {
    return '#search?tag=${safeEncodeComponent(tag)}';
  }

  /// Extract the tag from a #search?tag=... path, if present.
  /// Returns null when the path doesn't contain a valid tag.
  static String? extractTagFromSearchPath(String path) {
    if (!path.startsWith('#search?')) return null;

    final query = path.substring('#search?'.length);
    if (query.isEmpty) return null;

    try {
      final params = Uri.splitQueryString(query);
      final tag = params['tag'];
      if (tag != null && tag.isNotEmpty) {
        return tag;
      }
    } catch (_) {
      // Fall back below for non-standard query strings.
    }

    return null;
  }
}
