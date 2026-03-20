import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:path/path.dart' as pathlib;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import '../../components/video/thumbnail_strip.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:share_plus/share_plus.dart'; // Add import for Share Plus
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
// Add import for XFile
import '../../utils/route.dart';
import 'package:open_filex/open_filex.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';

class ImageViewerScreen extends StatefulWidget {
  final File file;
  final List<File>? imageFiles; // Optional list of all images in the folder
  final int initialIndex; // When provided with imageFiles, start at this index
  final Uint8List? imageBytes; // Optional preloaded bytes for immediate display

  const ImageViewerScreen({
    Key? key,
    required this.file,
    this.imageFiles,
    this.initialIndex = 0,
    this.imageBytes,
  }) : super(key: key);

  @override
  ImageViewerScreenState createState() => ImageViewerScreenState();
}

class ImageViewerScreenState extends State<ImageViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late TransformationController _transformationController;
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  late List<File> _allImages;
  int _currentIndex = 0;
  bool _isFullscreen = false;
  bool _controlsVisible = true;
  bool _showThumbnailStrip =
      true; // Biến để kiểm soát việc hiển thị thanh thumbnail
  double _rotation = 0.0;
  double _brightness = 0.0;
  double _contrast = 0.0;
  bool _isEditMode = false;
  bool _slideshowPlaying = false;
  final Duration _slideshowInterval = const Duration(seconds: 3);
  Timer? _slideshowTimer;

  // Thêm map để cache dữ liệu ảnh đã tải
  final Map<String, Uint8List> _imageCache = {};
  // Biến để theo dõi ảnh đang tải
  final Set<String> _loadingImages = {};
  // Kích thước tối đa của cache (số lượng ảnh)
  final int _maxCacheSize = 5;

  final double _minScale = 0.5;
  final double _maxScale = 5.0;
  
  // Check if platform is mobile
  bool _isMobile() {
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    
    // Image is precached before navigation, no need to evict
    _initImageList();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (_animation != null) {
          _transformationController.value = _animation!.value;
        }
      });

    // Tiền tải ảnh hiện tại và các ảnh hàng xóm
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchNeighboringImages();
    });
    // Force a repaint shortly after first frame to avoid initial black overlay on some Android devices
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() {});
      }
    });

    // Apply frame timing optimization for better performance
    FrameTimingOptimizer().optimizeImageRendering();

    // Configure system UI
    if (_isMobile()) {
      // On mobile, show full UI (both status bar and nav bar)
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    } else {
      // On desktop, keep bottom nav visible
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
          overlays: [SystemUiOverlay.bottom]);
    }
  }

  void _initImageList() {
    if (widget.imageFiles != null) {
      _allImages = List.from(widget.imageFiles!);
      _currentIndex = widget.initialIndex;
    } else {
      _allImages = [widget.file];
      _currentIndex = 0;
    }

    _pageController = PageController(initialPage: _currentIndex);

    // Load image list from directory if not provided
    if (widget.imageFiles == null) {
      _loadImagesFromDirectory();
    }
  }

  Future<void> _loadImagesFromDirectory() async {
    try {
      final directory = Directory(pathlib.dirname(widget.file.path));
      if (await directory.exists()) {
        final entities = await directory.list().toList();

        final images = entities.whereType<File>().where((file) {
          return FileTypeUtils.isImageFile(file.path);
        }).toList();

        // Sort images by name
        images.sort((a, b) => pathlib
            .basename(a.path)
            .toLowerCase()
            .compareTo(pathlib.basename(b.path).toLowerCase()));

        // Find current image index based on absolute path comparison
        final currentPath = widget.file.path;
        final index = images.indexWhere(
            (file) => file.path == currentPath // Exact path matching
            );

        if (mounted) {
          setState(() {
            // Only update the list if we found images
            if (images.isNotEmpty) {
              // Make sure the current image is in the list and index is valid
              if (index >= 0) {
                // If we have imageBytes (screenshot case), reorder list to put screenshot first
                // This keeps PageController at page 0 showing the correct image
                if (widget.imageBytes != null && index != 0) {
                  debugPrint('🔄 Reordering list - moving screenshot from index $index to 0');
                  final screenshot = images[index];
                  images.removeAt(index);
                  images.insert(0, screenshot);
                  debugPrint('   ✅ Screenshot now at index 0');
                }
                
                _allImages = images;
                // Keep _currentIndex = 0 to match PageController
                debugPrint('📋 Updated image list: ${images.length} images');
                debugPrint('   Current page: $_currentIndex');

                // Pre-load neighboring images
                _loadAndCacheImage(images[_currentIndex]);
                if (_currentIndex > 0) {
                  _loadAndCacheImage(images[_currentIndex - 1]);
                }
                if (_currentIndex < images.length - 1) {
                  _loadAndCacheImage(images[_currentIndex + 1]);
                }
              } else {
                // If we somehow can't find the image in the directory
                debugPrint(
                    'Warning: Could not find current image in directory. Path: $currentPath');
                _allImages = [widget.file];
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading images from directory: $e');
    }
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _pageController.dispose();
    _transformationController.dispose();
    _animationController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    super.dispose();
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_animationController.isAnimating) return;

    if (_transformationController.value != Matrix4.identity()) {
      // Reset to identity if already zoomed in
      _animation = Matrix4Tween(
        begin: _transformationController.value,
        end: Matrix4.identity(),
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ));
    } else {
      // Zoom in around tap point
      final position = details.localPosition;

      // Calculate the focal point for zooming (centered on the tap position)
      const double scale = 2.5;

      // Create a transformation matrix that zooms to a scale of 2.5x
      // centered on the position that was double-tapped
      final Matrix4 zoomed = Matrix4.identity()
        ..translateByVector3(Vector3(position.dx, position.dy, 0))
        ..scaleByVector3(Vector3(scale, scale, 1))
        ..translateByVector3(Vector3(-position.dx, -position.dy, 0));

      _animation = Matrix4Tween(
        begin: _transformationController.value,
        end: zoomed,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ));
    }

    _animationController.forward(from: 0);
  }

  void _resetTransformation() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _animationController.forward(from: 0);
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });

    if (_isMobile()) {
      if (_controlsVisible) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
      if (_isFullscreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
      }
    });
  }

  void _rotateImage() {
    setState(() {
      _rotation += 90.0;
      if (_rotation >= 360.0) {
        _rotation = 0.0;
      }
    });
    _resetTransformation();
  }

  void _rotateImageLeft() {
    setState(() {
      _rotation -= 90.0;
      if (_rotation <= -360.0) {
        _rotation = 0.0;
      }
    });
    _resetTransformation();
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
      if (!_isEditMode) {
        // Reset adjustments when exiting edit mode
        _brightness = 0.0;
        _contrast = 0.0;
      }
    });
  }

  void _toggleThumbnailStrip() {
    setState(() {
      _showThumbnailStrip = !_showThumbnailStrip;
    });
  }

  void _showImageInfo(BuildContext context, File file) async {
    try {
      final fileStat = await file.stat();
      final fileSize = _formatFileSize(fileStat.size);
      final modified = fileStat.modified;

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Image Details'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _infoRow('File name', pathlib.basename(file.path)),
                    const Divider(),
                    _infoRow('Path', file.path),
                    const Divider(),
                    _infoRow('Size', fileSize),
                    const Divider(),
                    _infoRow('Type', pathlib.extension(file.path).toUpperCase()),
                    const Divider(),
                    _infoRow('Last modified',
                        '${modified.day}/${modified.month}/${modified.year} ${modified.hour}:${modified.minute.toString().padLeft(2, '0')}'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    RouteUtils.safePopDialog(context);
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      }
    } catch (e) {
      debugPrint('Error showing image info: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to display image information: $e')),
        );
      }
    }
  }

  Future<void> _deleteImage(BuildContext context) async {
    final file = _allImages[_currentIndex];

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Trash'),
        content: Text(
            'Are you sure you want to move "${pathlib.basename(file.path)}" to trash?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('MOVE TO TRASH',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Use TrashManager instead of directly deleting
        final success = await TrashManager().moveToTrash(file.path);

        if (context.mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Image moved to trash')),
            );

            setState(() {
              _allImages.removeAt(_currentIndex);
              if (_allImages.isEmpty) {
                // No more images to show, return to previous screen
                RouteUtils.safePopDialog(context);
              } else {
                // Adjust current index if needed
                if (_currentIndex >= _allImages.length) {
                  _currentIndex = _allImages.length - 1;
                }
              }
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to move image to trash')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to move image to trash: $e')),
          );
        }
      }
    }
  }

  void _copyPathToClipboard() async {
    final file = _allImages[_currentIndex];
    await Clipboard.setData(ClipboardData(text: file.path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copied path to clipboard')),
      );
    }
  }

  Future<void> _openWithExternalApp() async {
    final file = _allImages[_currentIndex];
    bool opened = false;

    try {
      if (Platform.isAndroid) {
        opened = await ExternalAppHelper.openWithSystemChooser(file.path);
      } else {
        final result = await OpenFilex.open(file.path);
        opened = result.type == ResultType.done;
      }
    } catch (e) {
      opened = false;
    }

    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open with external app')),
      );
    }
  }

  void _toggleSlideshow() {
    if (_slideshowPlaying) {
      _slideshowTimer?.cancel();
      setState(() {
        _slideshowPlaying = false;
      });
      return;
    }

    _slideshowTimer?.cancel();
    _slideshowTimer = Timer.periodic(_slideshowInterval, (_) {
      if (!mounted) return;
      if (_allImages.length <= 1) return;
      if (_currentIndex < _allImages.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _pageController.animateToPage(0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut);
      }
    });

    setState(() {
      _slideshowPlaying = true;
    });
  }

  void _zoomReset() {
    _resetTransformation();
  }

  void _zoomIn() {
    _applyZoomRelative(1.25);
  }

  void _zoomOut() {
    _applyZoomRelative(0.8);
  }

  void _applyZoomRelative(double factor) {
    if (_animationController.isAnimating) return;
    final size = MediaQuery.of(context).size;
    final focal = Offset(size.width / 2, size.height / 2);

    final current = _transformationController.value;
    final currentScale = current.getMaxScaleOnAxis();
    double newScale = (currentScale * factor).clamp(_minScale, _maxScale);
    final double relative = (newScale / (currentScale == 0 ? 1 : currentScale));

    final Matrix4 zoomAroundCenter = Matrix4.identity()
      ..translateByVector3(Vector3(focal.dx, focal.dy, 0))
      ..scaleByVector3(Vector3(relative, relative, 1))
      ..translateByVector3(Vector3(-focal.dx, -focal.dy, 0));

    final Matrix4 target = zoomAroundCenter.multiplied(current);

    _animation = Matrix4Tween(
      begin: current,
      end: target,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    _animationController.forward(from: 0);
  }

  void _shareImage() {
    final file = _allImages[_currentIndex];
    final XFile xFile = XFile(file.path);
    Share.shareXFiles([xFile], text: 'Check out this image!');
  }

  // Phương thức để tải và cache ảnh
  Future<Uint8List?> _loadAndCacheImage(File file) async {
    final path = file.path;

    // Nếu đang tải, chờ đợi và không thực hiện tải lại
    if (_loadingImages.contains(path)) {
      // Chờ đợi cho đến khi ảnh được tải và cache
      int attempts = 0;
      while (_loadingImages.contains(path) && attempts < 100) {
        await Future.delayed(const Duration(milliseconds: 50));
        attempts++;
      }
      return _imageCache[path];
    }

    // Nếu đã có trong cache, trả về ngay
    if (_imageCache.containsKey(path)) {
      return _imageCache[path];
    }

    // Bắt đầu tải ảnh
    _loadingImages.add(path);

    try {
      // Đọc dữ liệu ảnh
      final bytes = await file.readAsBytes();

      // Lưu vào cache
      _imageCache[path] = bytes;

      // Quản lý kích thước cache - xóa mục cũ nhất nếu vượt giới hạn
      if (_imageCache.length > _maxCacheSize) {
        final oldest = _imageCache.keys.first;
        _imageCache.remove(oldest);
      }

      return bytes;
    } catch (e) {
      debugPrint('Error loading image $path: $e');
      return null;
    } finally {
      _loadingImages.remove(path);
    }
  }

  // Phương thức tiền tải ảnh hàng xóm
  void _prefetchNeighboringImages() {
    if (_allImages.length <= 1) return;

    // Tải ảnh hiện tại nếu chưa được tải
    _loadAndCacheImage(_allImages[_currentIndex]);

    // Tải ảnh tiếp theo nếu có
    if (_currentIndex < _allImages.length - 1) {
      _loadAndCacheImage(_allImages[_currentIndex + 1]);
    }

    // Tải ảnh trước đó nếu có
    if (_currentIndex > 0) {
      _loadAndCacheImage(_allImages[_currentIndex - 1]);
    }
  }

  // Build image widget - use Image.memory for preloaded bytes, Image.file otherwise
  Widget _buildImageWidget(File file, int index) {
    // Use preloaded bytes if this file matches the widget.file path
    final useBytes = file.path == widget.file.path && widget.imageBytes != null;
    
    if (useBytes) {
      debugPrint('📸 Using Image.memory for screenshot: ${file.path}');
      debugPrint('   Bytes length: ${widget.imageBytes!.length}');
      return Image.memory(
        widget.imageBytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) {
            debugPrint('   ✅ Image loaded synchronously');
            return child;
          }
          if (frame != null) {
            debugPrint('   ✅ Frame available: $frame');
            return child;
          }
          debugPrint('   ⏳ Waiting for frame...');
          return Center(
            child: CircularProgressIndicator(
              color: Colors.white.withAlpha(179),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          debugPrint('   ❌ Image.memory error: $error');
          debugPrint('   Stack: $stackTrace');
          return _buildErrorWidget(error);
        },
      );
    }
    
    return Image.file(
      file,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return Center(
          child: CircularProgressIndicator(
            color: Colors.white.withAlpha(179),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorWidget(error);
      },
    );
  }

  Widget _buildErrorWidget(Object error) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(PhosphorIconsLight.imageBroken, size: 80, color: Colors.white.withAlpha(179)),
        const SizedBox(height: 16),
        Text('Failed to display image',
            style: TextStyle(color: Colors.white.withAlpha(179))),
        const SizedBox(height: 8),
        Text(
          error.toString(),
          style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_allImages.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('No images to display'),
        ),
      );
    }

    // If in normal viewing mode (not editing)
    if (!_isEditMode) {
      return RawKeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKey: (RawKeyEvent event) {
          if (event is RawKeyDownEvent) {
            // Handle escape key press to exit the image viewer
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              RouteUtils.safePopDialog(context);
              return;
            }

            // Handle left arrow key press
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                _currentIndex > 0) {
              _pageController.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
            // Handle right arrow key press
            else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
                _currentIndex < _allImages.length - 1) {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: null,
          extendBody: false,
          extendBodyBehindAppBar: false,
          resizeToAvoidBottomInset: false,
          body: Column(
            children: [
              // Custom top bar
              if (_controlsVisible)
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.55),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(PhosphorIconsLight.arrowLeft),
                          color: Colors.white,
                          tooltip: 'Back',
                          onPressed: () => RouteUtils.safePopDialog(context),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return ClipRect(child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        pathlib.basename(_allImages[_currentIndex].path),
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        softWrap: false,
                                      ),
                                      if (_allImages.length > 1)
                                        Text(
                                          '${_currentIndex + 1} / ${_allImages.length}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.white70,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                          softWrap: false,
                                        ),
                                    ],
                                  ),
                                ),
                              ));
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(PhosphorIconsLight.shareFat, size: 20),
                          tooltip: 'Share',
                          color: Colors.white,
                          onPressed: _shareImage,
                        ),
                        IconButton(
                          icon: const Icon(PhosphorIconsLight.info, size: 20),
                          tooltip: 'Info',
                          color: Colors.white,
                          onPressed: () => _showImageInfo(context, _allImages[_currentIndex]),
                        ),
                        PopupMenuButton<String>(
                          iconColor: Colors.white,
                          onSelected: (value) {
                            switch (value) {
                              case 'rotate_right':
                                _rotateImage();
                                break;
                              case 'rotate_left':
                                _rotateImageLeft();
                                break;
                              case 'toggle_thumbs':
                                _toggleThumbnailStrip();
                                break;
                              case 'edit':
                                _toggleEditMode();
                                break;
                              case 'open_with':
                                _openWithExternalApp();
                                break;
                              case 'copy_path':
                                _copyPathToClipboard();
                                break;
                              case 'fullscreen':
                                _toggleFullscreen();
                                break;
                              case 'delete':
                                _deleteImage(context);
                                break;
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'rotate_right',
                              child: Text('Rotate right 90°', style: TextStyle(color: Colors.white)),
                            ),
                            PopupMenuItem(
                              value: 'rotate_left',
                              child: Text('Rotate left 90°', style: TextStyle(color: Colors.white)),
                            ),
                            PopupMenuItem(
                              value: 'toggle_thumbs',
                              child: Text('Toggle thumbnails', style: TextStyle(color: Colors.white)),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit (brightness/contrast)', style: TextStyle(color: Colors.white)),
                            ),
                            PopupMenuItem(
                              value: 'open_with',
                              child: Text('Open with...', style: TextStyle(color: Colors.white)),
                            ),
                            PopupMenuItem(
                              value: 'copy_path',
                              child: Text('Copy file path', style: TextStyle(color: Colors.white)),
                            ),
                            PopupMenuItem(
                              value: 'fullscreen',
                              child: Text('Toggle fullscreen', style: TextStyle(color: Colors.white)),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Move to trash', style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              // Main image viewer area
              Expanded(
                child: Listener(
            onPointerDown: (PointerDownEvent event) {
              // Mouse button 4 is usually the back button (button value is 8)
              if (event.buttons == 8 && _currentIndex > 0) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
              // Mouse button 5 is usually the forward button (button value is 16)
              else if (event.buttons == 16 &&
                  _currentIndex < _allImages.length - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
            child: SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  // Main image viewer
                  Expanded(
                    child: GestureDetector(
                      onTap: _toggleControls,
                      child: PageView.builder(
                      controller: _pageController,
                      itemCount: _allImages.length,
                      onPageChanged: (index) {
                        setState(() {
                          _currentIndex = index;
                          // Reset transformation when changing pages
                          _transformationController.value = Matrix4.identity();
                          _rotation = 0.0;
                        });
                        // Tiền tải ảnh kế tiếp và trước đó khi người dùng chuyển ảnh
                        _prefetchNeighboringImages();
                      },
                      itemBuilder: (context, index) {
                        final file = _allImages[index];
                        return Center(
                          child: GestureDetector(
                            onDoubleTapDown: _handleDoubleTap,
                            child: InteractiveViewer(
                              transformationController: _transformationController,
                              minScale: _minScale,
                              maxScale: _maxScale,
                              // Use default constrained: true to honor viewport constraints
                              child: Center(
                                key: ValueKey(file.path),
                                child: Transform.rotate(
                                  angle: _rotation * pi / 180,
                                  child: _buildImageWidget(file, index),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                // Thumbnail strip at the bottom
                if (_controlsVisible &&
                    _showThumbnailStrip &&
                    _allImages.length > 1)
                  Container(
                    height: 70,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      border: const Border(
                        top: BorderSide(
                          color: Colors.white24,
                          width: 1,
                        ),
                      ),
                    ),
                    child: ThumbnailStrip(
                      images: _allImages,
                      currentIndex: _currentIndex,
                      onThumbnailTap: (index) {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ),
                // Bottom toolbar (don't show if thumbnail strip is visible)
                if (_controlsVisible && !_showThumbnailStrip)
                  Container(
                    height: _isMobile() ? 72 : 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.85),
                          Colors.black.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                      border: const Border(
                        top: BorderSide(
                          color: Colors.white24,
                          width: 1,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          if (_allImages.length > 1)
                            IconButton(
                              icon: const Icon(PhosphorIconsLight.arrowLeft, size: 22),
                              tooltip: 'Previous',
                              color: Colors.white,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                              onPressed: _currentIndex > 0
                                  ? () {
                                      _pageController.previousPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  : null,
                            ),
                          IconButton(
                            icon: const Icon(PhosphorIconsLight.minus, size: 22),
                            tooltip: 'Zoom out',
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            onPressed: _zoomOut,
                          ),
                          IconButton(
                            icon: const Icon(PhosphorIconsLight.arrowsClockwise, size: 22),
                            tooltip: 'Reset view',
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            onPressed: _zoomReset,
                          ),
                          IconButton(
                            icon: const Icon(PhosphorIconsLight.plus, size: 22),
                            tooltip: 'Zoom in',
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            onPressed: _zoomIn,
                          ),
                          IconButton(
                            icon: const Icon(PhosphorIconsLight.info, size: 22),
                            tooltip: 'Info',
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            onPressed: () => _showImageInfo(context, _allImages[_currentIndex]),
                          ),
                          IconButton(
                            icon: const Icon(PhosphorIconsLight.shareFat, size: 22),
                            tooltip: 'Share',
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            onPressed: _shareImage,
                          ),
                          IconButton(
                            icon: const Icon(PhosphorIconsLight.trash, size: 22),
                            tooltip: 'Delete',
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            onPressed: () => _deleteImage(context),
                          ),
                          IconButton(
                            icon: Icon(
                              _isFullscreen
                                  ? PhosphorIconsLight.arrowsIn
                                  : PhosphorIconsLight.arrowsOut,
                              size: 22,
                            ),
                            tooltip: _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            onPressed: _toggleFullscreen,
                          ),
                          IconButton(
                            icon: Icon(
                              _slideshowPlaying
                                  ? PhosphorIconsLight.pause
                                  : PhosphorIconsLight.play,
                              size: 22,
                            ),
                            tooltip: _slideshowPlaying ? 'Pause slideshow' : 'Play slideshow',
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            constraints: const BoxConstraints(),
                            onPressed: _toggleSlideshow,
                          ),
                          if (_allImages.length > 1)
                            IconButton(
                              icon: const Icon(PhosphorIconsLight.arrowRight, size: 22),
                              tooltip: 'Next',
                              color: Colors.white,
                              padding: const EdgeInsets.all(8),
                              constraints: const BoxConstraints(),
                              onPressed: _currentIndex < _allImages.length - 1
                                  ? () {
                                      _pageController.nextPage(
                                        duration: const Duration(milliseconds: 300),
                                        curve: Curves.easeInOut,
                                      );
                                    }
                                  : null,
                            ),
                        ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            ),
            ),
            ),
          ],
        ),
      ),
      );
    } else {
      // Edit mode UI with sliders for adjustments
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black.withAlpha(179),
          title: const Text('Edit Image'),
          elevation: 0,
          actions: [
            TextButton(
              onPressed: _toggleEditMode,
              child: const Text('DONE', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(
                    _calculateColorMatrix(_brightness, _contrast),
                  ),
                  child: FutureBuilder<Uint8List?>(
                    future: _loadAndCacheImage(_allImages[_currentIndex]),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        // Show loading indicator
                        return const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              color: Colors.white70,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Loading image for editing...',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        );
                      } else if (snapshot.hasError) {
                        // Show error
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              PhosphorIconsLight.imageBroken,
                              size: 80,
                              color: Colors.white.withAlpha(179),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Failed to load image',
                              style:
                                  TextStyle(color: Colors.white.withAlpha(179)),
                            ),
                          ],
                        );
                      } else if (snapshot.hasData) {
                        // Show image with effects
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        );
                      } else {
                        // No data
                        return const Center(
                          child: Text(
                            'No image data',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
            ),
            Container(
              color: Colors.black.withAlpha(179),
              padding:
                  const EdgeInsets.symmetric(vertical: 16.0, horizontal: 24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brightness slider
                  Row(
                    children: [
                      const Icon(PhosphorIconsLight.sun, color: Colors.white, size: 20),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Slider(
                          value: _brightness,
                          min: -1.0,
                          max: 1.0,
                          divisions: 20,
                          label: 'Brightness: ${(_brightness * 100).round()}%',
                          onChanged: (value) {
                            setState(() {
                              _brightness = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  // Contrast slider
                  Row(
                    children: [
                      const Icon(PhosphorIconsLight.palette,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Slider(
                          value: _contrast,
                          min: -1.0,
                          max: 1.0,
                          divisions: 20,
                          label: 'Contrast: ${(_contrast * 100).round()}%',
                          onChanged: (value) {
                            setState(() {
                              _contrast = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _brightness = 0.0;
                            _contrast = 0.0;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: const Size(100, 36),
                        ),
                        icon: const Icon(PhosphorIconsLight.arrowsClockwise, size: 18),
                        label: const Text('Reset'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          // TODO: Implement save functionality
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Save feature will be implemented soon'),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade800,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: const Size(100, 36),
                        ),
                        icon: const Icon(PhosphorIconsLight.floppyDisk, size: 18),
                        label: const Text('Save Copy'),
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
  }

  // Helper method to calculate color matrix for brightness and contrast adjustments
  List<double> _calculateColorMatrix(double brightness, double contrast) {
    final double b = brightness;
    final double c = contrast + 1.0;

    // This matrix applies both brightness and contrast adjustments
    return [
      c,
      0,
      0,
      0,
      b * 255,
      0,
      c,
      0,
      0,
      b * 255,
      0,
      0,
      c,
      0,
      b * 255,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}



