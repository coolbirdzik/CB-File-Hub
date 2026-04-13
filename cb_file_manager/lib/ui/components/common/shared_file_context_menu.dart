import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../controllers/file_operations_handler.dart';
import '../../screens/folder_list/file_details_screen.dart';
import '../../screens/media_gallery/image_viewer_screen.dart';
import '../../screens/media_gallery/video_player_full_screen.dart';
import '../../dialogs/open_with_dialog.dart';
import '../../../helpers/files/external_app_helper.dart';
import 'package:path/path.dart' as pathlib;
import '../../tab_manager/components/tag_dialogs.dart' as tag_dialogs;
import '../../../services/network_browsing/webdav_service.dart';
import '../../../helpers/network/streaming_helper.dart';
import '../../../services/network_browsing/ftp_service.dart';
import 'package:file_picker/file_picker.dart';
import '../../../config/languages/app_localizations.dart';
import 'package:cb_file_manager/bloc/selection/selection.dart';
import '../../../helpers/media/folder_thumbnail_service.dart';
import '../../../helpers/media/video_thumbnail_helper.dart';
import '../../utils/file_type_utils.dart';
import '../../dialogs/folder_thumbnail_picker_dialog.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../screens/folder_list/folder_list_bloc.dart';
import '../../screens/folder_list/folder_list_event.dart';
import '../../screens/folder_list/folder_list_state.dart';
import '../../../helpers/files/windows_shell_context_menu.dart';
import '../../controllers/inline_rename_controller.dart';
import '../../../core/service_locator.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../utils/entity_open_actions.dart';
import '../../../utils/app_logger.dart';

enum ContextMenuTargetType {
  file,
  folder,
  multiSelection,
  background,
}

class ContextMenuAction {
  final String id;
  final String label;
  final IconData icon;
  final bool isDestructive;
  final bool isChecked;
  final bool isEnabled;
  final String? group;
  final List<ContextMenuSection>? childSections;
  final FutureOr<void> Function(BuildContext context)? onSelected;

  const ContextMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    this.isDestructive = false,
    this.isChecked = false,
    this.isEnabled = true,
    this.group,
    this.childSections,
    this.onSelected,
  });
}

class ContextMenuSection {
  final String? title;
  final List<ContextMenuAction> actions;

  const ContextMenuSection({
    this.title,
    required this.actions,
  });
}

bool _isMobileContextMenuPlatform() => Platform.isAndroid || Platform.isIOS;

OverlayEntry? _submenuOverlayEntry;
Timer? _submenuCloseTimer;

void _removeContextSubmenu() {
  _submenuCloseTimer?.cancel();
  _submenuCloseTimer = null;
  _submenuOverlayEntry?.remove();
  _submenuOverlayEntry = null;
}

void _scheduleContextSubmenuRemoval() {
  _submenuCloseTimer?.cancel();
  _submenuCloseTimer = Timer(
    const Duration(milliseconds: 120),
    _removeContextSubmenu,
  );
}

void _cancelContextSubmenuRemoval() {
  _submenuCloseTimer?.cancel();
  _submenuCloseTimer = null;
}

ContextMenuAction? _findContextMenuAction(
  List<ContextMenuSection> sections,
  String actionId,
) {
  for (final section in sections) {
    for (final action in section.actions) {
      if (action.id == actionId) {
        return action;
      }
    }
  }
  return null;
}

Future<void> showContextMenuPopup({
  required BuildContext context,
  required List<ContextMenuSection> sections,
  required Offset globalPosition,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;
  _removeContextSubmenu();

  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );
  final menuColor = Theme.of(context).colorScheme.surface.withAlpha(255);
  final popupItems = <PopupMenuEntry<String>>[];

  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    final section = sections[sectionIndex];
    final actions = section.actions;
    if (actions.isEmpty) {
      continue;
    }

    if (section.title != null && section.title!.isNotEmpty) {
      popupItems.add(
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            section.title!,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
          ),
        ),
      );
    }

    for (final action in actions) {
      if (action.childSections != null && action.childSections!.isNotEmpty) {
        popupItems.add(
          PopupMenuItem<String>(
            enabled: false,
            padding: EdgeInsets.zero,
            height: 48,
            child: _ContextMenuPopupSubmenuTrigger(
              actionContext: context,
              overlayBox: overlay,
              action: action,
            ),
          ),
        );
      } else {
        popupItems.add(
          PopupMenuItem<String>(
            value: action.id,
            enabled: action.isEnabled,
            child: _buildContextMenuActionRow(
              context,
              action,
              forPopup: true,
            ),
          ),
        );
      }
    }

    if (sectionIndex < sections.length - 1) {
      popupItems.add(const PopupMenuDivider());
    }
  }

  final selectedId = await showMenu<String>(
    context: context,
    position: position,
    color: menuColor,
    items: popupItems,
    popUpAnimationStyle: AnimationStyle.noAnimation,
  );
  _removeContextSubmenu();
  if (selectedId == null || !context.mounted) {
    return;
  }

  final action = _findContextMenuAction(sections, selectedId);
  if (action == null) {
    return;
  }

  if (action.onSelected == null) {
    return;
  }
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) {
    return;
  }
  await action.onSelected!(context);
}

Future<void> showContextMenuSheet({
  required BuildContext context,
  required String title,
  IconData? icon,
  String? subtitle,
  Widget? headerContent,
  required List<ContextMenuSection> sections,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: _ContextMenuSheetContent(
        actionContext: context,
        title: title,
        icon: icon,
        subtitle: subtitle,
        headerContent: headerContent,
        sections: sections,
      ),
    ),
  );
}

