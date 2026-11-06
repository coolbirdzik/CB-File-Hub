import 'package:flutter/foundation.dart';
import 'macos_glass_theme.dart';
import 'desktop_acrylic_theme.dart';
import 'package:flutter/material.dart';

/// Resolves the Material surface theme used alongside the desktop acrylic
/// backdrop. The native backdrop supplies the translucency; this theme keeps
/// Flutter-rendered surfaces and overlays on the same visual ramp.
ThemeData createDesktopAcrylicMaterialBridgeTheme({
  required ThemeData baseTheme,
  required Brightness brightness,
  required double strength,
  required bool preferTransparentBackdrop,
  double glassBlurStrength = 1,
  TargetPlatform? platform,
}) {
  final glass = (platform ?? defaultTargetPlatform) == TargetPlatform.macOS
      ? MacosGlassTheme(
          strength: strength,
          blurStrength: glassBlurStrength,
          brightness: brightness,
        )
      : null;
  final acrylic = DesktopAcrylicTheme(
    strength: strength,
    brightness: brightness,
    dynamicBackdrop: preferTransparentBackdrop,
  );
  final bool isLightMode = brightness == Brightness.light;
  const Color fluentLightBackground2 = Color(0xFFF4F4F5);
  const Color fluentLightBackground3 = Color(0xFFFFFFFF);
  final scaffoldOpacity = glass?.canvasOpacity ?? acrylic.canvasOpacity;
  final appBarOpacity = glass?.chromeOpacity ?? acrylic.chromeOpacity;
  final surfaceOpacity = glass?.surfaceOpacity ?? acrylic.surfaceOpacity;
  final containerOpacity = glass?.containerOpacity ?? acrylic.containerOpacity;
  final lowContainerOpacity =
      glass?.lowContainerOpacity ?? acrylic.lowContainerOpacity;
  final lowestContainerOpacity =
      glass?.lowestContainerOpacity ?? acrylic.lowestContainerOpacity;

  final colorScheme = baseTheme.colorScheme;
  Color surface(Color tint, double opacity, {bool inverse = false}) =>
      glass?.readableSurface(
        tint,
        opacity: opacity,
        foregrounds: inverse
            ? [colorScheme.onInverseSurface]
            : [colorScheme.onSurface, colorScheme.onSurfaceVariant],
      ) ??
      tint.withValues(alpha: opacity);
  const Color lightSurfaceBase = fluentLightBackground3;
  final Color effectiveSurfaceBase = isLightMode
      ? lightSurfaceBase
      : colorScheme.surface;

  // The container ladder keeps its tonal steps under acrylic. Collapsing
  // every level onto one base colour (as this bridge used to) only worked
  // while cards carried an outline; flat cards need the steps to show.
  Color container(Color base) => surface(base, containerOpacity);

  final bridgedColorScheme = colorScheme.copyWith(
    surface: surface(effectiveSurfaceBase, surfaceOpacity),
    surfaceBright: surface(
      isLightMode ? lightSurfaceBase : colorScheme.surfaceBright,
      surfaceOpacity,
    ),
    surfaceDim: surface(
      isLightMode ? fluentLightBackground2 : colorScheme.surfaceDim,
      surfaceOpacity,
    ),
    surfaceContainer: container(colorScheme.surfaceContainer),
    surfaceContainerHigh: container(colorScheme.surfaceContainerHigh),
    surfaceContainerHighest: container(colorScheme.surfaceContainerHighest),
    surfaceContainerLow: surface(
      colorScheme.surfaceContainerLow,
      lowContainerOpacity,
    ),
    surfaceContainerLowest: surface(
      effectiveSurfaceBase,
      lowestContainerOpacity,
    ),
    inverseSurface: surface(
      colorScheme.inverseSurface,
      surfaceOpacity,
      inverse: true,
    ),
    surfaceTint: Colors.transparent,
  );

  // Dialogs, menus and dropdown overlays stay solid even when page chrome
  // uses acrylic, and sit one tonal step above the canvas; their hairline
  // edge (from the base theme's shapes) finishes the separation.
  final Color dialogColor = colorScheme.surfaceContainer;
  final Color menuColor = colorScheme.surfaceContainer;

  return baseTheme.copyWith(
    extensions: [
      ...baseTheme.extensions.values.where(
        (value) => value is! MacosGlassTheme && value is! DesktopAcrylicTheme,
      ),
      if (glass != null) glass else acrylic,
    ],
    colorScheme: bridgedColorScheme,
    scaffoldBackgroundColor: surface(
      baseTheme.scaffoldBackgroundColor,
      scaffoldOpacity,
    ),
    canvasColor: menuColor,
    // Cards keep the base theme's translucent flat fill, which already
    // composites correctly over the acrylic backdrop.
    cardColor: container(colorScheme.surfaceContainer),
    dialogTheme: baseTheme.dialogTheme.copyWith(backgroundColor: dialogColor),
    popupMenuTheme: baseTheme.popupMenuTheme.copyWith(
      color: menuColor,
      surfaceTintColor: Colors.transparent,
    ),
    dropdownMenuTheme: baseTheme.dropdownMenuTheme.copyWith(
      menuStyle: (baseTheme.dropdownMenuTheme.menuStyle ?? const MenuStyle())
          .copyWith(
            backgroundColor: WidgetStatePropertyAll(menuColor),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
    ),
    bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
      backgroundColor: dialogColor,
      modalBackgroundColor: dialogColor,
    ),
    appBarTheme: baseTheme.appBarTheme.copyWith(
      backgroundColor: surface(
        baseTheme.appBarTheme.backgroundColor ??
            baseTheme.scaffoldBackgroundColor,
        appBarOpacity,
      ),
      surfaceTintColor: Colors.transparent,
    ),
  );
}
