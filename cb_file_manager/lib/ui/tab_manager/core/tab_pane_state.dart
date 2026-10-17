/// In-memory preview/properties pane visibility for each tab.
///
/// A toggle sticks for the tab's whole lifetime: navigating to another folder
/// (or a system screen and back) keeps it, and closing the tab drops it. It is
/// never persisted; a new tab starts from the stored defaults.
class TabPaneState {
  TabPaneState._();

  static final Map<String, bool> _previewVisible = {};
  static final Map<String, bool> _propertiesVisible = {};

  static bool? previewVisible(String tabId) => _previewVisible[tabId];

  static void setPreviewVisible(String tabId, bool visible) {
    _previewVisible[tabId] = visible;
  }

  static bool? propertiesVisible(String tabId) => _propertiesVisible[tabId];

  static void setPropertiesVisible(String tabId, bool visible) {
    _propertiesVisible[tabId] = visible;
  }

  /// Drops state of tabs that are no longer open. A split view's right pane
  /// uses `<tabId>_split` and lives as long as its tab.
  static void retainTabs(Set<String> openTabIds) {
    bool isOpen(String key) {
      if (openTabIds.contains(key)) return true;
      const splitSuffix = '_split';
      return key.endsWith(splitSuffix) &&
          openTabIds.contains(
            key.substring(0, key.length - splitSuffix.length),
          );
    }

    _previewVisible.removeWhere((key, _) => !isOpen(key));
    _propertiesVisible.removeWhere((key, _) => !isOpen(key));
  }

  static void clearAll() {
    _previewVisible.clear();
    _propertiesVisible.clear();
  }
}
