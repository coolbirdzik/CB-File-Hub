import 'dart:async';
import 'dart:io';
import 'package:cb_file_manager/utils/app_logger.dart';

/// Event types for file system changes
enum FileChangeType {
  create,
  modify,
  delete,
  move,
}

/// Represents a file system change event
class FileChangeEvent {
  final String path;
  final FileChangeType type;
  final bool isDirectory;

  FileChangeEvent({
    required this.path,
    required this.type,
    required this.isDirectory,
  });

  @override
  String toString() =>
      'FileChangeEvent(path: $path, type: $type, isDirectory: $isDirectory)';
}

/// Service to watch directory changes and notify listeners
///
/// This service provides a way to monitor file system changes in a directory
/// and automatically refresh the UI when changes occur.
class DirectoryWatcherService {
  static DirectoryWatcherService? _instance;
  static DirectoryWatcherService get instance =>
      _instance ??= DirectoryWatcherService._();

  DirectoryWatcherService._();

  // Current directory being watched
  String? _currentWatchPath;

  // Stream subscription for the directory watcher
  StreamSubscription<FileSystemEvent>? _watchSubscription;

  // Debounce timer to avoid too many refresh calls
  Timer? _debounceTimer;

  // Duration to debounce file system events
  static const Duration _debounceDuration = Duration(milliseconds: 500);

  // Stream controller for broadcasting file change events
  final _changeController = StreamController<FileChangeEvent>.broadcast();

  // Stream controller for directory refresh notifications
  final _refreshController = StreamController<String>.broadcast();

  // Batch of pending events to process
  final Set<String> _pendingEvents = {};
  final Map<String, DateTime> _suppressedRefreshUntil = {};

  /// Stream of file change events
  Stream<FileChangeEvent> get onFileChanged => _changeController.stream;

  /// Stream of directory refresh notifications
  /// This is the main stream that BLoC should listen to for auto-refresh
  Stream<String> get onDirectoryRefresh => _refreshController.stream;

  /// Start watching a directory for changes
  ///
  /// [path] - The directory path to watch
  ///
  /// Note: We intentionally do NOT use recursive watching for several reasons:
  /// 1. Performance: Recursive watching is expensive on all platforms
  ///    - Windows: Uses ReadDirectoryChangesW which can be slow for deep trees
  ///    - macOS: FSEvents has overhead for recursive monitoring
  ///    - Linux: inotify requires adding watches for each subdirectory
  ///    - Android: Limited file system notification support
  /// 2. Battery/Resource: Watching only current directory saves resources
  /// 3. UX: Users only need to see changes in the folder they're viewing
  Future<void> startWatching(String path) async {
    // Don't restart if already watching the same path
    if (_currentWatchPath == path && _watchSubscription != null) {
      return;
    }

    // Stop any existing watcher FIRST — synchronous, cancels the native handle.
    await stopWatching();

    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        AppLogger.warning(
            'DirectoryWatcherService: Directory does not exist: $path');
        return;
      }

      // Set _currentWatchPath only AFTER the directory is confirmed to exist.
      // This prevents a stale-path being set when the watch below fails due to
      // a race with another test's teardown deleting the directory.
      _currentWatchPath = path;

      // Start watching the directory (non-recursive).
      // On Windows, directory.watch() uses ReadDirectoryChangesW which acquires
      // a kernel handle immediately. If the directory is deleted concurrently
      // (e.g. another E2E test's teardown deleting the directory), this throws a
      // synchronous SocketException. The onError callback handles this silently.
      _watchSubscription = directory.watch(recursive: false).listen(
        _handleFileSystemEvent,
        onError: (Object error) {
          // Silently absorb — the watcher will recover on the next navigation.
          stopWatching();
        },
        cancelOnError: false,
      );

      AppLogger.info(
          'DirectoryWatcherService: Started watching $path (non-recursive)');
    } catch (e) {
      AppLogger.error('DirectoryWatcherService: Failed to start watching $path',
          error: e);
    }
  }

  /// Handle file system events
  void _handleFileSystemEvent(FileSystemEvent event) {
    // Ignore temporary files and hidden files
    final fileName = event.path.split(Platform.pathSeparator).last;
    if (fileName.startsWith('.') ||
        fileName.endsWith('.tmp') ||
        fileName.endsWith('.temp') ||
        fileName.contains('~')) {
      return;
    }

    // Map the event type
    FileChangeType changeType;
    switch (event.type) {
      case FileSystemEvent.create:
        changeType = FileChangeType.create;
        break;
      case FileSystemEvent.modify:
        changeType = FileChangeType.modify;
        break;
      case FileSystemEvent.delete:
        changeType = FileChangeType.delete;
        break;
      case FileSystemEvent.move:
        changeType = FileChangeType.move;
        break;
      default:
        changeType = FileChangeType.modify;
    }

    // Check if it's a directory
    final isDirectory = FileSystemEntity.isDirectorySync(event.path);

    // Create and emit the event
    final changeEvent = FileChangeEvent(
      path: event.path,
      type: changeType,
      isDirectory: isDirectory,
    );

    _changeController.add(changeEvent);

    // Add to pending events for batched refresh
    _pendingEvents.add(event.path);

    // Debounce the refresh notification
    _debounceRefresh();
  }

  /// Debounce refresh notifications to avoid excessive UI updates
  void _debounceRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      if (_pendingEvents.isNotEmpty && _currentWatchPath != null) {
        final suppressedUntil = _suppressedRefreshUntil[_currentWatchPath!];
        if (suppressedUntil != null &&
            suppressedUntil.isAfter(DateTime.now())) {
          AppLogger.info(
              'DirectoryWatcherService: Suppressed refresh for $_currentWatchPath');
          _pendingEvents.clear();
          return;
        }

        _suppressedRefreshUntil.remove(_currentWatchPath!);
        AppLogger.info(
            'DirectoryWatcherService: Triggering refresh for $_currentWatchPath (${_pendingEvents.length} changes)');
        _refreshController.add(_currentWatchPath!);
        _pendingEvents.clear();
      }
    });
  }

  /// Stop watching the current directory.
  ///
  /// This is a synchronous cancellation of the native OS handle (ReadDirectoryChangesW
  /// on Windows). No I/O is performed — the handle is closed immediately.
  Future<void> stopWatching() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;

    await _watchSubscription?.cancel();
    _watchSubscription = null;

    final previousPath = _currentWatchPath;
    _currentWatchPath = null;
    _pendingEvents.clear();
    _suppressedRefreshUntil.clear();

    if (previousPath != null) {
      AppLogger.info(
          'DirectoryWatcherService: Stopped watching $previousPath');
    }
  }

  /// Get the currently watched path
  String? get currentWatchPath => _currentWatchPath;

  /// Check if currently watching a directory
  bool get isWatching => _watchSubscription != null;

  /// Suppress auto-refresh notifications for a specific path temporarily.
  void suppressRefreshForPath(
    String path, {
    Duration duration = const Duration(seconds: 2),
  }) {
    _suppressedRefreshUntil[path] = DateTime.now().add(duration);
  }

  /// Force a manual refresh notification
  void forceRefresh() {
    if (_currentWatchPath != null) {
      _refreshController.add(_currentWatchPath!);
    }
  }

  /// Dispose the service
  void dispose() {
    stopWatching();
    _changeController.close();
    _refreshController.close();
  }
}
