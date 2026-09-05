import 'dart:convert';

import '../core/user_preferences.dart';

enum ContextMenuLayoutTarget { file, folder, multiSelection }

const String contextMenuThirdPartyAppsId = 'third_party_apps';

const List<String> defaultFileContextMenuLayout = <String>[
  'play_video',
  'view_image',
  'open',
  'open_file_location',
  'open_in_new_tab',
  'open_in_new_window',
  'open_with',
  'choose_default_app',
  'download',
  'copy',
  'cut',
  'rename',
  'tags',
  'properties',
  'delete',
  contextMenuThirdPartyAppsId,
  'more_options',
];

const List<String> defaultFolderContextMenuLayout = <String>[
  'open',
  'open_in_new_tab',
  'open_in_split_view',
  'open_in_new_window',
  'toggle_pin_sidebar',
  'copy',
  'cut',
  'paste',
  'rename',
  'tags',
  'properties',
  contextMenuThirdPartyAppsId,
  'more_options',
];

const List<String> defaultMultiSelectionContextMenuLayout = <String>[
  'copy',
  'cut',
  'tags',
  'delete',
  contextMenuThirdPartyAppsId,
  'more_options',
];

List<String> defaultContextMenuLayoutFor(ContextMenuLayoutTarget target) {
  switch (target) {
    case ContextMenuLayoutTarget.file:
      return defaultFileContextMenuLayout;
    case ContextMenuLayoutTarget.folder:
      return defaultFolderContextMenuLayout;
    case ContextMenuLayoutTarget.multiSelection:
      return defaultMultiSelectionContextMenuLayout;
  }
}

class ContextMenuLayoutPreference {
  final List<String> order;
  final Set<String> hiddenIds;

  const ContextMenuLayoutPreference({
    required this.order,
    required this.hiddenIds,
  });

  factory ContextMenuLayoutPreference.defaults(ContextMenuLayoutTarget target) {
    return ContextMenuLayoutPreference(
      order: List<String>.of(defaultContextMenuLayoutFor(target)),
      hiddenIds: <String>{},
    );
  }

  factory ContextMenuLayoutPreference.fromJson(
    ContextMenuLayoutTarget target,
    String? raw,
  ) {
    final defaults = defaultContextMenuLayoutFor(target);
    if (raw == null || raw.trim().isEmpty) {
      return ContextMenuLayoutPreference.defaults(target);
    }

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        return ContextMenuLayoutPreference.defaults(target);
      }

      final storedOrder = (decoded['order'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toList();
      final mergedOrder = <String>[];
      for (final id in <String>[...storedOrder, ...defaults]) {
        if (!mergedOrder.contains(id)) {
          mergedOrder.add(id);
        }
      }

      final hiddenIds = (decoded['hidden'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet();

      return ContextMenuLayoutPreference(
        order: mergedOrder,
        hiddenIds: hiddenIds,
      );
    } catch (_) {
      return ContextMenuLayoutPreference.defaults(target);
    }
  }

  ContextMenuLayoutPreference copyWith({
    List<String>? order,
    Set<String>? hiddenIds,
  }) {
    return ContextMenuLayoutPreference(
      order: order ?? this.order,
      hiddenIds: hiddenIds ?? this.hiddenIds,
    );
  }

  String toJson() {
    return json.encode(<String, dynamic>{
      'order': order,
      'hidden': hiddenIds.toList(),
    });
  }
}

class ContextMenuLayoutPreferences {
  ContextMenuLayoutPreferences._();

  static final ContextMenuLayoutPreferences instance =
      ContextMenuLayoutPreferences._();

  Future<ContextMenuLayoutPreference> load(
    ContextMenuLayoutTarget target,
  ) async {
    final raw = await UserPreferences.instance.getContextMenuLayoutJson(
      target.name,
    );
    return ContextMenuLayoutPreference.fromJson(target, raw);
  }

  Future<bool> save(
    ContextMenuLayoutTarget target,
    ContextMenuLayoutPreference preference,
  ) {
    return UserPreferences.instance.setContextMenuLayoutJson(
      target.name,
      preference.toJson(),
    );
  }

  Future<bool> reset(ContextMenuLayoutTarget target) {
    return UserPreferences.instance.clearContextMenuLayout(target.name);
  }
}
