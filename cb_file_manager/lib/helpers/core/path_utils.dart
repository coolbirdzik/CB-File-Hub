/// Common path utilities used across helpers
library path_utils;

/// Replace characters that are not allowed in file names with '_'.
String sanitizePath(String path) {
  return path.replaceAll(RegExp(r'[<>:"|?*]'), '_');
}

/// Convert a "#network/smb/" style tab path to a Windows UNC path.
/// Example: "#network/smb/server/share/folder/file.jpg" → "\\\\server\\share\\folder\\file.jpg".
/// If the input is already a UNC path or not an SMB tab path, it is returned unchanged.
String smbTabPathToUNC(String tabPath) {
  if (tabPath.startsWith('\\\\')) return tabPath; // already UNC
  const prefix = '#network/smb/';
  final lower = tabPath.toLowerCase();
  if (!lower.startsWith(prefix)) return tabPath;

  final without = tabPath.substring(prefix.length);
  final segments = without.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return tabPath;

  final host = Uri.decodeComponent(segments[0]);
  final share = segments.length > 1 ? Uri.decodeComponent(segments[1]) : '';
  final sub = segments.length > 2
      ? segments.sublist(2).map(Uri.decodeComponent).join('\\')
      : '';

  final buffer = StringBuffer('\\\\')..write(host);
  if (share.isNotEmpty) {
    buffer
      ..write('\\')
      ..write(share);
  }
  if (sub.isNotEmpty) {
    buffer
      ..write('\\')
      ..write(sub);
  }
  return buffer.toString();
}
