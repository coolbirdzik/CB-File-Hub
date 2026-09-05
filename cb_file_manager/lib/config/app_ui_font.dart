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
    final TextTheme Function(TextTheme) mapper;
    switch (font) {
      case AppUiFont.inter:
        return theme;
      case AppUiFont.roboto:
        mapper = GoogleFonts.robotoTextTheme;
        break;
      case AppUiFont.openSans:
        mapper = GoogleFonts.openSansTextTheme;
        break;
      case AppUiFont.notoSans:
        mapper = GoogleFonts.notoSansTextTheme;
        break;
      case AppUiFont.nunitoSans:
        mapper = GoogleFonts.nunitoSansTextTheme;
        break;
      case AppUiFont.sourceSans3:
        mapper = GoogleFonts.sourceSans3TextTheme;
        break;
      case AppUiFont.ibmPlexSans:
        mapper = GoogleFonts.ibmPlexSansTextTheme;
        break;
    }

    final textTheme = mapper(theme.textTheme);
    final primaryTextTheme = mapper(theme.primaryTextTheme);
    final family = textTheme.bodyMedium?.fontFamily ?? resolveFamily(font);

    TextStyle? mapStyle(TextStyle? style) {
      if (style == null) return null;
      return style.copyWith(fontFamily: family);
    }

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
