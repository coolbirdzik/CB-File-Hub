import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/permission_state_service.dart';
import '../../screens/onboarding/theme_onboarding_screen.dart';
import '../../screens/permissions/permission_explainer_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../components/common/operation_progress_overlay.dart';
import '../../../core/service_locator.dart';
import '../../../services/windowing/desktop_windowing_service.dart';
import '../../../services/windowing/window_startup_payload.dart';
import '../../../services/windowing/windows_native_tab_drag_drop_service.dart';
import 'tab_manager.dart';
import 'tab_screen.dart';

/// The main screen that provides the tabbed interface for the file manager
class TabMainScreen extends StatefulWidget {
  final WindowStartupPayload? startupPayload;
  const TabMainScreen({Key? key, this.startupPayload}) : super(key: key);

  /// Static method to create and open a new tab with a specific path
  static void openPath(BuildContext context, String path) {
    final tabBloc = context.read<TabManagerBloc>();
    tabBloc.add(AddTab(path: path));
  }

  /// Static method to open the default path (e.g., documents directory)
  static Future<void> openDefaultPath(BuildContext context) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      if (context.mounted) {
        openPath(context, directory.path);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${AppLocalizations.of(context)!.errorAccessingDirectory}$e')),
        );
      }
    }
  }

  @override
  State<TabMainScreen> createState() => _TabMainScreenState();
}

class _TabMainScreenState extends State<TabMainScreen> {
  static const String _themeOnboardingDoneKey = 'theme_onboarding_completed_v1';

  late TabManagerBloc _tabManagerBloc;
  late NetworkBrowsingBloc _networkBrowsingBloc;
  bool _checkedPerms = false;
  OverlayEntry? _operationProgressOverlayEntry;
  OverlayEntry? _nativeDropHighlightOverlayEntry;
  DesktopWindowingService? _desktopWindowing;

