import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_file_surface.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/components/search_bar.dart'
    as search;
import 'package:cb_file_manager/ui/tab_manager/core/tab_focus_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pressSearch(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('Ctrl+F opens search and refocuses without changing its query', (
    tester,
  ) async {
    final searchFocus = FocusNode();
    final otherFocus = FocusNode();
    addTearDown(searchFocus.dispose);
    addTearDown(otherFocus.dispose);
    var visible = false;
    var queries = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('vi')],
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return BrowserLikeFileSurface(
              selectionState: const SelectionState(),
              viewMode: ViewMode.list,
              isDesktop: true,
              visiblePaths: const [],
              onClearSelection: () {},
              showRemoveTagsDialog: (_) {},
              showManageAllTagsDialog: (_) {},
              showDeleteConfirmationDialog: (_) {},
              showAppBar: true,
              showSearchBar: visible,
              searchBar: search.SearchBar(
                focusNode: searchFocus,
                currentPath: 'C:/',
                tabId: 'test',
                onCloseSearch: () => update(() => visible = false),
                onQueryChanged: (_) => queries++,
                showTagSearch: false,
                showTipsButton: false,
                showGlobalSearchToggle: false,
                showRegexToggle: false,
              ),
              pathNavigationBar: const Text('path'),
              actions: const [],
              bodyBuilder: (_, _) =>
                  Material(child: TextField(focusNode: otherFocus)),
              onSearch: () {
                if (!visible) update(() => visible = true);
                searchFocus.requestFocus();
              },
            );
          },
        ),
      ),
    );
    await tester.pump();
    // Search must work even while a different input owns focus.
    otherFocus.requestFocus();
    await tester.pump();
    await pressSearch(tester);
    await tester.pump();
    expect(visible, isTrue);
    expect(searchFocus.hasFocus, isTrue);
    final input = find.descendant(
      of: find.byType(search.SearchBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, 'holiday');
    await tester.pump();
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(search.SearchBar),
        matching: find.byType(EditableText),
      ),
    );
    final value = editable.controller.value;
    final queriesBefore = queries;
    otherFocus.requestFocus();
    await tester.pump();
    expect(otherFocus.hasFocus, isTrue);
    await pressSearch(tester);
    await tester.pump();
    expect(searchFocus.hasFocus, isTrue);
    expect(visible, isTrue);
    expect(editable.controller.value, value);
    expect(queries, queriesBefore);
    await pressSearch(tester);
    expect(searchFocus.hasFocus, isTrue);
    expect(visible, isTrue);
    expect(editable.controller.text, 'holiday');
    expect(queries, queriesBefore);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // The SearchBar does not own the caller's focus node.
    searchFocus.addListener(() {});
  });

  testWidgets('Ctrl+F does not open search in an inactive tab', (tester) async {
    final scope = FocusScopeNode();
    addTearDown(scope.dispose);
    var searches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TabFocusGate(
          node: scope,
          isActive: false,
          child: BrowserLikeFileSurface(
            selectionState: const SelectionState(),
            viewMode: ViewMode.list,
            isDesktop: true,
            visiblePaths: const [],
            onClearSelection: () {},
            showRemoveTagsDialog: (_) {},
            showManageAllTagsDialog: (_) {},
            showDeleteConfirmationDialog: (_) {},
            showAppBar: false,
            showSearchBar: false,
            searchBar: const SizedBox(),
            pathNavigationBar: const SizedBox(),
            actions: const [],
            bodyBuilder: (_, _) =>
                const Material(child: TextField(autofocus: true)),
            onSearch: () => searches++,
          ),
        ),
      ),
    );
    await tester.pump();
    await pressSearch(tester);
    expect(searches, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
