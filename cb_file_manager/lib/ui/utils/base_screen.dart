import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cb_file_manager/ui/drawer.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart'; // Add UserPreferences import
// Import translation helper
import 'package:phosphor_flutter/phosphor_flutter.dart';
// Import RouteUtils
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
// For Platform check

/// A base screen widget that handles common functionality across all screens
/// including drawer, back button, and home button navigation.
class BaseScreen extends StatefulWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final FloatingActionButton? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool automaticallyImplyLeading;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
  final bool showAppBar;

  /// Static key for accessing drawer from anywhere - for backward compatibility only
  /// THIS SHOULD NOT BE USED IN NEW CODE - it's only here for legacy support
  static final GlobalKey<ScaffoldState> scaffoldKey =
      GlobalKey<ScaffoldState>(debugLabel: 'legacyGlobalScaffoldKey');

  /// Static reference to the most recently active BaseScreen state
  /// This is used for backward compatibility
  static _BaseScreenState? _mostRecentState;

  /// Function to open the drawer from anywhere in the app
  static void openDrawer() {
    // Try to use the most recent state first
    if (_mostRecentState != null && _mostRecentState!.mounted) {
      _mostRecentState!._scaffoldKey.currentState?.openDrawer();
      return;
    }

    // Fall back to the legacy key if no recent state available
    scaffoldKey.currentState?.openDrawer();
  }

  const BaseScreen({
    Key? key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.automaticallyImplyLeading = true,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.showAppBar = true,
  }) : super(key: key);

  @override
  State<BaseScreen> createState() => _BaseScreenState();
}

class _BaseScreenState extends State<BaseScreen> {
  // Instance-specific scaffold key
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(debugLabel: 'instanceScaffoldKey');

  // Drawer state variables
  bool _isDrawerPinned = false;
  bool _inAndroidPip = false;

  @override
  void initState() {
    super.initState();
    // Register as the most recent state
    BaseScreen._mostRecentState = this;
    // Load drawer preferences
    _loadDrawerPreferences();
    _attachPipListener();
  }

  void _attachPipListener() {
    // Listen for Android PiP changes to auto-hide AppBar globally
    const channel = MethodChannel('cb_file_manager/pip');
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipChanged') {
        final args = call.arguments;
        bool inPip = false;
        if (args is Map) {
          inPip = args['inPip'] == true;
        }
        if (mounted) {
          setState(() => _inAndroidPip = inPip);
        }
      }
    });
  }

  // Load drawer preferences from storage
  Future<void> _loadDrawerPreferences() async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      final drawerPinned = await prefs.getDrawerPinned();

      if (mounted) {
        setState(() {
          // Only set drawer to pinned if not on a small screen
          final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
          _isDrawerPinned = isSmallScreen ? false : drawerPinned;
        });
      }
    } catch (e) {
      // debugPrint('Error loading drawer preferences: $e');
    }
  }

  // Save drawer pinned state
  Future<void> _saveDrawerPinned(bool isPinned) async {
    try {
      final UserPreferences prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setDrawerPinned(isPinned);
    } catch (e) {
      // debugPrint('Error saving drawer pinned state: $e');
    }
  }

  // Toggle drawer pin state
  void _toggleDrawerPin() {
    // Check if we're on a small screen
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;

    setState(() {
      // Only allow pinning on larger screens
      if (!isSmallScreen) {
        _isDrawerPinned = !_isDrawerPinned;
        _saveDrawerPinned(_isDrawerPinned);
      } else {
        // Force unpinned on small screens and show a message
        _isDrawerPinned = false;
        _saveDrawerPinned(false);

        // Show a message explaining why pinning isn't available
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Menu pinning is only available on larger screens'),
              duration: Duration(seconds: 2),
            ),
          );
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine background color - use transparent on desktop for acrylic effect
    final bool isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final Color? resolvedBackgroundColor = widget.backgroundColor ?? (isDesktop ? Colors.transparent : null);

    return BlocProvider(
      create: (_) => DrawerCubit()..loadStorageLocations(),
      child: PopScope(
        canPop: true,
        child: Scaffold(
        key: _scaffoldKey, // Use instance-specific key
        extendBodyBehindAppBar: isDesktop,
        appBar: (widget.showAppBar && !_inAndroidPip)
            ? AppBar(
                backgroundColor: isDesktop ? Colors.transparent : null,
                elevation: isDesktop ? 0 : null,
                title: Text(widget.title),
                leading: widget.automaticallyImplyLeading
                    ? _buildLeadingIcon(context)
                    : null,
                actions: <Widget>[
                  // // Always add the menu button as the first action
                  // IconButton(
                  //   icon: const Icon(PhosphorIconsLight.list),
                  //   onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  // ),

                  // // Home button for emergency navigation
                  // IconButton(
                  //   icon: const Icon(PhosphorIconsLight.house),
                  //   tooltip: context.tr.home,
                  //   onPressed: () => goHome(context),
                  // ),

                  // Add any additional actions
                  if (widget.actions != null) ...widget.actions!,
                ],
              )
            : null,
        drawer: CBDrawer(
          context,
          isPinned: _isDrawerPinned,
          onPinStateChanged: (isPinned) {
            _toggleDrawerPin();
          },
        ),
        body: Container(
          color: isDesktop ? Colors.transparent : null,
          child: widget.body,
        ),
        backgroundColor: resolvedBackgroundColor,
        floatingActionButton: widget.floatingActionButton,
        bottomNavigationBar: widget.bottomNavigationBar,
        resizeToAvoidBottomInset: widget.resizeToAvoidBottomInset,
      ),
    ),
    );
  }

  /// Build the leading icon based on the navigation state
  Widget _buildLeadingIcon(BuildContext context) {
    return IconButton(
      icon: const Icon(PhosphorIconsLight.arrowLeft),
      onPressed: () {
        // 1) Try to pop the local navigator stack if possible
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
          return;
        }

        // 2) If running inside the tab system, handle back via TabManager
        TabManagerBloc? tabBloc;
        try {
          tabBloc = context.read<TabManagerBloc>();
        } catch (_) {
          tabBloc = null;
        }
        if (tabBloc != null) {
          final activeTab = tabBloc.state.activeTab;
          if (activeTab != null) {
            // 2a) Pop any nested navigator in the active tab (e.g. viewer/player)
            final nestedNav = activeTab.navigatorKey.currentState;
            if (nestedNav != null && nestedNav.canPop()) {
              nestedNav.pop();
              return;
            }

            // 2b) Navigate back within tab path history if available
            if (activeTab.navigationHistory.length > 1) {
              tabBloc.backNavigationToPath(activeTab.id);
              return;
            }

            // 2c) No history: close the current tab
            tabBloc.add(CloseTab(activeTab.id));
            return;
          }
        }

        // 3) Fallback: try a maybePop to gracefully handle other contexts
        Navigator.maybePop(context);
      },
    );
  }
}




