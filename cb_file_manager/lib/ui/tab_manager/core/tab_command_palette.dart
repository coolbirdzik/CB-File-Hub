import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/translation_helper.dart';
import '../../../core/service_locator.dart';
import '../../../helpers/core/user_preferences.dart';
import '../../../providers/theme_provider.dart';
import '../../components/command_palette/command_palette.dart';
import '../../components/keyboard_shortcuts/key_caps.dart';
import '../../components/keyboard_shortcuts/keyboard_shortcuts_view.dart';
import '../../screens/settings/settings_navigation.dart';
import '../../../design_system/cb_page_transitions.dart';
import '../../../helpers/core/text_utils.dart';
import '../../screens/media_gallery/image_viewer_screen.dart';
import '../../utils/entity_open_actions.dart';
import '../../utils/video_playback_launcher.dart';
import '../../utils/file_type_utils.dart';
import 'tab_data.dart';
import 'tab_manager.dart';
import 'tab_paths.dart';

/// Opens the command palette for the tab shell (Ctrl+K).
///
/// The tab-level commands come from the caller so they run through the same
/// handlers as their own shortcuts (Ctrl+T, Ctrl+W, …). Everything else —
/// open tabs, places, pinned and recent folders, "go to path" — is gathered
/// here from [TabManagerBloc] and [UserPreferences].
Future<void> showTabCommandPalette(
  BuildContext context, {
  required VoidCallback onNewTab,
  required VoidCallback onCloseTab,
  VoidCallback? onNewWindow,
  VoidCallback? onToggleSplitView,
}) {
  final l10n = context.tr;
  final tabBloc = context.read<TabManagerBloc>();
  final state = tabBloc.state;

  void openSpecial(String path, String name) {
    final existing = tabBloc.state.tabs.where((tab) => tab.path == path);
    if (existing.isNotEmpty) {
      tabBloc.add(SwitchToTab(existing.first.id));
    } else {
      tabBloc.add(AddTab(path: path, name: name, switchToTab: true));
    }
  }

  void openFolder(String path, {String? highlightedFileName}) {
    final existing = tabBloc.state.tabs.where(
      (tab) => p.equals(tab.path, path),
    );
    if (existing.isNotEmpty && highlightedFileName == null) {
      tabBloc.add(SwitchToTab(existing.first.id));
      return;
    }
    tabBloc.add(
      AddTab(
        path: path,
        name: _folderName(path),
        switchToTab: true,
        highlightedFileName: highlightedFileName,
      ),
    );
  }

  final items = <CommandPaletteItem>[
    for (final TabData tab in state.tabs)
      CommandPaletteItem(
        id: 'tab:${tab.id}',
        title: tab.name,
        subtitle: tab.path.startsWith('#') ? null : tab.path,
        icon: tab.icon ?? _iconForPath(tab.path),
        section: CommandPaletteSection.tabs,
        accessory: tab.id == state.activeTabId
            ? '•'
            : l10n.commandPaletteTabLabel,
        onRun: () => tabBloc.add(SwitchToTab(tab.id)),
      ),
    for (final place in _places(context))
      CommandPaletteItem(
        id: 'place:${place.path}',
        title: place.title,
        icon: place.icon,
        section: CommandPaletteSection.places,
        keywords: [place.path.replaceAll('#', '')],
        onRun: place.path == kSettingsPath
            ? () {
                if (context.mounted) openSettings(context);
              }
            : () => openSpecial(place.path, place.title),
      ),
    CommandPaletteItem(
      id: 'cmd:new-tab',
      title: l10n.newTab,
      icon: PhosphorIconsLight.plus,
      section: CommandPaletteSection.commands,
      shortcut: KeyCaps.chord('T'),
      onRun: onNewTab,
    ),
    if (onNewWindow != null)
      CommandPaletteItem(
        id: 'cmd:new-window',
        title: l10n.newWindow,
        icon: PhosphorIconsLight.appWindow,
        section: CommandPaletteSection.commands,
        shortcut: KeyCaps.chord('N', shift: true),
        onRun: onNewWindow,
      ),
    if (state.tabs.isNotEmpty)
      CommandPaletteItem(
        id: 'cmd:close-tab',
        title: l10n.closeTab,
        icon: PhosphorIconsLight.x,
        section: CommandPaletteSection.commands,
        shortcut: KeyCaps.chord('W'),
        onRun: onCloseTab,
      ),
    if (onToggleSplitView != null)
      CommandPaletteItem(
        id: 'cmd:split-view',
        title: l10n.commandPaletteToggleSplit,
        icon: PhosphorIconsLight.columns,
        section: CommandPaletteSection.commands,
        shortcut: KeyCaps.chord('\\'),
        onRun: onToggleSplitView,
      ),
    CommandPaletteItem(
      id: 'cmd:shortcuts',
      title: l10n.shortcutsTitle,
      icon: PhosphorIconsLight.keyboard,
      section: CommandPaletteSection.commands,
      keywords: ['keyboard', 'hotkey', 'shortcut'],
      onRun: () {
        if (context.mounted) unawaited(showKeyboardShortcutsDialog(context));
      },
    ),
    CommandPaletteItem(
      id: 'cmd:toggle-theme',
      title: l10n.commandPaletteToggleTheme,
      icon: PhosphorIconsLight.circleHalf,
      section: CommandPaletteSection.commands,
      keywords: [l10n.darkMode, l10n.lightMode, 'theme'],
      onRun: () => locator<ThemeProvider>().toggleTheme(),
    ),
  ];

  final activeTab = state.activeTab;
  final activePath = activeTab?.path;

  // A sub-folder of the current folder opens in place, like a double-click.
  void enterFolder(String path) {
    if (activeTab == null) return openFolder(path);
    tabBloc
      ..add(UpdateTabPath(activeTab.id, path))
      ..add(UpdateTabName(activeTab.id, _folderName(path)));
  }

  // Files open the way a double-click does: images in the app's viewer (with
  // the folder's other images to page through), videos in the app's player,
  // anything else through the shared open action. They are pushed on the
  // active tab's navigator so the viewer stays inside the tab.
  void openFile(String path, List<String> folderImages) {
    final navigator = activeTab?.navigatorKey.currentState;
    final BuildContext hostContext = navigator?.context ?? context;
    if (!hostContext.mounted) return;
    if (FileTypeUtils.isImageFile(path)) {
      final images = [for (final image in folderImages) File(image)];
      final index = folderImages.indexOf(path);
      (navigator ?? Navigator.of(hostContext)).push(
        CbFullBleedPageRoute<void>(
          builder: (_) => ImageViewerScreen(
            file: File(path),
            imageFiles: images.isEmpty ? null : images,
            initialIndex: index < 0 ? 0 : index,
          ),
        ),
      );
    } else if (FileTypeUtils.isVideoFile(path)) {
      unawaited(VideoPlaybackLauncher.open(hostContext, file: File(path)));
    } else {
      EntityOpenActions.openInNewTab(hostContext, sourcePath: path);
    }
  }

  return showCommandPalette(
    context: context,
    items: items,
    deferredItems: _folderItems(l10n.commandPaletteFolderLabel, openFolder)
        .then(
          (folders) async => [
            ...folders,
            if (activePath != null && !activePath.startsWith('#'))
              ...await _currentFolderItems(
                activePath,
                folderLabel: l10n.folder,
                fileLabel: l10n.file,
                openFolder: enterFolder,
                openFile: openFile,
              ),
          ],
        ),
    itemsForQuery: (query) => _goToPathItems(
      query,
      title: l10n.commandPaletteOpenPath,
      openFolder: openFolder,
    ),
  );
}

