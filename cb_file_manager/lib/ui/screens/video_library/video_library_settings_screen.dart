import 'package:cb_file_manager/design_system/primitives/cb_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/objectbox/video_library.dart';
import 'package:cb_file_manager/models/objectbox/video_library_config.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/ui/dialogs/thumbnail_browser_dialog.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/video_library_helpers.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/video_library_cover.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/components/navigation_bar.dart';

/// Settings screen for managing video library configuration.
///
/// The screen is organized into three cards: a cover/header card, a video
/// sources card, and a settings card, followed by a rescan action. The cover
/// image is picked through the same shared thumbnail browser used for tags
/// (folder browsing, tag search, video-frame extraction and cropping), so
/// choosing a library cover matches choosing a tag thumbnail.
class VideoLibrarySettingsScreen extends StatefulWidget {
  final VideoLibrary library;
  final String tabId;

  const VideoLibrarySettingsScreen({
    super.key,
    required this.library,
    required this.tabId,
  });

  @override
  State<VideoLibrarySettingsScreen> createState() =>
      _VideoLibrarySettingsScreenState();
}

class _VideoLibrarySettingsScreenState
    extends State<VideoLibrarySettingsScreen> {
  final VideoLibraryService _service = VideoLibraryService();
  final TextEditingController _addressController = TextEditingController();
  VideoLibraryConfig? _config;
  bool _isLoading = true;
  bool _isScanning = false;

  late VideoLibrary _library;

  @override
  void initState() {
    super.initState();
    _library = widget.library;
    _loadConfig();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });

    final config = await _service.getLibraryConfig(widget.library.id);
    // Reload the library so the cover image stays in sync with the database.
    final library = await _service.getLibraryById(widget.library.id);

    if (mounted) {
      setState(() {
        if (library != null) {
          _library = library;
        }
        _config = config;
        _isLoading = false;
      });
    }
  }

  Future<void> _addDirectory() async {
    final selectedDirectory = await VideoLibraryHelpers.pickDirectory();
    if (selectedDirectory != null && _config != null) {
      final success = await _service.addDirectoryToLibrary(
        widget.library.id,
        selectedDirectory,
      );

      if (success && mounted) {
        final localizations = AppLocalizations.of(context)!;
        VideoLibraryHelpers.showSuccessMessage(
          context,
          localizations.sourceAdded,
        );
        _loadConfig();
      }
    }
  }

  Future<void> _removeDirectory(String directory) async {
    if (_config == null) return;

    final success = await _service.removeDirectoryFromLibrary(
      widget.library.id,
      directory,
    );

    if (success && mounted) {
      final localizations = AppLocalizations.of(context)!;
      VideoLibraryHelpers.showSuccessMessage(
        context,
        localizations.sourceRemoved,
      );
      _loadConfig();
    }
  }

  Future<void> _toggleSubdirectories(bool value) async {
    if (_config == null) return;

    final updatedConfig = _config!.copyWith(includeSubdirectories: value);
    final success = await _service.updateLibraryConfig(updatedConfig);

    if (success) {
      setState(() {
        _config = updatedConfig;
      });
    }
  }

  Future<void> _changeCover() async {
    final localizations = AppLocalizations.of(context)!;
    final imagePath = await showThumbnailBrowserDialog(
      context,
      title: localizations.changeCoverImage,
      cropAspectRatio: 16 / 9,
    );
    if (imagePath == null || !mounted) return;

    await _applyCover(imagePath, localizations);
  }

  Future<void> _removeCover() async {
    final localizations = AppLocalizations.of(context)!;
    await _applyCover(null, localizations);
  }

  Future<void> _applyCover(
    String? imagePath,
    AppLocalizations localizations,
  ) async {
    final updated = _libraryWithCover(imagePath);
    final success = await _service.updateLibrary(updated);

    if (!mounted) return;
    if (success) {
      setState(() {
        _library = updated;
      });
      VideoLibraryHelpers.showSuccessMessage(
        context,
        imagePath == null
            ? localizations.coverImageRemoved
            : localizations.coverImageUpdated,
      );
    } else {
      VideoLibraryHelpers.showErrorMessage(
        context,
        localizations.coverImageUpdateFailed,
      );
    }
  }

  VideoLibrary _libraryWithCover(String? coverImagePath) {
    return VideoLibrary(
      name: _library.name,
      description: _library.description,
      coverImagePath: coverImagePath,
      createdAt: _library.createdAt,
      modifiedAt: _library.modifiedAt,
      colorTheme: _library.colorTheme,
      isSystemLibrary: _library.isSystemLibrary,
    )..id = _library.id;
  }

  Future<void> _rescanLibrary() async {
    final localizations = AppLocalizations.of(context)!;
    setState(() {
      _isScanning = true;
    });

    try {
      await _service.refreshLibrary(widget.library.id);
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
        VideoLibraryHelpers.showSuccessMessage(
          context,
          localizations.scanComplete,
        );
        _loadConfig();
      }
    }
  }

  void _openVideoGallery() {
    final tabManager = context.read<TabManagerBloc>();
    final activeTab = tabManager.state.activeTab;
    if (activeTab == null) return;

    TabNavigator.updateTabPath(context, activeTab.id, '#video');
    tabManager.add(
      UpdateTabName(activeTab.id, AppLocalizations.of(context)!.videoHubTitle),
    );
  }

  void _openLibrary() {
    final tabManager = context.read<TabManagerBloc>();
    final activeTab = tabManager.state.activeTab;
    if (activeTab == null) return;

    TabNavigator.updateTabPath(
      context,
      activeTab.id,
      '#video-library/${_library.id}',
    );
    tabManager.add(UpdateTabName(activeTab.id, _library.name));
  }

  Widget _buildAddressBar(AppLocalizations localizations) {
    return PathNavigationBar(
      tabId: widget.tabId,
      pathController: _addressController,
      onPathSubmitted: (_) {},
      currentPath: '#video-library-settings/${_library.id}',
      tabPath: '#video-library-settings/${_library.id}',
      enablePathEditing: false,
      canNavigateToParent: true,
      onNavigateToParent: _openLibrary,
      breadcrumbSegments: [
        BreadcrumbSegment(
          label: localizations.videoGallery,
          icon: PhosphorIconsLight.filmStrip,
          onTap: _openVideoGallery,
        ),
        BreadcrumbSegment(label: _library.name, onTap: _openLibrary),
        BreadcrumbSegment(label: localizations.settings),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    if (_isLoading) {
      return BaseScreen(
        title: localizations.videoLibrarySettings,
        titleWidget: _buildAddressBar(localizations),
        automaticallyImplyLeading: false,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_config == null) {
      return BaseScreen(
        title: localizations.videoLibrarySettings,
        titleWidget: _buildAddressBar(localizations),
        automaticallyImplyLeading: false,
        body: Center(child: Text(localizations.operationFailed)),
      );
    }

    final directories = _config!.directoriesList;

    return BaseScreen(
      title: localizations.videoLibrarySettings,
      titleWidget: _buildAddressBar(localizations),
      automaticallyImplyLeading: false,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCoverCard(theme, localizations),
          const SizedBox(height: 24),
          _buildSourcesCard(theme, localizations, directories),
          const SizedBox(height: 16),
          _buildSettingsCard(theme, localizations),
          const SizedBox(height: 24),
          _buildRescanButton(localizations),
        ],
      ),
    );
  }

  Widget _buildCoverCard(ThemeData theme, AppLocalizations localizations) {
    final cs = theme.colorScheme;
    final accentColor = VideoLibraryHelpers.getColorFromHex(
      _library.colorTheme,
      cs.primary,
    );
    final directories = _config?.directoriesList ?? const <String>[];
    final hasCover = _library.coverImagePath != null;
    final lastScanTime = _config?.lastScanTime;
    final lastScanText = lastScanTime != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(lastScanTime)
        : localizations.neverScanned;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 188,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoLibraryCover(
                  coverImagePath: _library.coverImagePath,
                  placeholderIcon: PhosphorIconsLight.imageSquare,
                  placeholderLabel: localizations.libraryCover,
                  accentColor: accentColor,
                ),
                if (hasCover)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        stops: [0.45, 1],
                        colors: [Colors.black38, Colors.transparent],
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _changeCover,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: _CoverBadge(
                    icon: PhosphorIconsLight.pencilSimple,
                    label: localizations.changeCoverImage,
                    onTap: _changeCover,
                  ),
                ),
                if (hasCover)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _CoverIconButton(
                      icon: PhosphorIconsLight.trash,
                      tooltip: localizations.removeCoverImage,
                      onTap: _removeCover,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _library.name,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_library.description?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    _library.description!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _StatChip(
                      icon: PhosphorIconsLight.videoCamera,
                      label:
                          '${_config!.fileCount} ${localizations.videos.toLowerCase()}',
                    ),
                    _StatChip(
                      icon: PhosphorIconsLight.folderOpen,
                      label:
                          '${directories.length} ${localizations.videoSources.toLowerCase()}',
                    ),
                    _StatChip(
                      icon: PhosphorIconsLight.clock,
                      label: '${localizations.lastScanLabel}: $lastScanText',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 18, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSourcesCard(
    ThemeData theme,
    AppLocalizations localizations,
    List<String> directories,
  ) {
    final cs = theme.colorScheme;
    return _buildSectionCard(
      theme: theme,
      icon: PhosphorIconsLight.folderOpen,
      title: localizations.manageVideoSources,
      children: [
        if (directories.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsLight.folder,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      localizations.noVideoSources,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          for (var i = 0; i < directories.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _buildDirectoryRow(theme, localizations, directories[i]),
          ],
        ],
        const Divider(height: 1, indent: 16, endIndent: 16),
        _buildAddSourceTile(theme, localizations),
      ],
    );
  }

  Widget _buildDirectoryRow(
    ThemeData theme,
    AppLocalizations localizations,
    String directory,
  ) {
    final cs = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(PhosphorIconsLight.folder, size: 18, color: cs.primary),
      ),
      title: Text(
        p.basename(directory),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        directory,
        style: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: Icon(
          PhosphorIconsLight.trash,
          size: 18,
          color: cs.error.withValues(alpha: 0.8),
        ),
        tooltip: localizations.removeVideoSource,
        onPressed: () => _removeDirectory(directory),
      ),
    );
  }

  Widget _buildAddSourceTile(ThemeData theme, AppLocalizations localizations) {
    final cs = theme.colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(PhosphorIconsLight.plusCircle, size: 18, color: cs.primary),
      ),
      title: Text(
        localizations.addVideoSource,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.primary,
        ),
      ),
      onTap: _addDirectory,
    );
  }

  Widget _buildSettingsCard(ThemeData theme, AppLocalizations localizations) {
    final cs = theme.colorScheme;
    return _buildSectionCard(
      theme: theme,
      icon: PhosphorIconsLight.gear,
      title: localizations.settings,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: _config!.includeSubdirectories,
          onChanged: _toggleSubdirectories,
          secondary: Icon(PhosphorIconsLight.folderOpen, color: cs.primary),
          title: Text(
            localizations.includeSubdirectories,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            _config!.includeSubdirectories
                ? localizations.searchInSubfolders
                : localizations.searchInCurrentFolder,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  PhosphorIconsLight.videoCamera,
                  size: 20,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localizations.videoExtensions,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final extension in _config!.fileExtensionsList)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              extension,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRescanButton(AppLocalizations localizations) {
    return SizedBox(
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _isScanning ? null : _rescanLibrary,
        icon: _isScanning
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(PhosphorIconsLight.arrowsClockwise),
        label: Text(
          _isScanning ? localizations.scanning : localizations.rescanLibrary,
        ),
      ),
    );
  }
}

/// Small icon + text chip used for the library stats row.
class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Translucent pill button overlaid on the cover image.
class _CoverBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _CoverBadge({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Translucent circular icon button overlaid on the cover image.
class _CoverIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _CoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: CbTooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
