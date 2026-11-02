import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import '../../bloc/selection/selection.dart';
import '../components/common/screen_scaffold.dart';
import '../components/common/file_view_shell.dart';
import '../components/common/browser_like_keyboard_shortcuts.dart';
import 'folder_list/folder_list_state.dart';
import 'network_browsing/components/network_navigation_bar.dart';

/// A base class for all system screens in the application
/// System screens are screens that are not tied to a file system path
/// but represent system functionality like tags, trash, settings, etc.
class SystemScreen extends StatelessWidget {
  /// The title of the system screen
  final String title;

  /// The system ID (used for routing, e.g. #tags, #trash)
  final String systemId;

  /// The icon to display in the tab
  final IconData icon;

  /// The actual content of the system screen
  final Widget child;

  /// Whether to show the app bar (default: true)
  final bool showAppBar;

  /// Additional actions to display in the app bar
  final List<Widget>? actions;
  final String? tabId;
  final VoidCallback? onRefresh;
  final ViewMode viewMode;
  final String? homePath;

  /// Like the file browser, [searchBar] takes the path's place in the
  /// toolbar while [showSearchBar] is set.
  final bool showSearchBar;
  final Widget? searchBar;

  /// Ctrl+F and Escape.
  final VoidCallback? onSearch;
  final VoidCallback? onEscape;

  /// Constructor
  const SystemScreen({
    super.key,
    required this.title,
    required this.systemId,
    required this.icon,
    required this.child,
    this.showAppBar = false,
    this.actions,
    this.tabId,
    this.onRefresh,
    this.viewMode = ViewMode.list,
    this.homePath,
    this.showSearchBar = false,
    this.searchBar,
    this.onSearch,
    this.onEscape,
  });

  @override
  Widget build(BuildContext context) {
    if (tabId != null &&
            const [
              '#network',
              '#smb',
              '#ftp',
              '#webdav',
              '#sftp',
              '#ssh',
            ].contains(systemId) ||
        systemId.startsWith('#ssh/')) {
      final tabs = context.read<TabManagerBloc>();
      void back() => tabs.backNavigationToPath(tabId!);
      void forward() => tabs.forwardNavigationToPath(tabId!);
      return Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) {
          if (tabs.state.activeTabId != tabId ||
              event is! KeyDownEvent ||
              BrowserLikeKeyboardShortcuts.isTextInputFocused()) {
            return KeyEventResult.ignored;
          }
          final alt = HardwareKeyboard.instance.isAltPressed;
          if ((alt && event.logicalKey == LogicalKeyboardKey.arrowLeft) ||
              event.logicalKey == LogicalKeyboardKey.backspace) {
            back();
            return KeyEventResult.handled;
          }
          if (alt && event.logicalKey == LogicalKeyboardKey.arrowRight) {
            forward();
            return KeyEventResult.handled;
          }
          if (alt && event.logicalKey == LogicalKeyboardKey.arrowUp) {
            final parent = networkParentPath(systemId);
            if (parent != null) navigateNetworkTab(context, tabId!, parent);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ScreenScaffold(
          selectionState: const SelectionState(),
          isNetworkPath: true,
          isDesktop: Platform.isWindows || Platform.isLinux || Platform.isMacOS,
          onClearSelection: () {},
          showRemoveTagsDialog: (_) {},
          showManageAllTagsDialog: (_) {},
          showDeleteConfirmationDialog: (_) {},
          showAppBar: showAppBar,
          showSearchBar: showSearchBar && searchBar != null,
          searchBar: searchBar ?? const SizedBox.shrink(),
          pathNavigationBar: NetworkNavigationBar(
            tabId: tabId!,
            path: systemId,
            homePath:
                homePath ??
                (systemId == '#sftp' || systemId.startsWith('#ssh')
                    ? '#ssh'
                    : '#home'),
          ),
          actions: actions ?? const [],
          body: ClipRect(
            child: FileViewShell(
              viewMode: viewMode,
              onMouseBack: back,
              onMouseForward: forward,
              onRefresh: onRefresh,
              onSearch: onSearch,
              onEscape: onEscape,
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      // Network landing pages must reserve space for their visible toolbar.
      extendBodyBehindAppBar: false,
      backgroundColor: Colors.transparent,
      appBar: showAppBar
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: Text(title),
              actions: actions,
              // Replace the close button with a back button
              // This will automatically handle whether to show a back arrow
              // or a close button depending on the navigation stack.
              leading: Navigator.canPop(context) ? const BackButton() : null,
            )
          : null,
      body: Container(color: Colors.transparent, child: child),
    );
  }

  /// Factory method to create a system screen tab
  /// This can be used to programmatically add a system screen tab to the tab manager
  static void openInTab(
    BuildContext context, {
    required String systemId,
    required String title,
    required IconData icon,
  }) {
    // Check if a tab with this systemId already exists
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final existingTab = tabBloc.state.tabs.firstWhere(
      (tab) => tab.path == systemId,
      orElse: () => TabData(id: '', name: '', path: ''),
    );

    if (existingTab.id.isNotEmpty) {
      // If tab exists, switch to it
      tabBloc.add(SwitchToTab(existingTab.id));
    } else {
      // Otherwise, create a new tab
      tabBloc.add(AddTab(path: systemId, name: title, switchToTab: true));
    }
  }
}
