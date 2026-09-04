import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import '../../controllers/file_operations_handler.dart';
import '../../controllers/archive_operations_handler.dart';
import '../../controllers/archive_navigation.dart';
import '../../widgets/file_preview_pane.dart';
import '../../screens/folder_list/file_details_screen.dart';
import '../../screens/media_gallery/image_viewer_screen.dart';
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
import '../../utils/route.dart';
import '../../screens/folder_list/folder_list_event.dart';
import '../../screens/folder_list/folder_list_state.dart';
import '../../../helpers/files/windows_shell_context_menu.dart';
import '../../../helpers/files/context_menu_layout_preferences.dart';
import '../../../e2e/cb_e2e_config.dart';
import '../../controllers/inline_rename_controller.dart';
import '../../../design_system/primitives/cb_inline_rename.dart';
import '../../../core/service_locator.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../utils/entity_open_actions.dart';
import '../../utils/video_playback_launcher.dart';
import '../../../utils/app_logger.dart';
import '../../screens/settings/context_menu_layout_settings_screen.dart';

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
  final Uint8List? iconBytes;
  final bool isDestructive;
  final bool isChecked;
  final bool isEnabled;
  final String? group;
  final List<ContextMenuSection>? childSections;
  final Future<List<ContextMenuSection>> Function(BuildContext context)?
      loadChildSections;
  final FutureOr<void> Function(BuildContext context)? onSelected;

  const ContextMenuAction({
    required this.id,
    required this.label,
    required this.icon,
    this.iconBytes,
    this.isDestructive = false,
    this.isChecked = false,
    this.isEnabled = true,
    this.group,
    this.childSections,
    this.loadChildSections,
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

class _ContextSubmenuOverlayEntry {
  final OverlayEntry entry;
  final Object owner;

  const _ContextSubmenuOverlayEntry({
    required this.entry,
    required this.owner,
  });
}

final List<_ContextSubmenuOverlayEntry> _submenuOverlayEntries =
    <_ContextSubmenuOverlayEntry>[];
Timer? _submenuCloseTimer;

void _removeContextSubmenusFrom(int depth) {
  while (_submenuOverlayEntries.length > depth) {
    _submenuOverlayEntries.removeLast().entry.remove();
  }
}

bool _isContextSubmenuOwnerActive(int depth, Object owner) {
  return _submenuOverlayEntries.length > depth &&
      identical(_submenuOverlayEntries[depth].owner, owner);
}

void _removeContextSubmenu() {
  _submenuCloseTimer?.cancel();
  _submenuCloseTimer = null;
  _removeContextSubmenusFrom(0);
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
      final childSections = action.childSections;
      if (childSections != null) {
        final childAction = _findContextMenuAction(childSections, actionId);
        if (childAction != null) {
          return childAction;
        }
      }
    }
  }
  return null;
}

class _LoadedWindowsShellMenu {
  final WindowsShellMenuSession session;
  final List<ContextMenuSection> sections;

  const _LoadedWindowsShellMenu({
    required this.session,
    required this.sections,
  });
}

class _WindowsShellMenuLoader {
  final BuildContext context;
  final List<String> paths;

  Future<_LoadedWindowsShellMenu?>? _loadFuture;
  bool _disposed = false;
  String? _leasedSessionId;

  _WindowsShellMenuLoader({
    required this.context,
    required this.paths,
  });

  Future<List<ContextMenuSection>> load(BuildContext _) async {
    if (_disposed) {
      return const <ContextMenuSection>[];
    }

    final loaded = await (_loadFuture ??= _loadWindowsShellMenu(
      context: context,
      paths: paths,
    ));
    if (_disposed) {
      return const <ContextMenuSection>[];
    }
    if (loaded != null && _leasedSessionId == null) {
      _leasedSessionId = loaded.session.id;
      WindowsShellContextMenu.retainCachedThirdPartyMenuSession(
        loaded.session.id,
      );
    }
    return loaded?.sections ?? const <ContextMenuSection>[];
  }

  void dispose() {
    _disposed = true;
    final leasedSessionId = _leasedSessionId;
    _leasedSessionId = null;
    if (leasedSessionId != null) {
      WindowsShellContextMenu.releaseCachedThirdPartyMenuSession(
        leasedSessionId,
      );
    }
  }
}

