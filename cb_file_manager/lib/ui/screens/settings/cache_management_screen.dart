import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/app_path_helper.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/helpers/media/folder_thumbnail_service.dart';
import 'package:cb_file_manager/helpers/media/photo_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/network/network_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/helpers/network/win32_smb_helper.dart';
import 'package:cb_file_manager/services/video_library_cache_service.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

class CacheManagementScreen extends StatefulWidget {
  const CacheManagementScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<CacheManagementScreen> createState() => _CacheManagementScreenState();
}

class _CacheManagementScreenState extends State<CacheManagementScreen> {
  bool _isLoading = false;
  bool _isClearingAll = false;
  final Set<String> _clearingKeys = <String>{};

  String? _rootPath;
  String? _documentsRootPath;

  _CacheEntry? _photoThumbs;
  _CacheEntry? _videoThumbs;
  _CacheEntry? _networkThumbs;
  _CacheEntry? _videoLibrary;
  _CacheEntry? _tempFiles;

  // Persistent (documents) data — survives OS cache cleanup.
  _CacheEntry? _tagThumbs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final root = await AppPathHelper.getRootDir();
      final documentsRoot = await AppPathHelper.getPersistentRootDir();
      final photoDir = await AppPathHelper.getPhotoCacheDir();
      final videoDir = await AppPathHelper.getVideoCacheDir();
      final networkDir = await AppPathHelper.getNetworkCacheDir();
      final tempDir = await AppPathHelper.getTempFilesDir();
      final tagThumbDir = await AppPathHelper.getTagThumbnailDir();
      final videoLibDir = await VideoLibraryCacheService.instance
          .getCacheDirectory();
      final networkStats = await NetworkThumbnailHelper().getCacheStats();

      final photoStats = await _directoryStats(photoDir);
      final videoStats = await _directoryStats(videoDir);
      final tempStats = await _directoryStats(tempDir);
      final tagThumbStats = await _directoryStats(tagThumbDir);
      final videoLibStats = await _directoryStats(videoLibDir);

