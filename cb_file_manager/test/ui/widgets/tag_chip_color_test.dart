import 'dart:convert';

import 'package:cb_file_manager/config/languages/app_localizations_delegate.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/ui/widgets/chips_input.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart';
import 'package:cb_file_manager/ui/widgets/tag_chips_field.dart';
import 'package:cb_file_manager/ui/widgets/tag_management_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Color backgroundOf(WidgetTester tester, Finder chip) => tester
    .widgetList<Container>(
      find.descendant(of: chip, matching: find.byType(Container)),
    )
    .map((widget) => widget.decoration)
    .whereType<BoxDecoration>()
    .singleWhere(
      (decoration) =>
          decoration.borderRadius == BorderRadius.circular(TagChipStyle.radius),
    )
    .color!;

void main() {
  final colors = TagColorManager.instance;
  const tag = 'Saved color';
  const palette = [Color(0xFF17314F), Color(0xFFFFE082)];

  for (final brightness in Brightness.values) {
    for (final color in palette) {
      testWidgets(
        'dialog and Properties chips match file chips in $brightness for $color',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            'tag_colors': jsonEncode({tag: color.toARGB32()}),
          });
          await colors.initialize();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              localizationsDelegates: const [AppLocalizationsDelegate()],
              supportedLocales: const [Locale('en')],
              home: Scaffold(
                body: Column(
                  children: [
                    const TagChip(tag: tag),
                    TagChipsField(
                      tags: const [tag],
                      chipLabel: (_) => '$tag 1/2',
                      suggestions: const [],
                      scopeParent: null,
                      onScopeChanged: (_) {},
                      onSuggestionSelected: (_) {},
                      onTextChanged: (_) {},
                      onSubmitted: (_) {},
                      onRemoved: (_) {},
                    ),
                    AnimatedTagChip(tag: tag, displayText: tag, onTap: () {}),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          void expectColors(Color source) {
            final browserChip = tester.widget<Chip>(find.byType(Chip));
            final expected = brightness == Brightness.dark
                ? Color.alphaBlend(Colors.white.withValues(alpha: .3), source)
                : source;
            expect(browserChip.backgroundColor, expected);
            expect(backgroundOf(tester, find.byType(TagInputChip)), expected);
            expect(
              backgroundOf(tester, find.byType(AnimatedTagChip)),
              expected,
            );
            final label = tester.widget<Text>(find.text('$tag 1/2'));
            expect(label.style!.color, browserChip.labelStyle!.color);
            expect(
              label.style!.color,
              source == palette.first ? Colors.white : Colors.black,
            );
          }

          expectColors(color);
          // Changing a saved color updates every visible representation, without
          // closing the dialog or changing the Properties selection.
          final replacement = color == palette.first
              ? palette.last
              : palette.first;
          await colors.setTagColor(tag, replacement);
          await tester.pumpAndSettle();
          expectColors(replacement);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'parent scope uses the same color and contrasting text as file chips',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'tag_colors': jsonEncode({tag: palette.first.toARGB32()}),
      });
      await colors.initialize();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppLocalizationsDelegate()],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: Column(
              children: [
                const TagChip(tag: tag),
                TagChipsField(
                  tags: const [],
                  suggestions: const [],
                  scopeParent: tag,
                  onScopeChanged: (_) {},
                  onSuggestionSelected: (_) {},
                  onTextChanged: (_) {},
                  onSubmitted: (_) {},
                  onRemoved: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final browserChip = tester.widget<Chip>(find.byType(Chip));
      expect(
        backgroundOf(tester, find.byType(TagScopeChip)),
        browserChip.backgroundColor,
      );
      final parent = tester.widget<Text>(
        find.descendant(
          of: find.byType(TagScopeChip),
          matching: find.text(tag),
        ),
      );
      expect(parent.style!.color, browserChip.labelStyle!.color);
    },
  );

  test(
    'loading empty preferences drops colors from the previous profile',
    () async {
      SharedPreferences.setMockInitialValues({
        'tag_colors': jsonEncode({tag: palette.first.toARGB32()}),
      });
      await colors.initialize();
      expect(colors.getTagColor(tag), palette.first);
      SharedPreferences.setMockInitialValues({});
      await colors.initialize();
      expect(colors.getAllTagColors(), isEmpty);
    },
  );
}