bool _canOfferWindowsShellMenu(List<String> paths) {
  return Platform.isWindows && !kCbE2E && paths.isNotEmpty;
}

Future<_LoadedWindowsShellMenu?> _loadWindowsShellMenu({
  required BuildContext context,
  required List<String> paths,
}) async {
  // Integration tests interact with Flutter PopupMenuItem widgets. A native
  // Shell session is outside the widget tree, so skip discovery in E2E mode.
  if (!_canOfferWindowsShellMenu(paths) ||
      paths.any(
        (path) =>
            FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound,
      )) {
    return null;
  }

  final session =
      await WindowsShellContextMenu.loadThirdPartyMenu(paths: paths);
  if (session == null) {
    return null;
  }
  if (!context.mounted) {
    await WindowsShellContextMenu.releaseSession(session.id);
    return null;
  }

  var generatedId = 0;
  List<ContextMenuSection> convertEntries(
    List<WindowsShellMenuEntry> entries,
  ) {
    final sections = <ContextMenuSection>[];
    var actions = <ContextMenuAction>[];

    void flushSection() {
      if (actions.isEmpty) return;
      sections.add(ContextMenuSection(actions: actions));
      actions = <ContextMenuAction>[];
    }

    for (final entry in entries) {
      if (entry.type == 'separator') {
        flushSection();
        continue;
      }

      final label = entry.label?.trim();
      if (label == null || label.isEmpty) {
        continue;
      }

      final children = convertEntries(entry.children);
      final commandId = entry.commandId;
      final submenuId = entry.submenuId;
      final actionId = commandId == null
          ? submenuId == null
              ? 'shell_submenu_${session.id}_${generatedId++}'
              : 'shell_submenu_${session.id}_$submenuId'
          : 'shell_command_${session.id}_$commandId';

      actions.add(
        ContextMenuAction(
          id: actionId,
          label: label,
          icon: PhosphorIconsLight.appWindow,
          iconBytes: entry.iconBytes,
          isEnabled: entry.isEnabled &&
              (children.isNotEmpty || submenuId != null || commandId != null),
          isChecked: entry.isChecked,
          childSections: children.isEmpty ? null : children,
          loadChildSections: submenuId == null
              ? null
              : (_) async {
                  final childEntries =
                      await WindowsShellContextMenu.loadThirdPartySubmenu(
                    sessionId: session.id,
                    submenuId: submenuId,
                  );
                  return convertEntries(childEntries);
                },
          onSelected: commandId == null
              ? null
              : (_) async {
                  await WindowsShellContextMenu.invokeSessionCommand(
                    sessionId: session.id,
                    commandId: commandId,
                  );
                },
        ),
      );
    }
    flushSection();
    return sections;
  }

  final shellSections = convertEntries(session.entries);
  if (shellSections.isEmpty) {
    await WindowsShellContextMenu.releaseSession(session.id);
    return null;
  }

  return _LoadedWindowsShellMenu(
    session: session,
    sections: shellSections,
  );
}

Future<void> _showAppContextMenu({
  required BuildContext context,
  required List<ContextMenuSection> sections,
  required List<String> paths,
  required Offset globalPosition,
  required ContextMenuLayoutTarget layoutTarget,
}) async {
  final layout = await ContextMenuLayoutPreferences.instance.load(layoutTarget);
  if (!context.mounted) {
    return;
  }
  final shellMenuLoader =
      layout.hiddenIds.contains(contextMenuThirdPartyAppsId) ||
              !_canOfferWindowsShellMenu(paths)
          ? null
          : _WindowsShellMenuLoader(
              context: context,
              paths: paths,
            );

  final mergedSections = _applyContextMenuLayout(
    context: context,
    sections: sections,
    loadShellSections: shellMenuLoader?.load,
    layout: layout,
    layoutTarget: layoutTarget,
  );

  try {
    await showContextMenuPopup(
      context: context,
      sections: mergedSections,
      globalPosition: globalPosition,
    );
  } finally {
    shellMenuLoader?.dispose();
  }
}

