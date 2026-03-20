import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Thêm import cho SystemUiOverlayStyle
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io'; // Thêm import cho Platform
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/theme_config.dart';
import 'core/tab_manager.dart';
import 'core/tab_data.dart';
import 'core/tab_paths.dart';
import 'tabbed_folder_list_screen.dart';
import '../screens/network_browsing/network_connection_screen.dart';
import '../screens/network_browsing/network_browser_screen.dart';
import '../screens/network_browsing/smb_browser_screen.dart'; // Added import for SMBBrowserScreen
import '../../bloc/network_browsing/network_browsing_bloc.dart';
import '../utils/route.dart';
import 'package:cb_file_manager/ui/state/video_ui_state.dart';
import 'screen_menu_registry.dart';

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
                    return _buildEmptyOrNormalChromeBar(context, state);
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
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;

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
              name: 'Search or enter path',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Vui lòng tạo một tab trước khi điều hướng'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              isDarkMode: isDarkMode,
            ),
          ),

          // Nút tạo tab mới nhanh (đặt trước nút số lượng tab)
          IconButton(
            icon: Icon(PhosphorIconsLight.plus, color: textColor),
            tooltip: 'New tab',
            onPressed: onAddNewTab,
          ),

          // Nút số lượng tab
          _buildTabCountButton(context, tState, textColor),

          // Nút menu tùy chọn
          IconButton(
            icon: Icon(PhosphorIconsLight.dotsThree, color: textColor),
            onPressed: () => _showMobileTabOptions(context),
          ),
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
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final textColor = isDarkMode ? Colors.white : Colors.black;

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
            tooltip: 'New tab',
            onPressed: onAddNewTab,
          ),

          // Nút số lượng tab và menu tab - đã chuyển sang bên phải thanh địa chỉ
          _buildTabCountButton(context, state, textColor),

          // Nút menu tùy chọn
          IconButton(
            icon: Icon(PhosphorIconsLight.dotsThree, color: textColor),
            onPressed: () {
              _showMobileTabOptions(context);
            },
          ),
        ],
      ),
    );
  }

  /// Hiển thị menu tùy chọn cho giao diện mobile
  void _showMobileTabOptions(BuildContext context) {
    final state = context.read<TabManagerBloc>().state;
    final activeTab = state.activeTab;
    // Lấy TabManagerBloc reference trước khi tạo BottomSheet
    final tabManagerBloc = context.read<TabManagerBloc>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => BlocProvider.value(
        value: tabManagerBloc,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(bottomSheetContext).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(bottomSheetContext).size.height * 0.6,
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
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                child: Text(
                  'Tùy chọn',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(bottomSheetContext).colorScheme.onSurface,
                  ),
                ),
              ),

              const Divider(height: 1),

              // Danh sách các tùy chọn
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // Thêm tab mới
                    ListTile(
                      leading: const Icon(PhosphorIconsLight.plus),
                      title: const Text('Thêm tab mới'),
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        onAddNewTab();
                      },
                    ),

                    // Làm mới tab hiện tại
                    if (activeTab != null)
                      ListTile(
                        leading: const Icon(PhosphorIconsLight.arrowsClockwise),
                        title: const Text('Làm mới tab'),
                        onTap: () {
                          Navigator.pop(bottomSheetContext);
                          tabManagerBloc
                              .add(UpdateTabPath(activeTab.id, activeTab.path));
                        },
                      ),

                    // Xem thông tin chi tiết về tab
                    if (activeTab != null)
                      ListTile(
                        leading: const Icon(PhosphorIconsLight.info),
                        title: const Text('Thông tin tab'),
                        onTap: () {
                          Navigator.pop(bottomSheetContext);
                          _showTabInfoDialog(context, activeTab);
                        },
                      ),

                    // Đóng tất cả các tab
                    if (state.tabs.isNotEmpty)
                      ListTile(
                        leading: const Icon(PhosphorIconsLight.x),
                        title: const Text('Đóng tất cả các tab'),
                        onTap: () {
                          RouteUtils.safePopDialog(bottomSheetContext);
                          _showCloseAllTabsConfirmation(context);
                        },
                      ),

                    // Dynamic menu items based on screen type
                    if (activeTab != null) ...[
                      ...MobileTabViewDynamicMenu._buildDynamicMenuItems(
                          context, activeTab.path, bottomSheetContext),
                    ],

                    const Divider(),

                    // Cài đặt
                    ListTile(
                      leading: const Icon(PhosphorIconsLight.gear),
                      title: const Text('Cài đặt'),
                      onTap: () {
                        RouteUtils.safePopDialog(bottomSheetContext);
                        final tabBloc =
                            BlocProvider.of<TabManagerBloc>(context);
                        final existingTab = tabBloc.state.tabs.firstWhere(
                          (tab) => tab.path == kSettingsPath,
                          orElse: () => TabData(id: '', name: '', path: ''),
                        );
                        if (existingTab.id.isNotEmpty) {
                          tabBloc.add(SwitchToTab(existingTab.id));
                        } else {
                          tabBloc.add(AddTab(
                            path: kSettingsPath,
                            name: 'Cài đặt',
                            switchToTab: true,
                          ));
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hiển thị hộp thoại xác nhận khi đóng tất cả các tab
  void _showCloseAllTabsConfirmation(BuildContext context) {
    // Lấy TabManagerBloc reference trước khi tạo dialog
    final tabBloc = context.read<TabManagerBloc>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đóng tất cả các tab?'),
        content: const Text('Bạn có chắc chắn muốn đóng tất cả các tab không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // Sử dụng tabBloc reference đã lấy từ trước
              final tabs = List<TabData>.from(tabBloc.state.tabs);
              for (var tab in tabs) {
                tabBloc.add(CloseTab(tab.id));
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Đóng tất cả'),
          ),
        ],
      ),
    );
  }

  /// Hiển thị thông tin chi tiết về tab
  void _showTabInfoDialog(BuildContext context, TabData tab) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tab.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Thông tin tab:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text('Đường dẫn: ${tab.path}'),
              const SizedBox(height: 4),
              Text('Ghim: ${tab.isPinned ? 'Có' : 'Không'}'),
              const SizedBox(height: 4),
              Text('ID: ${tab.id}'),
              const SizedBox(height: 16),
              const Text(
                'Lịch sử điều hướng:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (tab.navigationHistory.isEmpty)
                const Text('Không có lịch sử')
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: tab.navigationHistory.map((path) {
                        final isCurrentPath = path == tab.path;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            path.isEmpty ? 'Drives' : path,
                            style: TextStyle(
                              fontWeight:
                                  isCurrentPath ? FontWeight.bold : null,
                              color: isCurrentPath
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (tab.isPinned)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.read<TabManagerBloc>().add(ToggleTabPin(tab.id));
              },
              child: const Text('Bỏ ghim'),
            )
          else
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.read<TabManagerBloc>().add(ToggleTabPin(tab.id));
              },
              child: const Text('Ghim'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  /// Xây dựng nút hiển thị số lượng tab
  Widget _buildTabCountButton(
      BuildContext context, TabManagerState state, Color textColor) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        _showTabsBottomSheet(context, state);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        margin: const EdgeInsets.only(left: 8.0),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF0F2C4C) : Colors.grey[200],
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

  /// Hiển thị danh sách tab trong bottom sheet
  void _showTabsBottomSheet(BuildContext context, TabManagerState state) {
    // Lấy instance của TabManagerBloc từ context hiện tại
    final tabManagerBloc = BlocProvider.of<TabManagerBloc>(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) =>
          // Sử dụng BlocProvider.value để truyền instance của TabManagerBloc vào widget tree mới
          BlocProvider.value(
        value: tabManagerBloc,
        child: Builder(
          builder: (newContext) => BlocBuilder<TabManagerBloc, TabManagerState>(
            builder: (context, updatedState) => Container(
              decoration: BoxDecoration(
                color: Theme.of(newContext).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(newContext).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Thanh tiêu đề
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text(
                          'Tabs (${updatedState.tabs.length})',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(newContext).colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        // Nút thêm tab mới
                        IconButton(
                          icon: const Icon(PhosphorIconsLight.plus),
                          tooltip: 'Add new tab',
                          onPressed: () {
                            Navigator.pop(newContext); // Đóng bottom sheet
                            onAddNewTab();
                          },
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Danh sách tab (Grid dạng Chrome)
                  Flexible(
                    child: updatedState.tabs.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                'Không có tab nào',
                                style: TextStyle(
                                  color: Theme.of(newContext)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              // Xác định số cột theo chiều rộng
                              final width = constraints.maxWidth;
                              int crossAxisCount = 2;
                              if (width >= 480) crossAxisCount = 3;
                              if (width >= 720) crossAxisCount = 4;

                              return GridView.builder(
                                padding: const EdgeInsets.all(12.0),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.2,
                                ),
                                itemCount: updatedState.tabs.length,
                                itemBuilder: (context, index) {
                                  final tab = updatedState.tabs[index];
                                  final isActive =
                                      tab.id == updatedState.activeTabId;

                                  return _buildTabGridTile(
                                    context: newContext,
                                    tab: tab,
                                    isActive: isActive,
                                  );
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Thay thế class riêng bằng builder private để tránh class lồng nhau
  Widget _buildTabGridTile({
    required BuildContext context,
    required TabData tab,
    required bool isActive,
  }) {
    final theme = Theme.of(context);
    final borderColor = isActive
        ? theme.colorScheme.primary.withValues(alpha: 0.5)
        : theme.dividerColor.withValues(alpha: 0.3);

    return InkWell(
      borderRadius: BorderRadius.circular(16.0),
      onTap: () {
        if (!isActive) {
          BlocProvider.of<TabManagerBloc>(context).add(SwitchToTab(tab.id));
        }
        Navigator.pop(context);
      },
      child: Ink(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: borderColor),
          boxShadow: [],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16.0),
                  onTap: () {
                    BlocProvider.of<TabManagerBloc>(context)
                        .add(CloseTab(tab.id));
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6.0),
                    child: Icon(PhosphorIconsLight.x, size: 16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        tab.isPinned
                            ? PhosphorIconsLight.pushPin
                            : PhosphorIconsLight.folder,
                        size: 18,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.iconTheme.color,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tab.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w500,
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        PhosphorIconsLight.fileText,
                        size: 28,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tab.path.isEmpty ? 'Drives' : _shortenPath(tab.path),
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
          ],
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

  Widget _buildEmptyTabsView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            PhosphorIconsLight.file,
            size: 64,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          const Text(
            'No tabs open',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open a new tab to get started',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(PhosphorIconsLight.plus),
            label: const Text('New Tab'),
            onPressed: onAddNewTab,
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context, TabManagerState state) {
    final activeTab = state.activeTab;
    if (activeTab == null) return Container();

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
    final isDarkMode = theme.brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;

    // Get the TabManagerBloc instance from the current context
    final tabManagerBloc = BlocProvider.of<TabManagerBloc>(context);

    // Phân tách đường dẫn thành các phần
    List<String> pathParts = tab.path.split(Platform.pathSeparator);
    if (tab.path.startsWith(Platform.pathSeparator)) {
      pathParts = [
        Platform.pathSeparator,
        ...pathParts.where((part) => part.isNotEmpty)
      ];
    } else if (tab.path.isEmpty) {
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
                    color: Colors.grey.withValues(alpha: 0.3),
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
                      color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: Text(
                      tab.path.isEmpty ? 'Drives' : tab.path,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87,
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
                            ? ""
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
                              orElse: () =>
                                  currentPath.isEmpty ? 'Drives' : 'Root');
                          final tabName = lastPart.isEmpty
                              ? (currentPath.isEmpty ? 'Drives' : 'Root')
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
                                    : isDarkMode
                                        ? Colors.grey[800]
                                        : Colors.grey[200],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Center(
                                child: Text(
                                  historyPath.isEmpty
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
                                        : isDarkMode
                                            ? Colors.white
                                            : Colors.black87,
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
  /// Xây dựng dynamic menu items dựa trên loại màn hình
  static List<Widget> _buildDynamicMenuItems(
      BuildContext context, String path, BuildContext bottomSheetContext) {
    // Khởi tạo menu registry nếu chưa có
    ScreenMenuRegistry.initializeMenus(context);

    // Lấy menu items cho path hiện tại
    final menuItems = ScreenMenuRegistry.getMenuForPath(path);

    if (menuItems == null || menuItems.isEmpty) {
      return [];
    }

    return menuItems.map((item) {
      if (item.isDivider) {
        return const Divider();
      }

      return ListTile(
        leading: Icon(item.icon),
        title: Text(item.title),
        onTap: () {
          Navigator.pop(bottomSheetContext);
          item.onTap();
        },
      );
    }).toList();
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
        showAppBar: false, // Thêm tham số này vào TabbedFolderListScreen
      ),
    );
  }
}

/// Widget hiển thị thanh địa chỉ có thể nhấn để thay đổi đường dẫn
class AddressBarWidget extends StatelessWidget {
  final String path;
  final String name;
  final VoidCallback onTap;
  // `isDarkMode` is retained for backwards compatibility but no longer
  // used; the theme itself dictates the fill color via the
  // [addressBarFillColor] extension.
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
    // Using Colors directly below

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20.0),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        decoration: BoxDecoration(
          // background comes from themeconfig helper instead of hardcoded color
          color:
              ThemeConfig.addressBarFillColorFor(Theme.of(context).brightness),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIconsLight.magnifyingGlass,
              size: 18,
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              PhosphorIconsLight.caretDown,
              size: 20,
              color: isDarkMode ? Colors.white54 : Colors.black54,
            ),
          ],
        ),
      ),
    );
  }
}
