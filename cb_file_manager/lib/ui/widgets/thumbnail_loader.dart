import 'dart:collection';
import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/network/network_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/widgets/lazy_video_thumbnail.dart';
import 'package:cb_file_manager/ui/utils/scroll_velocity_notifier.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'thumbnail_listing_gate.dart';
import 'thumbnail_placeholder.dart';
import 'thumbnail_image.dart';

/// Memory pool để tái sử dụng image objects và giảm memory fragmentation
class ImageMemoryPool {
  static final Map<String, ui.Image> _imagePool = {};
  static final Map<String, DateTime> _lastUsed = {};
  static const int maxPoolSize = 50;
  static const Duration maxAge = Duration(minutes: 5);

  static void putImage(String key, ui.Image image) {
    _cleanupOldImages();
    if (_imagePool.length >= maxPoolSize) {
      _evictOldest();
    }
    _imagePool[key] = image;
    _lastUsed[key] = DateTime.now();
  }

  static ui.Image? getImage(String key) {
    final image = _imagePool[key];
    if (image != null) {
      _lastUsed[key] = DateTime.now();
    }
    return image;
  }

  static void _cleanupOldImages() {
    final now = DateTime.now();
    final keysToRemove = <String>[];

    _lastUsed.forEach((key, lastUsed) {
      if (now.difference(lastUsed) > maxAge) {
        keysToRemove.add(key);
      }
    });

    for (final key in keysToRemove) {
      _imagePool[key]?.dispose();
      _imagePool.remove(key);
      _lastUsed.remove(key);
    }
  }

  static void _evictOldest() {
    if (_lastUsed.isEmpty) return;

    final oldest = _lastUsed.entries.reduce(
      (a, b) => a.value.isBefore(b.value) ? a : b,
    );

    _imagePool[oldest.key]?.dispose();
    _imagePool.remove(oldest.key);
    _lastUsed.remove(oldest.key);
  }

  static void clear() {
    for (var image in _imagePool.values) {
      image.dispose();
    }
    _imagePool.clear();
    _lastUsed.clear();
  }
}

/// A global thumbnail cache to avoid regenerating thumbnails
class ThumbnailWidgetCache {
  static final ThumbnailWidgetCache _instance =
      ThumbnailWidgetCache._internal();
  factory ThumbnailWidgetCache() => _instance;
  ThumbnailWidgetCache._internal();

  final Map<String, Widget> _thumbnailWidgets = {};
  final Map<String, String> _thumbnailPaths =
      {}; // Cache for thumbnail file paths
  final Map<String, DateTime> _lastAccessTime = {};
  final Set<String> _generatingThumbnails = {};
  final Set<String> _failedThumbnails = {};

  // Stream controller to notify widgets when new thumbnails are available
  final StreamController<String> _thumbnailReadyController =
      StreamController<String>.broadcast();
  Stream<String> get onThumbnailReady => _thumbnailReadyController.stream;

  // Stream controller to notify when all thumbnails are loaded
  static final StreamController<bool> _allThumbnailsLoadedController =
      StreamController<bool>.broadcast();
  static Stream<bool> get onAllThumbnailsLoaded =>
      _allThumbnailsLoadedController.stream;

  // PERFORMANCE: Further reduced cache sizes for better memory management
  static const int _maxCacheSize = 150; // Further reduced from 200 for desktop
  static const Duration _cacheRetentionTime = Duration(
    minutes: 15, // Reduced from 30 minutes
  );

  Widget? getCachedThumbnailWidget(String path) {
    final widget = _thumbnailWidgets[path];
    if (widget != null) {
      _lastAccessTime[path] = DateTime.now();
    }
    return widget;
  }

  void cacheWidgetThumbnail(String path, Widget thumbnailWidget) {
    _thumbnailWidgets[path] = thumbnailWidget;
    _lastAccessTime[path] = DateTime.now();
    _cleanupCacheIfNeeded();
  }

  String? getCachedThumbnailPath(String path) {
    final thumbnailPath = _thumbnailPaths[path];
    if (thumbnailPath != null) {
      _lastAccessTime[path] = DateTime.now();
    }
    return thumbnailPath;
  }

