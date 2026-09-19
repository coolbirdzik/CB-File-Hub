import 'package:flutter/material.dart';

/// Resolves the Material surface theme used alongside the desktop acrylic
/// backdrop. The native backdrop supplies the translucency; this theme keeps
/// Flutter-rendered surfaces and overlays on the same visual ramp.
ThemeData createDesktopAcrylicMaterialBridgeTheme({
  required ThemeData baseTheme,
  required Brightness brightness,
  required double strength,
  required bool preferTransparentBackdrop,
}) {
  final double normalizedStrength = strength.clamp(0.0, 2.0).toDouble();
  final bool isLightMode = brightness == Brightness.light;
  const Color fluentLightBackground2 = Color(0xFFF3F4F7);
  const Color fluentLightBackground3 = Color(0xFFFFFFFF);

  double opacityByStrength({
    required double solidAtMin,
    required double glassAtMax,
  }) {
    return solidAtMin + (glassAtMax - solidAtMin) * normalizedStrength;
  }

  final scaffoldOpacity = brightness == Brightness.dark
      ? opacityByStrength(
          solidAtMin: 0.90,
          glassAtMax: preferTransparentBackdrop ? 0.24 : 0.34,
        )
      : opacityByStrength(
          solidAtMin: 0.99,
          glassAtMax: preferTransparentBackdrop ? 0.62 : 0.92,
        );
  final appBarOpacity = brightness == Brightness.dark
      ? opacityByStrength(
          solidAtMin: 0.94,
          glassAtMax: preferTransparentBackdrop ? 0.36 : 0.46,
        )
      : opacityByStrength(
          solidAtMin: 0.99,
          glassAtMax: preferTransparentBackdrop ? 0.70 : 0.93,
        );
  final surfaceOpacity = brightness == Brightness.dark
      ? opacityByStrength(
          solidAtMin: 0.88,
          glassAtMax: preferTransparentBackdrop ? 0.30 : 0.40,
        )
      : opacityByStrength(
          solidAtMin: 0.99,
          glassAtMax: preferTransparentBackdrop ? 0.72 : 0.90,
        );
  final containerOpacity = brightness == Brightness.dark
      ? opacityByStrength(
          solidAtMin: 0.84,
          glassAtMax: preferTransparentBackdrop ? 0.28 : 0.36,
        )
      : opacityByStrength(
          solidAtMin: 0.98,
          glassAtMax: preferTransparentBackdrop ? 0.68 : 0.88,
        );
  final lowContainerOpacity = brightness == Brightness.dark
      ? opacityByStrength(
          solidAtMin: 0.80,
          glassAtMax: preferTransparentBackdrop ? 0.24 : 0.32,
        )
      : opacityByStrength(
          solidAtMin: 0.98,
          glassAtMax: preferTransparentBackdrop ? 0.62 : 0.86,
        );
  final lowestContainerOpacity = brightness == Brightness.dark
      ? opacityByStrength(
          solidAtMin: 0.76,
          glassAtMax: preferTransparentBackdrop ? 0.20 : 0.28,
        )
      : opacityByStrength(
          solidAtMin: 0.97,
          glassAtMax: preferTransparentBackdrop ? 0.56 : 0.84,
        );

  final colorScheme = baseTheme.colorScheme;
  const Color lightSurfaceBase = fluentLightBackground3;
  final Color effectiveSurfaceBase = isLightMode
      ? lightSurfaceBase
      : colorScheme.surface;

  // The container ladder keeps its tonal steps under acrylic. Collapsing
  // every level onto one base colour (as this bridge used to) only worked
  // while cards carried an outline; flat cards need the steps to show.
  Color container(Color base) => base.withValues(alpha: containerOpacity);

  final bridgedColorScheme = colorScheme.copyWith(
    surface: effectiveSurfaceBase.withValues(alpha: surfaceOpacity),
    surfaceBright: (isLightMode ? lightSurfaceBase : colorScheme.surfaceBright)
        .withValues(alpha: surfaceOpacity),
    surfaceDim: (isLightMode ? fluentLightBackground2 : colorScheme.surfaceDim)
        .withValues(alpha: surfaceOpacity),
    surfaceContainer: container(colorScheme.surfaceContainer),
    surfaceContainerHigh: container(colorScheme.surfaceContainerHigh),
    surfaceContainerHighest: container(colorScheme.surfaceContainerHighest),
    surfaceContainerLow: colorScheme.surfaceContainerLow.withValues(
      alpha: lowContainerOpacity,
    ),
    surfaceContainerLowest: effectiveSurfaceBase.withValues(
      alpha: lowestContainerOpacity,
    ),
    inverseSurface: colorScheme.inverseSurface.withValues(
      alpha: surfaceOpacity,
    ),
    surfaceTint: Colors.transparent,
  );

  // Dialogs, menus and dropdown overlays stay solid even when page chrome
  // uses acrylic, and sit one tonal step above the canvas so they still read
  // as separate layers without an outline.
  final Color dialogColor = colorScheme.surfaceContainer;
  final Color menuColor = colorScheme.surfaceContainer;

  return baseTheme.copyWith(
    colorScheme: bridgedColorScheme,
    scaffoldBackgroundColor: baseTheme.scaffoldBackgroundColor.withValues(
      alpha: scaffoldOpacity,
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
      backgroundColor:
          (baseTheme.appBarTheme.backgroundColor ??
                  baseTheme.scaffoldBackgroundColor)
              .withValues(alpha: appBarOpacity),
      surfaceTintColor: Colors.transparent,
    ),
  );
}