class _ContextMenuActionOrigin {
  final ContextMenuAction action;
  final int sectionIndex;
  final String? sectionTitle;

  const _ContextMenuActionOrigin({
    required this.action,
    required this.sectionIndex,
    required this.sectionTitle,
  });
}

List<ContextMenuSection> _applyContextMenuLayout({
  required BuildContext context,
  required List<ContextMenuSection> sections,
  required Future<List<ContextMenuSection>> Function(BuildContext context)?
      loadShellSections,
  required ContextMenuLayoutPreference layout,
  required ContextMenuLayoutTarget layoutTarget,
}) {
  final actionOrigins = <String, _ContextMenuActionOrigin>{};
  for (var sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
    final section = sections[sectionIndex];
    for (final action in section.actions) {
      actionOrigins[action.id] = _ContextMenuActionOrigin(
        action: action,
        sectionIndex: sectionIndex,
        sectionTitle: section.title,
      );
    }
  }

  final orderedIds = <String>[];
  for (final id in <String>[...layout.order, ...actionOrigins.keys]) {
    if (!orderedIds.contains(id)) {
      orderedIds.add(id);
    }
  }

  final result = <ContextMenuSection>[];
  var pendingActions = <ContextMenuAction>[];
  int? pendingSectionIndex;
  String? pendingSectionTitle;

  void flushPendingActions() {
    if (pendingActions.isEmpty) return;
    result.add(
      ContextMenuSection(
        title: pendingSectionTitle,
        actions: pendingActions,
      ),
    );
    pendingActions = <ContextMenuAction>[];
    pendingSectionIndex = null;
    pendingSectionTitle = null;
  }

  for (final id in orderedIds) {
    if (layout.hiddenIds.contains(id)) {
      continue;
    }
    if (id == contextMenuThirdPartyAppsId) {
      flushPendingActions();
      if (loadShellSections != null) {
        result.add(
          ContextMenuSection(
            actions: [
              ContextMenuAction(
                id: contextMenuThirdPartyAppsId,
                label: AppLocalizations.of(context)!.thirdPartyApps,
                icon: PhosphorIconsLight.appWindow,
                loadChildSections: loadShellSections,
              ),
            ],
          ),
        );
      }
      continue;
    }

    final origin = actionOrigins[id];
    if (origin == null) {
      continue;
    }
    if (pendingSectionIndex != null &&
        pendingSectionIndex != origin.sectionIndex) {
      flushPendingActions();
    }
    pendingSectionIndex = origin.sectionIndex;
    pendingSectionTitle = origin.sectionTitle;
    pendingActions.add(origin.action);
  }
  flushPendingActions();

  final l10n = AppLocalizations.of(context)!;
  result.add(
    ContextMenuSection(
      actions: [
        ContextMenuAction(
          id: 'configure_context_menu',
          label: l10n.configureContextMenu,
          icon: PhosphorIconsLight.slidersHorizontal,
          onSelected: (actionContext) {
            Navigator.of(actionContext).push(
              MaterialPageRoute<void>(
                builder: (_) => ContextMenuLayoutSettingsScreen(
                  initialTarget: layoutTarget,
                ),
              ),
            );
          },
        ),
      ],
    ),
  );
  return result;
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
      if (_contextMenuActionHasSubmenu(action)) {
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

  final iconSize = forPopup ? 18.0 : 20.0;
  final Widget icon;
  if (action.iconBytes != null) {
    icon = Image.memory(
      action.iconBytes!,
      width: iconSize,
      height: iconSize,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => Icon(
        action.icon,
        size: iconSize,
        color: color,
      ),
    );
  } else {
    icon = Icon(
      action.icon,
      size: iconSize,
      color: color,
    );
  }
  final text = Text(
    action.label,
    style: TextStyle(
      color: color,
      fontWeight: action.isChecked ? FontWeight.w600 : FontWeight.w500,
    ),
  );
  final Widget? trailing;
  if (_contextMenuActionHasSubmenu(action)) {
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

  return KeyedSubtree(
    key: ValueKey<String>('context-menu-action-${action.id}'),
    child: Row(
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(child: text),
        if (trailing != null) trailing,
      ],
    ),
  );
}

bool _contextMenuActionHasSubmenu(ContextMenuAction action) {
  return action.loadChildSections != null ||
      (action.childSections != null && action.childSections!.isNotEmpty);
}

const double _contextSubmenuPreferredWidth = 220;
const double _contextSubmenuPreferredMaxHeight = 480;
const double _contextSubmenuWindowPadding = 8;

class _ContextSubmenuGeometry {
  final Offset position;
  final double width;
  final double maxHeight;

  const _ContextSubmenuGeometry({
    required this.position,
    required this.width,
    required this.maxHeight,
  });
}

_ContextSubmenuGeometry _contextSubmenuGeometry({
  required Size overlaySize,
  required Offset anchorPosition,
  required double itemWidth,
}) {
  final availableWidth =
      math.max(0.0, overlaySize.width - _contextSubmenuWindowPadding * 2);
  final submenuWidth = math.min(_contextSubmenuPreferredWidth, availableWidth);
  final availableHeight =
      math.max(0.0, overlaySize.height - _contextSubmenuWindowPadding * 2);
  final submenuMaxHeight =
      math.min(_contextSubmenuPreferredMaxHeight, availableHeight);

  double dx = anchorPosition.dx + itemWidth;
  if (dx + submenuWidth > overlaySize.width) {
    dx = anchorPosition.dx - submenuWidth;
  }
  final maxDx = math.max(
    _contextSubmenuWindowPadding,
    overlaySize.width - _contextSubmenuWindowPadding - submenuWidth,
  );
  dx = dx.clamp(_contextSubmenuWindowPadding, maxDx);

  final maxDy = math.max(
    _contextSubmenuWindowPadding,
    overlaySize.height - _contextSubmenuWindowPadding - submenuMaxHeight,
  );
  final dy = anchorPosition.dy.clamp(_contextSubmenuWindowPadding, maxDy);

  return _ContextSubmenuGeometry(
    position: Offset(dx, dy),
    width: submenuWidth,
    maxHeight: submenuMaxHeight,
  );
}

class _ContextMenuPopupSubmenuTrigger extends StatefulWidget {
  final BuildContext actionContext;
  final RenderBox overlayBox;
  final ContextMenuAction action;

  const _ContextMenuPopupSubmenuTrigger({
    required this.actionContext,
    required this.overlayBox,
    required this.action,
  });

  @override
  State<_ContextMenuPopupSubmenuTrigger> createState() =>
      _ContextMenuPopupSubmenuTriggerState();
}

class _ContextMenuPopupSubmenuTriggerState
    extends State<_ContextMenuPopupSubmenuTrigger> {
  final GlobalKey _itemKey = GlobalKey();
  final Object _submenuOwner = Object();
  Future<List<ContextMenuSection>>? _sectionsFuture;
  List<ContextMenuSection>? _resolvedSections;

  List<ContextMenuSection> _loadingSections() {
    return <ContextMenuSection>[
      ContextMenuSection(
        actions: <ContextMenuAction>[
          ContextMenuAction(
            id: '${widget.action.id}_loading',
            label: AppLocalizations.of(widget.actionContext)?.loading ??
                'Loading...',
            icon: PhosphorIconsLight.hourglass,
            isEnabled: false,
          ),
        ],
      ),
    ];
  }

  List<ContextMenuSection> _emptySections() {
    return <ContextMenuSection>[
      ContextMenuSection(
        actions: <ContextMenuAction>[
          ContextMenuAction(
            id: '${widget.action.id}_empty',
            label: widget.action.label,
            icon: widget.action.icon,
            isEnabled: false,
          ),
        ],
      ),
    ];
  }

  void _showSections(List<ContextMenuSection> sections) {
    final itemContext = _itemKey.currentContext;
    final itemBox = itemContext?.findRenderObject() as RenderBox?;
    if (itemBox == null) {
      return;
    }

    _showContextSubmenuOverlay(
      actionContext: widget.actionContext,
      rootMenuContext: context,
      overlayBox: widget.overlayBox,
      anchorBox: itemBox,
      sections: sections,
      depth: 0,
      owner: _submenuOwner,
    );
  }

  Future<void> _replaceLoadingSubmenu(
    Future<List<ContextMenuSection>> sectionsFuture,
  ) async {
    List<ContextMenuSection> sections;
    try {
      sections = await sectionsFuture;
    } catch (_) {
      sections = const <ContextMenuSection>[];
    }
    _resolvedSections = sections;
    if (!mounted ||
        !_isContextSubmenuOwnerActive(0, _submenuOwner) ||
        !widget.actionContext.mounted) {
      return;
    }
    _showSections(sections.isEmpty ? _emptySections() : sections);
  }

  void _openSubmenu() {
    _cancelContextSubmenuRemoval();
    final childSections = widget.action.childSections;
    if (childSections != null && childSections.isNotEmpty) {
      _showSections(childSections);
      return;
    }

    final loader = widget.action.loadChildSections;
    if (loader == null) {
      return;
    }

    final resolvedSections = _resolvedSections;
    if (resolvedSections != null) {
      _showSections(
        resolvedSections.isEmpty ? _emptySections() : resolvedSections,
      );
      return;
    }

    _showSections(_loadingSections());
    if (_sectionsFuture == null) {
      final sectionsFuture = loader(widget.actionContext);
      _sectionsFuture = sectionsFuture;
      unawaited(_replaceLoadingSubmenu(sectionsFuture));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      key: _itemKey,
      onEnter: (_) => _openSubmenu(),
      onExit: (_) => _scheduleContextSubmenuRemoval(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openSubmenu,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: _buildContextMenuActionRow(
            widget.actionContext,
            widget.action,
            forPopup: true,
          ),
        ),
      ),
    );
  }
}

