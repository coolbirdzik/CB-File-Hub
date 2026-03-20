import 'package:flutter/material.dart';
import 'package:cb_file_manager/models/objectbox/video_library.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/screens/video_library/create_video_library_dialog.dart';
import 'package:cb_file_manager/ui/screens/video_library/video_library_settings_screen.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/video_library_helpers.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:io';

/// Video Hub Screen - Main screen for managing video libraries
class VideoHubScreen extends StatefulWidget {
  const VideoHubScreen({Key? key}) : super(key: key);

  @override
  State<VideoHubScreen> createState() => _VideoHubScreenState();
}

class _VideoHubScreenState extends State<VideoHubScreen> {
  final VideoLibraryService _service = VideoLibraryService();
  List<VideoLibrary> _libraries = [];
  bool _isLoading = true;
  int _totalVideos = 0;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  /// Refresh both libraries and video count
  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    final libraries = await _service.getAllLibraries();
    
    if (!mounted) return;
    
    setState(() {
      _libraries = libraries;
    });

    // Load video count for all libraries
    int total = 0;
    for (final library in libraries) {
      final count = await _service.getLibraryVideoCount(library.id);
      total += count;
    }
    
    if (mounted) {
      setState(() {
        _totalVideos = total;
        _isLoading = false;
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
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.deleteVideoLibrary),
        content: Text(localizations.deleteVideoLibraryConfirmation(library.name)),
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
        VideoLibraryHelpers.showSuccessMessage(context, localizations.libraryDeletedSuccessfully);
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoLibrarySettingsScreen(library: library),
      ),
    ).then((_) {
      // Refresh libraries after returning from settings
      _refreshData();
    });
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
            theme.colorScheme.surfaceContainerLowest
                .withValues(alpha: desktopLightAlpha),
            theme.colorScheme.surfaceContainerLow
                .withValues(alpha: desktopLightAlpha),
            Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.02),
              theme.colorScheme.surfaceContainer
                  .withValues(alpha: desktopLightAlpha),
            ).withValues(alpha: desktopLightAlpha),
          ]
        : <Color>[];
    final darkBackgroundColor =
        isDesktopPlatform ? theme.colorScheme.surface.withValues(alpha: 0.30) : theme.colorScheme.surface;

    return Scaffold(
      backgroundColor: isDesktopPlatform
          ? Colors.transparent
          : (isLightMode
              ? theme.colorScheme.surfaceContainerLowest
              : theme.scaffoldBackgroundColor),
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
                : BoxDecoration(
                    color: darkBackgroundColor,
                  )),
        child: RefreshIndicator(
          onRefresh: _refreshData,
          child: CustomScrollView(
            slivers: [
              // Welcome Section
              SliverToBoxAdapter(
                child: _buildWelcomeSection(theme, localizations, isLightMode, isDesktopPlatform),
              ),

              // Libraries Grid
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: _isLoading
                    ? const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _libraries.isEmpty
                        ? SliverFillRemaining(
                            child: _buildEmptyState(theme, localizations, isLightMode, isDesktopPlatform),
                          )
                        : SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 300,
                              mainAxisSpacing: 16,
                              crossAxisSpacing: 16,
                              childAspectRatio: 1.2,
                            ),
                            delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              return _buildLibraryCard(
                                  theme, localizations, _libraries[index], isLightMode, isDesktopPlatform);
                            },
                              childCount: _libraries.length,
                            ),
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

  Widget _buildWelcomeSection(ThemeData theme, AppLocalizations localizations, bool isLightMode, bool isDesktopPlatform) {
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
                        color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isLoading)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: 0.7),
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
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
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

    return FutureBuilder<int>(
      future: _service.getLibraryVideoCount(library.id),
      builder: (context, snapshot) {
        final videoCount = snapshot.data ?? 0;

        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: () => _navigateToLibrary(library),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: isLightMode
                    ? cs.surface.withValues(alpha: isDesktopPlatform ? 0.46 : 1.0)
                    : cs.surface,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with menu
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(
                          PhosphorIconsLight.filmStrip,
                          color: cardColor,
                          size: 32,
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'settings') {
                              _navigateToSettings(library);
                            } else if (value == 'delete') {
                              _deleteLibrary(library);
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'settings',
                              child: Row(
                                children: [
                                  const Icon(PhosphorIconsLight.gear),
                                  const SizedBox(width: 8),
                                  Text(localizations.settings),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(PhosphorIconsLight.trash, color: Theme.of(context).colorScheme.error),
                                  const SizedBox(width: 8),
                                  Text(localizations.delete),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Library info
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            library.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (library.description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              library.description!,
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Footer with count
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
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
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$videoCount ${localizations.videos.toLowerCase()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
      },
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations localizations, bool isLightMode, bool isDesktopPlatform) {
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
          Text(
            localizations.noVideoSources,
            style: theme.textTheme.titleLarge,
          ),
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



