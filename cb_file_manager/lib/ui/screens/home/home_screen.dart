import 'package:cb_file_manager/services/media_library_updates.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_paths.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:cb_file_manager/ui/widgets/drawer/cubit/drawer_cubit.dart';
import 'package:cb_file_manager/services/home_content_service.dart';

import 'home_media_card.dart';

class HomeScreen extends StatefulWidget {
  final String tabId;
  final HomeContentService? contentService;

  const HomeScreen({super.key, required this.tabId, this.contentService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryController;
  late final HomeContentService _content;
  List<String> _recentPaths = const [];
  HomeMediaPreviews _previews = const HomeMediaPreviews();
  bool _loadingRecent = true;
  bool _recentFailed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _content = widget.contentService ?? HomeContentService();
    MediaLibraryUpdates.revision.addListener(_onLibraryChanged);
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _entryController.value = 1;
      } else {
        _entryController.forward();
      }
      unawaited(_loadContent());
    });
  }

  void _onLibraryChanged() {
    if (mounted) unawaited(_loadContent());
  }

  Future<void> _loadContent() async {
    final generation = ++_loadGeneration;
    setState(() {
      _previews = const HomeMediaPreviews();
      _loadingRecent = true;
      _recentFailed = false;
    });
    var paths = <String>[];
    try {
      paths = await _content.loadRecentPaths();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _recentPaths = paths;
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loadingRecent = false;
        _recentFailed = true;
      });
    }
    try {
      final previews = await _content.loadMediaPreviews(paths);
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _previews = previews);
    } catch (_) {
      // Library navigation remains available without previews.
    }
  }

  @override
  void dispose() {
    MediaLibraryUpdates.revision.removeListener(_onLibraryChanged);
    _entryController.dispose();
    super.dispose();
  }

  Widget _enter(int index, Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final animation = _entryController.drive(
      CurveTween(
        curve: Interval(
          index * 0.10,
          0.70 + index * 0.10,
          curve: CbCurves.standard,
        ),
      ),
    );
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: animation.drive(
          Tween(begin: const Offset(0, 0.035), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.tr;
    return BlocListener<TabManagerBloc, TabManagerState>(
      listenWhen: (previous, current) =>
          previous.activeTabId != current.activeTabId &&
          current.activeTabId == widget.tabId,
      listener: (_, _) => unawaited(_loadContent()),
      child: FileViewShell(
        viewMode: ViewMode.grid,
        enableKeyboardShortcuts: false,
        onMouseBack: () =>
            context.read<TabManagerBloc>().backNavigationToPath(widget.tabId),
        onMouseForward: () => context
            .read<TabManagerBloc>()
            .forwardNavigationToPath(widget.tabId),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: constraints.maxWidth > 800 ? 40 : 20,
                  vertical: 28,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _enter(0, _buildWelcomeSection(theme)),
                        const SizedBox(height: 28),
                        _enter(1, _buildRecentSection(theme)),
                        const SizedBox(height: 28),
                        _enter(
                          2,
                          LayoutBuilder(
                            builder: (context, space) {
                              final photos = HomeMediaCard(
                                key: const ValueKey('home-photos'),
                                title: l10n.imageGallery,
                                subtitle: l10n.homePhotosSubtitle,
                                previews: _previews.images,
                                onPressed: _openImageGallery,
                              );
                              final videos = HomeMediaCard(
                                key: const ValueKey('home-videos'),
                                title: l10n.videoGallery,
                                subtitle: l10n.homeVideosSubtitle,
                                previews: [
                                  if (_previews.videoCover != null)
                                    _previews.videoCover!,
                                ],
                                video: true,
                                onPressed: _openVideoGallery,
                              );
                              if (space.maxWidth < 620) {
                                return Column(
                                  children: [
                                    photos,
                                    const SizedBox(height: 16),
                                    videos,
                                  ],
                                );
                              }
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 6, child: photos),
                                  const SizedBox(width: 16),
                                  Expanded(flex: 5, child: videos),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 28),
                        _enter(3, _buildPinnedSection(theme, l10n)),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeSection(ThemeData theme) {
    final l10n = context.tr;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.welcomeTitle,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.homeSubtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            CbButton(
              label: l10n.browseFiles,
              icon: PhosphorIconsLight.folderOpen,
              onPressed: () => _navigateToPath(''),
              size: CbButtonSize.lg,
              variant: CbButtonVariant.primary,
            ),
            CbButton(
              label: l10n.newTabAction,
              icon: PhosphorIconsLight.plus,
              onPressed: _openNewTab,
              size: CbButtonSize.lg,
            ),
            CbButton(
              label: l10n.tagsAction,
              icon: PhosphorIconsLight.tag,
              onPressed: _openTagsTab,
              size: CbButtonSize.lg,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentSection(ThemeData theme) {
    final l10n = context.tr;
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.homeRecentFolders,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (_loadingRecent)
          Semantics(
            label: l10n.loading,
            child: Row(
              children: [
                for (var i = 0; i < 2; i++)
                  Expanded(
                    child: Container(
                      height: 76,
                      margin: EdgeInsets.only(right: i == 0 ? 12 : 0),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
              ],
            ),
          )
        else if (_recentFailed)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.homeRecentUnavailable,
                style: theme.textTheme.bodyMedium,
              ),
              CbButton(
                label: l10n.retry,
                onPressed: () => unawaited(_loadContent()),
              ),
            ],
          )
        else if (_recentPaths.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              l10n.homeRecentEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, space) {
              final columns = space.maxWidth >= 900
                  ? 3
                  : (space.maxWidth >= 560 ? 2 : 1);
              final width = (space.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final path in _recentPaths)
                    SizedBox(
                      width: width,
                      child: CbPressable(
                        tooltip: path,
                        onPressed: () => _navigateToPath(path),
                        builder: (context, state) => AnimatedContainer(
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : CbDurations.fast,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: state.pressed
                                ? cs.primary.withValues(alpha: 0.13)
                                : (state.hovered
                                      ? cs.primary.withValues(alpha: 0.08)
                                      : cs.surface.withValues(alpha: 0.55)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: state.focused
                                  ? cs.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIconsLight.folder,
                                color: cs.primary,
                                size: 26,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getPinnedDisplayName(path),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      path,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
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
                      localizations.homePinnedEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
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
              ...state.pinnedPaths.map(
                (path) => _buildPinnedItem(
                  theme,
                  path,
                  _iconForPinnedPath(path),
                  _getPinnedDisplayName(path),
                  () => _navigateToPath(path),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPinnedHeader(
    ThemeData theme,
    AppLocalizations localizations,
    ColorScheme cs,
  ) {
    return Row(
      children: [
        Icon(PhosphorIconsLight.pushPin, color: cs.primary, size: 24),
        const SizedBox(width: 16),
        Text(
          localizations.pinnedSection,
          style: theme.textTheme.titleMedium?.copyWith(
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
            ? theme.colorScheme.surface.withValues(
                alpha: isDesktopPlatform ? 0.46 : 1.0,
              )
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
                  child: Icon(icon, color: theme.colorScheme.primary, size: 20),
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
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.7,
                          ),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr.unpinFromSidebar,
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
    final parts = normalized.split(RegExp(r'[/\\]'));
    return parts.where((part) => part.isNotEmpty).isNotEmpty
        ? parts.where((part) => part.isNotEmpty).last
        : normalized;
  }

  void _openImageGallery() {
    // Navigate to Gallery Hub within the current tab to maintain navigation history
    final tabManager = context.read<TabManagerBloc>();
    final activeTab = tabManager.state.tabs
        .where((tab) => tab.id == widget.tabId)
        .firstOrNull;
    if (activeTab != null) {
      TabNavigator.updateTabPath(context, activeTab.id, '#gallery');
      tabManager.add(UpdateTabName(activeTab.id, context.tr.imageGallery));
    } else {
      // Fallback: create new tab if no active tab exists
      tabManager.add(AddTab(path: '#gallery', name: context.tr.imageGallery));
    }
  }

  void _openVideoGallery() {
    final tabManager = context.read<TabManagerBloc>();
    final activeTab = tabManager.state.tabs
        .where((tab) => tab.id == widget.tabId)
        .firstOrNull;
    if (activeTab != null) {
      TabNavigator.updateTabPath(context, activeTab.id, '#video');
      tabManager.add(UpdateTabName(activeTab.id, context.tr.videoHubTitle));
    } else {
      tabManager.add(AddTab(path: '#video', name: context.tr.videoHubTitle));
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
    final activeTab = tabBloc.state.tabs
        .where((tab) => tab.id == widget.tabId)
        .firstOrNull;

    final targetPath = path.isEmpty ? kDrivesPath : path;
    final tabName = isDrivesPath(targetPath)
        ? context.tr.drivesTab
        : _getPinnedDisplayName(targetPath);

    if (!mounted) return;

    if (activeTab != null) {
      // Update existing tab path
      TabNavigator.updateTabPath(context, activeTab.id, targetPath);
      tabBloc.add(UpdateTabName(activeTab.id, tabName));
    } else {
      // Create new tab if no active tab exists
      tabBloc.add(AddTab(path: targetPath, name: tabName, switchToTab: true));
    }
  }

  void _openTagsTab() {
    final tabBloc = context.read<TabManagerBloc>();
    final activeTab = tabBloc.state.tabs
        .where((tab) => tab.id == widget.tabId)
        .firstOrNull;

    if (activeTab != null) {
      // Navigate within the current tab to maintain navigation history
      TabNavigator.updateTabPath(context, activeTab.id, '#tags');
      tabBloc.add(UpdateTabName(activeTab.id, context.tr.tagsAction));
    } else {
      // Fallback: create new tab if no active tab exists
      tabBloc.add(
        AddTab(path: '#tags', name: context.tr.tagsAction, switchToTab: true),
      );
    }
  }
}
