import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/objectbox/video_library.dart';
import 'package:cb_file_manager/models/objectbox/video_library_config.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/video_library_helpers.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/directory_card_list_widget.dart';

/// Settings screen for managing video library configuration
class VideoLibrarySettingsScreen extends StatefulWidget {
  final VideoLibrary library;

  const VideoLibrarySettingsScreen({
    Key? key,
    required this.library,
  }) : super(key: key);

  @override
  State<VideoLibrarySettingsScreen> createState() =>
      _VideoLibrarySettingsScreenState();
}

class _VideoLibrarySettingsScreenState
    extends State<VideoLibrarySettingsScreen> {
  final VideoLibraryService _service = VideoLibraryService();
  VideoLibraryConfig? _config;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    setState(() {
      _isLoading = true;
    });

    final config = await _service.getLibraryConfig(widget.library.id);

    if (mounted) {
      setState(() {
        _config = config;
        _isLoading = false;
      });
    }
  }

  Future<void> _addDirectory() async {
    final selectedDirectory = await VideoLibraryHelpers.pickDirectory();
    if (selectedDirectory != null && _config != null) {
      final success = await _service.addDirectoryToLibrary(
          widget.library.id, selectedDirectory);

      if (success && mounted) {
        final localizations = AppLocalizations.of(context)!;
        VideoLibraryHelpers.showSuccessMessage(
            context, localizations.sourceAdded);
        _loadConfig();
      }
    }
  }

  Future<void> _removeDirectory(String directory) async {
    if (_config == null) return;

    final success =
        await _service.removeDirectoryFromLibrary(widget.library.id, directory);

    if (success && mounted) {
      final localizations = AppLocalizations.of(context)!;
      VideoLibraryHelpers.showSuccessMessage(
          context, localizations.sourceRemoved);
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

  Future<void> _rescanLibrary() async {
    final localizations = AppLocalizations.of(context)!;

    VideoLibraryHelpers.showSuccessMessage(
        context, localizations.scanForVideos);

    await _service.refreshLibrary(widget.library.id);

    if (mounted) {
      _loadConfig();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    if (_isLoading) {
      return BaseScreen(
        title: localizations.videoLibrarySettings,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_config == null) {
      return BaseScreen(
        title: localizations.videoLibrarySettings,
        body: Center(
          child: Text(localizations.operationFailed),
        ),
      );
    }

    final directories = _config!.directoriesList;

    return BaseScreen(
      title: localizations.videoLibrarySettings,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Library Info Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.library.name,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.library.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.library.description!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(PhosphorIconsLight.filmStrip,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${_config!.fileCount} ${localizations.videos.toLowerCase()}',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Video Sources Section
          Text(
            localizations.manageVideoSources,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Add Source Button
          Card(
            child: ListTile(
              leading: const Icon(PhosphorIconsLight.plusCircle),
              title: Text(localizations.addVideoSource),
              onTap: _addDirectory,
            ),
          ),
          const SizedBox(height: 8),

          // Sources List
          DirectoryCardListWidget(
            directories: directories,
            onRemove: _removeDirectory,
          ),

          const SizedBox(height: 24),

          // Settings Section
          Text(
            localizations.settings,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Include Subdirectories
          Card(
            child: SwitchListTile(
              value: _config!.includeSubdirectories,
              onChanged: _toggleSubdirectories,
              title: Text(localizations.includeSubdirectories),
              subtitle: Text(
                _config!.includeSubdirectories
                    ? localizations.searchInSubfolders
                    : localizations.searchInCurrentFolder,
              ),
            ),
          ),

          // Video Extensions (Display only for now)
          Card(
            child: ListTile(
              leading: const Icon(PhosphorIconsLight.videoCamera),
              title: Text(localizations.videoExtensions),
              subtitle: Text(_config!.fileExtensions),
            ),
          ),

          const SizedBox(height: 24),

          // Actions
          FilledButton.icon(
            onPressed: _rescanLibrary,
            icon: const Icon(PhosphorIconsLight.arrowsClockwise),
            label: Text(localizations.rescanLibrary),
          ),
        ],
      ),
    );
  }
}
