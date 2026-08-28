import 'dart:io';
import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import './utils/route.dart';
import './tab_manager/core/tab_main_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/config/design_system_config.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:cb_file_manager/design_system/fluent_chrome_surface.dart';
import 'package:cb_file_manager/design_system/fluent_surface_tokens.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Imported components
import 'package:cb_file_manager/ui/widgets/drawer/drawer_header_widget.dart';
import 'package:cb_file_manager/ui/widgets/drawer/drawer_navigation_item.dart';
import 'package:cb_file_manager/ui/widgets/drawer/storage_section_widget.dart';
import 'package:cb_file_manager/ui/widgets/drawer/pinned_section_widget.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';

/// Returns a key that forces a Fluent drawer section to honor the active tab's
/// persisted expansion state after a tab switch or expansion change.
/// Shared geometry and motion values for the desktop navigation surface.
///
/// Keeping these values together makes the drawer's spacing rhythm intentional
/// and prevents individual rows from drifting into unrelated visual styles.
class _FluentDrawerTokens {
  const _FluentDrawerTokens._();

  static const double width = 288;
  static const double outerRadius = 12;
  static const double itemRadius = 6;
  static const double itemHeight = 42;
  static const double itemVerticalMargin = 2;
  static const double sectionIndent = 30;
  static const double groupGap = 12;
  static const Duration stateTransition = Duration(milliseconds: 180);
  static const Duration sectionTransition = Duration(milliseconds: 200);
}

/// A borderless Fluent navigation section that keeps its content state in the
/// same keyed widget as the active tab's persisted expansion state.
/// One collapsible group (Pinned, Drives, ...) in the desktop drawer.
///
/// [expanded] is a live value, not a one-shot seed: the section stays mounted
/// and animates to match whenever the drawer state changes. That matters
/// beyond tidiness — this group used to carry a [ValueKey] built from the
/// active tab id and the expansion flag, so every tab switch and every
/// expand/collapse remounted the whole subtree. Remounting destroys and
/// recreates each semantics node under it inside a single frame, and the
/// Windows AccessibilityBridge cannot serialize an ui::AXTreeUpdate that drops
/// node ids and reclaims their slots at once — it drops the batch and floods
/// stderr with "Failed to update ui::AXTree". See the same reasoning in
/// ui/components/common/optimized_interaction_handler.dart.
class FluentDrawerSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final bool expanded;
  final ValueChanged<bool> onStateChanged;
  final Widget content;

  const FluentDrawerSection({
    Key? key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.expanded,
    required this.onStateChanged,
    required this.content,
  }) : super(key: key);

  @override
  State<FluentDrawerSection> createState() => _FluentDrawerSectionState();
}

class _FluentDrawerSectionState extends State<FluentDrawerSection> {
  // fluent's Expander reads `initiallyExpanded` once and has no
  // didUpdateWidget, so following the drawer state means driving its state
  // object directly.
  final GlobalKey<fluent.ExpanderState> _expanderKey =
      GlobalKey<fluent.ExpanderState>();

  /// True while [_syncExpansion] drives the expander, so the resulting
  /// callback is not echoed back into the cubit that asked for it.
  bool _syncingFromState = false;

  @override
  void didUpdateWidget(FluentDrawerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded) {
      _syncExpansion(widget.expanded);
    }
  }

  void _syncExpansion(bool expanded) {
    // Expander.isExpanded calls setState; didUpdateWidget runs mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _expanderKey.currentState;
      if (!mounted || state == null || state.isExpanded == expanded) return;
      _syncingFromState = true;
      try {
        state.isExpanded = expanded;
      } finally {
        _syncingFromState = false;
      }
    });
  }

  void _handleStateChanged(bool expanded) {
    if (_syncingFromState) return;
    widget.onStateChanged(expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final resources = theme.resources;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final icon = widget.icon;
    final selected = widget.selected;

    return fluent.Expander(
      key: _expanderKey,
      leading: Icon(
        icon,
        size: 18,
        color: selected ? accent : resources.textFillColorSecondary,
      ),
      header: Text(
        widget.title,
        style: TextStyle(
          color: resources.textFillColorPrimary,
          fontSize: 13.5,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      content: widget.content,
      initiallyExpanded: widget.expanded,
      onStateChanged: _handleStateChanged,
      animationDuration: _FluentDrawerTokens.sectionTransition,
      headerBackgroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) => _fluentDrawerStateFill(
          theme,
          states,
          selected: selected,
        ),
      ),
      headerShape: (_) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_FluentDrawerTokens.itemRadius),
      ),
      contentBackgroundColor: Colors.transparent,
      contentPadding: const EdgeInsetsDirectional.only(
        start: _FluentDrawerTokens.sectionIndent,
        end: 2,
        bottom: 4,
      ),
      contentShape: (_) => const RoundedRectangleBorder(),
    );
  }
}

