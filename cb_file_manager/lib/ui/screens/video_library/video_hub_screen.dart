import 'package:flutter/material.dart';
import 'package:cb_file_manager/models/objectbox/video_library.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/screens/video_library/create_video_library_dialog.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/video_library_cover.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/video_library_helpers.dart';
import 'package:cb_file_manager/ui/components/common/skeleton.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:io';
import 'package:cb_file_manager/ui/utils/route.dart';

/// Video Hub Screen - Main screen for managing video libraries
class VideoHubScreen extends StatefulWidget {
  final String tabId;

  const VideoHubScreen({super.key, required this.tabId});

  @override
  State<VideoHubScreen> createState() => _VideoHubScreenState();
}

class _VideoHubScreenState extends State<VideoHubScreen> {
  final VideoLibraryService _service = VideoLibraryService();
  final TextEditingController _addressController = TextEditingController(
    text: '#video',
  );
  List<VideoLibrary> _libraries = [];
  Map<int, int> _videoCounts = {};
  bool _isLoading = true;
  bool _isCountsLoading = false;
  int _totalVideos = 0;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  /// Refresh both libraries and video counts.
  ///
  /// Phase 1: Load library metadata from DB (instant).
  /// Phase 2: Load cached file counts from DB config table (instant, no I/O).
  /// Phase 3: Background filesystem scan to refresh stale counts.
  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    final libraries = await _service.getAllLibraries();

    if (!mounted) return;

    // Phase 1 + 2: Show libraries with cached counts immediately
    final cachedCounts = await _service.getCachedLibraryVideoCounts(libraries);

    if (!mounted) return;

    setState(() {
      _libraries = libraries;
      _videoCounts = cachedCounts;
      _totalVideos = cachedCounts.values.fold(0, (sum, c) => sum + c);
      _isLoading = false;
      // Show shimmer only if all cached counts are zero (likely never scanned)
      _isCountsLoading =
          cachedCounts.values.every((c) => c == 0) && libraries.isNotEmpty;
    });

    // Phase 3: Background filesystem scan only for missing/stale counts.
    // UI is already responsive with cached counts.
    final staleLibraries = await _service.getLibrariesNeedingCountRefresh(
      libraries,
    );
    if (staleLibraries.isEmpty) {
      if (mounted) {
        setState(() {
          _isCountsLoading = false;
        });
      }
      return;
    }

    final refreshedCounts = await _service.refreshAllLibraryVideoCounts(
      staleLibraries,
    );
    final freshCounts = <int, int>{...cachedCounts, ...refreshedCounts};

