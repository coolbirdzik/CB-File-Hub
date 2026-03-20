import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

/// Host wrapper for desktop acrylic windows.
///
/// In **dynamic** mode the native acrylic/mica backdrop is used
/// (applied via `WindowAcrylicService`). This widget then paints nothing.
///
/// In **wallpaper** mode the widget draws a user-selected image behind the
/// semi-transparent app chrome, giving the same glass look but with a
/// custom background.
class DesktopAcrylicBackdrop extends StatelessWidget {
  final Widget child;
  final Brightness brightness;

  const DesktopAcrylicBackdrop({
    Key? key,
    required this.child,
    required this.brightness,
  }) : super(key: key);

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

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background wallpaper with blur
        Image.file(
          imageFile,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        // Frosted glass blur overlay
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: 60 * themeProvider.desktopAcrylicStrength,
              sigmaY: 60 * themeProvider.desktopAcrylicStrength,
            ),
            child: Container(
              color: brightness == Brightness.light
                  ? Colors.white.withValues(
                      alpha: (0.82 +
                              0.14 *
                                  (1.0 - themeProvider.desktopAcrylicStrength))
                          .clamp(0.0, 1.0))
                  : Colors.black.withValues(
                      alpha: (0.78 +
                              0.16 *
                                  (1.0 - themeProvider.desktopAcrylicStrength))
                          .clamp(0.0, 1.0)),
            ),
          ),
        ),
        // App content
        child,
      ],
    );
  }
}
