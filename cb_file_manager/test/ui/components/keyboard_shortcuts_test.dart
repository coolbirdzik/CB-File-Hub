import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/config/languages/english_localizations.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/ui/components/keyboard_shortcuts/key_caps.dart';
import 'package:cb_file_manager/ui/components/keyboard_shortcuts/keyboard_shortcut_catalog.dart';
import 'package:cb_file_manager/ui/components/keyboard_shortcuts/keyboard_shortcuts_view.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_keyboard_shortcuts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = EnglishLocalizations();

  group('tab shortcut catalog', () {
    test('every binding the tab shell installs has a label', () {
      for (final intent in tabKeyboardShortcuts().values) {
        expect(
          tabShortcutLabel(intent, l10n),
          isNotNull,
          reason: '${intent.runtimeType} is bound but not documented',
        );
      }
    });

    test('is generated from the real bindings', () {
      final group = tabShortcutGroup(l10n);
      List<List<String>> combosFor(String label) =>
          group.entries.singleWhere((e) => e.label == label).combos;

      expect(combosFor(l10n.commandPaletteTitle), [
        ['Ctrl', 'K'],
      ]);
      // Ctrl+N is a second way to open a tab, not a new window.
      expect(combosFor(l10n.newTab), [
        ['Ctrl', 'T'],
        ['Ctrl', 'N'],
      ]);
      expect(combosFor(l10n.newWindow), [
        ['Ctrl', 'Shift', 'N'],
      ]);
      // Nine "go to tab N" bindings collapse into one row.
      expect(combosFor(l10n.shortcutSwitchToTab), [
        ['Ctrl', '1–9'],
      ]);
    });

    test('macOS shows ⌘ where a Ctrl alias also exists', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final group = tabShortcutGroup(l10n);
      final palette = group.entries.singleWhere(
        (e) => e.label == l10n.commandPaletteTitle,
      );
      expect(palette.combos, [
        ['⌘', 'K'],
      ]);
    });
  });

  test('key caps name keys the way menus do', () {
    expect(
      KeyCaps.forActivator(
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          alt: true,
          shift: true,
        ),
      ),
      ['Alt', 'Shift', '←'],
    );
    expect(KeyCaps.forKey(LogicalKeyboardKey.keyK), 'K');
    expect(KeyCaps.forKey(LogicalKeyboardKey.f5), 'F5');
    expect(KeyCaps.chord('W'), ['Ctrl', 'W']);
  });

  testWidgets('the reference lists every group and filters by search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeConfig.getDarkTheme(),
        localizationsDelegates: const [AppLocalizationsDelegate()],
        supportedLocales: const [Locale('en')],
        home: const Scaffold(
          body: KeyboardShortcutsView(showHomeTipToggle: false),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.shortcutsGroupTabs), findsOneWidget);
    expect(find.text(l10n.shortcutsGroupFiles), findsOneWidget);
    expect(find.text(l10n.shortcutsGroupImageViewer), findsOneWidget);
    expect(find.text(l10n.shortcutsGroupVideoPlayer), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('keyboard-shortcuts-search')),
      'mute',
    );
    await tester.pump();
    expect(find.text(l10n.shortcutMute), findsOneWidget);
    expect(find.text(l10n.newTab), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('keyboard-shortcuts-search')),
      'zzzz',
    );
    await tester.pump();
    expect(find.text(l10n.noResultsFound), findsOneWidget);
  });
}
