import 'dart:ui' show Tristate;

import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/config/fluent_theme_config.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/design_system/fluent_chrome_surface.dart';
import 'package:cb_file_manager/design_system/desktop_acrylic_theme_bridge.dart';
import 'package:cb_file_manager/design_system/fluent_surface_tokens.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/components/common/screen_scaffold.dart';
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

Widget _desktopFluentHost({
  required Widget child,
  required Brightness brightness,
}) {
  final baseTheme = brightness == Brightness.dark
      ? ThemeConfig.getDarkTheme()
      : ThemeConfig.getLightTheme();
  final appTheme = createDesktopAcrylicMaterialBridgeTheme(
    baseTheme: baseTheme,
    brightness: brightness,
    strength: 1.25,
    preferTransparentBackdrop: true,
  );
  final fluentTheme = FluentThemeConfig.getTheme(
    brightness == Brightness.dark ? AppThemeType.dark : AppThemeType.light,
    acrylicStrength: 1.25,
    preferTransparentBackdrop: true,
  );

  return fluent.FluentApp(
    theme: fluentTheme,
    darkTheme: fluentTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: Theme(data: appTheme, child: child),
  );
}

ScreenScaffold _screenScaffold() {
  return ScreenScaffold(
    selectionState: const SelectionState(),
    body: const SizedBox(key: ValueKey<String>('surface-test-body')),
    isNetworkPath: false,
    onClearSelection: () {},
    showRemoveTagsDialog: (_) {},
    showManageAllTagsDialog: (_) {},
    showDeleteConfirmationDialog: (_) {},
    isDesktop: true,
    showAppBar: true,
    showSearchBar: false,
    searchBar: const Text('Search'),
    pathNavigationBar: const Text('Path'),
    actions: const [],
  );
}

