import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../helpers/files/windows_app_icon.dart';
import '../../../services/disk_cleaner/macos_cleaner_platform.dart';
import '../../../services/app_insights/app_insights_models.dart';

/// An installed app's own icon, or a generic app glyph while it loads or
/// when it has none.
class InstalledAppIcon extends StatefulWidget {
  final InstalledAppInfo app;
  final double size;

  const InstalledAppIcon({super.key, required this.app, required this.size});

  @override
  State<InstalledAppIcon> createState() => _InstalledAppIconState();
}

class _InstalledAppIconState extends State<InstalledAppIcon> {
  Future<ui.Image?>? _iconFuture;
  String? _iconPath;

  @override
  void initState() {
    super.initState();
    _loadIcon();
  }

  @override
  void didUpdateWidget(InstalledAppIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextPath = resolveInstalledAppIconPath(widget.app);
    if (nextPath != _iconPath) _loadIcon();
  }

  void _loadIcon() {
    _iconPath = resolveInstalledAppIconPath(widget.app);
    final path = _iconPath;
    if (path == null) {
      _iconFuture = Future<ui.Image?>.value(null);
    } else if (Platform.isMacOS) {
      // Finder's icon, drawn at the tile's pixel size (2x on Retina).
      _iconFuture = MacosCleanerPlatform.appIcon(
        path,
        (widget.size * 2).ceil(),
      );
    } else {
      _iconFuture = WindowsAppIcon.extractIconFromFile(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: widget.size,
      height: widget.size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(widget.size * 0.22),
      ),
      child: FutureBuilder<ui.Image?>(
        future: _iconFuture,
        builder: (context, snapshot) {
          final image = snapshot.data;
          if (image != null) {
            return RawImage(
              image: image,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            );
          }
          return Icon(
            widget.app.source == InstalledAppSource.msix
                ? Icons.window_rounded
                : Icons.apps_rounded,
            size: widget.size * 0.58,
            color: theme.colorScheme.onSurfaceVariant,
          );
        },
      ),
    );
  }
}

/// The file holding [app]'s icon: its DisplayIcon, else its executable.
String? resolveInstalledAppIconPath(InstalledAppInfo app) {
  // macOS: Finder draws the icon from the bundle itself.
  final bundle = app.installLocation;
  if (app.source == InstalledAppSource.macApp &&
      bundle != null &&
      bundle.endsWith('.app')) {
    return bundle;
  }
  final displayIcon = app.displayIconPath?.trim();
  if (displayIcon != null && displayIcon.isNotEmpty) return displayIcon;
  if (app.executablePaths.isNotEmpty) return app.executablePaths.first;
  return null;
}