      if (!mounted) return;
      setState(() {
        _rootPath = root.path;
        _photoThumbs = _CacheEntry(
          key: 'photo',
          title: 'Photo thumbnails',
          subtitle: 'Generated JPEG previews for image grids and viewers',
          icon: PhosphorIconsLight.image,
          directory: photoDir,
          bytes: photoStats.totalBytes,
          files: photoStats.fileCount,
          accent: Colors.pinkAccent,
        );
        _videoThumbs = _CacheEntry(
          key: 'video',
          title: 'Video thumbnails',
          subtitle: 'Cached frame previews for videos',
          icon: PhosphorIconsLight.videoCamera,
          directory: videoDir,
          bytes: videoStats.totalBytes,
          files: videoStats.fileCount,
          accent: Colors.deepPurpleAccent,
        );
        _networkThumbs = _CacheEntry(
          key: 'network',
          title: 'Network thumbnails',
          subtitle: 'SMB / FTP / WebDAV thumbnail cache',
          icon: PhosphorIconsLight.cloud,
          directory: networkDir,
          bytes: (networkStats['totalSize'] as int?) ?? 0,
          files: (networkStats['fileCount'] as int?) ?? 0,
          accent: Colors.lightBlueAccent,
        );
        _videoLibrary = _CacheEntry(
          key: 'library',
          title: 'Video library cache',
          subtitle: 'Video library metadata and cached artifacts',
          icon: PhosphorIconsLight.filmStrip,
          directory: videoLibDir,
          bytes: videoLibStats.totalBytes,
          files: videoLibStats.fileCount,
          accent: Colors.amberAccent,
        );
        _tempFiles = _CacheEntry(
          key: 'temp',
          title: 'Temporary files',
          subtitle: 'Transient downloads and working files',
          icon: PhosphorIconsLight.folderMinus,
          directory: tempDir,
          bytes: tempStats.totalBytes,
          files: tempStats.fileCount,
          accent: Colors.orangeAccent,
        );
        _documentsRootPath = documentsRoot.path;
        _tagThumbs = _CacheEntry(
          key: 'tagThumbs',
          title:
              AppLocalizations.of(context)?.tagThumbnails ?? 'Tag thumbnails',
          subtitle:
              AppLocalizations.of(context)?.tagThumbnailsDescription ??
              'Thumbnail images you chose for tags (stored in Documents)',
          icon: PhosphorIconsLight.tag,
          directory: tagThumbDir,
          bytes: tagThumbStats.totalBytes,
          files: tagThumbStats.fileCount,
          accent: Colors.tealAccent,
          persistent: true,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load cache info: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int get _totalBytes =>
      (_photoThumbs?.bytes ?? 0) +
      (_videoThumbs?.bytes ?? 0) +
      (_networkThumbs?.bytes ?? 0) +
      (_videoLibrary?.bytes ?? 0) +
      (_tempFiles?.bytes ?? 0);

  int get _totalFiles =>
      (_photoThumbs?.files ?? 0) +
      (_videoThumbs?.files ?? 0) +
      (_networkThumbs?.files ?? 0) +
      (_videoLibrary?.files ?? 0) +
      (_tempFiles?.files ?? 0);

  /// Cache buckets (temp/cache root) — safe to clear, will be regenerated.
  List<_CacheEntry> get _entries => [
    ?_photoThumbs,
    ?_videoThumbs,
    ?_networkThumbs,
    ?_videoLibrary,
    ?_tempFiles,
  ];

  Future<void> _browseInApp(Directory dir, String title) async {
    try {
      final tabBloc = context.read<TabManagerBloc>();
      tabBloc.add(AddTab(path: dir.path, name: title, switchToTab: true));
    } catch (_) {
      await _openInSystem(dir.path);
    }
  }

  Future<void> _openInSystem(String path) async {
    final ok = await ExternalAppHelper.openWithSystemDefault(path);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open folder in system explorer'),
        ),
      );
    }
  }

  Future<void> _clearEntry(_CacheEntry entry) async {
    setState(() => _clearingKeys.add(entry.key));
    try {
      switch (entry.key) {
        case 'photo':
          await _clearDirectory(entry.directory);
          PhotoThumbnailHelper.clearMemoryCache();
          break;
        case 'video':
          await VideoThumbnailHelper.clearCache();
          FolderThumbnailService().clearCache();
          break;
        case 'network':
          await NetworkThumbnailHelper().clearCache();
          break;
        case 'library':
          await VideoLibraryCacheService.instance.clearAll();
          break;
        case 'temp':
          await Win32SmbHelper().clearTempFileCache();
          break;
        case 'tagThumbs':
          await _clearDirectory(entry.directory);
          TagThumbnailManager.instance.clearCache();
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${entry.title} cleared')));
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear ${entry.title}: $e')),
      );
    } finally {
      if (mounted) setState(() => _clearingKeys.remove(entry.key));
    }
  }

  Future<void> _clearAll() async {
    setState(() => _isClearingAll = true);
    try {
      await _clearDirectory(await AppPathHelper.getPhotoCacheDir());
      PhotoThumbnailHelper.clearMemoryCache();
      await VideoThumbnailHelper.clearCache();
      FolderThumbnailService().clearCache();
      await NetworkThumbnailHelper().clearCache();
      await VideoLibraryCacheService.instance.clearAll();
      await Win32SmbHelper().clearTempFileCache();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All cache cleared')));
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to clear cache: $e')));
    } finally {
      if (mounted) setState(() => _isClearingAll = false);
    }
  }

