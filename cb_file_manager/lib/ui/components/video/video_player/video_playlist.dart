import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../../helpers/core/filesystem_sorter.dart';
import '../../../../helpers/core/user_preferences.dart';
import '../../../../helpers/files/file_type_registry.dart';
import '../../../../helpers/files/folder_sort_manager.dart';
import '../../../screens/folder_list/folder_list_state.dart';
import '../../../widgets/lazy_video_thumbnail.dart';
import 'video_player_utils.dart';

/// Builds the playlist shown by the video player: the videos that sit next to
/// the file being played, in the order the folder view lists them.
class VideoPlaylist {
  VideoPlaylist._();

  /// Video files in [current]'s folder, ordered by [sortOption] or, when it
  /// is null, by the sort the folder view uses for that folder. Always
  /// contains [current]; an unreadable folder yields just that file.
  static Future<List<File>> fromFolder(
    File current, {
    SortOption? sortOption,
  }) async {
    final List<File> files = <File>[];
    try {
      await for (final entity in current.parent.list(followLinks: false)) {
        if (entity is File) files.add(entity);
      }
    } catch (_) {
      return <File>[current];
    }
    if (!files.any((f) => pathlib.equals(f.path, current.path))) {
      files.add(current);
    }
    final option = sortOption ?? await folderSortOption(current.parent.path);
    // Sorted with the folder view's own sorter over the same listing, then
    // narrowed to videos, so even ties land where the folder view puts them.
    final sorted = await FileSystemSorter.sortFiles(files, option);
    return sorted.where((f) => _isVideo(f.path)).toList();
  }

  /// The folder's own sort, else the default sort, as the folder view
  /// resolves it.
  static Future<SortOption> folderSortOption(String folderPath) async {
    try {
      final saved = await FolderSortManager().getFolderSortOption(folderPath);
      if (saved != null) return saved;
      final preferences = UserPreferences.instance;
      await preferences.init();
      return await preferences.getSortOption();
    } catch (_) {
      return SortOption.nameAsc;
    }
  }

  static bool _isVideo(String path) =>
      FileTypeRegistry.getCategory(VideoPlayerUtils.extensionFromPath(path)) ==
      FileCategory.video;
}

/// Opens the playlist as a floating panel above the player controls.
/// Tapping outside the panel (or pressing Esc) closes it; picking an entry
/// closes it and reports that file through [onSelected].
Future<void> showVideoPlaylistPanel({
  required BuildContext context,
  required List<File> items,
  required String currentPath,
  required ValueChanged<File> onSelected,
  VideoPlaylistThumbnailBuilder? thumbnailBuilder,
}) async {
  final picked = await showGeneralDialog<File>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    transitionDuration: const Duration(milliseconds: 150),
    pageBuilder: (dialogContext, _, _) => VideoPlaylistPanel(
      items: items,
      currentPath: currentPath,
      thumbnailBuilder: thumbnailBuilder,
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
  if (picked != null && !pathlib.equals(picked.path, currentPath)) {
    onSelected(picked);
  }
}

/// Draws an entry's preview at the given size.
typedef VideoPlaylistThumbnailBuilder =
    Widget Function(File file, double width, double height);

/// The floating playlist card. Pops its route with the chosen [File].
class VideoPlaylistPanel extends StatefulWidget {
  final List<File> items;
  final String currentPath;

  /// Defaults to the cached video thumbnails the file browser shows.
  final VideoPlaylistThumbnailBuilder? thumbnailBuilder;

  const VideoPlaylistPanel({
    super.key,
    required this.items,
    required this.currentPath,
    this.thumbnailBuilder,
  });

  @override
  State<VideoPlaylistPanel> createState() => _VideoPlaylistPanelState();
}

class _VideoPlaylistPanelState extends State<VideoPlaylistPanel> {
  static const double _itemExtent = 56;
  static const double _panelWidth = 380;
  static const double _thumbWidth = 72;
  static const double _thumbHeight = 40;

  late final int _currentIndex = widget.items.indexWhere(
    (f) => pathlib.equals(f.path, widget.currentPath),
  );
  late final ScrollController _scrollController = ScrollController(
    // Opens with the playing entry roughly in the middle of the list.
    initialScrollOffset: math.max(0, (_currentIndex - 3) * _itemExtent),
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final maxListHeight = math.max(
      _itemExtent * 2,
      math.min(media.size.height * 0.6, 480.0),
    );

    // Above the bottom control bar, against the right edge.
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 72),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(_panelWidth, media.size.width - 32),
            ),
            child: Material(
              color: Colors.black.withValues(alpha: 0.9),
              elevation: 12,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        const Icon(
                          PhosphorIconsLight.playlist,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.videoPlaylist,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          _currentIndex >= 0
                              ? '${_currentIndex + 1}/${widget.items.length}'
                              : '${widget.items.length}',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            PhosphorIconsLight.x,
                            color: Colors.white70,
                            size: 18,
                          ),
                          tooltip: l10n.close,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxListHeight),
                    child: ListView.builder(
                      controller: _scrollController,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemExtent: _itemExtent,
                      itemCount: widget.items.length,
                      itemBuilder: (context, index) =>
                          _buildItem(context, index),
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

  Widget _buildItem(BuildContext context, int index) {
    final file = widget.items[index];
    final isCurrent = index == _currentIndex;
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () => Navigator.of(context).pop(file),
      child: Container(
        color: isCurrent ? Colors.white.withValues(alpha: 0.1) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: isCurrent
                  ? Icon(PhosphorIconsFill.play, color: accent, size: 14)
                  : Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
            ),
            Container(
              width: _thumbWidth,
              height: _thumbHeight,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
                border: isCurrent
                    ? Border.all(color: accent, width: 1.5)
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: (widget.thumbnailBuilder ?? _defaultThumbnail)(
                file,
                _thumbWidth,
                _thumbHeight,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                pathlib.basename(file.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrent ? accent : Colors.white,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _defaultThumbnail(File file, double width, double height) {
    return LazyVideoThumbnail(
      videoPath: file.path,
      width: width,
      height: height,
      fit: BoxFit.cover,
      fallbackBuilder: () => const Center(
        child: Icon(
          PhosphorIconsLight.filmStrip,
          color: Colors.white38,
          size: 18,
        ),
      ),
    );
  }
}