class _Place {
  final String path;
  final String title;
  final IconData icon;

  const _Place(this.path, this.title, this.icon);
}

List<_Place> _places(BuildContext context) {
  final l10n = context.tr;
  return [
    _Place('#home', l10n.home, PhosphorIconsLight.house),
    _Place(kDrivesPath, l10n.drivesTab, PhosphorIconsLight.hardDrives),
    _Place('#gallery', l10n.imageGallery, PhosphorIconsLight.image),
    _Place('#video', l10n.videoGallery, PhosphorIconsLight.videoCamera),
    _Place('#tags', l10n.tags, PhosphorIconsLight.tag),
    _Place('#network', l10n.networksMenu, PhosphorIconsLight.wifiHigh),
    _Place('#ssh', l10n.sshWorkspace, PhosphorIconsLight.terminalWindow),
    _Place('#torrents', l10n.torrents, PhosphorIconsLight.downloadSimple),
    _Place(kAiChatPath, l10n.cbAgent, PhosphorIconsLight.sparkle),
    _Place(
      kCbAgentCleanerPath,
      l10n.cbAgentCleanerTitle,
      PhosphorIconsLight.broom,
    ),
    _Place('#trash', l10n.trashBin, PhosphorIconsLight.trash),
    _Place(kSettingsPath, l10n.settings, PhosphorIconsLight.gear),
  ];
}

/// Pinned and recent folders, read from disk after the palette has opened.
/// Unavailable folders are left out by the preference readers themselves.
Future<List<CommandPaletteItem>> _folderItems(
  String folderLabel,
  void Function(String path) openFolder,
) async {
  final prefs = UserPreferences.instance;
  final results = await Future.wait([
    prefs.getSidebarPinnedPaths(),
    prefs.getRecentPaths(limit: 8),
  ]);
  CommandPaletteItem folder(String path, CommandPaletteSection section) =>
      CommandPaletteItem(
        id: '${section.name}:$path',
        title: _folderName(path),
        subtitle: path,
        icon: PhosphorIconsLight.folder,
        section: section,
        accessory: folderLabel,
        onRun: () => openFolder(path),
      );
  final pinned = results[0];
  return [
    for (final path in pinned) folder(path, CommandPaletteSection.pinned),
    for (final path in results[1])
      if (!pinned.contains(path)) folder(path, CommandPaletteSection.recent),
  ];
}

