import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/tab_manager/shared/screen_menu_registry.dart'
    as shared_registry;

/// Menu item cho dynamic menu system
class ScreenMenuItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDivider;

  const ScreenMenuItem({
    required this.title,
    required this.icon,
    required this.onTap,
    this.isDivider = false,
  });

  /// Tạo divider item
  const ScreenMenuItem.divider()
      : title = '',
        icon = PhosphorIconsLight.minus,
        onTap = _emptyCallback,
        isDivider = true;

  static void _emptyCallback() {}
}

/// Registry để quản lý dynamic menu cho các màn hình khác nhau
class ScreenMenuRegistry {
  static final Map<String, List<ScreenMenuItem>> _menuRegistry = {};
  static bool _initialized = false;

  /// Khởi tạo tất cả menu cho các màn hình
  static void initializeMenus(BuildContext context) {
    if (_initialized) return;

    _initializeTagManagementMenu(context);
    _initializeFileBrowserMenu(context);
    _initializeSettingsMenu(context);
    _initializeNetworkMenu(context);

    _initialized = true;
  }

  /// Khởi tạo menu cho tag management screen
  static void _initializeTagManagementMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _menuRegistry['#tags'] = [
      const ScreenMenuItem.divider(),
      ScreenMenuItem(
        title: l10n.createNewTag,
        icon: PhosphorIconsLight.plus,
        onTap: () => _TagManagementHelper.showCreateTagDialog(context),
      ),
      ScreenMenuItem(
        title: l10n.searchTags,
        icon: PhosphorIconsLight.magnifyingGlass,
        onTap: () => _TagManagementHelper.showTagSearchDialog(context),
      ),
      ScreenMenuItem(
        title: l10n.tagManagementInfoTitle,
        icon: PhosphorIconsLight.info,
        onTap: () => _TagManagementHelper.showTagManagementInfo(context),
      ),
      ScreenMenuItem(
        title: l10n.tagListRefreshing,
        icon: PhosphorIconsLight.arrowsClockwise,
        onTap: () => _TagManagementHelper.refreshTagManagement(context),
      ),
      ScreenMenuItem(
        title: l10n.sortTags,
        icon: PhosphorIconsLight.gear,
        onTap: () => _TagManagementHelper.showTagSortOptions(context),
      ),
      ScreenMenuItem(
        title: l10n.gridViewMode,
        icon: PhosphorIconsLight.squaresFour,
        onTap: () => _TagManagementHelper.toggleViewMode(context),
      ),
      ScreenMenuItem(
        title: l10n.listViewMode,
        icon: PhosphorIconsLight.listBullets,
        onTap: () => _TagManagementHelper.toggleViewMode(context),
      ),
    ];
  }

  /// Khởi tạo menu cho file browser screen
  static void _initializeFileBrowserMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _menuRegistry['#filebrowser'] = [
      const ScreenMenuItem.divider(),
      ScreenMenuItem(
        title: l10n.newFolder,
        icon: PhosphorIconsLight.folderPlus,
        onTap: () => _FileBrowserHelper.createNewFolder(context),
      ),
      ScreenMenuItem(
        title: l10n.createNewFile,
        icon: PhosphorIconsLight.filePlus,
        onTap: () => _FileBrowserHelper.createNewFile(context),
      ),
      ScreenMenuItem(
        title: l10n.pasteHere,
        icon: PhosphorIconsLight.copy,
        onTap: () => _FileBrowserHelper.pasteFiles(context),
      ),
      ScreenMenuItem(
        title: l10n.sort,
        icon: PhosphorIconsLight.gear,
        onTap: () => _FileBrowserHelper.showSortOptions(context),
      ),
      ScreenMenuItem(
        title: l10n.viewMode,
        icon: PhosphorIconsLight.squaresFour,
        onTap: () => _FileBrowserHelper.toggleViewMode(context),
      ),
    ];
  }

  /// Khởi tạo menu cho settings screen
  static void _initializeSettingsMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _menuRegistry['#settings'] = [
      const ScreenMenuItem.divider(),
      ScreenMenuItem(
        title: l10n.exportSettings,
        icon: PhosphorIconsLight.downloadSimple,
        onTap: () => _SettingsHelper.exportSettings(context),
      ),
      ScreenMenuItem(
        title: l10n.importSettings,
        icon: PhosphorIconsLight.uploadSimple,
        onTap: () => _SettingsHelper.importSettings(context),
      ),
      ScreenMenuItem(
        title: l10n.resetSettings,
        icon: PhosphorIconsLight.arrowsClockwise,
        onTap: () => _SettingsHelper.resetSettings(context),
      ),
    ];
  }

  /// Khởi tạo menu cho network screen
  static void _initializeNetworkMenu(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    _menuRegistry['#network'] = [
      const ScreenMenuItem.divider(),
      ScreenMenuItem(
        title: l10n.addConnection,
        icon: PhosphorIconsLight.plus,
        onTap: () => _NetworkHelper.addNewConnection(context),
      ),
      ScreenMenuItem(
        title: l10n.startScan,
        icon: PhosphorIconsLight.magnifyingGlass,
        onTap: () => _NetworkHelper.scanNetwork(context),
      ),
      ScreenMenuItem(
        title: l10n.refresh,
        icon: PhosphorIconsLight.arrowsClockwise,
        onTap: () => _NetworkHelper.refreshConnections(context),
      ),
    ];
  }

  /// Lấy menu items cho một path cụ thể
  static List<ScreenMenuItem>? getMenuForPath(String path) {
    return _menuRegistry[path];
  }

  /// Đăng ký menu cho một path mới
  static void registerMenu(String path, List<ScreenMenuItem> menuItems) {
    _menuRegistry[path] = menuItems;
  }

  /// Xóa menu cho một path
  static void unregisterMenu(String path) {
    _menuRegistry.remove(path);
  }

  /// Lấy tất cả các path đã đăng ký
  static List<String> getRegisteredPaths() {
    return _menuRegistry.keys.toList();
  }

  /// Reset tất cả menu (dùng cho testing)
  static void reset() {
    _menuRegistry.clear();
    _initialized = false;
  }
}

