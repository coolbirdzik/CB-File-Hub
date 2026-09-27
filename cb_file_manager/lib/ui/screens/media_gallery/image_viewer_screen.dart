import 'dart:io';
import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:path/path.dart' as pathlib;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/ui/frame_timing_optimizer.dart';
import '../../components/video/thumbnail_strip.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:share_plus/share_plus.dart'; // Add import for Share Plus
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import '../../utils/route.dart';
import 'package:open_filex/open_filex.dart';
import 'package:cb_file_manager/helpers/files/external_app_helper.dart';
import 'package:cb_file_manager/helpers/files/windows_shell_context_menu.dart';
import 'image_editor/image_editor_screen.dart';
import 'widgets/image_viewer_chrome.dart';

class ImageViewerScreen extends StatefulWidget {
  final File file;
  final List<File>? imageFiles; // Optional list of all images in the folder
  final int initialIndex; // When provided with imageFiles, start at this index
  final Uint8List? imageBytes; // Optional preloaded bytes for immediate display

  const ImageViewerScreen({
    super.key,
    required this.file,
    this.imageFiles,
    this.initialIndex = 0,
    this.imageBytes,
  });

  @override
  ImageViewerScreenState createState() => ImageViewerScreenState();
}

class ImageViewerScreenState extends State<ImageViewerScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late TransformationController _transformationController;
  late AnimationController _animationController;
  late AnimationController _dismissController;
  late AnimationController _slideshowController;
  Animation<Matrix4>? _animation;
  Animation<double>? _dismissAnimation;

  /// Vertical drag distance of the swipe-to-close gesture.
  final ValueNotifier<double> _dismissOffset = ValueNotifier<double>(0);

  late List<File> _allImages;
  int _currentIndex = 0;
  bool _isFullscreen = false;
  bool _controlsVisible = true;
  bool _showThumbnailStrip =
      true; // Biến để kiểm soát việc hiển thị thanh thumbnail
  bool _showInfo = false;
  // The info panel is built on first open, then kept so it can animate out.
  bool _infoPanelBuilt = false;
  // False until the first frame, so the controls animate in on open.
  bool _entered = false;
  bool _isZoomed = false;
  // Rotation in degrees. Kept cumulative (not wrapped to 0..360) so that the
  // rotation animation always turns the short way.
  double _rotation = 0.0;
  bool _isEditMode = false;
  bool _slideshowPlaying = false;
  final Duration _slideshowInterval = const Duration(seconds: 3);

  final double _minScale = 0.5;
  final double _maxScale = 5.0;

  static const double _dismissDistance = 140;

  // Check if platform is mobile
  bool _isMobile() {
    return Platform.isAndroid || Platform.isIOS;
  }

  // FocusNode for the KeyboardListener — must be a persistent field so it is
  // not recreated (and requestFocus called) on every setState / rebuild.
  late FocusNode _keyboardFocusNode;

  @override
  void initState() {
    super.initState();

    // Image is precached before navigation, no need to evict
    _initImageList();
    _keyboardFocusNode = FocusNode();
    _transformationController = TransformationController()
      ..addListener(_onTransformChanged);
    _animationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 260),
        )..addListener(() {
          if (_animation != null) {
            _transformationController.value = _animation!.value;
          }
        });
    _dismissController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 320),
        )..addListener(() {
          final animation = _dismissAnimation;
          if (animation != null) _dismissOffset.value = animation.value;
        });
    _slideshowController = AnimationController(
      vsync: this,
      duration: _slideshowInterval,
    )..addStatusListener(_onSlideshowStatus);

    // Request keyboard focus once after the first frame so keyboard shortcuts
    // work, and let the controls animate in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardFocusNode.requestFocus();
      setState(() => _entered = true);
    });

    // Force a repaint on mobile to avoid the initial black overlay seen
    // on some Android devices.  Not needed (and wasteful) on desktop.
    if (_isMobile()) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) setState(() {});
      });
    }

    // Apply frame timing optimization for better performance
    FrameTimingOptimizer().optimizeImageRendering();

    // Configure system UI
    if (_isMobile()) {
      // On mobile, show full UI (both status bar and nav bar)
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    } else {
      // On desktop, keep bottom nav visible
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.bottom],
      );
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
        images.sort(
          (a, b) => pathlib
              .basename(a.path)
              .toLowerCase()
              .compareTo(pathlib.basename(b.path).toLowerCase()),
        );

        // Find current image index based on absolute path comparison
        final currentPath = widget.file.path;
        final index = images.indexWhere(
          (file) => file.path == currentPath, // Exact path matching
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
                  debugPrint(
                    '🔄 Reordering list - moving screenshot from index $index to 0',
                  );
                  final screenshot = images[index];
                  images.removeAt(index);
                  images.insert(0, screenshot);
                  debugPrint('   ✅ Screenshot now at index 0');
                }

                _allImages = images;
                // Keep _currentIndex = 0 to match PageController
                debugPrint('📋 Updated image list: ${images.length} images');
                debugPrint('   Current page: $_currentIndex');

                // NOTE: Do NOT prefetch bytes here.
                // The editor loads its own copy of the image when opened.
                // Eager loading competes with the main image decode → jank.
              } else {
                // If we somehow can't find the image in the directory
                debugPrint(
                  'Warning: Could not find current image in directory. Path: $currentPath',
                );
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
    _slideshowController.dispose();
    _dismissController.dispose();
    _dismissOffset.dispose();
    _pageController.dispose();
    _transformationController.dispose();
    _animationController.dispose();
    _keyboardFocusNode.dispose();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transformationController.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _isZoomed && mounted) {
      setState(() => _isZoomed = zoomed);
    }
  }

  void _animateTransformTo(Matrix4 target) {
    _animation =
        Matrix4Tween(
          begin: _transformationController.value,
          end: target,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    _animationController.forward(from: 0);
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_animationController.isAnimating) return;

    final current = _transformationController.value;
    final currentScale = current.getMaxScaleOnAxis();
    final translation = current.getTranslation();
    final isTransformed =
        (currentScale - 1).abs() > 0.001 || translation.length2 > 0.01;
    if (isTransformed) {
      // Reset to identity if already zoomed in
      _animateTransformTo(Matrix4.identity());
      return;
    }

    // Zoom in to 2.5x around the tap point.
    final position = details.localPosition;
    const double scale = 2.5;
    _animateTransformTo(
      Matrix4.identity()
        ..translateByVector3(Vector3(position.dx, position.dy, 0))
        ..scaleByVector3(Vector3(scale, scale, 1))
        ..translateByVector3(Vector3(-position.dx, -position.dy, 0)),
    );
  }

  void _resetTransformation() {
    _animateTransformTo(Matrix4.identity());
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });

    if (_isMobile()) {
      if (_controlsVisible) {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
        );
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
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
        );
      }
    });
  }

  void _rotateImage() {
    setState(() => _rotation += 90.0);
    _resetTransformation();
  }

  void _rotateImageLeft() {
    setState(() => _rotation -= 90.0);
    _resetTransformation();
  }

  void _toggleEditMode() {
    if (!_isEditMode && _slideshowPlaying) _toggleSlideshow();
    setState(() => _isEditMode = !_isEditMode);
    // The editor held keyboard focus; give it back to the viewer.
    if (!_isEditMode) _keyboardFocusNode.requestFocus();
  }

  /// Shows a copy saved by the editor next to the picture it came from.
  void _onEditedCopySaved(File saved) {
    if (!saved.existsSync() || !FileTypeUtils.isImageFile(saved.path)) return;
    final source = _allImages[_currentIndex];
    if (pathlib.dirname(saved.path) != pathlib.dirname(source.path)) return;
    if (_allImages.any((file) => file.path == saved.path)) return;
    setState(() => _allImages.insert(_currentIndex + 1, saved));
  }

  void _toggleThumbnailStrip() {
    setState(() {
      _showThumbnailStrip = !_showThumbnailStrip;
    });
  }

  void _toggleInfo() {
    setState(() {
      _showInfo = !_showInfo;
      _infoPanelBuilt = true;
    });
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _allImages.length || index == _currentIndex) {
      return;
    }
    if (!_pageController.hasClients) return;
    // Sliding across many pages would decode every image on the way.
    if ((index - _currentIndex).abs() > 2) {
      _pageController.jumpToPage(index);
    } else {
      _pageController.animateToPage(
        index,
        duration: ViewerMotion.slow,
        curve: ViewerMotion.curve,
      );
    }
  }

  void _previousImage() => _goToPage(_currentIndex - 1);

  void _nextImage() => _goToPage(_currentIndex + 1);

  void _onPageChanged(int index) {
    _animationController.stop();
    // Reset zoom when changing pages.
    _transformationController.value = Matrix4.identity();
    setState(() {
      _currentIndex = index;
      _rotation = 0.0;
    });
  }

  bool get _canDragToDismiss => !_isZoomed && !_isEditMode && !_showInfo;

  void _onDismissDragUpdate(DragUpdateDetails details) {
    _dismissController.stop();
    _dismissOffset.value += details.delta.dy;
  }

  void _onDismissDragEnd(DragEndDetails details) {
    final offset = _dismissOffset.value;
    final velocity = details.primaryVelocity ?? 0;
    final flung = velocity.abs() > 900 && velocity.sign == offset.sign;
    if (offset.abs() > _dismissDistance || flung) {
      RouteUtils.safePopDialog(context);
      return;
    }
    _dismissAnimation = Tween<double>(begin: offset, end: 0).animate(
      CurvedAnimation(parent: _dismissController, curve: Curves.easeOutBack),
    );
    _dismissController.forward(from: 0);
  }

  void _handleKeyEvent(KeyEvent event) {
    // The editor handles its own keys.
    if (_isEditMode) return;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;

    // Escape closes the innermost layer first.
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyRepeatEvent) return;
      if (_showInfo) {
        _toggleInfo();
      } else {
        RouteUtils.safePopDialog(context);
      }
      return;
    }

    // Holding a key repeats paging and zooming, nothing else.
    final repeatable =
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract;
    if (event is KeyRepeatEvent && !repeatable) return;

    final controlPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (controlPressed) {
      if (key == LogicalKeyboardKey.keyP) _printImage();
      return;
    }

    if (key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoomIn();
    } else if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoomOut();
    } else if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.numpad0) {
      _zoomReset();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _previousImage();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _nextImage();
    } else if (key == LogicalKeyboardKey.home) {
      _goToPage(0);
    } else if (key == LogicalKeyboardKey.end) {
      _goToPage(_allImages.length - 1);
    } else if (key == LogicalKeyboardKey.keyR) {
      HardwareKeyboard.instance.isShiftPressed
          ? _rotateImageLeft()
          : _rotateImage();
    } else if (key == LogicalKeyboardKey.keyI) {
      _toggleInfo();
    } else if (key == LogicalKeyboardKey.keyF ||
        key == LogicalKeyboardKey.f11) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.space) {
      if (_allImages.length > 1) _toggleSlideshow();
    } else if (key == LogicalKeyboardKey.delete) {
      _deleteImage(context);
    }
  }

  Future<void> _deleteImage(BuildContext context) async {
    final file = _allImages[_currentIndex];
    final l10n = AppLocalizations.of(context)!;

    final bool? confirm = await RouteUtils.showAcrylicDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.moveToTrashTitle),
        content: Text(
          l10n.moveToTrashConfirmMessage(pathlib.basename(file.path)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel.toUpperCase()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.moveToTrash.toUpperCase(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
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
            AppToast.success(context, l10n.imageMovedToTrash);

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
            AppToast.error(context, l10n.failedToMoveImageToTrash);
          }
        }
      } catch (e) {
        if (context.mounted) {
          AppToast.error(
            context,
            l10n.failedToMoveImageToTrashWithError(e.toString()),
          );
        }
      }
    }
  }

  void _copyPathToClipboard() async {
    final file = _allImages[_currentIndex];
    await Clipboard.setData(ClipboardData(text: file.path));
    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      AppToast.info(context, l10n.copiedPathToClipboard);
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
      final l10n = AppLocalizations.of(context)!;
      AppToast.error(context, l10n.unableToOpenWithExternalApp);
    }
  }

  void _toggleSlideshow() {
    setState(() => _slideshowPlaying = !_slideshowPlaying);
    if (_slideshowPlaying) {
      _slideshowController.forward(from: 0);
    } else {
      _slideshowController.stop();
      _slideshowController.value = 0;
    }
  }

  void _onSlideshowStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_slideshowPlaying) return;
    if (!mounted || !_pageController.hasClients) return;
    if (_allImages.length > 1) {
      if (_currentIndex < _allImages.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOutCubic,
        );
      } else {
        _pageController.jumpToPage(0);
      }
    }
    _slideshowController.forward(from: 0);
  }

  void _zoomReset() {
    _resetTransformation();
  }

  void _zoomIn() {
    _applyZoomRelative(1.15);
  }

  void _zoomOut() {
    _applyZoomRelative(1 / 1.15);
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

    _animateTransformTo(zoomAroundCenter.multiplied(current));
  }

  Future<void> _shareImage() async {
    final file = _allImages[_currentIndex];
    try {
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (error) {
      if (mounted) AppToast.error(context, 'Unable to share image: $error');
    }
  }

  Future<void> _printImage() async {
    final file = _allImages[_currentIndex];
    var started = false;
    try {
      if (Platform.isWindows) {
        started = await WindowsShellContextMenu.invokeVerb(
          paths: <String>[file.path],
          verb: 'print',
        );
      } else if (Platform.isLinux || Platform.isMacOS) {
        final result = await Process.run('lp', <String>[file.path]);
        started = result.exitCode == 0;
      }
    } catch (_) {
      started = false;
    }
    if (!mounted) return;
    if (started) {
      AppToast.success(context, 'Image sent to the printer');
    } else {
      AppToast.error(context, 'Unable to start printing for this image');
    }
  }

  // Fades the picture in once its first frame is decoded.
  Widget _fadeInFrame(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedSwitcher(
      duration: ViewerMotion.medium,
      switchInCurve: ViewerMotion.curve,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: frame == null
          ? const _ImageLoadingIndicator(key: ValueKey<String>('loading'))
          : KeyedSubtree(key: const ValueKey<String>('image'), child: child),
    );
  }

  // Build image widget - use Image.memory for preloaded bytes, Image.file otherwise
  Widget _buildImageWidget(File file) {
    // Use preloaded bytes if this file matches the widget.file path
    final useBytes = file.path == widget.file.path && widget.imageBytes != null;

    if (useBytes) {
      return Image.memory(
        widget.imageBytes!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: _fadeInFrame,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('   ❌ Image.memory error: $error');
          return _buildErrorWidget(error);
        },
      );
    }

    return Image.file(
      file,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      frameBuilder: _fadeInFrame,
      errorBuilder: (context, error, stackTrace) {
        return _buildErrorWidget(error);
      },
    );
  }

  Widget _buildErrorWidget(Object error) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(
              PhosphorIconsLight.imageBroken,
              size: 44,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to display image',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error.toString(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_allImages.isEmpty) {
      return const Scaffold(body: Center(child: Text('No images to display')));
    }

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: ValueListenableBuilder<double>(
          valueListenable: _dismissOffset,
          builder: (context, offset, child) {
            final progress = (offset.abs() / 400).clamp(0.0, 1.0);
            return ColoredBox(
              color: Colors.black.withValues(alpha: 1 - progress * 0.7),
              child: child,
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildGallery(),
              Positioned.fill(child: _buildChrome(context)),
              if (_infoPanelBuilt) _buildInfoPanel(context),
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: ViewerMotion.medium,
                  switchInCurve: ViewerMotion.curve,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.98,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _isEditMode
                      ? KeyedSubtree(
                          key: const ValueKey<String>('editor'),
                          child: ImageEditorScreen(
                            file: _allImages[_currentIndex],
                            initialQuarterTurns: (_rotation / 90).round(),
                            onClose: _toggleEditMode,
                            onSaved: _onEditedCopySaved,
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey<String>('no-editor'),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGallery() {
    return Listener(
      onPointerDown: (PointerDownEvent event) {
        // Mouse button 4 is usually the back button (button value is 8)
        if (event.buttons == kBackMouseButton) {
          _previousImage();
        }
        // Mouse button 5 is usually the forward button (button value is 16)
        else if (event.buttons == kForwardMouseButton) {
          _nextImage();
        }
      },
      // Swipe up or down to close. Touch only: a trackpad scroll or mouse
      // drag over the picture must not close the viewer.
      child: GestureDetector(
        supportedDevices: const <PointerDeviceKind>{
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
        },
        onVerticalDragUpdate: _canDragToDismiss ? _onDismissDragUpdate : null,
        onVerticalDragEnd: _canDragToDismiss ? _onDismissDragEnd : null,
        child: GestureDetector(
          onTap: _toggleControls,
          child: ValueListenableBuilder<double>(
            valueListenable: _dismissOffset,
            builder: (context, offset, child) {
              if (offset == 0) return child!;
              final progress = (offset.abs() / 400).clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(0, offset),
                child: Transform.scale(
                  scale: 1 - progress * 0.25,
                  child: child,
                ),
              );
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: _allImages.length,
              // While zoomed, one-finger drags pan the picture instead.
              physics: _isZoomed
                  ? const NeverScrollableScrollPhysics()
                  : const BouncingScrollPhysics(),
              onPageChanged: _onPageChanged,
              itemBuilder: _buildPage,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    final file = _allImages[index];
    final isCurrent = index == _currentIndex;
    final rotation = isCurrent ? _rotation : 0.0;

    return AnimatedBuilder(
      animation: _pageController,
      // Pages shrink and fade slightly as they slide away.
      builder: (context, child) {
        var delta = (_currentIndex - index).toDouble();
        if (_pageController.hasClients &&
            _pageController.position.haveDimensions) {
          delta = (_pageController.page ?? _currentIndex.toDouble()) - index;
        }
        final t = delta.abs().clamp(0.0, 1.0);
        if (t == 0) return child!;
        return Opacity(
          opacity: 1 - t * 0.6,
          child: Transform.scale(scale: 1 - t * 0.12, child: child),
        );
      },
      child: GestureDetector(
        onDoubleTapDown: _handleDoubleTap,
        child: InteractiveViewer(
          // Only the page on screen follows the zoom controls.
          transformationController: isCurrent
              ? _transformationController
              : null,
          minScale: _minScale,
          maxScale: _maxScale,
          scaleFactor: 500,
          interactionEndFrictionCoefficient: 0.00008,
          // Use default constrained: true to honor viewport constraints
          child: TweenAnimationBuilder<double>(
            key: ValueKey<String>(file.path),
            tween: Tween<double>(end: rotation * pi / 180),
            duration: ViewerMotion.slow,
            curve: ViewerMotion.curve,
            builder: (context, angle, child) =>
                _RotateToFit(angle: angle, child: child),
            child: _buildImageWidget(file),
          ),
        ),
      ),
    );
  }

  Widget _buildChrome(BuildContext context) {
    final media = MediaQuery.of(context);
    final visible = _controlsVisible && _entered;
    final showSideArrows = _allImages.length > 1 && media.size.width >= 600;

    return ValueListenableBuilder<double>(
      valueListenable: _dismissOffset,
      // The controls get out of the way while the picture is dragged.
      builder: (context, offset, child) {
        final opacity = (1 - offset.abs() / 120).clamp(0.0, 1.0);
        return Opacity(opacity: opacity, child: child);
      },
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ViewerChromeReveal(
              visible: visible,
              hiddenOffset: const Offset(0, -1),
              child: _buildTopBar(context),
            ),
          ),
          Positioned(
            top: media.padding.top,
            left: 0,
            right: 0,
            child: _buildSlideshowProgress(),
          ),
          if (showSideArrows) ...[
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: ViewerChromeReveal(
                  visible: visible && _currentIndex > 0,
                  hiddenOffset: const Offset(-0.5, 0),
                  child: ViewerIconButton(
                    icon: PhosphorIconsLight.caretLeft,
                    tooltip: 'Previous',
                    filled: true,
                    size: 48,
                    iconSize: 22,
                    onPressed: _currentIndex > 0 ? _previousImage : null,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              child: Center(
                child: ViewerChromeReveal(
                  visible: visible && _currentIndex < _allImages.length - 1,
                  hiddenOffset: const Offset(0.5, 0),
                  child: ViewerIconButton(
                    icon: PhosphorIconsLight.caretRight,
                    tooltip: 'Next',
                    filled: true,
                    size: 48,
                    iconSize: 22,
                    onPressed: _currentIndex < _allImages.length - 1
                        ? _nextImage
                        : null,
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ViewerChromeReveal(
              visible: visible,
              hiddenOffset: const Offset(0, 1),
              delay: const Duration(milliseconds: 40),
              child: _buildBottomBar(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final file = _allImages[_currentIndex];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.3),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 28),
          child: Row(
            children: [
              ViewerIconButton(
                icon: PhosphorIconsLight.arrowLeft,
                tooltip: 'Back',
                onPressed: () => RouteUtils.safePopDialog(context),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: ViewerMotion.medium,
                  switchInCurve: ViewerMotion.curve,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey<String>(file.path),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pathlib.basename(file.path),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                      ),
                      if (_allImages.length > 1) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${_currentIndex + 1} / ${_allImages.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.6),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ViewerIconButton(
                icon: PhosphorIconsLight.info,
                tooltip: 'Info (I)',
                active: _showInfo,
                onPressed: _toggleInfo,
              ),
              const SizedBox(width: 4),
              Builder(
                builder: (buttonContext) => ViewerIconButton(
                  icon: PhosphorIconsLight.dotsThreeVertical,
                  tooltip: 'More',
                  onPressed: () => _showMoreMenu(buttonContext),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlideshowProgress() {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _slideshowPlaying ? 1 : 0,
        duration: ViewerMotion.medium,
        child: AnimatedBuilder(
          animation: _slideshowController,
          builder: (context, _) => Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: _slideshowController.value,
              child: Container(
                height: 2.5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final showStrip = _showThumbnailStrip && _allImages.length > 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.3),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 36, 12, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSize(
                duration: ViewerMotion.medium,
                curve: ViewerMotion.curve,
                alignment: Alignment.bottomCenter,
                child: showStrip
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ThumbnailStrip(
                          images: _allImages,
                          currentIndex: _currentIndex,
                          thumbnailSize: 52,
                          spacing: 5,
                          onThumbnailTap: _goToPage,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              _buildToolbar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return Center(
      child: ViewerGlass(
        // Matches the square-ish rounded buttons it holds better than the
        // previous pill radius.
        borderRadius: const BorderRadius.all(Radius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ViewerIconButton(
                icon: PhosphorIconsLight.magnifyingGlassMinus,
                tooltip: 'Zoom out',
                onPressed: _zoomOut,
              ),
              _buildZoomLabel(),
              ViewerIconButton(
                icon: PhosphorIconsLight.magnifyingGlassPlus,
                tooltip: 'Zoom in',
                onPressed: _zoomIn,
              ),
              const ViewerToolbarDivider(),
              ViewerIconButton(
                icon: PhosphorIconsLight.arrowCounterClockwise,
                tooltip: 'Rotate left',
                onPressed: _rotateImageLeft,
              ),
              ViewerIconButton(
                icon: PhosphorIconsLight.arrowClockwise,
                tooltip: 'Rotate right',
                onPressed: _rotateImage,
              ),
              const ViewerToolbarDivider(),
              ViewerIconButton(
                icon: PhosphorIconsLight.slidersHorizontal,
                tooltip: 'Edit image',
                onPressed: _toggleEditMode,
              ),
              ViewerIconButton(
                icon: _slideshowPlaying
                    ? PhosphorIconsLight.pause
                    : PhosphorIconsLight.play,
                tooltip: _slideshowPlaying
                    ? 'Pause slideshow'
                    : 'Play slideshow',
                active: _slideshowPlaying,
                onPressed: _allImages.length > 1 ? _toggleSlideshow : null,
              ),
              ViewerIconButton(
                icon: _isFullscreen
                    ? PhosphorIconsLight.arrowsIn
                    : PhosphorIconsLight.arrowsOut,
                tooltip: _isFullscreen ? 'Exit fullscreen' : 'Fullscreen',
                onPressed: _toggleFullscreen,
              ),
              const ViewerToolbarDivider(),
              ViewerIconButton(
                icon: PhosphorIconsLight.shareFat,
                tooltip: 'Share',
                onPressed: _shareImage,
              ),
              ViewerIconButton(
                icon: PhosphorIconsLight.printer,
                tooltip: 'Print (Ctrl+P)',
                onPressed: _printImage,
              ),
              ViewerIconButton(
                icon: PhosphorIconsLight.trash,
                tooltip: 'Delete',
                color: const Color(0xFFFF8A80),
                onPressed: () => _deleteImage(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildZoomLabel() {
    return ValueListenableBuilder<Matrix4>(
      valueListenable: _transformationController,
      builder: (context, matrix, _) {
        final percent = (matrix.getMaxScaleOnAxis() * 100).round();
        return Tooltip(
          message: 'Reset zoom (0)',
          waitDuration: const Duration(milliseconds: 450),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _zoomReset,
              child: SizedBox(
                width: 52,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: percent == 100
                        ? Colors.white.withValues(alpha: 0.7)
                        : Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoPanel(BuildContext context) {
    final media = MediaQuery.of(context);
    final isWide = media.size.width >= 720;
    final panel = ImageInfoPanel(
      file: _allImages[_currentIndex],
      active: _showInfo,
      onClose: _toggleInfo,
      onCopyPath: _copyPathToClipboard,
    );

    if (isWide) {
      return Positioned(
        top: media.padding.top + 72,
        right: 16,
        bottom: media.padding.bottom + 150,
        width: 340,
        child: Align(
          alignment: Alignment.topRight,
          child: ViewerChromeReveal(
            visible: _showInfo,
            hiddenOffset: const Offset(0.12, 0),
            child: panel,
          ),
        ),
      );
    }
    return Positioned(
      left: 12,
      right: 12,
      bottom: media.padding.bottom + 12,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.6),
        child: ViewerChromeReveal(
          visible: _showInfo,
          hiddenOffset: const Offset(0, 0.25),
          child: panel,
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(BuildContext buttonContext) async {
    final l10n = AppLocalizations.of(context)!;
    final button = buttonContext.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(buttonContext).overlay?.context.findRenderObject()
            as RenderBox?;
    if (button == null || overlay == null) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          button.size.bottomLeft(const Offset(0, 6)),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(const Offset(0, 6)),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final value = await showMenu<String>(
      context: buttonContext,
      position: position,
      color: const Color(0xF21C1C20),
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      items: [
        _menuItem(
          'open_with',
          PhosphorIconsLight.arrowSquareOut,
          '${l10n.openWith}...',
        ),
        _menuItem('copy_path', PhosphorIconsLight.copy, 'Copy file path'),
        if (_allImages.length > 1)
          _menuItem(
            'toggle_thumbs',
            PhosphorIconsLight.squaresFour,
            _showThumbnailStrip ? 'Hide thumbnails' : 'Show thumbnails',
          ),
        const PopupMenuDivider(height: 8),
        _menuItem(
          'delete',
          PhosphorIconsLight.trash,
          l10n.moveToTrash,
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    switch (value) {
      case 'open_with':
        _openWithExternalApp();
      case 'copy_path':
        _copyPathToClipboard();
      case 'toggle_thumbs':
        _toggleThumbnailStrip();
      case 'delete':
        _deleteImage(context);
    }
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool destructive = false,
  }) {
    final color = destructive ? const Color(0xFFFF8A80) : Colors.white;
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.85)),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: color, fontSize: 13.5)),
        ],
      ),
    );
  }
}

class _ImageLoadingIndicator extends StatelessWidget {
  const _ImageLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: CircularProgressIndicator(
        strokeWidth: 2.2,
        color: Colors.white.withValues(alpha: 0.6),
      ),
    );
  }
}

/// Centres its child and rotates it by [angle], shrinking it just enough to
/// stay inside the available space at every point of the turn.
class _RotateToFit extends SingleChildRenderObjectWidget {
  final double angle;

  const _RotateToFit({required this.angle, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRotateToFit(angle);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRotateToFit renderObject,
  ) {
    renderObject.angle = angle;
  }
}

class _RenderRotateToFit extends RenderProxyBox {
  _RenderRotateToFit(this._angle);

  double _angle;

  set angle(double value) {
    if (value == _angle) return;
    _angle = value;
    markNeedsPaint();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    child?.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.biggest.isFinite
        ? constraints.biggest
        : constraints.constrain(child?.size ?? Size.zero);
  }

  Matrix4 get _transform {
    final childSize = child?.size ?? Size.zero;
    final w = childSize.width;
    final h = childSize.height;
    final cosA = cos(_angle).abs();
    final sinA = sin(_angle).abs();
    final boundsWidth = w * cosA + h * sinA;
    final boundsHeight = w * sinA + h * cosA;
    var scale = 1.0;
    if (boundsWidth > 0 && boundsHeight > 0) {
      scale = min(
        1.0,
        min(size.width / boundsWidth, size.height / boundsHeight),
      );
    }
    return Matrix4.identity()
      ..translateByVector3(Vector3(size.width / 2, size.height / 2, 0))
      ..rotateZ(_angle)
      ..scaleByVector3(Vector3(scale, scale, 1))
      ..translateByVector3(Vector3(-w / 2, -h / 2, 0));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(child, offset),
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}
