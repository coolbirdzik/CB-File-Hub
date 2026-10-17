import 'package:cb_file_manager/services/torrent/torrent_launch_request.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TabManagerBloc tabs;
  setUp(() => tabs = TabManagerBloc());
  tearDown(() => tabs.close());

  Future<void> dispatch(TabEvent event) async {
    final changed = tabs.stream.first;
    tabs.add(event);
    await changed;
  }

  String magnet(String digit) => 'magnet:?xt=urn:btih:${digit * 40}';

  test(
    'association creates one torrent tab and queues every rapid launch',
    () async {
      await dispatch(AddTab(path: '#home'));
      final launches = [
        magnet('1'),
        magnet('2'),
        magnet('2'),
        r'C:\new.torrent',
      ];
      final complete = tabs.stream.firstWhere(
        (state) =>
            state.activeTab?.pendingTorrentSources.length == launches.length,
      );
      for (final source in launches) {
        tabs.add(AddTab(path: TorrentLaunchRequest.pathFor(source)));
      }
      await complete;
      expect(tabs.state.tabs, hasLength(2));
      final tab = tabs.state.activeTab!;
      expect(tab.path, '#torrents');
      expect(
        tab.pendingTorrentSources.map((request) => request.source),
        launches,
      );
      final first = tab.pendingTorrentSources.first;
      await dispatch(ConsumeTorrentSource(tab.id, first));
      expect(
        tabs.state.activeTab!.pendingTorrentSources.map(
          (request) => request.source,
        ),
        launches.skip(1),
      );
    },
  );

  test(
    'association focuses existing tab and preserves navigation identity',
    () async {
      await dispatch(AddTab(path: '#torrents', name: 'My torrents'));
      final existing = tabs.state.activeTab!;
      await dispatch(AddTab(path: '#home'));
      await dispatch(AddTab(path: TorrentLaunchRequest.pathFor(magnet('1'))));
      final reused = tabs.state.activeTab!;
      expect(tabs.state.tabs, hasLength(2));
      expect(reused.id, existing.id);
      expect(reused.name, existing.name);
      expect(reused.navigatorKey, same(existing.navigatorKey));
      expect(reused.navigationHistory, same(existing.navigationHistory));
    },
  );

  test('prefers active torrent tab when multiple library tabs exist', () async {
    await dispatch(AddTab(path: '#torrents'));
    final first = tabs.state.activeTab!;
    await dispatch(AddTab(path: '#torrents'));
    final active = tabs.state.activeTab!;
    await dispatch(AddTab(path: TorrentLaunchRequest.pathFor(magnet('3'))));
    expect(tabs.state.tabs, hasLength(2));
    expect(tabs.state.activeTabId, active.id);
    expect(
      tabs.state.tabs
          .firstWhere((tab) => tab.id == first.id)
          .pendingTorrentSources,
      isEmpty,
    );
    expect(
      tabs.state.activeTab!.pendingTorrentSources.single.source,
      magnet('3'),
    );
  });
}
