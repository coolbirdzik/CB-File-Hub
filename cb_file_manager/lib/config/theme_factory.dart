import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Options for customizing theme generation
class ThemeOptions {
  final double borderRadius;
  final double elevation;
  final bool useMaterial3;
  final bool centerTitle;
  final double cardElevation;
  final double buttonElevation;

  const ThemeOptions({
    this.borderRadius = 20.0,
    this.elevation = 0.0,
    this.useMaterial3 = true,
    this.centerTitle = true,
    this.cardElevation = 0.0,
    this.buttonElevation = 0.0,
  });
}

/// Toast notification theme — all dimensions and opacity values centralised
/// so AppToast stays in sync with the active theme without duplicating magic
/// numbers across the codebase.
class AppToastTheme extends ThemeExtension<AppToastTheme> {
  // Icon container
  final double iconBoxSize;
  final double iconSize;
  final double iconBoxRadius;

  // Container
  final double containerRadius;
  final double hPadding;
  final double vPadding;
  final double maxWidth;

  // Blur
  final double blurSigmaDesktopLight;
  final double blurSigmaDesktopDark;
  final double blurSigmaMobile;

  // Colours / opacity
  final double surfaceOpacity;
  final double borderOpacity;
  final double shadowOpacityLight;
  final double shadowOpacityDark;
  final double iconAccentOpacity;

  // Durations
  final Duration durationSuccess;
  final Duration durationInfo;
  final Duration durationWarning;
  final Duration durationError;

  const AppToastTheme({
    required this.iconBoxSize,
    required this.iconSize,
    required this.iconBoxRadius,
    required this.containerRadius,
    required this.hPadding,
    required this.vPadding,
    required this.maxWidth,
    required this.blurSigmaDesktopLight,
    required this.blurSigmaDesktopDark,
    required this.blurSigmaMobile,
    required this.surfaceOpacity,
    required this.borderOpacity,
    required this.shadowOpacityLight,
    required this.shadowOpacityDark,
    required this.iconAccentOpacity,
    required this.durationSuccess,
    required this.durationInfo,
    required this.durationWarning,
    required this.durationError,
  });

  @override
  AppToastTheme copyWith({
    double? iconBoxSize,
    double? iconSize,
    double? iconBoxRadius,
    double? containerRadius,
    double? hPadding,
    double? vPadding,
    double? maxWidth,
    double? blurSigmaDesktopLight,
    double? blurSigmaDesktopDark,
    double? blurSigmaMobile,
    double? surfaceOpacity,
    double? borderOpacity,
    double? shadowOpacityLight,
    double? shadowOpacityDark,
    double? iconAccentOpacity,
    Duration? durationSuccess,
    Duration? durationInfo,
    Duration? durationWarning,
    Duration? durationError,
  }) =>
      AppToastTheme(
        iconBoxSize: iconBoxSize ?? this.iconBoxSize,
        iconSize: iconSize ?? this.iconSize,
        iconBoxRadius: iconBoxRadius ?? this.iconBoxRadius,
        containerRadius: containerRadius ?? this.containerRadius,
        hPadding: hPadding ?? this.hPadding,
        vPadding: vPadding ?? this.vPadding,
        maxWidth: maxWidth ?? this.maxWidth,
        blurSigmaDesktopLight:
            blurSigmaDesktopLight ?? this.blurSigmaDesktopLight,
        blurSigmaDesktopDark: blurSigmaDesktopDark ?? this.blurSigmaDesktopDark,
        blurSigmaMobile: blurSigmaMobile ?? this.blurSigmaMobile,
        surfaceOpacity: surfaceOpacity ?? this.surfaceOpacity,
        borderOpacity: borderOpacity ?? this.borderOpacity,
        shadowOpacityLight: shadowOpacityLight ?? this.shadowOpacityLight,
        shadowOpacityDark: shadowOpacityDark ?? this.shadowOpacityDark,
        iconAccentOpacity: iconAccentOpacity ?? this.iconAccentOpacity,
        durationSuccess: durationSuccess ?? this.durationSuccess,
        durationInfo: durationInfo ?? this.durationInfo,
        durationWarning: durationWarning ?? this.durationWarning,
        durationError: durationError ?? this.durationError,
      );