/// Helper class cho Tag Management menu
class _TagManagementHelper {
  static void showCreateTagDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final TextEditingController tagController = TextEditingController();

    RouteUtils.showAcrylicDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.newTagTitle),
        content: TextField(
          controller: tagController,
          decoration: InputDecoration(
            hintText: l10n.enterTagName,
            prefixIcon: const Icon(PhosphorIconsLight.tag),
          ),
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context);
              _createNewTagInDatabase(context, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              final tagName = tagController.text.trim();
              if (tagName.isNotEmpty) {
                Navigator.pop(context);
                _createNewTagInDatabase(context, tagName);
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    );
  }

  static Future<void> _createNewTagInDatabase(
      BuildContext context, String tagName) async {
    final l10n = AppLocalizations.of(context)!;
    final toast = AppToast.capture(context);
    try {
      await TagManager.initialize();
      final created = await TagManager.addStandaloneTag(tagName);

      if (!created) {
        toast.error(l10n.errorCreatingTag);
        return;
      }

      toast.success(l10n.tagCreatedSuccessfully(tagName));
    } catch (e) {
      toast.error(l10n.errorCreatingTag + e.toString());
    }
  }

  static void showTagSearchDialog(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.searchTags),
        content: TextField(
          decoration: InputDecoration(
            hintText: l10n.searchTagsHint,
            prefixIcon: const Icon(PhosphorIconsLight.magnifyingGlass),
          ),
          autofocus: true,
          onSubmitted: (value) {
            final toast = AppToast.capture(context);
            Navigator.pop(context);
            toast.info(l10n.searchingFor(value));
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  static void showTagManagementInfo(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.tagManagementInfoTitle),
        content: Text(l10n.tagManagementInfoDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  static void refreshTagManagement(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.tagListRefreshing);
  }

  static void showTagSortOptions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    RouteUtils.showAcrylicDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.sortTags),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(l10n.sortByAlphabet),
              leading: const Icon(PhosphorIconsLight.sortAscending),
              onTap: () {
                final toast = AppToast.capture(context);
                Navigator.pop(context);
                toast.info(l10n.sortByName);
              },
            ),
            ListTile(
              title: Text(l10n.sortByPopular),
              leading: const Icon(PhosphorIconsLight.trendUp),
              onTap: () {
                final toast = AppToast.capture(context);
                Navigator.pop(context);
                toast.info(l10n.sortByPopularity);
              },
            ),
            ListTile(
              title: Text(l10n.sortByRecent),
              leading: const Icon(PhosphorIconsLight.clockCounterClockwise),
              onTap: () {
                final toast = AppToast.capture(context);
                Navigator.pop(context);
                toast.info(l10n.sortByRecent);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  static void toggleViewMode(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.viewModeFeatureComingSoon);
  }
}

/// Helper class cho File Browser menu
class _FileBrowserHelper {
  static void createNewFolder(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.createNewFolder);
  }

  static Future<void> createNewFile(BuildContext context) async {
    await shared_registry.FileBrowserHelper.createNewFileWithRename(context);
  }

  static void pasteFiles(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.pasteHere);
  }

  static void showSortOptions(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.sort);
  }

  static void toggleViewMode(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.viewMode);
  }
}

/// Helper class cho Settings menu
class _SettingsHelper {
  static void exportSettings(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.exportSettings);
  }

  static void importSettings(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.importSettings);
  }

  static void resetSettings(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.resetSettings);
  }
}

/// Helper class cho Network menu
class _NetworkHelper {
  static void addNewConnection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.addConnection);
  }

  static void scanNetwork(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.startScan);
  }

  static void refreshConnections(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    AppToast.info(context, l10n.refresh);
  }
}