Widget _buildContextMenuActionRow(
  BuildContext context,
  ContextMenuAction action, {
  bool forPopup = false,
}) {
  final theme = Theme.of(context);
  final bool isDestructive = action.isDestructive;
  final Color color = !action.isEnabled
      ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
      : isDestructive
          ? theme.colorScheme.error
          : theme.colorScheme.onSurface;

  final icon = Icon(
    action.icon,
    size: forPopup ? 18 : 20,
    color: color,
  );
  final text = Text(
    action.label,
    style: TextStyle(
      color: color,
      fontWeight: action.isChecked ? FontWeight.w600 : FontWeight.w500,
    ),
  );
  final Widget? trailing;
  if (action.childSections != null && action.childSections!.isNotEmpty) {
    trailing = Icon(
      PhosphorIconsLight.caretRight,
      size: forPopup ? 16 : 18,
      color: color,
    );
  } else if (action.isChecked) {
    trailing = Icon(
      PhosphorIconsLight.check,
      size: forPopup ? 16 : 18,
      color: theme.colorScheme.primary,
    );
  } else {
    trailing = null;
  }

  return Row(
    children: [
      icon,
      const SizedBox(width: 12),
      Expanded(child: text),
      if (trailing != null) trailing,
    ],
  );
}

Offset _submenuPopupPosition({
  required Size overlaySize,
  required Offset anchorPosition,
  required double itemWidth,
}) {
  const submenuWidth = 220.0;
  const verticalPadding = 8.0;

  double dx = anchorPosition.dx + itemWidth;
  if (dx + submenuWidth > overlaySize.width) {
    dx = anchorPosition.dx - submenuWidth;
  }
  dx = dx.clamp(verticalPadding, overlaySize.width - submenuWidth);

  final dy = anchorPosition.dy.clamp(
    verticalPadding,
    overlaySize.height - 220.0,
  );

  return Offset(dx, dy);
}

class _ContextMenuPopupSubmenuTrigger extends StatelessWidget {
  final BuildContext actionContext;
  final RenderBox overlayBox;
  final ContextMenuAction action;

