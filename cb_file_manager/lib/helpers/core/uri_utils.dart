/// Converts a virtual network folder path to the address shown in the UI.
String networkAddress(String path, {bool includeUserInfo = true}) {
  if (!path.startsWith('#network/')) return path;
  final parts = path.split('/');
  if (parts.length < 3 || parts[2].isEmpty) return path;
  try {
    final protocol = parts[1].toLowerCase();
    var authority = Uri.decodeComponent(parts[2]);
    if (!includeUserInfo) {
      authority = authority.substring(authority.lastIndexOf('@') + 1);
    }
    if (protocol == 'sftp') {
      return Uri.parse(
        'sftp://$authority',
      ).replace(pathSegments: ['', ...parts.skip(3)]).toString();
    }
    return '$protocol://$authority/${parts.skip(3).join('/')}';
  } on FormatException {
    return path;
  }
}

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

  /// Returns `true` when [path] is a tag-search path (`#search?tag=...`).
  ///
  /// A tag is conceptually a folder in this app, so tag-search paths are used
  /// both to open a tag tab and to represent a child tag as a virtual folder
  /// inside a parent tag's result grid.
  static bool isTagSearchPath(String path) =>
      extractTagFromSearchPath(path) != null;

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
