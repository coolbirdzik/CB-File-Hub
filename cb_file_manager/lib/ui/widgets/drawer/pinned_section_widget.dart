import 'sidebar_pinned_entry.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';

import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';

class PinnedSectionWidget extends StatefulWidget {
  final Function(String path, String name) onNavigate;
  final bool initialExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const PinnedSectionWidget({
    super.key,
    required this.onNavigate,
    this.initialExpanded = false,
    this.onExpansionChanged,
  });

  @override
  State<PinnedSectionWidget> createState() => _PinnedSectionWidgetState();
}

class _PinnedSectionWidgetState extends State<PinnedSectionWidget> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
  }

  @override
  void didUpdateWidget(covariant PinnedSectionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialExpanded != widget.initialExpanded &&
        _isExpanded != widget.initialExpanded) {
      setState(() {
        _isExpanded = widget.initialExpanded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return BlocBuilder<DrawerCubit, DrawerState>(
      builder: (context, state) {
        if (state.pinnedPaths.isEmpty) {
          return const SizedBox.shrink();
        }

        return CbExpander(
          flush: true,
          headerPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: CbSpacing.sm,
          ),
          leading: Icon(
            PhosphorIconsLight.pushPin,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            defaultTargetPlatform == TargetPlatform.macOS
                ? l10n.favoritesSection
                : l10n.pinnedSection,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          contentPadding: const EdgeInsets.only(bottom: 8),
          expanded: _isExpanded,
          onExpansionChanged: (isExpanded) {
            _isExpanded = isExpanded;
            widget.onExpansionChanged?.call(isExpanded);
          },
          children: state.pinnedPaths
              .map((pinnedPath) {
                final entry = SidebarPinnedEntry.fromPath(
                  pinnedPath,
                  l10n: l10n,
                  userFolders: state.macosUserFolders,
                );
                return _buildPinnedItem(
                  context,
                  entry: entry,
                  onTap: () => widget.onNavigate(pinnedPath, entry.title),
                  onUnpin: () {
                    context.read<DrawerCubit>().togglePinnedPath(pinnedPath);
                  },
                );
              })
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildPinnedItem(
    BuildContext context, {
    required SidebarPinnedEntry entry,
    required VoidCallback onTap,
    required VoidCallback onUnpin,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 52, right: 14),
      dense: true,
      leading: Icon(
        entry.icon,
        size: 20,
        color: theme.colorScheme.primary.withValues(alpha: 0.8),
      ),
      title: Text(
        entry.title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      trailing: IconButton(
        icon: Icon(
          PhosphorIconsLight.pushPinSlash,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        tooltip: AppLocalizations.of(context)!.unpinFromSidebar,
        onPressed: onUnpin,
      ),
      onTap: onTap,
    );
  }
}
