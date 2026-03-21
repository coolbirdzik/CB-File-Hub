import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'dart:io';

/// Simple home screen that doesn't scan file system to avoid performance issues
class HomeScreen extends StatefulWidget {
  final String tabId;

  const HomeScreen({
    Key? key,
    required this.tabId,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isLightMode = theme.brightness == Brightness.light;
    final isDesktopPlatform =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final localizations = AppLocalizations.of(context)!;
    final size = MediaQuery.of(context).size;

    const desktopUnifiedBackgroundColor = Colors.transparent;
    final double desktopLightAlpha = isDesktopPlatform ? 0.42 : 1.0;
    final backgroundGradientColors = isLightMode
        ? <Color>[
            cs.surfaceContainerLowest.withValues(alpha: desktopLightAlpha),
            cs.surfaceContainerLow.withValues(alpha: desktopLightAlpha),
            Color.alphaBlend(
              cs.primary.withValues(alpha: 0.02),
              cs.surfaceContainer.withValues(alpha: desktopLightAlpha),
            ).withValues(alpha: desktopLightAlpha),
          ]
        : const <Color>[];
    final darkBackgroundColor =
        isDesktopPlatform ? cs.surface.withValues(alpha: 0.30) : cs.surface;

    return Scaffold(
      backgroundColor: isDesktopPlatform
          ? Colors.transparent
          : (isLightMode
              ? cs.surfaceContainerLowest
              : theme.scaffoldBackgroundColor),
      body: Container(
        decoration: isDesktopPlatform
            ? const BoxDecoration(color: desktopUnifiedBackgroundColor)
            : (isLightMode
                ? BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: backgroundGradientColors,
                    ),
                  )
                : BoxDecoration(
                    color: darkBackgroundColor,
                  )),
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: size.width > 800 ? 48 : 20,
                vertical: 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Welcome section
                      _buildWelcomeSection(theme),
                      const SizedBox(height: 40),

                      // Quick actions
                      _buildQuickActions(theme, localizations),
                      const SizedBox(height: 40),

                      // Pinned items
                      _buildPinnedSection(theme, localizations),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(ThemeData theme) {
    final cs = theme.colorScheme;
    final isLightMode = theme.brightness == Brightness.light;
    final isDesktopPlatform =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final welcomeGradientColors = isLightMode
        ? <Color>[
            Color.alphaBlend(
              cs.primary.withValues(alpha: 0.09),
              cs.surfaceContainerHigh,
            ).withValues(alpha: isDesktopPlatform ? 0.44 : 1.0),
            Color.alphaBlend(
              cs.primary.withValues(alpha: 0.05),
              cs.surfaceContainer,
            ).withValues(alpha: isDesktopPlatform ? 0.40 : 1.0),
          ]
        : const <Color>[];
    final darkWelcomeColor = isDesktopPlatform
        ? cs.surfaceContainerHigh.withValues(alpha: 0.52)
        : cs.surfaceContainerHigh;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isLightMode ? null : darkWelcomeColor,
        gradient: isLightMode
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: welcomeGradientColors,
              )
            : null,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsLight.house,
                color: cs.primary,
                size: 32,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr.welcomeTitle,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onPrimaryContainer,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr.welcomeSubtitle,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isLightMode
                  ? cs.surfaceContainerHighest.withValues(
                      alpha: isDesktopPlatform ? 0.44 : 0.75,
                    )
                  : cs.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.lightbulb,
                  color: cs.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr.quickActionsTip,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(ThemeData theme, AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              context.tr.quickActionsHome,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                context.tr.startHere,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            int crossAxis = 2;
            double aspectRatio = 1.2;

            if (constraints.maxWidth > 1200) {
              crossAxis = 4;
              aspectRatio = 1.2;
            } else if (constraints.maxWidth > 900) {
              crossAxis = 3;
              aspectRatio = 1.2;
            } else if (constraints.maxWidth > 600) {
              crossAxis = 2;
              aspectRatio = 1.1;
            } else {
              // Mobile screens - need more vertical space
              crossAxis = 2;
              aspectRatio = 0.95;
            }

            return GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxis,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: aspectRatio,
              ),
              children: [
                _buildActionCard(
                  theme,
                  context.tr.newTabAction,
                  context.tr.newTabActionDesc,
                  PhosphorIconsLight.plusCircle,
                  [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.7)
                  ],
                  () => _openNewTab(),
                ),
                _buildActionCard(
                  theme,
                  localizations.browseFiles,
                  localizations.browseFilesDescription,
                  PhosphorIconsLight.folder,
                  [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.7)
                  ],
                  () => _navigateToPath(''),
                ),
                _buildActionCard(
                  theme,
                  localizations.imageGallery,
                  localizations.manageMediaDescription,
                  PhosphorIconsLight.image,
                  [
                    theme.colorScheme.tertiary,
                    theme.colorScheme.tertiary.withValues(alpha: 0.7)
                  ],
                  () => _openImageGallery(),
                ),
                _buildActionCard(
                  theme,
                  localizations.videoGallery,
                  localizations.manageMediaDescription,
                  PhosphorIconsLight.videoCamera,
                  [
                    theme.colorScheme.secondary,
                    theme.colorScheme.secondary.withValues(alpha: 0.7)
                  ],
                  () => _openVideoGallery(),
                ),
                _buildActionCard(
                  theme,
                  context.tr.tagsAction,
                  context.tr.tagsActionDesc,
                  PhosphorIconsLight.tag,
                  [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.7)
                  ],
                  () => _openTagsTab(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCard(
    ThemeData theme,
    String title,
    String description,
    IconData icon,
    List<Color> gradientColors,
    VoidCallback onTap,
  ) {
    final isDesktopPlatform =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isLightMode = theme.brightness == Brightness.light;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adjust padding and spacing for smaller screens
        final isMobile = constraints.maxWidth < 200;
        final cardPadding = isMobile ? 12.0 : 20.0;
        final iconSize = isMobile ? 20.0 : 24.0;
        final spacing = isMobile ? 8.0 : 12.0;

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.all(cardPadding),
              decoration: BoxDecoration(
                color: isLightMode
                    ? theme.colorScheme.surface.withValues(
                        alpha: isDesktopPlatform ? 0.46 : 1.0,
                      )
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: iconSize + 4,
                    color: gradientColors[0],
                  ),
                  SizedBox(height: spacing),
                  Flexible(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: isMobile ? 13 : null,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: isMobile ? 11 : null,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPinnedSection(ThemeData theme, AppLocalizations localizations) {
    final cs = theme.colorScheme;
    final isDesktopPlatform =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isLightMode = theme.brightness == Brightness.light;
    return BlocBuilder<DrawerCubit, DrawerState>(
      builder: (context, state) {
        if (state.pinnedPaths.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isLightMode
                  ? cs.surface.withValues(alpha: isDesktopPlatform ? 0.46 : 1.0)
                  : cs.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPinnedHeader(theme, localizations, cs),
                const SizedBox(height: 24),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "No pinned items yet",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isLightMode
                ? cs.surface.withValues(alpha: isDesktopPlatform ? 0.46 : 1.0)
                : cs.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPinnedHeader(theme, localizations, cs),
              const SizedBox(height: 24),
              ...state.pinnedPaths.map((path) => _buildPinnedItem(
                    theme,
                    path,
                    _iconForPinnedPath(path),
                    _getPinnedDisplayName(path),
                    () => _navigateToPath(path),
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPinnedHeader(
      ThemeData theme, AppLocalizations localizations, ColorScheme cs) {
    return Row(
      children: [
        Icon(
          PhosphorIconsLight.pushPin,
          color: cs.primary,
          size: 24,
        ),
        const SizedBox(width: 16),
        Text(
          localizations.pinnedSection,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildPinnedItem(
    ThemeData theme,
    String path,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    final isDesktopPlatform =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isLightMode = theme.brightness == Brightness.light;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isLightMode
            ? theme.colorScheme.surface
                .withValues(alpha: isDesktopPlatform ? 0.46 : 1.0)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        path,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsLight.pushPinSlash, size: 20),
                  onPressed: () {
                    context.read<DrawerCubit>().togglePinnedPath(path);
                  },
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconForPinnedPath(String path) {
    try {
      final entityType = FileSystemEntity.typeSync(path, followLinks: false);
      if (entityType == FileSystemEntityType.file) {
        return PhosphorIconsLight.file;
      }
      if (entityType == FileSystemEntityType.directory) {
        return PhosphorIconsLight.folder;
      }
    } catch (_) {}
    return PhosphorIconsLight.pushPin;
  }

  String _getPinnedDisplayName(String path) {
    var normalized = path;
    if (normalized.endsWith(Platform.pathSeparator) && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (Platform.isWindows && RegExp(r'^[a-zA-Z]:$').hasMatch(normalized)) {
      return normalized;
    }
    if (normalized == '/') return '/';
    final parts = normalized.split(Platform.pathSeparator);
    return parts.where((part) => part.isNotEmpty).isNotEmpty
        ? parts.where((part) => part.isNotEmpty).last
        : normalized;
  }

  void _openImageGallery() {
    // Navigate to Gallery Hub within the current tab to maintain navigation history
    final tabManager = context.read<TabManagerBloc>();
    final activeTab = tabManager.state.activeTab;
    if (activeTab != null) {
      TabNavigator.updateTabPath(context, activeTab.id, '#gallery');
      tabManager.add(UpdateTabName(activeTab.id, 'Gallery Hub'));
    } else {
      // Fallback: create new tab if no active tab exists
      tabManager.add(AddTab(
        path: '#gallery',
        name: 'Gallery Hub',
      ));
    }
  }

  void _openVideoGallery() {
    final tabManager = context.read<TabManagerBloc>();
    final activeTab = tabManager.state.activeTab;
    if (activeTab != null) {
      TabNavigator.updateTabPath(context, activeTab.id, '#video');
      tabManager.add(UpdateTabName(activeTab.id, 'Video Hub'));
    } else {
      tabManager.add(AddTab(
        path: '#video',
        name: 'Video Hub',
      ));
    }
  }

  void _openNewTab() async {
    if (!mounted) return;

    // Always open new tab with home page
    final tabBloc = context.read<TabManagerBloc>();
    tabBloc.add(AddTab(path: '#home', name: context.tr.homeTab));
  }

  void _navigateToPath(String path) async {
    final tabBloc = context.read<TabManagerBloc>();
    final activeTab = tabBloc.state.activeTab;

    final targetPath = path.isEmpty ? kDrivesPath : path;
    final tabName = isDrivesPath(targetPath)
        ? context.tr.drivesTab
        : targetPath.split('/').last;

    if (!mounted) return;

    if (activeTab != null) {
      // Update existing tab path
      TabNavigator.updateTabPath(context, activeTab.id, targetPath);
      tabBloc.add(UpdateTabName(activeTab.id, tabName));
    } else {
      // Create new tab if no active tab exists
      tabBloc.add(AddTab(
        path: targetPath,
        name: tabName,
        switchToTab: true,
      ));
    }
  }

  void _openTagsTab() {
    final tabBloc = context.read<TabManagerBloc>();
    final activeTab = tabBloc.state.activeTab;

    if (activeTab != null) {
      // Navigate within the current tab to maintain navigation history
      TabNavigator.updateTabPath(context, activeTab.id, '#tags');
      tabBloc.add(UpdateTabName(activeTab.id, 'Tags'));
    } else {
      // Fallback: create new tab if no active tab exists
      tabBloc.add(
        AddTab(
          path: '#tags',
          name: 'Tags',
          switchToTab: true,
        ),
      );
    }
  }
}
