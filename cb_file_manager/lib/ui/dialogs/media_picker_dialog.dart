import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/components/common/skeleton.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';

typedef MediaPickerFileMatcher = bool Function(String path);

class MediaPickerFilterOption {
  final String id;
  final String label;
  final MediaPickerFileMatcher matches;

  const MediaPickerFilterOption({
    required this.id,
    required this.label,
    required this.matches,
  });
}

enum MediaPickerViewMode {
  grid,
  list,
}

enum MediaPickerSort {
  name,
  modified,
}

class MediaPickerConfig {
  final String initialPath;
  final String? rootPath;
  final bool restrictToRoot;
  final String? title;
  final String? emptyMessage;
  final MediaPickerFileMatcher? fileFilter;
  final List<MediaPickerFilterOption> filters;
  final String? initialFilterId;
  final MediaPickerViewMode initialViewMode;
  final MediaPickerSort initialSort;
  final bool showSearch;
  final bool showSort;
  final bool showViewToggle;
  final bool showHidden;
  final bool showFolders;
  final bool showFiles;

  const MediaPickerConfig({
    required this.initialPath,
    this.rootPath,
    this.restrictToRoot = false,
    this.title,
    this.emptyMessage,
    this.fileFilter,
    this.filters = const [],
    this.initialFilterId,
    this.initialViewMode = MediaPickerViewMode.grid,
    this.initialSort = MediaPickerSort.name,
    this.showSearch = true,
    this.showSort = true,
    this.showViewToggle = true,
    this.showHidden = false,
    this.showFolders = true,
    this.showFiles = true,
  });
}

Future<String?> showMediaPickerDialog(
  BuildContext context,
  MediaPickerConfig config,
) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final mediaQuery = MediaQuery.of(dialogContext);
      final dialogWidth = mediaQuery.size.width * 0.92;
      final dialogHeight = mediaQuery.size.height * 0.78;

      return AlertDialog(
        title: Text(
            config.title ?? AppLocalizations.of(dialogContext)!.browseFiles),
        content: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: _MediaPickerDialog(
            config: config,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                Text(AppLocalizations.of(dialogContext)!.cancel.toUpperCase()),
          ),
        ],
      );
    },
  );
}

class _MediaPickerDialog extends StatefulWidget {
  final MediaPickerConfig config;

  const _MediaPickerDialog({
    required this.config,
  });

  @override
  State<_MediaPickerDialog> createState() => _MediaPickerDialogState();
}

class _MediaPickerDialogState extends State<_MediaPickerDialog> {
  late String _currentPath;
  late MediaPickerViewMode _viewMode;
  late MediaPickerSort _sortBy;
  String _searchQuery = '';
  String? _activeFilterId;
  bool _isLoading = false;
  String? _errorMessage;
  List<Directory> _directories = [];
  List<File> _files = [];
  final TextEditingController _searchController = TextEditingController();
  String? _rootPath;

