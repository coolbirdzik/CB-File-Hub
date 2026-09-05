import 'dart:convert';
import 'dart:io';

class WindowTabPayload {
  final String path;
  final String? name;
  final String? highlightedFileName;

  const WindowTabPayload({
    required this.path,
    this.name,
    this.highlightedFileName,
  });

  factory WindowTabPayload.fromJson(Map<String, dynamic> json) {
    return WindowTabPayload(
      path: (json['path'] as String?) ?? '',
      name: json['name'] as String?,
      highlightedFileName: json['highlightedFileName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    if (name != null) 'name': name,
    if (highlightedFileName != null) 'highlightedFileName': highlightedFileName,
  };
}

class WindowStartupPayload {
  static const String envTabsKey = 'CB_STARTUP_TABS';
  static const String envSecondaryWindowKey = 'CB_SECONDARY_WINDOW';
  static const String envStartHiddenKey = 'CB_START_HIDDEN';
  static const String envWindowRoleKey = 'CB_WINDOW_ROLE';
  static const String envWindowPositionXKey = 'CB_WINDOW_POSITION_X';
  static const String envWindowPositionYKey = 'CB_WINDOW_POSITION_Y';
  static const String envStartDraggingKey = 'CB_START_DRAGGING';

  // Progress window IPC
  static const String envProgressIpcPortKey = 'CB_PROGRESS_IPC_PORT';
  static const String envProgressTitleKey = 'CB_PROGRESS_TITLE';
  static const String envProgressTotalKey = 'CB_PROGRESS_TOTAL';
  static const String envProgressIndeterminateKey = 'CB_PROGRESS_INDETERMINATE';

  final List<WindowTabPayload> tabs;
  final int? activeIndex;

  const WindowStartupPayload({required this.tabs, this.activeIndex});

  bool get isEmpty => tabs.isEmpty;

  static WindowStartupPayload? fromEnvironment() {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return null;
    }

    final raw = Platform.environment[envTabsKey];
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final tabs = decoded
            .whereType<Map>()
            .map((m) => WindowTabPayload.fromJson(Map<String, dynamic>.from(m)))
            .where((t) => t.path.trim().isNotEmpty)
            .toList(growable: false);
        if (tabs.isEmpty) return null;
        return WindowStartupPayload(tabs: tabs);
      }
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        final dynamic listValue = map['tabs'];
        final int? activeIndex = map['activeIndex'] is int
            ? map['activeIndex'] as int
            : int.tryParse('${map['activeIndex'] ?? ''}');

        final tabs = (listValue is List ? listValue : const <dynamic>[])
            .whereType<Map>()
            .map((m) => WindowTabPayload.fromJson(Map<String, dynamic>.from(m)))
            .where((t) => t.path.trim().isNotEmpty)
            .toList(growable: false);
        if (tabs.isEmpty) return null;
        return WindowStartupPayload(tabs: tabs, activeIndex: activeIndex);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
