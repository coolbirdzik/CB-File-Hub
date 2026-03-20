import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../helpers/media/video_thumbnail_helper.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';

/// A widget that efficiently displays a video thumbnail with lazy loading
/// and background processing to avoid UI thread blocking during scrolling
class LazyVideoThumbnail extends StatefulWidget {
  /// Path to the video file for which the thumbnail should be generated
  final String videoPath;

  /// Width of the thumbnail
  final double width;

  /// Height of the thumbnail
  final double height;

  /// Builder function that returns a widget to show when thumbnail is loading or on error
  final Widget Function() fallbackBuilder;

  /// Whether to keep the thumbnail in memory when it's scrolled out of view
  final bool keepAlive;

  /// If true, only shows the placeholder and doesn't attempt to load thumbnails
  final bool placeholderOnly;

  /// Callback when thumbnail is successfully generated
  final Function(String path)? onThumbnailGenerated;

  /// Callback when thumbnail generation fails with an error
  final Function(dynamic error)? onError;

  const LazyVideoThumbnail({
    Key? key,
    required this.videoPath,
    this.width = 160,
    this.height = 120,
    required this.fallbackBuilder,
    this.keepAlive = true,
    this.placeholderOnly = false,
    this.onThumbnailGenerated,
    this.onError,
  }) : super(key: key);

  @override
  State<LazyVideoThumbnail> createState() => _LazyVideoThumbnailState();
}

