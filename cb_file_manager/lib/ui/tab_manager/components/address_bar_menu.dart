import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Menu ba chấm trong thanh địa chỉ với các action dynamic tùy theo màn hình
class AddressBarMenu extends StatelessWidget {
  final List<AddressBarMenuItem> items;
  final String? tooltip;

  const AddressBarMenu({
    Key? key,
    required this.items,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<AddressBarMenuItem>(
      icon: Icon(
        PhosphorIconsLight.dotsThree,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      tooltip: tooltip ?? 'Tùy chọn',
      onSelected: (item) {
        item.onTap();
      },
      itemBuilder: (context) => items.map((item) {
        return PopupMenuItem<AddressBarMenuItem>(
          value: item,
          enabled: item.enabled,
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 18,
                color: item.enabled
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.title,
                  style: TextStyle(
                    color: item.enabled
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                  ),
                ),
              ),
              if (item.badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Text(
                    item.badge!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Model cho một item trong menu
class AddressBarMenuItem {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final String? badge;

  const AddressBarMenuItem({
    required this.title,
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.badge,
  });
}

/// Helper class để tạo các menu item phổ biến
class AddressBarMenuItems {
  /// Tạo menu item cho tìm kiếm
  static AddressBarMenuItem search({
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return AddressBarMenuItem(
      title: 'Tìm kiếm',
      icon: PhosphorIconsLight.magnifyingGlass,
      onTap: onTap,
      enabled: enabled,
    );
  }

  /// Tạo menu item cho sắp xếp
  static AddressBarMenuItem sort({
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return AddressBarMenuItem(
      title: 'Sắp xếp',
      icon: PhosphorIconsLight.gear,
      onTap: onTap,
      enabled: enabled,
    );
  }

  /// Tạo menu item cho refresh
  static AddressBarMenuItem refresh({
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return AddressBarMenuItem(
      title: 'Làm mới',
      icon: PhosphorIconsLight.arrowsClockwise,
      onTap: onTap,
      enabled: enabled,
    );
  }

  /// Tạo menu item cho thông tin
  static AddressBarMenuItem info({
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return AddressBarMenuItem(
      title: 'Thông tin',
      icon: PhosphorIconsLight.info,
      onTap: onTap,
      enabled: enabled,
    );
  }

  /// Tạo menu item cho xóa
  static AddressBarMenuItem delete({
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return AddressBarMenuItem(
      title: 'Xóa',
      icon: PhosphorIconsLight.trash,
      onTap: onTap,
      enabled: enabled,
    );
  }

  /// Tạo menu item cho thay đổi màu
  static AddressBarMenuItem changeColor({
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return AddressBarMenuItem(
      title: 'Thay đổi màu',
      icon: PhosphorIconsLight.palette,
      onTap: onTap,
      enabled: enabled,
    );
  }

  /// Tạo menu item cho mở trong tab mới
  static AddressBarMenuItem openInNewTab({
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return AddressBarMenuItem(
      title: 'Mở trong tab mới',
      icon: PhosphorIconsLight.squaresFour,
      onTap: onTap,
      enabled: enabled,
    );
  }
}
