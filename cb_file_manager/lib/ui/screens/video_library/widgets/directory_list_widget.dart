import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';

/// A reusable widget for displaying a list of directories with remove functionality
class DirectoryListWidget extends StatelessWidget {
  final List<String> directories;
  final Function(String) onRemove;
  final String? emptyMessage;

  const DirectoryListWidget({
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
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          emptyMessage ?? localizations.noVideoSources,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: directories.length,
        itemBuilder: (context, index) {
          final directory = directories[index];
          return ListTile(
            dense: true,
            leading: const Icon(PhosphorIconsLight.folder),
            title: Text(
              directory,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(PhosphorIconsLight.x),
              onPressed: () => onRemove(directory),
              tooltip: localizations.removeVideoSource,
            ),
          );
        },
      ),
    );
  }
}
