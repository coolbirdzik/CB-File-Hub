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
    _thumbnailPaths[path] = thumbnailPath;
    _lastAccessTime[path] = DateTime.now();
    _cleanupCacheIfNeeded();

    // Notify all listening widgets that a new thumbnail is ready
    _thumbnailReadyController.add(path);
  }

  bool isGeneratingThumbnail(String path) =>
      _generatingThumbnails.contains(path);
  void markGeneratingThumbnail(String path) => _generatingThumbnails.add(path);
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
  // and CPU with the listing work. Call [setListingReady(true)] after the
  // file list is fully loaded and sorted, and [setListingReady(false)] when
  // navigating to a new folder / starting a new scan.
  static bool _listingReady = true;
  static final List<VoidCallback> _pendingAfterReady = [];

  /// Whether the file listing is complete and thumbnails can start loading.
  static bool get isListingReady => _listingReady;

  /// Register a callback to run when the listing becomes ready.
  /// Used by album tiles that live outside [_ThumbnailLoaderState].
  static void runAfterReady(VoidCallback callback) {
    if (_listingReady) {
      callback();
    } else {
      _pendingAfterReady.add(callback);
    }
  }

  /// Signal whether the file listing is complete.
  /// When [ready] becomes true, all deferred thumbnail loads are flushed.
  static void setListingReady(bool ready) {
    _listingReady = ready;
    if (ready && _pendingAfterReady.isNotEmpty) {
      // Drain the deferred queue on the next microtask so setState from
      // the BLoC emit has finished first.
      final callbacks = List<VoidCallback>.from(_pendingAfterReady);
      _pendingAfterReady.clear();
      Future.microtask(() {
        for (final cb in callbacks) {
          cb();
        }
      });
    }
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

  /// Clear the file-exists cache. Call when navigating to a new directory
  /// so stale entries from previous folders don't persist.
  static void clearFileExistsCache() {
    _ThumbnailLoaderState.clearFileExistsCache();
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
  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _hasErrorNotifier = ValueNotifier<bool>(false);
  StreamSubscription? _thumbnailReadySubscription;
  bool _widgetMounted = true;
  Timer? _loadTimer;
  Timer? _delayedLoadTimer;
  Timer? _refreshTimer;
  Timer? _visibilityDebounceTimer;
  String? _networkThumbnailPath; // Store the generated thumbnail path
  bool _isScrollingFast = false; // Track if user is scrolling fast
  final int _thumbnailVersion = 0; // Track thumbnail version to force rebuild

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
  // `file.exists()` is an OS syscall. Caching results avoids calling it for
  // every item that becomes visible during scroll.
  static final Map<String, bool> _fileExistsCache = {};

  static Future<bool> _cachedFileExists(String path) async {
    final cached = _fileExistsCache[path];
    if (cached != null) return cached;
    bool exists = false;
    try {
      exists = !path.startsWith('#') && await File(path).exists();
    } catch (_) {}
    _fileExistsCache[path] = exists;
    return exists;
  }

  // Clear file-exists cache on directory navigation so stale entries don't
  // accumulate across multiple folder visits.
  static void clearFileExistsCache() {
    _fileExistsCache.clear();
  }

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
    _isLoadingNotifier.addListener(_handleLoadingChanged);

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
          _isLoadingNotifier.value = false;
          _hasErrorNotifier.value = false;

          if (widget.onThumbnailLoaded != null) {
            widget.onThumbnailLoaded!();
          }
        }
      }
    });

    // Check cache first - only use cached result, don't trigger load
    // Actual loading is deferred to VisibilityDetector to avoid blocking scroll
    final cachedPath = _cache.getCachedThumbnailPath(widget.filePath);
    if (cachedPath != null) {
      _networkThumbnailPath = cachedPath;
      _isLoadingNotifier.value = false;
      _hasErrorNotifier.value = false;
    }
    // For local image files, ResizeImage handles everything via Flutter's
    // ImageCache - no PhotoThumbnailHelper lookup needed here.
    // For network files, VisibilityDetector will trigger _loadThumbnail.
    _handleLoadingChanged();
  }

  // Scroll velocity changes are handled by the static _onGlobalScrollVelocityChanged
  // listener — no per-instance listener needed.

  void _scheduleLoad() {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(milliseconds: 50), () {
      // Reduced delay
      if (mounted) {
        _loadThumbnail();
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
    if (_loadingQueue.isEmpty) return;

    _isProcessingQueue = true;

    // The SplayTreeMap first key is always the lowest (highest priority) entry.
    final firstKey = _loadingQueue.firstKey()!;
    _loadingQueue.remove(firstKey);
    _currentLoads++;

    _isProcessingQueue = false;

    // Continue processing if more items pending.
    if (_loadingQueue.isNotEmpty && _currentLoads < maxConcurrentLoads) {
      Timer(const Duration(milliseconds: 50), _processLoadingQueue);
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
      _networkThumbnailPath = null; // Reset thumbnail path
      _loadThumbnail(); // Load immediately
    }
  }

  void _invalidateThumbnail() {
    _isLoadingNotifier.value = true;
    _hasErrorNotifier.value = false;
    _networkThumbnailPath = null;
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
    _isLoadingNotifier.removeListener(_handleLoadingChanged);
    _isLoadingNotifier.dispose();
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

  // Tránh tải lại thumbnail không cần thiết
  bool _shouldSkipReload(String? path, String? previousPath) {
    if (path == previousPath) return true;
    if (path == null || previousPath == null) return false;

    // Nếu đã là network path thì không reload nếu phần phía sau giống nhau
    // (tránh reload lại khi chỉ có giao thức thay đổi)
    if (path.startsWith('#network/') && previousPath.startsWith('#network/')) {
      final pathSegments = path.split('/');
      final previousSegments = previousPath.split('/');

      // Check if base paths (without protocol) match
      if (pathSegments.length > 3 && previousSegments.length > 3) {
        final basePath = pathSegments.sublist(3).join('/');
        final previousBasePath = previousSegments.sublist(3).join('/');
        if (basePath == previousBasePath) return true;
      }
    }

    return false;
  }

  void _loadThumbnail() async {
    if (!_widgetMounted) return;

    // Wait until the parent file list is fully loaded before starting
    // thumbnail work. This prevents thumbnail generation from competing
    // with directory scanning / sorting for I/O and CPU time.
    if (!ThumbnailLoader._listingReady) {
      ThumbnailLoader._pendingAfterReady.add(() {
        if (_widgetMounted && mounted) _loadThumbnail();
      });
      return;
    }

    final path = widget.filePath;
    final prevPath = _networkThumbnailPath;

    if (_shouldSkipReload(path, prevPath)) {
      return; // Avoid unnecessary reloads
    }

    // Check retry limits and backoff
    final now = DateTime.now();
    final lastAttempt = _lastAttemptTime[path];
    final failedCount = _failedAttempts[path] ?? 0;

    // Skip if we've exceeded max retries
    if (failedCount >= _maxRetries) {
      _hasErrorNotifier.value = true;
      _isLoadingNotifier.value = false;
      return;
    }

    // Skip if we tried too recently (exponential backoff)
    if (lastAttempt != null) {
      final backoffDelay = Duration(
        seconds: _retryBackoff.inSeconds * (failedCount + 1),
      );
      if (now.difference(lastAttempt) < backoffDelay) {
        return;
      }
    }

    // Đánh dấu đang tải - cập nhật ValueNotifier trực tiếp, không dùng setState
    // để tránh rebuild widget không cần thiết trước khi bắt đầu async work.
    _isLoadingNotifier.value = true;
    _hasErrorNotifier.value = false;

    // Track this attempt
    _lastAttemptTime[path] = now;

    try {
      if (path.isEmpty) {
        _hasErrorNotifier.value = true;
        _failedAttempts[path] = failedCount + 1;
        return;
      }

      // First try file directly if it exists locally.
      // Use cached result to avoid an OS syscall per visible item during scroll.
      final bool fileExists = await _cachedFileExists(path);

      String? thumbPath;

      // Priority processing for visible thumbnails
      if (path.startsWith('#network/')) {
        NetworkThumbnailHelper().markVisible(path);
      }

      if (fileExists) {
        if (widget.isVideo) {
          try {
            // NOTE: do NOT use isPriority: true here.
            // Priority is now determined by display index (sorted position in UI),
            // set via updateDisplayIndexMap(). Using isPriority: true would override
            // the display-order priority with file-system order, causing the
            // "loads bottom-of-list thumbnails first" bug.
            thumbPath = await VideoThumbnailHelper.getThumbnail(
              path,
              isPriority: false,
              forceRegenerate: false,
            );
          } catch (e) {
            // Video thumbnail generation failed
          }
        } else if (widget.isImage) {
          // Local images are handled entirely by ResizeImage in
          // _buildImageThumbnail().  No PhotoThumbnailHelper needed.
          thumbPath = null; // no-op: ResizeImage widget handles display
        }
      } else if (path.startsWith('#network/')) {
        // For network files (SMB, FTP, etc)
        final thumbnailHelper = NetworkThumbnailHelper();
        // Reduce work on mobile and limit concurrency
        final bool isMobile = Platform.isAndroid || Platform.isIOS;
        final int genSize = isMobile ? 128 : 256;
        final int limit = isMobile ? 2 : _maxActiveLoaders;
        if (_activeLoaders >= limit) {
          // Back off briefly and retry via scheduler
          await Future.delayed(const Duration(milliseconds: 120));
        }
        if (_activeLoaders >= limit) {
          _scheduleLoad();
          return;
        }
        _activeLoaders++;
        try {
          thumbPath = await thumbnailHelper.generateThumbnail(
            path,
            size: genSize,
          );
        } finally {
          _activeLoaders--;
        }
      }

      if (!_widgetMounted) return;

      if (thumbPath != null) {
        // Reset failed count on success
        _failedAttempts.remove(path);
        setState(() {
          _networkThumbnailPath = thumbPath;
          _isLoadingNotifier.value = false;
        });
      } else if (widget.isImage && !path.startsWith('#')) {
        // Local images: thumbPath=null is expected — ResizeImage handles
        // display natively.  Do NOT mark as error or increment failedAttempts.
        _isLoadingNotifier.value = false;
      } else {
        _failedAttempts[path] = failedCount + 1;
        _hasErrorNotifier.value = true;
      }
    } catch (e) {
      if (!_widgetMounted) return;
      _failedAttempts[path] = failedCount + 1;
      _hasErrorNotifier.value = true;
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

              // Only trigger load for network/video files. Local images
              // are displayed via ResizeImage which manages its own
              // loading lifecycle — no _loadThumbnail needed.
              final bool needsExplicitLoad =
                  widget.filePath.startsWith('#') || widget.isVideo;
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

              // Use a separate ValueListenableBuilder only for loading state
              // to minimize rebuilds when only loading state changes
              // Directly show content - no skeleton overlay to avoid
              // setState spam and shimmer animation overhead during scrolling
              return RepaintBoundary(child: _buildThumbnailContent());
            },
          ),
        ),
      ),
    );
  }

  void _handleLoadingChanged() {
    // No-op: removed setState-based overlay toggling that caused
    // excessive rebuilds during scrolling. The ValueListenableBuilder
    // handles loading state changes without needing setState.
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

  // Thumbnails are small enough that low quality is sufficient
  // Removed _markScrolling() which was calling setState() on every scroll frame
  // causing massive rebuild cascade across all visible widgets
  static const FilterQuality _thumbnailFilterQuality = FilterQuality.low;

  Widget _buildVideoThumbnail() {
    // For SMB videos, we need special handling
    if (widget.filePath.toLowerCase().startsWith('#network/smb/')) {
      // Check if we have a cached thumbnail path
      final cachedPath = _cache.getCachedThumbnailPath(widget.filePath);
      final thumbnailPath = _networkThumbnailPath ?? cachedPath;

      if (thumbnailPath != null) {
        // We have a thumbnail, display it
        // PERFORMANCE: Use adaptive filter quality based on scrolling state
        return Image.file(
          File(thumbnailPath),
          excludeFromSemantics: true, // decorative, see lazy_video_thumbnail
          key: ValueKey(
            'thumb-img-${widget.filePath}-${thumbnailPath.hashCode}-$_thumbnailVersion',
          ),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          filterQuality: _thumbnailFilterQuality,
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_widgetMounted) {
                _hasErrorNotifier.value = true;
              }
            });
            return _buildFallbackWidget();
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_widgetMounted) {
                  _isLoadingNotifier.value = false;
                  if (widget.onThumbnailLoaded != null) {
                    widget.onThumbnailLoaded!();
                  }
                }
              });
            }
            // Compute play icon size proportional to thumbnail so it
            // doesn't overflow small containers (e.g. 20x20 Miller columns).
            final double minDim = widget.width < widget.height
                ? widget.width
                : widget.height;
            final double playSize = minDim == double.infinity
                ? 32
                : (minDim * 0.7).clamp(12.0, 32.0);
            return Stack(
              fit: StackFit.expand,
              children: [
                child,
                // Add video play icon overlay
                Center(
                  child: Icon(
                    PhosphorIconsLight.playCircle,
                    color: Colors.white,
                    size: playSize,
                  ),
                ),
              ],
            );
          },
        );
      }

      // No thumbnail yet, try to generate one
      if (!_cache.isGeneratingThumbnail(widget.filePath)) {
        _cache.markGeneratingThumbnail(widget.filePath);
        final bool isMobile = Platform.isAndroid || Platform.isIOS;
        final int limit = isMobile ? 2 : _maxActiveLoaders;
        if (_activeLoaders >= limit) {
          _cache.markThumbnailGenerated(widget.filePath);
          _scheduleLoad();
          return _buildFallbackWidget();
        }
        _activeLoaders++;

        // Increment pending thumbnail count only when actually starting
        ThumbnailLoader.pendingThumbnailCount++;
        ThumbnailLoader._pendingTasksController.add(
          ThumbnailLoader.pendingThumbnailCount,
        );

        // Use NetworkThumbnailHelper to generate the thumbnail
        final int genSize = (Platform.isAndroid || Platform.isIOS) ? 128 : 256;
        NetworkThumbnailHelper()
            .generateThumbnail(widget.filePath, size: genSize)
            .timeout(
              const Duration(seconds: 30),
            ) // Longer timeout for 4K videos
            .then((path) {
              if (_widgetMounted && path != null) {
                setState(() {
                  _networkThumbnailPath = path;
                  _cache.cacheThumbnailPath(widget.filePath, path);
                });
                _isLoadingNotifier.value = false;
                if (widget.onThumbnailLoaded != null) {
                  widget.onThumbnailLoaded!();
                }
              } else {
                _isLoadingNotifier.value = false;
              }
              _cache.markThumbnailGenerated(widget.filePath);
              _activeLoaders--;

              // Decrement pending thumbnail count
              ThumbnailLoader.pendingThumbnailCount--;
              ThumbnailLoader._pendingTasksController.add(
                ThumbnailLoader.pendingThumbnailCount,
              );
            })
            .catchError((error) {
              if (_widgetMounted) {
                _isLoadingNotifier.value = false;
                _hasErrorNotifier.value = true;
              }
              _cache.markThumbnailGenerated(widget.filePath);
              _activeLoaders--;

              // Decrement pending thumbnail count
              ThumbnailLoader.pendingThumbnailCount--;
              ThumbnailLoader._pendingTasksController.add(
                ThumbnailLoader.pendingThumbnailCount,
              );
            });
      }

      // Return fallback while loading
      return _buildFallbackWidget();
    }

    // For local videos, use LazyVideoThumbnail
    return LazyVideoThumbnail(
      videoPath: widget.filePath,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      onThumbnailGenerated: (path) {
        if (_widgetMounted) {
          _isLoadingNotifier.value = false;
          if (widget.onThumbnailLoaded != null) {
            widget.onThumbnailLoaded!();
          }
        }
      },
      onError: (error) {
        if (_widgetMounted) {
          // Always set loading to false on error
          _isLoadingNotifier.value = false;
          _hasErrorNotifier.value = true;

          // Only log errors if they're not related to BackgroundIsolateBinaryMessenger
          if (error is! String ||
              !error.contains('BackgroundIsolateBinaryMessenger')) {}
        }
      },
      fallbackBuilder: () => _buildFallbackWidget(),
    );
  }

  Widget _buildImageThumbnail() {
    // For network files, use the generated thumbnail path if available
    if (widget.filePath.startsWith('#network/')) {
      // Check cache first
      final cachedPath = _cache.getCachedThumbnailPath(widget.filePath);
      final thumbnailPath = _networkThumbnailPath ?? cachedPath;

      if (thumbnailPath != null) {
        // Cache the path if not already cached
        if (cachedPath == null) {
          _cache.cacheThumbnailPath(widget.filePath, thumbnailPath);
        }

        // PERFORMANCE: Use adaptive filter quality based on scrolling state
        return Image.file(
          File(thumbnailPath),
          excludeFromSemantics: true, // decorative, see lazy_video_thumbnail
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          filterQuality: _thumbnailFilterQuality,
          cacheWidth: widget.width.isInfinite ? null : widget.width.toInt(),
          cacheHeight: widget.height.isInfinite ? null : widget.height.toInt(),
          errorBuilder: (context, error, stackTrace) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_widgetMounted) {
                _hasErrorNotifier.value = true;
              }
            });
            return _buildFallbackWidget();
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_widgetMounted) {
                  _isLoadingNotifier.value = false;
                  if (widget.onThumbnailLoaded != null) {
                    widget.onThumbnailLoaded!();
                  }
                }
              });
            }
            return child;
          },
        );
      } else {
        // No thumbnail available yet, show fallback
        // Trigger thumbnail generation if not already in progress
        if (!_cache.isGeneratingThumbnail(widget.filePath)) {
          _cache.markGeneratingThumbnail(widget.filePath);
          final bool isMobile = Platform.isAndroid || Platform.isIOS;
          final int limit = isMobile ? 2 : _maxActiveLoaders;
          if (_activeLoaders >= limit) {
            _cache.markThumbnailGenerated(widget.filePath);
            _scheduleLoad();
            return _buildFallbackWidget();
          }
          _activeLoaders++;

          // Increment pending thumbnail count only when actually starting
          ThumbnailLoader.pendingThumbnailCount++;
          ThumbnailLoader._pendingTasksController.add(
            ThumbnailLoader.pendingThumbnailCount,
          );

          final int genSize = (Platform.isAndroid || Platform.isIOS)
              ? 128
              : 256;
          NetworkThumbnailHelper()
              .generateThumbnail(widget.filePath, size: genSize)
              .timeout(const Duration(seconds: 6))
              .then((path) {
                if (_widgetMounted && path != null) {
                  setState(() {
                    _networkThumbnailPath = path;
                    _cache.cacheThumbnailPath(widget.filePath, path);
                  });
                  _isLoadingNotifier.value = false;
                  if (widget.onThumbnailLoaded != null) {
                    widget.onThumbnailLoaded!();
                  }
                } else {
                  _isLoadingNotifier.value = false;
                }
                _cache.markThumbnailGenerated(widget.filePath);
                _activeLoaders--;

                // Decrement pending thumbnail count
                ThumbnailLoader.pendingThumbnailCount--;
                ThumbnailLoader._pendingTasksController.add(
                  ThumbnailLoader.pendingThumbnailCount,
                );
              })
              .catchError((error) {
                // Check if this is a skip exception (backoff)
                if (error.toString().contains('ThumbnailSkippedException')) {
                  // Don't update error state for skipped thumbnails
                  if (_widgetMounted) {
                    _isLoadingNotifier.value = false;
                  }
                  _cache.markThumbnailGenerated(widget.filePath);
                  _activeLoaders--;

                  // Decrement counter since we incremented it at the start
                  ThumbnailLoader.pendingThumbnailCount--;
                  ThumbnailLoader._pendingTasksController.add(
                    ThumbnailLoader.pendingThumbnailCount,
                  );
                  return; // Don't log or update error state
                }

                if (_widgetMounted) {
                  _isLoadingNotifier.value = false;
                  _hasErrorNotifier.value = true;
                }
                _cache.markThumbnailGenerated(widget.filePath);
                _activeLoaders--;

                // Decrement pending thumbnail count
                ThumbnailLoader.pendingThumbnailCount--;
                ThumbnailLoader._pendingTasksController.add(
                  ThumbnailLoader.pendingThumbnailCount,
                );

                // Only log errors if they're not related to BackgroundIsolateBinaryMessenger
                if (error is! String ||
                    !error.contains('BackgroundIsolateBinaryMessenger')) {}
              });
        }

        return _buildFallbackWidget();
      }
    }

    // For LOCAL image files: use Flutter's native ResizeImage provider.
    //
    // WHY: PhotoThumbnailHelper uses the pure-Dart 'image' package which is
    // 10-20× slower than the platform JPEG codec (Skia/libjpeg).  ResizeImage
    // asks the platform codec to downsample at decode time (JPEG's 1/2 · 1/4 ·
    // 1/8 DCT scaling), so a 12 MP JPEG renders at 512 px in ~10-30 ms instead
    // of 200-500 ms.  The decoded bitmap is stored in Flutter's ImageCache
    // (up to 400 MB on desktop) so repeated views are instant - no disk I/O.
    //
    // For network files the old path is preserved below (they go through
    // NetworkThumbnailHelper / VideoThumbnailHelper as before).
    if (!widget.filePath.startsWith('#')) {
      return Image(
        excludeFromSemantics: true, // decorative, see lazy_video_thumbnail
        image: ResizeImage(
          FileImage(File(widget.filePath)),
          width: 512,
          allowUpscaling: false,
          policy: ResizeImagePolicy.fit,
        ),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        filterQuality: _thumbnailFilterQuality,
        // Show placeholder while decoding; swap to image when ready.
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            // Decode finished - report loaded.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_widgetMounted) {
                _isLoadingNotifier.value = false;
                widget.onThumbnailLoaded?.call();
              }
            });
            return child;
          }
          return _buildLoadingPlaceholderForThumbnail();
        },
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_widgetMounted) _hasErrorNotifier.value = true;
          });
          return _buildFallbackWidget();
        },
      );
    }

    // ── Network image thumbnails (old path) ───────────────────────────────────────
    final bool hasCachedThumbnail =
        _networkThumbnailPath != null &&
        _networkThumbnailPath != widget.filePath;

    if (!hasCachedThumbnail) {
      // Thumbnail not yet generated - show placeholder skeleton.
      // Generation is already running in a background isolate (kicked off by
      // _loadThumbnail); when done, setState will swap in the JPEG.
      return _buildLoadingPlaceholderForThumbnail();
    }

    final displayPath = _networkThumbnailPath!;
    return Image.file(
      File(displayPath),
      excludeFromSemantics: true, // decorative, see lazy_video_thumbnail
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: _thumbnailFilterQuality,
      // Thumbnail was already generated at 512 px; decode at widget size.
      cacheWidth: widget.width.isInfinite ? null : widget.width.ceil(),
      cacheHeight: widget.height.isInfinite ? null : widget.height.ceil(),
      errorBuilder: (context, error, stackTrace) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_widgetMounted) {
            _hasErrorNotifier.value = true;
          }
        });
        return _buildFallbackWidget();
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_widgetMounted) {
              _isLoadingNotifier.value = false;
              if (widget.onThumbnailLoaded != null) {
                widget.onThumbnailLoaded!();
              }
            }
          });
        }
        return child;
      },
    );
  }

  /// Lightweight placeholder shown while a photo thumbnail is being generated
  /// in a background isolate.  Uses a simple shimmer-free grey surface -
  /// no async work, no Image.file, no I/O.
  Widget _buildLoadingPlaceholderForThumbnail() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        return Container(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          child: Center(
            child: Icon(
              PhosphorIconsLight.image,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallbackWidget() {
    if (widget.fallbackBuilder != null) {
      return widget.fallbackBuilder!();
    }

    if (widget.isVideo) {
      return Container(
        color: Colors.black12,
        child: const Center(
          child: Icon(
            PhosphorIconsLight.videoCamera,
            size: 36,
            color: Colors.red,
          ),
        ),
      );
    } else if (widget.isImage) {
      return Container(
        color: Colors.black12,
        child: const Center(
          child: Icon(PhosphorIconsLight.image, size: 36, color: Colors.blue),
        ),
      );
    } else {
      return Container(
        color: Colors.black12,
        child: const Center(
          child: Icon(PhosphorIconsLight.file, size: 36, color: Colors.grey),
        ),
      );
    }
  }
}
