import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter_test/flutter_test.dart';

Future<TabManagerBloc> _bloc(List<String> paths) async {
  final bloc = TabManagerBloc();
  for (final path in paths) {
    bloc.add(AddTab(path: path, name: path));
  }
  await Future<void>.delayed(Duration.zero);
  return bloc;
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('reopens the closed tab at its original position', () async {
    final bloc = await _bloc(['/a', '/b', '/c']);
    addTearDown(bloc.close);

    bloc.add(CloseTab(bloc.state.tabs[1].id));
    await _settle();
    expect(bloc.state.tabs.map((t) => t.path), ['/a', '/c']);

    bloc.add(ReopenClosedTab());
    await _settle();
    expect(bloc.state.tabs.map((t) => t.path), ['/a', '/b', '/c']);
    expect(bloc.state.activeTab?.path, '/b');
    expect(bloc.canReopenClosedTab, isFalse);
  });

  test('reopens several closed tabs, newest first', () async {
    final bloc = await _bloc(['/a', '/b', '/c']);
    addTearDown(bloc.close);

    for (final tab in List.of(bloc.state.tabs)) {
      bloc.add(CloseTab(tab.id));
    }
    await _settle();
    expect(bloc.state.tabs, isEmpty);

    bloc.add(ReopenClosedTab());
    await _settle();
    expect(bloc.state.tabs.map((t) => t.path), ['/c']);
    bloc.add(ReopenClosedTab());
    bloc.add(ReopenClosedTab());
    await _settle();
    expect(bloc.state.tabs.map((t) => t.path), ['/a', '/b', '/c']);
  });

  test('a tab moved to another window is not reopenable', () async {
    final bloc = await _bloc(['/a', '/b']);
    addTearDown(bloc.close);

    bloc.add(CloseTab(bloc.state.tabs.first.id, rememberForReopen: false));
    await _settle();
    expect(bloc.canReopenClosedTab, isFalse);

    bloc.add(ReopenClosedTab());
    await _settle();
    expect(bloc.state.tabs.map((t) => t.path), ['/b']);
  });

  test('reopening with nothing closed does nothing', () async {
    final bloc = await _bloc(['/a']);
    addTearDown(bloc.close);

    bloc.add(ReopenClosedTab());
    await _settle();
    expect(bloc.state.tabs.map((t) => t.path), ['/a']);
  });

  test('close other tabs can be undone', () async {
    final bloc = await _bloc(['/a', '/b', '/c']);
    addTearDown(bloc.close);

    bloc.add(CloseOtherTabs(bloc.state.tabs[1].id));
    await _settle();
    expect(bloc.state.tabs.map((t) => t.path), ['/b']);

    bloc.add(ReopenClosedTab());
    bloc.add(ReopenClosedTab());
    await _settle();
    expect(bloc.state.tabs.map((t) => t.path), ['/a', '/b', '/c']);
  });
}