  const _ContextMenuPopupSubmenuTrigger({
    required this.actionContext,
    required this.overlayBox,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final itemKey = GlobalKey();

    void openSubmenu() {
      _cancelContextSubmenuRemoval();
      final itemContext = itemKey.currentContext;
      if (itemContext == null || action.childSections == null) {
        return;
      }

      final itemBox = itemContext.findRenderObject() as RenderBox?;
      if (itemBox == null) {
        return;
      }

      final itemPosition = itemBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      final submenuPosition = _submenuPopupPosition(
        overlaySize: overlayBox.size,
        anchorPosition: itemPosition,
        itemWidth: itemBox.size.width,
      );

      _removeContextSubmenu();
      _submenuOverlayEntry = OverlayEntry(
        builder: (_) => Positioned(
          left: submenuPosition.dx,
          top: submenuPosition.dy,
          width: 220,
          child: MouseRegion(
            onEnter: (_) => _cancelContextSubmenuRemoval(),
            onExit: (_) => _scheduleContextSubmenuRemoval(),
            child: Material(
              color: Theme.of(actionContext).colorScheme.surface.withAlpha(255),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final section in action.childSections!) ...[
                        if (section.title != null && section.title!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                            child: Text(
                              section.title!,
                              style: Theme.of(actionContext)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                  ),
                            ),
                          ),
                        for (final childAction in section.actions)
                          InkWell(
                            onTap: !childAction.isEnabled
                                ? null
                                : () async {
                                    _removeContextSubmenu();
                                    Navigator.pop(context);
                                    if (childAction.onSelected != null &&
                                        actionContext.mounted) {
                                      await childAction.onSelected!(
                                        actionContext,
                                      );
                                    }
                                  },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              child: _buildContextMenuActionRow(
                                actionContext,
                                childAction,
                                forPopup: true,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Overlay.of(actionContext).insert(_submenuOverlayEntry!);
    }

    return MouseRegion(
      key: itemKey,
      onEnter: (_) => openSubmenu(),
      onExit: (_) => _scheduleContextSubmenuRemoval(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: openSubmenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: _buildContextMenuActionRow(
            actionContext,
            action,
            forPopup: true,
          ),
        ),
      ),
    );
  }
}

class _ContextMenuSheetContent extends StatelessWidget {
  final BuildContext actionContext;
  final String title;
  final IconData? icon;
  final String? subtitle;
  final Widget? headerContent;
  final List<ContextMenuSection> sections;

  const _ContextMenuSheetContent({
    required this.actionContext,
    required this.title,
    required this.sections,
    this.icon,
    this.subtitle,
    this.headerContent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (headerContent != null) ...[
                          const SizedBox(height: 8),
                          headerContent!,
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      PhosphorIconsLight.x,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            for (final section in sections) ...[
              if (section.title != null && section.title!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  child: Text(
                    section.title!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              for (final action in section.actions)
                _ContextMenuSheetActionTile(
                  actionContext: actionContext,
                  action: action,
                ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ContextMenuSheetActionTile extends StatelessWidget {
  final BuildContext actionContext;
  final ContextMenuAction action;

  const _ContextMenuSheetActionTile({
    required this.actionContext,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDestructive = action.isDestructive;
    final Color color = !action.isEnabled
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
        : isDestructive
            ? theme.colorScheme.error
            : theme.colorScheme.onSurface;

    return ListTile(
      enabled: action.isEnabled,
      minTileHeight: 44,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(action.icon, color: color),
      title: Text(
        action.label,
        style: TextStyle(
          color: color,
          fontWeight: action.isChecked ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      trailing: action.childSections != null && action.childSections!.isNotEmpty
          ? Icon(
              PhosphorIconsLight.caretRight,
              color: color,
            )
          : action.isChecked
              ? Icon(
                  PhosphorIconsLight.check,
                  color: theme.colorScheme.primary,
                )
              : null,
      onTap: !action.isEnabled
          ? null
          : () async {
              Navigator.pop(context);
              if (action.childSections != null &&
                  action.childSections!.isNotEmpty) {
                await Future<void>.delayed(Duration.zero);
                if (actionContext.mounted) {
                  await showContextMenuSheet(
                    context: actionContext,
                    title: action.label,
                    icon: action.icon,
                    sections: action.childSections!,
                  );
                }
                return;
              }
              if (action.onSelected != null) {
                await Future<void>.delayed(Duration.zero);
                if (actionContext.mounted) {
                  await action.onSelected!(actionContext);
                }
              }
            },
    );
  }
}

/// A shared context menu for files
///
/// This menu is used by both grid view and list view to provide a consistent UI
class SharedFileContextMenu extends StatelessWidget {
  final File file;
  final List<String> fileTags;
  final bool isVideo;
  final bool isImage;
  final FolderListBloc? folderListBloc;
  final BuildContext? actionContext;
  final Function(BuildContext, String)? showAddTagToFileDialog;

  const SharedFileContextMenu({
    Key? key,
    required this.file,
    required this.fileTags,
    required this.isVideo,
    required this.isImage,
    this.folderListBloc,
    this.actionContext,
    this.showAddTagToFileDialog,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentService = StreamingHelper.instance.currentNetworkService;
    String? webDavSize;
    String? webDavModified;
    String? remotePath;
    String? remoteFileName;
    if (currentService is WebDAVService) {
      remotePath = currentService.getRemotePathFromLocal(file.path);
      if (remotePath != null) {
        remoteFileName = pathlib.basename(remotePath);
        final meta = currentService.getMeta(remotePath);
        if (meta != null) {
          if (meta.size >= 0) {
            webDavSize = _formatSize(meta.size);
          }
          webDavModified = meta.modified.toString().split('.').first;
        }
      }
    } else if (currentService is FTPService) {
      // For FTP, UI path is used as key
      remotePath = file.path;
      remoteFileName = pathlib.basename(file.path);
      final meta = currentService.getMeta(file.path);
      if (meta != null) {
        if (meta.size >= 0) {
          webDavSize = _formatSize(meta.size);
        }
        if (meta.modified != null) {
          webDavModified = meta.modified!.toString().split('.').first;
        }
      }
    }

    final headerContent = (webDavSize != null || webDavModified != null)
        ? Builder(
            builder: (context) {
              final theme = Theme.of(context);
              return Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (webDavSize != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIconsLight.hardDrives,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          webDavSize,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  if (webDavModified != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIconsLight.calendarBlank,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          webDavModified,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              );
            },
          )
        : null;

    return _ContextMenuSheetContent(
      actionContext: actionContext ?? context,
      title: remoteFileName ?? _basename(file),
      icon: isVideo
          ? PhosphorIconsLight.videoCamera
          : isImage
              ? PhosphorIconsLight.image
              : PhosphorIconsLight.file,
      headerContent: headerContent,
      sections: _buildFileContextMenuSections(
        context: context,
        folderListBloc: folderListBloc,
        file: file,
        fileTags: fileTags,
        isVideo: isVideo,
        isImage: isImage,
        showAddTagToFileDialog: showAddTagToFileDialog,
        remotePath: remotePath,
        remoteFileName: remoteFileName,
      ),
    );
  }

  // Helper to get file basename
  String _basename(File file) {
    return file.path.split(Platform.pathSeparator).last;
  }
}

/// A shared context menu for folders
class SharedFolderContextMenu extends StatelessWidget {
  final Directory folder;
  final Function(String)? onNavigate;
  final List<String> folderTags;
  final FolderListBloc? folderListBloc;
  final BuildContext? actionContext;
  final Function(BuildContext, String)? showAddTagToFileDialog;

  const SharedFolderContextMenu({
    Key? key,
    required this.folder,
    this.onNavigate,
    this.folderTags = const [],
    this.folderListBloc,
    this.actionContext,
    this.showAddTagToFileDialog,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isPathPinnedToSidebar(folder.path),
      builder: (context, snapshot) => _ContextMenuSheetContent(
        actionContext: actionContext ?? context,
        title: _basename(folder),
        icon: PhosphorIconsLight.folder,
        sections: _buildFolderContextMenuSections(
          context: context,
          folderListBloc: folderListBloc,
          folder: folder,
          onNavigate: onNavigate,
          folderTags: folderTags,
          showAddTagToFileDialog: showAddTagToFileDialog,
          isPinnedToSidebar: snapshot.data,
        ),
      ),
    );
  }

  // Helper to get folder basename
  String _basename(Directory dir) {
    String path = dir.path;
    // Handle trailing slash
    if (path.endsWith(Platform.pathSeparator)) {
      path = path.substring(0, path.length - 1);
    }
    return path.split(Platform.pathSeparator).last;
  }
}

List<ContextMenuSection> _buildFileContextMenuSections({
  required BuildContext context,
  FolderListBloc? folderListBloc,
  required File file,
  required List<String> fileTags,
  required bool isVideo,
  required bool isImage,
  Function(BuildContext, String)? showAddTagToFileDialog,
  String? remotePath,
  String? remoteFileName,
  Offset? globalPosition,
}) {
  final l10n = AppLocalizations.of(context)!;
  final currentService = StreamingHelper.instance.currentNetworkService;
  final isDesktopPlatform =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  final canShowShellMenu = Platform.isWindows &&
      FileSystemEntity.typeSync(file.path) != FileSystemEntityType.notFound;
  final canDownloadRemote =
      (currentService is WebDAVService || currentService is FTPService) &&
          remotePath != null;

  return [
    ContextMenuSection(
      title: l10n.open,
      actions: [
        if (isVideo)
          ContextMenuAction(
            id: 'play_video',
            label: l10n.playVideo,
            icon: PhosphorIconsLight.playCircle,
            onSelected: (_) => _openVideoWithUserPreference(context, file),
          ),
        if (isImage)
          ContextMenuAction(
            id: 'view_image',
            label: l10n.viewImage,
            icon: PhosphorIconsLight.image,
            onSelected: (_) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(file: file),
                ),
              );
            },
          ),
        ContextMenuAction(
          id: 'open',
          label: l10n.open,
          icon: PhosphorIconsLight.file,
          onSelected: (_) =>
              ExternalAppHelper.openFileWithApp(file.path, 'shell_open'),
        ),
        if (isDesktopPlatform)
          ContextMenuAction(
            id: 'open_in_new_tab',
            label: l10n.openInNewTab,
            icon: PhosphorIconsLight.squaresFour,
            onSelected: (_) => EntityOpenActions.openInNewTab(
              context,
              sourcePath: file.path,
            ),
          ),
        if (isDesktopPlatform)
          ContextMenuAction(
            id: 'open_in_new_window',
            label: _openInNewWindowLabel(context),
            icon: PhosphorIconsLight.appWindow,
            onSelected: (_) => EntityOpenActions.openInNewWindow(
              context,
              sourcePath: file.path,
            ),
          ),
        ContextMenuAction(
          id: 'open_with',
          label: l10n.openWith,
          icon: PhosphorIconsLight.arrowSquareOut,
          onSelected: (_) => showDialog(
            context: context,
            builder: (_) => OpenWithDialog(filePath: file.path),
          ),
        ),
        ContextMenuAction(
          id: 'choose_default_app',
          label: l10n.chooseDefaultApp,
          icon: PhosphorIconsLight.appWindow,
          onSelected: (_) => showDialog(
            context: context,
            builder: (_) => OpenWithDialog(
              filePath: file.path,
              saveAsDefaultOnSelect: true,
            ),
          ),
        ),
        if (canDownloadRemote)
          ContextMenuAction(
            id: 'download',
            label: l10n.download,
            icon: PhosphorIconsLight.downloadSimple,
            onSelected: (_) => _downloadRemoteFile(
              context: context,
              file: file,
              remoteFileName: remoteFileName,
            ),
          ),
      ],
    ),
    ContextMenuSection(
      title: l10n.copy,
      actions: [
        ContextMenuAction(
          id: 'copy',
          label: l10n.copy,
          icon: PhosphorIconsLight.copy,
          onSelected: (_) => FileOperationsHandler.copyToClipboard(
              context: context, entity: file),
        ),
        ContextMenuAction(
          id: 'cut',
          label: l10n.cut,
          icon: PhosphorIconsLight.scissors,
          onSelected: (_) => FileOperationsHandler.cutToClipboard(
              context: context, entity: file),
        ),
        ContextMenuAction(
          id: 'rename',
          label: l10n.rename,
          icon: PhosphorIconsLight.pencilSimple,
          onSelected: (_) => _renameEntity(
            context: context,
            entity: file,
            folderListBloc: folderListBloc,
          ),
        ),
        ContextMenuAction(
          id: 'tags',
          label: l10n.manageTags,
          icon: PhosphorIconsLight.tag,
          onSelected: (_) {
            AppLogger.info(
              '[ManageTags][ContextMenu] Tags clicked for file ${file.path}',
            );
            if (showAddTagToFileDialog != null) {
              AppLogger.info(
                '[ManageTags][ContextMenu] Using injected showAddTagToFileDialog for file ${file.path}',
              );
              showAddTagToFileDialog(context, file.path);
            } else {
              AppLogger.info(
                '[ManageTags][ContextMenu] Using default tag_dialogs.showAddTagToFileDialog for file ${file.path}',
              );
              tag_dialogs.showAddTagToFileDialog(context, file.path);
            }
          },
        ),
      ],
    ),
    ContextMenuSection(
      title: l10n.properties,
      actions: [
        ContextMenuAction(
          id: 'properties',
          label: l10n.properties,
          icon: PhosphorIconsLight.info,
          onSelected: (_) => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FileDetailsScreen(file: file),
            ),
          ),
        ),
        ContextMenuAction(
          id: 'delete',
          label: l10n.moveToTrash,
          icon: PhosphorIconsLight.trash,
          isDestructive: true,
          onSelected: (_) {
            final isDir = FileSystemEntity.isDirectorySync(file.path);
            SelectionBloc? selBloc;
            try {
              selBloc = context.read<SelectionBloc>();
            } catch (_) {
              selBloc = null;
            }
            final targetFolderListBloc =
                folderListBloc ?? _maybeFolderListBloc(context);
            if (targetFolderListBloc == null) {
              return;
            }
            FileOperationsHandler.handleDelete(
              context: context,
              folderListBloc: targetFolderListBloc,
              selectedFiles: isDir ? [] : [file.path],
              selectedFolders: isDir ? [file.path] : [],
              selectionBloc: selBloc,
              permanent: false,
              onClearSelection: () {},
            );
          },
        ),
        if (canShowShellMenu)
          ContextMenuAction(
            id: 'more_options',
            label: l10n.moreOptions,
            icon: PhosphorIconsLight.dotsThreeVertical,
            onSelected: (_) async {
              if (globalPosition == null) return;
              await WindowsShellContextMenu.showForPaths(
                paths: [file.path],
                globalPosition: globalPosition,
                devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
              );
            },
          ),
      ],
    ),
  ];
}

ScaffoldMessengerState? _maybeScaffoldMessenger(BuildContext context) {
  try {
    return ScaffoldMessenger.maybeOf(context);
  } catch (_) {
    return null;
  }
}

FolderListBloc? _maybeFolderListBloc(BuildContext context) {
  try {
    return context.read<FolderListBloc>();
  } catch (_) {
    return null;
  }
}

Future<T?> _showNoAnimationDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, _, __) => builder(dialogContext),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      return child;
    },
    useRootNavigator: true,
  );
}

/// Helper function to show file context menu
void showFileContextMenu({
  required BuildContext context,
  required File file,
  required List<String> fileTags,
  required bool isVideo,
  required bool isImage,
  Function(BuildContext, String)? showAddTagToFileDialog,
  Offset? globalPosition,
}) {
  final folderListBloc = _maybeFolderListBloc(context);
  if (_isMobileContextMenuPlatform()) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SafeArea(
          top: false,
          child: SharedFileContextMenu(
            file: file,
            fileTags: fileTags,
            isVideo: isVideo,
            isImage: isImage,
            folderListBloc: folderListBloc,
            actionContext: context,
            showAddTagToFileDialog: showAddTagToFileDialog,
          ),
        ),
      ),
    );
    return;
  }

  final screenSize = MediaQuery.of(context).size;
  final effectivePosition =
      globalPosition ?? Offset(screenSize.width / 2, screenSize.height / 2);
  final currentService = StreamingHelper.instance.currentNetworkService;
  String? remotePath;
  String? remoteFileName;
  if (currentService is WebDAVService) {
    remotePath = currentService.getRemotePathFromLocal(file.path);
    if (remotePath != null) {
      remoteFileName = pathlib.basename(remotePath);
    }
  } else if (currentService is FTPService) {
    remotePath = file.path;
    remoteFileName = pathlib.basename(file.path);
  }

  final sections = _buildFileContextMenuSections(
    context: context,
    folderListBloc: folderListBloc,
    file: file,
    fileTags: fileTags,
    isVideo: isVideo,
    isImage: isImage,
    showAddTagToFileDialog: showAddTagToFileDialog,
    remotePath: remotePath,
    remoteFileName: remoteFileName,
    globalPosition: effectivePosition,
  );
  unawaited(
    showContextMenuPopup(
      context: context,
      sections: sections,
      globalPosition: effectivePosition,
    ),
  );
}

Future<void> _downloadRemoteFile({
  required BuildContext context,
  required File file,
  String? remoteFileName,
}) async {
  try {
    final fileName = remoteFileName ?? pathlib.basename(file.path);
    final String? saveLocation = await FilePicker.platform.saveFile(
      dialogTitle: 'Save "$fileName" as...',
      fileName: fileName,
    );
    if (saveLocation == null) {
      return;
    }
    await StreamingHelper.instance.downloadFile(file.path, saveLocation);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.downloadedTo(saveLocation)),
      ),
    );
  } catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            AppLocalizations.of(context)!.downloadFailed(error.toString())),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

Future<bool> _isPathPinnedToSidebar(String path) async {
  final prefs = UserPreferences.instance;
  await prefs.init();
  return prefs.isPathPinnedToSidebar(path);
}

Future<void> _toggleSidebarPinnedPathWithFeedback(
  BuildContext context,
  String path,
) async {
  final prefs = UserPreferences.instance;
  await prefs.init();

  final isPinned = await prefs.isPathPinnedToSidebar(path);
  if (isPinned) {
    await prefs.removeSidebarPinnedPath(path);
  } else {
    await prefs.addSidebarPinnedPath(path);
  }

  if (!context.mounted) return;

  final l10n = AppLocalizations.of(context)!;
  final message = isPinned ? l10n.removedFromSidebar : l10n.pinnedToSidebar;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

String _openInNewWindowLabel(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  return '${l10n.open} ${l10n.newWindow.toLowerCase()}';
}

Future<void> _renameEntity({
  required BuildContext context,
  required FileSystemEntity entity,
  FolderListBloc? folderListBloc,
}) async {
  if (_tryStartInlineRename(context, entity)) {
    return;
  }

  await FileOperationsHandler.showRenameDialog(
    context: context,
    entity: entity,
    folderListBloc: folderListBloc,
  );
}

bool _tryStartInlineRename(BuildContext context, FileSystemEntity entity) {
  final bool isDesktop =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  if (!isDesktop) {
    return false;
  }

  final ViewMode? viewMode = () {
    try {
      return context.read<FolderListBloc>().state.viewMode;
    } catch (_) {
      return null;
    }
  }();
  final bool supportsInlineRename = viewMode == ViewMode.grid ||
      viewMode == ViewMode.gridPreview ||
      viewMode == ViewMode.details;
  if (!supportsInlineRename) {
    return false;
  }

  final inlineRenameController = InlineRenameScope.maybeOf(context);
  if (inlineRenameController == null) {
    return false;
  }

  inlineRenameController.startRename(entity.path);
  return true;
}

Future<void> _openVideoWithUserPreference(
  BuildContext context,
  File file,
) async {
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);

  final openedPreferred =
      await ExternalAppHelper.openWithPreferredVideoApp(file.path);
  if (openedPreferred) return;

  bool useSystemDefault = false;
  try {
    useSystemDefault =
        await locator<UserPreferences>().getUseSystemDefaultForVideo();
  } catch (_) {
    useSystemDefault = false;
  }

  if (useSystemDefault) {
    final opened = await ExternalAppHelper.openWithSystemDefault(file.path);
    if (!opened && navigator.mounted) {
      await showDialog<void>(
        context: navigator.context,
        builder: (_) => OpenWithDialog(filePath: file.path),
      );
    }
    return;
  }

  if (!navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VideoPlayerFullScreen(file: file),
    ),
  );
}

/// Helper function to show folder context menu
void showFolderContextMenu({
  required BuildContext context,
  required Directory folder,
  Function(String)? onNavigate,
  List<String> folderTags = const [],
  Function(BuildContext, String)? showAddTagToFileDialog,
  Offset? globalPosition,
}) {
  final folderListBloc = _maybeFolderListBloc(context);
  if (_isMobileContextMenuPlatform()) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SafeArea(
          top: false,
          child: SharedFolderContextMenu(
            folder: folder,
            onNavigate: onNavigate,
            folderTags: folderTags,
            folderListBloc: folderListBloc,
            actionContext: context,
            showAddTagToFileDialog: showAddTagToFileDialog,
          ),
        ),
      ),
    );
    return;
  }

  final screenSize = MediaQuery.of(context).size;
  final effectivePosition =
      globalPosition ?? Offset(screenSize.width / 2, screenSize.height / 2);
  unawaited(() async {
    final isPinnedToSidebar = await _isPathPinnedToSidebar(folder.path);
    if (!context.mounted) return;
    await showContextMenuPopup(
      context: context,
      sections: _buildFolderContextMenuSections(
        context: context,
        folderListBloc: folderListBloc,
        folder: folder,
        onNavigate: onNavigate,
        folderTags: folderTags,
        showAddTagToFileDialog: showAddTagToFileDialog,
        globalPosition: effectivePosition,
        isPinnedToSidebar: isPinnedToSidebar,
      ),
      globalPosition: effectivePosition,
    );
  }());
}

