import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';
import '../../design_system/macos_glass_theme.dart';

/// Host wrapper for desktop window materials.
///
/// In **dynamic** mode the native Windows Acrylic or macOS Glass is used
/// (applied via `WindowAcrylicService`). This widget then paints nothing.
///
/// In **wallpaper** mode the widget draws a user-selected image behind the
/// semi-transparent app chrome, giving the same glass look but with a
/// custom background.
class DesktopAcrylicBackdrop extends StatelessWidget {
  final Widget child;
  final Brightness brightness;

  const DesktopAcrylicBackdrop({
    super.key,
    required this.child,
    required this.brightness,
  });

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return child;

    final themeProvider = context.watch<ThemeProvider>();
    if (themeProvider.backdropMode != AcrylicBackdropMode.wallpaper) {
      return child;
    }

    final imagePath = themeProvider.backdropImagePath;
    if (imagePath == null || imagePath.isEmpty) return child;

    final imageFile = File(imagePath);
    final strength = themeProvider.desktopBackdropStrength;
    final glass = themeProvider.usesMacosGlass
        ? MacosGlassTheme(
            strength: strength,
            blurStrength: themeProvider.desktopGlassBlurStrength,
            brightness: brightness,
          )
        : null;
    final highContrast = MediaQuery.highContrastOf(context);
    final blur = highContrast ? 0.0 : glass?.blurSigma ?? 60 * strength;
    final tintOpacity = highContrast
        ? 1.0
        : glass?.wallpaperTintOpacity ??
              (brightness == Brightness.light
                  ? (0.82 + 0.14 * (1.0 - strength)).clamp(0.0, 1.0)
                  : (0.78 + 0.16 * (1.0 - strength)).clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background wallpaper with blur
        Image.file(
          imageFile,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        // Frosted glass blur overlay
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: ColoredBox(
              color:
                  (brightness == Brightness.light ? Colors.white : Colors.black)
                      .withValues(alpha: tintOpacity),
            ),
          ),
        ),
        // App content
        child,
      ],
    );
  }
}