  @override
  void initState() {
    super.initState();
    _currentPath = path.normalize(widget.config.initialPath);
    _rootPath = widget.config.rootPath != null
        ? path.normalize(widget.config.rootPath!)
        : null;
    _viewMode = widget.config.initialViewMode;
    _sortBy = widget.config.initialSort;
    if (widget.config.filters.isNotEmpty) {
      _activeFilterId =
          widget.config.initialFilterId ?? widget.config.filters.first.id;
    }
    _loadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizePath(String value) {
    final normalized = path.normalize(value);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool _isWithinRoot(String candidate) {
    if (_rootPath == null) {
      return true;
    }

    final root = _normalizePath(_rootPath!);
    final normalizedCandidate = _normalizePath(candidate);
    if (normalizedCandidate == root) {
      return true;
    }

    return path.isWithin(root, normalizedCandidate);
  }

  bool get _restrictToRoot => widget.config.restrictToRoot && _rootPath != null;

  bool get _canNavigateUp {
    final parent = path.dirname(_currentPath);
    if (parent == _currentPath) {
      return false;
    }

    if (!_restrictToRoot) {
      return true;
    }

    return _isWithinRoot(parent);
  }

  void _navigateToDirectory(String dirPath) {
    final normalized = path.normalize(dirPath);
    if (_restrictToRoot && !_isWithinRoot(normalized)) {
      return;
    }
    setState(() {
      _currentPath = normalized;
    });
    _loadEntries();
  }

  void _navigateUp() {
    if (!_canNavigateUp) {
      return;
    }
    _navigateToDirectory(path.dirname(_currentPath));
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final directory = Directory(_currentPath);
      if (!await directory.exists()) {
        setState(() {
          _directories = [];
          _files = [];
          _isLoading = false;
          _errorMessage = AppLocalizations.of(context)!.pathNotAccessible;
        });
        return;
      }

      final entities = await directory.list(followLinks: false).toList();
      final dirs = <Directory>[];
      final files = <File>[];

      for (final entity in entities) {
        final name = path.basename(entity.path);
        if (!widget.config.showHidden && name.startsWith('.')) {
          continue;
        }

        if (entity is Directory) {
          if (widget.config.showFolders) {
            dirs.add(entity);
          }
          continue;
        }

        if (entity is File) {
          if (!widget.config.showFiles) {
            continue;
          }
          final filter = widget.config.fileFilter;
          if (filter != null && !filter(entity.path)) {
            continue;
          }
          files.add(entity);
        }
      }

      _sortEntries(dirs, files);

      if (mounted) {
        setState(() {
          _directories = dirs;
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MediaPickerDialog: Error loading directory: $e');
      if (mounted) {
        setState(() {
          _directories = [];
          _files = [];
          _isLoading = false;
          _errorMessage = AppLocalizations.of(context)!.pathNotAccessible;
        });
      }
    }
  }

  void _sortEntries(List<Directory> dirs, List<File> files) {
    int compareByName(FileSystemEntity a, FileSystemEntity b) {
      return path
          .basename(a.path)
          .toLowerCase()
          .compareTo(path.basename(b.path).toLowerCase());
    }

    DateTime modified(FileSystemEntity entity) {
      try {
        return entity.statSync().modified;
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    switch (_sortBy) {
      case MediaPickerSort.name:
        dirs.sort(compareByName);
        files.sort(compareByName);
        break;
      case MediaPickerSort.modified:
        dirs.sort((a, b) => modified(b).compareTo(modified(a)));
        files.sort((a, b) => modified(b).compareTo(modified(a)));
        break;
    }
  }

  MediaPickerFilterOption? _activeFilter() {
    if (widget.config.filters.isEmpty) {
      return null;
    }
    final match = widget.config.filters
        .where((option) => option.id == _activeFilterId)
        .toList();
    return match.isNotEmpty ? match.first : widget.config.filters.first;
  }

  bool _matchesSearch(FileSystemEntity entity) {
    if (_searchQuery.isEmpty) {
      return true;
    }
    return path
        .basename(entity.path)
        .toLowerCase()
        .contains(_searchQuery.toLowerCase());
  }

  bool _matchesFilter(File file) {
    final filter = _activeFilter();
    if (filter == null) {
      return true;
    }
    return filter.matches(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final visibleDirs =
        _directories.where(_matchesSearch).toList(growable: false);
    final visibleFiles = _files
        .where((file) => _matchesSearch(file) && _matchesFilter(file))
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 520
            ? 2
            : width < 820
                ? 3
                : 4;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPathBar(context),
            const SizedBox(height: 8),
            _buildToolbar(context),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? Skeleton(
                      type: _viewMode == MediaPickerViewMode.grid
                          ? SkeletonType.grid
                          : SkeletonType.list,
                      crossAxisCount: crossAxisCount,
                      itemCount: 12,
                    )
                  : _buildContent(
                      context,
                      visibleDirs,
                      visibleFiles,
                      crossAxisCount,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPathBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        IconButton(
          onPressed: _canNavigateUp ? _navigateUp : null,
          tooltip: l10n.parentFolder,
          icon: const Icon(PhosphorIconsLight.arrowUp),
        ),
        Expanded(
          child: Tooltip(
            message: _currentPath,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                _currentPath,
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _loadEntries,
          tooltip: l10n.refresh,
          icon: const Icon(PhosphorIconsLight.arrowsClockwise),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showFilters = widget.config.filters.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.config.showSearch)
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value.trim();
              });
            },
            decoration: InputDecoration(
              hintText: l10n.search,
              prefixIcon: const Icon(PhosphorIconsLight.magnifyingGlass),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(PhosphorIconsLight.x),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              isDense: true,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.config.showSort)
              DropdownButton<MediaPickerSort>(
                value: _sortBy,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _sortBy = value;
                    _sortEntries(_directories, _files);
                  });
                },
                items: [
                  DropdownMenuItem(
                    value: MediaPickerSort.name,
                    child: Text(l10n.sortByName),
                  ),
                  DropdownMenuItem(
                    value: MediaPickerSort.modified,
                    child: Text(l10n.sortByDate),
                  ),
                ],
              ),
            if (widget.config.showViewToggle)
              ToggleButtons(
                isSelected: [
                  _viewMode == MediaPickerViewMode.grid,
                  _viewMode == MediaPickerViewMode.list,
                ],
                onPressed: (index) {
                  setState(() {
                    _viewMode = index == 0
                        ? MediaPickerViewMode.grid
                        : MediaPickerViewMode.list;
                  });
                },
                borderRadius: BorderRadius.circular(16.0),
                constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
                children: const [
                  Icon(PhosphorIconsLight.squaresFour),
                  Icon(PhosphorIconsLight.listBullets),
                ],
              ),
          ],
        ),
        if (showFilters) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.config.filters.map((filter) {
              return ChoiceChip(
                label: Text(filter.label),
                selected: filter.id == _activeFilterId,
                onSelected: (selected) {
                  if (!selected) {
                    return;
                  }
                  setState(() {
                    _activeFilterId = filter.id;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Directory> directories,
    List<File> files,
    int crossAxisCount,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    if (directories.isEmpty && files.isEmpty) {
      final emptyMessage = _searchQuery.isNotEmpty
          ? l10n.noFilesMatchFilter(_searchQuery)
          : (widget.config.emptyMessage ?? l10n.emptyFolder);
      return Center(
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
        ),
      );
    }

    return CustomScrollView(
      cacheExtent: 600,
      slivers: [
        if (directories.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(label: l10n.folders),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final directory = directories[index];
                return _DirectoryTile(
                  name: path.basename(directory.path),
                  onTap: () => _navigateToDirectory(directory.path),
                );
              },
              childCount: directories.length,
            ),
          ),
        ],
        if (files.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(label: l10n.files),
          ),
          _viewMode == MediaPickerViewMode.grid
              ? SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.86,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final file = files[index];
                      return _FileGridTile(
                        file: file,
                        onTap: () => Navigator.pop(context, file.path),
                      );
                    },
                    childCount: files.length,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final file = files[index];
                      return _FileListTile(
                        file: file,
                        onTap: () => Navigator.pop(context, file.path),
                      );
                    },
                    childCount: files.length,
                  ),
                ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.secondary,
            ),
      ),
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _DirectoryTile({
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(PhosphorIconsLight.folder, color: Colors.amber),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(PhosphorIconsLight.caretRight),
      onTap: onTap,
    );
  }
}

class _FileGridTile extends StatelessWidget {
  final File file;
  final VoidCallback onTap;

