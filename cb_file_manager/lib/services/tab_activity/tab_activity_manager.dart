import 'dart:async';

import 'package:flutter/foundation.dart';

/// Activity state for a tab. Used for prioritization and lifecycle hints.
enum TabActivityState {
  /// Tab is currently visible/active and used by the user.
  focused,

  /// Tab is open but not focused. Background work may continue at lower priority.
  backgroundActive,

  /// Tab has been left untouched longer than [TabActivityManager.inactiveThreshold].
  /// Aggressive cache release is performed and a reload is required when refocused.
  inactive,
}

/// Internal record holding per-tab activity metadata.
class _TabActivityRecord {
  TabActivityState state;
  DateTime lastFocusedAt;
  DateTime lastInteractionAt;
  DateTime? inactiveSince;
  bool needsReload;
  String? lastKnownPath;

  /// When true, this tab is excluded from automatic inactive transitions and
  /// from manual [TabActivityManager.markInactive]. Set by user via the tab
  /// context menu ("Keep tab always active"). Session-only — defaults to
  /// false on app restart.
  bool alwaysActive;

  _TabActivityRecord({
    required this.state,
    required this.lastFocusedAt,
    required this.lastInteractionAt,
    this.lastKnownPath,
  })  : inactiveSince = null,
        needsReload = false,
        alwaysActive = false;
}

/// Snapshot of a tab's activity, exposed for UI/diagnostics.
@immutable
class TabActivitySnapshot {
  final String tabId;
  final TabActivityState state;
  final DateTime lastFocusedAt;
  final DateTime lastInteractionAt;
  final DateTime? inactiveSince;
  final bool needsReload;

  const TabActivitySnapshot({
    required this.tabId,
    required this.state,
    required this.lastFocusedAt,
    required this.lastInteractionAt,
    required this.inactiveSince,
    required this.needsReload,
  });

  bool get isInactive => state == TabActivityState.inactive;
  bool get isFocused => state == TabActivityState.focused;
}

/// Listener invoked when a tab transitions to inactive. Implementations
/// should release tab-scoped caches/queues for [tabId] and [path].
typedef TabInactiveListener = void Function(String tabId, String? path);

/// Listener invoked when a tab is closed. Implementations should release
/// any per-tab resources they hold.
typedef TabClosedListener = void Function(String tabId, String? path);

/// Coordinates per-tab activity state for the tabbed folder shell.
///
/// Behavior summary:
/// - Tab unused for [inactiveThreshold] becomes [TabActivityState.inactive].
/// - Inactive tabs trigger registered cache-release listeners so RAM can be reclaimed.
/// - Refocusing an inactive tab marks it as needing a reload (consumed once).
/// - Focused tab is the highest-priority tab; background tabs are deprioritized.
///
/// This manager is process-local. Tabs do not run in separate processes
/// or isolates; isolation is purely a scheduling/lifecycle concept.
class TabActivityManager extends ChangeNotifier {
  /// Default inactive threshold (used when no preference has been loaded yet).
  static const Duration defaultInactiveThreshold = Duration(hours: 1);

  /// How often the periodic timer evaluates background tabs.
  static const Duration evaluationInterval = Duration(minutes: 1);

  final DateTime Function() _now;
  final Map<String, _TabActivityRecord> _records =
      <String, _TabActivityRecord>{};
  final List<TabInactiveListener> _inactiveListeners = <TabInactiveListener>[];
  final List<TabClosedListener> _closedListeners = <TabClosedListener>[];

  /// The currently active threshold. Mutable so user preferences can change it
  /// at runtime. Set to [Duration.zero] to disable auto-suspend entirely.
  Duration _inactiveThreshold = defaultInactiveThreshold;

  String? _focusedTabId;
  Timer? _evaluationTimer;
  bool _disposed = false;

  TabActivityManager({
    DateTime Function()? clock,
    Duration? initialThreshold,
  }) : _now = clock ?? DateTime.now {
    if (initialThreshold != null) {
      _inactiveThreshold = initialThreshold;
    }
  }

  /// The currently active inactive threshold.
  /// [Duration.zero] disables auto-suspend.
  Duration get inactiveThreshold => _inactiveThreshold;

  /// Whether auto-suspend is enabled (threshold > 0).
  bool get isAutoSuspendEnabled => _inactiveThreshold > Duration.zero;

  /// Update the inactive threshold at runtime. Pass [Duration.zero] to
  /// disable auto-suspend. The change takes effect on the next periodic
  /// evaluation cycle, but a manual [evaluateInactiveTabs] call will
  /// already use the new value.
  ///
  /// If [revivePreviouslyInactive] is true, any tab that was inactive but
  /// would no longer qualify under the new threshold is promoted back to
  /// background and its reload flag is preserved so the tab still reloads
  /// the next time it gets focus.
  void setInactiveThreshold(
    Duration value, {
    bool revivePreviouslyInactive = true,
  }) {
    if (_disposed) return;
    if (value.isNegative) value = Duration.zero;
    if (value == _inactiveThreshold) return;
    _inactiveThreshold = value;

    if (!isAutoSuspendEnabled && revivePreviouslyInactive) {
      // Threshold was turned off: nothing to evaluate, but mark currently
      // inactive tabs as background so their UI indicator clears.
      var changed = false;
      for (final entry in _records.entries) {
        final r = entry.value;
        if (r.state == TabActivityState.inactive) {
          r.state = (entry.key == _focusedTabId)
              ? TabActivityState.focused
              : TabActivityState.backgroundActive;
          r.inactiveSince = null;
          changed = true;
        }
      }
      if (changed) notifyListeners();
      return;
    }

    notifyListeners();
  }

