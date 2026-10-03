import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/models/database/sqlite_database_provider.dart';
import 'package:cb_file_manager/ui/controllers/selection_tags_controller.dart';
import 'package:cb_file_manager/ui/widgets/file_properties_pane.dart';
import 'package:cb_file_manager/ui/widgets/file_pane_layout.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late String first;
  late String second;
  late SelectionTagsController controller;
  late Map<String, List<String>> store;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('cb_properties_test_');
    first = '${root.path}/first.txt';
    second = '${root.path}/second.txt';
    await File(first).writeAsString('first');
    await File(second).writeAsString('second');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => root.path);
    await TagManager.initialize();
    await TagHierarchyManager.instance.initialize();
    await TagThumbnailManager.instance.initialize();
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance().close();
    await SqliteDatabaseProvider.closeSharedDatabase();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await root.delete(recursive: true);
  });

  setUp(() {
    store = {
      first: ['work'],
      second: ['personal'],
    };
    controller = SelectionTagsController(
      read: (path) async => List.of(store[path]!),
      write: (path, tags) async {
        store[path] = List.of(tags);
        return true;
      },
      changed: (_) {},
      changes: const Stream.empty(),
      createHierarchy: (_, _) async {},
    );
  });
  tearDown(() {
    EditableText.debugDeterministicCursor = false;
    controller.dispose();
  });

  Widget app(Widget child) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en'), Locale('vi')],
    home: Scaffold(body: child),
  );

  Widget pane({
    List<String> files = const [],
    List<String> folders = const [],
    bool visible = true,
    double height = 260,
    ValueChanged<double>? resize,
    VoidCallback? close,
    Widget? child,
  }) => FilePropertiesPane(
    controller: controller,
    filePaths: files,
    folderPaths: folders,
    visible: visible,
    height: height,
    onHeightChanged: resize ?? (_) {},
    onClose: close ?? () {},
    child: child ?? const Text('file list'),
  );

  Future<void> settle(WidgetTester tester) async {
    // Filesystem and SQLite use real asynchronous I/O, outside fake test time.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
    expect(controller.saving, isFalse);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await TagManager.getRecentTags();
      await TagManager.instance.getPopularTags();
    });
    await tester.pump();
  }

  test('properties pane preferences default and round trip', () async {
    final prefs = UserPreferences.instance;
    expect(await prefs.getPropertiesPaneVisible(), isFalse);
    expect(await prefs.getPropertiesPaneHeight(), 260);
    await prefs.setPropertiesPaneVisible(true);
    await prefs.setPropertiesPaneHeight(310);
    expect(await prefs.getPropertiesPaneVisible(), isTrue);
    expect(await prefs.getPropertiesPaneHeight(), 310);
  });

  test('custom pane layout is persisted through user preferences', () async {
    final prefs = UserPreferences.instance;
    expect(await prefs.getFilePaneLayout(), '');
    final layout = FilePaneLayoutNode.defaults.dock(
      FilePane.properties,
      FilePane.preview,
      FilePaneEdge.left,
    );
    expect(await prefs.setFilePaneLayout(layout.encode()), isTrue);
    final restored = FilePaneLayoutNode.decode(await prefs.getFilePaneLayout());
    expect(restored.encode(), layout.encode());
    await prefs.setFilePaneLayout('');
  });

  testWidgets('empty and folder-only selection do not offer file tag input', (
    tester,
  ) async {
    await tester.pumpWidget(app(pane()));
    await settle(tester);
    expect(
      find.text('Select a file to view its properties and tags.'),
      findsOneWidget,
    );
    expect(find.byType(ChipsInput<String>), findsNothing);
    await tester.pumpWidget(app(pane(folders: [root.path])));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.paths, isEmpty);
    expect(find.byType(ChipsInput<String>), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('mixed selection shows counts and applies tags only to files', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(pane(files: [first, second], folders: [root.path])),
    );
    await settle(tester);
    expect(find.text('work 1/2'), findsOneWidget);
    expect(find.text('personal 1/2'), findsOneWidget);
    expect(find.text('Tags apply only to selected files.'), findsOneWidget);
    expect(controller.paths, hasLength(2));
    await tester.tap(find.text('work 1/2'));
    await settle(tester);
    expect(store[second], ['personal', 'work']);
    expect(find.text('work 2/2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets(
    'input saves immediately and switching selection discards draft',
    (tester) async {
      var selected = [first];
      late StateSetter update;
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return pane(files: selected);
            },
          ),
        ),
      );
      await settle(tester);
      final recentSnapshot = tester
          .widget<RecentTagsWidget>(find.byType(RecentTagsWidget))
          .loadRecentTags!(6);
      final popularSnapshot = tester
          .widget<PopularTagsWidget>(find.byType(PopularTagsWidget))
          .loadPopularTags!(6);
      final input = find.descendant(
        of: find.byType(ChipsInput<String>),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, 'urgent');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(store[first], ['work', 'urgent']);
      expect(
        identical(
          recentSnapshot,
          tester
              .widget<RecentTagsWidget>(find.byType(RecentTagsWidget))
              .loadRecentTags!(6),
        ),
        isTrue,
      );
      expect(
        identical(
          popularSnapshot,
          tester
              .widget<PopularTagsWidget>(find.byType(PopularTagsWidget))
              .loadPopularTags!(6),
        ),
        isTrue,
      );
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byType(ChipsInput<String>),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      await tester.enterText(input, 'uncommitted');
      update(() => selected = [second]);
      await settle(tester);
      expect(
        identical(
          recentSnapshot,
          tester
              .widget<RecentTagsWidget>(find.byType(RecentTagsWidget))
              .loadRecentTags!(6),
        ),
        isFalse,
      );
      final state = tester.state<ChipsInputState<String>>(
        find.byType(ChipsInput<String>),
      );
      expect(state.controller.textWithoutReplacements, isEmpty);
      expect(store[second], ['personal']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets(
    'saving a tag keeps the input position, focus and scroll offset stable',
    (tester) async {
      final started = Completer<void>();
      final finish = Completer<void>();
      addTearDown(() {
        if (!finish.isCompleted) finish.complete();
      });
      controller.dispose();
      controller = SelectionTagsController(
        read: (path) async => List.of(store[path]!),
        write: (path, tags) async {
          started.complete();
          await finish.future;
          store[path] = List.of(tags);
          return true;
        },
        changed: (_) {},
        changes: const Stream.empty(),
      );
      await tester.pumpWidget(app(pane(files: [first])));
      await settle(tester);
      final input = find.descendant(
        of: find.byType(ChipsInput<String>),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(input);
      await tester.tap(input);
      await tester.pumpAndSettle();
      final state = tester.state<ChipsInputState<String>>(
        find.byType(ChipsInput<String>),
      );
      final editable = tester.widget<EditableText>(
        find.descendant(of: input, matching: find.byType(EditableText)),
      );
      final scroll = Scrollable.of(tester.element(input)).position;
      final offset = scroll.pixels;
      final top = tester.getTopLeft(input);
      final height = tester.getSize(input).height;
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '\uFFFEnew',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await started.future;
      await tester.pump();
      expect(controller.saving, isTrue);
      expect(state.controller.textWithoutReplacements, isEmpty);
      expect(state.controller.values, ['work', 'new']);
      expect(find.text('new'), findsOneWidget);
      expect(tester.getTopLeft(input), top);
      expect(tester.getSize(input).height, height);
      expect(scroll.pixels, offset);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(
        identical(
          tester.state<ChipsInputState<String>>(
            find.byType(ChipsInput<String>),
          ),
          state,
        ),
        isTrue,
      );
      finish.complete();
      await settle(tester);
      expect(store[first], ['work', 'new']);
      expect(state.controller.values, ['work', 'new']);
      expect(tester.getTopLeft(input), top);
      expect(tester.getSize(input).height, height);
      expect(scroll.pixels, offset);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets('typing keeps tag suggestions visible during the next debounce', (
    tester,
  ) async {
    await tester.runAsync(
      () => TagManager.setTags(first, ['suggest-alpha', 'suggest-alpine']),
    );
    await tester.pumpWidget(app(pane(files: [first])));
    await settle(tester);
    final input = find.descendant(
      of: find.byType(ChipsInput<String>),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(input);
    await tester.tap(input);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\uFFFEsuggest-al',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
    await settle(tester);
    final suggestions = tester
        .widget<ChipsInput<String>>(find.byType(ChipsInput<String>))
        .suggestions;
    expect(suggestions, containsAll(['suggest-alpha', 'suggest-alpine']));
    final overlayHeading = find.text('Suggested tags');
    expect(overlayHeading, findsOneWidget);
    final headingElement = tester.element(overlayHeading);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\uFFFEsuggest-alp',
        selection: TextSelection.collapsed(offset: 12),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester
          .widget<ChipsInput<String>>(find.byType(ChipsInput<String>))
          .suggestions,
      suggestions,
    );
    expect(overlayHeading, findsOneWidget);
    expect(identical(tester.element(overlayHeading), headingElement), isTrue);
    // An empty draft must still dismiss the popup immediately.
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '\uFFFE',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(overlayHeading, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => TagManager.setTags(first, []));
    await settle(tester);
  });

  testWidgets(
    'docking properties preserves a tag draft when its contents change columns',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final layout = FilePaneLayoutController();
      addTearDown(layout.dispose);
      var layoutBuilds = 0;
      await tester.pumpWidget(
        app(
          FilePropertiesPane(
            controller: controller,
            filePaths: [first],
            folderPaths: const [],
            visible: true,
            height: 260,
            onHeightChanged: (_) {},
            onClose: () {},
            headerLeading: const FilePaneDragHandle(pane: FilePane.properties),
            paneLayoutBuilder: (context, panel) {
              layoutBuilds++;
              return FilePaneLayout(
                controller: layout,
                files: const Text('file list'),
                preview: const SizedBox(),
                properties: panel,
                previewVisible: true,
                propertiesVisible: true,
                previewWidth: 360,
                propertiesHeight: 260,
              );
            },
            child: const SizedBox(),
          ),
        ),
      );
      await settle(tester);
      final input = find.descendant(
        of: find.byType(ChipsInput<String>),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, 'uncommitted');
      final before = tester.state<ChipsInputState<String>>(
        find.byType(ChipsInput<String>),
      );
      layout.update(
        layout.value.dock(
          FilePane.properties,
          FilePane.files,
          FilePaneEdge.left,
        ),
        persist: false,
      );
      await settle(tester);
      final after = tester.state<ChipsInputState<String>>(
        find.byType(ChipsInput<String>),
      );
      expect(identical(before, after), isTrue);
      expect(after.controller.textWithoutReplacements, 'uncommitted');
      final buildsBeforeSaving = layoutBuilds;
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(store[first], ['work', 'uncommitted']);
      expect(layoutBuilds, buildsBeforeSaving);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );

  testWidgets(
    'resize clamps to half, collapse preserves list element and narrow layout fits',
    (tester) async {
      var visible = true;
      var height = 260.0;
      late StateSetter update;
      const listKey = ValueKey('persistent-list');
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return pane(
                visible: visible,
                height: height,
                resize: (value) => setState(() => height = value),
                close: () => setState(() => visible = false),
                child: ListView(
                  key: listKey,
                  children: List.generate(100, (i) => Text('row $i')),
                ),
              );
            },
          ),
        ),
      );
      await settle(tester);
      final element = tester.element(find.byKey(listKey));
      await tester.drag(
        find.byKey(const ValueKey('properties-pane-resize')),
        const Offset(0, -500),
      );
      await settle(tester);
      expect(height, lessThanOrEqualTo(300));
      await tester.tap(find.byTooltip('Collapse properties and tags'));
      await settle(tester);
      expect(identical(tester.element(find.byKey(listKey)), element), isTrue);
      update(() => visible = true);
      await settle(tester);
      expect(identical(tester.element(find.byKey(listKey)), element), isTrue);
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(pane(files: [first, second])));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
