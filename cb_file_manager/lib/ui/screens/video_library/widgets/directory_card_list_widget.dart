import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';

/// A reusable widget for displaying directories as cards (used in settings screen)
class DirectoryCardListWidget extends StatelessWidget {
  final List<String> directories;
  final Function(String) onRemove;
  final String? emptyMessage;

  const DirectoryCardListWidget({
    Key? key,
    required this.directories,
    required this.onRemove,
    this.emptyMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    if (directories.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            emptyMessage ?? localizations.noVideoSources,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Column(
      children: directories.map((directory) {
        return Card(
          child: ListTile(
            leading: const Icon(PhosphorIconsLight.folder),
            title: Text(directory),
            trailing: IconButton(
              icon: const Icon(PhosphorIconsLight.trash),
              onPressed: () => onRemove(directory),
              tooltip: localizations.removeVideoSource,
            ),
          ),
        );
      }).toList(),
    );
  }
}