    if (mounted) {
      setState(() {
        _videoCounts = freshCounts;
        _totalVideos = freshCounts.values.fold(0, (sum, c) => sum + c);
        _isCountsLoading = false;
      });
    }
  }

  Future<void> _showCreateLibraryDialog() async {
    final result = await showDialog<VideoLibrary>(
      context: context,
      builder: (context) => const CreateVideoLibraryDialog(),
    );

    if (result != null) {
      _refreshData();
    }
  }

  Future<void> _deleteLibrary(VideoLibrary library) async {
    final localizations = AppLocalizations.of(context)!;

    final confirmed = await RouteUtils.showAcrylicDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.deleteVideoLibrary),
        content: Text(
          localizations.deleteVideoLibraryConfirmation(library.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(localizations.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _service.deleteLibrary(library.id);

      if (success && mounted) {
        VideoLibraryHelpers.showSuccessMessage(
          context,
          localizations.libraryDeletedSuccessfully,
        );
        _refreshData();
      }
    }
  }

  void _navigateToLibrary(VideoLibrary library) {
    // Navigate within current tab to keep tab history
    final tabManager = context.read<TabManagerBloc>();
    final activeTab = tabManager.state.activeTab;

    if (activeTab != null) {
      final path = '#video-library/${library.id}';
      TabNavigator.updateTabPath(context, activeTab.id, path);
      tabManager.add(UpdateTabName(activeTab.id, library.name));
    }
  }

  void _navigateToSettings(VideoLibrary library) {
    // Navigate within current tab so settings stays inside the tab (like the
    // library files screen) instead of covering the app with a pushed route.
    final localizations = AppLocalizations.of(context)!;
    final tabManager = context.read<TabManagerBloc>();
    final activeTab = tabManager.state.activeTab;

    if (activeTab != null) {
      final path = '#video-library-settings/${library.id}';
      TabNavigator.updateTabPath(context, activeTab.id, path);
      tabManager.add(
        UpdateTabName(
          activeTab.id,
          '${library.name} — ${localizations.videoLibrarySettings}',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    // Match home_screen background pattern
    final isLightMode = theme.brightness == Brightness.light;
    final isDesktopPlatform =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final double desktopLightAlpha = isDesktopPlatform ? 0.42 : 1.0;
    final backgroundGradientColors = isLightMode
        ? <Color>[
            theme.colorScheme.surfaceContainerLowest.withValues(
              alpha: desktopLightAlpha,
            ),
            theme.colorScheme.surfaceContainerLow.withValues(
              alpha: desktopLightAlpha,
            ),
            Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.02),
              theme.colorScheme.surfaceContainer.withValues(
                alpha: desktopLightAlpha,
              ),
            ).withValues(alpha: desktopLightAlpha),
          ]
        : <Color>[];
    final darkBackgroundColor = isDesktopPlatform
        ? theme.colorScheme.surface.withValues(alpha: 0.30)
        : theme.colorScheme.surface;

    return Scaffold(
      backgroundColor: isDesktopPlatform
          ? Colors.transparent
          : (isLightMode
                ? theme.colorScheme.surfaceContainerLowest
                : theme.scaffoldBackgroundColor),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: isDesktopPlatform ? Colors.transparent : null,
        elevation: isDesktopPlatform ? 0 : null,
        title: PathNavigationBar(
          tabId: widget.tabId,
          pathController: _addressController,
          onPathSubmitted: (_) {},
          currentPath: '#video',
          tabPath: '#video',
          enablePathEditing: false,
          breadcrumbSegments: [
            BreadcrumbSegment(
              label: localizations.videoGallery,
              icon: PhosphorIconsLight.filmStrip,
            ),
          ],
        ),
      ),
      body: Container(
        decoration: isDesktopPlatform
            ? const BoxDecoration(color: Colors.transparent)
            : (isLightMode
                  ? BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: backgroundGradientColors,
                      ),
                    )
                  : BoxDecoration(color: darkBackgroundColor)),
        child: RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            slivers: [
              // Welcome Section
              SliverToBoxAdapter(
                child: _buildWelcomeSection(
                  theme,
                  localizations,
                  isLightMode,
                  isDesktopPlatform,
                ),
              ),

              // Libraries Grid
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: _isLoading
                    ? SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 300,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.2,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _VideoLibrarySkeletonCard(index: index),
                          childCount: 6,
                        ),
                      )
                    : _libraries.isEmpty
                    ? SliverFillRemaining(
                        child: _buildEmptyState(
                          theme,
                          localizations,
                          isLightMode,
                          isDesktopPlatform,
                        ),
                      )
                    : SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 300,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.2,
                            ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          return _buildLibraryCard(
                            theme,
                            localizations,
                            _libraries[index],
                            isLightMode,
                            isDesktopPlatform,
                          );
                        }, childCount: _libraries.length),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateLibraryDialog,
        tooltip: localizations.createVideoLibrary,
        child: const Icon(PhosphorIconsLight.plus),
      ),
    );
  }

  Widget _buildWelcomeSection(
    ThemeData theme,
    AppLocalizations localizations,
    bool isLightMode,
    bool isDesktopPlatform,
  ) {
    final cs = theme.colorScheme;
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
        : <Color>[];
    final darkWelcomeColor = isDesktopPlatform
        ? cs.surfaceContainerHigh.withValues(alpha: 0.52)
        : cs.surfaceContainerHigh;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
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
                PhosphorIconsLight.filmStrip,
                color: theme.colorScheme.primary,
                size: 30,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.videoHubTitle,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onPrimaryContainer,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      localizations.videoHubWelcome,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer.withValues(
                          alpha: 0.7,
                        ),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isLoading)
                _isCountsLoading
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.7,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            ShimmerBox(
                              width: 40,
                              height: 24,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            const SizedBox(height: 4),
                            ShimmerBox(
                              width: 50,
                              height: 14,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(
                            alpha: 0.7,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '$_totalVideos',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            Text(
                              localizations.videos,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.7,
                                ),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryCard(
    ThemeData theme,
    AppLocalizations localizations,
    VideoLibrary library,
    bool isLightMode,
    bool isDesktopPlatform,
  ) {
    final cs = theme.colorScheme;
    final cardColor = VideoLibraryHelpers.getColorFromHex(
      library.colorTheme,
      theme.colorScheme.primaryContainer,
    );
    final videoCount = _videoCounts[library.id];
    final isDark = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: _LibraryCardContent(
        library: library,
        cardColor: cardColor,
        videoCount: videoCount,
        isDark: isDark,
        isLightMode: isLightMode,
        isDesktopPlatform: isDesktopPlatform,
        cs: cs,
        localizations: localizations,
        onTap: () => _navigateToLibrary(library),
        onSettings: () => _navigateToSettings(library),
        onDelete: () => _deleteLibrary(library),
        context: context,
      ),
    );
  }

  Widget _buildEmptyState(
    ThemeData theme,
    AppLocalizations localizations,
    bool isLightMode,
    bool isDesktopPlatform,
  ) {
    final cs = theme.colorScheme;
    final emptyStateGradientColors = isLightMode
        ? <Color>[
            Color.alphaBlend(
              cs.secondary.withValues(alpha: 0.08),
              cs.surfaceContainerHigh,
            ).withValues(alpha: isDesktopPlatform ? 0.44 : 1.0),
            Color.alphaBlend(
              cs.secondary.withValues(alpha: 0.04),
              cs.surfaceContainer,
            ).withValues(alpha: isDesktopPlatform ? 0.40 : 1.0),
          ]
        : <Color>[];
    final darkEmptyStateColor = isDesktopPlatform
        ? cs.surfaceContainerHigh.withValues(alpha: 0.52)
        : cs.surfaceContainerHigh;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isLightMode ? null : darkEmptyStateColor,
              gradient: isLightMode
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: emptyStateGradientColors,
                    )
                  : null,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              PhosphorIconsLight.filmStrip,
              size: 64,
              color: cs.secondary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          Text(localizations.noVideoSources, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            localizations.createVideoLibrary,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _showCreateLibraryDialog,
            icon: const Icon(PhosphorIconsLight.plus),
            label: Text(localizations.createVideoLibrary),
          ),
        ],
      ),
    );
  }
}