List<ContextMenuSection> _buildFolderContextMenuSections({
  required BuildContext context,
  FolderListBloc? folderListBloc,
  required Directory folder,
  Function(String)? onNavigate,
  List<String> folderTags = const [],
  Function(BuildContext, String)? showAddTagToFileDialog,
  Offset? globalPosition,
  bool? isPinnedToSidebar,
}) {
  final l10n = AppLocalizations.of(context)!;
  final isDesktopPlatform =
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  final canShowShellMenu = Platform.isWindows &&
      FileSystemEntity.typeSync(folder.path) != FileSystemEntityType.notFound;

  return [
    ContextMenuSection(
      title: l10n.open,
      actions: [
        ContextMenuAction(
          id: 'open',
          label: l10n.openFolder,
          icon: PhosphorIconsLight.folderOpen,
          onSelected: (_) {
            if (onNavigate != null) {
              onNavigate(folder.path);
            }
          },
        ),
        if (isDesktopPlatform)
          ContextMenuAction(
            id: 'open_in_new_tab',
            label: l10n.openInNewTab,
            icon: PhosphorIconsLight.squaresFour,
            onSelected: (_) => EntityOpenActions.openInNewTab(
              context,
              sourcePath: folder.path,
            ),
          ),
        if (isDesktopPlatform)
          ContextMenuAction(
            id: 'open_in_split_view',
            label: l10n.openInSplitView,
            icon: PhosphorIconsLight.columns,
            onSelected: (_) => EntityOpenActions.openInSplitView(
              context,
              sourcePath: folder.path,
            ),
          ),
        if (isDesktopPlatform)
          ContextMenuAction(
            id: 'open_in_new_window',
            label: _openInNewWindowLabel(context),
            icon: PhosphorIconsLight.appWindow,
            onSelected: (_) => EntityOpenActions.openInNewWindow(
              context,
              sourcePath: folder.path,
            ),
          ),
        ContextMenuAction(
          id: 'toggle_pin_sidebar',
          label: isPinnedToSidebar == true
              ? l10n.unpinFromSidebar
              : l10n.pinToSidebar,
          icon: isPinnedToSidebar == true
              ? PhosphorIconsLight.pushPinSlash
              : PhosphorIconsLight.pushPin,
          onSelected: (_) =>
              _toggleSidebarPinnedPathWithFeedback(context, folder.path),
        ),
      ],
    ),
    ContextMenuSection(
      title: l10n.copy,
      actions: [
        ContextMenuAction(
          id: 'copy',
          label: l10n.copy,
          icon: PhosphorIconsLight.copy,
          onSelected: (_) => FileOperationsHandler.copyToClipboard(
              context: context, entity: folder),
        ),
        ContextMenuAction(
          id: 'cut',
          label: l10n.cut,
          icon: PhosphorIconsLight.scissors,
          onSelected: (_) => FileOperationsHandler.cutToClipboard(
              context: context, entity: folder),
        ),
        ContextMenuAction(
          id: 'paste',
          label: l10n.pasteHere,
          icon: PhosphorIconsLight.clipboard,
          onSelected: (_) => FileOperationsHandler.pasteFromClipboard(
            context: context,
            destinationPath: folder.path,
          ),
        ),
        ContextMenuAction(
          id: 'rename',
          label: l10n.rename,
          icon: PhosphorIconsLight.pencilSimple,
          onSelected: (_) => _renameEntity(
            context: context,
            entity: folder,
            folderListBloc: folderListBloc,
          ),
        ),
        ContextMenuAction(
          id: 'tags',
          label: l10n.manageTags,
          icon: PhosphorIconsLight.tag,
          onSelected: (_) {
            AppLogger.info(
              '[ManageTags][ContextMenu] Tags clicked for folder ${folder.path}',
            );
            if (showAddTagToFileDialog != null) {
              AppLogger.info(
                '[ManageTags][ContextMenu] Using injected showAddTagToFileDialog for folder ${folder.path}',
              );
              showAddTagToFileDialog(context, folder.path);
            } else {
              AppLogger.info(
                '[ManageTags][ContextMenu] Using default tag_dialogs.showAddTagToFileDialog for folder ${folder.path}',
              );
              tag_dialogs.showAddTagToFileDialog(context, folder.path);
            }
          },
        ),
      ],
    ),
    ContextMenuSection(
      title: l10n.properties,
      actions: [
        ContextMenuAction(
          id: 'properties',
          label: l10n.properties,
          icon: PhosphorIconsLight.info,
          onSelected: (_) => _showFolderPropertiesDialog(context, folder),
        ),
        if (canShowShellMenu)
          ContextMenuAction(
            id: 'more_options',
            label: l10n.moreOptions,
            icon: PhosphorIconsLight.dotsThreeVertical,
            onSelected: (_) async {
              if (globalPosition == null) return;
              await WindowsShellContextMenu.showForPaths(
                paths: [folder.path],
                globalPosition: globalPosition,
                devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
              );
            },
          ),
      ],
    ),
  ];
}

