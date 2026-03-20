import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/helpers/platform_paths.dart';
import 'package:cb_file_manager/services/featured_albums_service.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';
import 'package:cb_file_manager/ui/screens/settings/featured_albums_settings_screen.dart';

import 'dart:io';

class GalleryHubScreen extends StatefulWidget {
  const GalleryHubScreen({Key? key}) : super(key: key);

  @override
  State<GalleryHubScreen> createState() => _GalleryHubScreenState();
}

class _GalleryHubScreenState extends State<GalleryHubScreen>
    with TickerProviderStateMixin {
  int _totalImages = 0;
  bool _isLoading = true;
  List<Album> _featuredAlbums = [];
  bool _loadingFeaturedAlbums = true;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AppLocalizations _localizations;
  late BuildContext _context;

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
    _loadImageCount();
    _loadFeaturedAlbums();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _loadImageCount() async {
    try {
      final count = await _countAllImages();
      if (mounted) {
        setState(() {
          _totalImages = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadFeaturedAlbums() async {
    try {
      final albums = await FeaturedAlbumsService.instance.getFeaturedAlbums();
      if (mounted) {
        setState(() {
          _featuredAlbums = albums;
          _loadingFeaturedAlbums = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingFeaturedAlbums = false;
        });
      }
    }
  }

  Future<int> _countAllImages() async {
    int count = 0;
    final commonPaths = [
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Pictures',
      '/storage/emulated/0/Download',
    ];

    for (final path in commonPaths) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          await for (final entity in dir.list(recursive: true)) {
            if (entity is File && _isImageFile(entity.path)) {
              count++;
            }
          }
        }
      } catch (e) {
        // Ignore errors for individual directories
      }
    }
    return count;
  }

  bool _isImageFile(String path) {
    final extension = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension);
  }

  @override
  Widget build(BuildContext context) {
    _context = context; // Initialize context field
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;
    _localizations = localizations; // Initialize localizations field
    final size = MediaQuery.of(context).size;

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
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Welcome section - full width
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width > 800 ? 32 : 16,
                      vertical: 24,
                    ),
                    child: _buildWelcomeSection(theme, isLightMode, isDesktopPlatform),
                  ),

                  // Gallery actions
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width > 800 ? 48 : 20,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildGalleryActions(theme, localizations),
                        const SizedBox(height: 40),

                        // Featured albums
                        if (_featuredAlbums.isNotEmpty || _loadingFeaturedAlbums)
                          _buildFeaturedAlbums(theme),
                        if (_featuredAlbums.isNotEmpty || _loadingFeaturedAlbums)
                          const SizedBox(height: 40),

                        // Stats overview
                        _buildStatsOverview(theme),
                        const SizedBox(height: 32),
                      ],
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

  Widget _buildWelcomeSection(ThemeData theme, bool isLightMode, bool isDesktopPlatform) {
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
      width: double.infinity,
      padding: const EdgeInsets.all(28),
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
                PhosphorIconsLight.images,
                color: cs.primary,
                size: 32,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _localizations.galleryHub,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onPrimaryContainer,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _localizations.managePhotosAndAlbums,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onPrimaryContainer.withValues(alpha: 0.7),
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
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$_totalImages',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                      Text(
                        _localizations.images,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.7),
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

  Widget _buildGalleryActions(ThemeData theme, AppLocalizations localizations) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
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
              localizations.galleryActions,
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
                localizations.quickAccess,
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
                  PlatformPaths.getAllImagesDisplayName(),
                  PlatformPaths.isDesktop
                      ? _localizations.browseAllYourPictures
                      : _localizations.browseAllYourPhotos,
                  PhosphorIconsLight.image,
                  [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.7)],
                  () => _navigateToAllImages(),
                ),
                _buildActionCard(
                  theme,
                  'Albums',
                  _localizations.organizeInAlbums,
                  PhosphorIconsLight.folder,
                  [theme.colorScheme.tertiary, theme.colorScheme.tertiary.withValues(alpha: 0.7)],
                  () => _navigateToAlbums(),
                ),
                _buildActionCard(
                  theme,
                  PlatformPaths.getCameraDisplayName(),
                  PlatformPaths.isDesktop
                      ? _localizations.picturesFolder
                      : _localizations.photosFromCamera,
                  PhosphorIconsLight.camera,
                  [theme.colorScheme.tertiary, theme.colorScheme.tertiary.withValues(alpha: 0.7)],
                  () => _navigateToCamera(),
                ),
                _buildActionCard(
                  theme,
                  PlatformPaths.getDownloadsDisplayName(),
                  PlatformPaths.isDesktop
                      ? _localizations.downloadedFiles
                      : _localizations.downloadedImages,
                  PhosphorIconsLight.downloadSimple,
                  [theme.colorScheme.secondary, theme.colorScheme.secondary.withValues(alpha: 0.7)],
                  () => _navigateToDownloads(),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adjust padding and spacing for smaller screens
        final isMobile = constraints.maxWidth < 200;
        final cardPadding = isMobile ? 12.0 : 20.0;
        final iconPadding = isMobile ? 10.0 : 12.0;
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
                color: theme.colorScheme.surface.withValues(alpha: 0.4),
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

  Widget _buildFeaturedAlbums(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 32,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.colorScheme.secondary,
                    theme.colorScheme.secondary.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              _localizations.featuredAlbums,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                _localizations.personalized,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(PhosphorIconsLight.gear,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: () => _openFeaturedAlbumsSettings(),
              tooltip: _localizations.configureFeaturedAlbums,
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_loadingFeaturedAlbums)
          const Center(child: CircularProgressIndicator())
        else if (_featuredAlbums.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.1),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  PhosphorIconsLight.folder,
                  size: 48,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 16),
                Text(
                  _localizations.noFeaturedAlbums,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _localizations.createSomeAlbumsToSeeThemFeaturedHere,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxis = 2;
              if (constraints.maxWidth > 1200) {
                crossAxis = 4;
              } else if (constraints.maxWidth > 900) {
                crossAxis = 3;
              }

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxis,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 1.1,
                ),
                itemCount: _featuredAlbums.length,
                itemBuilder: (context, index) {
                  final album = _featuredAlbums[index];
                  return _buildFeaturedAlbumCard(theme, album);
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildFeaturedAlbumCard(ThemeData theme, Album album) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _navigateToAlbum(album),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    PhosphorIconsLight.folder,
                    size: 22,
                    color: theme.colorScheme.secondary,
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: Icon(
                      PhosphorIconsLight.dotsThreeVertical,
                      size: 16,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    onSelected: (value) {
                      if (value == 'remove') {
                        _removeFromFeatured(album);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'remove',
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsLight.star, size: 16),
                            const SizedBox(width: 8),
                            Text(_localizations.removeFromFeatured),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      album.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (album.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        album.description!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsOverview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsLight.chartBar,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                _localizations.galleryStatistics,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    theme,
                    _localizations.totalImages,
                    '$_totalImages',
                    PhosphorIconsLight.image,
                    theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    theme,
                    _localizations.albums,
                    '0', // TODO: Get actual album count
                    PhosphorIconsLight.folder,
                    theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToAllImages() async {
    final path = await PlatformPaths.getAllImagesPath();
    final displayName = PlatformPaths.getAllImagesDisplayName();
    if (!mounted) return;
    final tabBloc = BlocProvider.of<TabManagerBloc>(_context);
    final activeTab = tabBloc.state.activeTab;
    if (activeTab != null) {
      TabNavigator.updateTabPath(_context, activeTab.id, path);
      tabBloc.add(UpdateTabName(activeTab.id, displayName));
    } else {
      // Fallback: if no active tab exists, create one
      tabBloc.add(AddTab(
        path: path,
        name: displayName,
        switchToTab: true,
      ));
    }
  }

  void _navigateToAlbums() {
    // Navigate within current tab to Albums (#albums)
    final tabBloc = BlocProvider.of<TabManagerBloc>(_context);
    final activeTab = tabBloc.state.activeTab;
    if (activeTab != null) {
      TabNavigator.updateTabPath(_context, activeTab.id, '#albums');
      tabBloc.add(UpdateTabName(activeTab.id, 'Albums'));
    } else {
      // Fallback: if no active tab exists, create one
      tabBloc.add(AddTab(
        path: '#albums',
        name: 'Albums',
        switchToTab: true,
      ));
    }
  }

  void _navigateToCamera() async {
    // Navigate within current tab to maintain navigation history
    final path = await PlatformPaths.getCameraPath();
    final displayName = PlatformPaths.getCameraDisplayName();
    if (!mounted) return;
    final tabBloc = BlocProvider.of<TabManagerBloc>(_context);
    final activeTab = tabBloc.state.activeTab;
    if (activeTab != null) {
      TabNavigator.updateTabPath(_context, activeTab.id, path);
      tabBloc.add(UpdateTabName(activeTab.id, displayName));
    } else {
      // Fallback: if no active tab exists, create one
      tabBloc.add(AddTab(
        path: path,
        name: displayName,
        switchToTab: true,
      ));
    }
  }

  void _navigateToDownloads() async {
    // Navigate within current tab to maintain navigation history
    final path = await PlatformPaths.getDownloadsPath();
    final displayName = PlatformPaths.getDownloadsDisplayName();
    if (!mounted) return;
    final tabBloc = BlocProvider.of<TabManagerBloc>(_context);
    final activeTab = tabBloc.state.activeTab;
    if (activeTab != null) {
      TabNavigator.updateTabPath(_context, activeTab.id, path);
      tabBloc.add(UpdateTabName(activeTab.id, displayName));
    } else {
      // Fallback: if no active tab exists, create one
      tabBloc.add(AddTab(
        path: path,
        name: displayName,
        switchToTab: true,
      ));
    }
  }

  void _navigateToAlbum(Album album) {
    // Navigate to album detail within the same tab using system path router
    final tabBloc = BlocProvider.of<TabManagerBloc>(_context);
    final activeTab = tabBloc.state.activeTab;
    final path = '#album/${album.id}';
    if (activeTab != null) {
      TabNavigator.updateTabPath(_context, activeTab.id, path);
      tabBloc.add(UpdateTabName(activeTab.id, album.name));
    } else {
      // Fallback: no active tab, open as new tab
      tabBloc.add(AddTab(
        path: path,
        name: album.name,
        switchToTab: true,
      ));
    }
  }

  void _removeFromFeatured(Album album) async {
    final success =
        await FeaturedAlbumsService.instance.removeFromFeatured(album.id);
    if (success && mounted) {
      // Reload featured albums
      _loadFeaturedAlbums();
      ScaffoldMessenger.of(_context).showSnackBar(
        SnackBar(
          content: Text('${album.name} removed from featured albums'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              await FeaturedAlbumsService.instance.addToFeatured(album.id);
              _loadFeaturedAlbums();
            },
          ),
        ),
      );
    }
  }

  void _openFeaturedAlbumsSettings() async {
    await Navigator.push(
      _context,
      MaterialPageRoute(
        builder: (context) => const FeaturedAlbumsSettingsScreen(),
      ),
    );
    // Reload featured albums when returning from settings
    _loadFeaturedAlbums();
  }
}