  const _FileGridTile({
    required this.file,
    required this.onTap,
  });

  bool get _isVideo => VideoThumbnailHelper.isSupportedVideoFormat(file.path);

  bool get _isImage => FileTypeUtils.isImageFile(file.path);

  @override
  Widget build(BuildContext context) {
    final fileName = path.basename(file.path);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: _FilePreview(
                file: file,
                isVideo: _isVideo,
                isImage: _isImage,
                previewSize: 180,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  final File file;
  final VoidCallback onTap;

  const _FileListTile({
    required this.file,
    required this.onTap,
  });

  bool get _isVideo => VideoThumbnailHelper.isSupportedVideoFormat(file.path);

  bool get _isImage => FileTypeUtils.isImageFile(file.path);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fileName = path.basename(file.path);
    final typeLabel = _isVideo
        ? l10n.video
        : _isImage
            ? l10n.image
            : l10n.file;

    return ListTile(
      dense: true,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: SizedBox(
          width: 56,
          height: 56,
          child: _FilePreview(
            file: file,
            isVideo: _isVideo,
            isImage: _isImage,
            previewSize: 80,
          ),
        ),
      ),
      title: Text(
        fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(typeLabel),
      onTap: onTap,
    );
  }
}

class _FilePreview extends StatelessWidget {
  final File file;
  final bool isVideo;
  final bool isImage;
  final double previewSize;

