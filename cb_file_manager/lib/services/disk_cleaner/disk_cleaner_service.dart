import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart' as win32;

import '../../helpers/core/filesystem_utils.dart';
import '../../helpers/core/io_extensions.dart';
import '../../helpers/files/trash_manager.dart';
import '../app_insights/app_insights_models.dart';
import '../../utils/app_logger.dart';
import 'cleaner_categories.dart';
import 'cleaner_models.dart';
import 'cleaner_safety.dart';
import 'disk_cleaner_isolate.dart';
import 'disk_tree_node.dart';
import 'full_disk_scan_isolate.dart';
import 'windows_known_folders.dart';

enum DiskCleanerAgentActivityType {
  scanStarted,
  scanProgress,
  scanDone,
  scanFailed
}

class DiskCleanerAgentActivity {
  final DiskCleanerAgentActivityType type;
  final String? ownerTabId;
  final String message;
  final int itemsFound;
  final int bytesFound;
  final String currentPath;
  final ScanReport? report;

  const DiskCleanerAgentActivity({
    required this.type,
    this.ownerTabId,
    this.message = '',
    this.itemsFound = 0,
    this.bytesFound = 0,
    this.currentPath = '',
    this.report,
  });
}

class CleanerScanContext {
  final String ownerTabId;
  final DiskTreeNode root;
  final String? selectedPath;
  final String? chartPath;
  final bool isScanning;
  final AppStorageReport? appStorageReport;
  final String? selectedAppId;
  final bool appInsightsSharedWithAgent;
  final DateTime updatedAt;

  const CleanerScanContext({
    required this.ownerTabId,
    required this.root,
    this.selectedPath,
    this.chartPath,
    this.isScanning = false,
    this.appStorageReport,
    this.selectedAppId,
    this.appInsightsSharedWithAgent = false,
    required this.updatedAt,
  });
}

/// Public façade for the Disk Cleaner skill.
///
/// All scan and clean operations route through this single service so the AI
/// tool layer (`tool_executor.dart`) and the companion UI screen produce
/// identical results from identical code paths.
class DiskCleanerService {
  DiskCleanerService._();

  static final DiskCleanerService instance = DiskCleanerService._();

  final StreamController<DiskCleanerAgentActivity> _agentActivityController =
      StreamController<DiskCleanerAgentActivity>.broadcast();

  Stream<DiskCleanerAgentActivity> get agentActivityStream =>
      _agentActivityController.stream;

  void emitAgentActivity(DiskCleanerAgentActivity activity) {
    _agentActivityController.add(activity);
  }

  /// Pending cleanup items set by the UI when user enters confirm phase.
  /// The AI tool `get_pending_cleanup_review` reads from here.
  List<JunkItem>? pendingCleanupItems;
  int pendingCleanupBytes = 0;

  final Map<String, CleanerScanContext> _cleanerScanContexts = {};

  CleanerScanHandle? _activeScan;

  /// Returns true while a scan is running. Used by callers that want to fail
  /// fast instead of throwing.
  bool get isScanning => _activeScan != null;

  void publishCleanerScanContext({
    required String ownerTabId,
    required DiskTreeNode? root,
    String? selectedPath,
    String? chartPath,
    bool isScanning = false,
    AppStorageReport? appStorageReport,
    String? selectedAppId,
    bool appInsightsSharedWithAgent = false,
  }) {
    if (root == null) {
      _cleanerScanContexts.remove(ownerTabId);
      return;
    }

    _cleanerScanContexts[ownerTabId] = CleanerScanContext(
      ownerTabId: ownerTabId,
      root: root,
      selectedPath: selectedPath,
      chartPath: chartPath,
      isScanning: isScanning,
      appStorageReport: appStorageReport,
      selectedAppId: selectedAppId,
      appInsightsSharedWithAgent: appInsightsSharedWithAgent,
      updatedAt: DateTime.now(),
    );
  }

  CleanerScanContext? getCleanerScanContext({String? ownerTabId}) {
    if (ownerTabId != null && ownerTabId.isNotEmpty) {
      return _cleanerScanContexts[ownerTabId];
    }
    if (_cleanerScanContexts.isEmpty) return null;
    return _cleanerScanContexts.values.reduce(
      (a, b) => a.updatedAt.isAfter(b.updatedAt) ? a : b,
    );
  }

  void clearCleanerScanContext(String ownerTabId) {
    _cleanerScanContexts.remove(ownerTabId);
  }

  /// Lists every category the cleaner knows about.
  ///
  /// On non-Windows platforms returns an empty list — the cleaner is
  /// Windows-only for now.
  List<CleanerCategory> listCategories({bool windowsOnly = true}) {
    if (windowsOnly && !Platform.isWindows) return const [];
    return CleanerCategories.all();
  }

  /// Returns free / total / used info for every Windows fixed drive.
  Future<List<DriveSpace>> getDriveSpace() async {
    if (!Platform.isWindows) return const [];

    final drives = await getAllWindowsDrives();
    final result = <DriveSpace>[];
    for (final dir in drives) {
      final path = dir.path;
      final label = (dir.getProperty('driveLabel') as String?) ?? '';
      final requiresAdmin = dir.requiresAdmin;
      final info = _readDriveSpace(path);
      if (info == null) {
        result.add(DriveSpace(
          path: path,
          label: label,
          totalBytes: 0,
          freeBytes: 0,
          requiresAdmin: requiresAdmin,
        ));
        continue;
      }
      result.add(DriveSpace(
        path: path,
        label: label,
        totalBytes: info.totalBytes,
        freeBytes: info.freeBytes,
        requiresAdmin: requiresAdmin,
      ));
    }
    return result;
  }

  /// Scans the requested categories, awaiting the final report.
  ///
  /// [drivePaths] is currently informational only — junk categories use
  /// per-user environment paths or absolute Windows paths, which target the
  /// system drive regardless of which drives the user "selected". Drive info
  /// is still threaded through so the report and `recycle_bin` rule can
  /// target every drive.
  ///
  /// [categoryIds] empty/null → all categories with `defaultEnabled: true`.
  ///
  /// Throws [StateError] if a scan is already in progress.
  Future<ScanReport> scanJunk({
    required List<String> drivePaths,
    required List<String> categoryIds,
    void Function(ScanProgress)? onProgress,
  }) async {
    final handle = await _beginScan(drivePaths, categoryIds);
    final progressSub =
        onProgress == null ? null : handle.progress.listen(onProgress);
    try {
      final report = await handle.future;
      if (categoryIds.isEmpty || categoryIds.contains('recycle_bin')) {
        final bin = await _scanRecycleBin();
        if (bin.isNotEmpty) {
          final merged =
              Map<String, List<JunkItem>>.from(report.itemsByCategory);
          merged['recycle_bin'] = bin;
          return ScanReport(
            drivesScanned: report.drivesScanned,
            itemsByCategory: merged,
            warnings: report.warnings,
            scannedAt: report.scannedAt,
          );
        }
      }
      return report;
    } finally {
      await progressSub?.cancel();
      _activeScan = null;
    }
  }

