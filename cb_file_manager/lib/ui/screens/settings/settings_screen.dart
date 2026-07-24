import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/config/language_controller.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/network/network_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/core/app_path_helper.dart';
import 'package:cb_file_manager/ui/screens/settings/cache_management_screen.dart';
import 'package:cb_file_manager/ui/screens/settings/database_settings_screen.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/config/theme_config.dart';
import 'package:cb_file_manager/config/design_system_config.dart';
import 'package:cb_file_manager/providers/theme_provider.dart';
import 'package:cb_file_manager/models/database/database_manager.dart';
import 'package:cb_file_manager/services/video_library_cache_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/screens/settings/ai_settings_section.dart';
import 'package:cb_file_manager/ui/screens/settings/local_ai_advisor_settings_section.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/tab_activity/tab_activity_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final UserPreferences _preferences = UserPreferences.instance;
  final LanguageController _languageController = LanguageController();
  final DatabaseManager _databaseManager = DatabaseManager.getInstance();
  String _currentLanguageCode = 'en';
  bool _isLoading = true;

  // Video thumbnail percentage value
  int _videoThumbnailPercentage = 30;

  // Thumbnail generation mode ('fast' or 'custom')
  String _thumbnailMode = 'fast';

  // Max concurrent thumbnail generation tasks
  int _maxConcurrency = 4;

  // Show file tags setting
  bool _showFileTags = true;
  TagThumbnailFitMode _tagThumbnailFitMode = TagThumbnailFitMode.contain;
  bool _rememberTabWorkspace = false;
  // Tab inactive threshold (in minutes). 0 means auto-suspend disabled.
  int _tabInactiveThresholdMinutes =
      UserPreferences.defaultTabInactiveThresholdMinutes;

  // Use system default app for video (false = in-app player by default)
  bool _useSystemDefaultForVideo = false;
  bool _isThemeExpanded = false;
  bool _isLanguageExpanded = false;
  String _appVersion = '';

  static const String _appAuthor = 'COOLBIRDZIK - ngtanhung41@gmail.com';

  // Database section state
  bool _isCloudSyncEnabled = false;
  bool _isSyncingCloud = false;
  Map<String, int> _popularTags = {};
  int _totalTagCount = 0;
  int _totalFileCount = 0;
  bool _isDatabaseStatsLoading = false;

  // Cache info (sizes are on-disk bytes)
  bool _isLoadingCacheInfo = false;
  String? _cacheRootPath;
  int? _networkThumbnailBytes;
  int? _networkThumbnailFiles;
  int? _videoThumbnailBytes;
  int? _videoThumbnailFiles;
  int? _videoLibraryBytes;
  int? _videoLibraryFiles;
  int? _tempFilesBytes;
  int? _tempFilesCount;
  int? _tagThumbnailBytes;
  int? _tagThumbnailFiles;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadCacheInfo();
    _loadAppInfo();
    _loadDatabaseStats();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      final fullVersion = build.isEmpty ? version : '$version.$build';
      if (!mounted) return;
      setState(() {
        _appVersion = fullVersion;
      });
    } catch (e) {
      debugPrint('Error loading app info: $e');
    }
  }

  Future<void> _loadPreferences() async {
    try {
      await _preferences.init();
      final percentage = await _preferences.getVideoThumbnailPercentage();
      final thumbnailMode = await _preferences.getThumbnailMode();
      final maxConcurrency = await _preferences.getMaxThumbnailConcurrency();
      final showFileTags = await _preferences.getShowFileTags();
      final tagThumbnailFitMode = await _preferences.getTagThumbnailFitMode();
      final rememberTabWorkspace =
          await _preferences.getRememberTabWorkspaceEnabled();
      final useSystemDefaultForVideo =
          await _preferences.getUseSystemDefaultForVideo();
      final tabInactiveMinutes =
          await _preferences.getTabInactiveThresholdMinutes();
      _preferences.isUsingDatabaseStorage();

      if (mounted) {
        setState(() {
          _currentLanguageCode = _languageController.currentLocale.languageCode;
          _videoThumbnailPercentage = percentage;
          _thumbnailMode = thumbnailMode;
          _maxConcurrency = maxConcurrency;
          _showFileTags = showFileTags;
          _tagThumbnailFitMode = tagThumbnailFitMode;
          _rememberTabWorkspace = rememberTabWorkspace;
          _useSystemDefaultForVideo = useSystemDefaultForVideo;
          _tabInactiveThresholdMinutes = tabInactiveMinutes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        final l10n = AppLocalizations.of(context)!;
        AppToast.error(context, '${l10n.errorLoadingTags}$e');
      }
    }
  }

  Future<void> _updateLanguage(String languageCode) async {
    await _languageController.changeLanguage(languageCode);
    setState(() {
      _currentLanguageCode = languageCode;
    });

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      AppToast.success(context, '${l10n.language} ${l10n.save}');
    }
  }

  Future<void> _updateVideoThumbnailPercentage(int percentage) async {
    await _preferences.setVideoThumbnailPercentage(percentage);
    setState(() {
      _videoThumbnailPercentage = percentage;
    });

    await VideoThumbnailHelper.refreshThumbnailPercentage();

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      AppToast.success(
        context,
        '${l10n.thumbnailPositionUpdated}$percentage%',
      );
    }
  }

  Future<void> _updateThumbnailMode(String mode) async {
    await _preferences.setThumbnailMode(mode);
    setState(() {
      _thumbnailMode = mode;
    });

    await VideoThumbnailHelper.refreshThumbnailMode();

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      AppToast.success(
        context,
        mode == 'fast' ? l10n.thumbnailModeFast : l10n.thumbnailModeCustom,
      );
    }
  }

  Future<void> _updateMaxConcurrency(int concurrency) async {
    await _preferences.setMaxThumbnailConcurrency(concurrency);
    setState(() {
      _maxConcurrency = concurrency;
    });

    await VideoThumbnailHelper.refreshMaxConcurrency();
  }

  Future<void> _updateShowFileTags(bool showTags) async {
    await _preferences.setShowFileTags(showTags);
    setState(() {
      _showFileTags = showTags;
    });

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      AppToast.success(
        context,
        showTags ? l10n.fileTagsEnabled : l10n.fileTagsDisabled,
      );
    }
  }

  Future<void> _updateTagThumbnailFitMode(TagThumbnailFitMode mode) async {
    final saved = await _preferences.setTagThumbnailFitMode(mode);
    if (saved && mounted) {
      setState(() {
        _tagThumbnailFitMode = mode;
      });
    }
  }

  Future<void> _updateRememberTabWorkspace(bool enabled) async {
    await _preferences.setRememberTabWorkspaceEnabled(enabled);
    if (!enabled) {
      await _preferences.clearLastOpenedTabPath();
      await _preferences.clearDrawerSectionStates();
    }

    setState(() {
      _rememberTabWorkspace = enabled;
    });
  }

  Future<void> _updateTabInactiveThresholdMinutes(int minutes) async {
    final clamped = minutes.clamp(
      UserPreferences.minTabInactiveThresholdMinutes,
      UserPreferences.maxTabInactiveThresholdMinutes,
    );
    await _preferences.setTabInactiveThresholdMinutes(clamped);
    if (locator.isRegistered<TabActivityManager>()) {
      locator<TabActivityManager>()
          .setInactiveThreshold(Duration(minutes: clamped));
    }
    if (mounted) {
      setState(() {
        _tabInactiveThresholdMinutes = clamped;
      });
    }
  }

  Future<void> _updateUseSystemDefaultForVideo(bool value) async {
    await _preferences.setUseSystemDefaultForVideo(value);
    setState(() => _useSystemDefaultForVideo = value);
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      AppToast.success(
        context,
        value
            ? l10n.useSystemDefaultForVideoEnabled
            : l10n.useSystemDefaultForVideoDisabled,
      );
    }
  }

  Future<void> _loadCacheInfo() async {
    try {
      if (mounted) {
        setState(() {
          _isLoadingCacheInfo = true;
        });
      }

      final root = await AppPathHelper.getRootDir();
      final networkStats = await NetworkThumbnailHelper().getCacheStats();
      final videoDir = await AppPathHelper.getVideoCacheDir();
      final tempDir = await AppPathHelper.getTempFilesDir();
      final tagThumbDir = await AppPathHelper.getTagThumbnailDir();

      final videoStats = await _directoryStats(videoDir);
      final tempStats = await _directoryStats(tempDir);
      final tagThumbStats = await _directoryStats(tagThumbDir);

      // Video library cache stats
      final videoLibDir =
          await VideoLibraryCacheService.instance.getCacheDirectory();
      final videoLibStats = await _directoryStats(videoLibDir);

      if (!mounted) return;
      setState(() {
        _cacheRootPath = root.path;

        _networkThumbnailBytes = (networkStats['totalSize'] as int?) ?? 0;
        _networkThumbnailFiles = (networkStats['fileCount'] as int?) ?? 0;

        _videoThumbnailBytes = videoStats.totalBytes;
        _videoThumbnailFiles = videoStats.fileCount;

        _videoLibraryBytes = videoLibStats.totalBytes;
        _videoLibraryFiles = videoLibStats.fileCount;

        _tempFilesBytes = tempStats.totalBytes;
        _tempFilesCount = tempStats.fileCount;

        _tagThumbnailBytes = tagThumbStats.totalBytes;
        _tagThumbnailFiles = tagThumbStats.fileCount;
      });
    } catch (e) {
      debugPrint('Error loading cache info: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCacheInfo = false;
        });
      }
    }
  }

  static Future<_DirectoryStats> _directoryStats(Directory dir) async {
    try {
      if (!await dir.exists()) {
        return const _DirectoryStats(fileCount: 0, totalBytes: 0);
      }

      int totalBytes = 0;
      int fileCount = 0;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            totalBytes += await entity.length();
            fileCount++;
          } catch (_) {}
        }
      }
      return _DirectoryStats(fileCount: fileCount, totalBytes: totalBytes);
    } catch (_) {
      return const _DirectoryStats(fileCount: 0, totalBytes: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header bar giống như file browser
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(PhosphorIconsLight.arrowLeft),
                  onPressed: () => _handleBack(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.settings,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildQuickSettingsSection(),
                        const SizedBox(height: 24),
                        _buildMediaSettingsSection(),
                        const SizedBox(height: 24),
                        _buildCacheManagementSection(),
                        const SizedBox(height: 24),
                        AiSettingsSection(
                          buildSectionCard: ({
                            required String title,
                            required IconData icon,
                            required List<Widget> children,
                          }) =>
                              _buildSectionCard(
                            title: title,
                            icon: icon,
                            children: children,
                          ),
                          buildCompactSettingTile: ({
                            required String title,
                            required String subtitle,
                            required IconData icon,
                            Widget? trailing,
                            VoidCallback? onTap,
                          }) =>
                              _buildCompactSettingTile(
                            title: title,
                            subtitle: subtitle,
                            icon: icon,
                            trailing: trailing,
                            onTap: onTap,
                          ),
                        ),
                        const SizedBox(height: 24),
                        LocalAiAdvisorSettingsSection(
                          buildSectionCard: ({
                            required String title,
                            required IconData icon,
                            required List<Widget> children,
                          }) =>
                              _buildSectionCard(
                            title: title,
                            icon: icon,
                            children: children,
                          ),
                          buildCompactSettingTile: ({
                            required String title,
                            required String subtitle,
                            required IconData icon,
                            Widget? trailing,
                            VoidCallback? onTap,
                          }) =>
                              _buildCompactSettingTile(
                            title: title,
                            subtitle: subtitle,
                            icon: icon,
                            trailing: trailing,
                            onTap: onTap,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildDatabaseSection(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Handle back navigation - close tab or pop navigator
  void _handleBack(BuildContext context) {
    // Try to get TabManagerBloc
    TabManagerBloc? tabBloc;
    try {
      tabBloc = context.read<TabManagerBloc>();
    } catch (_) {
      tabBloc = null;
    }

    if (tabBloc != null) {
      final activeTab = tabBloc.state.activeTab;
      if (activeTab != null) {
        // Close the settings tab
        tabBloc.add(CloseTab(activeTab.id));
        return;
      }
    }

    // Fallback to navigator pop
    Navigator.of(context).pop();
  }

  Widget _buildQuickSettingsSection() {
    return _buildSectionCard(
      title: AppLocalizations.of(context)!.interface,
      icon: PhosphorIconsLight.gear,
      children: [
        _buildLanguageCollapseTile(),
        _buildThemeCollapseTile(),
        _buildCompactSettingTile(
          title: AppLocalizations.of(context)!.showFileTags,
          subtitle: AppLocalizations.of(context)!.showFileTagsToggleDescription,
          icon: PhosphorIconsLight.tag,
          trailing: Switch(
            value: _showFileTags,
            onChanged: _updateShowFileTags,
          ),
        ),
        _buildCompactSettingTile(
          title: AppLocalizations.of(context)!.tagThumbnailFit,
          subtitle: AppLocalizations.of(context)!.tagThumbnailFitDescription,
          icon: PhosphorIconsLight.image,
          trailing: DropdownButton<TagThumbnailFitMode>(
            value: _tagThumbnailFitMode,
            onChanged: (mode) {
              if (mode != null) {
                _updateTagThumbnailFitMode(mode);
              }
            },
            items: [
              DropdownMenuItem(
                value: TagThumbnailFitMode.contain,
                child: Text(AppLocalizations.of(context)!.thumbnailFitContain),
              ),
              DropdownMenuItem(
                value: TagThumbnailFitMode.cover,
                child: Text(AppLocalizations.of(context)!.thumbnailFitCover),
              ),
            ],
          ),
        ),
        _buildCompactSettingTile(
          title: AppLocalizations.of(context)!.rememberTabWorkspace,
          subtitle:
              AppLocalizations.of(context)!.rememberTabWorkspaceDescription,
          icon: PhosphorIconsLight.clockCounterClockwise,
          trailing: Switch(
            value: _rememberTabWorkspace,
            onChanged: _updateRememberTabWorkspace,
          ),
        ),
        _buildTabInactiveThresholdTile(),
        _buildCompactSettingTile(
          title: AppLocalizations.of(context)!.aboutApp,
          subtitle:
              '${AppLocalizations.of(context)!.appDescription} • v${_appVersion.isEmpty ? '-' : _appVersion} • $_appAuthor',
          icon: PhosphorIconsLight.info,
        ),
      ],
    );
  }

  Widget _buildMediaSettingsSection() {
    return _buildSectionCard(
      title: AppLocalizations.of(context)!.videoThumbnails,
      icon: PhosphorIconsLight.videoCamera,
      children: [
        _buildCompactSettingTile(
          title: AppLocalizations.of(context)!.useSystemDefaultForVideo,
          subtitle:
              AppLocalizations.of(context)!.useSystemDefaultForVideoDescription,
          icon: PhosphorIconsLight.arrowSquareOut,
          trailing: Switch(
            value: _useSystemDefaultForVideo,
            onChanged: _updateUseSystemDefaultForVideo,
          ),
        ),
        // Thumbnail Mode Selection
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.thumbnailMode,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildModeCard(
                      title: AppLocalizations.of(context)!.thumbnailModeFast,
                      description: AppLocalizations.of(context)!
                          .thumbnailModeFastDescription,
                      icon: PhosphorIconsLight.lightning,
                      isSelected: _thumbnailMode == 'fast',
                      onTap: () => _updateThumbnailMode('fast'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildModeCard(
                      title: AppLocalizations.of(context)!.thumbnailModeCustom,
                      description: AppLocalizations.of(context)!
                          .thumbnailModeCustomDescription,
                      icon: PhosphorIconsLight.gear,
                      isSelected: _thumbnailMode == 'custom',
                      onTap: () => _updateThumbnailMode('custom'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Show position slider only in custom mode
        if (_thumbnailMode == 'custom')
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.thumbnailPosition,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '$_videoThumbnailPercentage%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Slider(
                  value: _videoThumbnailPercentage.toDouble(),
                  min: UserPreferences.minVideoThumbnailPercentage.toDouble(),
                  max: UserPreferences.maxVideoThumbnailPercentage.toDouble(),
                  divisions: 20,
                  onChanged: (value) {
                    setState(() {
                      _videoThumbnailPercentage = value.round();
                    });
                  },
                  onChangeEnd: (value) {
                    _updateVideoThumbnailPercentage(value.round());
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.thumbnailDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        // Max concurrency slider
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)!.maxConcurrency,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '$_maxConcurrency',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Slider(
                value: _maxConcurrency.toDouble(),
                min: UserPreferences.minThumbnailConcurrency.toDouble(),
                max: UserPreferences.maxThumbnailConcurrency.toDouble(),
                divisions: 31,
                onChanged: (value) {
                  setState(() {
                    _maxConcurrency = value.round();
                  });
                },
                onChangeEnd: (value) {
                  _updateMaxConcurrency(value.round());
                },
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.maxConcurrencyDescription,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required String title,
    required String description,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.iconTheme.color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    PhosphorIconsLight.checkCircle,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCacheManagementSection() {
    final theme = Theme.of(context);
    final totalBytes = (_networkThumbnailBytes ?? 0) +
        (_videoThumbnailBytes ?? 0) +
        (_videoLibraryBytes ?? 0) +
        (_tempFilesBytes ?? 0) +
        (_tagThumbnailBytes ?? 0);
    final totalFiles = (_networkThumbnailFiles ?? 0) +
        (_videoThumbnailFiles ?? 0) +
        (_videoLibraryFiles ?? 0) +
        (_tempFilesCount ?? 0) +
        (_tagThumbnailFiles ?? 0);

    return _buildSectionCard(
      title: AppLocalizations.of(context)!.appDataManagement,
      icon: PhosphorIconsLight.broom,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            PhosphorIconsLight.hardDrives,
                            color: theme.colorScheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!.appDataManagement,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppLocalizations.of(context)!
                                    .appDataManagementDescription,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMetricPill(
                          'Total',
                          FormatUtils.formatFileSize(totalBytes),
                        ),
                        _buildMetricPill('Files', '$totalFiles'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _cacheRootPath ??
                          AppLocalizations.of(context)!.notInitialized,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoadingCacheInfo
                                ? null
                                : () async {
                                    await _loadCacheInfo();
                                    if (!mounted) return;
                                    final l10n = AppLocalizations.of(context)!;
                                    AppToast.success(
                                      context,
                                      l10n.cacheInfoUpdated,
                                    );
                                  },
                            icon: const Icon(
                              PhosphorIconsLight.arrowsClockwise,
                              size: 16,
                            ),
                            label: Text(
                              AppLocalizations.of(context)!.refreshCacheInfo,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: () async {
                              await RouteUtils.showAcrylicDialog<void>(
                                context: context,
                                builder: (dialogContext) {
                                  final mediaQuery =
                                      MediaQuery.of(dialogContext);
                                  final maxDialogWidth =
                                      mediaQuery.size.width * 0.88;
                                  final maxDialogHeight =
                                      mediaQuery.size.height * 0.82;

                                  return Dialog(
                                    insetPadding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                      vertical: 24,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            maxDialogWidth.clamp(560.0, 980.0),
                                        maxHeight:
                                            maxDialogHeight.clamp(420.0, 900.0),
                                      ),
                                      child: const CacheManagementScreen(
                                        embedded: true,
                                      ),
                                    ),
                                  );
                                },
                              );
                              if (mounted) {
                                await _loadCacheInfo();
                              }
                            },
                            icon: const Icon(
                              PhosphorIconsLight.slidersHorizontal,
                              size: 16,
                            ),
                            label: Text(AppLocalizations.of(context)!.manage),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _isDatabaseSectionExpanded = true;
  bool _isDatabaseSectionExpandedCloudSync = false;

  Widget _buildDatabaseSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    PhosphorIconsLight.database,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)!.databaseSettings,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  icon: AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: _isDatabaseSectionExpanded ? 0.5 : 0,
                    child: const Icon(PhosphorIconsLight.caretDown, size: 16),
                  ),
                  onPressed: () {
                    setState(() {
                      _isDatabaseSectionExpanded = !_isDatabaseSectionExpanded;
                    });
                    if (_isDatabaseSectionExpanded && _totalTagCount == 0) {
                      _loadDatabaseStats();
                    }
                  },
                ),
              ],
            ),
          ),
          // Quick actions (always visible)
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const Icon(PhosphorIconsLight.uploadSimple, size: 20),
            title: Text(
              AppLocalizations.of(context)!.exportSettings,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              AppLocalizations.of(context)!.exportDescription,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(PhosphorIconsLight.caretRight, size: 16),
            onTap: () => _exportDatabase(context),
          ),
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: const Icon(PhosphorIconsLight.downloadSimple, size: 20),
            title: Text(
              AppLocalizations.of(context)!.importSettings,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              AppLocalizations.of(context)!.importDescription,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(PhosphorIconsLight.caretRight, size: 16),
            onTap: () => _importDatabase(context),
          ),
          // Expanded content
          if (_isDatabaseSectionExpanded) ...[
            const Divider(),
            // Database Type Info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        PhosphorIconsLight.checkCircle,
                        size: 16,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Using SQLite Database',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.databaseDescription,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            // Cloud Sync Section
            ExpansionTile(
              initiallyExpanded: _isDatabaseSectionExpandedCloudSync,
              onExpansionChanged: (expanded) {
                setState(() {
                  _isDatabaseSectionExpandedCloudSync = expanded;
                });
              },
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              leading: const Icon(PhosphorIconsLight.cloudArrowUp, size: 20),
              title: const Text(
                'Cloud Sync',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
              subtitle: Text(
                _isCloudSyncEnabled ? 'Enabled' : 'Disabled',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Switch(
                value: _isCloudSyncEnabled,
                onChanged: _toggleCloudSync,
              ),
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sync your tags and albums across devices',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isCloudSyncEnabled && !_isSyncingCloud
                                  ? _syncToCloud
                                  : null,
                              icon: _isSyncingCloud
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(PhosphorIconsLight.cloudArrowUp,
                                      size: 16),
                              label: Text(AppLocalizations.of(context)!.upload,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isCloudSyncEnabled && !_isSyncingCloud
                                  ? _syncFromCloud
                                  : null,
                              icon: const Icon(
                                  PhosphorIconsLight.cloudArrowDown,
                                  size: 16),
                              label: Text(
                                  AppLocalizations.of(context)!.download,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Popular Tags + Stats Section
            if (_isDatabaseStatsLoading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: PhosphorIconsLight.tag,
                        label: AppLocalizations.of(context)!.totalUniqueTags,
                        value: _totalTagCount.toString(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: PhosphorIconsLight.file,
                        label: AppLocalizations.of(context)!.taggedFiles,
                        value: _totalFileCount.toString(),
                      ),
                    ),
                  ],
                ),
              ),
              if (_popularTags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.popularTags,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _popularTags.entries.map((entry) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  entry.key,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${entry.value}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Open Advanced Database Settings
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: _openAdvancedDatabaseSettings,
                  icon: const Icon(PhosphorIconsLight.gear, size: 16),
                  label: Text(
                      AppLocalizations.of(context)!.advancedDatabaseSettings),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadDatabaseStats() async {
    if (!mounted) return;

    setState(() {
      _isDatabaseStatsLoading = true;
    });

    try {
      await _databaseManager.initialize();

      // Load cloud sync state
      _isCloudSyncEnabled = _databaseManager.isCloudSyncEnabled();

      // Get all unique tags
      final allTags = await _databaseManager.getAllUniqueTags();
      if (!mounted) return;

      _totalTagCount = allTags.length;

      // Count unique files with at least one tag using a single efficient SQL query
      // (replaces the previous O(n) loop that called findFilesByTag per tag)
      _totalFileCount = await _databaseManager.countUniqueTaggedFiles();

      // Get popular tags (top 5)
      _popularTags = await TagManager.instance.getPopularTags(limit: 5);
    } catch (e) {
      debugPrint('Error loading database stats: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDatabaseStatsLoading = false;
        });
      }
    }
  }

  void _openAdvancedDatabaseSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DatabaseSettingsScreen(),
      ),
    );
  }

  Future<void> _toggleCloudSync(bool value) async {
    try {
      _databaseManager.setCloudSyncEnabled(value);
      await _preferences.setCloudSyncEnabled(value);
      if (mounted) {
        setState(() {
          _isCloudSyncEnabled = value;
        });
        final l10n = AppLocalizations.of(context)!;
        AppToast.success(
          context,
          value ? l10n.cloudSyncEnabled : l10n.cloudSyncDisabled,
        );
      }
    } catch (e) {
      debugPrint('Error toggling cloud sync: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppToast.error(context, l10n.errorWithMessage(e.toString()));
      }
    }
  }

  Future<void> _syncToCloud() async {
    if (!_isCloudSyncEnabled) return;
    setState(() => _isSyncingCloud = true);
    try {
      final success = await _databaseManager.syncToCloud();
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppToast.success(context,
            success ? l10n.syncToCloudSuccess : l10n.syncToCloudFailed);
      }
    } catch (e) {
      debugPrint('Error syncing to cloud: $e');
    } finally {
      if (mounted) setState(() => _isSyncingCloud = false);
    }
  }

  Future<void> _syncFromCloud() async {
    if (!_isCloudSyncEnabled) return;
    setState(() => _isSyncingCloud = true);
    try {
      final success = await _databaseManager.syncFromCloud();
      if (success) {
        await _loadDatabaseStats();
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        AppToast.success(context,
            success ? l10n.syncFromCloudSuccess : l10n.syncFromCloudFailed);
      }
    } catch (e) {
      debugPrint('Error syncing from cloud: $e');
    } finally {
      if (mounted) setState(() => _isSyncingCloud = false);
    }
  }

  Future<void> _exportDatabase(BuildContext context) async {
    // Pre-extract context-dependent values before async gaps
    final l10n = AppLocalizations.of(context)!;
    final toast = AppToast.capture(context);

    try {
      String? saveLocation = await FilePicker.platform.saveFile(
        dialogTitle: l10n.saveDatabaseExport,
        fileName:
            'cb_file_hub_db_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (saveLocation != null) {
        final dbManager = DatabaseManager.getInstance();
        final filePath =
            await dbManager.exportDatabase(customPath: saveLocation);
        if (filePath != null) {
          if (mounted) {
            toast.success(l10n.exportSuccess + filePath);
          }
        } else {
          if (mounted) {
            toast.error(l10n.exportFailed);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        toast.error(l10n.errorExporting + e.toString());
      }
    }
  }

  Future<void> _importDatabase(BuildContext context) async {
    // Pre-extract context-dependent values before async gaps
    final l10n = AppLocalizations.of(context)!;
    final toast = AppToast.capture(context);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        // Show loading dialog
        if (!mounted) return;

        // Store the navigator key to close dialog later
        late NavigatorState dialogNavigator;
        showDialog(
          // ignore: use_build_context_synchronously
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            dialogNavigator = Navigator.of(dialogContext);
            return PopScope(
              canPop: false,
              child: AlertDialog(
                content: Row(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(width: 20),
                    Text(l10n.importing),
                  ],
                ),
              ),
            );
          },
        );

        try {
          final dbManager = DatabaseManager.getInstance();

          // Use skipFileExistenceCheck: true to allow importing tags for files
          // that don't exist yet (e.g., network drives, files to be added later)
          final success = await dbManager.importDatabase(
            filePath,
            skipFileExistenceCheck: true,
          );

          // Close loading dialog
          if (mounted) {
            dialogNavigator.pop();
          }

          if (success) {
            // Clear TagManager cache after successful import to ensure UI refreshes
            // This fixes the issue where background shows empty after import
            try {
              // Clear the static cache in TagManager
              TagManager.clearCache();
              debugPrint(
                  'SettingsScreen: Cleared TagManager cache after import');
            } catch (e) {
              debugPrint('SettingsScreen: Error clearing cache: $e');
            }

            if (mounted) {
              toast.success(l10n.importSuccess);
            }
          } else {
            if (mounted) {
              toast.error(l10n.importFailed);
            }
          }
        } catch (e) {
          // Close loading dialog on error
          if (mounted) {
            try {
              dialogNavigator.pop();
            } catch (_) {}

            toast.error(l10n.errorImporting + e.toString());
          }
        }
      } else {
        toast.info(l10n.importCancelled);
      }
    } catch (e) {
      // Handle picker errors
      if (mounted) {
        toast.error(l10n.errorImporting + e.toString());
      }
    }
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCompactSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, size: 20),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing ??
          (onTap != null
              ? const Icon(PhosphorIconsLight.caretRight, size: 16)
              : null),
      onTap: onTap,
    );
  }

  /// Preset values offered to the user for the tab inactive threshold.
  /// 0 means "off" (no auto-suspend).
  static const List<int> _tabInactivePresetMinutes = <int>[
    0,
    1,
    15,
    30,
    60,
    120,
    240,
    480,
    24 * 60,
  ];

  String _formatTabInactiveThresholdLabel(int minutes) {
    final l10n = AppLocalizations.of(context)!;
    if (minutes <= 0) {
      return l10n.tabInactiveThresholdDisabled;
    }
    if (minutes < 60) {
      return '$minutes ${l10n.tabInactiveThresholdMinutesValue}';
    }
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (remaining == 0) {
      return '$hours ${l10n.tabInactiveThresholdHoursValue}';
    }
    return '$hours ${l10n.tabInactiveThresholdHoursValue} '
        '$remaining ${l10n.tabInactiveThresholdMinutesValue}';
  }

  Widget _buildTabInactiveThresholdTile() {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final current = _tabInactiveThresholdMinutes;

    // Build the dropdown items from presets, plus the current value if it
    // is not in the preset list (so we never lose user-entered values).
    final values = <int>{..._tabInactivePresetMinutes, current}.toList()
      ..sort();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 0),
          const Icon(PhosphorIconsLight.moon, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tabInactiveThreshold,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.tabInactiveThresholdDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: current,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final v in values)
                DropdownMenuItem<int>(
                  value: v,
                  child: Text(
                    _formatTabInactiveThresholdLabel(v),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              _updateTabInactiveThresholdMinutes(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCollapseTile() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final theme = Theme.of(context);
        final currentTheme = themeProvider.currentTheme;
        final currentThemeName =
            ThemeConfig.themeNames[currentTheme] ?? currentTheme.name;
        final currentAccent = themeProvider.currentAccentColor;
        final currentAccentName =
            ThemeConfig.accentNames[currentAccent] ?? currentAccent.name;
        const showDesktopAcrylicControl =
            DesignSystemConfig.enableDesktopAcrylicWindowBackground;

        return Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            childrenPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            initiallyExpanded: _isThemeExpanded,
            onExpansionChanged: (expanded) {
              setState(() {
                _isThemeExpanded = expanded;
              });
            },
            leading: const Icon(PhosphorIconsLight.palette, size: 20),
            title: Text(
              AppLocalizations.of(context)!.theme,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              '$currentThemeName • Accent: $currentAccentName',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: AnimatedRotation(
              duration: const Duration(milliseconds: 180),
              turns: _isThemeExpanded ? 0.5 : 0,
              child: const Icon(PhosphorIconsLight.caretDown, size: 16),
            ),
            children: [
              ...AppThemeType.values.map((themeType) {
                final title =
                    ThemeConfig.themeNames[themeType] ?? themeType.name;
                // ignore: deprecated_member_use
                // ignore: deprecated_member_use
                return RadioListTile<AppThemeType>(
                  dense: true,
                  value: themeType,
                  // ignore: deprecated_member_use
                  groupValue: currentTheme,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    title,
                    style: const TextStyle(fontSize: 13),
                  ),
                  // ignore: deprecated_member_use
                  onChanged: (value) {
                    if (value == null) return;
                    context.read<ThemeProvider>().setTheme(value);
                  },
                );
              }),
              _buildAccentColorControl(themeProvider),
              if (showDesktopAcrylicControl) ...[
                _buildBackdropModeControl(themeProvider),
                _buildDesktopAcrylicStrengthControl(themeProvider),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAccentColorControl(ThemeProvider themeProvider) {
    final selectedAccent = themeProvider.currentAccentColor;
    final selectedAccentName =
        ThemeConfig.accentNames[selectedAccent] ?? selectedAccent.name;
    final accents =
        ThemeConfig.accentSeedColors.entries.toList(growable: false);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Accent Color',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Current accent: $selectedAccentName',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: accents.map((entry) {
              final accent = entry.key;
              final color = entry.value;
              final isSelected = accent == selectedAccent;
              return Tooltip(
                message: ThemeConfig.accentNames[accent] ?? accent.name,
                child: InkWell(
                  onTap: () => context.read<ThemeProvider>().setAccentColor(
                        accent,
                      ),
                  borderRadius: BorderRadius.circular(99),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.onSurface
                            : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.18),
                                blurRadius: 6,
                                spreadRadius: 0.2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdropModeControl(ThemeProvider themeProvider) {
    final theme = Theme.of(context);
    final mode = themeProvider.backdropMode;
    final imagePath = themeProvider.backdropImagePath;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Backdrop Mode',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            mode == AcrylicBackdropMode.wallpaper
                ? 'Using system wallpaper as backdrop.'
                : 'Using system dynamic acrylic backdrop.',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildModeChip(
                label: 'Dynamic',
                icon: PhosphorIconsLight.monitor,
                isSelected: mode == AcrylicBackdropMode.dynamic,
                onTap: () =>
                    themeProvider.setBackdropMode(AcrylicBackdropMode.dynamic),
              ),
              const SizedBox(width: 8),
              _buildModeChip(
                label: 'Wallpaper',
                icon: PhosphorIconsLight.image,
                isSelected: mode == AcrylicBackdropMode.wallpaper,
                onTap: () => themeProvider
                    .setBackdropMode(AcrylicBackdropMode.wallpaper),
              ),
            ],
          ),
          if (mode == AcrylicBackdropMode.wallpaper) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    imagePath != null && imagePath.isNotEmpty
                        ? imagePath.split(Platform.pathSeparator).last
                        : 'No system wallpaper detected',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 30,
                  child: OutlinedButton.icon(
                    onPressed: () => themeProvider.refreshSystemWallpaper(),
                    icon: const Icon(PhosphorIconsLight.arrowsClockwise,
                        size: 14),
                    label:
                        const Text('Refresh', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  height: 30,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        allowMultiple: false,
                      );
                      if (result != null &&
                          result.files.isNotEmpty &&
                          result.files.first.path != null) {
                        await themeProvider
                            .setBackdropImagePath(result.files.first.path);
                      }
                    },
                    icon: const Icon(PhosphorIconsLight.folderOpen, size: 14),
                    label: const Text('Custom', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ],
            ),
            if (imagePath != null && imagePath.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: theme.colorScheme.errorContainer,
                      alignment: Alignment.center,
                      child: Text(
                        'Image not found',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildModeChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopAcrylicStrengthControl(ThemeProvider themeProvider) {
    final value = themeProvider.desktopAcrylicStrength;
    final percentage = (value * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Desktop Acrylic Strength',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Adjust blur and tint intensity for desktop backdrop ($percentage%).',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Slider(
            min: 0,
            max: 2,
            divisions: 20,
            value: value,
            label: '$percentage%',
            onChanged: (nextValue) {
              context.read<ThemeProvider>().setDesktopAcrylicStrength(
                    nextValue,
                    persist: false,
                  );
            },
            onChangeEnd: (nextValue) {
              context.read<ThemeProvider>().setDesktopAcrylicStrength(
                    nextValue,
                    persist: true,
                  );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageCollapseTile() {
    final theme = Theme.of(context);
    final languageLabel = _currentLanguageCode == 'vi'
        ? AppLocalizations.of(context)!.vietnameseLanguage
        : AppLocalizations.of(context)!.englishLanguage;

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        initiallyExpanded: _isLanguageExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            _isLanguageExpanded = expanded;
          });
        },
        leading: const Icon(PhosphorIconsLight.globe, size: 20),
        title: Text(
          AppLocalizations.of(context)!.language,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          languageLabel,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: AnimatedRotation(
          duration: const Duration(milliseconds: 180),
          turns: _isLanguageExpanded ? 0.5 : 0,
          child: const Icon(PhosphorIconsLight.caretDown, size: 16),
        ),
        children: [
          _buildLanguageOptionTile(
            title: AppLocalizations.of(context)!.vietnameseLanguage,
            value: LanguageController.vietnamese,
            flagEmoji: '🇻🇳',
          ),
          _buildLanguageOptionTile(
            title: AppLocalizations.of(context)!.englishLanguage,
            value: LanguageController.english,
            flagEmoji: '🇬🇧',
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageOptionTile({
    required String title,
    required String value,
    required String flagEmoji,
  }) {
    final isSelected = _currentLanguageCode == value;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Row(
        children: [
          Text(flagEmoji),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
      trailing: isSelected
          ? Icon(
              PhosphorIconsLight.checkCircle,
              color: Theme.of(context).colorScheme.primary,
              size: 18,
            )
          : null,
      onTap: () => _updateLanguage(value),
    );
  }
}

class _DirectoryStats {
  final int fileCount;
  final int totalBytes;

  const _DirectoryStats({required this.fileCount, required this.totalBytes});
}
