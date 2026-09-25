import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/translation_helper.dart';

/// Top of the drawer: clears the status bar and, on wide screens, holds the
/// pin toggle.
class DrawerHeaderWidget extends StatelessWidget {
  final bool isPinned;
  final Function(bool) onPinStateChanged;

  const DrawerHeaderWidget({
    super.key,
    required this.isPinned,
    required this.onPinStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    final cs = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;

    if (isSmallScreen) {
      return SizedBox(height: topPadding + 8);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(18, topPadding + 8, 14, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: IconButton(
          icon: Icon(
            isPinned ? PhosphorIconsFill.pushPin : PhosphorIconsLight.pushPin,
            color: isPinned ? cs.primary : cs.onSurfaceVariant,
            size: 20,
          ),
          tooltip: isPinned ? context.tr.unpinMenu : context.tr.pinMenu,
          style: IconButton.styleFrom(
            backgroundColor: cs.onSurface.withValues(
              alpha: isPinned ? 0.05 : 0.06,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () {
            onPinStateChanged(!isPinned);
          },
        ),
      ),
    );
  }
}