  /// Streamed variant for UIs that want progress + final report.
  ///
  /// The returned [CleanerScanController] exposes a progress stream, a
  /// future report, and a cancel method.
  Future<CleanerScanController> scanJunkStream({
    required List<String> drivePaths,
    required List<String> categoryIds,
  }) async {
    final handle = await _beginScan(drivePaths, categoryIds);
    final completer = Completer<ScanReport>();

    handle.future.then((report) async {
      try {
        if (categoryIds.isEmpty || categoryIds.contains('recycle_bin')) {
          final bin = await _scanRecycleBin();
          if (bin.isNotEmpty) {
            final merged =
                Map<String, List<JunkItem>>.from(report.itemsByCategory);
            merged['recycle_bin'] = bin;
            completer.complete(ScanReport(
              drivesScanned: report.drivesScanned,
              itemsByCategory: merged,
              warnings: report.warnings,
              scannedAt: report.scannedAt,
            ));
            return;
          }
        }
        completer.complete(report);
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      } finally {
        _activeScan = null;
      }
    }).catchError((Object e, StackTrace st) {
      if (!completer.isCompleted) completer.completeError(e, st);
      _activeScan = null;
    });

    return CleanerScanController._(
      progress: handle.progress,
      report: completer.future,
      onCancel: () {
        handle.cancel();
        if (!completer.isCompleted) {
          completer.complete(ScanReport(
            drivesScanned: handle.drivesScanned,
            itemsByCategory: const {},
            warnings: const ['cancelled'],
            scannedAt: DateTime.now(),
          ));
        }
        _activeScan = null;
      },
    );
  }

  /// Cancels the in-flight scan, if any.
  void cancelActiveScan() {
    _activeScan?.cancel();
    _activeScan = null;
  }

