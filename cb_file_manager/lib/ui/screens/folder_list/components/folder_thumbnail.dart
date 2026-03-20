import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/helpers/media/folder_thumbnail_service.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/components/common/skeleton.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Widget for displaying folder thumbnail
class FolderThumbnail extends StatefulWidget {
  final Directory folder;
  final double size;

  const FolderThumbnail({
    Key? key,
    required this.folder,
    this.size = 80,
  }) : super(key: key);

  @override
  State<FolderThumbnail> createState() => _FolderThumbnailState();
}

class _FolderThumbnailState extends State<FolderThumbnail> {
  final FolderThumbnailService _thumbnailService = FolderThumbnailService();
  String? _thumbnailPath;
  String? _videoPath;
  String? _cachedVideoThumbnailPath;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _disposed = false;
  bool _isVideoThumbnailLoading = false;
  bool _videoThumbnailRequested = false;
  Timer? _videoThumbnailDelay;
  StreamSubscription<String>? _thumbnailChangedSubscription;
  StreamSubscription<String>? _videoThumbnailReadySubscription;
  StreamSubscription<void>? _cacheChangedSubscription;

  // Cache for this specific widget instance
  static final Map<String, String> _folderThumbnailPathCache = {};
  bool _pendingFallback = false;

  @override
  void initState() {
    super.initState();
    _thumbnailChangedSubscription =
        _thumbnailService.onThumbnailChanged.listen((folderPath) {
      if (folderPath == widget.folder.path) {
        _folderThumbnailPathCache.remove(folderPath);
        _loadThumbnail();
      }
    });

    _cacheChangedSubscription = VideoThumbnailHelper.onCacheChanged.listen((_) {
      if (_disposed) return;
      _folderThumbnailPathCache.remove(widget.folder.path);
      if (mounted) {
        setState(() {
          _cachedVideoThumbnailPath = null;
          if (_videoPath != null) {
            _isVideoThumbnailLoading = true;
          }
        });

        if (_videoPath != null) {
          _scheduleVideoThumbnailGeneration(_videoPath!);
        } else {
          _loadThumbnail();
        }
      }
    });

    _loadFromCacheOrFetch();
    _videoThumbnailReadySubscription =
        VideoThumbnailHelper.onThumbnailReady.listen((readyVideoPath) async {
      if (_videoPath == null || readyVideoPath != _videoPath) {
        return;
      }

      final cached = await VideoThumbnailHelper.getFromCache(readyVideoPath);
      if (cached == null || _disposed) {
        return;
      }

      setState(() {
        _cachedVideoThumbnailPath = cached;
        _isVideoThumbnailLoading = false;
      });
    });
  }

  @override
  void didUpdateWidget(FolderThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.path != widget.folder.path) {
      _videoPath = null;
      _cachedVideoThumbnailPath = null;
      _isVideoThumbnailLoading = false;
      _videoThumbnailRequested = false;
      _videoThumbnailDelay?.cancel();
      _loadFromCacheOrFetch();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _thumbnailChangedSubscription?.cancel();
    _videoThumbnailReadySubscription?.cancel();
    _cacheChangedSubscription?.cancel();
    _videoThumbnailDelay?.cancel();
    super.dispose();
  }

  void _loadFromCacheOrFetch() {
    final cached = _folderThumbnailPathCache[widget.folder.path];
    if (cached != null && _isCachedPathValid(cached)) {
      // Apply immediately without awaiting for faster display
      _isLoading = false;
      _applyFolderThumbnailPath(cached);
      return;
    }
    if (cached != null) {
      _folderThumbnailPathCache.remove(widget.folder.path);
    }
    _loadThumbnail();
  }

  bool _isCachedPathValid(String cached) {
    if (_isVideoPath(cached)) {
      final videoPath = _getVideoPath(cached);
      return videoPath.isNotEmpty && File(videoPath).existsSync();
    }
    return File(cached).existsSync();
  }