  @override
  void initState() {
    super.initState();
    _tabManagerBloc = TabManagerBloc();
    _networkBrowsingBloc = NetworkBrowsingBloc();

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      _desktopWindowing = locator<DesktopWindowingService>();
      unawaited(_desktopWindowing!.attachTabBloc(_tabManagerBloc));
    }
    if (Platform.isWindows) {
      WindowsNativeTabDragDropService.isDragHoveringWindow
          .addListener(_handleNativeDropHoverChanged);
      _handleNativeDropHoverChanged();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final payload = widget.startupPayload;
      if (payload != null && payload.tabs.isNotEmpty) {
        final active =
            (payload.activeIndex ?? 0).clamp(0, payload.tabs.length - 1);
        for (int i = 0; i < payload.tabs.length; i++) {
          final tab = payload.tabs[i];
          _tabManagerBloc.add(AddTab(
            path: tab.path,
            name: tab.name,
            switchToTab: i == active,
            highlightedFileName: tab.highlightedFileName,
          ));
        }
      }

      if (_operationProgressOverlayEntry == null) {
        final overlay = Overlay.maybeOf(context, rootOverlay: true);
        if (overlay != null) {
          _operationProgressOverlayEntry = OverlayEntry(
            builder: (_) => const OperationProgressOverlay(),
          );
          overlay.insert(_operationProgressOverlayEntry!);
        }
      }
      if (_checkedPerms) return;
      _checkedPerms = true;
      await _runStartupOnboardingAndPermissionFlow();
    });
  }

  bool _isDesktopPlatform() {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  bool _isSecondaryDesktopWindow() {
    if (!_isDesktopPlatform()) return false;
    return Platform.environment[WindowStartupPayload.envSecondaryWindowKey] ==
        '1';
  }

  Future<void> _runStartupOnboardingAndPermissionFlow() async {
    await _showThemeOnboardingIfNeeded();
    if (!mounted) return;

    // Desktop skips permission screen entirely.
    if (_isDesktopPlatform()) return;

    await _showPermissionExplainerIfNeeded();
  }

  Future<void> _showThemeOnboardingIfNeeded() async {
    // Secondary windows must not interrupt primary flow with onboarding.
    if (_isSecondaryDesktopWindow()) return;

    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_themeOnboardingDoneKey) ?? false;
    if (completed) return;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: theme.colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 760,
              maxHeight: 720,
            ),
            child: ThemeOnboardingScreen(
              embedded: true,
              onCompleted: () => Navigator.of(dialogContext).pop(),
            ),
          ),
        );
      },
    );

    await prefs.setBool(_themeOnboardingDoneKey, true);
  }

  Future<void> _showPermissionExplainerIfNeeded() async {
    final hasStorage =
        await PermissionStateService.instance.hasStorageOrPhotosPermission();
    final hasAllFiles = Platform.isAndroid
        ? await PermissionStateService.instance.hasAllFilesAccessPermission()
        : true;
    final hasInstallPackages = Platform.isAndroid
        ? await PermissionStateService.instance.hasInstallPackagesPermission()
        : true;
    final hasLocal =
        await PermissionStateService.instance.hasLocalNetworkPermission();
    final needsExplainer = !hasStorage ||
        !hasAllFiles ||
        !hasInstallPackages ||
        (Platform.isIOS ? !hasLocal : false);

    if (!needsExplainer || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PermissionExplainerScreen(),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      WindowsNativeTabDragDropService.isDragHoveringWindow
          .removeListener(_handleNativeDropHoverChanged);
    }
    _nativeDropHighlightOverlayEntry?.remove();
    _nativeDropHighlightOverlayEntry = null;
    _operationProgressOverlayEntry?.remove();
    _operationProgressOverlayEntry = null;
    unawaited(_desktopWindowing?.dispose());
    _tabManagerBloc.close();
    _networkBrowsingBloc.close();
    super.dispose();
  }

  void _handleNativeDropHoverChanged() {
    if (!mounted || !Platform.isWindows) return;
    final isHovering =
        WindowsNativeTabDragDropService.isDragHoveringWindow.value;

    if (isHovering) {
      if (_nativeDropHighlightOverlayEntry != null) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      _nativeDropHighlightOverlayEntry = OverlayEntry(
        builder: (_) => const _NativeDropHoverOverlay(),
      );
      overlay.insert(_nativeDropHighlightOverlayEntry!);
    } else {
      _nativeDropHighlightOverlayEntry?.remove();
      _nativeDropHighlightOverlayEntry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<TabManagerBloc>.value(value: _tabManagerBloc),
        BlocProvider<NetworkBrowsingBloc>.value(value: _networkBrowsingBloc),
      ],
      child: const TabScreen(),
    );
  }
}

class _NativeDropHoverOverlay extends StatefulWidget {
  const _NativeDropHoverOverlay();

  @override
  State<_NativeDropHoverOverlay> createState() =>
      _NativeDropHoverOverlayState();
}

class _NativeDropHoverOverlayState extends State<_NativeDropHoverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    )..repeat();
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.colorScheme.primary;
    final isDarkMode = theme.brightness == Brightness.dark;

    final frameColor = baseColor.withValues(alpha: isDarkMode ? 0.26 : 0.22);
    final stripBorderColor =
        baseColor.withValues(alpha: isDarkMode ? 0.76 : 0.70);
    final stripFillColor =
        baseColor.withValues(alpha: isDarkMode ? 0.14 : 0.11);
    final veilColor = isDarkMode
        ? Colors.black.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.03);

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            Tween<double>(begin: 0.22, end: 0.42)
                .transform(_animation.value);

            return Stack(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(color: veilColor),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16.0),
                        border: Border.all(color: frameColor, width: 1.6),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 8,
                  height: 41,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(11),
                      color: stripFillColor,
                      border: Border.all(color: stripBorderColor, width: 1.8),
                      boxShadow: const [],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 8,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 90),
                    opacity: 0.9,
                    child: Container(
                      width: 3,
                      height: 41,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