  static Future<void> _clearDirectory(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<_DirectoryStats> _directoryStats(Directory dir) async {
    try {
      if (!await dir.exists()) {
        return const _DirectoryStats(fileCount: 0, totalBytes: 0);
      }
      int totalBytes = 0;
      int fileCount = 0;
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          fileCount++;
          try {
            totalBytes += await entity.length();
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
    final theme = Theme.of(context);

    if (widget.embedded) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.appDataManagement ??
                        'App Data Management',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _buildAcrylicIconButton(
                  theme: theme,
                  tooltip:
                      AppLocalizations.of(context)?.refreshCacheInfo ??
                      'Refresh',
                  onPressed: _isLoading ? null : _load,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          PhosphorIconsLight.arrowsClockwise,
                          size: 18,
                        ),
                ),
                const SizedBox(width: 8),
                _buildAcrylicIconButton(
                  theme: theme,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(PhosphorIconsLight.x, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(theme)),
        ],
      );
    }

    return BaseScreen(
      title:
          AppLocalizations.of(context)?.appDataManagement ??
          'App Data Management',
      actions: [
        IconButton(
          tooltip: AppLocalizations.of(context)?.refreshCacheInfo ?? 'Refresh',
          onPressed: _isLoading ? null : _load,
          icon: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(PhosphorIconsLight.arrowsClockwise),
        ),
      ],
      body: _buildBody(theme),
    );
  }

