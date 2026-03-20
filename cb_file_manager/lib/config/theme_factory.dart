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
    final Color lightBorder = Colors.black.withValues(alpha: 0.08);

    return ThemeData(
      useMaterial3: opts.useMaterial3,
      brightness: brightness,
      primaryColor: colorScheme.primary,
      scaffoldBackgroundColor: scaffoldColor,
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
        color: cardColor,
        elevation: opts.elevation > 0 ? 2 : opts.elevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
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

      // Icon Theme
      iconTheme: IconThemeData(
        color: isLight
            ? colorScheme.onSurface.withValues(alpha: 0.72)
            : Colors.white70,
      ),

      // Divider Color
      dividerColor:
          isLight ? Colors.black.withValues(alpha: 0.12) : Colors.grey.shade700,
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
