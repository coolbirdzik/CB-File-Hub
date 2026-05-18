import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../services/permission_state_service.dart';
import '../../screens/onboarding/theme_onboarding_screen.dart';
import '../../screens/permissions/permission_explainer_screen.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import '../../../bloc/network_browsing/network_browsing_bloc.dart';
import '../../components/common/operation_progress_overlay.dart';
import '../../../core/service_locator.dart';
import '../../../services/windowing/desktop_windowing_service.dart';
import '../../../services/progress/desktop_app_icon_progress_service.dart';
import '../../controllers/operation_progress_controller.dart';
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
    final tabBloc = context.read<TabManagerBloc>();
    final l10n = AppLocalizations.of(context)!;
    final toast = AppToast.capture(context);
    try {
      final directory = await getApplicationDocumentsDirectory();
      tabBloc.add(AddTab(path: directory.path));
    } catch (e) {
      toast.error('${l10n.errorAccessingDirectory}$e');
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
      locator<DesktopAppIconProgressService>().start(
        locator<OperationProgressController>(),
      );
    }
    if (Platform.isWindows) {
      WindowsNativeTabDragDropService.isDragHoveringWindow
          .addListener(_handleNativeDropHoverChanged);
      _handleNativeDropHoverChanged();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
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

      // Insert the overlay synchronously within the postFrameCallback so it
      // happens at a safe frame boundary and never after an await point.
      if (_operationProgressOverlayEntry == null) {
        final overlay = Overlay.maybeOf(context, rootOverlay: true);
        if (overlay != null) {
          _operationProgressOverlayEntry = OverlayEntry(
            builder: (_) => const OperationProgressOverlay(),
          );
          overlay.insert(_operationProgressOverlayEntry!);
        }
      }

      // Run the async onboarding/permission flow as a separate unawaited
      // Future so it does not turn this postFrameCallback into an async
      // function (which would resume after awaits mid-frame).
      if (!_checkedPerms) {
        _checkedPerms = true;
        unawaited(_runStartupOnboardingAndPermissionFlow());
      }
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
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        barrierDismissible: false,
        pageBuilder: (routeCtx, animation, _) {
          return Consumer<ThemeProvider>(
            builder: (ctx, provider, __) {
              final theme = Theme.of(ctx);
              final solidBg =
                  theme.scaffoldBackgroundColor.withValues(alpha: 1);
              final cardBg = (theme.dialogTheme.backgroundColor ??
                      theme.colorScheme.surfaceContainerHigh)
                  .withValues(alpha: 1);
              return Material(
                color: solidBg,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 760,
                        maxHeight: 720,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: ColoredBox(
                          color: cardBg,
                          child: SizedBox.expand(
                            child: ThemeOnboardingScreen(
                              embedded: true,
                              onCompleted: () => Navigator.of(routeCtx).pop(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        transitionsBuilder: (ctx, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 220),
      ),
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
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      unawaited(locator<DesktopAppIconProgressService>().stop());
    }
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
            Tween<double>(begin: 0.22, end: 0.42).transform(_animation.value);

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
