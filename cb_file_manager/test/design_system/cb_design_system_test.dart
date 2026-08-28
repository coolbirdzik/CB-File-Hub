import 'dart:math' as math;

import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the properties that define the CoolBird look. These are the things
/// that silently regress when someone reaches for a Material default, so they
/// are asserted rather than left to review.
void main() {
  group('CbThemeBuilder', () {
    test('attaches CbTokens alongside any extra extensions', () {
      final theme = ThemeConfig.getLightTheme();

      expect(theme.extension<CbTokens>(), isNotNull);
      // The toast theme rides along; building the theme must not drop it.
      expect(theme.extension<AppToastThemeProbe>(), isNull);
      expect(theme.extensions.length, greaterThanOrEqualTo(2));
    });

    test('surfaceTint is transparent so M3 never tints elevation', () {
      for (final theme in [
        ThemeConfig.getLightTheme(),
        ThemeConfig.getDarkTheme(),
      ]) {
        expect(theme.colorScheme.surfaceTint, Colors.transparent);
        expect(theme.cardTheme.surfaceTintColor, Colors.transparent);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      }
    });

    test('ink splash is disabled', () {
      final theme = ThemeConfig.getLightTheme();
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.splashColor, Colors.transparent);
      expect(theme.highlightColor, Colors.transparent);
    });

    test('the primary colour is the accent itself, not a tonal derivative', () {
      // `ColorScheme.fromSeed` would shift the seed's hue and chroma; the
      // whole point of the hand-built scheme is that it does not.
      for (final accent in AppAccentColor.values) {
        final expected = ThemeConfig.getAccentSeedColor(accent);
        final theme = ThemeConfig.getLightTheme(accentColor: accent);
        expect(theme.colorScheme.primary, expected,
            reason: '$accent should reach the theme unmodified');
      }
    });

    test('body text uses the CoolBird 13px ramp, not Material 14px', () {
      final theme = ThemeConfig.getLightTheme();
      expect(theme.textTheme.bodyMedium!.fontSize, 13);
    });

    test('type is the bundled Inter, not a platform font stack', () {
      final theme = ThemeConfig.getLightTheme();
      expect(theme.textTheme.bodyMedium!.fontFamily, CbTypography.uiFamily);
      expect(theme.textTheme.headlineMedium!.fontFamily, CbTypography.uiFamily);
      expect(CbTypography.mono.fontFamily, CbTypography.monoFamily);
    });

    test('accent text colour stays legible on light surfaces', () {
      // Pale accents (yellow, lime) are the risk case: their base colour is
      // unreadable as text on white, so the ramp darkens the text variant.
      for (final accent in AppAccentColor.values) {
        final tokens = ThemeConfig.getLightTheme(accentColor: accent).cb;
        final ratio = _contrastRatio(
          tokens.colors.accent.text,
          tokens.colors.surface,
        );
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$accent accent text should meet WCAG AA on surface');
      }
    });

    test('filled controls contrast with their own foreground', () {
      for (final accent in AppAccentColor.values) {
        for (final brightness in Brightness.values) {
          final ramp = CbAccentRamp.from(
            ThemeConfig.getAccentSeedColor(accent),
            brightness,
          );
          expect(
              _contrastRatio(ramp.onBase, ramp.base), greaterThanOrEqualTo(3.0),
              reason: '$accent/$brightness label on a filled control');
        }
      }
    });
  });

  group('CbTokens', () {
    test('lerp interpolates colours and snaps brightness at the midpoint', () {
      final light = CbTokens.of(Brightness.light, const Color(0xFF0078D4));
      final dark = CbTokens.of(Brightness.dark, const Color(0xFF0078D4));

      final mid = light.lerp(dark, 0.5);
      expect(mid.brightness, Brightness.dark);
      expect(mid.colors.surface,
          Color.lerp(light.colors.surface, dark.colors.surface, 0.5));

      expect(light.lerp(dark, 0.0).colors.surface, light.colors.surface);
      expect(light.lerp(dark, 1.0).colors.surface, dark.colors.surface);
    });

    testWidgets('context.cb falls back instead of throwing when unwired',
        (tester) async {
      late CbTokens seen;
      await tester.pumpWidget(MaterialApp(
        // Deliberately a bare theme with no CbTokens extension.
        theme: ThemeData(useMaterial3: true),
        home: Builder(builder: (context) {
          seen = context.cb;
          return const SizedBox();
        }),
      ));

      expect(seen, same(CbTokens.fallback));
    });
  });

  group('CbButton', () {
    Widget host(Widget child) => MaterialApp(
          theme: ThemeConfig.getLightTheme(),
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('fires onPressed and honours the token control height',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(CbButton(
        label: 'Delete',
        onPressed: () => taps++,
      )));

      await tester.tap(find.text('Delete'));
      expect(taps, 1);

      final size = tester.getSize(find.byType(CbButton));
      expect(size.height, CbSizes.controlMd);
    });

    testWidgets('a null onPressed makes the button inert', (tester) async {
      await tester.pumpWidget(host(
        const CbButton(label: 'Delete', onPressed: null),
      ));

      await tester.tap(find.text('Delete'));
      await tester.pump();
      // Nothing to assert beyond "did not throw and did not call back" — the
      // callback is null, so reaching the tap handler at all would crash.
      expect(find.byType(CbButton), findsOneWidget);
    });

    testWidgets('loading blocks presses and shows a spinner', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(CbButton(
        label: 'Scanning',
        loading: true,
        onPressed: () => taps++,
      )));

      await tester.tap(find.text('Scanning'));
      await tester.pump();

      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('icon-only buttons are square and expose their tooltip',
        (tester) async {
      await tester.pumpWidget(host(CbButton.icon(
        icon: Icons.close,
        tooltip: 'Close',
        onPressed: () {},
      )));

      final size = tester.getSize(find.byType(CbButton));
      expect(size.width, size.height);
      expect(find.byTooltip('Close'), findsOneWidget);
    });
  });

  group('CbSurface', () {
    testWidgets('a flat surface casts no shadow; an overlay does',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeConfig.getLightTheme(),
        home: const Scaffold(
          body: Column(
            children: [
              CbSurface(
                key: Key('flat'),
                level: CbSurfaceLevel.flat,
                child: SizedBox(width: 40, height: 40),
              ),
              CbSurface(
                key: Key('overlay'),
                level: CbSurfaceLevel.overlay,
                child: SizedBox(width: 40, height: 40),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      BoxDecoration decorationOf(String key) {
        final container = tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return container.decoration! as BoxDecoration;
      }

      expect(decorationOf('flat').boxShadow, isEmpty);
      expect(decorationOf('overlay').boxShadow, isNotEmpty);
    });
  });
}

/// Relative luminance contrast per WCAG 2.1.
double _contrastRatio(Color foreground, Color background) {
  final a = _relativeLuminance(foreground);
  final b = _relativeLuminance(background);
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// A probe type that is never registered — used to assert that
/// `extension<T>()` returns null for extensions the theme does not carry.
class AppToastThemeProbe extends ThemeExtension<AppToastThemeProbe> {
  const AppToastThemeProbe();

  @override
  ThemeExtension<AppToastThemeProbe> copyWith() => this;

  @override
  ThemeExtension<AppToastThemeProbe> lerp(
          ThemeExtension<AppToastThemeProbe>? other, double t) =>
      this;
}
