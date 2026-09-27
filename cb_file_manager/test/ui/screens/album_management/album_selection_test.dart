import 'package:cb_file_manager/ui/components/common/item_shell.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/screens/system_screen_router.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:cb_file_manager/ui/tab_manager/components/search_bar.dart'
    as tab_components;
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late TabManagerBloc tabs;
  late DrawerCubit drawer;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb-album-selection-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    SharedPreferences.setMockInitialValues({});
    await UserPreferences.instance.init();
    final db = await SqliteDatabaseProvider().getDatabase();
    for (var id = 1; id <= 2; id++) {
      await db.insert(
        'albums',
        (Album(name: 'Album $id')..id = id).toDatabaseMap(),
      );
    }
    locator.registerSingleton<AlbumService>(AlbumService.instance);
  });

  tearDownAll(() async {
    await locator.unregister<AlbumService>();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  setUp(() async {
    drawer = DrawerCubit();
    await UserPreferences.instance.setGridListCollectionMode(
      'albums',
      ViewMode.grid,
    );
  });
  tearDown(() async {
    await tabs.close();
    await drawer.close();
  });

  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() async {
        final db = await SqliteDatabaseProvider().getDatabase();
        await db.rawQuery('SELECT 1');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> selectCollectionView(WidgetTester tester, ViewMode mode) async {
    final menu = tester.widget<PopupMenuButton<ViewMode>>(
      find.byKey(const ValueKey('shared-view-mode-menu')),
    );
    menu.onSelected!(mode);
    await flush(tester);
  }

  Future<void> mount(
    WidgetTester tester,
    String path, {
    bool reuseTabs = false,
  }) async {
    if (!reuseTabs) tabs = TabManagerBloc();
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (!reuseTabs) tabs.add(AddTab(path: path));
    await tester.pump();
    final tabId = tabs.state.activeTabId!;
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: tabs),
          BlocProvider.value(value: drawer),
        ],
        child: fluent.FluentApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Theme(
            data: CbThemeBuilder.build(
              brightness: Brightness.light,
              accent: Colors.teal,
            ),
            child: child!,
          ),
          home: Builder(
            builder: (context) =>
                SystemScreenRouter.routeSystemPath(context, path, tabId)!,
          ),
        ),
      ),
    );
    await flush(tester);
  }

  for (final mode in ['grid', 'list', 'gallery']) {
    testWidgets('$mode albums select singly and open by double click', (
      tester,
    ) async {
      final path = mode == 'gallery' ? '#gallery' : '#albums';
      await mount(tester, path);
      if (mode == 'list') {
        await selectCollectionView(tester, ViewMode.list);
      }
      expect(
        find.byKey(const ValueKey('fluent-browser-toolbar')),
        findsOneWidget,
      );
      final navigation = tester.widget<PathNavigationBar>(
        find.byType(PathNavigationBar),
      );
      expect(navigation.currentPath, path);
      expect(navigation.enablePathEditing, isTrue);
      final expectedView = mode == 'list' ? ViewMode.list : ViewMode.grid;
      expect(
        find.byKey(ValueKey('grid-list-collection-${expectedView.name}')),
        findsOneWidget,
      );
      expect(
        await tester.runAsync(
          () => UserPreferences.instance.getGridListCollectionMode('albums'),
        ),
        expectedView,
      );
      final first = find.byKey(const ValueKey('album-1'));
      final second = find.byKey(const ValueKey('album-2'));
      final firstName = find.descendant(
        of: first,
        matching: find.text('Album 1'),
      );
      final secondName = find.descendant(
        of: second,
        matching: find.text('Album 2'),
      );
      expect(first, findsOneWidget);
      await tester.ensureVisible(first);
      await tester.tap(firstName, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 350));
      expect(tabs.state.activeTab!.path, path);
      expect(
        mode == 'list'
            ? tester.widget<ListItemShell>(first).isSelected
            : tester.widget<GridItemShell>(first).isSelected,
        isTrue,
      );
      await tester.tap(secondName, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        mode == 'list'
            ? tester.widget<ListItemShell>(first).isSelected
            : tester.widget<GridItemShell>(first).isSelected,
        isFalse,
      );
      expect(
        mode == 'list'
            ? tester.widget<ListItemShell>(second).isSelected
            : tester.widget<GridItemShell>(second).isSelected,
        isTrue,
      );
      expect(tabs.state.activeTab!.path, path);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        mode == 'list'
            ? tester.widget<ListItemShell>(second).isSelected
            : tester.widget<GridItemShell>(second).isSelected,
        isFalse,
      );
      final menu = find.descendant(
        of: first,
        matching: find.byType(PopupMenuButton<String>),
      );
      await tester.ensureVisible(menu);
      await tester.pump();
      await tester.tap(menu, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(CheckedPopupMenuItem<String>), findsOneWidget);
      expect(tabs.state.activeTab!.path, path);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 350));

      // Both the title and the cover/body belong to the same activation target.
      final point = mode == 'list'
          ? tester.getCenter(firstName)
          : tester.getTopLeft(first) + const Offset(30, 30);
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(point, kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump();
      expect(tabs.state.activeTab!.path, '#album/1');
      expect(tabs.state.activeTab!.navigationHistory.last, '#album/1');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    });
  }

  testWidgets('Image Gallery is a unified source browser', (tester) async {
    await mount(tester, '#gallery');
    expect(find.byKey(const ValueKey('grid-list-collection-grid')), findsOne);
    expect(find.byKey(const ValueKey('album-1')), findsOne);
    expect(find.byKey(const ValueKey('featured-album-1')), findsNothing);
    final firstAlbum = find.byKey(const ValueKey('album-1'));
    expect(tester.getSize(firstAlbum).height, greaterThan(200));
    expect(
      find.descendant(of: firstAlbum, matching: find.byType(Card)),
      findsNothing,
    );
    expect(find.text('Source'), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('create-image-source')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Create Image Source'), findsOne);
    expect(find.text('Image Sources'), findsOne);
    expect(find.text('Include Subdirectories'), findsOne);
    expect(find.byKey(const ValueKey('add-image-source-directory')), findsOne);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  testWidgets('Image Gallery exposes common search sort and refresh actions', (
    tester,
  ) async {
    await mount(tester, '#gallery');
    expect(find.byKey(const ValueKey('shared-search-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-sort-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-view-mode-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-refresh-action')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shared-search-action')));
    await tester.pump();
    final search = tester.widget<tab_components.SearchBar>(
      find.byType(tab_components.SearchBar),
    );
    search.onQueryChanged!('Album 2');
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('album-1')), findsNothing);
    expect(find.byKey(const ValueKey('album-2')), findsOneWidget);

    final sort = tester.widget<PopupMenuButton<SortOption>>(
      find.byKey(const ValueKey('shared-sort-menu')),
    );
    final sortOptions = sort
        .itemBuilder(
          tester.element(find.byKey(const ValueKey('shared-sort-menu'))),
        )
        .whereType<PopupMenuItem<SortOption>>()
        .map((item) => item.value)
        .toSet();
    expect(
      sortOptions,
      equals({
        SortOption.nameAsc,
        SortOption.nameDesc,
        SortOption.dateAsc,
        SortOption.dateDesc,
        SortOption.dateCreatedAsc,
        SortOption.dateCreatedDesc,
      }),
    );
    sort.onSelected!(SortOption.nameDesc);
    await tester.pump();
    expect(
      tester
          .widget<PopupMenuButton<SortOption>>(
            find.byKey(const ValueKey('shared-sort-menu')),
          )
          .initialValue,
      SortOption.nameDesc,
    );
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  for (final mode in [ViewMode.tiles, ViewMode.details, ViewMode.tree]) {
    testWidgets('Image Gallery supports ${mode.name} view', (tester) async {
      await mount(tester, '#gallery');
      await selectCollectionView(tester, mode);
      expect(
        find.byKey(ValueKey('grid-list-collection-${mode.name}')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('album-1')), findsOneWidget);
      expect(
        await tester.runAsync(
          () => UserPreferences.instance.getGridListCollectionMode(
            'albums',
            supportedModes: const {
              ViewMode.list,
              ViewMode.tiles,
              ViewMode.grid,
              ViewMode.details,
              ViewMode.tree,
            },
          ),
        ),
        mode,
      );
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    });
  }

  testWidgets('Image Gallery address bar accepts typed paths', (tester) async {
    await mount(tester, '#gallery');
    final bar = tester.widget<PathNavigationBar>(
      find.byType(PathNavigationBar),
    );
    expect(bar.enablePathEditing, isTrue);

    await tester.tap(find.byType(BreadcrumbAddressBar));
    await tester.pump();
    final editor = find.byType(EditableText);
    expect(editor, findsOneWidget);
    await tester.enterText(editor, '#home');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();
    expect(tabs.state.activeTab!.path, '#home');
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  testWidgets(
    'album toolbar exposes the system path and handles mouse history',
    (tester) async {
      await mount(tester, '#albums');
      final navFinder = find.byType(PathNavigationBar);
      final bar = tester.widget<PathNavigationBar>(navFinder);
      expect(bar.pathController.text, '#albums');
      expect(bar.currentPath, '#albums');
      expect(bar.tabPath, '#albums');
      expect(bar.enablePathEditing, isTrue);
      tabs.add(UpdateTabPath(tabs.state.activeTabId!, '#gallery'));
      await tester.pump();
      await tester.pump();
      expect(tabs.state.activeTab!.path, '#gallery');
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      await mouse.down(const Offset(1000, 800));
      await mouse.up();
      await mouse.removePointer();
      await tester.pump();
      await tester.pump();
      expect(tabs.state.activeTab!.path, '#albums');
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );

  testWidgets('Albums supports Ctrl multi selection and Ctrl+A', (
    tester,
  ) async {
    await mount(tester, '#albums');
    final first = find.byKey(const ValueKey('album-1'));
    final second = find.byKey(const ValueKey('album-2'));
    final firstName = find.descendant(
      of: first,
      matching: find.text('Album 1'),
    );
    final secondName = find.descendant(
      of: second,
      matching: find.text('Album 2'),
    );

    await tester.tap(firstName, kind: PointerDeviceKind.mouse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(secondName, kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<GridItemShell>(first).isSelected, isTrue);
    expect(tester.widget<GridItemShell>(second).isSelected, isTrue);
    expect(
      find.byKey(const ValueKey('albums-delete-selection')),
      findsOneWidget,
    );
    expect(find.text('2 items selected'), findsOneWidget);
    expect(find.textContaining('Calculating size'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.widget<GridItemShell>(first).isSelected, isFalse);
    expect(tester.widget<GridItemShell>(second).isSelected, isFalse);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(tester.widget<GridItemShell>(first).isSelected, isTrue);
    expect(tester.widget<GridItemShell>(second).isSelected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('delete 2 albums'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  testWidgets('Albums supports Shift range selection', (tester) async {
    await mount(tester, '#albums');
    final first = find.byKey(const ValueKey('album-1'));
    final second = find.byKey(const ValueKey('album-2'));
    await tester.tap(
      find.descendant(of: first, matching: find.text('Album 1')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(
      find.descendant(of: second, matching: find.text('Album 2')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(tester.widget<GridItemShell>(first).isSelected, isTrue);
    expect(tester.widget<GridItemShell>(second).isSelected, isTrue);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  for (final mode in [ViewMode.grid, ViewMode.list]) {
    testWidgets('Albums supports rubber-band drag selection in ${mode.name}', (
      tester,
    ) async {
      await mount(tester, '#albums');
      if (mode == ViewMode.list) {
        await selectCollectionView(tester, ViewMode.list);
      }
      final first = find.byKey(const ValueKey('album-1'));
      final second = find.byKey(const ValueKey('album-2'));
      final firstRect = tester.getRect(first);
      final secondRect = tester.getRect(second);
      final dragStart = Offset(
        math.min(firstRect.left, secondRect.left) + 2,
        math.min(firstRect.top, secondRect.top) + 2,
      );
      final dragEnd = Offset(
        math.max(firstRect.right, secondRect.right) - 2,
        math.max(firstRect.bottom, secondRect.bottom) - 2,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.down(dragStart);
      await mouse.moveTo(dragEnd);
      await mouse.up();
      await mouse.removePointer();
      await tester.pump();
      if (mode == ViewMode.grid) {
        expect(tester.widget<GridItemShell>(first).isSelected, isTrue);
        expect(tester.widget<GridItemShell>(second).isSelected, isTrue);
      } else {
        expect(tester.widget<ListItemShell>(first).isSelected, isTrue);
        expect(tester.widget<ListItemShell>(second).isSelected, isTrue);
      }
      expect(find.text('2 items selected'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    });
  }

  testWidgets('Albums restores the selected view when reopened', (
    tester,
  ) async {
    await mount(tester, '#albums');
    await selectCollectionView(tester, ViewMode.list);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
    await mount(tester, '#albums', reuseTabs: true);
    expect(
      find.byKey(const ValueKey('grid-list-collection-list')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<PopupMenuButton<ViewMode>>(
            find.byKey(const ValueKey('shared-view-mode-menu')),
          )
          .initialValue,
      ViewMode.list,
    );
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  testWidgets('inside an album retains the common toolbar and system address', (
    tester,
  ) async {
    final image = File('${root.path}${Platform.pathSeparator}detail-test.png');
    var added = false;
    await tester.runAsync(() async {
      await image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
      added = await AlbumService.instance.addFileToAlbum(1, image.path);
    });
    expect(added, isTrue);
    await mount(tester, '#album/1');
    expect(
      find.byKey(const ValueKey('fluent-browser-toolbar')),
      findsOneWidget,
    );
    final bar = tester.widget<PathNavigationBar>(
      find.byType(PathNavigationBar),
    );
    expect(bar.pathController.text, '#album/1');
    expect(bar.currentPath, '#album/1');
    expect(bar.enablePathEditing, isTrue);
    expect(find.byKey(const ValueKey('shared-search-action')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-sort-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-refresh-action')), findsOneWidget);
    final viewToggle = tester.widget<PopupMenuButton<ViewMode>>(
      find.byKey(const ValueKey('shared-view-mode-menu')),
    );
    viewToggle.onSelected!(ViewMode.grid);
    await flush(tester);
    final imageTile = find.byKey(ValueKey('album-grid-${image.path}'));
    expect(imageTile, findsOneWidget);
    await tester.tap(
      imageTile,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await flush(tester);
    expect(find.text('View Image'), findsOneWidget);
    expect(find.text('Open with'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Properties'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final viewOptions = viewToggle
        .itemBuilder(
          tester.element(find.byKey(const ValueKey('shared-view-mode-menu'))),
        )
        .whereType<PopupMenuItem<ViewMode>>()
        .map((item) => item.value)
        .toSet();
    expect(
      viewOptions,
      containsAll({
        ViewMode.list,
        ViewMode.tiles,
        ViewMode.grid,
        ViewMode.details,
        ViewMode.tree,
      }),
    );
    for (final mode in [ViewMode.tiles, ViewMode.details, ViewMode.tree]) {
      tester
          .widget<PopupMenuButton<ViewMode>>(
            find.byKey(const ValueKey('shared-view-mode-menu')),
          )
          .onSelected!(mode);
      await flush(tester);
      expect(
        tester
            .widget<PopupMenuButton<ViewMode>>(
              find.byKey(const ValueKey('shared-view-mode-menu')),
            )
            .initialValue,
        mode,
      );
      expect(
        find.byKey(ValueKey('${mode.name}-${image.path}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byIcon(PhosphorIconsLight.arrowUp));
    await tester.pump();
    await tester.pump();
    expect(tabs.state.activeTab!.path, '#gallery');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });
}
