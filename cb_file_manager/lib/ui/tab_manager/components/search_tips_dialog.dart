import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import '../../utils/route.dart';

Future<void> showSearchTipsDialog(BuildContext context) async {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final l10n = AppLocalizations.of(context)!;

  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(PhosphorIconsLight.info, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(l10n.searchTipsTitle),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SearchTipItem(
              icon: PhosphorIconsLight.textT,
              title: l10n.searchByFilename,
              description: l10n.searchByFilenameDesc,
            ),
            const Divider(),
            _SearchTipItem(
              icon: PhosphorIconsLight.shoppingBagOpen,
              title: l10n.searchByTags,
              description: l10n.searchByTagsDesc,
            ),
            const Divider(),
            _SearchTipItem(
              icon: PhosphorIconsLight.hash,
              title: l10n.searchMultipleTags,
              description: l10n.searchMultipleTagsDesc,
            ),
            const Divider(),
            _SearchTipItem(
              icon: PhosphorIconsLight.globe,
              title: l10n.globalSearch,
              description: l10n.globalSearchDesc,
            ),
            const Divider(),
            _SearchTipItem(
              icon: PhosphorIconsLight.list,
              title: l10n.searchShortcuts,
              description: l10n.searchShortcutsDesc,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => RouteUtils.safePopDialog(context),
          child: Text(l10n.close),
        ),
      ],
      backgroundColor: isDark ? Colors.grey[850] : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
  );
}

class _SearchTipItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _SearchTipItem({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
