import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Thêm import cho SystemUiOverlayStyle
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io'; // Thêm import cho Platform
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../core/tab_manager.dart';
import '../core/tab_data.dart';
import '../core/tab_paths.dart';
import '../core/tab_thumbnail_service.dart';
import '../../screens/home/home_screen.dart';
import '../core/tabbed_folder/tabbed_folder_list_screen.dart';
import '../../screens/network_browsing/network_connection_screen.dart';
import '../../screens/network_browsing/network_browser_screen.dart';
import '../../screens/network_browsing/smb_browser_screen.dart'; // Added import for SMBBrowserScreen
import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import 'package:cb_file_manager/services/network_browsing/network_service_registry.dart';
import 'package:cb_file_manager/ui/state/video_ui_state.dart';
import '../../screens/system_screen_router.dart'; // Import SystemScreenRouter for system paths
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'mobile_file_actions_controller.dart';

/// Giao diện kiểu Chrome cho thiết bị di động, hiển thị thanh địa chỉ ở trên
/// và một nút hiển thị số lượng tab bên cạnh
class MobileTabView extends StatelessWidget {
  /// Callback khi nhấn vào nút thêm tab mới
  final VoidCallback onAddNewTab;

  const MobileTabView({
    Key? key,
    required this.onAddNewTab,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Lấy theme để xác định màu sắc phù hợp (sử dụng brightness và màu nền)
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return BlocBuilder<TabManagerBloc, TabManagerState>(
      builder: (context, state) {
        // Xác định style dựa trên trạng thái tab và theme
        final overlayStyle = isDarkMode
            ? SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.light,
                statusBarBrightness: Brightness.dark,
              )
            : SystemUiOverlayStyle.dark.copyWith(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: Brightness.dark,
                statusBarBrightness: Brightness.light,
              );

        // Sử dụng AnnotatedRegion để áp dụng style cho khu vực này
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: SafeArea(
            child: Column(
              children: [
                // Ẩn thanh địa chỉ khi video fullscreen
                ValueListenableBuilder<bool>(
                  valueListenable: VideoUiState.isFullscreen,
                  builder: (context, isFs, _) {
                    if (isFs) return const SizedBox.shrink();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildEmptyOrNormalChromeBar(context, state),
                        // Add action buttons row for file management (local and network browsing)
                        if (state.tabs.isNotEmpty &&
                            state.activeTab != null &&
                            _shouldShowMobileActionBar(state.activeTab!.path))
                          _buildMobileActionButtons(
                            context,
                            state.activeTab!.id,
                            state.activeTab!.path,
                          ),
                      ],
                    );
                  },
                ),

                // Nội dung chính: hiển thị nội dung tab hoặc màn hình trống
                Expanded(
                  child: state.tabs.isEmpty
                      ? _buildEmptyTabsView(context)
                      : _buildTabContent(context, state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Xây dựng thanh chrome style cho cả trường hợp có tab và không có tab
  Widget _buildEmptyOrNormalChromeBar(
      BuildContext context, TabManagerState state) {
    // Nếu không có tab, hiển thị thanh chrome style đơn giản hơn
    if (state.tabs.isEmpty) {
      return _buildEmptyChromeStyleAddressBar(context);
    }

    // Nếu có tab, sử dụng thanh chrome style bình thường
    return _buildChromeStyleAddressBar(context, state);
  }

  /// Xây dựng thanh chrome style khi không có tab nào
  Widget _buildEmptyChromeStyleAddressBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final backgroundColor = theme.scaffoldBackgroundColor;
    final localizations = AppLocalizations.of(context)!;

    // Lấy state hiện tại để hiển thị nút đếm tab (0)
    final tState = context.read<TabManagerBloc>().state;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
      decoration: BoxDecoration(color: backgroundColor),
      child: Row(
        children: [
          // Nút menu
          IconButton(
            icon: Icon(PhosphorIconsLight.list, color: textColor),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),

          // Thanh địa chỉ dạng placeholder, vẫn có nền rõ ràng
          Expanded(
            child: AddressBarWidget(
              path: '',
              name: localizations.searchOrEnterPath,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(localizations.pleaseCreateTabFirst),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              isDarkMode: isDarkMode,
            ),
          ),

          // Nút tạo tab mới nhanh (đặt trước nút số lượng tab)
          IconButton(
            icon: Icon(PhosphorIconsLight.plus, color: textColor),
            tooltip: localizations.newTab,
            onPressed: onAddNewTab,
          ),

          // Nút số lượng tab
          _buildTabCountButton(context, tState, textColor),
        ],
      ),
    );
  }

  /// Xây dựng thanh địa chỉ và nút tab kiểu Chrome
  Widget _buildChromeStyleAddressBar(
      BuildContext context, TabManagerState state) {
    // Lấy tab đang hoạt động
    final activeTab = state.activeTab;
    if (activeTab == null) return Container();

    // Lấy màu từ theme để đảm bảo đồng bộ với theme của ứng dụng
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Màu nền rõ ràng để dễ nhìn toàn thanh
    final backgroundColor = theme.scaffoldBackgroundColor;
    final textColor = theme.colorScheme.onSurface;
    final localizations = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
      decoration: BoxDecoration(color: backgroundColor),
      child: Row(
        children: [
          // Nút menu để mở drawer
          IconButton(
            icon: Icon(PhosphorIconsLight.list, color: textColor),
            onPressed: () {
              // Mở Scaffold drawer
              Scaffold.of(context).openDrawer();
            },
          ),

          // Thanh địa chỉ
          Expanded(
            child: AddressBarWidget(
              path: activeTab.path,
              name: activeTab.name,
              onTap: () {
                _showPathNavigationDialog(context, activeTab);
              },
              isDarkMode: isDarkMode,
            ),
          ),

          // Nút thêm tab mới nhanh (đặt trước nút số lượng tab)
          IconButton(
            icon: Icon(PhosphorIconsLight.plus, color: textColor),
            tooltip: localizations.newTab,
            onPressed: onAddNewTab,
          ),

          // Nút số lượng tab và menu tab - đã chuyển sang bên phải thanh địa chỉ
          _buildTabCountButton(context, state, textColor),
        ],
      ),
    );
  }

  /// Xây dựng nút hiển thị số lượng tab
  Widget _buildTabCountButton(
      BuildContext context, TabManagerState state, Color textColor) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        _showTabsBottomSheet(context, state);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        margin: const EdgeInsets.only(left: 8.0),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${state.tabs.length}',
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              PhosphorIconsLight.file,
              size: 16,
              color: textColor,
            ),
          ],
        ),
      ),
    );
  }

  /// Hiển thị danh sách tab trong full screen mode
  void _showTabsBottomSheet(BuildContext context, TabManagerState state) async {
    final tabManagerBloc = BlocProvider.of<TabManagerBloc>(context);
    final localizations = AppLocalizations.of(context)!;

    // Capture thumbnail of active tab before showing tab manager
    final activeTab = state.activeTab;
    if (activeTab != null) {
      // Small delay to ensure content is fully rendered
      await Future.delayed(const Duration(milliseconds: 100));

      final thumbnail = await TabThumbnailService.captureTabThumbnail(
        activeTab.repaintBoundaryKey,
      );
      if (thumbnail != null && context.mounted) {
        tabManagerBloc.add(UpdateTabThumbnail(activeTab.id, thumbnail));
        debugPrint(
            'Captured thumbnail for active tab: ${activeTab.name} (${thumbnail.length} bytes)');
      }
    }

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => BlocProvider.value(
          value: tabManagerBloc,
          child: Builder(
            builder: (newContext) =>
                BlocBuilder<TabManagerBloc, TabManagerState>(
              builder: (context, updatedState) {
                final theme = Theme.of(context);

                return Scaffold(
                  backgroundColor: theme.scaffoldBackgroundColor,
                  appBar: AppBar(
                    elevation: 0,
                    backgroundColor: theme.scaffoldBackgroundColor,
                    leading: IconButton(
                      icon: Icon(
                        PhosphorIconsLight.x,
                        color: theme.colorScheme.onSurface,
                      ),
                      tooltip: localizations.close,
                      onPressed: () => Navigator.pop(context),
                    ),
                    title: Text(
                      localizations.tabManager,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    actions: [
                      PopupMenuButton<String>(
                        icon: Icon(
                          PhosphorIconsLight.dotsThree,
                          color: theme.colorScheme.onSurface,
                        ),
                        tooltip: localizations.moreOptions,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        offset: const Offset(0, 48),
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'add_tab',
                            child: Row(
                              children: [
                                Icon(
                                  PhosphorIconsLight.plus,
                                  size: 20,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  localizations.addNewTab,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (updatedState.tabs.isNotEmpty)
                            PopupMenuItem<String>(
                              value: 'close_all',
                              child: Row(
                                children: [
                                  Icon(
                                    PhosphorIconsLight.xCircle,
                                    size: 20,
                                    color: theme.colorScheme.error,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    localizations.closeAllTabs,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        onSelected: (value) {
                          if (value == 'add_tab') {
                            Navigator.pop(context);
                            onAddNewTab();
                          } else if (value == 'close_all') {
                            BlocProvider.of<TabManagerBloc>(context)
                                .add(CloseAllTabs());
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ],
                  ),
                  body: updatedState.tabs.isEmpty
                      ? _buildEmptyTabsState(context, localizations)
                      : _buildTabsGrid(context, updatedState, localizations),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyTabsState(
      BuildContext context, AppLocalizations localizations) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32.0),
              decoration: BoxDecoration(
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIconsLight.files,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              localizations.noTabsOpen,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              localizations.openNewTabToStart,
              style: TextStyle(
                fontSize: 16,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabsGrid(BuildContext context, TabManagerState state,
      AppLocalizations localizations) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int crossAxisCount = 2;
        if (width >= 600) crossAxisCount = 3;
        if (width >= 900) crossAxisCount = 4;

        return GridView.builder(
          padding: const EdgeInsets.all(20.0),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
            childAspectRatio: 0.75,
          ),
          itemCount: state.tabs.length,
          itemBuilder: (context, index) {
            final tab = state.tabs[index];
            final isActive = tab.id == state.activeTabId;

            return _buildTabGridTile(
              context: context,
              tab: tab,
              isActive: isActive,
              localizations: localizations,
            );
          },
        );
      },
    );
  }

  Widget _buildTabGridTile({
    required BuildContext context,
    required TabData tab,
    required bool isActive,
    required AppLocalizations localizations,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (!isActive) {
            BlocProvider.of<TabManagerBloc>(context).add(SwitchToTab(tab.id));
          }
          Navigator.pop(context);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isActive
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                : theme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Icon + Name + Close button
              Row(
                children: [
                  Icon(
                    tab.isPinned
                        ? PhosphorIconsLight.pushPin
                        : PhosphorIconsLight.folder,
                    size: 20,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tab.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      BlocProvider.of<TabManagerBloc>(context)
                          .add(CloseTab(tab.id));
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        PhosphorIconsLight.x,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Preview area with thumbnail or icon
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: tab.thumbnail != null
                      ? Image.memory(
                          tab.thumbnail!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Icon(
                                _getPreviewIcon(tab.path),
                                size: 48,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Icon(
                            _getPreviewIcon(tab.path),
                            size: 48,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // Path
              Text(
                tab.path.isEmpty || isDrivesPath(tab.path)
                    ? localizations.drives
                    : _shortenPath(tab.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortenPath(String p) {
    final parts =
        p.split(Platform.pathSeparator).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return p;
    if (parts.length == 1) return parts.first;
    return '${parts[parts.length - 2]}/${parts.last}';
  }

  IconData _getPreviewIcon(String path) {
    if (isDrivesPath(path)) return PhosphorIconsLight.hardDrives;

    // System paths
    if (path.startsWith('#')) {
      if (path == '#home') return PhosphorIconsLight.house;
      if (path == '#gallery' || path.startsWith('#album')) {
        return PhosphorIconsLight.image;
      }
      if (path == '#video') return PhosphorIconsLight.videoCamera;
      if (path == '#tags') return PhosphorIconsLight.tag;
      if (path == '#network' || path.startsWith('#network/')) {
        return PhosphorIconsLight.hardDrives;
      }
      if (path == '#smb') return PhosphorIconsLight.folder;
      return PhosphorIconsLight.squaresFour;
    }

    // Regular folder paths
    if (path.isEmpty) return PhosphorIconsLight.hardDrives;

    // Check for common folders
    final lowerPath = path.toLowerCase();
    if (lowerPath.contains('download')) {
      return PhosphorIconsLight.downloadSimple;
    }
    if (lowerPath.contains('picture') ||
        lowerPath.contains('photo') ||
        lowerPath.contains('dcim')) {
      return PhosphorIconsLight.image;
    }
    if (lowerPath.contains('video') || lowerPath.contains('movie')) {
      return PhosphorIconsLight.videoCamera;
    }
    if (lowerPath.contains('music') || lowerPath.contains('audio')) {
      return PhosphorIconsLight.musicNote;
    }
    if (lowerPath.contains('document')) return PhosphorIconsLight.fileText;

    return PhosphorIconsLight.folder;
  }

  Widget _buildEmptyTabsView(BuildContext context) {
    // Use HomeScreen like desktop when no tabs are open
    // Wrap in ClipRect to prevent overflow issues on mobile
    return const ClipRect(
      child: HomeScreen(
        tabId: 'home', // Use a special ID for home screen
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, TabManagerState state) {
    final activeTab = state.activeTab;
    if (activeTab == null) return Container();

    // Wrap with RepaintBoundary for screenshot capability
    return RepaintBoundary(
      key: activeTab.repaintBoundaryKey,
      child: _buildTabContentInner(context, activeTab),
    );
  }

  Widget _buildTabContentInner(BuildContext context, TabData activeTab) {
    // Check if this is a system path (starting with #)
    if (activeTab.path.startsWith('#') && !isDrivesPath(activeTab.path)) {
      // Handle network-specific paths
      if (activeTab.path == '#network') {
        // Path for displaying connection manager
        return BlocProvider<NetworkBrowsingBloc>.value(
          key: ValueKey('${activeTab.id}_network_connection_screen'),
          value: context.read<NetworkBrowsingBloc>(),
          child: const NetworkConnectionScreen(),
        );
      } else if (activeTab.path == '#smb') {
        // Path for the dedicated SMB Browser Screen (discovery and connection management)
        return BlocProvider<NetworkBrowsingBloc>.value(
          key: ValueKey('${activeTab.id}_smb_browser_screen'),
          value: context.read<
              NetworkBrowsingBloc>(), // Use the shared BLoC from TabMainScreen
          child: SMBBrowserScreen(
            tabId: activeTab.id,
            // SMBBrowserScreen uses SystemScreen which handles its own AppBar
          ),
        );
      } else if (activeTab.path.startsWith('#network/')) {
        // Path for browsing a specific network location (e.g., #network/service_id/actual_path)
        // This will be used by NetworkBrowserScreen for SMB, FTP, WebDAV browsing after connection.
        if (activeTab.path.length <= '#network/'.length ||
            activeTab.path == '#network/') {
          return BlocProvider<NetworkBrowsingBloc>.value(
            key: ValueKey(
                '${activeTab.id}_network_connection_fallback_incomplete_path'),
            value: context.read<NetworkBrowsingBloc>(),
            child: const NetworkConnectionScreen(),
          );
        }

        if (NetworkServiceRegistry().getServiceForPath(activeTab.path) ==
            null) {
          return BlocProvider<NetworkBrowsingBloc>.value(
            key: ValueKey(
                '${activeTab.id}_network_connection_fallback_no_service'),
            value: context.read<NetworkBrowsingBloc>(),
            child: const NetworkConnectionScreen(),
          );
        }

        return BlocProvider<NetworkBrowsingBloc>.value(
          key: ValueKey(
              '${activeTab.id}_network_browser_screen_${activeTab.path}'),
          value: context.read<NetworkBrowsingBloc>(),
          child: NetworkBrowserScreen(
            path: activeTab.path,
            tabId: activeTab.id,
            showAppBar: false,
          ),
        );
      } else {
        // Other system paths (#home, #gallery, #video, #tags, etc.)
        // Use SystemScreenRouter to route to the appropriate screen
        final systemScreen = SystemScreenRouter.routeSystemPath(
          context,
          activeTab.path,
          activeTab.id,
        );

        if (systemScreen != null) {
          return Container(
            key: ValueKey('${activeTab.id}_system_screen_${activeTab.path}'),
            child: systemScreen,
          );
        }

        // Fallback to empty container if system path is not recognized
        return Container(
          key:
              ValueKey('${activeTab.id}_unknown_system_path_${activeTab.path}'),
          child: Center(
            child: Text('Unknown system path: ${activeTab.path}'),
          ),
        );
      }
    } else {
      // Local file system path
      return Container(
        key: ValueKey(
            '${activeTab.id}_local_content_${activeTab.path}'), // Key includes path for local content
        child: Navigator(
          key: activeTab
              .navigatorKey, // This key should be stable for the tab's Navigator
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              settings: settings,
              builder: (context) => TabContentScreen(
                path: activeTab.path,
                tabId: activeTab.id,
              ),
            );
          },
        ),
      );
    }
  }

  /// Hiển thị dialog cho phép người dùng thay đổi đường dẫn
  void _showPathNavigationDialog(BuildContext context, TabData tab) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    // Get the TabManagerBloc instance from the current context
    final tabManagerBloc = BlocProvider.of<TabManagerBloc>(context);

    // Phân tách đường dẫn thành các phần
    List<String> pathParts = tab.path.split(Platform.pathSeparator);
    if (tab.path.startsWith(Platform.pathSeparator)) {
      pathParts = [
        Platform.pathSeparator,
        ...pathParts.where((part) => part.isNotEmpty)
      ];
    } else if (tab.path.isEmpty || isDrivesPath(tab.path)) {
      pathParts = ["Drives"];
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) =>
          // Wrap with BlocProvider.value to make the TabManagerBloc available inside the bottom sheet
          BlocProvider.value(
        value: tabManagerBloc,
        child: Builder(
          builder: (newContext) => Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Thanh kéo ở trên cùng
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
                  padding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: Row(
                    children: [
                      Text(
                        'Chọn vị trí',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      // Nút đóng
                      IconButton(
                        icon: Icon(PhosphorIconsLight.x, color: textColor),
                        onPressed: () => Navigator.pop(newContext),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Hiển thị đường dẫn hiện tại
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Text(
                      tab.path.isEmpty || isDrivesPath(tab.path)
                          ? 'Drives'
                          : tab.path,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),

                // Danh sách các phần của đường dẫn
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: pathParts.length,
                    itemBuilder: (context, index) {
                      // Tạo đường dẫn từ đầu đến phần hiện tại
                      String currentPath;
                      if (pathParts[0] == "Drives") {
                        currentPath = index == 0
                            ? kDrivesPath
                            : pathParts
                                .sublist(1, index + 1)
                                .join(Platform.pathSeparator);
                      } else {
                        if (pathParts[0] == Platform.pathSeparator) {
                          currentPath = index == 0
                              ? Platform.pathSeparator
                              : Platform.pathSeparator +
                                  pathParts
                                      .sublist(1, index + 1)
                                      .join(Platform.pathSeparator);
                        } else {
                          currentPath = pathParts
                              .sublist(0, index + 1)
                              .join(Platform.pathSeparator);
                        }
                      }

                      return ListTile(
                        leading: Icon(
                          index == 0
                              ? PhosphorIconsLight.desktop
                              : PhosphorIconsLight.folder,
                          color: theme.colorScheme.primary,
                        ),
                        title: Text(
                          pathParts[index].isEmpty ? 'Root' : pathParts[index],
                          style: TextStyle(
                            fontWeight: index == pathParts.length - 1
                                ? FontWeight.bold
                                : null,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(newContext);
                          // Use the new context to access the BlocProvider
                          final tabBloc =
                              BlocProvider.of<TabManagerBloc>(newContext);

                          // Update the tab path (this will automatically handle navigation history)
                          tabBloc.add(UpdateTabPath(tab.id, currentPath));

                          // Update tab name
                          final pathParts =
                              currentPath.split(Platform.pathSeparator);
                          final lastPart = pathParts.lastWhere(
                              (part) => part.isNotEmpty,
                              orElse: () => (currentPath.isEmpty ||
                                      isDrivesPath(currentPath))
                                  ? 'Drives'
                                  : 'Root');
                          final tabName = lastPart.isEmpty
                              ? ((currentPath.isEmpty ||
                                      isDrivesPath(currentPath))
                                  ? 'Drives'
                                  : 'Root')
                              : lastPart;
                          tabBloc.add(UpdateTabName(tab.id, tabName));
                        },
                      );
                    },
                  ),
                ),

                // Phần chân với lịch sử điều hướng
                if (tab.navigationHistory.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Lịch sử điều hướng:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: tab.navigationHistory.length,
                      itemBuilder: (context, index) {
                        final historyPath = tab.navigationHistory[index];
                        final isCurrentPath = historyPath == tab.path;

                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: InkWell(
                            onTap: () {
                              Navigator.pop(newContext);
                              if (!isCurrentPath) {
                                // Use the new context to access the BlocProvider
                                final tabBloc =
                                    BlocProvider.of<TabManagerBloc>(newContext);

                                // Update the tab path (this will automatically handle navigation history)
                                tabBloc.add(UpdateTabPath(tab.id, historyPath));
                              }
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isCurrentPath
                                    ? theme.colorScheme.primary
                                        .withValues(alpha: 0.2)
                                    : theme.colorScheme.surfaceContainerHighest
                                        .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Text(
                                  historyPath.isEmpty ||
                                          isDrivesPath(historyPath)
                                      ? 'Drives'
                                      : historyPath
                                              .split(Platform.pathSeparator)
                                              .last
                                              .isEmpty
                                          ? Platform.pathSeparator
                                          : historyPath
                                              .split(Platform.pathSeparator)
                                              .last,
                                  style: TextStyle(
                                    color: isCurrentPath
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface,
                                    fontWeight:
                                        isCurrentPath ? FontWeight.bold : null,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Extension để thêm method dynamic menu cho MobileTabView
extension MobileTabViewDynamicMenu on MobileTabView {
  /// Build mobile action buttons row for file management tools
  /// Now uses shared buildMobileActionBar from controller for consistency
  Widget _buildMobileActionButtons(
      BuildContext context, String tabId, String path) {
    final controller = MobileFileActionsController.forTab(tabId);
    controller.actionBarProfile = isDrivesPath(path)
        ? MobileActionBarProfile.drivesMinimal
        : MobileActionBarProfile.full;
    return controller.buildMobileActionBar(context);
  }

  /// Check if mobile action bar should be shown for the given path
  /// Returns true for local paths and network paths (#network/, smb://, ftp://, etc.)
  /// Returns false for other system paths (#home, #gallery, #video, #tags, etc.)
  bool _shouldShowMobileActionBar(String path) {
    if (isDrivesPath(path)) {
      return true;
    }

    if (path.startsWith('#search?tag=')) {
      return true;
    }

    // Allow network browsing paths
    if (path.startsWith('#network/')) {
      return true;
    }

    // Block other system paths that start with #
    if (path.startsWith('#')) {
      return false;
    }

    // Allow local file paths and direct network paths (smb://, ftp://, etc.)
    return true;
  }
}

/// Widget để hiển thị nội dung tab, tái sử dụng TabbedFolderListScreen
class TabContentScreen extends StatelessWidget {
  final String path;
  final String tabId;

  const TabContentScreen({
    Key? key,
    required this.path,
    required this.tabId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Get the current TabManagerBloc from context
    final tabManagerBloc = BlocProvider.of<TabManagerBloc>(context);

    // Use BlocProvider.value to pass down the same instance of TabManagerBloc
    return BlocProvider.value(
      value: tabManagerBloc,
      child: TabbedFolderListScreen(
        path: path,
        tabId: tabId,
        showAppBar: false, // Keep app bar hidden, tools will be in Chrome bar
      ),
    );
  }
}

/// Widget hiển thị thanh địa chỉ có thể nhấn để thay đổi đường dẫn
class AddressBarWidget extends StatelessWidget {
  final String path;
  final String name;
  final VoidCallback onTap;
  final bool isDarkMode;

  const AddressBarWidget({
    Key? key,
    required this.path,
    required this.name,
    required this.onTap,
    required this.isDarkMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20.0),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        decoration: BoxDecoration(
          // Nền rõ ràng cho thanh địa chỉ (đồng nhất dark)
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIconsLight.magnifyingGlass,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              PhosphorIconsLight.caretDown,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }
}