  /// Register a callback fired when any tab transitions to inactive.
  void addInactiveListener(TabInactiveListener listener) {
    _inactiveListeners.add(listener);
  }

  void removeInactiveListener(TabInactiveListener listener) {
    _inactiveListeners.remove(listener);
  }

  /// Register a callback fired when a tab is closed (any state).
  void addClosedListener(TabClosedListener listener) {
    _closedListeners.add(listener);
  }

  void removeClosedListener(TabClosedListener listener) {
    _closedListeners.remove(listener);
  }

  /// Start the periodic background timer that evaluates inactivity.
  /// Safe to call multiple times.
  void startPeriodicEvaluation() {
    if (_disposed) return;
    _evaluationTimer?.cancel();
    _evaluationTimer = Timer.periodic(evaluationInterval, (_) {
      evaluateInactiveTabs();
    });
  }

  /// Stop periodic evaluation. Used in tests and on shutdown.
  void stopPeriodicEvaluation() {
    _evaluationTimer?.cancel();
    _evaluationTimer = null;
  }

  /// Currently focused tab id, or null if none.
  String? get focusedTabId => _focusedTabId;

  /// Returns whether [tabId] is currently inactive.
  bool isInactive(String tabId) {
    final r = _records[tabId];
    return r != null && r.state == TabActivityState.inactive;
  }

  /// Returns whether [tabId] is pinned as always-active and excluded from
  /// automatic inactive transitions.
  bool isAlwaysActive(String tabId) {
    final r = _records[tabId];
    return r != null && r.alwaysActive;
  }

  /// Set the always-active pin for [tabId].
  ///
  /// When [value] is true the tab is excluded from
  /// [evaluateInactiveTabs] and [markInactive]. If the tab was already
  /// inactive at the moment of pinning it is promoted back to background
  /// (or focused, if it is the currently focused tab) and the reload flag
  /// is preserved so the existing refocus pipeline still runs the next
  /// time the user clicks the tab.
  ///
  /// State is in-memory only (session-scoped). Listeners are notified once
  /// per change.
  void setAlwaysActive(String tabId, bool value) {
    if (_disposed) return;
    final r = _records[tabId];
    if (r == null) return;
    if (r.alwaysActive == value) return;
    r.alwaysActive = value;

    if (value && r.state == TabActivityState.inactive) {
      r.state = (tabId == _focusedTabId)
          ? TabActivityState.focused
          : TabActivityState.backgroundActive;
      r.inactiveSince = null;
    }
    notifyListeners();
  }

  /// Returns whether [tabId] needs a reload.
  bool needsReload(String tabId) {
    final r = _records[tabId];
    return r != null && r.needsReload;
  }

  /// Returns the activity state for [tabId], or null if unknown.
  TabActivityState? stateOf(String tabId) => _records[tabId]?.state;

  /// Returns a snapshot for [tabId], or null if unknown.
  TabActivitySnapshot? snapshotOf(String tabId) {
    final r = _records[tabId];
    if (r == null) return null;
    return TabActivitySnapshot(
      tabId: tabId,
      state: r.state,
      lastFocusedAt: r.lastFocusedAt,
      lastInteractionAt: r.lastInteractionAt,
      inactiveSince: r.inactiveSince,
      needsReload: r.needsReload,
    );
  }

  /// Number of tracked tabs (for diagnostics/tests).
  int get trackedTabCount => _records.length;

  /// Mark a tab as focused. Other tracked tabs are demoted to background.
  /// If the tab was inactive, it is promoted and a reload is required.
  void onTabFocused(String tabId, {String? path}) {
    if (_disposed) return;
    final now = _now();

    // Demote previously focused tab.
    if (_focusedTabId != null && _focusedTabId != tabId) {
      final prev = _records[_focusedTabId!];
      if (prev != null && prev.state == TabActivityState.focused) {
        prev.state = TabActivityState.backgroundActive;
      }
    }

    final existing = _records[tabId];
    if (existing == null) {
      _records[tabId] = _TabActivityRecord(
        state: TabActivityState.focused,
        lastFocusedAt: now,
        lastInteractionAt: now,
        lastKnownPath: path,
      );
    } else {
      // Promote from any state to focused.
      existing.state = TabActivityState.focused;
      existing.lastFocusedAt = now;
      existing.lastInteractionAt = now;
      existing.inactiveSince = null;
      if (path != null) existing.lastKnownPath = path;
      // needsReload is preserved if already set; consumed by caller via
      // consumeReloadFlag() once UI reload starts.
    }

    _focusedTabId = tabId;
    notifyListeners();
  }