  void _reloadThumbnailAfterInvalidCache() {
    if (_disposed || _isLoading) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _isLoading) {
        return;
      }
      _folderThumbnailPathCache.remove(widget.folder.path);
      _loadThumbnail();
    });
  }

  Future<void> _fallbackToImageIfPossible() async {
    if (_pendingFallback || _disposed) {
      return;
    }
    _pendingFallback = true;

    try {
      final hasCustom =
          await _thumbnailService.hasCustomThumbnail(widget.folder.path);
      if (hasCustom) {
        return;
      }

      final imagePath =
          await _thumbnailService.findFirstImageInFolder(widget.folder.path);
      if (imagePath == null) {
        return;
      }

      await _thumbnailService.setAutoThumbnail(
        widget.folder.path,
        imagePath,
      );
      _folderThumbnailPathCache[widget.folder.path] = imagePath;

      if (!_disposed) {
        setState(() {
          _thumbnailPath = imagePath;
          _videoPath = null;
          _cachedVideoThumbnailPath = null;
          _isVideoThumbnailLoading = false;
          _videoThumbnailRequested = false;
        });
      }
    } finally {
      _pendingFallback = false;
    }
  }

  Future<void> _loadThumbnail() async {
    if (_disposed) return;

    // Only show loading if we don't already have a thumbnail
    if (_thumbnailPath == null) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }

    try {
      final path =
          await _thumbnailService.getFolderThumbnail(widget.folder.path);

      if (_disposed) return;

      // Cache the result for future use
      if (path != null) {
        _folderThumbnailPathCache[widget.folder.path] = path;
      }

      await _applyFolderThumbnailPath(path);
    } catch (e) {
      debugPrint(
          'Error loading thumbnail for folder ${widget.folder.path}: $e');
      if (!_disposed) {
        setState(() {
          _thumbnailPath = null;
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  bool _isVideoPath(String? path) {
    if (path == null) return false;
    return path.startsWith("video::");
  }

  String _getVideoPath(String path) {
    if (!path.startsWith("video::")) return path;

    final parts = path.split("::");
    if (parts.length >= 3) {
      return parts[1];
    }
    return path.substring(7);
  }

  String _getThumbnailPath(String path) {
    if (!path.startsWith("video::")) return path;

    final parts = path.split("::");
    if (parts.length >= 3) {
      return parts[2];
    }
    return path.substring(7);
  }

  @override
  Widget build(BuildContext context) {
    // Use a RepaintBoundary with a key based on the folder path to prevent repainting
    return RepaintBoundary(
      key: ValueKey('folder-thumbnail-${widget.folder.path}'),
      child: _buildThumbnailContent(context),
    );
  }

  Widget _buildThumbnailContent(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_isLoading) {
      return _buildLoadingPlaceholder();
    }

    // Default folder icon when no thumbnail
    if (_thumbnailPath == null || _loadFailed) {
      return Center(
        child: Icon(
          PhosphorIconsLight.folder,
          size: widget.size * 0.7,
          color: primaryColor,
        ),
      );
    }

    final bool isVideo = _isVideoPath(_thumbnailPath);
    final String videoPath = isVideo ? _getVideoPath(_thumbnailPath!) : '';
    final String thumbnailPath = _getThumbnailPath(_thumbnailPath!);

    try {
      if (isVideo) {
        if (!File(videoPath).existsSync()) {
          debugPrint('Video file does not exist: $videoPath');
          _reloadThumbnailAfterInvalidCache();
          return _buildFolderIcon(context);
        }

        final cachedPath = _cachedVideoThumbnailPath;
        final hasCached = cachedPath != null && File(cachedPath).existsSync();
        if (cachedPath != null && !hasCached && !_videoThumbnailRequested) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_disposed || !mounted) return;
            setState(() {
              _cachedVideoThumbnailPath = null;
              _isVideoThumbnailLoading = true;
              _videoThumbnailRequested = false;
            });
            _scheduleVideoThumbnailGeneration(videoPath);
          });
        }

        return Container(
          width: double.infinity,
          height: double.infinity,
          margin: const EdgeInsets.all(1),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasCached)
                Image.file(
                  File(cachedPath),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Error loading folder video thumbnail: $error');
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _cachedVideoThumbnailPath == cachedPath) {
                        _reloadThumbnailAfterInvalidCache();
                      }
                    });
                    return _buildFolderIcon(context);
                  },
                )
              else if (_isVideoThumbnailLoading)
                ShimmerBox(
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.circular(16.0),
                )
              else
                _buildFolderIcon(context),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  child: Icon(
                    PhosphorIconsLight.play,
                    color: Colors.white,
                    size: widget.size * 0.25 < 16 ? widget.size * 0.25 : 16,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        final file = File(thumbnailPath);
        if (!file.existsSync()) {
          debugPrint('Image file does not exist: $thumbnailPath');
          _reloadThumbnailAfterInvalidCache();
          return _buildFolderIcon(context);
        }

        return Container(
          width: double.infinity,
          height: double.infinity,
          margin: const EdgeInsets.all(1),
          child: ThumbnailLoader(
            filePath: thumbnailPath,
            isVideo: false,
            isImage: true,
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(1),
            fit: BoxFit.contain,
            fallbackBuilder: () => _buildFolderIcon(context),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error rendering folder thumbnail: $e');
      return _buildFolderIcon(context);
    }
  }

  Widget _buildFolderIcon(BuildContext context) {
    return Center(
      child: Icon(
        PhosphorIconsLight.folder,
        size: widget.size * 0.7,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Future<void> _applyFolderThumbnailPath(String? path) async {
    if (_disposed) return;

    String? videoPath;
    String? cachedVideoThumbnailPath;
    if (path != null && _isVideoPath(path)) {
      videoPath = _getVideoPath(path);
      cachedVideoThumbnailPath =
          await VideoThumbnailHelper.getFromCache(videoPath);
    }

    if (_disposed) return;

    setState(() {
      _thumbnailPath = path;
      _videoPath = videoPath;
      _cachedVideoThumbnailPath = cachedVideoThumbnailPath;
      _isLoading = false;
      _loadFailed = false;
      _isVideoThumbnailLoading =
          videoPath != null && cachedVideoThumbnailPath == null;
      _videoThumbnailRequested = false;
    });

    if (videoPath != null && cachedVideoThumbnailPath == null) {
      _scheduleVideoThumbnailGeneration(videoPath);
    }
  }

  void _scheduleVideoThumbnailGeneration(String videoPath) {
    if (_videoThumbnailRequested) {
      return;
    }
    _videoThumbnailRequested = true;

    _videoThumbnailDelay?.cancel();
    // Reduced delay for faster thumbnail generation
    _videoThumbnailDelay = Timer(const Duration(milliseconds: 5), () {
      if (_disposed) return;
      _startVideoThumbnailGeneration(videoPath);
    });
  }

  void _startVideoThumbnailGeneration(String videoPath) {
    final targetSize = (widget.size * 1.6).round().clamp(120, 160);

    VideoThumbnailHelper.generateThumbnail(
      videoPath,
      isPriority: true,
      quality: 45,
      thumbnailSize: targetSize,
    ).then((thumbPath) {
      if (_disposed) return;
      if (thumbPath != null && File(thumbPath).existsSync()) {
        setState(() {
          _cachedVideoThumbnailPath = thumbPath;
          _isVideoThumbnailLoading = false;
        });
      } else {
        setState(() {
          _isVideoThumbnailLoading = false;
        });
        unawaited(_fallbackToImageIfPossible());
      }
    }).catchError((_) {
      if (_disposed) return;
      setState(() {
        _isVideoThumbnailLoading = false;
      });
      unawaited(_fallbackToImageIfPossible());
    });
  }

  Widget _buildLoadingPlaceholder() {
    return ShimmerBox(
      width: double.infinity,
      height: double.infinity,
      borderRadius: BorderRadius.circular(16.0),
    );
  }
}

// Helper function to determine if we're on desktop
bool get isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;