void _showFolderPropertiesDialog(BuildContext context, Directory folder) {
  final folderName = folder.path.split(Platform.pathSeparator).last;
  final l10n = AppLocalizations.of(context)!;
  final thumbnailService = FolderThumbnailService();
  final scaffoldMessenger = _maybeScaffoldMessenger(context);
  Future<String?> customThumbnailFuture =
      thumbnailService.getCustomThumbnailPath(folder.path);

  folder.stat().then((stat) {
    if (!context.mounted) return;

    _showNoAnimationDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.properties),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _propertyRow(l10n.fileName, folderName),
                const Divider(),
                _propertyRow(l10n.filePath, folder.path),
                const Divider(),
                _propertyRow(
                    l10n.fileModified, stat.modified.toString().split('.')[0]),
                const Divider(),
                _propertyRow(
                    l10n.fileAccessed, stat.accessed.toString().split('.')[0]),
                const Divider(),
                Text(
                  l10n.folderThumbnail,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                FutureBuilder<String?>(
                  future: customThumbnailFuture,
                  builder: (context, snapshot) {
                    final value = snapshot.data;
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Text(l10n.loadingThumbnails);
                    }

                    if (value == null || value.isEmpty) {
                      return Text(l10n.thumbnailAuto);
                    }

                    final displayValue = value.startsWith('video::')
                        ? value.substring(7)
                        : value;
                    return Text(displayValue);
                  },
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: () async {
                        final selectedPath =
                            await showFolderThumbnailPickerDialog(
                          dialogContext,
                          folder.path,
                        );
                        if (selectedPath == null) {
                          return;
                        }

                        final isImage = FileTypeUtils.isImageFile(selectedPath);
                        final isVideo =
                            VideoThumbnailHelper.isSupportedVideoFormat(
                                selectedPath);
                        if (!isImage && !isVideo) {
                          if (context.mounted && scaffoldMessenger != null) {
                            scaffoldMessenger.showSnackBar(
                              SnackBar(
                                  content: Text(l10n.invalidThumbnailFile)),
                            );
                          }
                          return;
                        }

                        await thumbnailService.setCustomThumbnail(
                          folder.path,
                          selectedPath,
                          isVideo: isVideo,
                        );
                        if (dialogContext.mounted) {
                          setState(() {
                            customThumbnailFuture = Future.value(isVideo
                                ? 'video::$selectedPath'
                                : selectedPath);
                          });
                        }
                        if (context.mounted && scaffoldMessenger != null) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(content: Text(l10n.folderThumbnailSet)),
                          );
                        }
                      },
                      child: Text(l10n.chooseThumbnail.toUpperCase()),
                    ),
                    TextButton(
                      onPressed: () async {
                        await thumbnailService
                            .clearCustomThumbnail(folder.path);
                        if (dialogContext.mounted) {
                          setState(() {
                            customThumbnailFuture = Future.value(null);
                          });
                        }
                        if (context.mounted && scaffoldMessenger != null) {
                          scaffoldMessenger.showSnackBar(
                            SnackBar(
                                content: Text(l10n.folderThumbnailCleared)),
                          );
                        }
                      },
                      child: Text(l10n.clearThumbnail.toUpperCase()),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close.toUpperCase()),
            ),
          ],
        ),
      ),
    );
  }).catchError((error) {
    if (!context.mounted) return;
    scaffoldMessenger?.showSnackBar(
      SnackBar(
          content: Text(l10n.errorGettingFolderProperties(error.toString()))),
    );
  });
}

