import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// User-selectable UI typefaces from Google Fonts.
///
/// All options are free/open licences (SIL OFL or Apache 2.0) with Latin
/// Extended / Vietnamese coverage. [inter] is bundled in the app binary;
/// the rest are fetched once via `google_fonts` and cached on disk.
enum AppUiFont {
  inter,
  roboto,
  openSans,
  notoSans,
  nunitoSans,
  sourceSans3,
  ibmPlexSans,
}

/// Helpers for [AppUiFont] display names and ThemeData application.
class AppUiFontConfig {
  const AppUiFontConfig._();

  static const AppUiFont defaultFont = AppUiFont.inter;

  static const Map<AppUiFont, String> displayNames = {
    AppUiFont.inter: 'Inter',
    AppUiFont.roboto: 'Roboto',
    AppUiFont.openSans: 'Open Sans',
    AppUiFont.notoSans: 'Noto Sans',
    AppUiFont.nunitoSans: 'Nunito Sans',
    AppUiFont.sourceSans3: 'Source Sans 3',
    AppUiFont.ibmPlexSans: 'IBM Plex Sans',
  };

  /// Short Unicode sample for the settings picker.
  static const String previewSample = 'Xin chào · Hello · ₫';

  /// Resolves the engine font-family name and ensures remote fonts are loaded.
  static String resolveFamily(AppUiFont font) {
    switch (font) {
      case AppUiFont.inter:
        return 'Inter';
      case AppUiFont.roboto:
        return GoogleFonts.roboto().fontFamily!;
      case AppUiFont.openSans:
        return GoogleFonts.openSans().fontFamily!;
      case AppUiFont.notoSans:
        return GoogleFonts.notoSans().fontFamily!;
      case AppUiFont.nunitoSans:
        return GoogleFonts.nunitoSans().fontFamily!;
      case AppUiFont.sourceSans3:
        return GoogleFonts.sourceSans3().fontFamily!;
      case AppUiFont.ibmPlexSans:
        return GoogleFonts.ibmPlexSans().fontFamily!;
    }
  }

  /// Applies [font] across [theme]'s text ramps (keeps sizes/weights).
  static ThemeData applyToTheme(ThemeData theme, AppUiFont font) {
    if (font == AppUiFont.inter) return theme;

    // Google Fonts 9 returns material_ui.TextTheme. Map the shared TextStyle
    // values instead so this also works with Flutter's Material bridge.
    TextStyle? mapStyle(TextStyle? style) {
      if (style == null) return null;
      return switch (font) {
        AppUiFont.inter => style,
        AppUiFont.roboto => GoogleFonts.roboto(textStyle: style),
        AppUiFont.openSans => GoogleFonts.openSans(textStyle: style),
        AppUiFont.notoSans => GoogleFonts.notoSans(textStyle: style),
        AppUiFont.nunitoSans => GoogleFonts.nunitoSans(textStyle: style),
        AppUiFont.sourceSans3 => GoogleFonts.sourceSans3(textStyle: style),
        AppUiFont.ibmPlexSans => GoogleFonts.ibmPlexSans(textStyle: style),
      };
    }

    TextTheme mapTextTheme(TextTheme text) => text.copyWith(
      displayLarge: mapStyle(text.displayLarge),
      displayMedium: mapStyle(text.displayMedium),
      displaySmall: mapStyle(text.displaySmall),
      headlineLarge: mapStyle(text.headlineLarge),
      headlineMedium: mapStyle(text.headlineMedium),
      headlineSmall: mapStyle(text.headlineSmall),
      titleLarge: mapStyle(text.titleLarge),
      titleMedium: mapStyle(text.titleMedium),
      titleSmall: mapStyle(text.titleSmall),
      bodyLarge: mapStyle(text.bodyLarge),
      bodyMedium: mapStyle(text.bodyMedium),
      bodySmall: mapStyle(text.bodySmall),
      labelLarge: mapStyle(text.labelLarge),
      labelMedium: mapStyle(text.labelMedium),
      labelSmall: mapStyle(text.labelSmall),
    );

    final textTheme = mapTextTheme(theme.textTheme);
    final primaryTextTheme = mapTextTheme(theme.primaryTextTheme);

    return theme.copyWith(
      textTheme: textTheme,
      primaryTextTheme: primaryTextTheme,
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: mapStyle(theme.appBarTheme.titleTextStyle),
        toolbarTextStyle: mapStyle(theme.appBarTheme.toolbarTextStyle),
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        titleTextStyle: mapStyle(theme.dialogTheme.titleTextStyle),
        contentTextStyle: mapStyle(theme.dialogTheme.contentTextStyle),
      ),
      textButtonTheme: TextButtonThemeData(
        style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStatePropertyAll(
            mapStyle(theme.textTheme.labelLarge) ?? textTheme.labelLarge,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: (theme.elevatedButtonTheme.style ?? const ButtonStyle())
            .copyWith(
              textStyle: WidgetStatePropertyAll(
                mapStyle(theme.textTheme.labelLarge) ?? textTheme.labelLarge,
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
            .copyWith(
              textStyle: WidgetStatePropertyAll(
                mapStyle(theme.textTheme.labelLarge) ?? textTheme.labelLarge,
              ),
            ),
      ),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        hintStyle: mapStyle(theme.inputDecorationTheme.hintStyle),
        labelStyle: mapStyle(theme.inputDecorationTheme.labelStyle),
        helperStyle: mapStyle(theme.inputDecorationTheme.helperStyle),
        errorStyle: mapStyle(theme.inputDecorationTheme.errorStyle),
        floatingLabelStyle: mapStyle(
          theme.inputDecorationTheme.floatingLabelStyle,
        ),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        titleTextStyle: mapStyle(theme.listTileTheme.titleTextStyle),
        subtitleTextStyle: mapStyle(theme.listTileTheme.subtitleTextStyle),
      ),
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: mapStyle(theme.chipTheme.labelStyle),
        secondaryLabelStyle: mapStyle(theme.chipTheme.secondaryLabelStyle),
      ),
      tabBarTheme: theme.tabBarTheme.copyWith(
        labelStyle: mapStyle(theme.tabBarTheme.labelStyle),
        unselectedLabelStyle: mapStyle(theme.tabBarTheme.unselectedLabelStyle),
      ),
      tooltipTheme: theme.tooltipTheme.copyWith(
        textStyle: mapStyle(theme.tooltipTheme.textStyle),
      ),
    );
  }

  /// Preview [TextStyle] for settings chips (loads remote font if needed).
  static TextStyle previewStyle(AppUiFont font, {double fontSize = 14}) {
    switch (font) {
      case AppUiFont.inter:
        return TextStyle(
          fontFamily: 'Inter',
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        );
      case AppUiFont.roboto:
        return GoogleFonts.roboto(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        );
      case AppUiFont.openSans:
        return GoogleFonts.openSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        );
      case AppUiFont.notoSans:
        return GoogleFonts.notoSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        );
      case AppUiFont.nunitoSans:
        return GoogleFonts.nunitoSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        );
      case AppUiFont.sourceSans3:
        return GoogleFonts.sourceSans3(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        );
      case AppUiFont.ibmPlexSans:
        return GoogleFonts.ibmPlexSans(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        );
    }
  }
}