Color _fluentDrawerStateFill(
  fluent.FluentThemeData theme,
  Set<WidgetState> states, {
  required bool selected,
}) {
  final resources = theme.resources;
  final accent = theme.accentColor.defaultBrushFor(theme.brightness);
  if (states.contains(WidgetState.pressed)) {
    return selected
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.18),
            resources.solidBackgroundFillColorBase,
          )
        : resources.subtleFillColorTertiary;
  }
  if (selected) {
    return Color.alphaBlend(
      accent.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.2 : 0.1,
      ),
      resources.solidBackgroundFillColorBase,
    );
  }
  if (states.contains(WidgetState.hovered)) {
    return resources.subtleFillColorSecondary;
  }
  return resources.subtleFillColorTransparent;
}

class CBDrawer extends StatelessWidget {
  final BuildContext parentContext;
  final String? activeTabId;
  final bool isPinned;
  final Function(bool) onPinStateChanged;

  const CBDrawer(
    this.parentContext, {
    Key? key,
    this.activeTabId,
    required this.isPinned,
    required this.onPinStateChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return _CBDrawerContent(
      parentContext: parentContext,
      activeTabId: activeTabId,
      isPinned: isPinned,
      onPinStateChanged: onPinStateChanged,
    );
  }
}

class _CBDrawerContent extends StatefulWidget {
  final BuildContext parentContext;
  final String? activeTabId;
  final bool isPinned;
  final Function(bool) onPinStateChanged;

  const _CBDrawerContent({
    Key? key,
    required this.parentContext,
    this.activeTabId,
    required this.isPinned,
    required this.onPinStateChanged,
  }) : super(key: key);