Widget _propertyRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Helper function to show context menu for multiple selected files
void showMultipleFilesContextMenu({
  required BuildContext context,
  required List<String> selectedPaths,
  Offset? globalPosition,
  required VoidCallback onClearSelection,
}) {
  final screenSize = MediaQuery.of(context).size;
  final effectivePosition =
      globalPosition ?? Offset(screenSize.width / 2, screenSize.height / 2);
  final sections = _buildMultiSelectionContextMenuSections(
    context: context,
    folderListBloc: _maybeFolderListBloc(context),
    selectedPaths: selectedPaths,
    onClearSelection: onClearSelection,
    globalPosition: effectivePosition,
  );

  if (_isMobileContextMenuPlatform()) {
    final l10n = AppLocalizations.of(context)!;
    unawaited(
      showContextMenuSheet(
        context: context,
        title: l10n.itemsSelected(selectedPaths.length),
        icon: PhosphorIconsLight.checks,
        sections: sections,
      ),
    );
    return;
  }

  unawaited(
    showContextMenuPopup(
      context: context,
      sections: sections,
      globalPosition: effectivePosition,
    ),
  );
}

List<ContextMenuSection> _buildMultiSelectionContextMenuSections({
  required BuildContext context,
  FolderListBloc? folderListBloc,
  required List<String> selectedPaths,
  required VoidCallback onClearSelection,
  Offset? globalPosition,
}) {
  final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
  final bloc = folderListBloc;
  final l10n = AppLocalizations.of(context)!;
  final count = selectedPaths.length;
  final canShowShellMenu = Platform.isWindows &&
      selectedPaths.isNotEmpty &&
      selectedPaths.every((path) =>
          FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound);

  final entitiesList = <FileSystemEntity>[];
  final files = <String>[];
  final folders = <String>[];

  for (final path in selectedPaths) {
    if (FileSystemEntity.isDirectorySync(path)) {
      entitiesList.add(Directory(path));
      folders.add(path);
    } else {
      entitiesList.add(File(path));
      files.add(path);
    }
  }

  return [
    ContextMenuSection(
      title: l10n.itemsSelected(count),
      actions: [
        ContextMenuAction(
          id: 'copy',
          label: l10n.copy,
          icon: PhosphorIconsLight.copy,
          isEnabled: bloc != null,
          onSelected: (_) {
            if (bloc == null) return;
            bloc.add(CopyFiles(entitiesList));
            _maybeScaffoldMessenger(context)?.showSnackBar(
              SnackBar(content: Text(l10n.copiedToClipboard('$count items'))),
            );
          },
        ),
        ContextMenuAction(
          id: 'cut',
          label: l10n.cut,
          icon: PhosphorIconsLight.scissors,
          isEnabled: bloc != null,
          onSelected: (_) {
            if (bloc == null) return;
            bloc.add(CutFiles(entitiesList));
            _maybeScaffoldMessenger(context)?.showSnackBar(
              SnackBar(content: Text(l10n.cutToClipboard('$count items'))),
            );
          },
        ),
        ContextMenuAction(
          id: 'tags',
          label: l10n.manageTags,
          icon: PhosphorIconsLight.tag,
          onSelected: (_) {
            AppLogger.info(
              '[ManageTags][MultiContextMenu] Tags clicked for selected paths',
              error: 'selectedPaths=$selectedPaths',
            );
            if (selectedPaths.length == 1) {
              AppLogger.info(
                '[ManageTags][MultiContextMenu] Redirecting single selected path to single-file dialog',
                error: 'filePath=${selectedPaths.first}',
              );
              tag_dialogs.showAddTagToFileDialog(context, selectedPaths.first);
            } else {
              AppLogger.info(
                '[ManageTags][MultiContextMenu] Opening batch tag dialog',
                error: 'selectedPaths=$selectedPaths',
              );
              tag_dialogs.showBatchAddTagDialog(context, selectedPaths);
            }
          },
        ),
        ContextMenuAction(
          id: 'delete',
          label: l10n.deleteTitle,
          icon: PhosphorIconsLight.trash,
          isDestructive: true,
          isEnabled: bloc != null,
          onSelected: (_) {
            if (bloc == null) return;
            SelectionBloc? selectionBloc;
            try {
              selectionBloc = context.read<SelectionBloc>();
            } catch (_) {
              selectionBloc = null;
            }
            FileOperationsHandler.handleDelete(
              context: context,
              folderListBloc: bloc,
              selectedFiles: files,
              selectedFolders: folders,
              selectionBloc: selectionBloc,
              permanent: false,
              onClearSelection: onClearSelection,
            );
          },
        ),
        if (canShowShellMenu)
          ContextMenuAction(
            id: 'more_options',
            label: l10n.moreOptions,
            icon: PhosphorIconsLight.dotsThreeVertical,
            onSelected: (_) {
              if (globalPosition == null) return;
              WindowsShellContextMenu.showForPaths(
                paths: selectedPaths,
                globalPosition: globalPosition,
                devicePixelRatio: devicePixelRatio,
              );
            },
          ),
      ],
    ),
  ];
}
