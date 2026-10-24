import 'dart:convert';

import 'package:cb_file_manager/services/windowing/window_startup_payload.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_pane_state.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_window_transfer.dart';
import 'package:cb_file_manager/services/windowing/windows_native_tab_drag_drop_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('large gallery snapshots fit a native merge and restore all paths', () {
    final tab = TabData(id: 'large-gallery', name: 'Videos', path: '#video');
    final paths = List.generate(
      15000,
      (i) =>
          'D:/Videos/Collection with long names/Season ${i ~/ 30}/clip-$i.mp4',
    );
    TabWindowTransfer.register(tab.id, () => {'loadedFiles': paths});
    addTearDown(() {
      TabWindowTransfer.unregister(tab.id);
      TabWindowTransfer.forget(tab.id);
    });
    final payload = TabWindowTransfer.capture(tab);
    final encoded = WindowsNativeTabDragDropService.encodeTabsPayload([
      payload,
    ]);
    expect(utf8.encode(encoded).length, lessThan(1024 * 1024 - 8));
    final decoded = WindowsNativeTabDragDropService.decodeTabsPayload(encoded);
    TabWindowTransfer.restore(decoded.single);
    expect(TabWindowTransfer.peekInitial(tab.id)['loadedFiles'], paths);
    expect(TabWindowTransfer.takeInitial(tab.id)['loadedFiles'], paths);
    expect(TabWindowTransfer.peekInitial(tab.id), isEmpty);
  });

  test(
    'transfer preserves navigation and split state with fresh widget keys',
    () async {
      final original = TabData(
        id: 'transfer-folder',
        name: 'Music',
        path: r'C:\Music',
        isPinned: true,
        navigationHistory: [r'C:\', r'C:\Music'],
        forwardHistory: [r'C:\Music\Live'],
        splitPanePath: r'D:\Audio',
        splitPaneTabData: TabData(
          id: 'transfer-folder_split',
          name: 'Audio',
          path: r'D:\Audio',
        ),
      );
      TabPaneState.setPreviewVisible(original.id, true);
      TabPaneState.setPropertiesVisible(original.id, false);
      TabWindowTransfer.register(
        original.id,
        () => {
          'scroll': 725.0,
          'files': [r'C:\Music\one.flac'],
          'query': 'live',
        },
      );
      addTearDown(() {
        TabWindowTransfer.unregister(original.id);
        TabWindowTransfer.forget(original.id);
        TabPaneState.clearAll();
      });
      final payload = WindowTabPayload.fromJson(
        jsonDecode(jsonEncode(TabWindowTransfer.capture(original).toJson()))
            as Map<String, dynamic>,
      );
      // Mutating the source after capture cannot change the pending transfer.
      original.navigationHistory.add(r'C:\Other');
      final destination = TabManagerBloc();
      addTearDown(destination.close);
      final changed = destination.stream.first;
      WindowsNativeTabDragDropService.addTabs(destination, [payload]);
      await changed;
      final restored = destination.state.activeTab!;
      expect(restored.id, original.id);
      expect(restored.navigationHistory, [r'C:\', r'C:\Music']);
      expect(restored.forwardHistory, original.forwardHistory);
      expect(restored.isPinned, isTrue);
      expect(restored.navigatorKey, isNot(same(original.navigatorKey)));
      expect(
        restored.repaintBoundaryKey,
        isNot(same(original.repaintBoundaryKey)),
      );
      expect(restored.splitPaneTabData?.path, r'D:\Audio');
      expect(TabPaneState.previewVisible(restored.id), isTrue);
      expect(TabWindowTransfer.takeInitial(restored.id), {
        'scroll': 725.0,
        'files': [r'C:\Music\one.flac'],
        'query': 'live',
      });
      expect(TabWindowTransfer.takeInitial(restored.id), isEmpty);
      final duplicate = destination.stream.first;
      destination.add(AddTab(path: payload.path, windowPayload: payload));
      await duplicate;
      expect(destination.state.tabs, hasLength(1));
    },
  );

  test(
    'legacy payloads still open and inserted transfers activate their own id',
    () async {
      final destination = TabManagerBloc();
      addTearDown(destination.close);
      var changed = destination.stream.first;
      WindowsNativeTabDragDropService.addTabs(destination, const [
        WindowTabPayload(path: '/legacy', name: 'Legacy'),
      ]);
      await changed;
      final payload = TabWindowTransfer.capture(
        TabData(id: 'moved', name: 'Moved', path: '/moved'),
      );
      changed = destination.stream.first;
      WindowsNativeTabDragDropService.addTabs(destination, [
        payload,
      ], insertIndex: 0);
      await changed;
      expect(destination.state.tabs.map((t) => t.path), ['/moved', '/legacy']);
      expect(destination.state.activeTabId, 'moved');
    },
  );
}
