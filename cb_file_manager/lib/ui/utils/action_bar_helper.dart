import 'package:flutter/material.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Helper class to standardize app bar functionality across the application
class ActionBarHelper {
  /// Creates a standard app bar with the given title
  static AppBar createAppBar({
    required String title,
    required BuildContext context,
    List<Widget>? actions,
    bool automaticallyImplyLeading = true,
    Color? backgroundColor,
    PreferredSizeWidget? bottom,
    double? elevation,
    Widget? flexibleSpace,
  }) {
    return AppBar(
      title: Text(title),
      actions: actions,
      leading: automaticallyImplyLeading ? _buildLeadingIcon(context) : null,
      backgroundColor: backgroundColor,
      bottom: bottom,
      elevation: elevation,
      flexibleSpace: flexibleSpace,
    );
  }

  /// Builds the leading icon (back button or drawer toggle) based on navigation context
  static Widget? _buildLeadingIcon(BuildContext context) {
    final ModalRoute<dynamic>? parentRoute = ModalRoute.of(context);
    final bool canPop = parentRoute?.canPop ?? false;

    if (canPop) {
      return IconButton(
        icon: const Icon(PhosphorIconsLight.arrowLeft),
        onPressed: () => RouteUtils.safeBackNavigation(context),
      );
    } else {
      return IconButton(
        icon: const Icon(PhosphorIconsLight.list),
        onPressed: () => BaseScreen.openDrawer(),
      );
    }
  }

  /// Creates a search action for the app bar
  static IconButton createSearchAction(VoidCallback onPressed) {
    return IconButton(
      icon: const Icon(PhosphorIconsLight.magnifyingGlass),
      tooltip: 'Search',
      onPressed: onPressed,
    );
  }

  /// Creates a settings action for the app bar
  static IconButton createSettingsAction(VoidCallback onPressed) {
    return IconButton(
      icon: const Icon(PhosphorIconsLight.gear),
      tooltip: 'Settings',
      onPressed: onPressed,
    );
  }

  /// Creates a more options menu for the app bar with the provided items
  static PopupMenuButton<String> createMoreOptionsMenu({
    required Map<String, IconData> items,
    required Function(String) onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) {
        return items.entries.map((entry) {
          return PopupMenuItem<String>(
            value: entry.key,
            child: Row(
              children: [
                Icon(entry.value, size: 20),
                const SizedBox(width: 8),
                Text(entry.key),
              ],
            ),
          );
        }).toList();
      },
    );
  }

  /// Creates a title with breadcrumb navigation for folder hierarchy
  static Widget createBreadcrumbTitle(
    BuildContext context,
    List<String> pathSegments,
    Function(int) onSegmentTap,
  ) {
    if (pathSegments.isEmpty) {
      return const Text('Home');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < pathSegments.length; i++) ...[
            if (i > 0) const Text(' / ', style: TextStyle(fontSize: 16)),
            InkWell(
              onTap: () => onSegmentTap(i),
              child: Text(
                pathSegments[i],
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Creates a selection mode app bar for multi-select operations
  static AppBar createSelectionModeAppBar({
    required BuildContext context,
    required int selectedCount,
    required VoidCallback onClose,
    required List<Widget> actions,
  }) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(PhosphorIconsLight.x),
        onPressed: onClose,
      ),
      title: Text('$selectedCount selected'),
      actions: actions,
      backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.85),
    );
  }
}
