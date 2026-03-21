import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/translation_helper.dart';

class DrawerHeaderWidget extends StatelessWidget {
  final bool isPinned;
  final Function(bool) onPinStateChanged;

  const DrawerHeaderWidget({
    Key? key,
    required this.isPinned,
    required this.onPinStateChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final topPadding = MediaQuery.of(context).padding.top + 16;

    return Container(
      padding: EdgeInsets.fromLTRB(18, topPadding, 14, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primaryContainer.withValues(alpha: 0.55),
            cs.surfaceContainerHighest.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo with shadow effect
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 30,
                  width: 30,
                  errorBuilder: (context, error, stackTrace) => Icon(
                    PhosphorIconsLight.folder,
                    color: cs.primary,
                    size: 28,
                  ),
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    context.tr.appTitle,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // Pin button (hidden on small screens)
              if (!isSmallScreen)
                IconButton(
                  icon: Icon(
                    isPinned
                        ? PhosphorIconsLight.pushPin
                        : PhosphorIconsLight.pushPin,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                  tooltip: isPinned ? context.tr.unpinMenu : context.tr.pinMenu,
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surface.withValues(alpha: 0.7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    onPinStateChanged(!isPinned);
                  },
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Subtitle
          Text(
            'File Management Made Simple',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
