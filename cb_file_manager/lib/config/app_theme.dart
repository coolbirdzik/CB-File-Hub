import 'package:flutter/material.dart';
import 'theme_factory.dart';

/// Lớp cấu hình Theme toàn cục cho ứng dụng
class AppTheme {
  // Định nghĩa các màu theo logo
  static const Color primaryBlue = Color(0xFF436E98); // Màu xanh chính từ logo
  static const Color darkBlue = Color(0xFF152C4F); // Màu xanh đậm từ logo
  static const Color lightBlue = Color(0xFF6C99C0); // Màu xanh nhạt từ logo

  // Màu nền và màu phụ mới (nhẹ nhàng hơn)
  static const Color lightBackground = Color(0xFFF9FAFB);
  static const Color darkBackground = Color(0xFF121820);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E2530);

  // Tạo MaterialColor từ màu primaryBlue để dùng cho primarySwatch
  static MaterialColor createMaterialColor(Color color) {
    List<double> strengths = <double>[.05, .1, .2, .3, .4, .5, .6, .7, .8, .9];
    Map<int, Color> swatch = {};
    final int r = (color.r * 255.0).round(),
        g = (color.g * 255.0).round(),
        b = (color.b * 255.0).round();

    for (final double strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    swatch[500] = color;
    return MaterialColor(color.toARGB32(), swatch);
  }

  // Tạo swatch từ màu chính
  static final MaterialColor primarySwatch = createMaterialColor(primaryBlue);

  // Theme sáng cho ứng dụng - mềm mại hơn, đơn giản hơn, ít border
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.light(
      primary: primaryBlue,
      secondary: lightBlue,
      onPrimary: Colors.white,
      primaryContainer: lightBlue.withValues(alpha: 0.15),
      surface: surfaceLight,
      onSurface: darkBlue,
    );

    return ThemeFactory.createTheme(
      colorScheme: colorScheme,
      brightness: Brightness.light,
      options: const ThemeOptions(
        borderRadius: 20.0,
        elevation: 0.0,
        useMaterial3: true,
        cardElevation: 0.0,
        buttonElevation: 0.0,
      ),
    );
  }

  // Theme tối cho ứng dụng - mềm mại hơn, đơn giản hơn, ít border
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme.dark(
      primary: primaryBlue,
      secondary: lightBlue,
      onPrimary: Colors.white,
      primaryContainer: primaryBlue.withValues(alpha: 0.3),
      surface: surfaceDark,
      onSurface: Colors.white,
    );

    return ThemeFactory.createTheme(
      colorScheme: colorScheme,
      brightness: Brightness.dark,
      options: const ThemeOptions(
        borderRadius: 20.0,
        elevation: 0.0,
        useMaterial3: true,
        cardElevation: 0.0,
        buttonElevation: 0.0,
      ),
    );
  }
}
