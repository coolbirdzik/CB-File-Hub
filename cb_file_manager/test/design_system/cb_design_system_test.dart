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

    test('chrome is flat: no outline on cards, dialogs, menus, chips', () {
      BorderSide sideOf(ShapeBorder? shape) =>
          shape is OutlinedBorder ? shape.side : BorderSide.none;

      for (final theme in [
        ThemeConfig.getLightTheme(),
        ThemeConfig.getDarkTheme(),
      ]) {
        expect(sideOf(theme.cardTheme.shape), BorderSide.none);
        expect(sideOf(theme.dialogTheme.shape), BorderSide.none);
        expect(sideOf(theme.popupMenuTheme.shape), BorderSide.none);
        expect(sideOf(theme.snackBarTheme.shape), BorderSide.none);
        expect(theme.chipTheme.side, BorderSide.none);
        expect(theme.tabBarTheme.dividerColor, Colors.transparent);
        expect(
          sideOf(theme.menuTheme.style!.shape!.resolve(const {})),
          BorderSide.none,
        );
        // OutlinedButton keeps its name but renders as a tonal button.
        final outlined = theme.outlinedButtonTheme.style!;
        expect(
          outlined.side?.resolve(const {}),
          anyOf(isNull, BorderSide.none),
        );
        expect(
          outlined.backgroundColor!.resolve(const {}),
          theme.cb.colors.fill,
        );
        // Inputs show no line at rest; focus is a bottom accent indicator.
        final inputs = theme.inputDecorationTheme;
        expect(inputs.enabledBorder!.borderSide, BorderSide.none);
        expect(inputs.focusedBorder, isA<UnderlineInputBorder>());
        expect(
          inputs.focusedBorder!.borderSide.color,
          theme.cb.colors.accent.base,
        );
      }
    });

    test('the surface container ladder steps in tone, never repeats white', () {
      for (final theme in [
        ThemeConfig.getLightTheme(),
        ThemeConfig.getDarkTheme(),
      ]) {
        final s = theme.colorScheme;
        final ladder = [
          s.surfaceContainerLowest,
          s.surfaceContainerLow,
          s.surfaceContainer,
          s.surfaceContainerHigh,
          s.surfaceContainerHighest,
        ];
        // Each step must be distinguishable from the one below it; flat cards
        // painted from this ladder have no outline to fall back on.
        for (var i = 1; i < ladder.length; i++) {
          expect(ladder[i], isNot(ladder[i - 1]), reason: 'step $i');
        }
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
        expect(
          theme.colorScheme.primary,
          expected,
          reason: '$accent should reach the theme unmodified',
        );
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
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$accent accent text should meet WCAG AA on surface',
        );
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
            _contrastRatio(ramp.onBase, ramp.base),
            greaterThanOrEqualTo(3.0),
            reason: '$accent/$brightness label on a filled control',
          );
        }
      }
    });
  });

  group('CbDecorations.selectionFill', () {
    // Measured as perceptual distance (ΔE) from the canvas rather than
    // luminance contrast: a pale yellow wash is lighter than the grey hover
    // fill yet far easier to spot, and contrast alone would call it fainter.
    // The old opaque `accent.tintStrong` managed only ~1.5× hover with the
    // default blue, which is what made selected items hard to find.
    test('selection stands at least twice as far off the canvas as hover', () {
      for (final accent in AppAccentColor.values) {
        for (final brightness in Brightness.values) {
          final tokens = CbTokens.of(
            brightness,
            ThemeConfig.getAccentSeedColor(accent),
          );
          final canvas = tokens.colors.canvas;
          double offset(Color fill) =>
              _deltaE(Color.alphaBlend(fill, canvas), canvas);

          final hover = offset(tokens.colors.fillHover);
          final selected = offset(CbDecorations.selectionFill(tokens));
          final selectedHover = offset(
            CbDecorations.selectionFill(tokens, hovered: true),
          );

          expect(
            selected,
            greaterThanOrEqualTo(hover * 2),
            reason: '$accent/$brightness selected vs hovered item',
          );
          expect(
            selectedHover,
            greaterThan(selected),
            reason: '$accent/$brightness hovering a selected item',
          );
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
      expect(
        mid.colors.surface,
        Color.lerp(light.colors.surface, dark.colors.surface, 0.5),
      );

      expect(light.lerp(dark, 0.0).colors.surface, light.colors.surface);
      expect(light.lerp(dark, 1.0).colors.surface, dark.colors.surface);
    });

    testWidgets('context.cb falls back instead of throwing when unwired', (
      tester,
    ) async {
      late CbTokens seen;
      await tester.pumpWidget(
        MaterialApp(
          // Deliberately a bare theme with no CbTokens extension.
          theme: ThemeData(useMaterial3: true),
          home: Builder(
            builder: (context) {
              seen = context.cb;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(seen, same(CbTokens.fallback));
    });
  });

  group('CbButton', () {
    Widget host(Widget child) => MaterialApp(
      theme: ThemeConfig.getLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('fires onPressed and honours the token control height', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(CbButton(label: 'Delete', onPressed: () => taps++)),
      );

      await tester.tap(find.text('Delete'));
      expect(taps, 1);

      final size = tester.getSize(find.byType(CbButton));
      expect(size.height, CbSizes.controlMd);
    });

    testWidgets('a null onPressed makes the button inert', (tester) async {
      await tester.pumpWidget(
        host(const CbButton(label: 'Delete', onPressed: null)),
      );

      await tester.tap(find.text('Delete'));
      await tester.pump();
      // Nothing to assert beyond "did not throw and did not call back" — the
      // callback is null, so reaching the tap handler at all would crash.
      expect(find.byType(CbButton), findsOneWidget);
    });

    testWidgets('loading blocks presses and shows a spinner', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          CbButton(label: 'Scanning', loading: true, onPressed: () => taps++),
        ),
      );

      await tester.tap(find.text('Scanning'));
      await tester.pump();

      expect(taps, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('icon-only buttons are square and expose their tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          CbButton.icon(icon: Icons.close, tooltip: 'Close', onPressed: () {}),
        ),
      );

      final size = tester.getSize(find.byType(CbButton));
      expect(size.width, size.height);
      expect(find.byTooltip('Close'), findsOneWidget);
    });
  });

  group('CbSurface', () {
    testWidgets('a flat surface casts no shadow; an overlay does', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
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

/// CIE76 colour difference: how far apart two colours look, whatever their
/// hue.
double _deltaE(Color a, Color b) {
  final (l1, a1, b1) = _lab(a);
  final (l2, a2, b2) = _lab(b);
  return math.sqrt(
    math.pow(l1 - l2, 2) + math.pow(a1 - a2, 2) + math.pow(b1 - b2, 2),
  );
}

/// CIE L*a*b* (D65) of an sRGB colour.
(double, double, double) _lab(Color color) {
  double linear(double value) => value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  final r = linear(color.r);
  final g = linear(color.g);
  final b = linear(color.b);
  final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
  final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
  double f(double t) =>
      t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = f(x);
  final fy = f(y);
  final fz = f(z);
  return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

/// A probe type that is never registered — used to assert that
/// `extension<T>()` returns null for extensions the theme does not carry.
class AppToastThemeProbe extends ThemeExtension<AppToastThemeProbe> {
  const AppToastThemeProbe();

  @override
  ThemeExtension<AppToastThemeProbe> copyWith() => this;

  @override
  ThemeExtension<AppToastThemeProbe> lerp(
    ThemeExtension<AppToastThemeProbe>? other,
    double t,
  ) => this;
}