  @override
  AppToastTheme lerp(ThemeExtension<AppToastTheme>? other, double t) {
    if (other is! AppToastTheme) return this;
    return AppToastTheme(
      iconBoxSize: lerpDouble(iconBoxSize, other.iconBoxSize, t)!,
      iconSize: lerpDouble(iconSize, other.iconSize, t)!,
      iconBoxRadius: lerpDouble(iconBoxRadius, other.iconBoxRadius, t)!,
      containerRadius: lerpDouble(containerRadius, other.containerRadius, t)!,
      hPadding: lerpDouble(hPadding, other.hPadding, t)!,
      vPadding: lerpDouble(vPadding, other.vPadding, t)!,
      maxWidth: lerpDouble(maxWidth, other.maxWidth, t)!,
      blurSigmaDesktopLight:
          lerpDouble(blurSigmaDesktopLight, other.blurSigmaDesktopLight, t)!,
      blurSigmaDesktopDark:
          lerpDouble(blurSigmaDesktopDark, other.blurSigmaDesktopDark, t)!,
      blurSigmaMobile: lerpDouble(blurSigmaMobile, other.blurSigmaMobile, t)!,
      surfaceOpacity: lerpDouble(surfaceOpacity, other.surfaceOpacity, t)!,
      borderOpacity: lerpDouble(borderOpacity, other.borderOpacity, t)!,
      shadowOpacityLight:
          lerpDouble(shadowOpacityLight, other.shadowOpacityLight, t)!,
      shadowOpacityDark:
          lerpDouble(shadowOpacityDark, other.shadowOpacityDark, t)!,
      iconAccentOpacity:
          lerpDouble(iconAccentOpacity, other.iconAccentOpacity, t)!,
      durationSuccess: Duration(
        milliseconds: lerpDouble(durationSuccess.inMilliseconds,
                other.durationSuccess.inMilliseconds, t)!
            .round(),
      ),
      durationInfo: Duration(
        milliseconds: lerpDouble(durationInfo.inMilliseconds,
                other.durationInfo.inMilliseconds, t)!
            .round(),
      ),
      durationWarning: Duration(
        milliseconds: lerpDouble(durationWarning.inMilliseconds,
                other.durationWarning.inMilliseconds, t)!
            .round(),
      ),
      durationError: Duration(
        milliseconds: lerpDouble(durationError.inMilliseconds,
                other.durationError.inMilliseconds, t)!
            .round(),
      ),
    );
  }
}

/// Factory class for creating consistent theme configurations
class ThemeFactory {
  static Color _blend(Color base, Color tint, double alpha) {
    return Color.alphaBlend(tint.withValues(alpha: alpha), base);
  }

  /// Creates a complete ThemeData from a color scheme and brightness
  static ThemeData createTheme({
    required ColorScheme colorScheme,
    required Brightness brightness,
    ThemeOptions? options,
  }) {
    final opts = options ?? const ThemeOptions();
    final bool isLight = brightness == Brightness.light;
    final Color scaffoldColor =
        isLight ? colorScheme.surface : colorScheme.surface;
    final Color appBarColor =
        isLight ? colorScheme.surface : colorScheme.surface;
    final Color cardColor = isLight
        ? _blend(colorScheme.surface, Colors.black, 0.045)
        : colorScheme.surface;
    final Color inputFillColor = isLight
        ? _blend(colorScheme.surface, Colors.black, 0.035)
        : colorScheme.surface;
    final Color menuColor = colorScheme.surfaceContainerHigh;
    final Color lightBorder = Colors.black.withValues(alpha: 0.08);

    return ThemeData(
      useMaterial3: opts.useMaterial3,
      brightness: brightness,
      primaryColor: colorScheme.primary,
      scaffoldBackgroundColor: scaffoldColor,
      canvasColor: menuColor,
      colorScheme: colorScheme,

      // AppBar Theme
      appBarTheme: AppBarTheme(
        backgroundColor: appBarColor,
        foregroundColor: isLight ? colorScheme.primary : colorScheme.onSurface,
        elevation: opts.elevation,
        centerTitle: opts.centerTitle,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
          statusBarBrightness: isLight ? Brightness.light : Brightness.dark,
        ),
        iconTheme: IconThemeData(
          color: isLight ? colorScheme.primary : colorScheme.onSurface,
        ),
        titleTextStyle: TextStyle(
          color: isLight ? colorScheme.primary : colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
      ),

      // Button Themes
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: opts.buttonElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(opts.borderRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor:
              isLight ? colorScheme.primary : colorScheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(opts.borderRadius),
          ),
          side: BorderSide(
            color: (isLight ? colorScheme.primary : Colors.white)
                .withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor:
              isLight ? colorScheme.primary : colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),

      // FloatingActionButton Theme
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: opts.elevation > 0 ? 2 : opts.elevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      // Card Theme
      cardTheme: CardThemeData(
        elevation: opts.cardElevation,
        color: cardColor,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // PopupMenu Theme
      popupMenuTheme: PopupMenuThemeData(
        color: menuColor,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuColor),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),

      // Divider Theme
      dividerTheme: DividerThemeData(
        thickness: 0.5,
        color: isLight
            ? Colors.black.withValues(alpha: 0.08)
            : Colors.grey.withValues(alpha: 0.2),
      ),

      // InputDecoration Theme
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isLight ? lightBorder : Colors.grey.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isLight ? lightBorder : Colors.grey.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),

      // Dialog Theme
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        elevation: opts.elevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      // BottomSheet Theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        modalBackgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        elevation: opts.elevation,
      ),