  @override
  State<_CBDrawerContent> createState() => _CBDrawerContentState();
}

class _CBDrawerContentState extends State<_CBDrawerContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DrawerCubit>().setActiveTab(widget.activeTabId);
    });
  }

  @override
  void didUpdateWidget(covariant _CBDrawerContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTabId != widget.activeTabId) {
      context.read<DrawerCubit>().setActiveTab(widget.activeTabId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktopPlatform =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    final useFluentDesktopShell = isDesktopPlatform &&
        DesignSystemConfig.enableFluentDesktopShell &&
        !DesignSystemConfig.enableLegacyMaterialDesktopShell;
    if (useFluentDesktopShell) {
      return _buildFluentDrawer(context);
    }

    final ThemeData theme = Theme.of(context);
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final Color windowsLightDrawerTopBase = Color.alphaBlend(
      theme.colorScheme.primary.withValues(alpha: 0.01),
      const Color(0xFFFFFFFF),
    );
    const Color windowsLightDrawerBottomBase = Color(0xFFFFFFFF);
    final double topTintAlpha =
        isDesktopPlatform ? (isDarkMode ? 0.84 : 0.70) : 1.0;
    final double bottomTintAlpha =
        isDesktopPlatform ? (isDarkMode ? 0.80 : 0.64) : 0.85;
    final bool usePinnedIntegratedStyle = widget.isPinned && isDesktopPlatform;

    return Drawer(
      elevation: 0,
      backgroundColor: Colors.transparent,
      shape: usePinnedIntegratedStyle
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
      child: ClipRRect(
        borderRadius: usePinnedIntegratedStyle
            ? BorderRadius.zero
            : const BorderRadius.only(
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Overlay drawer keeps its own frosted panel. Pinned drawer stays
            // transparent so it shares the same scaffold acrylic as the rest.
            if (isDesktopPlatform && !usePinnedIntegratedStyle)
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: const SizedBox.expand(),
              ),
            if (!usePinnedIntegratedStyle)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      isDarkMode
                          ? theme.colorScheme.surface
                              .withValues(alpha: topTintAlpha)
                          : windowsLightDrawerTopBase.withValues(
                              alpha: topTintAlpha),
                      isDarkMode
                          ? theme.colorScheme.surfaceContainerLowest
                              .withValues(alpha: bottomTintAlpha)
                          : windowsLightDrawerBottomBase.withValues(
                              alpha: bottomTintAlpha),
                    ],
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: 1,
                  color: theme.colorScheme.outline
                      .withValues(alpha: isDarkMode ? 0.12 : 0.08),
                ),
              ),
            Column(
              children: [
                // Modern drawer header
                DrawerHeaderWidget(
                  isPinned: widget.isPinned,
                  onPinStateChanged: widget.onPinStateChanged,
                ),

                // Scrollable menu items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    children: [
                      // Main navigation items
                      DrawerNavigationItem(
                        icon: PhosphorIconsLight.house,
                        title: context.tr.home,
                        onTap: () => _navigateTo(context, '#home', 'Home'),
                      ),

                      BlocBuilder<DrawerCubit, DrawerState>(
                        builder: (context, drawerState) {
                          return PinnedSectionWidget(
                            key: ValueKey<String>(
                              'pinned-${drawerState.activeTabId}-${drawerState.isPinnedExpanded}',
                            ),
                            onNavigate: (path, name) => _navigateTo(
                              context,
                              path,
                              name,
                              isStorage: true,
                            ),
                            initialExpanded: drawerState.isPinnedExpanded,
                            onExpansionChanged: (isExpanded) {
                              context
                                  .read<DrawerCubit>()
                                  .setPinnedExpanded(isExpanded);
                            },
                          );
                        },
                      ),

                      // Storage section with expansion
                      BlocBuilder<DrawerCubit, DrawerState>(
                        builder: (context, drawerState) {
                          return StorageSectionWidget(
                            key: ValueKey<String>(
                              'storage-${drawerState.activeTabId}-${drawerState.isStorageExpanded}',
                            ),
                            onNavigate: (path, name) => _navigateTo(
                              context,
                              path,
                              name,
                              isStorage: true,
                            ),
                            onTrashTap: () =>
                                _navigateTo(context, '#trash', 'Trash'),
                            initialExpanded: drawerState.isStorageExpanded,
                            onExpansionChanged: (isExpanded) {
                              context
                                  .read<DrawerCubit>()
                                  .setStorageExpanded(isExpanded);
                            },
                          );
                        },
                      ),

                      const SizedBox(height: 8),

                      DrawerNavigationItem(
                        icon: PhosphorIconsLight.image,
                        title: context.tr.imageGallery,
                        onTap: () => _navigateTo(
                          context,
                          '#gallery',
                          context.tr.imageGallery,
                        ),
                      ),

                      DrawerNavigationItem(
                        icon: PhosphorIconsLight.videoCamera,
                        title: context.tr.videoGallery,
                        onTap: () => _navigateTo(
                          context,
                          '#video',
                          context.tr.videoGallery,
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Tags section
                      DrawerNavigationItem(
                        icon: PhosphorIconsLight.tag,
                        title: context.tr.tags,
                        onTap: () => _navigateTo(context, '#tags', 'Tags'),
                      ),

                      DrawerNavigationItem(
                        icon: PhosphorIconsLight.wifiHigh,
                        title: context.tr.networksMenu,
                        onTap: () => _navigateTo(
                            context, '#network', context.tr.networkTab),
                      ),

                      DrawerNavigationItem(
                        icon: PhosphorIconsLight.sparkle,
                        title: context.tr.cbAgent,
                        onTap: () => _navigateToAiChat(context),
                      ),

                      if (Platform.isWindows)
                        DrawerNavigationItem(
                          icon: PhosphorIconsLight.broom,
                          title: context.tr.cbAgentCleanerTitle,
                          onTap: () => _navigateTo(context, '#cb-agent-cleaner',
                              context.tr.cbAgentCleanerTitle),
                        ),

                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.45),
                        ),
                      ),

                      // Settings and info section
                      DrawerNavigationItem(
                        icon: PhosphorIconsLight.gear,
                        title: context.tr.settings,
                        onTap: () {
                          _navigateTo(
                              context, kSettingsPath, context.tr.settings);
                        },
                      ),
                    ],
                  ),
                ),

                // Footer with app info
                _buildDrawerFooter(theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFluentDrawer(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final resources = theme.resources;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final surfaces = FluentSurfaceTokens.of(context);
    final drawerRadius = widget.isPinned
        ? BorderRadius.zero
        : const BorderRadius.only(
            topRight: Radius.circular(_FluentDrawerTokens.outerRadius),
            bottomRight: Radius.circular(_FluentDrawerTokens.outerRadius),
          );

    String? activePath;
    try {
      activePath = context.watch<TabManagerBloc>().state.activeTab?.path;
    } catch (_) {
      // The legacy standalone drawer can be rendered without a tab provider.
    }

    return FluentChromeSurface(
      key: const ValueKey<String>('fluent-drawer-acrylic'),
      tint: surfaces.chromeTint,
      tintAlpha: surfaces.drawerTintAlpha,
      blurSigma: surfaces.chromeBlur,
      borderRadius: drawerRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: surfaces.chromeStroke,
              width: widget.isPinned ? 1 : 0.75,
            ),
          ),
        ),
        child: SizedBox(
          width: _FluentDrawerTokens.width,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildFluentDrawerHeader(
                  context,
                  resources: resources,
                  accent: accent,
                ),
                Expanded(
                  child: BlocBuilder<DrawerCubit, DrawerState>(
                    builder: (context, state) {
                      final hasSelectedPinnedPath = state.pinnedPaths.any(
                        (path) => _isFluentPathSelected(activePath, path),
                      );
                      final hasSelectedStoragePath = state.storageLocations.any(
                        (storage) => _isFluentPathSelected(
                          activePath,
                          storage.path,
                        ),
                      );

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                        children: [
                          _fluentNavigationItem(
                            context,
                            icon: PhosphorIconsLight.house,
                            title: context.tr.home,
                            semanticLabel: context.tr.home,
                            selected: _isFluentPathSelected(
                              activePath,
                              '#home',
                            ),
                            onPressed: () =>
                                _navigateTo(context, '#home', 'Home'),
                          ),
                          const SizedBox(
                            height: _FluentDrawerTokens.groupGap,
                          ),
                          if (state.pinnedPaths.isNotEmpty)
                            _buildFluentSection(
                              context,
                              key: const ValueKey<String>('fluent-pinned'),
                              icon: PhosphorIconsLight.pushPin,
                              title: context.tr.pinnedSection,
                              selected: hasSelectedPinnedPath,
                              expanded: state.isPinnedExpanded,
                              onStateChanged:
                                  context.read<DrawerCubit>().setPinnedExpanded,
                              content: Column(
                                children: state.pinnedPaths
                                    .map(
                                      (path) => _fluentNavigationItem(
                                        context,
                                        icon: _fluentPinnedIcon(path),
                                        title: _fluentPinnedName(path),
                                        semanticLabel: _fluentPinnedName(path),
                                        selected: _isFluentPathSelected(
                                          activePath,
                                          path,
                                        ),
                                        onPressed: () => _navigateTo(
                                          context,
                                          path,
                                          _fluentPinnedName(path),
                                          isStorage: true,
                                        ),
                                        trailing: fluent.Tooltip(
                                          message: context.tr.unpinFromSidebar,
                                          child: Semantics(
                                            button: true,
                                            label: context.tr.unpinFromSidebar,
                                            child: fluent.IconButton(
                                              icon: Icon(
                                                PhosphorIconsLight.pushPinSlash,
                                                size: 14,
                                                color: resources
                                                    .textFillColorSecondary,
                                              ),
                                              iconButtonMode:
                                                  fluent.IconButtonMode.tiny,
                                              onPressed: () => context
                                                  .read<DrawerCubit>()
                                                  .togglePinnedPath(path),
                                            ),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                              ),
                            ),
                          const SizedBox(
                            height: _FluentDrawerTokens.groupGap,
                          ),
                          _buildFluentSection(
                            context,
                            key: const ValueKey<String>('fluent-storage'),
                            icon: PhosphorIconsLight.hardDrives,
                            title: context.tr.drivesTab,
                            selected: hasSelectedStoragePath,
                            expanded: state.isStorageExpanded,
                            onStateChanged:
                                context.read<DrawerCubit>().setStorageExpanded,
                            content: _buildFluentStorageItems(
                              context,
                              state,
                              activePath: activePath,
                            ),
                          ),
                          const SizedBox(
                            height: _FluentDrawerTokens.groupGap,
                          ),
                          _fluentNavigationItem(
                            context,
                            icon: PhosphorIconsLight.image,
                            title: context.tr.imageGallery,
                            semanticLabel: context.tr.imageGallery,
                            selected: _isFluentPathSelected(
                              activePath,
                              '#gallery',
                            ),
                            onPressed: () => _navigateTo(
                              context,
                              '#gallery',
                              context.tr.imageGallery,
                            ),
                          ),
                          _fluentNavigationItem(
                            context,
                            icon: PhosphorIconsLight.videoCamera,
                            title: context.tr.videoGallery,
                            semanticLabel: context.tr.videoGallery,
                            selected: _isFluentPathSelected(
                              activePath,
                              '#video',
                            ),
                            onPressed: () => _navigateTo(
                              context,
                              '#video',
                              context.tr.videoGallery,
                            ),
                          ),
                          const SizedBox(
                            height: _FluentDrawerTokens.groupGap,
                          ),
                          _fluentNavigationItem(
                            context,
                            icon: PhosphorIconsLight.tag,
                            title: context.tr.tags,
                            semanticLabel: context.tr.tags,
                            selected: _isFluentPathSelected(
                              activePath,
                              '#tags',
                            ),
                            onPressed: () =>
                                _navigateTo(context, '#tags', 'Tags'),
                          ),
                          _fluentNavigationItem(
                            context,
                            icon: PhosphorIconsLight.wifiHigh,
                            title: context.tr.networksMenu,
                            semanticLabel: context.tr.networksMenu,
                            selected: _isFluentPathSelected(
                              activePath,
                              '#network',
                            ),
                            onPressed: () => _navigateTo(
                              context,
                              '#network',
                              context.tr.networkTab,
                            ),
                          ),
                          _fluentNavigationItem(
                            context,
                            icon: PhosphorIconsLight.sparkle,
                            title: context.tr.cbAgent,
                            semanticLabel: context.tr.cbAgent,
                            selected: _isFluentPathSelected(
                              activePath,
                              kAiChatPath,
                            ),
                            onPressed: () => _navigateToAiChat(context),
                          ),
                          if (Platform.isWindows)
                            _fluentNavigationItem(
                              context,
                              icon: PhosphorIconsLight.broom,
                              title: context.tr.cbAgentCleanerTitle,
                              semanticLabel: context.tr.cbAgentCleanerTitle,
                              selected: _isFluentPathSelected(
                                activePath,
                                kCbAgentCleanerPath,
                              ),
                              onPressed: () => _navigateTo(
                                context,
                                kCbAgentCleanerPath,
                                context.tr.cbAgentCleanerTitle,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: fluent.Divider(
                              style: fluent.DividerThemeData(
                                decoration: BoxDecoration(
                                  color: resources.dividerStrokeColorDefault,
                                ),
                              ),
                            ),
                          ),
                          _fluentNavigationItem(
                            context,
                            icon: PhosphorIconsLight.gear,
                            title: context.tr.settings,
                            semanticLabel: context.tr.settings,
                            selected: _isFluentPathSelected(
                              activePath,
                              kSettingsPath,
                            ),
                            onPressed: () => _navigateTo(
                              context,
                              kSettingsPath,
                              context.tr.settings,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                _buildFluentDrawerFooter(
                  resources: resources,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFluentDrawerHeader(
    BuildContext context, {
    required fluent.ResourceDictionary resources,
    required Color accent,
  }) {
    final pinLabel =
        widget.isPinned ? context.tr.unpinMenu : context.tr.pinMenu;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: resources.dividerStrokeColorDefault),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 13),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/logo.png',
                height: 32,
                width: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                  ),
                  child: SizedBox(
                    height: 32,
                    width: 32,
                    child: Icon(
                      PhosphorIconsLight.folder,
                      size: 20,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                context.tr.appTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: resources.textFillColorPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: pinLabel,
              child: fluent.Tooltip(
                message: pinLabel,
                child: fluent.IconButton(
                  icon: Icon(
                    widget.isPinned
                        ? PhosphorIconsFill.pushPin
                        : PhosphorIconsLight.pushPin,
                    size: 16,
                    color: resources.textFillColorSecondary,
                  ),
                  iconButtonMode: fluent.IconButtonMode.small,
                  onPressed: () {
                    widget.onPinStateChanged(!widget.isPinned);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFluentSection(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String title,
    required bool selected,
    required bool expanded,
    required ValueChanged<bool> onStateChanged,
    required Widget content,
  }) {
    return FluentDrawerSection(
      key: key,
      icon: icon,
      title: title,
      selected: selected,
      expanded: expanded,
      onStateChanged: onStateChanged,
      content: content,
    );
  }

  Widget _fluentNavigationItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onPressed,
    String? semanticLabel,
    bool selected = false,
    Widget? trailing,
  }) {
    final theme = fluent.FluentTheme.of(context);
    final resources = theme.resources;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);

    return fluent.HoverButton(
      semanticLabel: semanticLabel ?? title,
      cursor: SystemMouseCursors.click,
      onPressed: onPressed,
      builder: (context, states) {
        final isPressed = states.contains(WidgetState.pressed);
        final iconColor =
            selected || isPressed ? accent : resources.textFillColorSecondary;

        return Padding(
          padding: const EdgeInsets.symmetric(
            vertical: _FluentDrawerTokens.itemVerticalMargin,
          ),
          child: fluent.FocusBorder(
            focused: states.contains(WidgetState.focused),
            renderOutside: false,
            child: AnimatedContainer(
              duration: _FluentDrawerTokens.stateTransition,
              curve: Curves.easeOutCubic,
              height: _FluentDrawerTokens.itemHeight,
              decoration: ShapeDecoration(
                color: _fluentDrawerStateFill(
                  theme,
                  states,
                  selected: selected,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    _FluentDrawerTokens.itemRadius,
                  ),
                ),
              ),
              padding: const EdgeInsetsDirectional.only(start: 10, end: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 4,
                    child: Center(
                      child: AnimatedContainer(
                        duration: _FluentDrawerTokens.stateTransition,
                        curve: Curves.easeOutCubic,
                        width: selected ? 3 : 0,
                        height: 20,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, size: 18, color: iconColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: resources.textFillColorPrimary,
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 4),
                    trailing,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFluentStorageItems(
    BuildContext context,
    DrawerState state, {
    String? activePath,
  }) {
    if (state.isLoading) {
      return const Padding(
        padding: EdgeInsetsDirectional.only(top: 8, bottom: 12),
        child: Center(
          child: fluent.ProgressRing(strokeWidth: 2),
        ),
      );
    }
    if (state.storageLocations.isEmpty) {
      return _fluentNavigationItem(
        context,
        icon: PhosphorIconsLight.arrowsClockwise,
        title: context.tr.noStorageLocationsFound,
        semanticLabel: context.tr.noStorageLocationsFound,
        onPressed: () => context.read<DrawerCubit>().loadStorageLocations(),
      );
    }

    return Column(
      children: [
        for (final storage in state.storageLocations)
          _buildFluentStorageItem(
            context,
            storage,
            activePath: activePath,
          ),
        _fluentNavigationItem(
          context,
          icon: PhosphorIconsLight.trash,
          title: context.tr.trashBin,
          semanticLabel: context.tr.trashBin,
          selected: _isFluentPathSelected(activePath, '#trash'),
          onPressed: () => _navigateTo(context, '#trash', context.tr.trashBin),
        ),
      ],
    );
  }

  Widget _buildFluentStorageItem(
    BuildContext context,
    Directory storage, {
    String? activePath,
  }) {
    final displayName = _fluentStorageName(storage);
    final requiresAdmin = storage.requiresAdmin;
    final adminLabel = context.tr.requiresAdminPrivileges;
    final semanticLabel =
        requiresAdmin ? '$displayName, $adminLabel' : displayName;

    return _fluentNavigationItem(
      context,
      icon: storage.path.startsWith('C:')
          ? PhosphorIconsLight.desktop
          : PhosphorIconsLight.hardDrives,
      title: displayName,
      semanticLabel: semanticLabel,
      selected: _isFluentPathSelected(activePath, storage.path),
      trailing: requiresAdmin
          ? _buildFluentAdminIndicator(context, label: adminLabel)
          : null,
      onPressed: () {
        if (requiresAdmin) {
          showStorageAdminAccessDialog(
            context,
            drive: storage,
            onNavigate: (path, name) => _navigateTo(
              context,
              path,
              name,
              isStorage: true,
            ),
          );
          return;
        }
        _navigateTo(
          context,
          storage.path,
          displayName,
          isStorage: true,
        );
      },
    );
  }

  Widget _buildFluentAdminIndicator(
    BuildContext context, {
    required String label,
  }) {
    final theme = fluent.FluentTheme.of(context);
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    return ExcludeSemantics(
      child: fluent.Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 2, end: 2),
          child: Icon(
            PhosphorIconsLight.lockSimple,
            size: 15,
            color: accent,
          ),
        ),
      ),
    );
  }

  Widget _buildFluentDrawerFooter(
      {required fluent.ResourceDictionary resources}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: resources.dividerStrokeColorDefault),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 13),
        child: Row(
          children: [
            Expanded(
              child: FutureBuilder<String>(
                future: _getFullVersion(),
                builder: (context, snapshot) {
                  final version = snapshot.data;
                  return Text(
                    version == null || version.isEmpty
                        ? 'Version'
                        : 'Version $version',
                    style: TextStyle(
                      color: resources.textFillColorSecondary,
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ),
            Text(
              '© CoolBirdZik',
              style: TextStyle(
                color: resources.textFillColorSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isFluentPathSelected(String? activePath, String targetPath) {
    if (activePath == null || activePath.isEmpty) return false;
    if (targetPath == kAiChatPath) return isAiChatPath(activePath);
    if (targetPath.startsWith('#')) return activePath == targetPath;

    final current = _normalizeFluentPath(activePath);
    final target =
        _normalizeFluentPath(_normalizePinnedNavigationPath(targetPath));
    return current == target;
  }

  String _normalizeFluentPath(String path) {
    var normalized = path.trim();
    if (Platform.isWindows) {
      normalized = normalized.replaceAll('/', '\\').toLowerCase();
    }
    while (normalized.length > 1 &&
        (normalized.endsWith('/') || normalized.endsWith('\\'))) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _fluentStorageName(Directory storage) {
    var path = storage.path;
    if (path.length > 1 && path.endsWith(Platform.pathSeparator)) {
      path = path.substring(0, path.length - 1);
    }
    if (Platform.isWindows && path.contains(':')) {
      final drive = path.split(r'\').first;
      return '$drive (${drive.startsWith('C:') ? 'System' : 'Drive'})';
    }
    return path;
  }

  String _fluentPinnedName(String path) {
    var normalized = path;
    if (normalized.endsWith(Platform.pathSeparator) && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final parts = normalized.split(Platform.pathSeparator);
    return parts.where((part) => part.isNotEmpty).isNotEmpty
        ? parts.where((part) => part.isNotEmpty).last
        : normalized;
  }

  IconData _fluentPinnedIcon(String path) {
    try {
      return FileSystemEntity.typeSync(path, followLinks: false) ==
              FileSystemEntityType.file
          ? PhosphorIconsLight.file
          : PhosphorIconsLight.folder;
    } catch (_) {
      return PhosphorIconsLight.pushPin;
    }
  }

  void _navigateTo(BuildContext context, String path, String name,
      {bool isStorage = false}) {
    if (!widget.isPinned) {
      RouteUtils.safePopDialog(context);
    }

    if (isStorage) {
      _openInCurrentTab(context, path, name);
    } else {
      final tabBloc = BlocProvider.of<TabManagerBloc>(context);

      // Check if tab exists for special paths
      if (path.startsWith('#')) {
        final existingTab = tabBloc.state.tabs.firstWhere(
          (tab) => tab.path == path,
          orElse: () => TabData(id: '', name: '', path: ''),
        );

        if (existingTab.id.isNotEmpty) {
          tabBloc.add(SwitchToTab(existingTab.id));
          return;
        }
      }

      // If home, update current tab or create new
      if (path == '#home') {
        final activeTab = tabBloc.state.activeTab;
        if (activeTab != null) {
          tabBloc.add(UpdateTabPath(activeTab.id, '#home'));
          tabBloc.add(UpdateTabName(activeTab.id, 'Home'));
        } else {
          tabBloc.add(AddTab(path: '#home', name: 'Home', switchToTab: true));
        }
        return;
      }

      // Create new tab for others
      tabBloc.add(AddTab(path: path, name: name, switchToTab: true));
    }
  }

  void _navigateToAiChat(BuildContext context) {
    final tabBloc = BlocProvider.of<TabManagerBloc>(context);
    final activePath = tabBloc.state.activeTab?.path ?? '';
    final hasWorkspace = activePath.isNotEmpty && !activePath.startsWith('#');
    final path = hasWorkspace
        ? '#ai-chat?workspace=${Uri.encodeComponent(activePath)}'
        : '#ai-chat';
    _navigateTo(context, path, context.tr.aiChatTab);
  }

  void _openInCurrentTab(BuildContext context, String path, String name) {
    final navigationPath = _normalizePinnedNavigationPath(path);
    final navigationName = navigationPath == path
        ? name
        : navigationPath.split(Platform.pathSeparator).lastWhere(
              (part) => part.isNotEmpty,
              orElse: () => name,
            );

    TabManagerBloc? tabBloc;
    try {
      tabBloc = BlocProvider.of<TabManagerBloc>(context, listen: false);
    } catch (e) {
      tabBloc = null;
    }

    if (tabBloc != null) {
      final activeTab = tabBloc.state.activeTab;
      if (activeTab != null) {
        tabBloc.add(UpdateTabPath(activeTab.id, navigationPath));
        tabBloc.add(UpdateTabName(activeTab.id, navigationName));
      } else {
        tabBloc.add(AddTab(path: navigationPath, name: navigationName));
      }
    } else {
      // Fallback navigation
      Navigator.of(context)
          .pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => const TabMainScreen()),
              (route) => false)
          .then((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          // Note: context might be invalid here, but TabMainScreen.openPath handles it?
          // Actually we should use navigator key or similar if possible, but this is legacy logic
          // Keeping it simple for now
        });
      });
    }
  }

  String _normalizePinnedNavigationPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return path;

    try {
      final type = FileSystemEntity.typeSync(trimmed, followLinks: false);
      if (type == FileSystemEntityType.file) {
        return File(trimmed).parent.path;
      }
    } catch (_) {}

    return path;
  }

  Widget _buildDrawerFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          FutureBuilder<String>(
            future: _getFullVersion(),
            builder: (context, snapshot) {
              final versionText = snapshot.data == null
                  ? 'Version'
                  : 'Version ${snapshot.data}';
              return Text(
                versionText,
                style: TextStyle(
                  color:
                      theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              );
            },
          ),
          Text(
            '© CoolBirdZik',
            style: TextStyle(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getFullVersion() async {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    final build = info.buildNumber.trim();
    if (version.isEmpty && build.isEmpty) {
      return '';
    }
    if (build.isEmpty) {
      return version;
    }
    if (version.isEmpty) {
      return build;
    }
    return '$version.$build';
  }
}
