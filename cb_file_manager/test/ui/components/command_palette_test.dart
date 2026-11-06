import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/ui/components/command_palette/command_palette.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_keyboard_shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

CommandPaletteItem _item(
  String id,
  String title,
  CommandPaletteSection section, {
  String? subtitle,
  List<String> keywords = const [],
  VoidCallback? onRun,
}) => CommandPaletteItem(
  id: id,
  title: title,
  subtitle: subtitle,
  icon: Icons.circle,
  section: section,
  keywords: keywords,
  onRun: onRun ?? () {},
);

void main() {
  group('rankCommandPaletteItems', () {
    final items = [
      _item('c1', 'Close tab', CommandPaletteSection.commands),
      _item('p1', 'Settings', CommandPaletteSection.places),
      _item('t1', 'Downloads', CommandPaletteSection.tabs),
      _item('p2', 'Cài đặt mạng', CommandPaletteSection.places),
      _item(
        'c2',
        'Toggle theme',
        CommandPaletteSection.commands,
        keywords: ['dark mode'],
      ),
    ];

    test('an empty query keeps every item, grouped in section order', () {
      final ranked = rankCommandPaletteItems(items, '');
      expect(ranked.map((i) => i.id), ['t1', 'p1', 'p2', 'c1', 'c2']);
    });

    test('matches are accent-insensitive and include keywords', () {
      expect(rankCommandPaletteItems(items, 'cai dat').map((i) => i.id), [
        'p2',
      ]);
      expect(rankCommandPaletteItems(items, 'dark').map((i) => i.id), ['c2']);
    });

    test('prefix matches rank above mid-word matches within a section', () {
      final ranked = rankCommandPaletteItems([
        _item('a', 'New folder', CommandPaletteSection.commands),
        _item('b', 'Folder size', CommandPaletteSection.commands),
      ], 'fold');
      expect(ranked.map((i) => i.id), ['b', 'a']);
    });

    test('search-only items wait for a query; sections are capped', () {
      final folder = [
        for (var i = 0; i < 40; i++)
          CommandPaletteItem(
            id: 'f$i',
            title: 'photo $i.jpg',
            icon: Icons.circle,
            section: CommandPaletteSection.currentFolder,
            onlyWhenSearching: true,
            onRun: () {},
          ),
      ];
      expect(rankCommandPaletteItems(folder, ''), isEmpty);
      expect(
        rankCommandPaletteItems(folder, 'photo'),
        hasLength(kCommandPaletteSectionLimit),
      );
    });

    test('duplicate ids are shown once', () {
      final ranked = rankCommandPaletteItems([
        _item('x', 'Home', CommandPaletteSection.pinned),
        _item('x', 'Home', CommandPaletteSection.recent),
      ], '');
      expect(ranked, hasLength(1));
    });
  });

  test('Ctrl+K opens the palette', () {
    final bindings = tabKeyboardShortcuts().entries.where(
      (entry) =>
          entry.key is SingleActivator &&
          (entry.key as SingleActivator).trigger == LogicalKeyboardKey.keyK &&
          (entry.key as SingleActivator).control,
    );
    expect(bindings, hasLength(1));
    expect(bindings.single.value, isA<OpenCommandPaletteIntent>());
  });

  group('CommandPalette', () {
    Future<List<String>> pumpPalette(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ran = <String>[];
      final items = [
        _item(
          'tab',
          'Documents',
          CommandPaletteSection.tabs,
          onRun: () => ran.add('tab'),
        ),
        _item(
          'settings',
          'Settings',
          CommandPaletteSection.places,
          onRun: () => ran.add('settings'),
        ),
        _item(
          'theme',
          'Toggle theme',
          CommandPaletteSection.commands,
          onRun: () => ran.add('theme'),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeConfig.getDarkTheme(),
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showCommandPalette(
                  context: context,
                  items: items,
                  deferredItems: Future.value([
                    _item(
                      'recent',
                      'Projects',
                      CommandPaletteSection.recent,
                      subtitle: r'C:\Projects',
                      onRun: () => ran.add('recent'),
                    ),
                  ]),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return ran;
    }

    testWidgets('shows grouped items, including ones that load later', (
      tester,
    ) async {
      await pumpPalette(tester);
      expect(find.byKey(const ValueKey('command-palette')), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Open Tabs'), findsOneWidget);
      expect(find.text('Commands'), findsOneWidget);
    });

    testWidgets('typing filters, arrows move and Enter runs after closing', (
      tester,
    ) async {
      final ran = await pumpPalette(tester);
      final search = find.byKey(const ValueKey('command-palette-search'));
      await tester.enterText(search, 'tog');
      await tester.pump();
      expect(find.text('Documents'), findsNothing);
      expect(find.text('Toggle theme'), findsOneWidget);

      // "e" matches all four, shown as Documents, Projects, Settings, Toggle
      // theme (tabs, recent, places, commands). Down twice lands on Settings.
      await tester.enterText(search, 'e');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('command-palette')), findsNothing);
      expect(ran, ['settings']);
    });

    testWidgets('clicking a row runs it', (tester) async {
      final ran = await pumpPalette(tester);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(ran, ['settings']);
    });

    testWidgets('Escape closes without running anything', (tester) async {
      final ran = await pumpPalette(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('command-palette')), findsNothing);
      expect(ran, isEmpty);
      expect(CommandPalette.isOpen, isFalse);
    });

    testWidgets('an unmatched query says so', (tester) async {
      await pumpPalette(tester);
      await tester.enterText(
        find.byKey(const ValueKey('command-palette-search')),
        'zzzz',
      );
      await tester.pump();
      expect(find.text('No results found'), findsOneWidget);
    });
  });
}