  /// Record any user interaction on a tab (scroll, click, action). Resets
  /// the inactivity counter without changing focus.
  void onTabInteraction(String tabId, {String? path}) {
    if (_disposed) return;
    final now = _now();
    final r = _records[tabId];
    if (r == null) {
      _records[tabId] = _TabActivityRecord(
        state: tabId == _focusedTabId
            ? TabActivityState.focused
            : TabActivityState.backgroundActive,
        lastFocusedAt: now,
        lastInteractionAt: now,
        lastKnownPath: path,
      );
      notifyListeners();
      return;
    }

    r.lastInteractionAt = now;
    if (path != null) r.lastKnownPath = path;

    // Promote from inactive on direct interaction.
    if (r.state == TabActivityState.inactive) {
      r.state = (tabId == _focusedTabId)
          ? TabActivityState.focused
          : TabActivityState.backgroundActive;
      r.inactiveSince = null;
      r.needsReload = true;
      notifyListeners();
    }
  }

  /// Update the cached path associated with the tab without changing activity.
  void updateTabPath(String tabId, String? path) {
    final r = _records[tabId];
    if (r == null) return;
    if (r.lastKnownPath == path) return;
    r.lastKnownPath = path;
  }

  /// Notify that a tab was closed. Releases tracking and fires close listeners.
  void onTabClosed(String tabId) {
    if (_disposed) return;
    final r = _records.remove(tabId);
    if (_focusedTabId == tabId) {
      _focusedTabId = null;
    }
    if (r != null) {
      for (final l in List<TabClosedListener>.from(_closedListeners)) {
        try {
          l(tabId, r.lastKnownPath);
        } catch (_) {
          // listener errors must not break tab manager.
        }
      }
      notifyListeners();
    }
  }

  /// Manually transition [tabId] to [TabActivityState.inactive].
  ///
  /// Triggered by user action (e.g. right-click menu "Mark inactive"). The
  /// focused tab is refused — the user must switch away first or pick another
  /// tab. Returns true on success, false if the tab is unknown, already
  /// inactive, currently focused, or pinned via [setAlwaysActive].
  ///
  /// Fires the inactive listener so the same cache release pipeline runs as
  /// for automatic transitions.
  bool markInactive(String tabId) {
    if (_disposed) return false;
    final r = _records[tabId];
    if (r == null) return false;
    if (r.alwaysActive) return false;
    if (r.state == TabActivityState.focused) return false;
    if (r.state == TabActivityState.inactive) return false;

    r.state = TabActivityState.inactive;
    r.inactiveSince = _now();
    r.needsReload = true;

    final path = r.lastKnownPath;
    for (final l in List<TabInactiveListener>.from(_inactiveListeners)) {
      try {
        l(tabId, path);
      } catch (_) {
        // listener errors must not break tab manager.
      }
    }
    notifyListeners();
    return true;
  }

  /// Consume the reload flag for [tabId]. Returns true exactly once after a
  /// tab transitions from inactive back to focused or background.
  bool consumeReloadFlag(String tabId) {
    final r = _records[tabId];
    if (r == null) return false;
    if (!r.needsReload) return false;
    r.needsReload = false;
    return true;
  }

  /// Manually mark a tab as needing reload. Mainly for tests.
  @visibleForTesting
  void debugMarkNeedsReload(String tabId) {
    final r = _records[tabId];
    if (r == null) return;
    r.needsReload = true;
  }

  /// Evaluate all tracked tabs and transition idle ones to inactive.
  /// Returns the list of tab ids that transitioned this call.
  ///
  /// When auto-suspend is disabled (threshold == 0) this is a no-op.
  List<String> evaluateInactiveTabs([DateTime? now]) {
    if (_disposed) return const <String>[];
    if (!isAutoSuspendEnabled) return const <String>[];
    final threshold = _inactiveThreshold;
    final evaluatedAt = now ?? _now();
    final transitioned = <String>[];

    _records.forEach((tabId, r) {
      if (r.state == TabActivityState.focused) return;
      if (r.state == TabActivityState.inactive) return;
      if (r.alwaysActive) return;

      final reference = r.lastInteractionAt.isAfter(r.lastFocusedAt)
          ? r.lastInteractionAt
          : r.lastFocusedAt;
      final idleFor = evaluatedAt.difference(reference);
      if (idleFor >= threshold) {
        r.state = TabActivityState.inactive;
        r.inactiveSince = evaluatedAt;
        r.needsReload = true;
        transitioned.add(tabId);
      }
    });

    if (transitioned.isNotEmpty) {
      for (final tabId in transitioned) {
        final r = _records[tabId];
        final path = r?.lastKnownPath;
        for (final l in List<TabInactiveListener>.from(_inactiveListeners)) {
          try {
            l(tabId, path);
          } catch (_) {
            // listener errors must not break tab manager.
          }
        }
      }
      notifyListeners();
    }

    return transitioned;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopPeriodicEvaluation();
    _records.clear();
    _inactiveListeners.clear();
    _closedListeners.clear();
    super.dispose();
  }
}