  void cacheThumbnailPath(String path, String thumbnailPath) {
    _failedThumbnails.remove(path);
    _thumbnailPaths[path] = thumbnailPath;
    _lastAccessTime[path] = DateTime.now();
    _cleanupCacheIfNeeded();

    // Notify all listening widgets that a new thumbnail is ready
    _thumbnailReadyController.add(path);
  }

  bool isGeneratingThumbnail(String path) =>
      _generatingThumbnails.contains(path);
  void markGeneratingThumbnail(String path) {
    _failedThumbnails.remove(path);
    _generatingThumbnails.add(path);
  }

  bool hasFailedThumbnail(String path) => _failedThumbnails.contains(path);
  void markThumbnailFailed(String path) {
    _failedThumbnails.add(path);
    if (_failedThumbnails.length > _maxCacheSize) {
      _failedThumbnails.remove(_failedThumbnails.first);
    }
    _thumbnailReadyController.add(path);
  }

  void markThumbnailGenerated(String path) {
    _generatingThumbnails.remove(path);

    // If no more thumbnails are being generated, notify listeners
    if (_generatingThumbnails.isEmpty &&
        ThumbnailLoader.pendingThumbnailCount == 0) {
      _allThumbnailsLoadedController.add(true);
    }
  }

  void clearCache() {
    _thumbnailWidgets.clear();
    _thumbnailPaths.clear();
    _lastAccessTime.clear();
    _generatingThumbnails.clear();
    _failedThumbnails.clear();
  }

  void dispose() {
    _thumbnailReadyController.close();
    _allThumbnailsLoadedController.close();
    clearCache();
    debugPrint('ThumbnailWidgetCache: Disposed resources');
  }

  void _cleanupCacheIfNeeded() {
    if (_thumbnailWidgets.length > _maxCacheSize) {
      // Sort by last access time (oldest first)
      final sortedEntries = _lastAccessTime.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      // Remove oldest entries until we're below the limit
      final entriesToRemove = sortedEntries.take((_maxCacheSize * 0.2).round());
      for (final entry in entriesToRemove) {
        _thumbnailWidgets.remove(entry.key);
        _lastAccessTime.remove(entry.key);
      }
    }
  }

  // Clean up entries that haven't been accessed for a while
  void cleanupStaleEntries() {
    final now = DateTime.now();
    final stalePaths = _lastAccessTime.entries
        .where((entry) => now.difference(entry.value) > _cacheRetentionTime)
        .map((entry) => entry.key)
        .toList();

    for (final path in stalePaths) {
      _thumbnailWidgets.remove(path);
      _thumbnailPaths.remove(path);
      _lastAccessTime.remove(path);
    }
  }

  // Check if any thumbnails are still being generated
  bool get isAnyThumbnailGenerating =>
      _generatingThumbnails.isNotEmpty ||
      ThumbnailLoader.pendingThumbnailCount > 0;
}

/// A widget that displays thumbnails for images and videos with loading indicators
class ThumbnailLoader extends StatefulWidget {
  @visibleForTesting
  static Future<String?> Function(String path, int size)?
  debugNetworkThumbnailGenerator;
  final String filePath;
  final bool isVideo;
  final bool isImage;
  final double width;
  final double height;
  final BoxFit fit;
  final bool showLoadingIndicator;
  final Widget Function()? fallbackBuilder;
  final VoidCallback? onThumbnailLoaded;
  final BorderRadius? borderRadius;
  final bool isPriority;

  // Static counter to track pending thumbnail generation tasks
  static int pendingThumbnailCount = 0;

  // Display-index map: maps file path to its index in the current display order.
  // Lower index = higher priority. Updated by the parent file list view
  // whenever the file list changes (load, sort, filter).
  // This is the key to solving the "load in file-system order vs display in sort order" problem.
  static final Map<String, int> _displayIndexByPath = <String, int>{};

  // Stream controller to notify when background tasks change
  static final StreamController<int> _pendingTasksController =
      StreamController<int>.broadcast();
  static Stream<int> get onPendingTasksChanged =>
      _pendingTasksController.stream;

