import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/utils/app_logger.dart';

/// Manages parent-child tag relationships.
///
/// Eager singleton (like [TagColorManager]). The full hierarchy is cached
/// in-memory as two maps:
///   * _parentToChildren : parent → [child, ...]
///   * _childToParents   : child  → [parent, ...]
///
/// Circular references are prevented via DFS before every [addChild] call.
class TagHierarchyManager {
  static final TagHierarchyManager instance = TagHierarchyManager._internal();

  TagHierarchyManager._internal();

  // ── In-memory cache ──────────────────────────────────────────────────────
  /// parent normalizedTag → list of child normalizedTags
  final Map<String, List<String>> _parentToChildren = {};

  /// child normalizedTag → list of parent normalizedTags
  final Map<String, List<String>> _childToParents = {};

  bool _cacheLoaded = false;

  // ── Change notification ──────────────────────────────────────────────────
  final StreamController<void> _changeController =
      StreamController<void>.broadcast();

  /// Fires whenever any hierarchy relationship changes.
  Stream<void> get onHierarchyChanged => _changeController.stream;

  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Load the full hierarchy from the database. Safe to call multiple times.
  Future<void> initialize() async {
    if (_cacheLoaded) return;
    try {
      final db = DatabaseManager.getInstance();
      if (!db.isInitialized()) await db.initialize();
      final all = await db.getAllTagHierarchy();

      _parentToChildren.clear();
      _childToParents.clear();

      for (final entry in all.entries) {
        final parent = entry.key;
        for (final child in entry.value) {
          _parentToChildren.putIfAbsent(parent, () => <String>[]).add(child);
          _childToParents.putIfAbsent(child, () => <String>[]).add(parent);
        }
      }
      _cacheLoaded = true;
      AppLogger.info(
        '[TagHierarchyManager] Loaded hierarchy',
        error:
            'parents=${_parentToChildren.length} relationships=${all.values.fold<int>(0, (s, l) => s + l.length)}',
      );
    } catch (e) {
      AppLogger.error('[TagHierarchyManager] initialize failed', error: e);
    }
  }

  /// Add a parent-child relationship.
  ///
  /// Returns `false` if the relationship would create a circular reference or
  /// the database write fails.
  Future<bool> addChild(String parentTag, String childTag) async {
    final parent = _normalize(parentTag);
    final child = _normalize(childTag);

    if (parent == child) return false;
    if (_wouldCreateCycle(parent, child)) {
      AppLogger.warning(
        '[TagHierarchyManager] Circular reference detected',
        error: 'parent=$parent child=$child',
      );
      return false;
    }

    // Already exists?
    final existing = _parentToChildren[parent];
    if (existing != null && existing.contains(child)) return true;

    try {
      final db = DatabaseManager.getInstance();
      final ok = await db.setTagHierarchy(parent, child);
      if (ok) {
        _parentToChildren.putIfAbsent(parent, () => <String>[]).add(child);
        _childToParents.putIfAbsent(child, () => <String>[]).add(parent);
        _changeController.add(null);
        _notifyListeners();
      }
      return ok;
    } catch (e) {
      AppLogger.error('[TagHierarchyManager] addChild failed', error: e);
      return false;
    }
  }

  /// Remove a parent-child relationship.
  Future<bool> removeChild(String parentTag, String childTag) async {
    final parent = _normalize(parentTag);
    final child = _normalize(childTag);

    try {
      final db = DatabaseManager.getInstance();
      final ok = await db.removeTagHierarchy(parent, child);
      if (ok) {
        _parentToChildren[parent]?.remove(child);
        if (_parentToChildren[parent]?.isEmpty ?? false) {
          _parentToChildren.remove(parent);
        }
        _childToParents[child]?.remove(parent);
        if (_childToParents[child]?.isEmpty ?? false) {
          _childToParents.remove(child);
        }
        _changeController.add(null);
        _notifyListeners();
      }
      return ok;
    } catch (e) {
      AppLogger.error('[TagHierarchyManager] removeChild failed', error: e);
      return false;
    }
  }

  /// Remove ALL hierarchy relationships involving [tag] (as parent or child).
  Future<bool> removeAllForTag(String tag) async {
    final normalized = _normalize(tag);
    try {
      final db = DatabaseManager.getInstance();
      final ok = await db.removeAllHierarchyForTag(normalized);
      if (ok) {
        // Remove as parent
        final children = _parentToChildren.remove(normalized);
        if (children != null) {
          for (final child in children) {
            _childToParents[child]?.remove(normalized);
            if (_childToParents[child]?.isEmpty ?? false) {
              _childToParents.remove(child);
            }
          }
        }
        // Remove as child
        final parents = _childToParents.remove(normalized);
        if (parents != null) {
          for (final parent in parents) {
            _parentToChildren[parent]?.remove(normalized);
            if (_parentToChildren[parent]?.isEmpty ?? false) {
              _parentToChildren.remove(parent);
            }
          }
        }
        _changeController.add(null);
        _notifyListeners();
      }
      return ok;
    } catch (e) {
      AppLogger.error('[TagHierarchyManager] removeAllForTag failed', error: e);
      return false;
    }
  }

  /// Get children of [parentTag] (normalized tag names).
  List<String> getChildren(String parentTag) {
    return List.unmodifiable(
      _parentToChildren[_normalize(parentTag)] ?? const <String>[],
    );
  }

  /// Get parents of [childTag] (normalized tag names).
  List<String> getParents(String childTag) {
    return List.unmodifiable(
      _childToParents[_normalize(childTag)] ?? const <String>[],
    );
  }

  /// Returns `true` if [tag] has any children.
  bool isParent(String tag) =>
      _parentToChildren[_normalize(tag)]?.isNotEmpty ?? false;

  /// Returns `true` if [tag] has any parents.
  bool isChild(String tag) =>
      _childToParents[_normalize(tag)]?.isNotEmpty ?? false;

  /// Full hierarchy tree: parent → [children].
  Map<String, List<String>> getHierarchyTree() =>
      Map.unmodifiable(_parentToChildren);

  /// Returns tags that are root parents (have children but no parents).
  List<String> getRootParents() {
    return _parentToChildren.keys
        .where((p) => !(_childToParents[p]?.isNotEmpty ?? false))
        .toList(growable: false);
  }

  /// Returns tags that are standalone (no parents and no children).
  bool isStandalone(String tag) {
    final n = _normalize(tag);
    return !isParent(n) && !isChild(n);
  }

  /// Clear the in-memory cache. Next access will reload from DB.
  void clearCache() {
    _parentToChildren.clear();
    _childToParents.clear();
    _cacheLoaded = false;
  }

  // ── Circular reference detection (DFS) ───────────────────────────────────

  /// Returns `true` if adding parent→child would create a cycle.
  ///
  /// A cycle exists if [parent] is reachable from [child] by following
  /// existing parent→child edges. In other words, [child] is already an
  /// ancestor of [parent].
  bool _wouldCreateCycle(String parent, String child) {
    // If child→...→parent path exists, adding parent→child creates a cycle.
    final visited = <String>{};
    return _dfsReaches(child, parent, visited);
  }

  /// DFS: can we reach [target] starting from [current] by following
  /// parentToChildren edges?
  bool _dfsReaches(String current, String target, Set<String> visited) {
    if (current == target) return true;
    if (!visited.add(current)) return false; // already visited

    final children = _parentToChildren[current];
    if (children == null) return false;

    for (final child in children) {
      if (_dfsReaches(child, target, visited)) return true;
    }
    return false;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _normalize(String tag) => tag.trim().toLowerCase();
}
