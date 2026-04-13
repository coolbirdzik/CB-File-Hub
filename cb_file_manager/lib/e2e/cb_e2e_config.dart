import 'dart:async';
import '../core/service_locator.dart';
import '../models/database/database_manager.dart';
import '../services/directory_watcher_service.dart';
import '../services/windowing/window_startup_payload.dart';

/// Enabled when running integration tests with `--dart-define=CB_E2E=true`.
const bool kCbE2E = bool.fromEnvironment('CB_E2E', defaultValue: false);

/// Skips production-only startup work during E2E unless explicitly disabled.
const bool kCbE2EFast =
    kCbE2E && bool.fromEnvironment('CB_E2E_FAST', defaultValue: true);

/// Captures a screenshot after every wrapped E2E action when enabled.
const bool kCbE2EFullScreenshots =
    bool.fromEnvironment('CB_E2E_FULL_SCREENSHOTS', defaultValue: false);

/// Serializes E2E test teardown so the next test never starts [runCbFileApp]
/// before the previous test's teardown is complete.
///
/// Flutter's `addTearDown` runs AFTER the test body returns but BEFORE the next
/// test's body runs. However, it is a callback — the framework does not await it.
/// This means the next test can call [runCbFileApp] while the previous test's
/// teardown (particularly `locator.reset()`) is still in-flight.
///
/// Without this semaphore, the following race occurs:
/// 1. Test A finishes → teardown started → `stopWatching()` called (sync)
/// 2. Test B starts → `runCbFileApp()` called → `startWatching(newPath)`
/// 3. Test A teardown: `_deleteDirectorySafe()` runs, deleting old directory
/// 4. Test B watcher: `Directory.watch()` on new directory FAILS because
///    `Directory.watch()` on Windows requires stable handles — and the OS
///    may briefly return "Access is denied" if handle plumbing is unsettled.
///
/// The semaphore is acquired at the START of each test (inside `runCbFileApp`)
/// and released at the END of each test (inside `tearDownCbFileAppForNextE2ETest`).
/// The `await _e2eSemaphore!.future` inside `runCbFileApp` ensures that the
/// new test blocks until the previous test's teardown has fully completed.
Completer<void>? _e2eSemaphore;

/// Set by [integration_test] before [runCbFileApp] when [kCbE2E] is true.
class CbE2EConfig {
  CbE2EConfig._();

  static WindowStartupPayload? startupPayload;

  /// Acquires the E2E serialization semaphore. Must be called at the start of each
  /// test's body (before `runCbFileApp`) to prevent the next test from starting
  /// before this test's teardown is complete.
  static Future<void> acquireE2ESemaphore() async {
    if (!kCbE2E) return;
    // If a previous semaphore exists, await its completion (teardown finished).
    if (_e2eSemaphore != null && !_e2eSemaphore!.isCompleted) {
      await _e2eSemaphore!.future;
    }
    // Create a new completer — the next test will await this.
    _e2eSemaphore = Completer<void>();
  }

  /// Releases the E2E serialization semaphore. Must be called at the END of each
  /// test (inside `tearDownCbFileAppForNextE2ETest`) to unblock the next test.
  static void releaseE2ESemaphore() {
    if (!kCbE2E) return;
    if (_e2eSemaphore != null && !_e2eSemaphore!.isCompleted) {
      _e2eSemaphore!.complete();
    }
    _e2eSemaphore = null;
  }

  static void clear() {
    startupPayload = null;
  }
}

/// Resets [DatabaseManager]'s singleton and [GetIt] so another `testWidgets` can call [runCbFileApp]
/// in the same process (E2E only).
///
/// The ORDER of teardown is critical:
///
/// 1. [DirectoryWatcherService.stopWatching] — stops the native directory watcher
///    BEFORE the temp sandbox directory is deleted. Without this, the watcher
///    receives `SocketException: Access is denied` when the directory disappears
///    while it is still subscribed.
///
/// 2. [locator.reset] — disposes all BLoCs/services that depend on the locator.
///    After this, no more async UI work races with the next [runCbFileApp].
///
/// 3. [releaseE2ESemaphore] — releases the E2E serialization semaphore, unblocking
///    the next test's `acquireE2ESemaphore()` call inside `runCbFileApp`.
///
/// Does **not** close the process-wide SQLite file handle ([SqliteDatabaseProvider] static pool).
/// Closing between tests races async UI/prefs work and the next [runCbFileApp], producing
/// `DatabaseException(error database_closed)` while widgets still call into prefs.
Future<void> tearDownCbFileAppForNextE2ETest() async {
  if (!kCbE2E) return;

  // 1. Stop the directory watcher FIRST — prevents SocketException when
  //    the sandbox directory is deleted shortly after by _deleteDirectorySafe().
  DirectoryWatcherService.instance.stopWatching();

  // 2. Brief pause to let the OS release the native directory handle.
  //    On Windows, Directory.watch() uses ReadDirectoryChangesW which holds
  //    a kernel handle — cancelling the Dart StreamSubscription is synchronous
  //    but the OS handle release is not guaranteed to be instantaneous.
  await Future<void>.delayed(const Duration(milliseconds: 100));

  DatabaseManager.resetSingletonForE2ETest();
  try {
    await locator.reset(dispose: true);
  } catch (_) {}

  // 3. Release the E2E serialization semaphore — allows the next test to proceed.
  CbE2EConfig.releaseE2ESemaphore();
}