  const _FilePreview({
    required this.file,
    required this.isVideo,
    required this.isImage,
    required this.previewSize,
  });

  @override
  Widget build(BuildContext context) {
    if (isImage) {
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final cacheSize = (previewSize * devicePixelRatio).round();
      return Image.file(
        file,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, __, ___) => _fallbackTile(
          isVideo: false,
          isImage: true,
        ),
      );
    }

    if (isVideo) {
      return _PickerVideoThumbnail(
        videoPath: file.path,
        thumbnailSize: previewSize.round(),
        thumbnailQuality: previewSize >= 140 ? 55 : 45,
      );
    }

    return _fallbackTile(
      isVideo: false,
      isImage: false,
    );
  }
}

Widget _fallbackTile({
  required bool isVideo,
  required bool isImage,
}) {
  if (isVideo) {
    return Container(
      color: Colors.blueGrey[900],
      child: const Center(
        child: Icon(
          PhosphorIconsLight.videoCamera,
          color: Colors.white70,
          size: 36,
        ),
      ),
    );
  }

  if (isImage) {
    return Container(
      color: Colors.black12,
      child: const Center(
        child: Icon(
          PhosphorIconsLight.image,
          color: Colors.blueGrey,
          size: 36,
        ),
      ),
    );
  }

  return Container(
    color: Colors.black12,
    child: const Center(
      child: Icon(
        PhosphorIconsLight.file,
        color: Colors.blueGrey,
        size: 36,
      ),
    ),
  );
}

class _PickerVideoThumbnail extends StatefulWidget {
  final String videoPath;
  final int thumbnailSize;
  final int thumbnailQuality;

  const _PickerVideoThumbnail({
    required this.videoPath,
    required this.thumbnailSize,
    required this.thumbnailQuality,
  });

  @override
  State<_PickerVideoThumbnail> createState() => _PickerVideoThumbnailState();
}

class _PickerVideoThumbnailState extends State<_PickerVideoThumbnail> {
  String? _thumbnailPath;
  bool _isLoading = false;
  bool _requested = false;
  StreamSubscription<String>? _thumbReadySubscription;

  @override
  void initState() {
    super.initState();
    _thumbReadySubscription =
        VideoThumbnailHelper.onThumbnailReady.listen((readyPath) async {
      if (readyPath != widget.videoPath) {
        return;
      }
      final cached = await VideoThumbnailHelper.getFromCache(readyPath);
      if (!mounted || cached == null) {
        return;
      }
      setState(() {
        _thumbnailPath = cached;
        _isLoading = false;
      });
    });
    _loadCached();
  }

  @override
  void dispose() {
    _thumbReadySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCached() async {
    final cached = await VideoThumbnailHelper.getFromCache(widget.videoPath);
    if (!mounted || cached == null) {
      return;
    }
    setState(() {
      _thumbnailPath = cached;
    });
  }

  void _startGeneration() {
    if (_requested || _isLoading) {
      return;
    }
    _requested = true;
    setState(() {
      _isLoading = true;
    });

    VideoThumbnailHelper.generateThumbnail(
      widget.videoPath,
      isPriority: true,
      quality: widget.thumbnailQuality,
      thumbnailSize: widget.thumbnailSize,
    ).then((path) {
      if (!mounted) return;
      setState(() {
        _thumbnailPath = path ?? _thumbnailPath;
        _isLoading = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        VisibilityDetector(
          key: ValueKey('media-picker-video-${widget.videoPath}'),
          onVisibilityChanged: (info) {
            if (info.visibleFraction > 0.15 && _thumbnailPath == null) {
              _startGeneration();
            }
          },
          child: _buildContent(),
        ),
        const Positioned(
          right: 6,
          bottom: 6,
          child: Icon(
            PhosphorIconsLight.playCircle,
            color: Colors.white,
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final path = _thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }

    if (_isLoading) {
      return ShimmerBox(
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.circular(16.0),
      );
    }

    return _fallbackTile(isVideo: true, isImage: false);
  }
}
