import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';

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
    _menuRegistry['#tags'] = [
      const ScreenMenuItem.divider(),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.createNewTag,
        icon: PhosphorIconsLight.plus,
        onTap: () => _TagManagementHelper.showCreateTagDialog(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.searchTags,
        icon: PhosphorIconsLight.magnifyingGlass,
        onTap: () => _TagManagementHelper.showTagSearchDialog(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.tagManagementTitle,
        icon: PhosphorIconsLight.info,
        onTap: () => _TagManagementHelper.showTagManagementInfo(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.tagListRefreshing,
        icon: PhosphorIconsLight.arrowsClockwise,
        onTap: () => _TagManagementHelper.refreshTagManagement(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.sortTags,
        icon: PhosphorIconsLight.gear,
        onTap: () => _TagManagementHelper.showTagSortOptions(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.gridViewMode,
        icon: PhosphorIconsLight.squaresFour,
        onTap: () => _TagManagementHelper.toggleViewMode(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.listViewMode,
        icon: PhosphorIconsLight.listBullets,
        onTap: () => _TagManagementHelper.toggleViewMode(context),
      ),
    ];
  }

  /// Khởi tạo menu cho file browser screen
  static void _initializeFileBrowserMenu(BuildContext context) {
    _menuRegistry['#filebrowser'] = [
      const ScreenMenuItem.divider(),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.newFolder,
        icon: PhosphorIconsLight.folderPlus,
        onTap: () => _FileBrowserHelper.createNewFolder(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.create,
        icon: PhosphorIconsLight.filePlus,
        onTap: () => _FileBrowserHelper.createNewFile(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.pasteHere,
        icon: PhosphorIconsLight.copy,
        onTap: () => _FileBrowserHelper.pasteFiles(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.sort,
        icon: PhosphorIconsLight.gear,
        onTap: () => _FileBrowserHelper.showSortOptions(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.featureNotImplemented,
        icon: PhosphorIconsLight.squaresFour,
        onTap: () => _FileBrowserHelper.toggleViewMode(context),
      ),
    ];
  }

  /// Khởi tạo menu cho settings screen
  static void _initializeSettingsMenu(BuildContext context) {
    _menuRegistry['#settings'] = [
      const ScreenMenuItem.divider(),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.exportSettings,
        icon: PhosphorIconsLight.downloadSimple,
        onTap: () => _SettingsHelper.exportSettings(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.importSettings,
        icon: PhosphorIconsLight.uploadSimple,
        onTap: () => _SettingsHelper.importSettings(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.resetSettings,
        icon: PhosphorIconsLight.arrowsClockwise,
        onTap: () => _SettingsHelper.resetSettings(context),
      ),
    ];
  }

  /// Khởi tạo menu cho network screen
  static void _initializeNetworkMenu(BuildContext context) {
    _menuRegistry['#network'] = [
      const ScreenMenuItem.divider(),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.addConnection,
        icon: PhosphorIconsLight.plus,
        onTap: () => _NetworkHelper.addNewConnection(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.startScan,
        icon: PhosphorIconsLight.magnifyingGlass,
        onTap: () => _NetworkHelper.scanNetwork(context),
      ),
      ScreenMenuItem(
        title: AppLocalizations.of(context)!.refresh,
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
    final TextEditingController tagController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Tạo thẻ mới'),
        content: TextField(
          controller: tagController,
          decoration: const InputDecoration(
            hintText: 'Nhập tên thẻ...',
            prefixIcon: Icon(PhosphorIconsLight.tag),
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
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              final tagName = tagController.text.trim();
              if (tagName.isNotEmpty) {
                Navigator.pop(context);
                _createNewTagInDatabase(context, tagName);
              }
            },
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  static Future<void> _createNewTagInDatabase(
      BuildContext context, String tagName) async {
    try {
      await TagManager.initialize();
      final created = await TagManager.addStandaloneTag(tagName);

      if (!created) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.errorCreatingTag),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context)!.tagCreatedSuccessfully(tagName)),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                AppLocalizations.of(context)!.errorCreatingTag + e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  static void showTagSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tìm kiếm thẻ'),
        content: TextField(
          decoration: const InputDecoration(
            hintText: 'Nhập tên thẻ...',
            prefixIcon: Icon(PhosphorIconsLight.magnifyingGlass),
          ),
          autofocus: true,
          onSubmitted: (value) {
            Navigator.pop(dialogContext);
            if (dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                    content: Text(AppLocalizations.of(dialogContext)!
                        .searchingFor(value))),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
  }

  static void showTagManagementInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thông tin quản lý thẻ'),
        content: const Text(
          'Màn hình này cho phép bạn quản lý các thẻ (tags) của file và thư mục.\n\n'
          '• Xem danh sách tất cả thẻ\n'
          '• Tìm kiếm thẻ\n'
          '• Sắp xếp thẻ theo tên, độ phổ biến\n'
          '• Xem file được gắn thẻ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  static void refreshTagManagement(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.tagListRefreshing),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  static void showTagSortOptions(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sắp xếp thẻ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Theo tên (A-Z)'),
              leading: const Icon(PhosphorIconsLight.sortAscending),
              onTap: () {
                Navigator.pop(dialogContext);
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Sắp xếp theo tên A-Z')),
                  );
                }
              },
            ),
            ListTile(
              title: const Text('Theo độ phổ biến'),
              leading: const Icon(PhosphorIconsLight.trendUp),
              onTap: () {
                Navigator.pop(dialogContext);
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(content: Text('Sắp xếp theo độ phổ biến')),
                  );
                }
              },
            ),
            ListTile(
              title: const Text('Theo thời gian gần đây'),
              leading: const Icon(PhosphorIconsLight.clockCounterClockwise),
              onTap: () {
                Navigator.pop(dialogContext);
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                        content: Text('Sắp xếp theo thời gian gần đây')),
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
        ],
      ),
    );
  }

  static void toggleViewMode(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chức năng chuyển chế độ xem sẽ được thêm sau'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// Helper class cho File Browser menu
class _FileBrowserHelper {
  static void createNewFolder(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tạo thư mục mới')),
    );
  }

  static void createNewFile(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tạo file mới')),
    );
  }

  static void pasteFiles(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dán file')),
    );
  }

  static void showSortOptions(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sắp xếp file')),
    );
  }

  static void toggleViewMode(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thay đổi chế độ xem')),
    );
  }
}

/// Helper class cho Settings menu
class _SettingsHelper {
  static void exportSettings(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Xuất cài đặt')),
    );
  }

  static void importSettings(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nhập cài đặt')),
    );
  }

  static void resetSettings(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đặt lại cài đặt')),
    );
  }
}

/// Helper class cho Network menu
class _NetworkHelper {
  static void addNewConnection(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thêm kết nối mới')),
    );
  }

  static void scanNetwork(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Quét mạng')),
    );
  }

  static void refreshConnections(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Làm mới danh sách kết nối')),
    );
  }
}
