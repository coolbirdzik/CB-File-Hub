import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../helpers/media/video_thumbnail_helper.dart';
import '../../helpers/core/user_preferences.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';
import 'thumbnail_image.dart';
import 'thumbnail_placeholder.dart';
import 'thumbnail_listing_gate.dart';

/// A widget that efficiently displays a video thumbnail with lazy loading
/// and background processing to avoid UI thread blocking during scrolling
class LazyVideoThumbnail extends StatefulWidget {
  /// Path to the video file for which the thumbnail should be generated
  final String videoPath;

  /// Width of the thumbnail
  final double width;

  /// Height of the thumbnail
  final double height;

  /// How the generated frame is inscribed into the available thumbnail area.
  final BoxFit fit;

  /// Builder for a thumbnail that failed to load.
  final Widget Function() fallbackBuilder;

  /// Whether to keep the thumbnail in memory when it's scrolled out of view
  final bool keepAlive;

  /// If true, only shows the placeholder and doesn't attempt to load thumbnails
  final bool placeholderOnly;
  final bool showLoadingIndicator;

  /// Callback when thumbnail is successfully generated
  final Function(String path)? onThumbnailGenerated;

  /// Callback when thumbnail generation fails with an error
  final Function(dynamic error)? onError;

  const LazyVideoThumbnail({
    super.key,
    required this.videoPath,
    this.width = 160,
    this.height = 120,
    this.fit = BoxFit.cover,
    required this.fallbackBuilder,
    this.keepAlive = true,
    this.placeholderOnly = false,
    this.showLoadingIndicator = true,
    this.onThumbnailGenerated,
    this.onError,
  });

  @override
  State<LazyVideoThumbnail> createState() => _LazyVideoThumbnailState();
}

