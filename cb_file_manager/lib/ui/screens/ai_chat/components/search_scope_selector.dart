import 'package:flutter/material.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../services/ai/file_context_builder.dart';

/// Horizontal chip selector for AI search scope.
class SearchScopeSelector extends StatelessWidget {
  final SearchScope selectedScope;
  final ValueChanged<SearchScope> onScopeChanged;
  final String currentPath;

  const SearchScopeSelector({
    Key? key,
    required this.selectedScope,
    required this.onScopeChanged,
    this.currentPath = '',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildChip(
                context,
                label: l.currentFolder,
                scope: SearchScope.currentDirectory,
              ),
              const SizedBox(width: 6),
              _buildChip(
                context,
                label: l.recursiveSearch,
                scope: SearchScope.recursive,
              ),
              const SizedBox(width: 6),
              _buildChip(
                context,
                label: l.aiTaggedFiles,
                scope: SearchScope.taggedFiles,
              ),
              const SizedBox(width: 6),
              _buildChip(
                context,
                label: l.allDrives,
                scope: SearchScope.allDrives,
              ),
            ],
          ),
        ),
        if (currentPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              currentPath,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required SearchScope scope,
  }) {
    final isSelected = selectedScope == scope;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => onScopeChanged(scope),
      visualDensity: VisualDensity.compact,
    );
  }
}