  // Method to check if any background tasks are still running
  static bool get hasBackgroundTasks =>
      pendingThumbnailCount > 0 ||
      ThumbnailWidgetCache()._generatingThumbnails.isNotEmpty;

  // Update the display-index map. Call this from the parent file list view
  // whenever the file list changes (load, sort, filter).
  // [filePaths] is the current list of file paths in display order.
  static void updateDisplayIndexMap(List<String> filePaths) {
    _displayIndexByPath.clear();
    for (var i = 0; i < filePaths.length; i++) {
      _displayIndexByPath[filePaths[i]] = i;
    }
    // Also update VideoThumbnailHelper so its _requestThumbnail uses the same map.
    VideoThumbnailHelper.updateDisplayIndexMap(filePaths);
  }

  // Clear the display-index map (e.g., when navigating away).
  static void clearDisplayIndexMap() {
    _displayIndexByPath.clear();
    VideoThumbnailHelper.clearDisplayIndexMap();
  }

  // Get the display index for a path. Returns null if not in map.
  static int? getDisplayIndex(String path) => _displayIndexByPath[path];

  // ── Listing-ready gate ────────────────────────────────────────────────────
  // When the parent screen is still loading / scanning the file list,
  // thumbnail generation should be deferred so it doesn't compete for I/O
  // and CPU with the listing work. Scanners acquire [pauseListing] and release
  // that token after publishing the listing, with a finally block for failures.
  /// Whether the file listing is complete and thumbnails can start loading.
  static bool get isListingReady => ThumbnailListingGate.instance.isReady;

  static bool isListingReadyFor(String path) =>
      ThumbnailListingGate.instance.isReadyFor(path);

  static VoidCallback pauseListing({String? folder}) =>
      ThumbnailListingGate.instance.pause(folder: folder);

  /// Register a callback to run when the listing becomes ready.
  /// Used by album tiles that live outside [_ThumbnailLoaderState].
  static void runAfterReady(VoidCallback callback, {String? source}) =>
      ThumbnailListingGate.instance.whenReady(callback, source: source);

  /// Signal whether the file listing is complete.
  /// When [ready] becomes true, all deferred thumbnail loads are flushed.
  static void setListingReady(bool ready) {
    ThumbnailListingGate.instance.setLegacyReady(ready);
  }

  // Method to reset pending thumbnail count
  static void resetPendingCount() {
    if (pendingThumbnailCount > 0) {
      pendingThumbnailCount = 0;
      _pendingTasksController.add(0);
    }
  }

  // Method to force reset pending count (for debugging and edge cases)
  static void forceResetPendingCount() {
    pendingThumbnailCount = 0;
    _pendingTasksController.add(0);
  }

  // Method to clean up static resources
  static void disposeStatic() {
    _pendingTasksController.close();
    ThumbnailWidgetCache._allThumbnailsLoadedController.close();
    debugPrint('ThumbnailLoader: Disposed static resources');
  }

  // ── Tab suspend/resume registry ───────────────────────────────────────────
  // Allows the tab activity system to suspend thumbnail loading for inactive
  // tabs and resume when they become active again.
  static final Map<String, Set<String>> _suspendedTabs = {};

  /// Suspend thumbnail loading for a tab. Widgets whose [filePath] starts
  /// with [path] will skip enqueue while the tab is suspended.
  /// If [path] is empty, the tab entry is removed (no-op suspend).
  static void suspendTab(String tabId, String path) {
    if (path.isEmpty) {
      _suspendedTabs.remove(tabId);
      return;
    }
    _suspendedTabs.putIfAbsent(tabId, () => <String>{}).add(path);
  }

  /// Resume thumbnail loading for a tab.
  static void resumeTab(String tabId) {
    _suspendedTabs.remove(tabId);
  }

  /// Whether a given file path is currently suspended (belongs to an
  /// inactive tab).
  static bool isPathSuspended(String filePath) {
    for (final paths in _suspendedTabs.values) {
      for (final p in paths) {
        if (filePath.startsWith(p)) return true;
      }
    }
    return false;
  }

