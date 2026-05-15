import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../bloc/ai_agent/ai_agent_bloc.dart';
import '../../../bloc/ai_agent/ai_agent_event.dart';
import '../../../services/ai/ai_chat_history_service.dart';
import '../../../services/ai/ai_provider_service.dart';
import '../../../services/ai/file_context_builder.dart';

/// Controller for the AI side panel.
///
/// Maintains per-tab [AiAgentBloc] history so conversation persists
/// when the panel is toggled or the user temporarily switches away.
class AiPanelController extends ChangeNotifier {
  static const double defaultPanelWidth = 380;
  static const double minPanelWidth = 320;
  static const double maxPanelWidth = 760;
  static const String _panelWidthPrefsKey = 'ai_side_panel_width';

  bool _isOpen = false;
  String _currentPath = '';
  String? _ownerTabId;
  double _panelWidth = defaultPanelWidth;
  bool _isDisposed = false;
  bool _panelWidthNotifyScheduled = false;

  /// Blocs kept alive per tab so conversation history is preserved.
  final Map<String, AiAgentBloc> _tabBlocs = {};

  AiPanelController() {
    _loadPanelWidth();
  }

  bool get isOpen => _isOpen;
  String get currentPath => _currentPath;
  String? get ownerTabId => _ownerTabId;
  double get panelWidth => _panelWidth;

  static double maxWidthForAvailableWidth(double availableWidth) {
    return math.min(
      maxPanelWidth,
      math.max(minPanelWidth, availableWidth * 0.65),
    );
  }

  double clampedPanelWidthFor(double availableWidth) {
    return _clampPanelWidth(_panelWidth, availableWidth: availableWidth);
  }

  void updatePanelWidth(double width, {required double availableWidth}) {
    final next = _clampPanelWidth(width, availableWidth: availableWidth);
    if (next == _panelWidth) return;
    _panelWidth = next;
    _schedulePanelWidthNotify();
  }

  Future<void> commitPanelWidth({required double availableWidth}) async {
    _panelWidth = _clampPanelWidth(_panelWidth, availableWidth: availableWidth);
    _schedulePanelWidthNotify();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_panelWidthPrefsKey, _panelWidth);
  }

  /// Returns the living [AiAgentBloc] for the given tab, creating one if needed.
  /// Pass localized thinking phrases from AppLocalizations.
  AiAgentBloc blocForTab(
    String tabId, {
    String? initialPath,
    required List<String> thinkingPhrases,
    required String waitingApproval,
    required String runningToolTemplate,
  }) {
    if (!_tabBlocs.containsKey(tabId)) {
      final bloc = AiAgentBloc(
        providerService: GetIt.instance<AiProviderService>(),
        historyService: GetIt.instance<AiChatHistoryService>(),
        thinkingPhrases: thinkingPhrases,
        waitingApproval: waitingApproval,
        runningToolTemplate: runningToolTemplate,
      );
      bloc.add(InitializeAiAgent(workspacePath: initialPath ?? ''));
      if (initialPath != null && initialPath.isNotEmpty) {
        bloc.add(UpdateCurrentPath(initialPath));
        bloc.add(const ChangeSearchScope(SearchScope.recursive));
      }
      _tabBlocs[tabId] = bloc;
    }
    return _tabBlocs[tabId]!;
  }

  void open({String? path, String? tabId}) {
    if (path != null) _currentPath = path;
    _ownerTabId = tabId;
    _isOpen = true;
    // Update path in the tab's bloc
    if (tabId != null && path != null && path.isNotEmpty) {
      _tabBlocs[tabId]?.add(UpdateCurrentPath(path));
    }
    notifyListeners();
  }

  void close() {
    _isOpen = false;
    _ownerTabId = null;
    notifyListeners();
  }

  void toggle({String? path, String? tabId}) {
    if (_isOpen && _ownerTabId == tabId) {
      close();
    } else {
      open(path: path, tabId: tabId);
    }
  }

  /// Called on every tab switch — closes panel if active tab changed.
  void onActiveTabChanged(String? activeTabId) {
    if (_isOpen && _ownerTabId != null && _ownerTabId != activeTabId) {
      close();
    }
  }

  void updatePath(String path) {
    _currentPath = path;
    // Keep the active tab's bloc in sync
    if (_ownerTabId != null) {
      _tabBlocs[_ownerTabId]?.add(UpdateCurrentPath(path));
    }
  }

  /// Disposes blocs for tabs that no longer exist.
  void evictTabs(Set<String> activeTabIds) {
    final stale =
        _tabBlocs.keys.where((id) => !activeTabIds.contains(id)).toList();
    for (final id in stale) {
      _tabBlocs[id]?.close();
      _tabBlocs.remove(id);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    for (final bloc in _tabBlocs.values) {
      bloc.close();
    }
    _tabBlocs.clear();
    super.dispose();
  }

  Future<void> _loadPanelWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_panelWidthPrefsKey);
    if (saved == null || _isDisposed) return;
    _panelWidth = _clampPanelWidth(saved);
    notifyListeners();
  }

  void _schedulePanelWidthNotify() {
    if (_panelWidthNotifyScheduled) return;
    _panelWidthNotifyScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      if (_isDisposed) return;
      _panelWidthNotifyScheduled = false;
      notifyListeners();
    });
  }

  double _clampPanelWidth(double width, {double? availableWidth}) {
    final maxWidth = availableWidth == null
        ? maxPanelWidth
        : maxWidthForAvailableWidth(availableWidth);
    final minWidth = math.min(minPanelWidth, maxWidth);
    return width.clamp(minWidth, maxWidth).toDouble();
  }
}

/// InheritedWidget providing [AiPanelController] to descendants.
class AiPanelScope extends InheritedWidget {
  final AiPanelController controller;

  const AiPanelScope({
    Key? key,
    required this.controller,
    required Widget child,
  }) : super(key: key, child: child);

  static AiPanelController? of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AiPanelScope>();
    return scope?.controller;
  }

  /// Non-dependency version (won't rebuild on changes).
  static AiPanelController? maybeOf(BuildContext context) {
    final scope =
        context.getElementForInheritedWidgetOfExactType<AiPanelScope>();
    return (scope?.widget as AiPanelScope?)?.controller;
  }

  @override
  bool updateShouldNotify(AiPanelScope oldWidget) {
    return controller != oldWidget.controller;
  }
}