class _LazyVideoThumbnailState extends State<LazyVideoThumbnail>
    with AutomaticKeepAliveClientMixin {
  // Notifiers to maintain widget state
  final _visibilityNotifier = ValueNotifier<bool>(false);
  final _thumbnailPathNotifier = ValueNotifier<String?>(null);

  // State tracking
  bool _isLoading = false;
  final _hasError = ValueNotifier<bool>(false);
  bool _shouldRegenerateThumbnail = true;
  final Object _viewportOwner = Object();
  final _preferences = UserPreferences.instance;
  bool get _canGenerate =>
      !widget.placeholderOnly &&
      (!_preferences.videoThumbnailViewportOnly.value ||
          (_visibilityNotifier.value && !_isScrollingFast));

  // Progress simulation timer

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

  // AutomaticKeepAliveClientMixin implementation
  // PERFORMANCE: Changed to false to reduce memory pressure during scrolling
  @override
  bool get wantKeepAlive => false; // Changed from widget.keepAlive

  @override
  void initState() {
    super.initState();

    // Listen to scroll velocity changes
    ScrollVelocityNotifier.instance.addListener(_onScrollVelocityChanged);
    _preferences.videoThumbnailViewportOnly.addListener(_onViewportModeChanged);

    _scheduleInitialLoad();

    // Subscribe to cache changed events
    _cacheChangedSubscription = VideoThumbnailHelper.onCacheChanged.listen((_) {
      _handleCacheCleared();
    });

    // Listen for specific thumbnail ready events for this video path
    // Note: readyVideoPath is the normalized cache key, so we need to compare properly
    _thumbReadySubscription = VideoThumbnailHelper.onThumbnailReady.listen((
      readyVideoPath,
    ) async {
      if (!mounted) return;

      // Compare normalized paths since the stream sends the cache key (normalized)
      final normalizedWidgetPath = VideoThumbnailHelper.getNormalizedPath(
        widget.videoPath,
      );
      if (readyVideoPath != normalizedWidgetPath &&
          readyVideoPath != widget.videoPath) {
        return;
      }

      // If we don't yet show a thumbnail, update from cache and repaint
      if (_thumbnailPathNotifier.value == null) {
        try {
          final videoPath = widget.videoPath;
          final cached = await VideoThumbnailHelper.getFromCache(videoPath);
          if (!mounted || widget.videoPath != videoPath) return;
          if (cached != null) {
            // IMPORTANT: Use setState to ensure widget rebuilds
            setState(() {
              _thumbnailPathNotifier.value = cached;
              _shouldRegenerateThumbnail = false;
            });
            _cachePollTimer?.cancel();
          }
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    ScrollVelocityNotifier.instance.removeListener(_onScrollVelocityChanged);
    _preferences.videoThumbnailViewportOnly.removeListener(
      _onViewportModeChanged,
    );
    VideoThumbnailHelper.setViewportVisible(_viewportOwner, null);
    _visibilityNotifier.dispose();
    _thumbnailPathNotifier.dispose();
    _hasError.dispose();
    _cachePollTimer?.cancel();
    _cacheChangedSubscription?.cancel();
    _thumbReadySubscription?.cancel();
    super.dispose();
  }

  void _onScrollVelocityChanged() {
    final isFast = ScrollVelocityNotifier.instance.isScrollingFast;
    if (_isScrollingFast != isFast) {
      _isScrollingFast = isFast;
      if (isFast) {
        // Cancel pending operations when scrolling fast
        _cachePollTimer?.cancel();
        VideoThumbnailHelper.setViewportVisible(_viewportOwner, null);
      } else {
        _updateViewportInterest();
        _scheduleInitialLoad();
      }
    }
  }

  void _updateViewportInterest() {
    VideoThumbnailHelper.setViewportVisible(
      _viewportOwner,
      _visibilityNotifier.value && !widget.placeholderOnly && !_isScrollingFast
          ? widget.videoPath
          : null,
    );
  }

  void _onViewportModeChanged() {
    if (!mounted) return;
    _updateViewportInterest();
    if (_canGenerate) _scheduleInitialLoad();
  }

  @override
  void didUpdateWidget(LazyVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only set regeneration flag if the path actually changed
    if (widget.videoPath != oldWidget.videoPath) {
      _cachePollTimer?.cancel();
      _thumbnailVersion++;
      _thumbnailPathNotifier.value = null;
      _isLoading = false;
      _hasError.value = false;
      _shouldRegenerateThumbnail = true;
      _updateViewportInterest();
      _scheduleInitialLoad();
    }
    if (widget.placeholderOnly != oldWidget.placeholderOnly) {
      _updateViewportInterest();
      _scheduleInitialLoad();
    }
  }

  /// Handle the event when the thumbnail cache is cleared
  void _handleCacheCleared() {
    // Use the helper's throttled log method
    VideoThumbnailHelper.logWithThrottle(
      '[Thumbnail] Cache cleared notification received',
      widget.videoPath,
    );

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
    _hasError.value = false;
    _shouldRegenerateThumbnail = true;
    _thumbnailVersion++; // Increment version to force Image widget rebuild
    _isLoading =
        false; // BUGFIX: Reset loading state so _loadThumbnail doesn't early-return

    // Let clearCache finish before loading again. Keep the real visibility:
    // mounted widgets can belong to hidden tabs or the scroll cache.
    final source = widget.videoPath;
    final version = _thumbnailVersion;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted ||
          widget.videoPath != source ||
          version != _thumbnailVersion) {
        return;
      }

      if (!_canGenerate) return;
      _loadThumbnail(forceRegenerate: true, isPriority: true);
      _startCachePolling();
    });
  }

  /// Schedule initial thumbnail load.
  /// Cached frames can display immediately. New extraction follows the
  /// viewport preference; the helper prefetches a few display-order neighbours.
  void _scheduleInitialLoad() {
    // Don't schedule if we've determined we don't need to regenerate
    if (!_shouldRegenerateThumbnail) return;

    final videoPath = widget.videoPath;
    final cached = VideoThumbnailHelper.peekCachedThumbnailPath(videoPath);
    if (cached != null) {
      _thumbnailPathNotifier.value = cached;
      _shouldRegenerateThumbnail = false;
      return;
    }

    if (!_canGenerate) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.videoPath != videoPath || !_canGenerate) return;

      VideoThumbnailHelper.getFromCache(videoPath)
          .then((cachedThumbnailPath) {
            if (!mounted || widget.videoPath != videoPath) return;

            // If we have a cached path, use it immediately
            if (cachedThumbnailPath != null) {
              setState(() {
                _thumbnailPathNotifier.value = cachedThumbnailPath;
                _shouldRegenerateThumbnail = false;
              });

              return;
            }

            // Not cached — check if proactiveGenerateAll already queued it.
            // If so, wait for the onThumbnailReady stream notification, but also
            // start cache polling as a safety net in case the stream event is
            // missed (e.g. cache-hit early-return in _generateThumbnailInternal).
            if (!_canGenerate) return;
            if (!_preferences.videoThumbnailViewportOnly.value &&
                VideoThumbnailHelper.isPathQueued(widget.videoPath)) {
              _startCachePolling();
              return;
            }

            // Not cached AND not queued (e.g. widget used outside folder list,
            // or proactive queue already finished without this file).
            // Request as a fallback with non-priority so it doesn't disrupt
            // the sorted queue order.
            if (_canGenerate) {
              _loadThumbnail(isPriority: _visibilityNotifier.value);
            }
          })
          .catchError((error) {
            VideoThumbnailHelper.logWithThrottle(
              '[Thumbnail] Error checking cache: $error',
              widget.videoPath,
            );
          });
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// Start loading the thumbnail
  void _loadThumbnail({bool forceRegenerate = false, bool isPriority = false}) {
    // Skip if already loading, if we're in placeholder-only mode,
    // if we already have a thumbnail generated and don't need to regenerate,
    // or if we've determined we don't need to regenerate
    if (_isLoading ||
        !_canGenerate ||
        (_thumbnailPathNotifier.value != null && !forceRegenerate) ||
        (!_shouldRegenerateThumbnail && !forceRegenerate)) {
      return;
    }

    final videoPath = widget.videoPath;
    final version = _thumbnailVersion;
    if (!ThumbnailListingGate.instance.isReadyFor(videoPath)) {
      ThumbnailListingGate.instance.whenReady(() {
        if (mounted &&
            widget.videoPath == videoPath &&
            version == _thumbnailVersion) {
          _loadThumbnail(
            forceRegenerate: forceRegenerate,
            isPriority: isPriority,
          );
        }
      }, source: videoPath);
      return;
    }
    _hasError.value = false;

    // Use the helper's throttled log method
    VideoThumbnailHelper.logWithThrottle(
      '[Thumbnail] Starting thumbnail load (force=$forceRegenerate, priority=$isPriority)',
      widget.videoPath,
    );

    _isLoading = true;

    final int? thumbnailSize = _resolveThumbnailSize();

    // If the path is already queued by proactiveGenerateAll (which respects
    // sort order), don't re-request with isPriority=true as that would
    // assign flat priority 100 and disrupt the top-to-bottom generation order.
    // Instead, just wait for the onThumbnailReady stream to deliver the result.
    final bool alreadyQueued = VideoThumbnailHelper.isPathQueued(
      widget.videoPath,
    );
    if (alreadyQueued &&
        !forceRegenerate &&
        !_preferences.videoThumbnailViewportOnly.value) {
      // Already queued with correct priority — just wait for stream notification
      _isLoading = false;
      _startCachePolling();
      return;
    }

    final bool usePriority = _preferences.videoThumbnailViewportOnly.value
        ? _visibilityNotifier.value
        : isPriority && !(thumbnailSize != null && thumbnailSize <= 96);

    // Use VideoThumbnailHelper directly instead of ThumbnailIsolateManager
    VideoThumbnailHelper.generateThumbnail(
          widget.videoPath,
          isPriority: usePriority,
          forceRegenerate: forceRegenerate,
          thumbnailSize: thumbnailSize,
          viewportOwner: _viewportOwner,
        )
        .then((path) {
          if (!mounted ||
              widget.videoPath != videoPath ||
              version != _thumbnailVersion) {
            return;
          }

          _isLoading = false;
          if (path == null && !_canGenerate) return;

          if (path != null) {
            // Use the helper's throttled log method
            VideoThumbnailHelper.logWithThrottle(
              '[Thumbnail] Thumbnail generated successfully',
              widget.videoPath,
            );

            // IMPORTANT: Wrap in setState to ensure widget tree rebuilds
            // ValueNotifier update alone may not trigger rebuild in some cases
            setState(() {
              _thumbnailPathNotifier.value = path;
              _shouldRegenerateThumbnail = false;
            });
            // Stop polling if running
            _cachePollTimer?.cancel();
          } else {
            // Use the helper's throttled log method
            VideoThumbnailHelper.logWithThrottle(
              '[Thumbnail] Failed to generate thumbnail',
              widget.videoPath,
            );

            _thumbnailPathNotifier.value = null;
            _hasError.value = true;

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
        })
        .catchError((error) {
          if (!mounted ||
              widget.videoPath != videoPath ||
              version != _thumbnailVersion) {
            return;
          }

          // Use the helper's throttled log method
          VideoThumbnailHelper.logWithThrottle(
            '[Thumbnail] Error generating thumbnail: $error',
            widget.videoPath,
          );

          _thumbnailPathNotifier.value = null;
          _hasError.value = true;
          _isLoading = false;

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

  /// Keep tracking decoded tiles too, so scrolling away releases prefetch work.
  void _onVisibilityChanged(VisibilityInfo info) {
    if (!mounted) return;

    final isNowVisible = info.visibleFraction > 0;
    final wasVisible = _visibilityNotifier.value;

    if (isNowVisible == wasVisible) return;

    _visibilityNotifier.value = isNowVisible;
    _updateViewportInterest();

    if (!isNowVisible) {
      _cachePollTimer?.cancel();
    } else {
      _scheduleInitialLoad();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(
      child: VisibilityDetector(
        key: ValueKey('vid-visibility:${widget.videoPath}'),
        onVisibilityChanged: _onVisibilityChanged,
        child: ValueListenableBuilder<String?>(
          valueListenable: _thumbnailPathNotifier,
          builder: (context, thumbnailPath, _) {
            if (thumbnailPath != null) {
              return _buildThumbnailImage(thumbnailPath);
            }
            return ValueListenableBuilder<bool>(
              valueListenable: _hasError,
              builder: (context, failed, _) => failed
                  ? widget.fallbackBuilder()
                  : ThumbnailPlaceholder(
                      isVideo: true,
                      visible: widget.showLoadingIndicator,
                    ),
            );
          },
        ),
      ),
    );
  }

  // Polls the cache periodically as a safety net for missed stream events.
  // Uses a short interval with a max attempt count to bound total overhead.
  static const int _maxPollAttempts = 5;
  static const Duration _pollInterval = Duration(milliseconds: 2000);
  int _pollAttempts = 0;

  void _startCachePolling() {
    if (!_canGenerate) return;
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

      final videoPath = widget.videoPath;
      try {
        final cached = await VideoThumbnailHelper.getFromCache(videoPath);
        if (!mounted || widget.videoPath != videoPath) return;
        if (cached != null) {
          setState(() {
            _thumbnailPathNotifier.value = cached;
            _shouldRegenerateThumbnail = false;
          });
          return; // Success — stop polling
        }
      } catch (_) {}

      // Schedule next attempt if we haven't hit the limit
      if (mounted && _pollAttempts < _maxPollAttempts) {
        _schedulePollAttempt();
      }
    });
  }

  /// The decoded frame, not generation/cache lookup, completes loading.
  Widget _buildThumbnailImage(String thumbnailPath) {
    final videoPath = widget.videoPath;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ThumbnailImage(
        key: ValueKey('$videoPath-$thumbnailPath-$_thumbnailVersion'),
        image: FileImage(File(thumbnailPath)),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        isVideo: true,
        showLoadingIndicator: widget.showLoadingIndicator,
        onReady: () {
          _shouldRegenerateThumbnail = false;
          widget.onThumbnailGenerated?.call(thumbnailPath);
        },
        errorBuilder: widget.fallbackBuilder,
        onError: (error) {
          if (!mounted ||
              widget.videoPath != videoPath ||
              _thumbnailPathNotifier.value != thumbnailPath) {
            return;
          }
          _hasError.value = true;
          _thumbnailPathNotifier.value = null;
          _isLoading = false;
          _shouldRegenerateThumbnail = true;
          unawaited(
            VideoThumbnailHelper.removeFromCache(videoPath).then((_) {
              if (mounted &&
                  widget.videoPath == videoPath &&
                  !widget.placeholderOnly) {
                _scheduleInitialLoad();
              }
            }),
          );
          widget.onError?.call(error);
        },
      ),
    );
  }
}
