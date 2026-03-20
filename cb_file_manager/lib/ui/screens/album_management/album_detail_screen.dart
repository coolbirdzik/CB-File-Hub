import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/ui/screens/media_gallery/image_viewer_screen.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/ui/widgets/app_progress_indicator.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'create_album_dialog.dart';
import 'batch_add_dialog.dart';
import 'package:path/path.dart' as pathlib;
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/services/smart_album_service.dart';
import 'package:cb_file_manager/services/album_auto_rule_service.dart';
import 'auto_rules_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:cb_file_manager/ui/screens/folder_list/components/file_grid_item.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';

class AlbumDetailScreen extends StatefulWidget {
  final Album album;

  const AlbumDetailScreen({
    Key? key,
    required this.album,
  }) : super(key: key);

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final AlbumService _albumService = AlbumService.instance;

  List<File> _imageFiles = [];
  List<File> _originalImageFiles = [];
  bool _isLoading = true;
  bool _isSelectionMode = false;
  final Set<String> _selectedFilePaths = {};
  double _thumbnailSize = 3.0; // Grid crossAxisCount
  String? _searchQuery;
  bool _isShuffled = false;
  late UserPreferences _preferences;
  bool _isSmartAlbum = false;
  bool _cancelSmartScan = false;
  Timer? _autoRescanTimer;
  int _activeRulesCount = 0;
  int _sourceFoldersCount = 0;
  DateTime? _lastScanTime;

  // Listen album updates to refresh UI incrementally
  StreamSubscription<int>? _albumUpdateSub;
  StreamSubscription<Map<String, dynamic>>? _progressSub;
  Timer? _refreshDebounce;

  // Progress tracking state
  bool _isBackgroundProcessing = false;
  int _currentProgress = 0;
  int _totalProgress = 0;
  String _progressStatus = '';
  Timer? _progressDebounce;

  @override
  void initState() {
    super.initState();
    _preferences = UserPreferences.instance;
    _loadGridPreference();
    _initSmartStateAndLoad();

    // Subscribe to album updates and refresh grid progressively
    _albumUpdateSub = AlbumService.instance.albumUpdatedStream
        .where((id) => id == widget.album.id)
        .listen((_) => _scheduleAlbumReload());

    // Subscribe to progress updates
    _progressSub = AlbumService.instance.progressStream
        .where((progress) => progress['albumId'] == widget.album.id)
        .listen(_handleProgressUpdate);
  }

  Future<void> _initSmartStateAndLoad() async {
    try {
      _isSmartAlbum =
          await SmartAlbumService.instance.isSmartAlbum(widget.album.id);
    } catch (_) {
      _isSmartAlbum = false;
    }
    if (mounted) {
      if (_isSmartAlbum) {
        await _refreshSmartStatus();
        await _loadCachedSmartImages();
        _startAutoRescan();
      }
      _loadAlbumFiles(initial: true);
    }
  }

  Future<void> _refreshSmartStatus() async {
    try {
      final allRules = await AlbumAutoRuleService.instance.loadRules();
      final rules = allRules
          .where((r) => r.albumId == widget.album.id && r.isActive)
          .toList();
      final roots =
          await SmartAlbumService.instance.getScanRoots(widget.album.id);
      final last =
          await SmartAlbumService.instance.getLastScanTime(widget.album.id);
      if (mounted) {
        setState(() {
          _activeRulesCount = rules.length;
          _sourceFoldersCount = roots.length;
          _lastScanTime = last;
        });
      }
    } catch (_) {}
  }

  String _smartStatusText() {
    final last = _lastScanTime != null
        ? DateFormat('HH:mm dd/MM').format(_lastScanTime!)
        : 'Never';
    return '$_activeRulesCount rules • $_sourceFoldersCount sources • Last: $last';
  }

  Future<void> _loadGridPreference() async {
    try {
      await _preferences.init();
      final size = await _preferences.getImageGalleryThumbnailSize();
      if (mounted) {
        setState(() {
          _thumbnailSize = size;
        });
      }
    } catch (_) {}
  }

