import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/drive/drive_info.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Storage glyphs shared by cards, details, tree, columns and the inspector.
class DriveAvatar extends StatelessWidget {
  final DriveInfo drive;
  final double size;
  const DriveAvatar({super.key, required this.drive, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final dark = context.cb.isDark;
    final hue = switch (drive.kind) {
      DriveKind.wsl => 25.0,
      DriveKind.removable || DriveKind.optical => 38.0,
      DriveKind.network => 265.0,
      _ => drive.isSystemVolume ? 210.0 : 172.0,
    };
    final ink = HSLColor.fromAHSL(1, hue, .62, dark ? .7 : .38).toColor();
    final icon = switch (drive.kind) {
      DriveKind.wsl => PhosphorIconsLight.linuxLogo,
      DriveKind.removable => PhosphorIconsLight.usb,
      DriveKind.network => PhosphorIconsLight.network,
      DriveKind.optical => PhosphorIconsLight.disc,
      DriveKind.ram => PhosphorIconsLight.memory,
      DriveKind.internal => PhosphorIconsLight.deviceMobile,
      _ => PhosphorIconsLight.hardDrives,
    };
    if (size < 24) return Icon(icon, size: size, color: ink);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: ink.withValues(alpha: dark ? .18 : .10),
                  borderRadius: BorderRadius.circular(size >= 44 ? 12 : 8),
                  border: Border.all(color: ink.withValues(alpha: .13)),
                ),
                child: Icon(icon, size: size * .64, color: ink),
              ),
            ),
            if (drive.isSystemVolume && size >= 38)
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: context.cbColors.canvas.withValues(alpha: 1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    PhosphorIconsFill.windowsLogo,
                    size: 13,
                    color: ink,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