      // TabBar Theme
      tabBarTheme: TabBarThemeData(
        labelColor: isLight ? colorScheme.primary : colorScheme.onSurface,
        unselectedLabelColor: isLight ? Colors.grey : Colors.grey[400],
        indicator: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isLight ? colorScheme.primary : colorScheme.onSurface,
              width: 2,
            ),
          ),
        ),
      ),

      // Text Theme
      textTheme: TextTheme(
        displayLarge: TextStyle(color: colorScheme.onSurface),
        displayMedium: TextStyle(color: colorScheme.onSurface),
        displaySmall: TextStyle(color: colorScheme.onSurface),
        headlineLarge: TextStyle(color: colorScheme.onSurface),
        headlineMedium: TextStyle(color: colorScheme.onSurface),
        headlineSmall: TextStyle(color: colorScheme.onSurface),
        titleLarge: TextStyle(color: colorScheme.onSurface),
        titleMedium: TextStyle(color: colorScheme.onSurface),
        titleSmall: TextStyle(color: colorScheme.onSurface),
        bodyLarge: TextStyle(color: colorScheme.onSurface),
        bodyMedium: TextStyle(color: colorScheme.onSurface),
        bodySmall: TextStyle(color: colorScheme.onSurface),
        labelLarge: TextStyle(color: colorScheme.onSurface),
        labelMedium: TextStyle(color: colorScheme.onSurface),
        labelSmall: TextStyle(color: colorScheme.onSurface),
      ),

      // Scrollbar Theme — wider track for easier dragging
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return 14.0;
          }
          return 10.0;
        }),
        radius: const Radius.circular(8.0),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return colorScheme.primary.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.hovered)) {
            return colorScheme.primary.withValues(alpha: 0.45);
          }
          return isLight
              ? Colors.black.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.3);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return isLight
                ? Colors.black.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.05);
          }
          return Colors.transparent;
        }),
        trackBorderColor: WidgetStateProperty.all(Colors.transparent),
        minThumbLength: 48.0,
        crossAxisMargin: 2.0,
        mainAxisMargin: 2.0,
        interactive: true,
        thumbVisibility: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return true;
          return null; // Use default behavior otherwise
        }),
      ),

      // Icon Theme
      iconTheme: IconThemeData(
        color: isLight
            ? colorScheme.onSurface.withValues(alpha: 0.72)
            : Colors.white70,
      ),

      // Divider Color
      dividerColor:
          isLight ? Colors.black.withValues(alpha: 0.12) : Colors.grey.shade700,
    ).copyWith(
      extensions: [
        AppToastTheme(
          iconBoxSize: 30.0,
          iconSize: 18.0,
          iconBoxRadius: 8.0,
          containerRadius: 12.0,
          hPadding: 12.0,
          vPadding: 10.0,
          maxWidth: 360.0,
          blurSigmaDesktopLight: 18.0,
          blurSigmaDesktopDark: 10.0,
          blurSigmaMobile: 8.0,
          surfaceOpacity: 0.82,
          borderOpacity: 0.22,
          shadowOpacityLight: 0.16,
          shadowOpacityDark: 0.40,
          iconAccentOpacity: 0.14,
          durationSuccess: Duration(milliseconds: 2200),
          durationInfo: Duration(milliseconds: 2200),
          durationWarning: Duration(milliseconds: 2600),
          durationError: Duration(milliseconds: 3200),
        ),
      ],
    );
  }

  /// Creates a color scheme from a seed color
  static ColorScheme createColorScheme({
    required Color seedColor,
    required Brightness brightness,
    Color? background,
    Color? surface,
  }) {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );

    final resolvedSurface = surface ?? background ?? baseScheme.surface;
    if (brightness == Brightness.light) {
      final surfaceLowest = resolvedSurface;
      final surfaceLow = _blend(resolvedSurface, Colors.black, 0.02);
      final surfaceContainer = _blend(resolvedSurface, Colors.black, 0.04);
      final surfaceHigh = _blend(resolvedSurface, Colors.black, 0.06);
      final surfaceHighest = _blend(resolvedSurface, Colors.black, 0.08);
      final surfaceDim = _blend(resolvedSurface, Colors.black, 0.10);
      final surfaceBright = resolvedSurface;

      return baseScheme.copyWith(
        surface: resolvedSurface,
        surfaceContainerLowest: surfaceLowest,
        surfaceContainerLow: surfaceLow,
        surfaceContainer: surfaceContainer,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: surfaceHighest,
        surfaceDim: surfaceDim,
        surfaceBright: surfaceBright,
      );
    }

    return baseScheme.copyWith(surface: resolvedSurface);
  }
}
