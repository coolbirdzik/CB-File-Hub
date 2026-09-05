import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A class that represents tab data in the file manager
class TabData {
  /// The unique identifier for this tab
  final String id;

  /// The display name of the tab (usually the folder name)
  final String name;

  /// The current path being displayed in the tab
  final String path;

  /// Icon to display in the tab
  final IconData? icon;

  /// Whether the tab is pinned
  final bool isPinned;

  /// Whether the tab is currently performing a background task (e.g. loading)
  final bool isLoading;

  /// Navigation history for this tab
  final List<String> navigationHistory;

  /// Forward navigation history for this tab
  final List<String> forwardHistory;

  /// Navigator key for this tab to maintain separate navigation state
  final GlobalKey<NavigatorState> navigatorKey;

  /// RepaintBoundary key for capturing screenshots
  final GlobalKey repaintBoundaryKey;

  /// Thumbnail screenshot of the tab content
  final Uint8List? thumbnail;

  /// Timestamp when thumbnail was captured
  final DateTime? thumbnailCapturedAt;

  /// File name to highlight/scroll to when tab opens
  final String? highlightedFileName;

  /// Path shown in the right-hand pane when split view is active.
  /// null means single-pane mode.
  final String? splitPanePath;

  /// Full navigation state for the right-hand split pane.
  /// Kept in sync with [splitPanePath] — set when split opens, cleared on close.
  final TabData? splitPaneTabData;

  TabData({
    required this.id,
    required this.name,
    required this.path,
    this.icon,
    this.isPinned = false,
    this.isLoading = false,
    List<String>? navigationHistory,
    List<String>? forwardHistory,
    GlobalKey<NavigatorState>? navigatorKey,
    GlobalKey? repaintBoundaryKey,
    this.thumbnail,
    this.thumbnailCapturedAt,
    this.highlightedFileName,
    this.splitPanePath,
    this.splitPaneTabData,
  }) : navigationHistory = navigationHistory ?? [path],
       forwardHistory = forwardHistory ?? <String>[],
       navigatorKey = navigatorKey ?? GlobalKey<NavigatorState>(),
       repaintBoundaryKey = repaintBoundaryKey ?? GlobalKey();

  /// Create a copy of this tab with some properties changed
  TabData copyWith({
    String? name,
    String? path,
    IconData? icon,
    bool? isPinned,
    bool? isLoading,
    List<String>? navigationHistory,
    List<String>? forwardHistory,
    GlobalKey<NavigatorState>? navigatorKey,
    GlobalKey? repaintBoundaryKey,
    Uint8List? thumbnail,
    DateTime? thumbnailCapturedAt,
    bool clearThumbnail = false,
    String? highlightedFileName,
    bool clearHighlightedFile = false,
    String? splitPanePath,
    bool clearSplitPane = false,
    TabData? splitPaneTabData,
  }) {
    return TabData(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      icon: icon ?? this.icon,
      isPinned: isPinned ?? this.isPinned,
      isLoading: isLoading ?? this.isLoading,
      navigationHistory: navigationHistory ?? this.navigationHistory,
      forwardHistory: forwardHistory ?? this.forwardHistory,
      navigatorKey: navigatorKey ?? this.navigatorKey,
      repaintBoundaryKey: repaintBoundaryKey ?? this.repaintBoundaryKey,
      thumbnail: clearThumbnail ? null : (thumbnail ?? this.thumbnail),
      thumbnailCapturedAt: clearThumbnail
          ? null
          : (thumbnailCapturedAt ?? this.thumbnailCapturedAt),
      highlightedFileName: clearHighlightedFile
          ? null
          : (highlightedFileName ?? this.highlightedFileName),
      splitPanePath: clearSplitPane
          ? null
          : (splitPanePath ?? this.splitPanePath),
      splitPaneTabData: clearSplitPane
          ? null
          : (splitPaneTabData ?? this.splitPaneTabData),
    );
  }

  /// Update the path of this tab
  void updatePath(String newPath) {
    if (newPath != path) {
      // Check if we're navigating to a path we've already been to
      final existingIndex = navigationHistory.indexOf(newPath);
      if (existingIndex != -1 &&
          existingIndex != navigationHistory.length - 1) {
        // If we're going back to a previous path, add current path to forwardHistory
        forwardHistory.add(path);

        // Remove all paths after the one we're navigating to from backward history
        navigationHistory.removeRange(
          existingIndex + 1,
          navigationHistory.length,
        );
      } else {
        // Only add the new path to history if it's different from the last path in history
        if (navigationHistory.isEmpty || navigationHistory.last != newPath) {
          navigationHistory.add(newPath);
        }

        // Clear forward history since we're navigating to a new path
        forwardHistory.clear();

        // Trim history if it gets too long (optional)
        if (navigationHistory.length > 30) {
          navigationHistory.removeAt(0);
        }
      }
    }
  }

  /// Check if navigation back is possible
  bool canNavigateBack() {
    return navigationHistory.length > 1;
  }

  /// Get the previous path in the navigation history
  String? getPreviousPath() {
    if (navigationHistory.length > 1) {
      return navigationHistory[navigationHistory.length - 2];
    }
    return null;
  }

  /// Navigate back in the navigation history
  /// Returns the previous path if successful, null otherwise
  String? navigateBack() {
    if (canNavigateBack()) {
      // Add current path to forward history before going back
      forwardHistory.add(path);

      // Remove current path
      navigationHistory.removeLast();

      // Check if the new current path is the same as the one we just removed
      // If so, keep going back until we find a different path
      String? previousPath = path;
      while (navigationHistory.length > 1 &&
          navigationHistory.last == previousPath) {
        debugPrint(
          'TabData: Removing duplicate path from history: ${navigationHistory.last}',
        );
        previousPath = navigationHistory.last;
        navigationHistory.removeLast();
      }

      // Return the new current path (which was the previous one)
      return navigationHistory.isNotEmpty ? navigationHistory.last : null;
    }
    return null;
  }

  /// Check if navigation forward is possible
  bool canNavigateForward() {
    return forwardHistory.isNotEmpty;
  }

  /// Get the next path in the forward navigation history
  String? getNextPath() {
    if (forwardHistory.isNotEmpty) {
      return forwardHistory.last;
    }
    return null;
  }

  /// Navigate forward in the navigation history
  /// Returns the next path if successful, null otherwise
  String? navigateForward() {
    if (canNavigateForward()) {
      // Get the next path
      final nextPath = forwardHistory.last;

      // Remove it from forward history
      forwardHistory.removeLast();

      // Add it to navigation history
      navigationHistory.add(nextPath);

      return nextPath;
    }
    return null;
  }
}
