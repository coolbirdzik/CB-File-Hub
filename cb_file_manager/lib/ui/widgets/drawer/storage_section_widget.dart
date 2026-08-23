import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/design_system_config.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:cb_file_manager/ui/utils/route.dart';

class StorageSectionWidget extends StatefulWidget {
  final Function(String path, String name) onNavigate;
  final VoidCallback onTrashTap;
  final bool initialExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  const StorageSectionWidget({
    Key? key,
    required this.onNavigate,
    required this.onTrashTap,
    this.initialExpanded = false,
    this.onExpansionChanged,
  }) : super(key: key);

  @override
  State<StorageSectionWidget> createState() => _StorageSectionWidgetState();
}

/// Shows the shared confirmation used before opening a storage location that
/// requires administrator access.
void showStorageAdminAccessDialog(
  BuildContext context, {
  required Directory drive,
  required void Function(String path, String name) onNavigate,
}) {
  if (_isFluentDesktopShellActive) {
    fluent.showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => fluent.ContentDialog(
        title: Semantics(
          header: true,
          child: Text(context.tr.adminAccessRequired),
        ),
        content: Text(context.tr.driveRequiresAdmin(drive.path)),
        actions: [
          Semantics(
            button: true,
            label: context.tr.cancel,
            child: fluent.Button(
              onPressed: () => RouteUtils.safePopDialog(dialogContext),
              child: Text(context.tr.cancel),
            ),
          ),
          Semantics(
            button: true,
            label: context.tr.ok,
            child: fluent.FilledButton(
              autofocus: true,
              onPressed: () {
                RouteUtils.safePopDialog(dialogContext);
                onNavigate(drive.path, drive.path.split(r'\')[0]);
              },
              child: Text(context.tr.ok),
            ),
          ),
        ],
      ),
    );
    return;
  }

  RouteUtils.showAcrylicDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr.adminAccessRequired),
      content: Text(context.tr.driveRequiresAdmin(drive.path)),
      actions: [
        TextButton(
          onPressed: () => RouteUtils.safePopDialog(context),
          child: Text(context.tr.cancel),
        ),
        TextButton(
          onPressed: () {
            RouteUtils.safePopDialog(context);
            onNavigate(drive.path, drive.path.split(r'\')[0]);
          },
          child: Text(context.tr.ok),
        ),
      ],
    ),
  );
}

bool get _isFluentDesktopShellActive =>
    (Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
    DesignSystemConfig.enableFluentDesktopShell &&
    !DesignSystemConfig.enableLegacyMaterialDesktopShell;

class _StorageSectionWidgetState extends State<StorageSectionWidget> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
  }

  @override
  void didUpdateWidget(covariant StorageSectionWidget oldWidget) {
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
    final ThemeData theme = Theme.of(context);

    return BlocBuilder<DrawerCubit, DrawerState>(
      builder: (context, state) {
        return Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
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
                  PhosphorIconsLight.hardDrives,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  context.tr.drivesTab,
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
                children: <Widget>[
                  if (state.isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (state.storageLocations.isEmpty)
                    ListTile(
                      contentPadding:
                          const EdgeInsets.only(left: 52, right: 14),
                      title: Text(context.tr.noStorageLocationsFound),
                      trailing: IconButton(
                        icon: const Icon(PhosphorIconsLight.arrowsClockwise),
                        onPressed: () {
                          context.read<DrawerCubit>().loadStorageLocations();
                        },
                      ),
                    )
                  else
                    ...state.storageLocations.map((storage) {
                      return _buildStorageItem(context, storage);
                    }),

                  // Trash Bin
                  _buildItem(
                    context,
                    icon: PhosphorIconsLight.trash,
                    title: context.tr.trashBin,
                    iconColor: theme.colorScheme.error,
                    onTap: widget.onTrashTap,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStorageItem(BuildContext context, Directory storage) {
    final theme = Theme.of(context);
    String displayName = _getStorageDisplayName(storage);
    IconData icon = _getStorageIcon(storage);
    bool requiresAdmin = storage.requiresAdmin;

    return _buildItem(
      context,
      icon: icon,
      title: displayName,
      subtitle: requiresAdmin ? context.tr.requiresAdminPrivileges : null,
      iconColor: requiresAdmin ? theme.colorScheme.tertiary : null,
      onTap: () {
        if (requiresAdmin) {
          _showAdminAccessDialog(context, storage);
        } else {
          widget.onNavigate(storage.path, displayName);
        }
      },
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    Color? iconColor,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 52, right: 14),
      dense: true,
      leading: Icon(
        icon,
        size: 20,
        color: iconColor ?? theme.colorScheme.primary.withValues(alpha: 0.8),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color,
              ),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  void _showAdminAccessDialog(BuildContext context, Directory drive) {
    showStorageAdminAccessDialog(
      context,
      drive: drive,
      onNavigate: widget.onNavigate,
    );
  }

  // Helper methods from original file
  String _getStorageDisplayName(Directory storage) {
    String path = storage.path;
    if (path.length > 1 && path.endsWith(Platform.pathSeparator)) {
      path = path.substring(0, path.length - 1);
    }

    if (Platform.isWindows && path.contains(':')) {
      String driveLetter = path.split(r'\')[0];
      return '$driveLetter (${_getDriveTypeIcon(storage)})';
    }

    if (path == '/') return 'Root (/)';
    if (path == '/storage/emulated/0') return 'Internal Storage (Primary)';
    if (path == '/sdcard') return 'Internal Storage (sdcard)';
    if (path == '/storage') return 'Storage';

    return path;
  }

  String _getDriveTypeIcon(Directory drive) {
    String path = drive.path;
    if (path.startsWith('C:')) {
      return 'System';
    }
    return 'Drive';
  }

  IconData _getStorageIcon(Directory drive) {
    if (Platform.isWindows && drive.path.startsWith('C:')) {
      return PhosphorIconsLight.desktop;
    }
    return PhosphorIconsLight.hardDrives;
  }
}
