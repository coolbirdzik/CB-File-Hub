/// Folder names of a Chromium or Electron user-data folder (browsers, VS
/// Code family editors, Slack, Discord, Teams and most Electron apps).
abstract final class ChromiumLayout {
  /// Web, script and GPU caches, rebuilt on the next launch.
  static const cacheFolders = {
    'cache',
    'code cache',
    'gpucache',
    'cacheddata',
    'dawncache',
    'dawngraphitecache',
    'dawnwebgpucache',
    'grshadercache',
    'shadercache',
    'graphitedawncache',
  };

  /// Storage of embedded web views. Holds sign-ins and app state: kept.
  static const webStorageFolders = {
    'webstorage',
    'service worker',
    'local storage',
    'session storage',
    'indexeddb',
    'partitions',
    'blob_storage',
    'shared_proto_db',
    'cookies',
    'cookies-journal',
  };

  /// Crashpad subfolders holding minidumps.
  static const crashReportFolders = {'completed', 'pending', 'reports'};

  /// A folder is a Chromium user-data folder when it holds one of the cache
  /// folders or `Crashpad`.
  static bool matches(Iterable<String> childNames) => childNames.any((name) {
    final lower = name.toLowerCase();
    return lower == 'crashpad' ||
        (lower != 'cache' && cacheFolders.contains(lower));
  });
}