void _showContextSubmenuOverlay({
  required BuildContext actionContext,
  required BuildContext rootMenuContext,
  required RenderBox overlayBox,
  required RenderBox anchorBox,
  required List<ContextMenuSection> sections,
  required int depth,
  required Object owner,
}) {
  final anchorPosition = anchorBox.localToGlobal(
    Offset.zero,
    ancestor: overlayBox,
  );
  final geometry = _contextSubmenuGeometry(
    overlaySize: overlayBox.size,
    anchorPosition: anchorPosition,
    itemWidth: anchorBox.size.width,
  );

  _removeContextSubmenusFrom(depth);
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: geometry.position.dx,
      top: geometry.position.dy,
      width: geometry.width,
      child: _ContextSubmenuPanel(
        actionContext: actionContext,
        rootMenuContext: rootMenuContext,
        overlayBox: overlayBox,
        sections: sections,
        depth: depth,
        maxHeight: geometry.maxHeight,
      ),
    ),
  );
  _submenuOverlayEntries.add(
    _ContextSubmenuOverlayEntry(entry: entry, owner: owner),
  );
  Overlay.of(actionContext).insert(entry);
}

class _ContextSubmenuPanel extends StatelessWidget {
  final BuildContext actionContext;
  final BuildContext rootMenuContext;
  final RenderBox overlayBox;
  final List<ContextMenuSection> sections;
  final int depth;
  final double maxHeight;