  Widget _buildAcrylicIconButton({
    required ThemeData theme,
    required String tooltip,
    required VoidCallback? onPressed,
    required Widget icon,
  }) {
    final isEnabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(
            alpha: isEnabled ? 0.42 : 0.24,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: IconButton(
          onPressed: onPressed,
          icon: icon,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          splashRadius: 18,
          color: isEnabled
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurface.withValues(alpha: 0.45),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    final totalBytes = _totalBytes;
    final l10n = AppLocalizations.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeroOverview(theme),
        const SizedBox(height: 20),

        // ── Stored data (persistent, in Documents) ──────────────────────────
        _buildSectionLabel(
          theme,
          icon: PhosphorIconsLight.hardDrive,
          label: l10n?.documentsData ?? 'Stored data',
          description:
              l10n?.documentsDataDescription ??
              'Data kept in your Documents folder so it survives cache cleanup.',
        ),
        const SizedBox(height: 12),
        _buildDocumentsRootCard(theme),
        const SizedBox(height: 12),
        if (_tagThumbs != null)
          _buildEntryCard(theme, _tagThumbs!, _tagThumbs!.bytes),
        const SizedBox(height: 24),

        // ── Cache (temporary, safe to clear) ────────────────────────────────
        _buildSectionLabel(
          theme,
          icon: PhosphorIconsLight.broom,
          label: l10n?.cacheManagement ?? 'Cache',
          description:
              l10n?.cacheManagementDescription ??
              'Short-term cache used for thumbnails, library artifacts and temporary files.',
        ),
        const SizedBox(height: 12),
        _buildRootLocationCard(theme),
        const SizedBox(height: 12),
        ..._entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildEntryCard(theme, e, totalBytes),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _isClearingAll ? null : _clearAll,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _isClearingAll
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(PhosphorIconsLight.trash),
          label: Text(l10n?.clearAllCache ?? 'Clear all cache'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionLabel(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String description,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentsRootCard(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return _buildAcrylicPanel(
      theme,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsLight.folderOpen,
                color: theme.colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.documentsRoot ?? 'Documents root',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            _documentsRootPath ?? (l10n?.notInitialized ?? 'Not initialized'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _documentsRootPath == null
                    ? null
                    : () => _browseInApp(
                        Directory(_documentsRootPath!),
                        l10n?.documentsRoot ?? 'Documents root',
                      ),
                icon: const Icon(PhosphorIconsLight.folderSimplePlus, size: 16),
                label: Text(l10n?.browse ?? 'Browse in app'),
              ),
              OutlinedButton.icon(
                onPressed: _documentsRootPath == null
                    ? null
                    : () => _openInSystem(_documentsRootPath!),
                icon: const Icon(PhosphorIconsLight.arrowSquareOut, size: 16),
                label: Text(l10n?.openFolder ?? 'Open folder'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroOverview(ThemeData theme) {
    return _buildAcrylicPanel(
      theme,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  PhosphorIconsLight.hardDrives,
                  color: theme.colorScheme.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context)?.appDataManagement ??
                          'App Data Management',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(
                            context,
                          )?.appDataManagementDescription ??
                          'Manage stored data and temporary cache used by the app.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetricChip(
                theme,
                'Total size',
                FormatUtils.formatFileSize(_totalBytes),
              ),
              _buildMetricChip(theme, 'Files', _totalFiles.toString()),
              _buildMetricChip(theme, 'Buckets', _entries.length.toString()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRootLocationCard(ThemeData theme) {
    return _buildAcrylicPanel(
      theme,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                PhosphorIconsLight.folderOpen,
                color: theme.colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.cacheFolder ?? 'Cache root',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            _rootPath ??
                (AppLocalizations.of(context)?.notInitialized ??
                    'Not initialized'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _rootPath == null
                    ? null
                    : () => _browseInApp(
                        Directory(_rootPath!),
                        AppLocalizations.of(context)?.cacheFolder ??
                            'Cache Root',
                      ),
                icon: const Icon(PhosphorIconsLight.folderSimplePlus, size: 16),
                label: Text(
                  AppLocalizations.of(context)?.browse ?? 'Browse in app',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _rootPath == null
                    ? null
                    : () => _openInSystem(_rootPath!),
                icon: const Icon(PhosphorIconsLight.arrowSquareOut, size: 16),
                label: Text(
                  AppLocalizations.of(context)?.openFolder ?? 'Open folder',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(ThemeData theme, _CacheEntry entry, int totalBytes) {
    final l10n = AppLocalizations.of(context);
    final busy = _clearingKeys.contains(entry.key);
    final ratio = totalBytes <= 0 ? 0.0 : entry.bytes / totalBytes;
    // The persistent (documents) entry is shown on its own, so a "% of total
    // cache" bar is meaningless there.
    final showRatio = !entry.persistent;

    return _buildAcrylicPanel(
      theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: entry.accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(entry.icon, color: entry.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      FormatUtils.formatFileSize(entry.bytes),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${entry.files} files',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (showRatio) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: ratio.clamp(0.0, 1.0),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.35),
                  valueColor: AlwaysStoppedAnimation<Color>(entry.accent),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                totalBytes <= 0
                    ? '0% of total cache'
                    : '${(ratio * 100).toStringAsFixed(1)}% of total cache',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _browseInApp(entry.directory, entry.title),
                  icon: const Icon(PhosphorIconsLight.folderOpen, size: 16),
                  label: Text(l10n?.browse ?? 'Browse in app'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openInSystem(entry.directory.path),
                  icon: const Icon(PhosphorIconsLight.arrowSquareOut, size: 16),
                  label: Text(l10n?.openFolder ?? 'Open folder'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : () => _clearEntry(entry),
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsLight.broom, size: 16),
                  label: Text(
                    entry.persistent
                        ? (l10n?.clearTagThumbnails ?? 'Clear')
                        : (l10n?.clear ?? 'Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(ThemeData theme, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
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
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcrylicPanel(
    ThemeData theme, {
    EdgeInsetsGeometry padding = const EdgeInsets.all(0),
    required Widget child,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CacheEntry {
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
  final Directory directory;
  final int bytes;
  final int files;
  final Color accent;

  /// When true this bucket holds persistent user data (stored under Documents),
  /// not disposable cache. It is excluded from "Clear all cache" and shown in
  /// its own section.
  final bool persistent;

  const _CacheEntry({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.directory,
    required this.bytes,
    required this.files,
    required this.accent,
    this.persistent = false,
  });
}

class _DirectoryStats {
  final int fileCount;
  final int totalBytes;

  const _DirectoryStats({required this.fileCount, required this.totalBytes});
}
