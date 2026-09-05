import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';

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

        return Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                key: ValueKey<String>(
                  'pinned-${state.activeTabId}-${widget.initialExpanded}',
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                trailing: AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  turns: _isExpanded ? 0.5 : 0.0,
                  child: Icon(
                    PhosphorIconsLight.caretDown,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                leading: Icon(
                  PhosphorIconsLight.pushPin,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  l10n.pinnedSection,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                collapsedBackgroundColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                initiallyExpanded: _isExpanded,
                onExpansionChanged: (isExpanded) {
                  setState(() {
                    _isExpanded = isExpanded;
                  });
                  widget.onExpansionChanged?.call(isExpanded);
                },
                children: state.pinnedPaths
                    .map((pinnedPath) {
                      return _buildPinnedItem(
                        context,
                        pinnedPath: pinnedPath,
                        onTap: () => widget.onNavigate(
                          pinnedPath,
                          _getPinnedDisplayName(pinnedPath),
                        ),
                        onUnpin: () {
                          context.read<DrawerCubit>().togglePinnedPath(
                            pinnedPath,
                          );
                        },
                      );
                    })
                    .toList(growable: false),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPinnedItem(
    BuildContext context, {
    required String pinnedPath,
    required VoidCallback onTap,
    required VoidCallback onUnpin,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 52, right: 14),
      dense: true,
      leading: Icon(
        _iconForPinnedPath(pinnedPath),
        size: 20,
        color: theme.colorScheme.primary.withValues(alpha: 0.8),
      ),
      title: Text(
        _getPinnedDisplayName(pinnedPath),
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

  IconData _iconForPinnedPath(String path) {
    try {
      final entityType = FileSystemEntity.typeSync(path, followLinks: false);
      if (entityType == FileSystemEntityType.file) {
        return PhosphorIconsLight.file;
      }
      if (entityType == FileSystemEntityType.directory) {
        return PhosphorIconsLight.folder;
      }
    } catch (_) {}
    return PhosphorIconsLight.pushPin;
  }

  String _getPinnedDisplayName(String path) {
    var normalized = path;
    if (normalized.endsWith(Platform.pathSeparator) && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (Platform.isWindows && RegExp(r'^[a-zA-Z]:$').hasMatch(normalized)) {
      return normalized;
    }
    if (normalized == '/') return '/';
    final parts = normalized.split(Platform.pathSeparator);
    return parts.where((part) => part.isNotEmpty).isNotEmpty
        ? parts.where((part) => part.isNotEmpty).last
        : normalized;
  }
}