  const _ContextSubmenuPanel({
    required this.actionContext,
    required this.rootMenuContext,
    required this.overlayBox,
    required this.sections,
    required this.depth,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _cancelContextSubmenuRemoval(),
      onExit: (_) => _scheduleContextSubmenuRemoval(),
      child: Material(
        color: Theme.of(actionContext).colorScheme.surface.withAlpha(255),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var sectionIndex = 0;
                      sectionIndex < sections.length;
                      sectionIndex++) ...[
                    if (sectionIndex > 0) const Divider(height: 1),
                    if (sections[sectionIndex].title != null &&
                        sections[sectionIndex].title!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Text(
                          sections[sectionIndex].title!,
                          style: Theme.of(actionContext)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                        ),
                      ),
                    for (final childAction in sections[sectionIndex].actions)
                      _ContextSubmenuActionRow(
                        actionContext: actionContext,
                        rootMenuContext: rootMenuContext,
                        overlayBox: overlayBox,
                        action: childAction,
                        depth: depth,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextSubmenuActionRow extends StatefulWidget {
  final BuildContext actionContext;
  final BuildContext rootMenuContext;
  final RenderBox overlayBox;
  final ContextMenuAction action;
  final int depth;

  const _ContextSubmenuActionRow({
    required this.actionContext,
    required this.rootMenuContext,
    required this.overlayBox,
    required this.action,
    required this.depth,
  });

  @override
  State<_ContextSubmenuActionRow> createState() =>
      _ContextSubmenuActionRowState();
}

class _ContextSubmenuActionRowState extends State<_ContextSubmenuActionRow> {
  final GlobalKey _itemKey = GlobalKey();
  final Object _submenuOwner = Object();
  Future<List<ContextMenuSection>>? _sectionsFuture;
  List<ContextMenuSection>? _resolvedSections;

  int get _childDepth => widget.depth + 1;

  List<ContextMenuSection> _loadingSections() {
    return <ContextMenuSection>[
      ContextMenuSection(
        actions: <ContextMenuAction>[
          ContextMenuAction(
            id: '${widget.action.id}_loading',
            label: AppLocalizations.of(widget.actionContext)?.loading ??
                'Loading...',
            icon: PhosphorIconsLight.hourglass,
            isEnabled: false,
          ),
        ],
      ),
    ];
  }

  List<ContextMenuSection> _emptySections() {
    return <ContextMenuSection>[
      ContextMenuSection(
        actions: <ContextMenuAction>[
          ContextMenuAction(
            id: '${widget.action.id}_empty',
            label: widget.action.label,
            icon: widget.action.icon,
            isEnabled: false,
          ),
        ],
      ),
    ];
  }

  void _showSections(List<ContextMenuSection> sections) {
    final itemContext = _itemKey.currentContext;
    final itemBox = itemContext?.findRenderObject() as RenderBox?;
    if (itemBox == null) {
      return;
    }
    _showContextSubmenuOverlay(
      actionContext: widget.actionContext,
      rootMenuContext: widget.rootMenuContext,
      overlayBox: widget.overlayBox,
      anchorBox: itemBox,
      sections: sections,
      depth: _childDepth,
      owner: _submenuOwner,
    );
  }

  Future<void> _replaceLoadingSubmenu(
    Future<List<ContextMenuSection>> sectionsFuture,
  ) async {
    List<ContextMenuSection> sections;
    try {
      sections = await sectionsFuture;
    } catch (_) {
      sections = const <ContextMenuSection>[];
    }
    _resolvedSections = sections;
    if (!mounted ||
        !_isContextSubmenuOwnerActive(_childDepth, _submenuOwner) ||
        !widget.actionContext.mounted) {
      return;
    }
    _showSections(sections.isEmpty ? _emptySections() : sections);
  }

  void _openChildSubmenu() {
    if (!widget.action.isEnabled ||
        !_contextMenuActionHasSubmenu(widget.action)) {
      return;
    }
    _cancelContextSubmenuRemoval();

    final childSections = widget.action.childSections;
    if (childSections != null && childSections.isNotEmpty) {
      _showSections(childSections);
      return;
    }

    final resolvedSections = _resolvedSections;
    if (resolvedSections != null) {
      _showSections(
        resolvedSections.isEmpty ? _emptySections() : resolvedSections,
      );
      return;
    }

    final loader = widget.action.loadChildSections;
    if (loader == null) {
      return;
    }
    _showSections(_loadingSections());
    if (_sectionsFuture == null) {
      final sectionsFuture = loader(widget.actionContext);
      _sectionsFuture = sectionsFuture;
      unawaited(_replaceLoadingSubmenu(sectionsFuture));
    }
  }

  Future<void> _selectAction() async {
    if (!widget.action.isEnabled) {
      return;
    }
    if (_contextMenuActionHasSubmenu(widget.action)) {
      _openChildSubmenu();
      return;
    }
    _removeContextSubmenu();
    Navigator.pop(widget.rootMenuContext);
    if (widget.action.onSelected != null && widget.actionContext.mounted) {
      await widget.action.onSelected!(widget.actionContext);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSubmenu = _contextMenuActionHasSubmenu(widget.action);
    return MouseRegion(
      key: _itemKey,
      onEnter: (_) {
        _cancelContextSubmenuRemoval();
        if (hasSubmenu) {
          _openChildSubmenu();
        } else {
          _removeContextSubmenusFrom(_childDepth);
        }
      },
      child: InkWell(
        key: ValueKey<String>(
          'context-menu-action-tap-${widget.action.id}',
        ),
        onTap: widget.action.isEnabled ? _selectAction : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          child: _buildContextMenuActionRow(
            widget.actionContext,
            widget.action,
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
      key: ValueKey<String>('context-menu-action-tap-${action.id}'),
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
  final Future<void> Function(BuildContext, File)? onDeleteFile;
  final bool showOpenFileLocation;

  const SharedFileContextMenu({
    Key? key,
    required this.file,
    required this.fileTags,
    required this.isVideo,
    required this.isImage,
    this.folderListBloc,
    this.actionContext,
    this.showAddTagToFileDialog,
    this.onDeleteFile,
    this.showOpenFileLocation = false,
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
        onDeleteFile: onDeleteFile,
        showOpenFileLocation: showOpenFileLocation,
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
  Future<void> Function(BuildContext, File)? onDeleteFile,
  bool showOpenFileLocation = false,
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
  final isArchive = FileTypeUtils.isArchiveFile(file.path);
  final isTextOrPdf =
      FileTypeUtils.isTextFile(file.path) || FileTypeUtils.isPdfFile(file.path);

  return [
    if (isArchive)
      ContextMenuSection(
        title: l10n.archiveSectionTitle,
        actions: [
          ContextMenuAction(
            id: 'browse_archive',
            label: l10n.archiveBrowseTitle,
            icon: PhosphorIconsLight.archive,
            onSelected: (_) => ArchiveNavigation.openBrowse(
              context,
              archiveFilePath: file.path,
              folderListBloc: folderListBloc,
            ),
          ),
          ContextMenuAction(
            id: 'extract_here',
            label: l10n.archiveExtractHere,
            icon: PhosphorIconsLight.package,
            onSelected: (_) => ArchiveOperationsHandler.extractHere(
              context: context,
              archiveFile: file,
              folderListBloc: folderListBloc,
            ),
          ),
          ContextMenuAction(
            id: 'extract_to',
            label: l10n.archiveExtractTo,
            icon: PhosphorIconsLight.folderOpen,
            onSelected: (_) => ArchiveOperationsHandler.extractToDirectory(
              context: context,
              archiveFile: file,
              folderListBloc: folderListBloc,
            ),
          ),
        ],
      ),
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
          onSelected: (_) {
            if (isTextOrPdf) {
              InAppFileViewer.open(context, file);
            } else {
              ExternalAppHelper.openFileWithApp(file.path, 'shell_open');
            }
          },
        ),
        if (showOpenFileLocation && isDesktopPlatform)
          ContextMenuAction(
            id: 'open_file_location',
            label: 'Open file location',
            icon: PhosphorIconsLight.folderOpen,
            onSelected: (_) => EntityOpenActions.openInNewTab(
              context,
              sourcePath: file.path,
              preferredTabName: pathlib.basename(file.parent.path),
              openContainingFolder: true,
            ),
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
          onSelected: (_) => RouteUtils.showAcrylicDialog(
            context: context,
            builder: (_) => OpenWithDialog(filePath: file.path),
          ),
        ),
        ContextMenuAction(
          id: 'choose_default_app',
          label: l10n.chooseDefaultApp,
          icon: PhosphorIconsLight.appWindow,
          onSelected: (_) => RouteUtils.showAcrylicDialog(
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
          onSelected: (actionContext) async {
            if (onDeleteFile != null) {
              await onDeleteFile(actionContext, file);
              return;
            }
            final isDir = FileSystemEntity.isDirectorySync(file.path);
            SelectionBloc? selBloc;
            try {
              selBloc = actionContext.read<SelectionBloc>();
            } catch (_) {
              selBloc = null;
            }
            final targetFolderListBloc =
                folderListBloc ?? _maybeFolderListBloc(actionContext);
            if (targetFolderListBloc == null) {
              return;
            }
            FileOperationsHandler.handleDelete(
              context: actionContext,
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
  Future<void> Function(BuildContext, File)? onDeleteFile,
  bool showOpenFileLocation = false,
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
            onDeleteFile: onDeleteFile,
            showOpenFileLocation: showOpenFileLocation,
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
    onDeleteFile: onDeleteFile,
    showOpenFileLocation: showOpenFileLocation,
    remotePath: remotePath,
    remoteFileName: remoteFileName,
    globalPosition: effectivePosition,
  );
  unawaited(() async {
    await _showAppContextMenu(
      context: context,
      sections: sections,
      paths: [file.path],
      globalPosition: effectivePosition,
      layoutTarget: ContextMenuLayoutTarget.file,
    );
  }());
}

Future<void> _downloadRemoteFile({
  required BuildContext context,
  required File file,
  String? remoteFileName,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final toast = AppToast.capture(context);
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
    toast.success(l10n.downloadedTo(saveLocation));
  } catch (error) {
    toast.error(l10n.downloadFailed(error.toString()));
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
  final l10n = AppLocalizations.of(context)!;
  final toast = AppToast.capture(context);
  final prefs = UserPreferences.instance;
  await prefs.init();

  final isPinned = await prefs.isPathPinnedToSidebar(path);
  if (isPinned) {
    await prefs.removeSidebarPinnedPath(path);
  } else {
    await prefs.addSidebarPinnedPath(path);
  }

  final message = isPinned ? l10n.removedFromSidebar : l10n.pinnedToSidebar;
  toast.info(message);
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
    anchorRect: cbAnchorRectOf(context),
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
      viewMode == ViewMode.details ||
      viewMode == ViewMode.columns ||
      viewMode == ViewMode.tiles;
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
  await VideoPlaybackLauncher.open(navigator.context, file: file);
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
    final sections = _buildFolderContextMenuSections(
      context: context,
      folderListBloc: folderListBloc,
      folder: folder,
      onNavigate: onNavigate,
      folderTags: folderTags,
      showAddTagToFileDialog: showAddTagToFileDialog,
      globalPosition: effectivePosition,
      isPinnedToSidebar: isPinnedToSidebar,
    );
    await _showAppContextMenu(
      context: context,
      sections: sections,
      paths: [folder.path],
      globalPosition: effectivePosition,
      layoutTarget: ContextMenuLayoutTarget.folder,
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
  final toast = AppToast.capture(context);
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
                          toast.warning(l10n.invalidThumbnailFile);
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
                        toast.success(l10n.folderThumbnailSet);
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
                        toast.success(l10n.folderThumbnailCleared);
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
    toast.error(l10n.errorGettingFolderProperties(error.toString()));
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
  Future<void> Function(BuildContext, List<String>)? onDeleteFiles,
}) {
  final screenSize = MediaQuery.of(context).size;
  final effectivePosition =
      globalPosition ?? Offset(screenSize.width / 2, screenSize.height / 2);
  final sections = _buildMultiSelectionContextMenuSections(
    context: context,
    folderListBloc: _maybeFolderListBloc(context),
    selectedPaths: selectedPaths,
    onClearSelection: onClearSelection,
    onDeleteFiles: onDeleteFiles,
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

  unawaited(() async {
    await _showAppContextMenu(
      context: context,
      sections: sections,
      paths: selectedPaths,
      globalPosition: effectivePosition,
      layoutTarget: ContextMenuLayoutTarget.multiSelection,
    );
  }());
}

List<ContextMenuSection> _buildMultiSelectionContextMenuSections({
  required BuildContext context,
  FolderListBloc? folderListBloc,
  required List<String> selectedPaths,
  required VoidCallback onClearSelection,
  Future<void> Function(BuildContext, List<String>)? onDeleteFiles,
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
            AppToast.info(
              context,
              l10n.copiedToClipboard(l10n.itemsCount(count)),
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
            AppToast.info(
              context,
              l10n.cutToClipboard(l10n.itemsCount(count)),
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
          isEnabled: onDeleteFiles != null || bloc != null,
          onSelected: (actionContext) async {
            if (onDeleteFiles != null) {
              await onDeleteFiles(actionContext, selectedPaths);
              return;
            }
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