  /// Debug helper: number of currently suspended tabs.
  static int debugSuspendedTabCount() => _suspendedTabs.length;

  /// Debug helper: clear the suspend registry.
  static void debugClearSuspendRegistry() {
    _suspendedTabs.clear();
  }

  // Static method to reset failed attempts (useful for network reconnection)
  static void resetFailedAttempts() {
    _ThumbnailLoaderState._failedAttempts.clear();
    _ThumbnailLoaderState._lastAttemptTime.clear();
  }

  const ThumbnailLoader({
    super.key,
    required this.filePath,
    required this.isVideo,
    required this.isImage,
    this.width = double.infinity,
    this.height = double.infinity,
    this.fit = BoxFit.cover,
    this.showLoadingIndicator = true,
    this.fallbackBuilder,
    this.onThumbnailLoaded,
    this.borderRadius,
    this.isPriority = false,
  });

  @override
  State<ThumbnailLoader> createState() => _ThumbnailLoaderState();
}

class _ThumbnailLoaderState extends State<ThumbnailLoader>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final ThumbnailWidgetCache _cache = ThumbnailWidgetCache();
  final ValueNotifier<bool> _hasErrorNotifier = ValueNotifier<bool>(false);
  StreamSubscription? _thumbnailReadySubscription;
  bool _widgetMounted = true;
  Timer? _loadTimer;
  Timer? _delayedLoadTimer;
  Timer? _refreshTimer;
  Timer? _visibilityDebounceTimer;
  String? _networkThumbnailPath; // Store the generated thumbnail path
  bool _isScrollingFast = false; // Track if user is scrolling fast
  int _thumbnailVersion = 0;

  // Debounce for VisibilityDetector: kept short because loading a cached
  // thumbnail JPEG is cheap.  Fast-scroll detection (ScrollVelocityNotifier)
  // is the primary gating mechanism, not this timer.
  static const Duration _visibilityDebounceDuration = Duration(
    milliseconds: 100,
  );

  // No extra delay: thumbnail display is fast once the JPEG is cached.
  static const Duration _thumbnailLoadDelay = Duration.zero;

  // Viewport-based loading priority system.
  // Priority is based on DISPLAY order (sorted list index), not file system order.
  // When the user sorts by date/name, files at the top of the UI (index 0)
  // should load before files at the bottom (index 100+), regardless of which
  // file system entries the OS listed first.
  // SplayTreeMap keeps entries sorted by key automatically — O(log N) insert
  // and O(log N) first-key access, replacing the previous O(N log N) sort.
  // Key is (displayIndex * 1_000_000 + insertionCounter) to break ties by
  // arrival order (FIFO within the same display-index bucket).
  static final SplayTreeMap<int, String> _loadingQueue =
      SplayTreeMap<int, String>();
  static int _queueInsertionCounter = 0;
  static bool _isProcessingQueue = false;

  // ── Global static listeners (shared across all instances) ──────────────────
  // Instead of each instance registering its own WidgetsBinding observer and
  // ScrollVelocityNotifier listener (N listeners for N items), we use a single
  // static listener that notifies all instances via a Set.
  static final Set<_ThumbnailLoaderState> _liveInstances = {};
  static bool _staticListenersRegistered = false;

  static void _ensureStaticListeners() {
    if (_staticListenersRegistered) return;
    _staticListenersRegistered = true;
    ScrollVelocityNotifier.instance.addListener(_onGlobalScrollVelocityChanged);
  }

  static void _onGlobalScrollVelocityChanged() {
    final isFast = ScrollVelocityNotifier.instance.isScrollingFast;
    for (final instance in _liveInstances) {
      if (isFast && instance._isScrollingFast != isFast) {
        instance._isScrollingFast = true;
        instance._cancelPendingLoad();
      } else if (!isFast && instance._isScrollingFast != isFast) {
        instance._isScrollingFast = false;
      }
    }
  }

  // ── Global cache-change handler ─────────────────────────────────────────────
  // The old code had every instance subscribe to VideoThumbnailHelper.onCacheChanged
  // and call _cache.clearCache() on each event — clearing the SHARED singleton N
  // times. Now a single static subscription handles it once.
  static StreamSubscription<void>? _globalCacheChangedSubscription;
  static bool _cacheInvalidationPending = false;

  static void _ensureGlobalCacheListener() {
    if (_globalCacheChangedSubscription != null) return;
    _globalCacheChangedSubscription = VideoThumbnailHelper.onCacheChanged.listen((
      _,
    ) {
      if (_cacheInvalidationPending) return; // coalesce rapid bursts
      _cacheInvalidationPending = true;
      // Clear the shared cache exactly once, then invalidate all live instances.
      ThumbnailWidgetCache().clearCache();
      for (final instance in List.of(_liveInstances)) {
        if (instance._widgetMounted) {
          instance._invalidateThumbnail();
        }
      }
      _cacheInvalidationPending = false;
    });
  }

  // ── File-exists cache ───────────────────────────────────────────────────────
  // Background processing limits
  static const int maxConcurrentLoads =
      5; // Tăng từ 3 để SMB thumbnails load nhanh hơn
  static int _currentLoads = 0;

  // Track failed attempts with retry limits and backoff
  static final _failedAttempts = <String, int>{};
  static final _lastAttemptTime = <String, DateTime>{};
  static const int _maxRetries = 3;
  static const Duration _retryBackoff = Duration(seconds: 2);

  // Limit how many thumbnails can be loaded at once per screen.
  // Increased for SMB: thumbnails are fetched over the network (not local disk)
  // so the raster thread is the only real bottleneck. 4 allows noticeably
  // faster thumbnail grid population without causing visible jank.
  static int _activeLoaders = 0;
  static const int _maxActiveLoaders = 4;

  @override
  bool get wantKeepAlive =>
      // Keep visible/nearby image+video thumbnail states alive so scrolling
      // away and back does not recreate the whole thumbnail pipeline.
      widget.isImage || widget.isVideo;

  @override
  void initState() {
    super.initState();
    _widgetMounted = true;

    // Register in global live-instances set (replaces per-instance
    // WidgetsBinding.addObserver and ScrollVelocityNotifier.addListener).
    _liveInstances.add(this);
    _ensureStaticListeners();
    _ensureGlobalCacheListener();

    // Per-instance subscription only for thumbnail-ready events specific to this path.
    _thumbnailReadySubscription = _cache.onThumbnailReady.listen((path) {
      if (_widgetMounted && mounted && path == widget.filePath) {
        final cachedPath = _cache.getCachedThumbnailPath(widget.filePath);
        if (cachedPath != null) {
          setState(() {
            _networkThumbnailPath = cachedPath;
          });
          _hasErrorNotifier.value = false;
        } else if (_cache.hasFailedThumbnail(path)) {
          _hasErrorNotifier.value = true;
        }
      }
    });

    // Check cache first - only use cached result, don't trigger load
    // Actual loading is deferred to VisibilityDetector to avoid blocking scroll
    final cachedPath = _cache.getCachedThumbnailPath(widget.filePath);
    if (cachedPath != null) {
      _networkThumbnailPath = cachedPath;
      _hasErrorNotifier.value = false;
    }
    // For local image files, ResizeImage handles everything via Flutter's
    // ImageCache - no PhotoThumbnailHelper lookup needed here.
    // For network files, VisibilityDetector will trigger _loadThumbnail.
  }

  // Scroll velocity changes are handled by the static _onGlobalScrollVelocityChanged
  // listener — no per-instance listener needed.

  void _scheduleLoad() {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(milliseconds: 50), () {
      // Reduced delay
      if (mounted) {
        _addToLoadingQueue();
      }
    });
  }

  // Smart loading với priority queue - delay to prioritize file list display
  void _scheduleLoadWithDelay() {
    _delayedLoadTimer?.cancel();
    _delayedLoadTimer = Timer(_thumbnailLoadDelay, () {
      if (_widgetMounted && mounted) {
        _addToLoadingQueue();
      }
    });
  }

  // Add item to queue with its display index (sort order position).
  // Items with lower index get loaded first.
  // The SplayTreeMap keeps the queue always sorted — O(log N) insert.
  void _addToLoadingQueue([int? displayIndex]) {
    // Look up display index from the map if not explicitly provided.
    final baseIndex =
        displayIndex ??
        ThumbnailLoader.getDisplayIndex(widget.filePath) ??
        999999;
    // Combine display index and insertion counter into a single sortable key
    // so that ties (same display index) are broken by arrival order (FIFO).
    // Multiply by 1000000 to leave room for up to 1M items at the same index.
    final queueKey = baseIndex * 1000000 + (_queueInsertionCounter % 1000000);
    // Skip if already in queue (check values set for O(N) but rare in practice).
    if (_loadingQueue.values.contains(widget.filePath)) return;
    _loadingQueue[queueKey] = widget.filePath;
    _queueInsertionCounter++;
    _processLoadingQueue();
  }

  // Process queue with concurrency limit, loading items in priority order.
  // SplayTreeMap.firstKey() is O(log N), removing first entry is O(log N).
  // Previously this did a full O(N log N) sort on every call.
  static void _processLoadingQueue() {
    if (_isProcessingQueue || _currentLoads >= maxConcurrentLoads) return;
    _isProcessingQueue = true;
    try {
      while (_loadingQueue.isNotEmpty && _currentLoads < maxConcurrentLoads) {
        final path = _loadingQueue.remove(_loadingQueue.firstKey())!;
        final instances = _liveInstances.where(
          (state) => state._widgetMounted && state.widget.filePath == path,
        );
        if (instances.isEmpty) continue;
        _currentLoads++;
        unawaited(
          instances.first._loadThumbnail().whenComplete(() {
            _currentLoads--;
            _processLoadingQueue();
          }),
        );
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  // Cancel pending loads to save resources.
  void _cancelPendingLoad() {
    _loadTimer?.cancel();
    _delayedLoadTimer?.cancel();
    // Remove from priority queue (scan all values since key is composite).
    final keysToRemove = <int>[];
    for (final e in _loadingQueue.entries) {
      if (e.value == widget.filePath) keysToRemove.add(e.key);
    }
    for (final k in keysToRemove) {
      _loadingQueue.remove(k);
    }
  }

  @override
  void didUpdateWidget(ThumbnailLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.isVideo != widget.isVideo ||
        oldWidget.isImage != widget.isImage) {
      _cancelPendingLoad();
      _thumbnailVersion++;
      _networkThumbnailPath = null; // Reset thumbnail path
      _hasErrorNotifier.value = false;
      _scheduleLoad();
    }
  }

  void _invalidateThumbnail() {
    _hasErrorNotifier.value = false;
    setState(() {
      _thumbnailVersion++;
      _networkThumbnailPath = null;
    });
    // Use a small delay to prevent multiple reloads in quick succession
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_widgetMounted && mounted) {
        _loadThumbnail();
      }
    });
  }

  @override
  void dispose() {
    _liveInstances.remove(this);
    _thumbnailReadySubscription?.cancel();
    _hasErrorNotifier.dispose();
    _widgetMounted = false;
    _loadTimer?.cancel();
    _delayedLoadTimer?.cancel();
    _refreshTimer?.cancel();
    _visibilityDebounceTimer?.cancel();

    // Clear retry tracking for this path
    _failedAttempts.remove(widget.filePath);
    _lastAttemptTime.remove(widget.filePath);

    // Cleanup memory
    _networkThumbnailPath = null;

    // Mark this path as invisible (lower priority)
    if (widget.filePath.startsWith('#network/')) {
      NetworkThumbnailHelper().markInvisible(widget.filePath);
    }

    super.dispose();
  }

  Future<void> _loadThumbnail() async {
    if (!_widgetMounted) return;
    if (!widget.filePath.startsWith('#network/')) return;

    // Wait until the parent file list is fully loaded before starting
    // thumbnail work. This prevents thumbnail generation from competing
    // with directory scanning / sorting for I/O and CPU time.
    if (!ThumbnailLoader.isListingReadyFor(widget.filePath)) {
      ThumbnailLoader.runAfterReady(() {
        if (_widgetMounted && mounted) _loadThumbnail();
      }, source: widget.filePath);
      return;
    }

    final path = widget.filePath;
    final version = _thumbnailVersion;
    if (_cache.isGeneratingThumbnail(path)) return;
    if (_networkThumbnailPath != null ||
        _cache.getCachedThumbnailPath(path) != null) {
      return;
    }
    // Check retry limits and backoff
    final now = DateTime.now();
    final lastAttempt = _lastAttemptTime[path];
    final failedCount = _failedAttempts[path] ?? 0;

    // Skip if we've exceeded max retries
    if (failedCount >= _maxRetries) {
      _hasErrorNotifier.value = true;
      return;
    }

    // Skip if we tried too recently (exponential backoff)
    if (lastAttempt != null) {
      final backoffDelay = Duration(
        seconds: _retryBackoff.inSeconds * (failedCount + 1),
      );
      final elapsed = now.difference(lastAttempt);
      if (elapsed < backoffDelay) {
        _delayedLoadTimer?.cancel();
        _delayedLoadTimer = Timer(backoffDelay - elapsed, () {
          if (_widgetMounted) _addToLoadingQueue();
        });
        return;
      }
    }

    final limit = (Platform.isAndroid || Platform.isIOS)
        ? 2
        : _maxActiveLoaders;
    if (_activeLoaders >= limit) {
      _scheduleLoad();
      return;
    }
    _hasErrorNotifier.value = false;
    _lastAttemptTime[path] = now;
    _cache.markGeneratingThumbnail(path);
    _activeLoaders++;
    ThumbnailLoader.pendingThumbnailCount++;
    ThumbnailLoader._pendingTasksController.add(
      ThumbnailLoader.pendingThumbnailCount,
    );
    try {
      NetworkThumbnailHelper().markVisible(path);
      final size = (Platform.isAndroid || Platform.isIOS) ? 128 : 256;
      final request =
          ThumbnailLoader.debugNetworkThumbnailGenerator?.call(path, size) ??
          NetworkThumbnailHelper().generateThumbnail(path, size: size);
      final thumbnail = await request.timeout(
        Duration(seconds: widget.isVideo ? 30 : 6),
      );
      if (thumbnail != null) {
        _failedAttempts.remove(path);
        _cache.cacheThumbnailPath(path, thumbnail);
      } else {
        _failedAttempts[path] = failedCount + 1;
        _cache.markThumbnailFailed(path);
      }
    } on ThumbnailSkippedException {
      if (_widgetMounted &&
          widget.filePath == path &&
          version == _thumbnailVersion) {
        _delayedLoadTimer?.cancel();
        _delayedLoadTimer = Timer(_retryBackoff, _addToLoadingQueue);
      }
    } catch (_) {
      _failedAttempts[path] = failedCount + 1;
      _cache.markThumbnailFailed(path);
    } finally {
      _activeLoaders--;
      if (ThumbnailLoader.pendingThumbnailCount > 0) {
        ThumbnailLoader.pendingThumbnailCount--;
      }
      ThumbnailLoader._pendingTasksController.add(
        ThumbnailLoader.pendingThumbnailCount,
      );
      _cache.markThumbnailGenerated(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Gói toàn bộ nội dung bên trong VisibilityDetector để chỉ tải khi thấy trên màn hình
    return RepaintBoundary(
      child: VisibilityDetector(
        key: ValueKey('vis-${widget.filePath}'),
        onVisibilityChanged: (info) {
          if (!_widgetMounted) return;

          // PERFORMANCE: Skip loading during fast scrolling
          if (ScrollVelocityNotifier.instance.isScrollingFast) {
            _visibilityDebounceTimer?.cancel();
            _cancelPendingLoad();
            return;
          }

          // PERFORMANCE: Debounce visibility changes to prevent excessive operations during scrolling
          _visibilityDebounceTimer?.cancel();

          // Increased threshold: only load when visible fraction > 80% to avoid loading too early
          if (info.visibleFraction > 0.8) {
            // Debounce becoming visible to avoid loading during fast scrolling
            _visibilityDebounceTimer = Timer(_visibilityDebounceDuration, () {
              if (!_widgetMounted) return;

              // Double-check scroll velocity before loading
              if (ScrollVelocityNotifier.instance.isScrollingFast) {
                return;
              }

              // Became visible
              NetworkThumbnailHelper().markVisible(widget.filePath);

              // Local videos already have LazyVideoThumbnail's cache/generation
              // pipeline; starting another one here duplicated mapped-drive
              // file probes and video requests for every newly visible tile.
              // Local images likewise use ResizeImage's own lifecycle.
              final bool needsExplicitLoad = widget.filePath.startsWith('#');
              if (needsExplicitLoad &&
                  _networkThumbnailPath == null &&
                  !_cache.isGeneratingThumbnail(widget.filePath) &&
                  !ScrollVelocityNotifier.instance.isScrollingFast) {
                _scheduleLoadWithDelay();
              }
            });
          } else if (info.visibleFraction == 0) {
            // Immediately handle becoming invisible (no debounce needed)
            NetworkThumbnailHelper().markInvisible(widget.filePath);
            _cancelPendingLoad();
          }
        },
        child: ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.zero,
          // PERFORMANCE: Consolidated ValueListenableBuilder to eliminate double rebuilds
          child: ValueListenableBuilder<bool>(
            valueListenable: _hasErrorNotifier,
            builder: (context, hasError, _) {
              if (hasError) {
                return RepaintBoundary(child: _buildFallbackWidget());
              }

              // The image's first decoded frame controls its placeholder.
              return RepaintBoundary(child: _buildThumbnailContent());
            },
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailContent() {
    if (widget.isVideo) {
      return _buildVideoThumbnail();
    } else if (widget.isImage) {
      return _buildImageThumbnail();
    } else {
      return _buildFallbackWidget();
    }
  }

  Widget _buildVideoThumbnail() {
    if (widget.filePath.startsWith('#network/')) {
      return _buildNetworkThumbnail(isVideo: true);
    }
    return LazyVideoThumbnail(
      videoPath: widget.filePath,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      showLoadingIndicator: widget.showLoadingIndicator,
      onThumbnailGenerated: (_) => widget.onThumbnailLoaded?.call(),
      onError: (_) {},
      fallbackBuilder: () => _buildFallbackWidget(),
    );
  }

  Widget _buildImageThumbnail() {
    if (widget.filePath.startsWith('#network/')) {
      return _buildNetworkThumbnail();
    }
    return ThumbnailImage(
      key: ValueKey('photo-${widget.filePath}-$_thumbnailVersion'),
      image: ResizeImage(
        FileImage(File(widget.filePath)),
        width: 512,
        allowUpscaling: false,
        policy: ResizeImagePolicy.fit,
      ),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      showLoadingIndicator: widget.showLoadingIndicator,
      onReady: widget.onThumbnailLoaded,
    );
  }

  Widget _buildNetworkThumbnail({bool isVideo = false}) {
    final cached =
        _networkThumbnailPath ?? _cache.getCachedThumbnailPath(widget.filePath);
    if (cached == null) {
      return ThumbnailPlaceholder(
        isVideo: isVideo,
        visible: widget.showLoadingIndicator,
      );
    }
    return ThumbnailImage(
      key: ValueKey('network-${widget.filePath}-$cached-$_thumbnailVersion'),
      image: FileImage(File(cached)),
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      isVideo: isVideo,
      showLoadingIndicator: widget.showLoadingIndicator,
      onReady: widget.onThumbnailLoaded,
    );
  }

  Widget _buildFallbackWidget() {
    if (widget.isVideo || widget.isImage) {
      return ThumbnailPlaceholder(isVideo: widget.isVideo, failed: true);
    }
    return widget.fallbackBuilder?.call() ??
        const Center(child: Icon(PhosphorIconsLight.file, color: Colors.grey));
  }
}
