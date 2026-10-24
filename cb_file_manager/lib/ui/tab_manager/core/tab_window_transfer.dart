import 'dart:convert';
import 'dart:io';

import '../../../services/windowing/window_startup_payload.dart';
import '../../../services/torrent/torrent_launch_request.dart';
import 'tab_data.dart';
import 'tab_pane_state.dart';

/// Captures UI state on demand before crossing an engine boundary.
/// Widgets register only for their mounted lifetime; pending state is consumed
/// once by the destination screen after its own engine creates the tab.
abstract final class TabWindowTransfer {
  static final _readers = <String, Map<String, dynamic> Function()>{};
  static final _pending = <String, Map<String, dynamic>>{};

  static void register(String id, Map<String, dynamic> Function() read) =>
      _readers[id] = read;

  /// With [read], removes it only if still registered: a remounted screen
  /// registers its reader before the old one is disposed.
  static void unregister(String id, [Object? read]) {
    // Method tear-offs of one object compare equal, not identical.
    if (read == null || _readers[id] == read) _readers.remove(id);
  }

  static Map<String, dynamic> takeInitial(String id) =>
      _pending.remove(id) ?? {};

  /// Route metadata is needed before the destination screen consumes its view.
  static Map<String, dynamic> peekInitial(String id) =>
      Map.unmodifiable(_pending[id] ?? const <String, dynamic>{});
  static void forget(String id) {
    _pending.remove(id);
    _pending.remove('${id}_split');
  }

  static WindowTabPayload capture(TabData tab) {
    final view = _readers[tab.id]?.call() ?? _pending[tab.id];
    final viewJson = view == null ? null : jsonEncode(view);
    final session = <String, dynamic>{
      'id': tab.id,
      'history': tab.navigationHistory,
      'forward': tab.forwardHistory,
      'pinned': tab.isPinned,
      'torrentSources': tab.pendingTorrentSources.map((r) => r.source).toList(),
      'preview': TabPaneState.previewVisible(tab.id),
      'properties': TabPaneState.propertiesVisible(tab.id),
      if (tab.splitPaneTabData != null)
        'split': capture(tab.splitPaneTabData!).toJson(),
      // Loaded galleries may contain thousands of paths. Compress large
      // snapshots so they fit the native merge message without truncation.
      'view': viewJson != null && viewJson.length > 64 * 1024
          ? {'gzip': base64Encode(gzip.encode(utf8.encode(viewJson)))}
          : view,
    };
    // Own the snapshot: later source navigation must not mutate its history.
    return WindowTabPayload(
      path: tab.path,
      name: tab.name,
      highlightedFileName: tab.highlightedFileName,
      session: Map<String, dynamic>.from(
        jsonDecode(jsonEncode(session)) as Map,
      ),
    );
  }

  static TabData restore(WindowTabPayload payload) {
    final session = payload.session ?? const <String, dynamic>{};
    final id =
        session['id'] as String? ??
        'tab_${DateTime.now().microsecondsSinceEpoch}';
    var view = session['view'];
    if (view is Map && view['gzip'] is String) {
      view = jsonDecode(
        utf8.decode(gzip.decode(base64Decode(view['gzip'] as String))),
      );
    }
    if (view is Map) _pending[id] = Map<String, dynamic>.from(view);
    if (session['preview'] is bool) {
      TabPaneState.setPreviewVisible(id, session['preview'] as bool);
    }
    if (session['properties'] is bool) {
      TabPaneState.setPropertiesVisible(id, session['properties'] as bool);
    }
    final split = session['split'];
    final splitTab = split is Map
        ? restore(WindowTabPayload.fromJson(Map<String, dynamic>.from(split)))
        : null;
    List<String>? strings(Object? value) =>
        value is List ? value.whereType<String>().toList() : null;
    return TabData(
      id: id,
      name: payload.name ?? payload.path,
      path: payload.path,
      navigationHistory: strings(session['history']),
      forwardHistory: strings(session['forward']),
      isPinned: session['pinned'] == true,
      pendingTorrentSources: (strings(session['torrentSources']) ?? [])
          .where(TorrentLaunchRequest.isSource)
          .map(TorrentLaunchRequest.new)
          .toList(),
      highlightedFileName: payload.highlightedFileName,
      splitPanePath: splitTab?.path,
      splitPaneTabData: splitTab,
    );
  }
}