class _LazyVideoThumbnailState extends State<LazyVideoThumbnail>
    with AutomaticKeepAliveClientMixin {
  // Notifiers to maintain widget state
  final _visibilityNotifier = ValueNotifier<bool>(false);
  final _thumbnailPathNotifier = ValueNotifier<String?>(null);
  final _progressNotifier = ValueNotifier<double>(0.0);
  final _isGeneratingNotifier = ValueNotifier<bool>(false);
  final _generationStatusNotifier =
      ValueNotifier<ThumbnailGenerationStatus?>(null);

  // State tracking
  bool _isLoading = false;
  bool _isThumbnailGenerated = false;
  bool _shouldRegenerateThumbnail = true;
  bool _hasSyncLoadLog = false;
  bool _hasFrameLoadLog = false;

  // Progress simulation timer
  Timer? _progressTimer;

  // Lightweight cache polling to recover missed repaints
  Timer? _cachePollTimer;

  // Track fast scrolling state
  bool _isScrollingFast = false;

  // Track thumbnail version to force rebuild on cache clear
  int _thumbnailVersion = 0;

  // Stream subscription to cache clear events
  StreamSubscription? _cacheChangedSubscription;
  // Subscription to per-file thumbnail ready notifications
  StreamSubscription<String>? _thumbReadySubscription;
  // Subscription for generation status updates
  StreamSubscription<ThumbnailGenerationStatus>? _generationStatusSubscription;

  // AutomaticKeepAliveClientMixin implementation
  // PERFORMANCE: Changed to false to reduce memory pressure during scrolling
  @override
  bool get wantKeepAlive => false; // Changed from widget.keepAlive

  @override
  void initState() {
    super.initState();
    // Use the helper's throttled log method
    VideoThumbnailHelper.logWithThrottle(
        '[Thumbnail] Initializing thumbnail', widget.videoPath);

    // Listen to scroll velocity changes
    ScrollVelocityNotifier.instance.addListener(_onScrollVelocityChanged);

    _scheduleInitialLoad();

    // Subscribe to cache changed events
    _cacheChangedSubscription = VideoThumbnailHelper.onCacheChanged.listen((_) {
      _handleCacheCleared();
    });

    // Listen for specific thumbnail ready events for this video path
    // Note: readyVideoPath is the normalized cache key, so we need to compare properly
    _thumbReadySubscription =
        VideoThumbnailHelper.onThumbnailReady.listen((readyVideoPath) async {
      if (!mounted) return;

      // Compare normalized paths since the stream sends the cache key (normalized)
      final normalizedWidgetPath =
          VideoThumbnailHelper.getNormalizedPath(widget.videoPath);
      if (readyVideoPath != normalizedWidgetPath &&
          readyVideoPath != widget.videoPath) {
        return;
      }

      // If we don't yet show a thumbnail, update from cache and repaint
      if (_thumbnailPathNotifier.value == null) {
        try {
          final cached =
              await VideoThumbnailHelper.getFromCache(widget.videoPath);
          if (!mounted) return;
          if (cached != null) {
            // IMPORTANT: Use setState to ensure widget rebuilds
            setState(() {
              _thumbnailPathNotifier.value = cached;
              _isThumbnailGenerated = true;
              _shouldRegenerateThumbnail = false;
            });
            _onThumbnailGenerated(cached);
            _cachePollTimer?.cancel();
          }
        } catch (_) {}
      }
    });

    // Listen for generation status updates
    _generationStatusSubscription =
        VideoThumbnailHelper.onGenerationStatus.listen((status) {
      if (!mounted) return;

      // Check if this status is for our video
      final normalizedWidgetPath =
          VideoThumbnailHelper.getNormalizedPath(widget.videoPath);
      if (status.videoPath != normalizedWidgetPath &&
          status.videoPath != widget.videoPath) {
        return;
      }

      _generationStatusNotifier.value = status;
    });
  }

  @override
  void dispose() {
    ScrollVelocityNotifier.instance.removeListener(_onScrollVelocityChanged);
    _visibilityNotifier.dispose();
    _thumbnailPathNotifier.dispose();
    _progressNotifier.dispose();
    _isGeneratingNotifier.dispose();
    _generationStatusNotifier.dispose();
    _progressTimer?.cancel();
    _cachePollTimer?.cancel();
    _cacheChangedSubscription?.cancel();
    _thumbReadySubscription?.cancel();
    _generationStatusSubscription?.cancel();
    super.dispose();
  }

  void _onScrollVelocityChanged() {
    final isFast = ScrollVelocityNotifier.instance.isScrollingFast;
    if (_isScrollingFast != isFast) {
      _isScrollingFast = isFast;
      if (isFast) {
        // Cancel pending operations when scrolling fast
        _progressTimer?.cancel();
        _cachePollTimer?.cancel();
      }
    }
  }

  @override
  void didUpdateWidget(LazyVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only set regeneration flag if the path actually changed
    if (widget.videoPath != oldWidget.videoPath) {
      _shouldRegenerateThumbnail = true;
      _hasSyncLoadLog = false;
      _hasFrameLoadLog = false;
      _scheduleInitialLoad();
    }
  }

  /// Handle the event when the thumbnail cache is cleared
  void _handleCacheCleared() {
    // Use the helper's throttled log method
    VideoThumbnailHelper.logWithThrottle(
        '[Thumbnail] Cache cleared notification received', widget.videoPath);

    if (!mounted) return;

    // Force evict image from Flutter cache to ensure reload from disk
    if (_thumbnailPathNotifier.value != null) {
      try {
        final file = File(_thumbnailPathNotifier.value!);
        if (file.existsSync()) {
          final provider = FileImage(file);
          provider.evict();
        }
      } catch (e) {
        // Ignore errors during eviction
      }
    }

    _thumbnailPathNotifier.value = null;
    _isThumbnailGenerated = false;
    _shouldRegenerateThumbnail = true;
    _thumbnailVersion++; // Increment version to force Image widget rebuild
    _isLoading =
        false; // BUGFIX: Reset loading state so _loadThumbnail doesn't early-return
    _hasSyncLoadLog = false; // Reset frame log flag when cache is cleared
    _hasFrameLoadLog = false; // Reset frame log flag when cache is cleared

    // Reload thumbnail after cache clear.
    // Use a slightly longer delay to allow clearCache() to fully complete
    // (including its finally block resetting _isProcessingQueue).
    // Also reset _visibilityNotifier since the VisibilityDetector was not
    // in the tree while the image was displayed, so the old value is stale.
    final wasVisible = _visibilityNotifier.value;
    _visibilityNotifier.value = false;

    // Use the helper's throttled log method
    VideoThumbnailHelper.logWithThrottle(
        '[Thumbnail] Reloading thumbnail after cache clear (wasVisible=$wasVisible)',
        widget.videoPath);

    // Use a longer delay to ensure clearCache's finally block has completed
    // and _isProcessingQueue is properly reset to false.
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      // Mark as visible again and start loading regardless of VisibilityDetector
      // since we know this widget was in the tree when cache was cleared
      _visibilityNotifier.value = true;

      // Request with high priority and force regeneration
      _loadThumbnail(forceRegenerate: true, isPriority: true);
      _startCachePolling();
    });
  }

  /// Schedule initial thumbnail load.
  /// Checks cache first; if not cached, requests generation immediately.
  /// Generation for ALL files in the directory is driven by
  /// proactiveGenerateAll (called from the bloc), so this widget does NOT
  /// wait for visibility — it either picks up a cached result or joins
  /// the existing queue via the onThumbnailReady stream.
  void _scheduleInitialLoad() {
    // Don't schedule if we've determined we don't need to regenerate
    if (!_shouldRegenerateThumbnail) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      VideoThumbnailHelper.getFromCache(widget.videoPath)
          .then((cachedThumbnailPath) {
        if (!mounted) return;

        // If we have a cached path, use it immediately
        if (cachedThumbnailPath != null) {
          setState(() {
            _thumbnailPathNotifier.value = cachedThumbnailPath;
            _isThumbnailGenerated = true;
            _shouldRegenerateThumbnail = false;
          });

          if (widget.onThumbnailGenerated != null) {
            widget.onThumbnailGenerated!(cachedThumbnailPath);
          }
          return;
        }

        // Not cached — check if proactiveGenerateAll already queued it.
        // If so, wait for the onThumbnailReady stream notification, but also
        // start cache polling as a safety net in case the stream event is
        // missed (e.g. cache-hit early-return in _generateThumbnailInternal).
        if (VideoThumbnailHelper.isPathQueued(widget.videoPath)) {
          _isGeneratingNotifier.value = true;
          _startCachePolling();
          return;
        }

        // Not cached AND not queued (e.g. widget used outside folder list,
        // or proactive queue already finished without this file).
        // Request as a fallback with non-priority so it doesn't disrupt
        // the sorted queue order.
        if (!widget.placeholderOnly) {
          _loadThumbnail(isPriority: false);
        }
      }).catchError((error) {
        VideoThumbnailHelper.logWithThrottle(
            '[Thumbnail] Error checking cache: $error', widget.videoPath);
      });
    });
  }

  /// Start loading the thumbnail
  void _loadThumbnail({bool forceRegenerate = false, bool isPriority = false}) {
    // Skip if already loading, if we're in placeholder-only mode,
    // if we already have a thumbnail generated and don't need to regenerate,
    // or if we've determined we don't need to regenerate
    if (_isLoading ||
        widget.placeholderOnly ||
        (_thumbnailPathNotifier.value != null && !forceRegenerate) ||
        (!_shouldRegenerateThumbnail && !forceRegenerate)) {
      return;
    }

    // Use the helper's throttled log method
    VideoThumbnailHelper.logWithThrottle(
        '[Thumbnail] Starting thumbnail load (force=$forceRegenerate, priority=$isPriority)',
        widget.videoPath);

    _isLoading = true;
    _progressNotifier.value = 0.0;
    _isGeneratingNotifier.value = true; // Show generating indicator

    // Start progress simulation for better UX
    _simulateProgressUpdates();

    final int? thumbnailSize = _resolveThumbnailSize();

    // If the path is already queued by proactiveGenerateAll (which respects
    // sort order), don't re-request with isPriority=true as that would
    // assign flat priority 100 and disrupt the top-to-bottom generation order.
    // Instead, just wait for the onThumbnailReady stream to deliver the result.
    final bool alreadyQueued =
        VideoThumbnailHelper.isPathQueued(widget.videoPath);
    if (alreadyQueued && !forceRegenerate) {
      // Already queued with correct priority — just wait for stream notification
      _isLoading = false;
      _isGeneratingNotifier.value = true; // Still show generating indicator
      return;
    }

    final bool usePriority =
        isPriority && !(thumbnailSize != null && thumbnailSize <= 96);

    // Use VideoThumbnailHelper directly instead of ThumbnailIsolateManager
    VideoThumbnailHelper.generateThumbnail(
      widget.videoPath,
      isPriority: usePriority,
      forceRegenerate: forceRegenerate,
      thumbnailSize: thumbnailSize,
    ).then((path) {
      if (!mounted) return;

      _progressTimer?.cancel();
      _isLoading = false;
      _isGeneratingNotifier.value = false; // Hide generating indicator

      if (path != null) {
        // Use the helper's throttled log method
        VideoThumbnailHelper.logWithThrottle(
            '[Thumbnail] Thumbnail generated successfully', widget.videoPath);

        // IMPORTANT: Wrap in setState to ensure widget tree rebuilds
        // ValueNotifier update alone may not trigger rebuild in some cases
        setState(() {
          _thumbnailPathNotifier.value = path;
          _isThumbnailGenerated = true;
          _shouldRegenerateThumbnail = false;
        });
        _onThumbnailGenerated(path);
        // Stop polling if running
        _cachePollTimer?.cancel();
      } else {
        // Use the helper's throttled log method
        VideoThumbnailHelper.logWithThrottle(
            '[Thumbnail] Failed to generate thumbnail', widget.videoPath);

        _thumbnailPathNotifier.value = null;

        // Call onError callback if provided
        if (widget.onError != null) {
          widget.onError!('Failed to generate thumbnail');
        }

        // Start polling cache while visible to recover missed updates
        if (_visibilityNotifier.value) {
          _startCachePolling();
        }
      }

      // Update UI - no need for setState since we use ValueListenableBuilder
      _progressNotifier.value = 1.0;
    }).catchError((error) {
      if (!mounted) return;

      _progressTimer?.cancel();
      // Use the helper's throttled log method
      VideoThumbnailHelper.logWithThrottle(
          '[Thumbnail] Error generating thumbnail: $error', widget.videoPath);

      _thumbnailPathNotifier.value = null;
      _isLoading = false;
      _isGeneratingNotifier.value = false; // Hide generating indicator
      _progressNotifier.value = 0.0;

      // Call onError callback if provided
      if (widget.onError != null) {
        widget.onError!(error);
      }
      // No setState needed - ValueListenableBuilder will handle UI updates
    });
  }

  int? _resolveThumbnailSize() {
    final double target = math.max(widget.width, widget.height);
    if (!target.isFinite || target <= 0) {
      return null;
    }
    final int size = target.round();
    return size.clamp(24, 320);
  }

  /// Simulate progress updates for better UX while thumbnail is generating
  /// PERFORMANCE: Removed periodic timer to eliminate timer storm during scrolling
  void _simulateProgressUpdates() {
    _progressTimer?.cancel();
    _progressNotifier.value = 0.0;

    // Use a single delayed update instead of periodic timer
    // This eliminates the timer storm issue while still providing visual feedback
    _progressTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _thumbnailPathNotifier.value == null) {
        _progressNotifier.value = 0.5;
      }
    });
  }

  /// Handle the thumbnail generation completion
  void _onThumbnailGenerated(String path) {
    // Notify parent about the thumbnail being generated
    if (widget.onThumbnailGenerated != null) {
      // Use a post-frame callback to avoid calling during build
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Use the helper's throttled log method
          VideoThumbnailHelper.logWithThrottle(
              '[Thumbnail] Notifying parent about thumbnail generated',
              widget.videoPath);
          widget.onThumbnailGenerated!(path);
        }
      });
    }

    // No need for setState - ValueListenableBuilder will handle UI updates automatically
  }

  /// Visibility change handler — only tracks visibility state for UI indicators.
  /// Thumbnail generation is NOT gated by visibility; it is driven by
  /// proactiveGenerateAll (for ALL files in the directory) and by
  /// _scheduleInitialLoad as a fallback.
  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;

    final isNowVisible = info.visibleFraction > 0;
    final wasVisible = _visibilityNotifier.value;

    if (isNowVisible == wasVisible) return;

    _visibilityNotifier.value = isNowVisible;

    if (!isNowVisible) {
      _cachePollTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // Use a unique key for the VisibilityDetector based on video path
    // This helps Flutter identify and reuse this widget when possible
    // Use collision-free key to ensure VisibilityDetector delivers events reliably
    final Key visibilityKey = ValueKey('vid-visibility:${widget.videoPath}');

    return RepaintBoundary(
      child: ValueListenableBuilder<String?>(
        valueListenable: _thumbnailPathNotifier,
        builder: (context, thumbnailPath, _) {
          // If we have a thumbnail path, render it directly
          // Skip existsSync() to avoid blocking UI thread during scroll
          // Image.file errorBuilder will handle missing files gracefully
          if (thumbnailPath != null) {
            return _buildThumbnailImage(thumbnailPath);
          }

          // The main widget that detects visibility and loads thumbnails
          return VisibilityDetector(
            key: visibilityKey,
            onVisibilityChanged: _onVisibilityChanged,
            child: ValueListenableBuilder<bool>(
              valueListenable: _isGeneratingNotifier,
              builder: (context, isGenerating, _) {
                return ValueListenableBuilder<ThumbnailGenerationStatus?>(
                  valueListenable: _generationStatusNotifier,
                  builder: (context, status, _) {
                    return Stack(
                      children: [
                        widget.fallbackBuilder(),
                        if (isGenerating)
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  ),
                                  if (status != null) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      status.statusMessage,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  // Polls the cache periodically as a safety net for missed stream events.
  // Uses a short interval with a max attempt count to bound total overhead.
  static const int _maxPollAttempts = 5;
  static const Duration _pollInterval = Duration(milliseconds: 2000);
  int _pollAttempts = 0;

  void _startCachePolling() {
    _cachePollTimer?.cancel();
    _pollAttempts = 0;
    _schedulePollAttempt();
  }

  void _schedulePollAttempt() {
    _cachePollTimer = Timer(_pollInterval, () async {
      if (!mounted) return;

      // Stop if we already have a thumbnail or exceeded max attempts
      if (_thumbnailPathNotifier.value != null || _isLoading) return;

      _pollAttempts++;

      try {
        final cached =
            await VideoThumbnailHelper.getFromCache(widget.videoPath);
        if (cached != null && mounted) {
          setState(() {
            _thumbnailPathNotifier.value = cached;
            _isThumbnailGenerated = true;
            _shouldRegenerateThumbnail = false;
          });
          _onThumbnailGenerated(cached);
          return; // Success — stop polling
        }
      } catch (_) {}

      // Schedule next attempt if we haven't hit the limit
      if (mounted && _pollAttempts < _maxPollAttempts) {
        _schedulePollAttempt();
      }
    });
  }

  /// Build the actual thumbnail image
  Widget _buildThumbnailImage(String thumbnailPath) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Image.file(
          File(thumbnailPath),
          key: ValueKey(
              'thumbnail-${widget.videoPath}-${thumbnailPath.hashCode}-$_thumbnailVersion'),
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          errorBuilder: (context, error, stackTrace) {
            // Use the helper's throttled log method
            VideoThumbnailHelper.logWithThrottle(
                '[Thumbnail] Error loading thumbnail image: $error',
                widget.videoPath);

            _thumbnailPathNotifier.value = null;
            _isLoading = false;
            _isThumbnailGenerated = false;
            _shouldRegenerateThumbnail = true;
            VideoThumbnailHelper.removeFromCache(widget.videoPath);
            return widget.fallbackBuilder();
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) {
              if (!_hasSyncLoadLog) {
                // Use the helper's throttled log method
                VideoThumbnailHelper.logWithThrottle(
                    '[Thumbnail] Thumbnail image loaded synchronously',
                    widget.videoPath);
                _hasSyncLoadLog = true;
              }
              // Also notify for synchronously loaded images
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    widget.onThumbnailGenerated != null &&
                    !_isThumbnailGenerated) {
                  widget.onThumbnailGenerated!(thumbnailPath);
                  _isThumbnailGenerated = true;
                  _shouldRegenerateThumbnail = false;
                }
              });
              // Return with play icon overlay for synchronously loaded images
              return Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  // Add video play icon overlay
                  const Center(
                    child: Icon(
                      PhosphorIconsLight.playCircle,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ],
              );
            }

            if (frame != null) {
              if (!_hasFrameLoadLog) {
                // Use the helper's throttled log method
                VideoThumbnailHelper.logWithThrottle(
                    '[Thumbnail] Thumbnail image frame loaded',
                    widget.videoPath);
                _hasFrameLoadLog = true;
              }
              // Thumbnail is ready now
              SchedulerBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    widget.onThumbnailGenerated != null &&
                    !_isThumbnailGenerated) {
                  widget.onThumbnailGenerated!(thumbnailPath);
                  _isThumbnailGenerated = true;
                  _shouldRegenerateThumbnail = false;
                }
              });
            }

            return AnimatedSwitcher(
              duration: const Duration(
                  milliseconds: 50), // Reduced from 200ms to avoid flickering
              child: frame != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        child,
                        // Add video play icon overlay for local videos
                        const Center(
                          child: Icon(
                            PhosphorIconsLight.playCircle,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    )
                  : SizedBox(
                      width: widget.width,
                      height: widget.height,
                      child: widget.fallbackBuilder()),
            );
          },
        ),
      ),
    );
  }
}
