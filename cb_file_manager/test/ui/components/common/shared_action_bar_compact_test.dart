import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tr = EnglishLocalizations();
  Future<void> mount(
    WidgetTester tester,
    List<String> calls, {
    double width = 320,
    bool searching = false,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizationsDelegate()],
        home: Scaffold(
          body: Builder(
            builder: (context) => Row(
              children: [
                const Expanded(
                  child: Text('Collection', overflow: TextOverflow.ellipsis),
                ),
                ...SharedActionBar.buildCommonActions(
                  context: context,
                  compact: width < 640,
                  primaryAction: IconButton(
                    key: const ValueKey('create-collection'),
                    icon: const Icon(Icons.add),
                    tooltip: 'Create collection',
                    onPressed: () => calls.add('create'),
                  ),
                  onSearchPressed: () => calls.add('search'),
                  isSearchActive: searching,
                  onSortOptionSelected: (sort) =>
                      calls.add('sort:${sort.name}'),
                  currentSortOption: SortOption.nameAsc,
                  allowedSortOptions: {SortOption.nameAsc, SortOption.dateDesc},
                  viewMode: ViewMode.grid,
                  allowedViewModes: {ViewMode.grid, ViewMode.list},
                  onViewModeToggled: () => calls.add('toggle-view'),
                  onViewModeSelected: (mode) => calls.add('view:${mode.name}'),
                  onRefresh: () => calls.add('refresh'),
                  onSelectionModeToggled: () => calls.add('selection'),
                  additionalMoreOptions: const [
                    PopupMenuItem(
                      value: 'custom',
                      child: Text('Edit collection'),
                    ),
                  ],
                  onAdditionalMoreOptionSelected: (value) => calls.add(value),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(const ValueKey('shared-more-action')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'narrow collection keeps create visible and secondary commands usable',
    (tester) async {
      final calls = <String>[];
      await mount(tester, calls);
      final create = find.byKey(const ValueKey('create-collection'));
      expect(tester.getRect(create).right, lessThanOrEqualTo(320));
      await tester.tap(create);
      await choose(tester, tr.searchTooltip);
      await choose(tester, tr.sortDateModifiedNewest);
      await choose(tester, tr.viewModeList);
      await choose(tester, tr.refreshTooltip);
      await choose(tester, tr.selectMultipleFiles);
      await choose(tester, 'Edit collection');
      expect(calls, [
        'create',
        'search',
        'sort:dateDesc',
        'view:list',
        'refresh',
        'selection',
        'custom',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an active narrow search keeps its close control on the toolbar',
    (tester) async {
      final calls = <String>[];
      await mount(tester, calls, searching: true);
      await tester.tap(find.byTooltip(tr.close));
      expect(calls, ['search']);
      expect(find.byKey(const ValueKey('create-collection')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide collections place create between refresh and more', (
    tester,
  ) async {
    await mount(tester, [], width: 1200);
    final create = tester.getRect(
      find.byKey(const ValueKey('create-collection')),
    );
    final refresh = tester.getRect(
      find.byKey(const ValueKey('shared-refresh-action')),
    );
    final more = tester.getRect(
      find.byKey(const ValueKey('shared-more-action')),
    );
    expect(create.left, greaterThanOrEqualTo(refresh.right));
    expect(create.right, lessThanOrEqualTo(more.left));
    expect(tester.takeException(), isNull);
  });
}
