import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/primitives/cb_select.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class FolderViewModePreferenceControl extends StatelessWidget {
  const FolderViewModePreferenceControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final FolderViewModePreference value;
  final ValueChanged<FolderViewModePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 640;
        final select = CbSelect<FolderViewModePreference>(
          value: value,
          onChanged: onChanged,
          expand: stacked,
          tooltip: l10n.folderViewModePreference,
          items: [
            CbSelectItem(
              value: FolderViewModePreference.mediaGrid,
              label: l10n.folderViewModeMediaGrid,
              icon: PhosphorIconsLight.squaresFour,
            ),
            CbSelectItem(
              value: FolderViewModePreference.inheritParent,
              label: l10n.folderViewModeInheritParent,
              icon: PhosphorIconsLight.folder,
            ),
          ],
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(PhosphorIconsLight.folder, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.folderViewModePreference,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.folderViewModePreferenceDescription,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (stacked) ...[const SizedBox(height: 8), select],
                  ],
                ),
              ),
              if (!stacked) ...[const SizedBox(width: 16), select],
            ],
          ),
        );
      },
    );
  }
}