void main() {
  testWidgets('Fluent browser canvas and toolbar use bridged semantic surfaces',
      (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        _desktopFluentHost(
          brightness: brightness,
          child: _screenScaffold(),
        ),
      );

      final baseTheme = brightness == Brightness.dark
          ? ThemeConfig.getDarkTheme()
          : ThemeConfig.getLightTheme();
      final materialTheme = createDesktopAcrylicMaterialBridgeTheme(
        baseTheme: baseTheme,
        brightness: brightness,
        strength: 1.25,
        preferTransparentBackdrop: true,
      );
      final surfaces = FluentSurfaceTokens.fromTheme(materialTheme);
      final canvas = tester.widget<ColoredBox>(
        find.byKey(const ValueKey<String>('fluent-browser-canvas')),
      );
      final toolbar = tester.widget<FluentChromeSurface>(
        find.byKey(const ValueKey<String>('fluent-browser-toolbar')),
      );

      expect(canvas.color, materialTheme.scaffoldBackgroundColor);
      expect(canvas.color, surfaces.canvas);
      expect(toolbar.tint, surfaces.chromeTint);
      expect(toolbar.tintAlpha, surfaces.toolbarTintAlpha);
      expect(toolbar.blurSigma, surfaces.chromeBlur);
      final compositedToolbar = Color.alphaBlend(
        surfaces.toolbar,
        surfaces.canvas,
      );
      expect(surfaces.toolbar.a, lessThan(1.0));
      expect(
        compositedToolbar.computeLuminance(),
        lessThan(surfaces.canvas.computeLuminance()),
      );
    }
  });

  testWidgets('Fluent chrome explicitly composites toolbar and drawer alpha',
      (tester) async {
    for (final brightness in Brightness.values) {
      final baseTheme = brightness == Brightness.dark
          ? ThemeConfig.getDarkTheme()
          : ThemeConfig.getLightTheme();
      final materialTheme = createDesktopAcrylicMaterialBridgeTheme(
        baseTheme: baseTheme,
        brightness: brightness,
        strength: 1.25,
        preferTransparentBackdrop: true,
      );
      final surfaces = FluentSurfaceTokens.fromTheme(materialTheme);
      final background = surfaces.canvas;
      const boundaryKey = ValueKey<String>('chrome-rendered-surfaces');

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 220,
              height: 100,
              child: RepaintBoundary(
                key: boundaryKey,
                child: Stack(
                  children: [
                    ColoredBox(
                      color: background,
                      child: const SizedBox.expand(),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: FluentChromeSurface(
                          tint: surfaces.chromeTint,
                          tintAlpha: surfaces.toolbarTintAlpha,
                          blurSigma: 0,
                          borderRadius: BorderRadius.zero,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 120,
                      top: 0,
                      child: SizedBox(
                        width: 100,
                        height: 100,
                        child: FluentChromeSurface(
                          tint: surfaces.chromeTint,
                          tintAlpha: surfaces.drawerTintAlpha,
                          blurSigma: 0,
                          borderRadius: BorderRadius.zero,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      expect(boundary.size, const Size(220, 100));

      final renderedTintColors = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((decoratedBox) =>
              (decoratedBox.decoration as BoxDecoration).color)
          .whereType<Color>()
          .toList();
      expect(renderedTintColors, hasLength(2));
      final toolbarTint = surfaces.chromeTint.withValues(
        alpha: surfaces.toolbarTintAlpha,
      );
      final drawerTint = surfaces.chromeTint.withValues(
        alpha: surfaces.drawerTintAlpha,
      );
      expect(renderedTintColors, containsAll(<Color>[toolbarTint, drawerTint]));
      final expectedToolbar = Color.alphaBlend(toolbarTint, background);
      final expectedDrawer = Color.alphaBlend(drawerTint, background);
      expect(
        expectedDrawer.computeLuminance(),
        lessThan(expectedToolbar.computeLuminance()),
      );
      expect(
        expectedToolbar.computeLuminance(),
        lessThan(background.computeLuminance()),
      );
      expect(
        expectedDrawer.computeLuminance(),
        lessThan(background.computeLuminance()),
      );
    }
  });

  testWidgets('disabled Fluent navigation icons inherit disabled foreground',
      (tester) async {
    final materialTheme = ThemeConfig.getLightTheme();
    final surfaces = FluentSurfaceTokens.fromTheme(materialTheme);
    await tester.pumpWidget(
      _desktopFluentHost(
        brightness: Brightness.light,
        child: PathNavigationBar(
          tabId: 'test-tab',
          pathController: TextEditingController(),
          onPathSubmitted: (_) {},
          currentPath: r'C:\Users',
          tabPath: r'C:\Users',
        ),
      ),
    );

    final leftIcon = find.byIcon(PhosphorIconsLight.arrowLeft);
    final rightIcon = find.byIcon(PhosphorIconsLight.arrowRight);
    expect(leftIcon, findsOneWidget);
    expect(rightIcon, findsOneWidget);
    expect(tester.widget<Icon>(leftIcon).color, isNull);
    expect(tester.widget<Icon>(rightIcon).color, isNull);
    expect(IconTheme.of(tester.element(leftIcon)).color, surfaces.textDisabled);
    expect(
        IconTheme.of(tester.element(rightIcon)).color, surfaces.textDisabled);
  });

  testWidgets('Fluent breadcrumbs expose focus and keyboard activation',
      (tester) async {
    var activations = 0;
    final surfaces = FluentSurfaceTokens.fromTheme(ThemeConfig.getDarkTheme());
    await tester.pumpWidget(
      _desktopFluentHost(
        brightness: Brightness.dark,
        child: SizedBox(
          width: 420,
          child: BreadcrumbAddressBar(
            segments: [
              BreadcrumbSegment(
                label: 'Documents',
                onTap: () => activations++,
              ),
            ],
          ),
        ),
      ),
    );

    final segment = find.bySemanticsLabel('Documents').last;
    final hoverButton = find.byType(fluent.HoverButton);
    expect(hoverButton, findsOneWidget);
    final hoverButtonWidget = tester.widget<fluent.HoverButton>(hoverButton);
    expect(hoverButtonWidget.semanticLabel, 'Documents');
    expect(hoverButtonWidget.onPressed, isNotNull);
    final semantics = tester.getSemantics(segment);
    expect(semantics.flagsCollection.isFocused, isNot(Tristate.none));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester.getSemantics(segment).flagsCollection.isFocused,
      Tristate.isTrue,
    );
    final chip = find.descendant(
      of: hoverButton,
      matching: find.byType(AnimatedContainer),
    );
    final chipDecoration =
        tester.widget<AnimatedContainer>(chip).decoration! as BoxDecoration;
    expect(chipDecoration.border!.top.color, surfaces.focusRing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 120));
    expect(activations, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 120));
    expect(activations, 2);

    await tester.tap(segment);
    await tester.pump(const Duration(milliseconds: 120));
    expect(activations, 3);
  });
}