/// Card content widget — separated from state so it can be const-reified.
class _LibraryCardContent extends StatelessWidget {
  final VideoLibrary library;
  final Color cardColor;
  final int? videoCount;
  final bool isDark;
  final bool isLightMode;
  final bool isDesktopPlatform;
  final ColorScheme cs;
  final AppLocalizations localizations;
  final VoidCallback onTap;
  final VoidCallback onSettings;
  final VoidCallback onDelete;
  final BuildContext context;

  const _LibraryCardContent({
    required this.library,
    required this.cardColor,
    required this.videoCount,
    required this.isDark,
    required this.isLightMode,
    required this.isDesktopPlatform,
    required this.cs,
    required this.localizations,
    required this.onTap,
    required this.onSettings,
    required this.onDelete,
    required this.context,
  });

  @override
  Widget build(BuildContext context) {
    // Use static alpha values derived from isDesktopPlatform so the widget
    // can be rebuilt with const semantics when only the count changes.
    final double bgAlpha = isDesktopPlatform ? 0.46 : 1.0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isLightMode
                ? cs.surface.withValues(alpha: bgAlpha)
                : cs.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover banner with overlaid menu
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoLibraryCover(
                      coverImagePath: library.coverImagePath,
                      placeholderIcon: PhosphorIconsLight.filmStrip,
                      accentColor: cardColor,
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _LibraryMenuButton(
                        onSettings: onSettings,
                        onDelete: onDelete,
                        settingsLabel: localizations.settings,
                        deleteLabel: localizations.delete,
                      ),
                    ),
                  ],
                ),
              ),

              // Library info
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      library.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (library.description != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        library.description!,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Footer with count (shimmer while loading)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIconsLight.videoCamera,
                      size: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    if (videoCount == null)
                      const _CountShimmer()
                    else
                      Text(
                        '$videoCount ${localizations.videos.toLowerCase()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
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
}

/// Translucent circular menu button overlaid on the library cover banner.
class _LibraryMenuButton extends StatelessWidget {
  final VoidCallback onSettings;
  final VoidCallback onDelete;
  final String settingsLabel;
  final String deleteLabel;

  const _LibraryMenuButton({
    required this.onSettings,
    required this.onDelete,
    required this.settingsLabel,
    required this.deleteLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
      child: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'settings') {
            onSettings();
          } else if (value == 'delete') {
            onDelete();
          }
        },
        icon: const Icon(Icons.more_vert, size: 18, color: Colors.white),
        itemBuilder: (ctx) => [
          PopupMenuItem(
            value: 'settings',
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.gear),
                const SizedBox(width: 8),
                Text(settingsLabel),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.trash,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Text(deleteLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Static shimmer for the video count placeholder.
class _CountShimmer extends StatelessWidget {
  const _CountShimmer();

  @override
  Widget build(BuildContext context) {
    return ShimmerBox(
      width: 60,
      height: 14,
      borderRadius: BorderRadius.circular(4),
    );
  }
}

/// Skeleton card matching the layout of a real library card
class _VideoLibrarySkeletonCard extends StatelessWidget {
  final int index;

  const _VideoLibrarySkeletonCard({required this.index});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header skeleton (icon + menu)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShimmerBox(
                    width: 32,
                    height: 32,
                    borderRadius: BorderRadius.circular(8),
                    delay: Duration(milliseconds: (index * 80).clamp(0, 480)),
                  ),
                  ShimmerBox(
                    width: 24,
                    height: 24,
                    borderRadius: BorderRadius.circular(12),
                    delay: Duration(
                      milliseconds: (index * 80 + 40).clamp(0, 520),
                    ),
                  ),
                ],
              ),
            ),

            // Body skeleton (title + description)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShimmerBox(
                      width: double.infinity,
                      height: 20,
                      borderRadius: BorderRadius.circular(6),
                      delay: Duration(
                        milliseconds: (index * 80 + 80).clamp(0, 560),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ShimmerBox(
                      width: 120,
                      height: 14,
                      borderRadius: BorderRadius.circular(4),
                      delay: Duration(
                        milliseconds: (index * 80 + 120).clamp(0, 600),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Footer skeleton (video count)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.15,
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  ShimmerBox(
                    width: 16,
                    height: 16,
                    borderRadius: BorderRadius.circular(4),
                    delay: Duration(
                      milliseconds: (index * 80 + 160).clamp(0, 640),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ShimmerBox(
                    width: 70,
                    height: 14,
                    borderRadius: BorderRadius.circular(4),
                    delay: Duration(
                      milliseconds: (index * 80 + 200).clamp(0, 680),
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
}