  /// Deletes the items in [items], routing each through the safety check.
  ///
  /// [permanent] = true uses [File.delete] / [Directory.delete]. Otherwise the
  /// items are moved to the Recycle Bin via [TrashManager]. Recycle Bin items
  /// are always permanently deleted regardless of the flag because they are
  /// already in the Bin.
  /// Public entry: runs the full clean pipeline in a background isolate so
  /// the UI thread is never blocked by FFI preflight, directory expansion,
  /// MethodChannel awaits, or per-item logging. The main isolate only:
  ///  - spawns the worker
  ///  - bridges progress + failure prompts back through SendPort messages
  ///  - awaits the final [CleanReport]
  Future<CleanReport> cleanJunk({
    required List<JunkItem> items,
    required bool permanent,
    void Function(int done, int total, String? currentPath)? onProgress,
    Future<CleanFailureAction> Function(CleanFailureDetails details)?
        onDeleteFailure,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    SendPort? workerSend;
    final completer = Completer<CleanReport>();
    final rootIsolateToken = RootIsolateToken.instance;

    StreamSubscription<dynamic>? messageSub;
    StreamSubscription<dynamic>? errorSub;
    StreamSubscription<dynamic>? exitSub;

    void closePorts() {
      messageSub?.cancel();
      errorSub?.cancel();
      exitSub?.cancel();
      receivePort.close();
      errorPort.close();
      exitPort.close();
    }

    messageSub = receivePort.listen((dynamic msg) async {
      if (msg is SendPort) {
        workerSend = msg;
        return;
      }
      if (msg is _CleanProgressMessage) {
        try {
          onProgress?.call(msg.done, msg.total, msg.currentPath);
        } catch (e, st) {
          AppLogger.warning(
            '[DiskCleaner] onProgress threw: $e',
            stackTrace: st,
          );
        }
        return;
      }
      if (msg is _CleanFailurePrompt) {
        var action = CleanFailureAction.skip;
        if (onDeleteFailure != null) {
          try {
            action = await onDeleteFailure(msg.details);
          } catch (e, st) {
            AppLogger.warning(
              '[DiskCleaner] onDeleteFailure threw: $e',
              stackTrace: st,
            );
          }
        }
        workerSend?.send(_CleanFailureResponse(msg.requestId, action));
        return;
      }
      if (msg is _CleanFinished) {
        if (!completer.isCompleted) {
          completer.complete(msg.report);
        }
        closePorts();
        return;
      }
      if (msg is _CleanFailed) {
        if (!completer.isCompleted) {
          completer.completeError(msg.error, msg.stackTrace);
        }
        closePorts();
        return;
      }
    });

    errorSub = errorPort.listen((dynamic err) {
      if (!completer.isCompleted) {
        completer.completeError(
            err is List && err.length >= 2 ? err[0] : err.toString());
      }
      closePorts();
    });

    exitSub = exitPort.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(StateError(
            '[DiskCleaner] Worker isolate exited before sending result'));
      }
      closePorts();
    });

    await Isolate.spawn<_CleanWorkerArgs>(
      _cleanWorkerEntry,
      _CleanWorkerArgs(
        replyTo: receivePort.sendPort,
        items: items,
        permanent: permanent,
        rootIsolateToken: rootIsolateToken,
      ),
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
      errorsAreFatal: true,
      debugName: 'cb_file_manager.disk_cleaner',
    );

    return completer.future;
  }

  /// In-isolate implementation. Same logic as before, but reachable both
  /// directly (legacy callers in tests) and from the worker entry above.
  Future<CleanReport> _cleanJunkInternal({
    required List<JunkItem> items,
    required bool permanent,
    void Function(int done, int total, String? currentPath)? onProgress,
    Future<CleanFailureAction> Function(CleanFailureDetails details)?
        onDeleteFailure,
  }) async {
    final succeeded = <String>[];
    final failed = <String, String>{};
    final skippedUnsafe = <String>[];
    final skippedInUse = <String>[];
    final skippedByUser = <String>{};
    var skipAllRemainingDeletes = false;
    int freed = 0;

    final trash = TrashManager();
    onProgress?.call(0, 0, null);
    final expandedItems = await _expandDirectoryTargets(
      items,
      onPreparing: (currentPath) {
        // Surface the directory being expanded so the UI can show
        // "Preparing files…" instead of appearing frozen on huge junk
        // folders (e.g. %TEMP% with tens of thousands of children).
        onProgress?.call(0, 0, currentPath);
      },
    );
    final total = expandedItems.length;

    // Filter unsafe paths first and bucket the rest by handling strategy.
    // Bulk operations are batched into a single native IFileOperation call
    // (Windows) which avoids spawning powershell.exe per item — this is the
    // primary cost of the legacy implementation.
    final byPath = <String, JunkItem>{};
    final binItems = <JunkItem>[];
    final bulkItems = <JunkItem>[];

    for (final item in expandedItems) {
      final isBinItem =
          item.isRecycleBinItem || item.categoryId == 'recycle_bin';
      final safeByRule = CleanerPathSafety.isPathSafeToDelete(
        item.path,
        recycleBinItem: isBinItem,
      );
      // Allow paths the user explicitly selected from the disk tree. Keep the
      // stricter allowlist for scanner rules and AI-driven cleanup.
      if (!safeByRule && !item.isUserSelected) {
        skippedUnsafe.add(item.path);
        continue;
      }
      // Deduplicate by path; junk scans can produce the same path under
      // multiple categories.
      if (byPath.containsKey(item.path)) continue;
      byPath[item.path] = item;
      if (isBinItem) {
        binItems.add(item);
      } else {
        bulkItems.add(item);
      }
    }

    int done = skippedUnsafe.length;
    onProgress?.call(done, total, null);

    void recordSuccess(
      JunkItem item, {
      String? actionLabel,
      bool log = true,
    }) {
      succeeded.add(item.path);
      freed += item.sizeBytes;
      if (!log) return;
      AppLogger.info(
        '[DiskCleaner] ${actionLabel ?? (permanent ? "Deleted" : "Moved to Recycle Bin")}: ${item.path}',
      );
    }

    void recordSkippedInUse(
      JunkItem item, {
      String? blockedPath,
      String? actionLabel,
      bool log = true,
    }) {
      skippedInUse.add(item.path);
      if (!log) return;
      AppLogger.warning(
        '[DiskCleaner] Skipped in-use path during ${actionLabel ?? (permanent ? "permanent delete" : "recycle-bin move")}: ${item.path}'
        '${blockedPath != null && blockedPath != item.path ? ' | blocked by: $blockedPath' : ''}',
      );
    }

    void recordSkippedInUseMany(
      List<JunkItem> items, {
      String? actionLabel,
      bool log = true,
    }) {
      if (items.isEmpty) return;
      skippedInUse.addAll(items.map((item) => item.path));
      if (!log) return;
      AppLogger.warning(
        '[DiskCleaner] Skipped ${items.length} in-use item(s) during ${actionLabel ?? (permanent ? "permanent delete" : "recycle-bin move")} | first=${items.first.path}',
      );
    }

    void recordSkippedByUser(
      JunkItem item, {
      required String reason,
      String? actionLabel,
      bool log = true,
    }) {
      skippedByUser.add(item.path);
      if (!log) return;
      AppLogger.warning(
        '[DiskCleaner] Skipped by user during ${actionLabel ?? (permanent ? "permanent delete" : "recycle-bin move")}: ${item.path} | reason: $reason',
      );
    }

    void recordSkippedByUserMany(
      List<JunkItem> items, {
      required String reason,
      String? actionLabel,
      bool log = true,
    }) {
      if (items.isEmpty) return;
      skippedByUser.addAll(items.map((item) => item.path));
      if (!log) return;
      AppLogger.warning(
        '[DiskCleaner] Skipped ${items.length} item(s) by user during ${actionLabel ?? (permanent ? "permanent delete" : "recycle-bin move")} | first=${items.first.path} | reason: $reason',
      );
    }

    Future<bool> retryDeleteSingleItem(JunkItem item) async {
      final paths = [item.path];
      final ok = permanent
          ? await trash.deleteMultiplePermanently(paths, chunkSize: 1)
          : await trash.moveMultipleToTrashBatched(paths, chunkSize: 1);
      return ok.contains(item.path);
    }

    Future<void> resolveFailedItem(
      JunkItem item, {
      String? fallbackReason,
      String? actionLabel,
      bool knownInUse = false,
    }) async {
      var lastReason = fallbackReason;

      while (true) {
        if (skipAllRemainingDeletes) {
          recordSkippedByUser(
            item,
            reason: 'Skipped after user selected Skip all',
            actionLabel: actionLabel,
            log: false,
          );
          return;
        }

        final classification = knownInUse
            ? _DeleteFailureClassification(
                isInUse: true,
                reason: _fileInUseFailure,
                blockedPath: item.path,
              )
            : onDeleteFailure == null
                ? await _classifyDeleteFailure(item.path, permanent)
                : _DeleteFailureClassification(
                    isInUse: false,
                    reason: lastReason ??
                        (permanent
                            ? 'Failed to delete'
                            : 'Failed to move to Recycle Bin'),
                  );
        final effectiveReason =
            classification.isInUse || lastReason == null || lastReason.isEmpty
                ? classification.reason
                : lastReason;

        if (onDeleteFailure == null) {
          if (classification.isInUse) {
            recordSkippedInUse(
              item,
              blockedPath: classification.blockedPath,
              actionLabel: actionLabel,
            );
          } else {
            failed[item.path] = effectiveReason;
            AppLogger.warning(
              '[DiskCleaner] Failed ${actionLabel ?? (permanent ? "delete" : "move to Recycle Bin")}: ${item.path} | reason: $effectiveReason',
            );
          }
          return;
        }

        final action = await onDeleteFailure(CleanFailureDetails(
          item: item,
          reason: effectiveReason,
          isInUse: classification.isInUse,
          blockedPath: classification.blockedPath,
          permanent: permanent,
        ));

        if (action == CleanFailureAction.skip ||
            action == CleanFailureAction.skipAll) {
          if (action == CleanFailureAction.skipAll) {
            skipAllRemainingDeletes = true;
          }
          if (classification.isInUse) {
            recordSkippedInUse(
              item,
              blockedPath: classification.blockedPath,
              actionLabel: actionLabel,
            );
          } else {
            recordSkippedByUser(
              item,
              reason: effectiveReason,
              actionLabel: actionLabel,
            );
          }
          return;
        }

        try {
          AppLogger.info(
            '[DiskCleaner] Retrying ${actionLabel ?? (permanent ? "permanent delete" : "recycle-bin move")}: ${item.path}',
          );
          final retried = await retryDeleteSingleItem(item);
          if (retried) {
            recordSuccess(item, actionLabel: actionLabel);
            return;
          }
          lastReason = permanent
              ? 'Retry failed to delete'
              : 'Retry failed to move to Recycle Bin';
        } catch (e, st) {
          lastReason = '$e';
          AppLogger.error(
            '[DiskCleaner] Exception while retrying ${actionLabel ?? (permanent ? "delete" : "move to Recycle Bin")}: ${item.path}',
            error: e,
            stackTrace: st,
          );
        }
      }
    }

    // 1) Regular files/directories: delete in native batches first. Only
    // paths that actually fail surface a user decision or deeper
    // classification.
    if (bulkItems.isNotEmpty) {
      // A healthy item should participate in a real batch. The previous
      // 4/8/16-item ramp-up repeatedly paid the COM startup cost, and risky
      // extensions were sent through one IFileOperation call per file.
      const maxChunkSize = 64;

      var start = 0;
      while (start < bulkItems.length) {
        // Always yield to the event loop at the top of each chunk so the
        // UI can repaint and process the close-dialog frame even when the
        // cleaner is in the middle of a large bulk-skip pass.
        await Future<void>.delayed(Duration.zero);
        final chunkSize = skipAllRemainingDeletes ? 512 : maxChunkSize;
        final end = (start + chunkSize < bulkItems.length)
            ? start + chunkSize
            : bulkItems.length;
        final chunk = bulkItems.sublist(start, end);
        final batchedDeletes = <JunkItem>[];
        final autoSkippedInUse = <JunkItem>[];

        if (!skipAllRemainingDeletes) {
          AppLogger.info(
            '[DiskCleaner] Preparing ${permanent ? "permanent delete" : "recycle-bin move"} batch | range=${start + 1}-$end/$total | first=${chunk.first.path}',
          );
        }
        onProgress?.call(done, total, chunk.first.path);

        for (final item in chunk) {
          // Once Skip all is active, skip ALL FFI preflight (CreateFile +
          // Restart Manager). Each Restart Manager session start/end takes
          // 30-100ms and was being called for every item in a 512-file
          // chunk — that single loop alone could block the UI thread for
          // 15-50s. With Skip all active, only do cheap string-based
          // volatile detection and let the native batch handle the rest.
          final volatileBusy = _shouldTreatAsVolatileInUsePath(item.path);

          bool quickBusy = false;
          bool shouldProbe = false;

          if (!skipAllRemainingDeletes) {
            shouldProbe = _shouldProbePathBusyBeforeBatch(
              item.path,
              permanent,
              chunkIndex: start == 0 ? 0 : (start ~/ chunkSize),
            );
            quickBusy =
                shouldProbe && _isPathBusyByAnotherProcessQuick(item.path);
          }

          final isLikelyBusy = quickBusy || volatileBusy;
          if (!skipAllRemainingDeletes && (shouldProbe || volatileBusy)) {
            AppLogger.info(
              '[DiskCleaner] Delete preflight | path=${item.path} | shouldProbe=$shouldProbe | quickBusy=$quickBusy | volatileBusy=$volatileBusy | route=${isLikelyBusy ? "skip-in-use" : "batch"}',
            );
          }
          if (isLikelyBusy) {
            if (skipAllRemainingDeletes) {
              autoSkippedInUse.add(item);
            } else {
              await resolveFailedItem(
                item,
                actionLabel:
                    permanent ? 'permanent delete' : 'recycle-bin move',
                knownInUse: true,
              );
              done++;
              onProgress?.call(done, total, item.path);
            }
            continue;
          }

          // Lock diagnostics are intentionally lazy. Restart Manager costs
          // tens of milliseconds per file, so healthy items go straight into
          // the batch and only actual failures are classified later.
          batchedDeletes.add(item);
        }

        if (autoSkippedInUse.isNotEmpty) {
          recordSkippedInUseMany(
            autoSkippedInUse,
            actionLabel: permanent ? 'permanent delete' : 'recycle-bin move',
            log: false,
          );
          done += autoSkippedInUse.length;
          onProgress?.call(done, total, autoSkippedInUse.last.path);
        }

        if (batchedDeletes.isEmpty) {
          start = end;
          continue;
        }

        final paths =
            batchedDeletes.map((item) => item.path).toList(growable: false);
        onProgress?.call(done, total, paths.first);

        try {
          Set<String> ok;
          // Same fast-skip rationale as the guarded single path above:
          // once the user chose Skip all, do not let each failed batch
          // burn the full native timeout.
          final fastSkipTimeout = skipAllRemainingDeletes
              ? const Duration(milliseconds: 200)
              : null;
          if (permanent) {
            ok = await trash.deleteMultiplePermanently(
              paths,
              chunkSize: paths.length,
              timeoutOverride: fastSkipTimeout,
            );
          } else {
            ok = await trash.moveMultipleToTrashBatched(
              paths,
              chunkSize: paths.length,
              timeoutOverride: fastSkipTimeout,
            );
          }

          var batchSuccessCount = 0;
          var batchSuccessBytes = 0;
          for (var i = 0; i < batchedDeletes.length; i++) {
            final item = batchedDeletes[i];
            if (skipAllRemainingDeletes) {
              final remaining = batchedDeletes.sublist(i);
              recordSkippedByUserMany(
                remaining,
                reason: 'Skipped after user selected Skip all',
                actionLabel:
                    permanent ? 'permanent delete' : 'recycle-bin move',
                log: false,
              );
              done += remaining.length;
              onProgress?.call(done, total, remaining.last.path);
              break;
            }
            if (ok.contains(item.path)) {
              recordSuccess(item, log: false);
              batchSuccessCount++;
              batchSuccessBytes += item.sizeBytes;
            } else {
              await resolveFailedItem(item);
            }
            done++;
            onProgress?.call(done, total, item.path);
          }
          if (batchSuccessCount > 0) {
            AppLogger.info(
              '[DiskCleaner] Finished ${permanent ? "permanent delete" : "recycle-bin move"} batch | success=$batchSuccessCount | bytes=$batchSuccessBytes | first=${batchedDeletes.first.path}',
            );
          }
        } catch (e) {
          for (var i = 0; i < batchedDeletes.length; i++) {
            final item = batchedDeletes[i];
            if (skipAllRemainingDeletes) {
              final remaining = batchedDeletes.sublist(i);
              recordSkippedByUserMany(
                remaining,
                reason: 'Skipped after user selected Skip all',
                actionLabel:
                    permanent ? 'permanent delete' : 'recycle-bin move',
                log: false,
              );
              done += remaining.length;
              onProgress?.call(done, total, remaining.last.path);
              break;
            }
            await resolveFailedItem(item, fallbackReason: '$e');
            done++;
            onProgress?.call(done, total, item.path);
          }
        }

        start = end;
      }
    }

    // 2) Items already inside the Recycle Bin still go through the
    // per-item COM/PowerShell path. These are usually a small set.
    for (int i = 0; i < binItems.length; i++) {
      final item = binItems[i];
      AppLogger.info(
        '[DiskCleaner] Processing delete from Recycle Bin: ${item.path}',
      );
      onProgress?.call(done, total, item.path);
      try {
        final ok = await trash.deleteFromWindowsRecycleBin(item.path);
        if (ok) {
          recordSuccess(item, actionLabel: 'Deleted from Recycle Bin');
        } else {
          await resolveFailedItem(
            item,
            fallbackReason: 'Failed to delete from Recycle Bin',
            actionLabel: 'delete from Recycle Bin',
          );
        }
      } on FileSystemException catch (e) {
        await resolveFailedItem(
          item,
          fallbackReason: e.message,
          actionLabel: 'delete from Recycle Bin',
        );
      } catch (e) {
        await resolveFailedItem(
          item,
          fallbackReason: '$e',
          actionLabel: 'delete from Recycle Bin',
        );
      }
      done++;
      onProgress?.call(done, total, item.path);
    }

    return CleanReport(
      freedBytes: freed,
      succeeded: succeeded,
      failed: failed,
      skippedUnsafe: skippedUnsafe,
      skippedInUse: skippedInUse,
      skippedByUser: skippedByUser.toList(growable: false),
      wasPermanent: permanent,
    );
  }

  Future<List<JunkItem>> _expandDirectoryTargets(
    List<JunkItem> items, {
    void Function(String currentPath)? onPreparing,
  }) async {
    final expanded = <JunkItem>[];

    for (final item in items) {
      final isBinItem =
          item.isRecycleBinItem || item.categoryId == 'recycle_bin';
      if (isBinItem) {
        expanded.add(item);
        continue;
      }

      final type = FileSystemEntity.typeSync(item.path, followLinks: false);
      if (type != FileSystemEntityType.directory) {
        expanded.add(item);
        continue;
      }

      // Explicit user-selected directories should be deleted as directories.
      // Only scanner rules marked as container-only should expand to their
      // descendant files while preserving the folder itself.
      if (!item.isContainerOnly) {
        expanded.add(item);
        continue;
      }

      AppLogger.info('[DiskCleaner] Expanding directory target: ${item.path}');
      onPreparing?.call(item.path);
      var childCount = 0;
      try {
        await for (final entity
            in Directory(item.path).list(recursive: true, followLinks: false)) {
          final childType =
              FileSystemEntity.typeSync(entity.path, followLinks: false);
          if (childType != FileSystemEntityType.file) {
            continue;
          }

          int size = 0;
          DateTime? modified;
          try {
            final stat = entity.statSync();
            size = stat.size;
            modified = stat.modified;
          } catch (_) {}

          expanded.add(JunkItem(
            path: entity.path,
            sizeBytes: size,
            lastModified: modified,
            categoryId: item.categoryId,
          ));
          childCount++;

          // Yield periodically so the UI can repaint and the user sees the
          // "Preparing files…" status update instead of a frozen screen
          // while we walk huge junk directories (e.g. %TEMP%).
          if (childCount % 500 == 0) {
            onPreparing?.call(entity.path);
            await Future<void>.delayed(Duration.zero);
          }
        }
      } catch (e, st) {
        AppLogger.warning(
          '[DiskCleaner] Failed to fully expand directory target: ${item.path}',
          error: e,
          stackTrace: st,
        );
      }

      AppLogger.info(
        '[DiskCleaner] Expanded directory target: ${item.path} -> $childCount file(s)',
      );
    }

    return expanded;
  }

  static const String _fileInUseFailure =
      'Skipped because the file is currently in use';

  Future<_DeleteFailureClassification> _classifyDeleteFailure(
    String path,
    bool permanent,
  ) async {
    final blockedPath = await _findBlockedDeletePath(path);
    if (blockedPath != null) {
      return _DeleteFailureClassification(
        isInUse: true,
        reason: _fileInUseFailure,
        blockedPath: blockedPath,
      );
    }
    if (Platform.isWindows && _hasRestartManagerLock(path)) {
      return const _DeleteFailureClassification(
        isInUse: true,
        reason: _fileInUseFailure,
      );
    }
    return _DeleteFailureClassification(
      isInUse: false,
      reason: permanent ? 'Failed to delete' : 'Failed to move to Recycle Bin',
    );
  }

  /// Maximum number of descendants probed when classifying a failed directory
  /// delete. The recursive probe used to be unbounded, which made the cleaner
  /// appear "stuck at 1/N" whenever a large junk directory contained a busy
  /// file deep in the tree. The cap keeps classification cheap (worst case
  /// ~200 fast `CreateFile` calls) while still catching the common cases
  /// (busy file at the top of a category folder).
  static const int _classifyMaxDescendants = 200;

  /// Hard deadline for the descendant probe. Once we cross this we stop
  /// walking and treat the failure as a generic delete failure — the user
  /// still gets a Skip / Skip all / Retry dialog.
  static const Duration _classifyDeadline = Duration(milliseconds: 750);

  Future<String?> _findBlockedDeletePath(String path) async {
    final entityType = FileSystemEntity.typeSync(path, followLinks: false);
    if (entityType == FileSystemEntityType.notFound) {
      return null;
    }

    if (_isPathBusyByAnotherProcessQuick(path)) {
      return path;
    }

    if (entityType != FileSystemEntityType.directory) {
      return null;
    }

    final deadline = DateTime.now().add(_classifyDeadline);
    var probed = 0;

    try {
      // Non-recursive first pass — most "in use" hits are top-level (e.g.
      // an open log file directly inside a category folder). Cheap and
      // deterministic.
      await for (final entity
          in Directory(path).list(recursive: false, followLinks: false)) {
        if (probed >= _classifyMaxDescendants ||
            DateTime.now().isAfter(deadline)) {
          return null;
        }
        if (_isPathBusyByAnotherProcessQuick(entity.path)) {
          return entity.path;
        }
        probed++;
      }
    } catch (_) {
      // Ignore traversal errors here; they are surfaced through the main
      // delete result. This pass is only for detecting in-use descendants.
    }

    // Bounded recursive pass — only run if we still have budget. This used
    // to be unbounded and was the primary source of the "clean is stuck at
    // 1/N" symptom on large junk directories.
    if (probed >= _classifyMaxDescendants || DateTime.now().isAfter(deadline)) {
      return null;
    }

    try {
      await for (final entity
          in Directory(path).list(recursive: true, followLinks: false)) {
        if (probed >= _classifyMaxDescendants ||
            DateTime.now().isAfter(deadline)) {
          return null;
        }
        if (_isPathBusyByAnotherProcessQuick(entity.path)) {
          return entity.path;
        }
        probed++;
      }
    } catch (_) {
      // Same rationale as above.
    }

    return null;
  }

  bool _isPathBusyByAnotherProcessQuick(String path) {
    if (!Platform.isWindows) {
      return false;
    }

    final nativePath = path.toNativeUtf16();
    try {
      final attributes = win32.GetFileAttributes(nativePath);
      if (attributes == 0xFFFFFFFF) {
        return false;
      }

      final isDirectory = (attributes & win32.FILE_ATTRIBUTE_DIRECTORY) != 0;
      // Fast "is another process holding this path" probe. Asking for zero
      // share is intentionally conservative: if someone else has the file open,
      // skip it here instead of letting a recycle-bin batch stall on it.
      final handle = win32.CreateFile(
        nativePath,
        win32.FILE_READ_ATTRIBUTES,
        0,
        nullptr,
        win32.OPEN_EXISTING,
        isDirectory ? win32.FILE_FLAG_BACKUP_SEMANTICS : 0,
        win32.NULL,
      );
      if (handle != win32.INVALID_HANDLE_VALUE) {
        win32.CloseHandle(handle);
        return false;
      }

      final error = win32.GetLastError();
      return error == win32.ERROR_SHARING_VIOLATION ||
          error == win32.ERROR_LOCK_VIOLATION ||
          error == win32.ERROR_USER_MAPPED_FILE ||
          error == win32.ERROR_ACCESS_DENIED;
    } finally {
      calloc.free(nativePath);
    }
  }

  bool _shouldProbePathBusyBeforeBatch(
    String path,
    bool permanent, {
    required int chunkIndex,
  }) {
    if (permanent) {
      return false;
    }

    final lowerPath = path.toLowerCase();

    // First recycle-bin batch is the most user-visible point of failure.
    // Probe every local file there so a single locked temp artifact does not
    // enter IFileOperation and stall the whole batch on item #1.
    if (chunkIndex == 0) {
      return true;
    }

    return lowerPath.endsWith('.dll') ||
        lowerPath.endsWith('.node') ||
        lowerPath.endsWith('.exe') ||
        lowerPath.endsWith('.pyd') ||
        lowerPath.endsWith('.sys') ||
        lowerPath.endsWith('.ocx') ||
        lowerPath.endsWith('.msi') ||
        lowerPath.endsWith('.tmp') ||
        lowerPath.endsWith('.log') ||
        lowerPath.endsWith('.etl');
  }

  bool _shouldTreatAsVolatileInUsePath(String path) {
    final lowerPath = path.toLowerCase().replaceAll('/', r'\');
    // These locations are actively written by background runtimes (OneDrive,
    // WebView2/Chromium, LevelDB). Restart Manager often cannot identify the
    // holder, but Windows IFileOperation can still block indefinitely while
    // trying to move the file to Recycle Bin. Treat them as volatile/in-use and
    // skip them instead of letting a single live log stall the cleaner.
    final isBrowserRuntimeCache = lowerPath.contains(r'\code cache\') ||
        lowerPath.contains(r'\gpucache\') ||
        lowerPath.contains(r'\cache_data\') ||
        lowerPath.contains(r'\shadercache\') ||
        lowerPath.contains(r'\local storage\leveldb\') ||
        lowerPath.contains(r'\session storage\') ||
        lowerPath.contains(r'\service worker\cache');
    if (isBrowserRuntimeCache) {
      return true;
    }

    final isLiveDatabaseOrLog = lowerPath.endsWith('.log') ||
        lowerPath.endsWith('.ldb') ||
        lowerPath.endsWith('.sqlite') ||
        lowerPath.endsWith('.sqlite-wal') ||
        lowerPath.endsWith('.sqlite-shm');
    if (!isLiveDatabaseOrLog) {
      return false;
    }

    return lowerPath.contains(r'\onedrive\') ||
        lowerPath.contains(r'\ebwebview\') ||
        lowerPath.contains(r'\webview2\') ||
        lowerPath.contains(r'\edge\') ||
        lowerPath.contains(r'\microsoftedge\') ||
        lowerPath.contains(r'\chrome\') ||
        lowerPath.contains(r'\chromium\') ||
        lowerPath.contains(r'\leveldb\') ||
        lowerPath.contains(r'\local storage\');
  }

  bool _hasRestartManagerLock(String path) {
    final bindings = _RestartManagerBindings.instance;
    final sessionHandle = calloc<Uint32>();
    final sessionKey = calloc<Uint16>(_RestartManagerBindings.sessionKeyLength);
    Pointer<Utf16>? pathPtr;
    Pointer<Pointer<Utf16>>? fileListPtr;

    try {
      final startResult =
          bindings.startSession(sessionHandle, 0, sessionKey.cast());
      if (startResult != win32.ERROR_SUCCESS) {
        return false;
      }

      pathPtr = path.toNativeUtf16();
      fileListPtr = calloc<Pointer<Utf16>>(1)..value = pathPtr;

      final registerResult = bindings.registerResources(
        sessionHandle.value,
        1,
        fileListPtr,
        0,
        nullptr,
        0,
        nullptr,
      );
      if (registerResult != win32.ERROR_SUCCESS) {
        return false;
      }

      final procInfoNeeded = calloc<Uint32>();
      final procInfo = calloc<Uint32>()..value = 0;
      final rebootReasons = calloc<Uint32>();
      try {
        final listResult = bindings.getList(
          sessionHandle.value,
          procInfoNeeded,
          procInfo,
          nullptr,
          rebootReasons,
        );
        return listResult == win32.ERROR_MORE_DATA ||
            (listResult == win32.ERROR_SUCCESS && procInfoNeeded.value > 0);
      } finally {
        calloc.free(procInfoNeeded);
        calloc.free(procInfo);
        calloc.free(rebootReasons);
      }
    } catch (_) {
      return false;
    } finally {
      if (sessionHandle.value != 0) {
        bindings.endSession(sessionHandle.value);
      }
      if (fileListPtr != null) {
        calloc.free(fileListPtr);
      }
      if (pathPtr != null) {
        calloc.free(pathPtr);
      }
      calloc.free(sessionHandle);
      calloc.free(sessionKey);
    }
  }

  // ---------------------------------------------------------------------------
  // Full disk scan (TreeSize-style)
  // ---------------------------------------------------------------------------

  FullDiskScanHandle? _activeFullScan;

  /// Whether a full disk scan is currently running.
  bool get isFullScanning => _activeFullScan != null;

  /// Scans the entire drive at [drivePath] recursively, building a tree of
  /// directory sizes. Returns a handle with progress stream and future result.
  ///
  /// After the scan completes, call [markJunkNodes] on the result tree to
  /// highlight which directories/files match known junk categories.
  Future<FullDiskScanHandle> scanFullDisk({
    required String drivePath,
    int maxDepth = 20,
  }) async {
    if (_activeFullScan != null) {
      throw StateError(
          'A full disk scan is already in progress; cancel it first.');
    }
    if (!Platform.isWindows) {
      throw StateError('Full disk scan is only supported on Windows.');
    }

    final handle = await spawnFullDiskScan(
      drivePath: drivePath,
      maxDepth: maxDepth,
    );
    _activeFullScan = handle;

    // Auto-clear when done, including when the scan fails or is cancelled.
    // A bare `.then` would skip the error path and leave the handle pinned,
    // after which every later scan throws "already in progress" until the
    // app restarts. The identity check keeps a slow completion from clearing
    // a newer scan that has since started.
    // Callers await `handle.future` themselves and handle its error, so this
    // bookkeeping branch is ignored rather than left as an unhandled error.
    handle.future.whenComplete(() {
      if (identical(_activeFullScan, handle)) _activeFullScan = null;
    }).ignore();

    return handle;
  }

  /// Cancels the in-flight full disk scan, if any.
  void cancelFullDiskScan() {
    _activeFullScan?.cancel();
    _activeFullScan = null;
  }

  /// Marks nodes in [root] that match known junk category paths.
  ///
  /// Two matching modes:
  /// - Rules WITHOUT includeGlobs: the entire resolved directory subtree is
  ///   junk (e.g. %TEMP%, browser cache dirs). Mark the node + all descendants.
  /// - Rules WITH includeGlobs: only individual FILES matching the glob inside
  ///   that directory are junk. The directory itself is NOT marked — only
  ///   matching leaf files get tagged.
  void markJunkNodes(DiskTreeNode root) {
    root.invalidateJunkCache();
    final categories = CleanerCategories.all();

    // Split rules into "whole directory" vs "glob-filtered"
    final wholeDirJunk = <String, String>{}; // upper path → category ID
    final globFilteredJunk = <_GlobRule>[];

    for (final cat in categories) {
      for (final rule in cat.rules) {
        if (rule.source.kind == PathSourceKind.recycleBin) continue;
        final resolved = WindowsKnownFolders.resolve(rule.source);
        if (resolved == null || resolved.isEmpty) continue;

        if (rule.includeGlobs == null || rule.includeGlobs!.isEmpty) {
          // No glob filter → entire directory is junk
          wholeDirJunk[resolved.toUpperCase()] = cat.id;
        } else {
          // Has glob filter → only matching files are junk
          globFilteredJunk.add(_GlobRule(
            basePath: resolved.toUpperCase(),
            categoryId: cat.id,
            globs: rule.includeGlobs!.map((g) => _globToRegex(g)).toList(),
          ));
        }
      }
    }

    _markJunkRecursive(root, wholeDirJunk, globFilteredJunk);
  }

  void _markJunkRecursive(
    DiskTreeNode node,
    Map<String, String> wholeDirJunk,
    List<_GlobRule> globFilteredJunk,
  ) {
    final upperPath = node.fullPath.toUpperCase();

    // Check whole-directory rules: if this node IS the junk dir or inside it
    for (final entry in wholeDirJunk.entries) {
      if (upperPath == entry.key || upperPath.startsWith('${entry.key}\\')) {
        _markSubtreeAsJunk(node, entry.value);
        return; // Entire subtree is junk
      }
    }

    // Check glob-filtered rules: only mark individual files, not directories
    if (node.isFile) {
      final fileName = _nodeBasename(node.fullPath).toUpperCase();
      final parentPath = _nodeParentDir(node.fullPath).toUpperCase();
      for (final rule in globFilteredJunk) {
        // File must be inside (or recursively under) the rule's base path
        if (parentPath == rule.basePath ||
            parentPath.startsWith('${rule.basePath}\\')) {
          // Check if filename matches any of the globs
          for (final glob in rule.globs) {
            if (glob.hasMatch(fileName)) {
              node.junkCategoryId = rule.categoryId;
              break;
            }
          }
          if (node.junkCategoryId != null) break;
        }
      }
    }

    // Recurse into children
    for (final child in node.children) {
      _markJunkRecursive(child, wholeDirJunk, globFilteredJunk);
    }
  }

  void _markSubtreeAsJunk(DiskTreeNode node, String categoryId) {
    node.junkCategoryId = categoryId;
    for (final child in node.children) {
      _markSubtreeAsJunk(child, categoryId);
    }
  }

  static String _nodeBasename(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  static String _nodeParentDir(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i > 0 ? path.substring(0, i) : path;
  }

  static RegExp _globToRegex(String glob) {
    final buffer = StringBuffer('^');
    for (final ch in glob.split('')) {
      switch (ch) {
        case '*':
          buffer.write('.*');
          break;
        case '?':
          buffer.write('.');
          break;
        case '.':
        case '(':
        case ')':
        case '[':
        case ']':
        case '{':
        case '}':
        case r'\':
        case '+':
        case '|':
        case '^':
        case r'$':
          buffer.write(r'\');
          buffer.write(ch);
          break;
        default:
          buffer.write(ch);
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<CleanerScanHandle> _beginScan(
    List<String> drivePaths,
    List<String> categoryIds,
  ) async {
    if (_activeScan != null) {
      throw StateError(
          'A disk scan is already in progress; call cancelActiveScan first.');
    }
    if (!Platform.isWindows) {
      throw StateError('DiskCleanerService is only supported on Windows.');
    }

    final selected = _resolveCategories(categoryIds);
    final resolvedRules = <ResolvedRule>[];
    for (final cat in selected) {
      for (final rule in cat.rules) {
        if (rule.source.kind == PathSourceKind.recycleBin) continue;
        final base = WindowsKnownFolders.resolve(rule.source);
        if (base == null || base.isEmpty) continue;
        resolvedRules.add(ResolvedRule(
          categoryId: cat.id,
          basePath: base,
          includeGlobs: rule.includeGlobs,
          excludeGlobs: rule.excludeGlobs,
          minAge: rule.minAge,
          emptyOnly: rule.emptyOnly,
          recursive: rule.recursive,
        ));
      }
    }

    final handle = await spawnScanWithResolvedRules(
      drivesScanned: drivePaths.isEmpty ? const ['C:\\'] : drivePaths,
      rules: resolvedRules,
    );
    _activeScan = handle;
    return handle;
  }

  List<CleanerCategory> _resolveCategories(List<String> ids) {
    if (ids.isEmpty) {
      return CleanerCategories.all()
          .where((c) => c.defaultEnabled)
          .toList(growable: false);
    }
    final out = <CleanerCategory>[];
    for (final id in ids) {
      final cat = CleanerCategories.byId(id);
      if (cat != null) out.add(cat);
    }
    return out;
  }

  Future<List<JunkItem>> _scanRecycleBin() async {
    if (!Platform.isWindows) return const [];
    try {
      final items = await TrashManager().getWindowsRecycleBinItems();
      return [
        for (final item in items)
          JunkItem(
            path: item.recycleBinPath,
            sizeBytes: item.size,
            lastModified: item.trashedDate,
            categoryId: 'recycle_bin',
            isRecycleBinItem: true,
            originalPath: item.originalPath,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Returns total/free bytes for [drivePath], or null on failure.
  _DriveSpaceRaw? _readDriveSpace(String drivePath) {
    if (!Platform.isWindows) return null;
    final drive = drivePath.endsWith('\\') ? drivePath : '$drivePath\\';
    final lpFree = calloc<Uint64>();
    final lpTotal = calloc<Uint64>();
    final lpTotalFree = calloc<Uint64>();
    try {
      final ok = win32.GetDiskFreeSpaceEx(
        drive.toNativeUtf16(),
        lpFree,
        lpTotal,
        lpTotalFree,
      );
      if (ok == 0) return null;
      return _DriveSpaceRaw(lpTotal.value, lpFree.value);
    } catch (_) {
      return null;
    } finally {
      calloc.free(lpFree);
      calloc.free(lpTotal);
      calloc.free(lpTotalFree);
    }
  }
}

class _DriveSpaceRaw {
  final int totalBytes;
  final int freeBytes;
  const _DriveSpaceRaw(this.totalBytes, this.freeBytes);
}

/// Helper for glob-filtered junk rules used by [markJunkNodes].
class _GlobRule {
  final String basePath; // uppercased
  final String categoryId;
  final List<RegExp> globs;
  const _GlobRule({
    required this.basePath,
    required this.categoryId,
    required this.globs,
  });
}

/// Caller-facing controller returned by [DiskCleanerService.scanJunkStream].
class CleanerScanController {
  final Stream<ScanProgress> progress;
  final Future<ScanReport> report;
  final void Function() _cancel;

  CleanerScanController._({
    required this.progress,
    required this.report,
    required void Function() onCancel,
  }) : _cancel = onCancel;

  void cancel() => _cancel();
}

class _DeleteFailureClassification {
  final bool isInUse;
  final String reason;
  final String? blockedPath;

  const _DeleteFailureClassification({
    required this.isInUse,
    required this.reason,
    this.blockedPath,
  });
}

typedef _RmStartSessionNative = Int32 Function(
  Pointer<Uint32>,
  Uint32,
  Pointer<Utf16>,
);
typedef _RmStartSessionDart = int Function(
  Pointer<Uint32>,
  int,
  Pointer<Utf16>,
);

typedef _RmRegisterResourcesNative = Int32 Function(
  Uint32,
  Uint32,
  Pointer<Pointer<Utf16>>,
  Uint32,
  Pointer<Void>,
  Uint32,
  Pointer<Pointer<Utf16>>,
);
typedef _RmRegisterResourcesDart = int Function(
  int,
  int,
  Pointer<Pointer<Utf16>>,
  int,
  Pointer<Void>,
  int,
  Pointer<Pointer<Utf16>>,
);

typedef _RmGetListNative = Int32 Function(
  Uint32,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
);
typedef _RmGetListDart = int Function(
  int,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Void>,
  Pointer<Uint32>,
);

typedef _RmEndSessionNative = Int32 Function(Uint32);
typedef _RmEndSessionDart = int Function(int);

class _RestartManagerBindings {
  static const int sessionKeyLength = 33;
  static final _RestartManagerBindings instance = _RestartManagerBindings._();

  final DynamicLibrary _lib = DynamicLibrary.open('Rstrtmgr.dll');

  late final _RmStartSessionDart startSession =
      _lib.lookupFunction<_RmStartSessionNative, _RmStartSessionDart>(
          'RmStartSession');

  late final _RmRegisterResourcesDart registerResources =
      _lib.lookupFunction<_RmRegisterResourcesNative, _RmRegisterResourcesDart>(
          'RmRegisterResources');

  late final _RmGetListDart getList =
      _lib.lookupFunction<_RmGetListNative, _RmGetListDart>('RmGetList');

  late final _RmEndSessionDart endSession = _lib
      .lookupFunction<_RmEndSessionNative, _RmEndSessionDart>('RmEndSession');

  _RestartManagerBindings._();
}

// ---------------------------------------------------------------------------
// Background-isolate worker for cleanJunk
// ---------------------------------------------------------------------------
//
// The worker runs the entire clean pipeline (FFI preflight, directory
// expansion, native delete batches, logging) in a separate isolate so the
// UI thread stays responsive during long cleanup runs.
//
// Bridge protocol:
//  - main → worker: spawn args (reply port, items, permanent flag,
//    RootIsolateToken so MethodChannel works in the worker isolate)
//  - worker → main: SendPort handshake, then a stream of progress messages
//    and failure prompts
//  - main → worker: failure responses (skip / skipAll / retry)
//  - worker → main: final CleanReport or error message

class _CleanWorkerArgs {
  final SendPort replyTo;
  final List<JunkItem> items;
  final bool permanent;
  final RootIsolateToken? rootIsolateToken;

  const _CleanWorkerArgs({
    required this.replyTo,
    required this.items,
    required this.permanent,
    required this.rootIsolateToken,
  });
}

class _CleanProgressMessage {
  final int done;
  final int total;
  final String? currentPath;

  const _CleanProgressMessage(this.done, this.total, this.currentPath);
}

class _CleanFailurePrompt {
  final int requestId;
  final CleanFailureDetails details;

  const _CleanFailurePrompt(this.requestId, this.details);
}

class _CleanFailureResponse {
  final int requestId;
  final CleanFailureAction action;

  const _CleanFailureResponse(this.requestId, this.action);
}

class _CleanFinished {
  final CleanReport report;

  const _CleanFinished(this.report);
}

class _CleanFailed {
  final Object error;
  final StackTrace stackTrace;

  const _CleanFailed(this.error, this.stackTrace);
}

void _cleanWorkerEntry(_CleanWorkerArgs args) async {
  // MethodChannel calls (used by TrashManager → WindowsFileOperations) need
  // the binary messenger to be wired up in this isolate.
  if (args.rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(args.rootIsolateToken!);
  }

  final controlPort = ReceivePort();
  args.replyTo.send(controlPort.sendPort);

  // Throttle progress messages so we never flood the main isolate's event
  // queue. The 80 ms window matches the UI-side throttle and is enough to
  // keep the bottom progress bar smooth without per-file message storms.
  var lastProgressSentAt = DateTime.fromMillisecondsSinceEpoch(0);
  const progressInterval = Duration(milliseconds: 80);

  void sendProgress(int done, int total, String? currentPath) {
    final now = DateTime.now();
    final isFinal = total > 0 && done >= total;
    final isPreparing = total == 0;
    if (!isFinal &&
        !isPreparing &&
        now.difference(lastProgressSentAt) < progressInterval) {
      return;
    }
    lastProgressSentAt = now;
    args.replyTo.send(_CleanProgressMessage(done, total, currentPath));
  }

  // Pending failure-prompt completers, keyed by request id.
  var nextPromptId = 0;
  final pendingPrompts = <int, Completer<CleanFailureAction>>{};

  final controlSub = controlPort.listen((dynamic msg) {
    if (msg is _CleanFailureResponse) {
      final completer = pendingPrompts.remove(msg.requestId);
      completer?.complete(msg.action);
    }
  });

  Future<CleanFailureAction> bridgePrompt(CleanFailureDetails details) {
    final id = nextPromptId++;
    final completer = Completer<CleanFailureAction>();
    pendingPrompts[id] = completer;
    args.replyTo.send(_CleanFailurePrompt(id, details));
    return completer.future;
  }

  try {
    final report = await DiskCleanerService.instance._cleanJunkInternal(
      items: args.items,
      permanent: args.permanent,
      onProgress: sendProgress,
      onDeleteFailure: bridgePrompt,
    );
    args.replyTo.send(_CleanFinished(report));
  } catch (e, st) {
    args.replyTo.send(_CleanFailed(e, st));
  } finally {
    await controlSub.cancel();
    controlPort.close();
  }
}