  void _handleProgressUpdate(Map<String, dynamic> progress) {
    // Debounce progress updates to avoid spamming UI thread
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {
          _isBackgroundProcessing = progress['status'] != 'completed' &&
              progress['status'] != 'error';
          _currentProgress = progress['current'] ?? 0;
          _totalProgress = progress['total'] ?? 0;

          switch (progress['status']) {
            case 'scanning':
              _progressStatus = 'Scanning files...';
              break;
            case 'processing':
              _progressStatus =
                  'Adding files... ($_currentProgress/$_totalProgress)';
              break;
            case 'completed':
              _progressStatus = 'Completed!';
              // Hide progress after 2 seconds
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) {
                  setState(() {
                    _isBackgroundProcessing = false;
                  });
                }
              });
              break;
            case 'error':
              _progressStatus =
                  'Error: ${progress['error'] ?? 'Unknown error'}';
              break;
          }
        });
      }
    });
  }

  Future<void> _loadAlbumFiles({bool initial = false}) async {
    if (initial) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      if (_isSmartAlbum) {
        await _scanSmartAlbumImages();
        return;
      }

      final albumFiles = await _albumService.getAlbumFiles(widget.album.id);
      final imageFiles = <File>[];

      for (final albumFile in albumFiles) {
        final file = File(albumFile.filePath);
        if (await file.exists()) {
          imageFiles.add(file);
        }
      }

      if (mounted) {
        setState(() {
          _originalImageFiles = List<File>.from(imageFiles);
          _applyFiltersAndOrder();
          _isLoading = false;
        });

        // Trigger thumbnail preloading for videos
        _preloadVideoThumbnails();
      }
    } catch (e) {
      debugPrint('Error loading album files: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _preloadVideoThumbnails() async {
    // Preload thumbnails for video files in the album
    try {
      final videoFiles = _imageFiles.where((file) {
        final extension = pathlib.extension(file.path).toLowerCase();
        final category = FileTypeRegistry.getCategory(extension);
        return category == FileCategory.video;
      }).toList();

      if (videoFiles.isEmpty) return;

      debugPrint(
          'Album: Preloading thumbnails for ${videoFiles.length} videos');

      // Batch preload with limited concurrency to avoid overwhelming the system
      const batchSize = 5;
      for (var i = 0; i < videoFiles.length; i += batchSize) {
        final batch = videoFiles.skip(i).take(batchSize).toList();
        await Future.wait(
          batch.map((file) => VideoThumbnailHelper.generateThumbnail(
                file.path,
                isPriority: false,
              ).catchError((e) {
                debugPrint('Failed to generate thumbnail for ${file.path}: $e');
                return null;
              })),
        );

        // Small delay between batches to prevent system overload
        if (i + batchSize < videoFiles.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      debugPrint('Album: Finished preloading video thumbnails');
    } catch (e) {
      debugPrint('Error preloading video thumbnails: $e');
    }
  }

  Future<void> _scanSmartAlbumImages() async {
    // Load active rules for this album
    final allRules = await AlbumAutoRuleService.instance.loadRules();
    final rules = allRules
        .where((r) => r.albumId == widget.album.id && r.isActive)
        .toList();
    if (mounted) {
      // Immediately prune any currently displayed items that no longer match rules
      if (rules.isNotEmpty && _originalImageFiles.isNotEmpty) {
        _originalImageFiles = _originalImageFiles.where((f) {
          final base = pathlib.basename(f.path);
          return rules.any((r) => r.matches(base));
        }).toList();
        _applyFiltersAndOrder();
      } else if (rules.isEmpty) {
        // No rules -> clear current items to reflect new config
        _originalImageFiles = [];
        _applyFiltersAndOrder();
      }
      setState(() {
        // Keep current cached display; only update incrementally during scan
        _cancelSmartScan = false;
        _isBackgroundProcessing = true;
        _isLoading = false; // Ensure grid is visible while scanning
        _progressStatus = rules.isEmpty
            ? 'No rules configured for this album'
            : 'Scanning...';
        _currentProgress = 0;
        _totalProgress = 0; // Unknown total -> indeterminate
      });
    }

    if (rules.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isBackgroundProcessing = false;
        });
      }
      return;
    }

    // Use configured scan roots if available; otherwise, stop and ask user to configure
    List<String> roots =
        await SmartAlbumService.instance.getScanRoots(widget.album.id);
    if (roots.isEmpty) {
      if (mounted) {
        setState(() {
          _isBackgroundProcessing = false;
          _progressStatus = 'No scan locations configured';
        });
      }
      return;
    }
    int matched = 0;
    int processed = 0;
    // Include both image and video extensions for smart album scanning
    final mediaExts = {
      // Image extensions
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.bmp',
      '.webp',
      '.tif',
      '.tiff',
      // Video extensions
      '.mp4',
      '.mkv',
      '.avi',
      '.mov',
      '.wmv',
      '.flv',
      '.webm',
      '.m4v',
      '.3gp',
      '.ts',
      '.mts',
      '.m2ts',
    };

    Future<void> scanDir(Directory dir) async {
      try {
        await for (final entity
            in dir.list(recursive: false, followLinks: false)) {
          if (_cancelSmartScan) return;
          if (entity is File) {
            processed++;
            final ext = pathlib.extension(entity.path).toLowerCase();
            if (mediaExts.contains(ext)) {
              final name = pathlib.basename(entity.path);
              if (rules.any((r) => r.matches(name))) {
                matched++;
                if (mounted) {
                  if (!_originalImageFiles.any((f) => f.path == entity.path)) {
                    _originalImageFiles.add(entity);
                  }
                  // Apply filters in-place to update UI progressively
                  _applyFiltersAndOrder();
                  // Update status occasionally
                  if (matched % 20 == 0 || processed % 200 == 0) {
                    setState(() {
                      _progressStatus = 'Scanning device... matched $matched';
                    });
                  }
                }
              }
            }
          } else if (entity is Directory) {
            // Recurse into subdirectory
            await scanDir(entity);
          }
        }
      } catch (_) {
        // Ignore directories we cannot access
      }
    }

    for (final rootPath in roots) {
      if (_cancelSmartScan) break;
      await scanDir(Directory(rootPath));
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _isBackgroundProcessing = false;
        _progressStatus = 'Completed! Found $matched files';
      });

      // Trigger thumbnail preloading for videos after smart scan completes
      _preloadVideoThumbnails();
    }

    // Cache results
    try {
      await SmartAlbumService.instance.setCachedFiles(
          widget.album.id, _originalImageFiles.map((f) => f.path).toList());
    } catch (_) {}
  }

  Future<void> _loadCachedSmartImages() async {
    try {
      final cached =
          await SmartAlbumService.instance.getCachedFiles(widget.album.id);
      if (cached.isNotEmpty && mounted) {
        // Load current active rules for this album and filter cached list to avoid stale/unfiltered cache
        final allRules = await AlbumAutoRuleService.instance.loadRules();
        final rules = allRules
            .where((r) => r.albumId == widget.album.id && r.isActive)
            .toList();

        final files = <File>[];
        for (final p in cached) {
          final f = File(p);
          if (f.existsSync()) {
            if (rules.isEmpty) {
              // If no rules, show nothing until a scan happens (consistent with scan path)
              // Skip adding files
            } else {
              final base = pathlib.basename(p);
              if (rules.any((r) => r.matches(base))) {
                files.add(f);
              }
            }
          }
        }

        setState(() {
          _originalImageFiles = files;
          _applyFiltersAndOrder();
          _isLoading = false;
        });

        // Trigger thumbnail preloading for videos after loading cached files
        _preloadVideoThumbnails();
      }
    } catch (_) {}
  }

  void _startAutoRescan() {
    _autoRescanTimer?.cancel();
    // Auto rescan every 5 minutes (lightweight incremental without true FS watchers)
    _autoRescanTimer = Timer.periodic(const Duration(minutes: 5), (t) {
      if (!_isBackgroundProcessing) {
        _scanSmartAlbumImages();
      }
    });
  }

  Future<void> _showManageSourcesDialog() async {
    final service = SmartAlbumService.instance;
    List<String> roots = await service.getScanRoots(widget.album.id);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) {
          List<String> localRoots = List.from(roots);
          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Scan Locations'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (localRoots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          'No locations selected. Add folders to scan for this album.',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                        ),
                      ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: localRoots.length,
                        itemBuilder: (context, index) {
                          final p = localRoots[index];
                          return ListTile(
                            dense: true,
                            leading: Icon(PhosphorIconsLight.folder),
                            title: Text(p,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(
                              icon: Icon(PhosphorIconsLight.trash,
                                  color: Theme.of(context).colorScheme.error),
                              onPressed: () {
                                setState(() {
                                  localRoots.removeAt(index);
                                });
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final dir =
                              await FilePicker.platform.getDirectoryPath();
                          if (dir != null && dir.isNotEmpty) {
                            setState(() {
                              if (!localRoots.contains(dir)) {
                                localRoots.add(dir);
                              }
                            });
                          }
                        },
                        icon: Icon(PhosphorIconsLight.plus),
                        label: const Text('Add folder'),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await service.setScanRoots(widget.album.id, localRoots);
                    if (mounted) {
                      Navigator.pop(context);
                    }
                    // Re-scan with new roots
                    if (mounted && _isSmartAlbum) {
                      _scanSmartAlbumImages();
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  void _scheduleAlbumReload() {
    // No debounce for instant UI feedback
    if (mounted) {
      _loadAlbumFiles();
    }
  }

  void _applyFiltersAndOrder() {
    // Start from original list
    List<File> files = List<File>.from(_originalImageFiles);

    // Apply search filter
    if (_searchQuery != null && _searchQuery!.trim().isNotEmpty) {
      final q = _searchQuery!.toLowerCase();
      files = files
          .where((f) => pathlib.basename(f.path).toLowerCase().contains(q))
          .toList();
    }

    // Apply shuffle
    if (_isShuffled) {
      files.shuffle();
    }

    _imageFiles = files;
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffled = !_isShuffled;
      _applyFiltersAndOrder();
    });
  }

  void _showSearchDialog() {
    String query = _searchQuery ?? '';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search in Album'),
        content: TextField(
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter image name...',
            prefixIcon: Icon(PhosphorIconsLight.magnifyingGlass),
          ),
          controller: TextEditingController(text: query),
          onChanged: (value) => query = value,
          onSubmitted: (_) {
            RouteUtils.safePopDialog(context);
            setState(() {
              _searchQuery = query.trim().isEmpty ? null : query.trim();
              _applyFiltersAndOrder();
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              RouteUtils.safePopDialog(context);
            },
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              RouteUtils.safePopDialog(context);
              setState(() {
                _searchQuery = query.trim().isEmpty ? null : query.trim();
                _applyFiltersAndOrder();
              });
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddFilesMenu() async {
    if (!mounted) return;
    final result = await showDialog(
      context: context,
      builder: (context) => BatchAddDialog(albumId: widget.album.id),
    );

    if (result != null && mounted) {
      String message;
      if (result is Map<String, dynamic>) {
        if (result.containsKey('error')) {
          message = 'Error: ${result['error']}';
        } else if (result.containsKey('background')) {
          message = 'Adding files in background...';
        } else {
          final added = result['added'] ?? 0;
          final total = result['total'] ?? 0;
          message = 'Added $added out of $total files';
        }
      } else {
        message = 'Files added successfully';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      // Only reload if not background operation
      if (result is Map<String, dynamic> && !result.containsKey('background')) {
        _loadAlbumFiles();
      }
    }
  }

  Future<void> _editAlbum() async {
    if (!mounted) return;
    final result = await showDialog<Album>(
      context: context,
      builder: (context) => CreateAlbumDialog(editingAlbum: widget.album),
    );

    if (result != null && mounted) {
      // Update the album reference and reload if needed
      setState(() {
        // The album object is updated in place
      });
    }
  }

  Future<void> _removeSelectedFiles() async {
    if (_selectedFilePaths.isEmpty) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            'Remove ${_selectedFilePaths.length} ${_selectedFilePaths.length == 1 ? 'image' : 'images'}?'),
        content: const Text(
            'Remove selected images from this album? The original files will not be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      int successCount = 0;
      for (final filePath in _selectedFilePaths) {
        if (await _albumService.removeFileFromAlbum(
            widget.album.id, filePath)) {
          successCount++;
        }
      }

      setState(() {
        _isSelectionMode = false;
        _selectedFilePaths.clear();
      });

      await _loadAlbumFiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Removed $successCount ${successCount == 1 ? 'image' : 'images'} from album'),
          ),
        );
      }
    }
  }

  int _resolveGridColumns() {
    final maxColumns = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.columns,
      minValue: UserPreferences.minThumbnailSize.round(),
      maxValue: UserPreferences.maxThumbnailSize.round(),
    );
    return _thumbnailSize
        .round()
        .clamp(UserPreferences.minThumbnailSize.round(), maxColumns)
        .toInt();
  }

  Widget _buildGridView() {
    final columns = _resolveGridColumns();

    return GridView.builder(
      padding: const EdgeInsets.all(8.0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _imageFiles.length,
      itemBuilder: (context, index) {
        final file = _imageFiles[index];
        final isSelected = _selectedFilePaths.contains(file.path);

        return FileGridItem(
          file: file,
          isSelected: isSelected,
          isSelectionMode: _isSelectionMode,
          isDesktopMode: true,
          toggleFileSelection: (path,
              {shiftSelect = false, ctrlSelect = false}) {
            setState(() {
              if (isSelected) {
                _selectedFilePaths.remove(path);
              } else {
                _selectedFilePaths.add(path);
              }
            });
          },
          toggleSelectionMode: () {
            setState(() {
              _isSelectionMode = !_isSelectionMode;
              if (!_isSelectionMode) {
                _selectedFilePaths.clear();
              }
            });
          },
          onFileTap: (file, isRightClick) {
            if (!isRightClick && !_isSelectionMode) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ImageViewerScreen(
                    file: file,
                    imageFiles: _imageFiles,
                    initialIndex: index,
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _albumUpdateSub?.cancel();
    _progressSub?.cancel();
    _refreshDebounce?.cancel();
    _progressDebounce?.cancel();
    _autoRescanTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSelectionMode) {
      return Scaffold(
        appBar: AppBar(
          title: Text('${_selectedFilePaths.length} selected'),
          leading: IconButton(
            icon: Icon(PhosphorIconsLight.x),
            onPressed: () {
              setState(() {
                _isSelectionMode = false;
                _selectedFilePaths.clear();
              });
            },
          ),
          actions: [
            IconButton(
              icon: Icon(PhosphorIconsLight.minusCircle),
              tooltip: 'Remove from album',
              onPressed:
                  _selectedFilePaths.isEmpty ? null : _removeSelectedFiles,
            ),
            IconButton(
              icon: Icon(PhosphorIconsLight.checkSquare),
              tooltip: 'Select all',
              onPressed: () {
                setState(() {
                  if (_selectedFilePaths.length == _imageFiles.length) {
                    _selectedFilePaths.clear();
                  } else {
                    _selectedFilePaths.addAll(_imageFiles.map((f) => f.path));
                  }
                });
              },
            ),
          ],
        ),
        body: _buildGridView(),
      );
    }

    return BaseScreen(
      title: widget.album.name,
      automaticallyImplyLeading: true,
      actions: [
        // Quick selection toggle
        IconButton(
          icon: Icon(PhosphorIconsLight.checks),
          tooltip: 'Select Images',
          onPressed: () {
            setState(() {
              _isSelectionMode = true;
            });
          },
        ),
        // Search in album
        IconButton(
          icon: Icon(PhosphorIconsLight.magnifyingGlass),
          tooltip: 'Search',
          onPressed: _showSearchDialog,
        ),
        // Grid size control
        IconButton(
          icon: Icon(PhosphorIconsLight.squaresFour),
          tooltip: 'Grid Size',
          onPressed: () => SharedActionBar.showGridSizeDialog(
            context,
            currentGridSize: _thumbnailSize.round(),
            onApply: (size) async {
              setState(() {
                _thumbnailSize = size.toDouble();
              });
              try {
                await _preferences
                    .setImageGalleryThumbnailSize(size.toDouble());
              } catch (_) {}
            },
            sizeMode: GridSizeMode.columns,
            minGridSize: UserPreferences.minThumbnailSize.round(),
            maxGridSize: UserPreferences.maxThumbnailSize.round(),
          ),
        ),
        // Shuffle toggle
        IconButton(
          icon: Icon(PhosphorIconsLight.shuffle),
          color: _isShuffled ? Theme.of(context).colorScheme.primary : null,
          tooltip: _isShuffled ? 'Unshuffle' : 'Shuffle',
          onPressed: _toggleShuffle,
        ),
        IconButton(
          icon: Icon(PhosphorIconsLight.plus),
          onPressed: _showAddFilesMenu,
          tooltip: 'Add images',
        ),
        PopupMenuButton<String>(
          onSelected: (value) async {
            switch (value) {
              case 'edit':
                _editAlbum();
                break;
              case 'select':
                setState(() {
                  _isSelectionMode = true;
                });
                break;
              case 'shuffle':
                _toggleShuffle();
                break;
              case 'clear_search':
                setState(() {
                  _searchQuery = null;
                  _applyFiltersAndOrder();
                });
                break;
              case 'manage_rules':
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AutoRulesScreen(
                      scopedAlbumId: widget.album.id,
                      scopedAlbumName: widget.album.name,
                    ),
                  ),
                );
                if (mounted && _isSmartAlbum) {
                  await _loadCachedSmartImages();
                  _scanSmartAlbumImages();
                }
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.pencilSimple),
                  SizedBox(width: 8),
                  Text('Edit Album'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'select',
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.checks),
                  SizedBox(width: 8),
                  Text('Select Images'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'shuffle',
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.shuffle),
                  SizedBox(width: 8),
                  Text('Shuffle'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'clear_search',
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.x),
                  SizedBox(width: 8),
                  Text('Clear Search'),
                ],
              ),
            ),
            if (_isSmartAlbum)
              PopupMenuItem(
                value: 'manage_rules',
                child: Row(
                  children: [
                    Icon(PhosphorIconsLight.faders),
                    SizedBox(width: 8),
                    Text('Manage Rules'),
                  ],
                ),
              ),
          ],
        ),
      ],
      body: Column(
        children: [
          if (_isSmartAlbum)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.sparkle, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Smart Album (dynamic by rules)'),
                        const SizedBox(height: 2),
                        Text(
                          _smartStatusText(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _showManageSourcesDialog,
                    icon: Icon(PhosphorIconsLight.folderOpen),
                    label: const Text('Sources'),
                  ),
                  if (_isBackgroundProcessing)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _cancelSmartScan = true;
                          _isBackgroundProcessing = false;
                          _progressStatus = 'Canceled';
                        });
                      },
                      icon: Icon(PhosphorIconsLight.x),
                      label: const Text('Cancel'),
                    ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () {
                      if (!_isBackgroundProcessing) {
                        setState(() {
                          _isLoading = true;
                        });
                        _scanSmartAlbumImages();
                      }
                    },
                    icon: Icon(PhosphorIconsLight.arrowsClockwise),
                    label: const Text('Rescan'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AutoRulesScreen(
                              scopedAlbumId: widget.album.id,
                              scopedAlbumName: widget.album.name),
                        ),
                      );
                      if (mounted && _isSmartAlbum) {
                        await _loadCachedSmartImages();
                        _scanSmartAlbumImages();
                        await _refreshSmartStatus();
                      }
                    },
                    icon: Icon(PhosphorIconsLight.faders),
                    label: const Text('Rules'),
                  ),
                ],
              ),
            ),
          if (_searchQuery != null && _searchQuery!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(PhosphorIconsLight.magnifyingGlass, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Search: "$_searchQuery"'),
                    ),
                    IconButton(
                      icon: Icon(PhosphorIconsLight.x, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          _searchQuery = null;
                          _applyFiltersAndOrder();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (_isBackgroundProcessing)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _progressStatus,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  AppProgressIndicator(
                    value: (_totalProgress > 0)
                        ? _currentProgress / _totalProgress
                        : null,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.2),
                  ),
                ],
              ),
            ),
          if (_isLoading && !_isBackgroundProcessing)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4.0),
              child: AppProgressIndicatorBeautiful(),
            ),
          Expanded(
            child: (_imageFiles.isEmpty && !_isLoading)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIconsLight.images,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery == null || _searchQuery!.isEmpty
                              ? 'No images in this album'
                              : 'No images match your search',
                          style: TextStyle(
                            fontSize: 18,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add images to start building your album',
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _showAddFilesMenu,
                          icon: Icon(PhosphorIconsLight.images),
                          label: const Text('Add Images'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(8.0),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _resolveGridColumns(),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _imageFiles.length,
                    itemBuilder: (context, index) {
                      final file = _imageFiles[index];
                      final filePath = file.path;
                      final isSelected = _selectedFilePaths.contains(filePath);

                      return FileGridItem(
                        file: file,
                        isSelected: isSelected,
                        isSelectionMode: _isSelectionMode,
                        isDesktopMode: true,
                        toggleFileSelection: (path,
                            {shiftSelect = false, ctrlSelect = false}) {
                          setState(() {
                            if (isSelected) {
                              _selectedFilePaths.remove(path);
                            } else {
                              _selectedFilePaths.add(path);
                            }
                          });
                        },
                        toggleSelectionMode: () {
                          setState(() {
                            _isSelectionMode = !_isSelectionMode;
                            if (!_isSelectionMode) {
                              _selectedFilePaths.clear();
                            }
                          });
                        },
                        onFileTap: (file, isRightClick) {
                          if (!isRightClick && !_isSelectionMode) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ImageViewerScreen(
                                  file: file,
                                  imageFiles: _imageFiles,
                                  initialIndex: index,
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFilesMenu,
        tooltip: 'Add images',
        child: Icon(PhosphorIconsLight.plus),
      ),
    );
  }
}