/// Most entries read from the active tab's folder. Enough for any folder a
/// person browses by hand, bounded so a huge directory cannot stall the
/// palette.
const int _kCurrentFolderEntryLimit = 2000;

/// Entries of the active tab's folder, searchable from the palette (shown
/// only once the user types). Read asynchronously after the palette opens;
/// an unreadable folder contributes nothing.
Future<List<CommandPaletteItem>> _currentFolderItems(
  String folder, {
  required String folderLabel,
  required String fileLabel,
  required void Function(String path) openFolder,
  required void Function(String path, List<String> folderImages) openFile,
}) async {
  final entities = <FileSystemEntity>[];
  try {
    await for (final entity in Directory(
      folder,
    ).list(followLinks: false).take(_kCurrentFolderEntryLimit)) {
      if (p.basename(entity.path).isNotEmpty) entities.add(entity);
    }
  } on FileSystemException {
    // Permission denied or the folder vanished: no rows.
    return const [];
  }
  final images = [
    for (final entity in entities)
      if (entity is File && FileTypeUtils.isImageFile(entity.path)) entity.path,
  ]..sort((a, b) => TextUtils.compareNatural(p.basename(a), p.basename(b)));
  return [
    for (final entity in entities)
      CommandPaletteItem(
        id: 'entry:${entity.path}',
        title: p.basename(entity.path),
        icon: entity is Directory
            ? PhosphorIconsLight.folder
            : _iconForFile(entity.path),
        section: CommandPaletteSection.currentFolder,
        accessory: entity is Directory ? folderLabel : fileLabel,
        onlyWhenSearching: true,
        onRun: entity is Directory
            ? () => openFolder(entity.path)
            : () => openFile(entity.path, images),
      ),
  ];
}

IconData _iconForFile(String path) {
  if (FileTypeUtils.isImageFile(path)) return PhosphorIconsLight.image;
  if (FileTypeUtils.isVideoFile(path)) return PhosphorIconsLight.filmStrip;
  if (FileTypeUtils.isAudioFile(path)) return PhosphorIconsLight.musicNote;
  if (FileTypeUtils.isArchiveFile(path)) return PhosphorIconsLight.fileZip;
  if (FileTypeUtils.isPdfFile(path)) return PhosphorIconsLight.filePdf;
  if (FileTypeUtils.isTextFile(path)) return PhosphorIconsLight.fileText;
  return PhosphorIconsLight.file;
}

/// A "go to" row whenever the query looks like a path.
///
/// Built on every keystroke, so it never touches the disk: a synchronous
/// stat of `\\nas\share` or a disconnected mapped drive can block the UI
/// thread for seconds. The path is resolved asynchronously only when the row
/// is run — a file opens its folder with the file highlighted, anything else
/// opens as a folder (and a missing one shows the tab's own error state).
List<CommandPaletteItem> _goToPathItems(
  String query, {
  required String title,
  required void Function(String path, {String? highlightedFileName}) openFolder,
}) {
  final String raw = query.trim();
  if (!_looksLikePath(raw)) return const [];
  String path = raw;
  if (path.startsWith('~')) {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
    if (home == null) return const [];
    path = p.join(home, path.substring(1).replaceFirst(RegExp(r'^[\\/]'), ''));
  }
  return [
    CommandPaletteItem(
      id: 'goto:$path',
      title: path,
      subtitle: title,
      icon: PhosphorIconsLight.arrowSquareOut,
      section: CommandPaletteSection.goTo,
      keywords: [raw],
      onRun: () async {
        FileSystemEntityType type;
        try {
          type = await FileSystemEntity.type(path);
        } on FileSystemException {
          type = FileSystemEntityType.notFound;
        }
        if (type == FileSystemEntityType.file) {
          openFolder(p.dirname(path), highlightedFileName: p.basename(path));
        } else {
          openFolder(path);
        }
      },
    ),
  ];
}

bool _looksLikePath(String value) {
  if (value.isEmpty) return false;
  return value.startsWith('/') ||
      value.startsWith(r'\\') ||
      value.startsWith('~') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value);
}

String _folderName(String path) {
  final name = p.basename(path);
  return name.isEmpty ? path : name;
}

IconData _iconForPath(String path) {
  if (path == '#home') return PhosphorIconsLight.house;
  if (path == kSettingsPath) return PhosphorIconsLight.gear;
  if (path.startsWith('#')) return PhosphorIconsLight.squaresFour;
  return PhosphorIconsLight.folder;
}
