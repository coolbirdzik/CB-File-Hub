import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../e2e/cb_e2e_config.dart';

import '../../../bloc/ai_agent/ai_agent_event.dart';
import '../../../bloc/cleaner_app_insights/cleaner_app_insights_cubit.dart';
import '../../../bloc/cleaner_app_insights/cleaner_app_insights_state.dart';
import '../../../config/languages/app_localizations.dart';
import '../../../helpers/files/external_app_helper.dart';
import '../../../helpers/files/windows_shell_context_menu.dart';
import '../../../ui/controllers/file_operations_handler.dart';
import '../../../ui/dialogs/open_with_dialog.dart';
import '../../../ui/components/common/browser_like_keyboard_shortcuts.dart';
import '../../../ui/components/common/shared_file_context_menu.dart';
import '../../../ui/tab_manager/components/tag_dialogs.dart' as tag_dialogs;
import '../../../ui/utils/entity_open_actions.dart';
import '../../../ui/utils/file_type_utils.dart';
import '../../../ui/utils/route.dart';
import '../../../services/ai/ai_provider_service.dart';
import '../../../services/app_insights/app_insights_models.dart';
import '../../../services/app_insights/app_storage_analyzer.dart';
import '../../../services/app_insights/windows_app_inventory_service.dart';
import '../../../services/disk_cleaner/cleaner_categories.dart';
import '../../../services/disk_cleaner/cleaner_models.dart';
import '../../../services/disk_cleaner/cleaner_growth_history_service.dart';
import '../../../services/disk_cleaner/cleaner_last_scan_service.dart';
import '../../../services/disk_cleaner/disk_cleaner_service.dart';
import '../../../services/disk_cleaner/disk_tree_node.dart';
import '../../../services/disk_cleaner/disk_tree_selection.dart';
import '../../../services/disk_cleaner/full_disk_scan_isolate.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../widgets/app_progress_indicator.dart';
import '../ai_chat/ai_panel_controller.dart';
import 'cleaner_apps_view.dart';
import 'cleaner_utilities_shell.dart';

/// Full disk analyzer + cleaner screen (TreeSize-style).
///
/// 2-panel layout after scan: collapsible tree view (left) + pie chart (right).
/// Junk categories are highlighted and tickable for deletion.
typedef CleanerCachedResultLookup = FullDiskScanResult? Function(
  String drivePath,
);

typedef CleanerFullDiskScanStarter = Future<FullDiskScanHandle> Function(
  String drivePath,
);

/// Separates informational old-large evidence into independently ranked
/// folder and file sections for the Cleaner results panel.
class OldLargeEvidenceSections {
  final List<FullDiskScanInsight> folders;
  final List<FullDiskScanInsight> files;

  const OldLargeEvidenceSections({
    required this.folders,
    required this.files,
  });

  int get totalCount => folders.length + files.length;
}

enum OldLargeEvidenceFilter { all, folders, files }

/// Builds deterministic, size-ranked sections without touching the drive.
OldLargeEvidenceSections splitOldLargeEvidence(
  Iterable<FullDiskScanInsight> items,
) {
  final folders = <FullDiskScanInsight>[];
  final files = <FullDiskScanInsight>[];
  for (final item in items) {
    (item.isFile ? files : folders).add(item);
  }
  folders.sort(compareOldLargeDiskInsights);
  files.sort(compareOldLargeDiskInsights);
  return OldLargeEvidenceSections(folders: folders, files: files);
}

/// Returns the selected old-large evidence in stable presentation order.
///
/// The All view deliberately keeps folders before files so directory evidence
/// cannot be hidden among file rows.
List<FullDiskScanInsight> filterOldLargeEvidence(
  Iterable<FullDiskScanInsight> items,
  OldLargeEvidenceFilter filter,
) {
  final sections = splitOldLargeEvidence(items);
  switch (filter) {
    case OldLargeEvidenceFilter.all:
      return <FullDiskScanInsight>[...sections.folders, ...sections.files];
    case OldLargeEvidenceFilter.folders:
      return sections.folders;
    case OldLargeEvidenceFilter.files:
      return sections.files;
  }
}

/// Finds the deepest displayed node that contains [path].
///
/// Old-large file evidence can refer to a file row folded into a directory's
/// aggregate row. This helper searches only the current in-memory display
/// tree, so revealing evidence never scans the drive or creates a deletion
/// target for a missing file.
DiskTreeNode? findNearestDisplayedTreeNodeForPath(
  DiskTreeNode root,
  String path,
) {
  final normalizedTarget = AppStorageAnalyzer.normalizeWindowsPath(path);
  if (normalizedTarget.isEmpty) return null;

  DiskTreeNode? nearest;
  var nearestPathLength = -1;
  final stack = <DiskTreeNode>[root];
  while (stack.isNotEmpty) {
    final node = stack.removeLast();
    final normalizedNodePath =
        AppStorageAnalyzer.normalizeWindowsPath(node.fullPath);
    if (normalizedNodePath.isNotEmpty &&
        normalizedNodePath.length > nearestPathLength &&
        AppStorageAnalyzer.isSameOrDescendant(
          normalizedTarget,
          normalizedNodePath,
        )) {
      nearest = node;
      nearestPathLength = normalizedNodePath.length;
    }
    stack.addAll(node.children);
  }
  return nearest;
}

class _OldLargeEvidenceSection {
  final String keySuffix;
  final String title;
  final List<FullDiskScanInsight> items;

  const _OldLargeEvidenceSection({
    required this.keySuffix,
    required this.title,
    required this.items,
  });
}

/// Coordinates the two user-visible scan intents: setup may display a
/// completed result, while an explicit refresh always starts a scan.
@visibleForTesting
class CleanerScanCoordinator {
  final CleanerCachedResultLookup _cachedResultFor;
  final CleanerFullDiskScanStarter _startFullDiskScan;

  const CleanerScanCoordinator({
    required CleanerCachedResultLookup cachedResultFor,
    required CleanerFullDiskScanStarter startFullDiskScan,
  })  : _cachedResultFor = cachedResultFor,
        _startFullDiskScan = startFullDiskScan;

  FullDiskScanResult? cachedSetupResult(String drivePath) {
    return _cachedResultFor(drivePath);
  }

  Future<FullDiskScanHandle> forceRefresh(String drivePath) {
    return _startFullDiskScan(drivePath);
  }
}

class CbAgentCleanerScreen extends StatefulWidget {
  const CbAgentCleanerScreen({Key? key}) : super(key: key);

  @override
  State<CbAgentCleanerScreen> createState() => _CbAgentCleanerScreenState();
}

enum _Phase { setup, results, cleaned }

enum _CleanDeleteMode { recycleBin, permanent }

/// One-tap views over the scanned tree. These match how people actually think
/// about reclaiming space, instead of requiring them to walk the hierarchy.
enum _TreePreset { none, largeFiles, logsAndCaches, installers }

enum _CleanerSubFeature { diskCleaner, appInsights }

class _AppInsightsEvidence {
  final InstalledAppInventoryResult inventory;
  final Map<String, AppUsageEvidence> usageByAppId;
  final List<String> warnings;
  final bool isPartial;

  const _AppInsightsEvidence({
    required this.inventory,
    required this.usageByAppId,
    required this.warnings,
    required this.isPartial,
  });

  factory _AppInsightsEvidence.inventoryOnly(
    InstalledAppInventoryResult inventory,
  ) {
    return _AppInsightsEvidence(
      inventory: inventory,
      usageByAppId: const <String, AppUsageEvidence>{},
      warnings: <String>[
        ...inventory.warnings,
        'App usage evidence is still loading.',
      ],
      isPartial: true,
    );
  }
}

class _AppInsightsAnalysisRequest {
  final FullDiskScanResult scanResult;
  final _AppInsightsEvidence evidence;
  final Map<String, String> environment;

  const _AppInsightsAnalysisRequest({
    required this.scanResult,
    required this.evidence,
    required this.environment,
  });
}

AppStorageReport _analyzeAppInsightsInBackground(
  _AppInsightsAnalysisRequest request,
) {
  return const AppStorageAnalyzer().analyze(
    root: request.scanResult.root,
    scanResult: request.scanResult,
    apps: request.evidence.inventory.apps,
    usageByAppId: request.evidence.usageByAppId,
    inventoryWarnings: request.evidence.warnings,
    inventoryIsPartial: request.evidence.isPartial,
    environment: request.environment,
  );
}

/// Returns the canonical root used by the full-disk scan cache.
///
/// Drive pickers can return either `C:` or a slash-terminated variant. The
/// service only treats the latter as a drive-root scan, so callers must use
/// this form for both cache lookup and scan execution.
@visibleForTesting
String normalizeCleanerDriveRoot(String drivePath) {
  final normalized = drivePath.trim().replaceAll('/', '\\');
  final rootMatch = RegExp(r'^([A-Za-z]):\\*$').firstMatch(normalized);
  if (rootMatch == null) return normalized;
  return '${rootMatch.group(1)!.toUpperCase()}:\\';
}

class _CbAgentCleanerScreenState extends State<CbAgentCleanerScreen> {
  final DiskCleanerService _service = DiskCleanerService.instance;
  late final CleanerScanCoordinator _scanCoordinator;
  final WindowsAppInventoryService _appInventoryService =
      WindowsAppInventoryService();
  final AppStorageAnalyzer _appStorageAnalyzer = const AppStorageAnalyzer();

  OutlinedBorder get _cleanerButtonShape =>
      ChipTheme.of(context).shape ?? const StadiumBorder();

  _Phase _phase = _Phase.setup;

  // Setup
  List<DriveSpace> _drives = [];
  String? _selectedDrive;
  String? _appInsightsDrive;
  bool _aiAvailable = false;

  /// Last completed scan per drive, keyed by [_normalizedDriveKey]. Drives the
  /// "previous scan" card on the setup screen; purely informational.
  final Map<String, CleanerLastScanSummary> _lastScanSummaries =
      <String, CleanerLastScanSummary>{};

  // Scan progress
  /// Full-disk progress is hot UI state. Keep it outside the screen's main
  /// rebuild path so a progress tick does not rebuild the tree, pie chart, and
  /// all of the Cleaner controls.
  final ValueNotifier<FullDiskScanProgress?> _diskProgressListenable =
      ValueNotifier<FullDiskScanProgress?>(null);
  bool _isScanningFullDisk = false;
  int _diskScanGeneration = 0;
  int _appInsightsGeneration = 0;
  Timer? _diskProgressContextTimer;
  static const Duration _diskProgressContextThrottle =
      Duration(milliseconds: 250);

  // Cleanup progress
  bool _isCleaningJunk = false;
  bool _isQuickCleaning = false;
  // Hot progress data lives in a ValueNotifier so only the progress bar
  // rebuilds during cleanup. Calling setState on every progress tick used
  // to rebuild the entire 2900-line screen — including the disk tree and
  // pie chart — and the bar appeared to stutter because each rebuild
  // costs more than the 16ms frame budget. Now the tree/pie are static
  // during cleanup, and only this notifier-driven section repaints.
  final ValueNotifier<_CleanProgressSnapshot> _cleanProgress =
      ValueNotifier<_CleanProgressSnapshot>(const _CleanProgressSnapshot());
  DateTime _lastCleanProgressUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _cleanProgressUiThrottle = Duration(milliseconds: 80);

  // Pending confirmation before clean
  List<JunkItem> _pendingCleanItems = [];
  int _pendingCleanBytes = 0;
  _CleanDeleteMode _selectedCleanMode = _CleanDeleteMode.recycleBin;

  // Cleaned phase data
  List<JunkItem> _cleanedItems = [];
  int _cleanedFreedBytes = 0;
  int _cleanedFailureCount = 0;
  int _cleanedSkippedInUseCount = 0;
  int _cleanedSkippedByUserCount = 0;
  int _lastCleanSuccessCount = 0;

  /// Free space on the cleaned drive immediately before and after the run, so
  /// the cleaned screen can show the change rather than just a freed total.
  int? _freeBytesBeforeClean;
  int? _freeBytesAfterClean;
  bool _lastCleanWasPermanent = false;
  bool _skipAllDeleteFailures = false;
  bool _isPermanentDeleting = false;
  int _permanentDone = 0;
  int _permanentTotal = 0;

  // Results
  DiskTreeNode? _rootNode;
  DiskTreeNode? _aggregateCacheRoot;
  int _cachedJunkBytes = 0;
  int _cachedCleanableCount = 0;
  DiskTreeNode? _selectedNode; // node shown in pie chart
  DiskTreeNode? _chartNode;
  Timer? _chartUpdateTimer;
  final Set<DiskTreeNode> _selectedTreeTargets = <DiskTreeNode>{};
  final Set<String> _selectedTreePaths = <String>{};
  final Set<String> _reviewVisibleTreePaths = <String>{};
  final ValueNotifier<Set<String>> _selectedTreePathListenable =
      ValueNotifier<Set<String>>(const <String>{});
  final ValueNotifier<String?> _focusedTreePathListenable =
      ValueNotifier<String?>(null);
  String? _selectionAnchorPath;
  String? _publishedCleanerContextTabId;
  bool _showCleanableOnly = false;
  _TreePreset _activePreset = _TreePreset.none;

  /// Memoised [_matchesPresetSubtree] results for the current (root, preset).
  final Map<DiskTreeNode, bool> _presetMatchCache = <DiskTreeNode, bool>{};

  static const int _largeFileThresholdBytes = 1024 * 1024 * 1024;
  static const int _installerThresholdBytes = 50 * 1024 * 1024;
  static const Set<String> _installerExtensions = <String>{
    '.msi',
    '.exe',
    '.iso',
    '.msix',
    '.appx',
    '.msu',
    '.cab',
  };
  static const Set<String> _logAndCacheCategoryIds = <String>{
    'windows_temp',
    'browser_cache',
    'thumbnail_cache',
    'app_cache',
    'crash_dumps_logs',
    'dev_cache',
  };
  bool _showGrowthOnly = false;
  bool _reviewMode = false; // when true, tree shows only selected items
  OldLargeEvidenceFilter _oldLargeEvidenceFilter = OldLargeEvidenceFilter.all;
  bool _oldLargeEvidenceExpanded = true;
  bool _isRefreshingNode = false;
  bool _isShowingCachedDiskScan = false;
  late final CleanerAppInsightsCubit _appInsightsCubit;
  StreamSubscription<CleanerAppInsightsState>? _appInsightsStateSub;
  AppStorageReport? _appStorageReport;
  FullDiskScanResult? _lastDiskScanResult;
  List<CleanerFolderGrowth> _recentFolderGrowth = const <CleanerFolderGrowth>[];
  FullDiskScanResult? _appInsightsScanResult;
  bool _isScanningAppInsights = false;
  final ValueNotifier<FullDiskScanProgress?> _appInsightsProgressListenable =
      ValueNotifier<FullDiskScanProgress?>(null);
  _CleanerSubFeature _activeSubFeature = _CleanerSubFeature.diskCleaner;
  final ValueNotifier<_CleanerSubFeature> _subFeatureListenable =
      ValueNotifier<_CleanerSubFeature>(_CleanerSubFeature.diskCleaner);
  bool _appInsightsSharedWithAgent = false;

  // Agent activity (when CB Agent triggers scan_disk_junk from AI panel)
  StreamSubscription<DiskCleanerAgentActivity>? _agentActivitySub;
  bool _agentScanning = false;
  String _agentStatus = '';
  int _agentItemsFound = 0;
  int _agentBytesFound = 0;
  String _agentCurrentPath = '';

  /// Scroll controller for the flat tree list. Needed so keyboard navigation
  /// can keep the focused row on screen; rows use a fixed 28px extent.
  final ScrollController _treeScrollController = ScrollController();

  /// Scroll controller for the old-large evidence list.
  ///
  /// This list has its own scrollbar and must not fall back to the page's
  /// primary controller, which may not have a position attached while the
  /// results layout is being built.
  final ScrollController _oldLargeItemsScrollController = ScrollController();
  static const double _treeRowExtent = 28;

  final FocusNode _resultsFocusNode = FocusNode(debugLabel: 'cbCleanerResults');
  final FocusNode _appsFocusNode = FocusNode(debugLabel: 'cbCleanerApps');

  @override
  void initState() {
    super.initState();
    _scanCoordinator = CleanerScanCoordinator(
      cachedResultFor: _service.cachedFullScanResult,
      startFullDiskScan: (drivePath) =>
          _service.scanFullDisk(drivePath: drivePath),
    );
    _appInsightsCubit = CleanerAppInsightsCubit();
    _appInsightsStateSub = _appInsightsCubit.stream.listen((state) {
      if (!mounted) return;
      _publishCleanerScanContext();
    });
    _loadSetup();
    _agentActivitySub = _service.agentActivityStream.listen(_onAgentActivity);
  }

  @override
  void dispose() {
    if (_isScanningFullDisk || _isScanningAppInsights) {
      _service.cancelFullDiskScan();
    }
    _diskScanGeneration++;
    _appInsightsGeneration++;
    _agentActivitySub?.cancel();
    _appInsightsStateSub?.cancel();
    _appInsightsCubit.close();
    if (_publishedCleanerContextTabId != null) {
      _service.clearCleanerScanContext(_publishedCleanerContextTabId!);
    }
    _chartUpdateTimer?.cancel();
    _selectedTreePathListenable.dispose();
    _focusedTreePathListenable.dispose();
    _cancelDiskProgressContextPublication();
    _diskProgressListenable.dispose();
    _appInsightsProgressListenable.dispose();
    _subFeatureListenable.dispose();
    _cleanProgress.dispose();
    _treeScrollController.dispose();
    _oldLargeItemsScrollController.dispose();
    _resultsFocusNode.dispose();
    _appsFocusNode.dispose();
    super.dispose();
  }

  void _onAgentActivity(DiskCleanerAgentActivity event) {
    if (!mounted) return;
    // Only apply when this screen is in the active tab AND the AI panel
    // is open inside the SAME tab as the one that triggered the scan.
    final tabState = context.read<TabManagerBloc>().state;
    final activeTab = tabState.activeTab;
    if (activeTab == null) return;
    if (activeTab.path != '#cb-agent-cleaner') return;

    final controller = AiPanelScope.maybeOf(context);
    final panelTabId = controller?.ownerTabId;
    if (panelTabId == null || panelTabId != activeTab.id) return;
    if (event.ownerTabId != null && event.ownerTabId != activeTab.id) {
      return;
    }

    switch (event.type) {
      case DiskCleanerAgentActivityType.scanStarted:
        setState(() {
          _agentScanning = true;
          _agentStatus = event.message;
          _agentItemsFound = 0;
          _agentBytesFound = 0;
          _agentCurrentPath = '';
        });
        _publishCleanerScanContext();
        break;
      case DiskCleanerAgentActivityType.scanProgress:
        setState(() {
          _agentScanning = true;
          _agentStatus = event.message;
          _agentItemsFound = event.itemsFound;
          _agentBytesFound = event.bytesFound;
          _agentCurrentPath = event.currentPath;
        });
        _publishCleanerScanContext();
        break;
      case DiskCleanerAgentActivityType.scanDone:
        setState(() {
          _agentScanning = false;
          _agentStatus = '';
          _agentCurrentPath = '';
        });
        _publishCleanerScanContext();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .diskCleanerAgentFoundJunk(
                    event.itemsFound, _fmt(event.bytesFound))),
          ),
        );
        break;
      case DiskCleanerAgentActivityType.scanFailed:
        setState(() {
          _agentScanning = false;
          _agentStatus = '';
          _agentCurrentPath = '';
        });
        _publishCleanerScanContext();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(event.message)),
        );
        break;
    }
  }

  Future<void> _loadSetup() async {
    if (kCbE2E) {
      _drives = const [
        DriveSpace(
          path: 'C:\\',
          label: 'System',
          totalBytes: 512 * 1024 * 1024 * 1024,
          freeBytes: 184 * 1024 * 1024 * 1024,
        ),
        DriveSpace(
          path: 'D:\\',
          label: 'Data',
          totalBytes: 1024 * 1024 * 1024 * 1024,
          freeBytes: 640 * 1024 * 1024 * 1024,
        ),
      ];
      _selectedDrive = _drives.first.path;
      _appInsightsDrive = _defaultDrivePath(_drives);
      _aiAvailable = true;
      _seedE2EResultsDemo();
      if (mounted) setState(() {});
      return;
    }

    _drives = await _service.getDriveSpace();
    _selectedDrive = _mostPressuredDrivePath(_drives);
    _appInsightsDrive = _defaultDrivePath(_drives);
    await _loadLastScanSummaries();
    try {
      final providers =
          await GetIt.instance<AiProviderService>().getEnabledProviders();
      _aiAvailable = providers.isNotEmpty;
    } catch (_) {}
    if (mounted) setState(() {});
    if (_activeSubFeature == _CleanerSubFeature.appInsights &&
        _appInsightsCubit.state.status == CleanerAppInsightsStatus.idle) {
      unawaited(_startAppInsightsScan());
    }
  }

  Future<void> _loadLastScanSummaries() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final service = CleanerLastScanService(preferences);
      for (final drive in _drives) {
        final summary = service.read(drive.path);
        if (summary != null) {
          _lastScanSummaries[_normalizedDriveKey(drive.path)] = summary;
        }
      }
    } catch (error) {
      debugPrint('Unable to read Cleaner last scan summaries: $error');
    }
  }

  CleanerLastScanSummary? _lastScanFor(String? drivePath) {
    if (drivePath == null) return null;
    return _lastScanSummaries[_normalizedDriveKey(drivePath)];
  }

  /// Fraction of the drive already in use, 0..1. Used to colour the capacity
  /// bars so the drive that actually needs attention is obvious at a glance.
  static double _driveUsedFraction(DriveSpace drive) {
    if (drive.totalBytes <= 0) return 0;
    return (drive.usedBytes / drive.totalBytes).clamp(0.0, 1.0);
  }

  /// Picks the drive under the most space pressure rather than always
  /// defaulting to the system drive — that is almost always the one the user
  /// opened the Cleaner for.
  String? _mostPressuredDrivePath(List<DriveSpace> drives) {
    if (drives.isEmpty) return null;
    DriveSpace? best;
    var bestFraction = -1.0;
    for (final drive in drives) {
      if (drive.totalBytes <= 0) continue;
      final fraction = _driveUsedFraction(drive);
      if (fraction > bestFraction) {
        bestFraction = fraction;
        best = drive;
      }
    }
    // Only override the system-drive default when a drive is genuinely tight.
    if (best != null && bestFraction >= 0.85) return best.path;
    return _defaultDrivePath(drives);
  }

  String? _defaultDrivePath(List<DriveSpace> drives) {
    if (drives.isEmpty) return null;
    final systemDrive = Platform.environment['SystemDrive'];
    if (systemDrive != null && systemDrive.isNotEmpty) {
      final normalized = systemDrive.endsWith('\\')
          ? systemDrive.toUpperCase()
          : '$systemDrive\\'.toUpperCase();
      for (final drive in drives) {
        final path = drive.path.endsWith('\\')
            ? drive.path.toUpperCase()
            : '${drive.path}\\'.toUpperCase();
        if (path == normalized) return drive.path;
      }
    }
    return drives.first.path;
  }

  Map<String, String> get _appInsightsEnvironment {
    if (!kCbE2E) return Platform.environment;
    return const <String, String>{
      'SYSTEMDRIVE': r'C:',
      'LOCALAPPDATA': r'C:\Users\ngtan\AppData\Local',
      'APPDATA': r'C:\Users\ngtan\AppData\Roaming',
      'PROGRAMDATA': r'C:\ProgramData',
    };
  }

  void _seedE2EResultsDemo() {
    final root = DiskTreeNode(
      name: 'C:\\',
      fullPath: 'C:\\',
      sizeBytes: 128 * 1024 * 1024 * 1024,
      fileCount: 186420,
      isExpanded: true,
      children: [
        DiskTreeNode(
          name: 'Users',
          fullPath: 'C:\\Users',
          sizeBytes: 54 * 1024 * 1024 * 1024,
          fileCount: 84210,
          isExpanded: true,
          children: [
            DiskTreeNode(
              name: 'ngtan',
              fullPath: 'C:\\Users\\ngtan',
              sizeBytes: 37 * 1024 * 1024 * 1024,
              fileCount: 51240,
              isExpanded: true,
              children: [
                DiskTreeNode(
                  name: 'AppData',
                  fullPath: 'C:\\Users\\ngtan\\AppData',
                  sizeBytes: 14 * 1024 * 1024 * 1024,
                  fileCount: 26100,
                  isExpanded: true,
                  children: [
                    DiskTreeNode(
                      name: 'Temp',
                      fullPath: 'C:\\Users\\ngtan\\AppData\\Local\\Temp',
                      sizeBytes: 6 * 1024 * 1024 * 1024,
                      fileCount: 14820,
                      junkCategoryId: 'windows_temp',
                    ),
                    DiskTreeNode(
                      name: 'GPUCache',
                      fullPath:
                          'C:\\Users\\ngtan\\AppData\\Local\\Google\\Chrome\\User Data\\Default\\GPUCache',
                      sizeBytes: 1200 * 1024 * 1024,
                      fileCount: 3420,
                      junkCategoryId: 'browser_cache',
                    ),
                    DiskTreeNode(
                      name: 'Code Cache',
                      fullPath:
                          'C:\\Users\\ngtan\\AppData\\Local\\Microsoft\\Edge\\User Data\\Default\\Code Cache',
                      sizeBytes: 860 * 1024 * 1024,
                      fileCount: 1880,
                      junkCategoryId: 'browser_cache',
                    ),
                  ],
                ),
                DiskTreeNode(
                  name: 'Downloads',
                  fullPath: 'C:\\Users\\ngtan\\Downloads',
                  sizeBytes: 8 * 1024 * 1024 * 1024,
                  fileCount: 2740,
                ),
              ],
            ),
          ],
        ),
        DiskTreeNode(
          name: 'Windows',
          fullPath: 'C:\\Windows',
          sizeBytes: 29 * 1024 * 1024 * 1024,
          fileCount: 62100,
          isExpanded: true,
          children: [
            DiskTreeNode(
              name: 'SoftwareDistribution',
              fullPath: 'C:\\Windows\\SoftwareDistribution\\Download',
              sizeBytes: 4200 * 1024 * 1024,
              fileCount: 940,
              junkCategoryId: 'windows_update_cache',
            ),
            DiskTreeNode(
              name: 'Prefetch',
              fullPath: 'C:\\Windows\\Prefetch',
              sizeBytes: 380 * 1024 * 1024,
              fileCount: 512,
              junkCategoryId: 'prefetch',
            ),
          ],
        ),
        DiskTreeNode(
          name: r'$Recycle.Bin',
          fullPath: r'C:\$Recycle.Bin',
          sizeBytes: 3100 * 1024 * 1024,
          fileCount: 126,
          junkCategoryId: 'recycle_bin',
        ),
      ],
    );

    final evaluatedAt = DateTime(2026, 8);
    final appReport = AppStorageReport(
      drivePath: r'C:\',
      generatedAt: evaluatedAt,
      isPartial: true,
      warnings: const <String>[
        'E2E fixture: one protected folder could not be measured.',
      ],
      apps: <AppStorageProfile>[
        AppStorageProfile(
          app: const InstalledAppInfo(
            id: 'win32:google-chrome',
            displayName: 'Google Chrome',
            publisher: 'Google LLC',
            version: '126.0',
            source: InstalledAppSource.win32,
            installLocation: r'C:\Program Files\Google\Chrome',
            displayIconPath:
                r'C:\Program Files\Google\Chrome\Application\chrome.exe',
          ),
          usage: AppUsageEvidence(
            lastOpenedAt: DateTime(2025, 12, 1),
            source: AppUsageSource.userAssist,
            confidence: UsageEvidenceConfidence.high,
          ),
          entries: const <AppStorageEntry>[
            AppStorageEntry(
              path:
                  r'C:\Users\ngtan\AppData\Local\Google\Chrome\User Data\Default\GPUCache',
              kind: AppStorageKind.cache,
              sizeBytes: 1200 * 1024 * 1024,
              measurementQuality: MeasurementQuality.measured,
              attributionConfidence: AttributionConfidence.confirmed,
              categoryId: 'browser_cache',
              isCleanable: true,
            ),
          ],
        ),
        const AppStorageProfile(
          app: InstalledAppInfo(
            id: 'win32:microsoft-edge',
            displayName: 'Microsoft Edge',
            publisher: 'Microsoft Corporation',
            version: '126.0',
            source: InstalledAppSource.win32,
            installLocation: r'C:\Program Files (x86)\Microsoft\Edge',
          ),
          entries: <AppStorageEntry>[
            AppStorageEntry(
              path:
                  r'C:\Users\ngtan\AppData\Local\Microsoft\Edge\User Data\Default\Code Cache',
              kind: AppStorageKind.cache,
              sizeBytes: 860 * 1024 * 1024,
              measurementQuality: MeasurementQuality.measured,
              attributionConfidence: AttributionConfidence.confirmed,
              categoryId: 'browser_cache',
              isCleanable: true,
            ),
          ],
        ),
        const AppStorageProfile(
          app: InstalledAppInfo(
            id: 'msix:spotifyab.spotifymusic_zpdnekdrzrea0',
            displayName: 'Spotify Music',
            publisher: 'Spotify AB',
            version: '1.2.40',
            source: InstalledAppSource.msix,
            packageFamilyName: 'SpotifyAB.SpotifyMusic_zpdnekdrzrea0',
            estimatedSizeBytes: 6200 * 1024 * 1024,
          ),
        ),
      ],
      sharedOrUnattributed: const <AppStorageEntry>[
        AppStorageEntry(
          path: r'C:\Users\ngtan\Downloads',
          kind: AppStorageKind.shared,
          sizeBytes: 8 * 1024 * 1024 * 1024,
          measurementQuality: MeasurementQuality.measured,
          attributionConfidence: AttributionConfidence.shared,
        ),
      ],
    );

    final scanResult = FullDiskScanResult(
      root: root,
      duration: Duration.zero,
    );

    setState(() {
      _phase = _Phase.results;
      _isScanningFullDisk = false;
      _rootNode = root;
      _selectedNode = root.children.first;
      _chartNode = root.children.first;
      _selectedTreeTargets.clear();
      _selectedTreePaths.clear();
      _publishTreeSelection();
      _selectionAnchorPath = root.children.first.fullPath;
      _showCleanableOnly = false;
      _showGrowthOnly = false;
      _cachedFlatRoot = null;
      _flatRowsValid = false;
      _appStorageReport = appReport;
      _lastDiskScanResult = scanResult;
      _appInsightsScanResult = scanResult;
      _recentFolderGrowth = const <CleanerFolderGrowth>[
        CleanerFolderGrowth(
          path: r'C:\Users\ngtan\Downloads',
          previousSizeBytes: 6 * 1024 * 1024 * 1024,
          currentSizeBytes: 8 * 1024 * 1024 * 1024,
        ),
        CleanerFolderGrowth(
          path:
              r'C:\Users\ngtan\AppData\Local\Google\Chrome\User Data\Default\GPUCache',
          previousSizeBytes: 500 * 1024 * 1024,
          currentSizeBytes: 1700 * 1024 * 1024,
        ),
      ];
    });
    _appInsightsCubit.setReport(appReport, evaluatedAt: evaluatedAt);
  }

  void _clearCleanupSelection(DiskTreeNode? root) {
    DiskTreeSelection.setAllCleanableChecked(root, false);
    for (final target in _selectedTreeTargets) {
      target.isSelectedForDeletion = false;
    }
    _selectedTreeTargets.clear();
    _selectedTreePaths.clear();
    _reviewVisibleTreePaths.clear();
    _pendingCleanItems = [];
    _pendingCleanBytes = 0;
    _reviewMode = false;
    _service.pendingCleanupItems = const <JunkItem>[];
    _service.pendingCleanupBytes = 0;
    _selectedTreePathListenable.value = const <String>{};
  }

  void _showCachedDiskScan(FullDiskScanResult result) {
    _diskScanGeneration++;
    _cancelDiskProgressContextPublication();
    _diskProgressListenable.value = null;
    _clearCleanupSelection(result.root);
    setState(() {
      _phase = _Phase.results;
      _isScanningFullDisk = false;
      _isShowingCachedDiskScan = true;
      _rootNode = result.root;
      _selectedNode = result.root;
      _chartNode = result.root;
      _aggregateCacheRoot = result.root;
      _cachedJunkBytes = result.junkBytes ?? result.root.junkBytes;
      _cachedCleanableCount =
          result.cleanableCount ?? _countCleanableNodes(result.root);
      _lastDiskScanResult = result;
      _selectionAnchorPath = null;
      _showCleanableOnly = false;
      _showGrowthOnly = false;
      _recentFolderGrowth = const <CleanerFolderGrowth>[];
      _cachedFlatRoot = null;
      _flatRowsValid = false;
      _appInsightsSharedWithAgent = false;
    });
    _publishTreeSelection();
  }

  Future<void> _startScan({bool forceRefresh = false}) async {
    if (_selectedDrive == null || _isScanningAppInsights) return;
    // Recover from a scan the service still considers active while this screen
    // is not tracking one (a previous run that failed, or a screen that was
    // disposed mid-scan). Without this the service rejects every new scan.
    if (_service.isFullScanning && !_isScanningFullDisk) {
      _service.cancelFullDiskScan();
    }
    final drive = _selectedDrive!;
    final driveRoot = normalizeCleanerDriveRoot(drive);
    if (!forceRefresh) {
      final cachedResult = _scanCoordinator.cachedSetupResult(driveRoot);
      if (cachedResult != null) {
        _showCachedDiskScan(cachedResult);
        return;
      }
    }
    final cachedResult = _scanCoordinator.cachedSetupResult(driveRoot);
    final cachedRoot = cachedResult?.root;
    final diskScanGeneration = ++_diskScanGeneration;
    _cancelDiskProgressContextPublication();
    _diskProgressListenable.value = null;
    _clearCleanupSelection(cachedRoot ?? _rootNode);
    setState(() {
      // Show the TreeSize layout immediately. The tree is populated when the
      // scan completes, while progress is shown inline in the same view.
      _phase = _Phase.results;
      _isScanningFullDisk = true;
      _isShowingCachedDiskScan = false;
      _rootNode = cachedRoot ??
          DiskTreeNode(
            name: driveRoot,
            fullPath: driveRoot,
            isExpanded: true,
          );
      _selectedNode = _rootNode;
      _chartNode = _rootNode;
      _selectedTreeTargets.clear();
      _selectedTreePaths.clear();
      _publishTreeSelection();
      _selectionAnchorPath = null;
      _appInsightsSharedWithAgent = false;
      _showGrowthOnly = false;
      _recentFolderGrowth = const <CleanerFolderGrowth>[];
    });

    try {
      final handle = await _scanCoordinator.forceRefresh(driveRoot);
      handle.progress.listen((p) {
        if (mounted && diskScanGeneration == _diskScanGeneration) {
          // Keep the visible root counters moving while the full tree is
          // still being built inside the isolate. The notifier below updates
          // only the progress-aware sections that display these counters.
          if (!p.isIncremental) {
            _rootNode?.sizeBytes = p.bytesScanned;
            _rootNode?.fileCount = p.filesScanned;
          }
          _diskProgressListenable.value = p;
          _scheduleDiskProgressContextPublication();
        }
      });
      handle.treeSnapshots.listen((root) {
        if (!mounted || diskScanGeneration != _diskScanGeneration) {
          return;
        }
        if (!identical(_rootNode, root)) {
          final expandedPaths = _collectExpandedPaths(_rootNode);
          _applyExpandedPaths(root, expandedPaths);
        }
        setState(() {
          _rootNode = root;
          _selectedNode = root;
          _chartNode = root;
          _selectedTreeTargets.clear();
          _selectedTreePaths.clear();
          _publishTreeSelection();
          _selectionAnchorPath = null;
          _cachedFlatRoot = null;
          _flatRowsValid = false;
        });
      });
      final result = await handle.future;
      if (mounted && diskScanGeneration == _diskScanGeneration) {
        _cancelDiskProgressContextPublication();
        // A clean cached completion returns the exact cached root instance.
        // It already has the current expansion state, so walking it just to
        // write the same booleans back can freeze the UI on large trees.
        if (!identical(_rootNode, result.root)) {
          final expandedPaths = _collectExpandedPaths(_rootNode);
          _applyExpandedPaths(result.root, expandedPaths);
        }
        setState(() {
          _isScanningFullDisk = false;
          _isShowingCachedDiskScan = false;
          _rootNode = result.root;
          _selectedNode = result.root;
          _chartNode = result.root;
          _phase = _Phase.results;
          _selectedTreeTargets.clear();
          _selectedTreePaths.clear();
          _publishTreeSelection();
          _selectionAnchorPath = null;
          _cachedFlatRoot = null;
          _flatRowsValid = false;
          _lastDiskScanResult = result;
          _aggregateCacheRoot = result.root;
          _cachedJunkBytes = result.junkBytes ?? result.root.junkBytes;
          _cachedCleanableCount =
              result.cleanableCount ?? _countCleanableNodes(result.root);
        });
        _diskProgressListenable.value = null;
        _publishCleanerScanContext();
        unawaited(_updateFolderGrowthHistory(result, diskScanGeneration));
        unawaited(_recordLastScanSummary(drive, result));
        if (_activeSubFeature == _CleanerSubFeature.appInsights &&
            _appStorageReport == null &&
            !_isScanningAppInsights) {
          unawaited(_startAppInsightsScan());
        }
      }
    } catch (e) {
      if (mounted && diskScanGeneration == _diskScanGeneration) {
        _cancelDiskProgressContextPublication();
        _diskProgressListenable.value = null;
        setState(() {
          _isScanningFullDisk = false;
          _isShowingCachedDiskScan = false;
          _phase = _Phase.setup;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .diskCleanerScanFailedMsg('$e'))),
        );
        if (_activeSubFeature == _CleanerSubFeature.appInsights &&
            _appStorageReport == null &&
            !_isScanningAppInsights) {
          unawaited(_startAppInsightsScan());
        }
      }
    }
  }

  void _returnToDriveSetup() {
    if (_isScanningFullDisk) {
      _service.cancelFullDiskScan();
      _diskScanGeneration++;
    }
    _cancelDiskProgressContextPublication();
    _diskProgressListenable.value = null;
    _appInsightsSharedWithAgent = false;
    setState(() {
      _phase = _Phase.setup;
      _isScanningFullDisk = false;
      _isShowingCachedDiskScan = false;
      _reviewMode = false;
      _rootNode = null;
      _selectedNode = null;
      _chartNode = null;
      _selectedTreeTargets.clear();
      _selectedTreePaths.clear();
      _publishTreeSelection();
      _selectionAnchorPath = null;
      _cachedFlatRoot = null;
      _flatRowsValid = false;
    });
  }

  /// Persists a one-line summary of this scan so the setup screen can show
  /// what the previous run found instead of an empty placeholder.
  Future<void> _recordLastScanSummary(
    String drivePath,
    FullDiskScanResult result,
  ) async {
    try {
      final root = result.root;
      DriveSpace? drive;
      for (final candidate in _drives) {
        if (candidate.path == drivePath) {
          drive = candidate;
          break;
        }
      }
      final summary = CleanerLastScanSummary(
        drivePath: drivePath,
        scannedAt: DateTime.now(),
        totalBytes: root.sizeBytes,
        fileCount: root.fileCount,
        junkBytes: result.junkBytes ?? root.junkBytes,
        cleanableCount: result.cleanableCount ?? _countCleanableNodes(root),
        freeBytes: drive?.freeBytes ?? 0,
      );
      final preferences = await SharedPreferences.getInstance();
      await CleanerLastScanService(preferences).write(summary);
      if (!mounted) return;
      setState(
          () => _lastScanSummaries[_normalizedDriveKey(drivePath)] = summary);
    } catch (error) {
      debugPrint('Unable to record Cleaner last scan summary: $error');
    }
  }

  static String _normalizedDriveKey(String drivePath) {
    var normalized = drivePath.trim().toUpperCase();
    while (normalized.endsWith(r'\')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<void> _updateFolderGrowthHistory(
    FullDiskScanResult result,
    int diskScanGeneration,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final comparison =
          await CleanerGrowthHistoryService(preferences).compareAndStore(
        result,
      );
      if (!mounted || diskScanGeneration != _diskScanGeneration) return;
      setState(() {
        _recentFolderGrowth = comparison.folders;
        if (_showGrowthOnly && _recentFolderGrowth.isEmpty) {
          _showGrowthOnly = false;
        } else if (_showGrowthOnly && _rootNode != null) {
          _expandGrowthAncestors(_rootNode!);
        }
        _flatRowsValid = false;
      });
    } catch (error) {
      debugPrint('Unable to update Cleaner folder growth history: $error');
    }
  }

  Future<InstalledAppInventoryResult> _loadInstalledAppInventory({
    void Function(InstalledAppInventoryResult snapshot)? onSnapshot,
  }) async {
    try {
      return await _appInventoryService.loadInventory(onSnapshot: onSnapshot);
    } catch (error) {
      return InstalledAppInventoryResult(
        apps: const <InstalledAppInfo>[],
        warnings: <String>['Installed app inventory failed: $error'],
        isPartial: true,
      );
    }
  }

  Future<void> _startAppInsightsScan({bool forceDiskScan = false}) async {
    if (_isScanningAppInsights || _isScanningFullDisk) return;
    final scanDrive = _appInsightsDrive ?? _defaultDrivePath(_drives);
    if (scanDrive == null) return;

    final generation = ++_appInsightsGeneration;
    late final Future<InstalledAppInventoryResult> inventoryFuture;
    late final Future<_AppInsightsEvidence> evidenceFuture;
    var latestSnapshot = DiskTreeNode(
      name: scanDrive,
      fullPath: scanDrive,
      isExpanded: true,
    );
    _AppInsightsEvidence? progressiveEvidence;
    Timer? progressiveTimer;
    var progressiveBusy = false;
    var progressiveDirty = false;
    var finalizing = false;

    Future<void> publishProgressiveReport() async {
      if (finalizing || progressiveBusy) return;
      final evidence = progressiveEvidence;
      if (evidence == null) return;
      final snapshot = latestSnapshot;
      progressiveBusy = true;
      progressiveDirty = false;
      try {
        final report = await _analyzeAppInsightsReport(
          result: FullDiskScanResult(
            root: snapshot,
            duration: Duration.zero,
          ),
          evidence: evidence,
          scanInProgress: true,
        );
        if (!mounted || finalizing || generation != _appInsightsGeneration) {
          return;
        }
        _publishAppInsightsReport(report);
      } finally {
        progressiveBusy = false;
        if (progressiveDirty && !finalizing) {
          progressiveTimer = Timer(
            const Duration(milliseconds: 350),
            () => unawaited(publishProgressiveReport()),
          );
        }
      }
    }

    void scheduleProgressiveReport({bool immediate = false}) {
      if (finalizing || progressiveEvidence == null) return;
      progressiveDirty = true;
      if (progressiveBusy || (progressiveTimer?.isActive ?? false)) return;
      progressiveTimer = Timer(
        immediate ? Duration.zero : const Duration(milliseconds: 550),
        () => unawaited(publishProgressiveReport()),
      );
    }

    _appInsightsSharedWithAgent = false;
    _appInsightsProgressListenable.value = null;
    _appInsightsCubit.setLoading();
    setState(() {
      _isScanningAppInsights = true;
      _appStorageReport = null;
    });
    _publishCleanerScanContext();

    inventoryFuture = _loadInstalledAppInventory(
      onSnapshot: (inventory) {
        if (!mounted || generation != _appInsightsGeneration) return;
        progressiveEvidence = _AppInsightsEvidence.inventoryOnly(inventory);
        scheduleProgressiveReport(immediate: true);
      },
    );
    evidenceFuture = inventoryFuture.then(_loadAppInsightsEvidence);

    try {
      var result = _lastDiskScanResult;
      final canReuseDiskScan = !forceDiskScan &&
          result != null &&
          _isSameDriveRoot(result.root.fullPath, scanDrive);

      if (canReuseDiskScan) {
        final inventory = await inventoryFuture;
        if (!mounted || generation != _appInsightsGeneration) return;
        progressiveEvidence = _AppInsightsEvidence.inventoryOnly(inventory);
        latestSnapshot = result.root;
        await publishProgressiveReport();
      } else {
        unawaited(
          inventoryFuture.then((inventory) {
            if (!mounted || generation != _appInsightsGeneration) return;
            progressiveEvidence = _AppInsightsEvidence.inventoryOnly(inventory);
            scheduleProgressiveReport(immediate: true);
          }),
        );
        unawaited(
          evidenceFuture.then((evidence) {
            if (!mounted || generation != _appInsightsGeneration) return;
            progressiveEvidence = evidence;
            scheduleProgressiveReport(immediate: true);
          }),
        );

        final handle = await _service.scanFullDisk(drivePath: scanDrive);
        handle.progress.listen((progress) {
          if (!mounted || generation != _appInsightsGeneration) return;
          _appInsightsProgressListenable.value = progress;
        });
        handle.treeSnapshots.listen((root) {
          if (!mounted || generation != _appInsightsGeneration) return;
          latestSnapshot = root;
          scheduleProgressiveReport();
        });
        result = await handle.future;
        if (!mounted || generation != _appInsightsGeneration) return;
        // Current scan workers apply junk rules and calculate aggregates
        // before returning. Keep the fallback for older fixtures/results that
        // predate those fields so App Insights remains safe in compatibility
        // tests and cached sessions.
        if (result.junkBytes == null || result.cleanableCount == null) {
          _service.markJunkNodes(result.root);
        }
      }

      if (!mounted || generation != _appInsightsGeneration) {
        return;
      }
      finalizing = true;
      progressiveTimer?.cancel();
      _appInsightsScanResult = result;
      final evidence = await evidenceFuture;
      if (!mounted || generation != _appInsightsGeneration) return;
      final report = await _analyzeAppInsightsReport(
        result: result,
        evidence: evidence,
      );
      if (!mounted || generation != _appInsightsGeneration) return;
      _publishAppInsightsReport(report);
    } catch (error) {
      finalizing = true;
      progressiveTimer?.cancel();
      if (!mounted || generation != _appInsightsGeneration) return;
      _appInsightsCubit.setError('$error');
    } finally {
      finalizing = true;
      progressiveTimer?.cancel();
      if (mounted && generation == _appInsightsGeneration) {
        setState(() => _isScanningAppInsights = false);
        _appInsightsProgressListenable.value = null;
      }
    }
  }

  void _cancelAppInsightsScan() {
    if (!_isScanningAppInsights) return;
    _service.cancelFullDiskScan();
    _appInsightsGeneration++;
    _appInsightsProgressListenable.value = null;
    _appInsightsSharedWithAgent = false;
    _appInsightsCubit.clear();
    setState(() => _isScanningAppInsights = false);
    _publishCleanerScanContext();
  }

  bool _isSameDriveRoot(String left, String right) {
    final normalizedLeft =
        AppStorageAnalyzer.normalizeWindowsPath(left).toUpperCase();
    final normalizedRight =
        AppStorageAnalyzer.normalizeWindowsPath(right).toUpperCase();
    return normalizedLeft == normalizedRight;
  }

  Future<_AppInsightsEvidence> _loadAppInsightsEvidence(
    InstalledAppInventoryResult inventory,
  ) async {
    var usageByAppId = const <String, AppUsageEvidence>{};
    var usageIsPartial = false;
    final warnings = <String>[...inventory.warnings];
    try {
      usageByAppId = await _appInventoryService.loadUsageEvidence(
        inventory.apps,
      );
      warnings.addAll(_appInventoryService.lastUsageWarnings);
      usageIsPartial = _appInventoryService.lastUsageWarnings.isNotEmpty;
    } catch (error) {
      usageIsPartial = true;
      warnings.add('App usage evidence could not be read: $error');
    }
    return _AppInsightsEvidence(
      inventory: inventory,
      usageByAppId: usageByAppId,
      warnings: warnings,
      isPartial: inventory.isPartial || usageIsPartial,
    );
  }

  Future<AppStorageReport> _analyzeAppInsightsReport({
    required FullDiskScanResult result,
    required _AppInsightsEvidence evidence,
    bool scanInProgress = false,
  }) {
    final effectiveResult = scanInProgress
        ? FullDiskScanResult(
            root: result.root,
            duration: result.duration,
            inaccessible: result.inaccessible,
            coverageIssues: <FullDiskScanCoverageIssue>[
              ...result.coverageIssues,
              FullDiskScanCoverageIssue(
                path: result.root.fullPath,
                reason: FullDiskScanCoverageIssueReason.scanInProgress,
                detail: 'Progressive App Insights snapshot',
              ),
            ],
          )
        : result;
    return compute(
      _analyzeAppInsightsInBackground,
      _AppInsightsAnalysisRequest(
        scanResult: effectiveResult,
        evidence: evidence,
        environment: Map<String, String>.from(_appInsightsEnvironment),
      ),
    );
  }

  void _publishAppInsightsReport(AppStorageReport report) {
    _appStorageReport = report;
    _appInsightsCubit.setReport(report);
    _publishCleanerScanContext();
  }

  void _openAppStorageFolder(AppStorageEntry entry) {
    EntityOpenActions.openInNewTab(
      context,
      sourcePath: entry.path,
    );
  }

  Future<void> _manageInstalledApp(InstalledAppInfo app) async {
    final packageFamilyName = app.packageFamilyName?.trim();
    final appUri = app.source == InstalledAppSource.msix &&
            packageFamilyName != null &&
            packageFamilyName.isNotEmpty
        ? Uri.parse(
            'ms-settings:appsfeatures-app?PFN='
            '${Uri.encodeQueryComponent(packageFamilyName)}',
          )
        : Uri.parse('ms-settings:appsfeatures');
    try {
      if (await launchUrl(appUri, mode: LaunchMode.externalApplication)) {
        return;
      }
      if (appUri.toString() != 'ms-settings:appsfeatures') {
        await launchUrl(
          Uri.parse('ms-settings:appsfeatures'),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${app.displayName}: $error')),
      );
    }
  }

  void _askAgentAboutApp(AppStorageProfile profile) {
    _appInsightsCubit.selectApp(profile.app.id);
    _askAiAboutApps();
  }

  void _reviewAppCleanableData(AppStorageProfile profile) {
    final appScanResult = _appInsightsScanResult;
    final root = appScanResult?.root;
    if (root == null) return;

    final candidates = _appStorageAnalyzer.buildCleanableReviewItems(
      profile,
      environment: _appInsightsEnvironment,
    );
    final safeItems = <JunkItem>[];
    final safeNodes = <DiskTreeNode>[];
    final acceptedPaths = <String>[];
    for (final candidate in candidates) {
      final node = _findTreeNodeByExactPath(root, candidate.path);
      if (node == null ||
          !node.isJunk ||
          node.junkCategoryId != candidate.categoryId) {
        continue;
      }
      final normalizedPath =
          AppStorageAnalyzer.normalizeWindowsPath(candidate.path);
      if (acceptedPaths.any(
        (parent) => AppStorageAnalyzer.isSameOrDescendant(
          normalizedPath,
          parent,
        ),
      )) {
        continue;
      }
      acceptedPaths.add(normalizedPath);
      safeNodes.add(node);
      safeItems.add(
        JunkItem(
          path: candidate.path,
          sizeBytes: node.sizeBytes,
          categoryId: candidate.categoryId,
          isContainerOnly: candidate.isContainerOnly,
          isUserSelected: false,
        ),
      );
    }

    if (safeItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.cleanerAppsNoStorageDetails),
        ),
      );
      return;
    }

    void clearSelection(DiskTreeNode node) {
      node.isSelectedForDeletion = false;
      for (final child in node.children) {
        clearSelection(child);
      }
    }

    clearSelection(root);
    _selectedTreeTargets.clear();
    _selectedTreePaths.clear();
    for (final node in safeNodes) {
      node.isSelectedForDeletion = true;
      _selectedTreeTargets.add(node);
      _selectedTreePaths.add(node.fullPath);
    }
    root.invalidateSelectionCache();
    _setSubFeature(_CleanerSubFeature.diskCleaner);
    setState(() {
      _phase = _Phase.results;
      _rootNode = root;
      _lastDiskScanResult = appScanResult;
      _selectedNode = safeNodes.first;
      _chartNode = safeNodes.first;
      _selectionAnchorPath = safeNodes.first.fullPath;
      _flatRowsValid = false;
    });
    _rebuildReviewVisibleTreePaths();
    _publishTreeSelection();
    _enterReviewMode(exactCleanableItems: safeItems);
  }

  DiskTreeNode? _findTreeNodeByExactPath(
    DiskTreeNode root,
    String path,
  ) {
    final target = AppStorageAnalyzer.normalizeWindowsPath(path);
    final stack = <DiskTreeNode>[root];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (AppStorageAnalyzer.normalizeWindowsPath(node.fullPath) == target) {
        return node;
      }
      stack.addAll(node.children);
    }
    return null;
  }

  void _openAiPanel() {
    if (_activeSubFeature == _CleanerSubFeature.appInsights) {
      _askAiAboutApps();
      return;
    }
    _sendToAi(_buildAiSummary());
  }

  void _askAiAboutApps() {
    final report = _appStorageReport;
    if (report == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.cleanerAppsUnavailable),
        ),
      );
      return;
    }

    _appInsightsSharedWithAgent = true;
    _publishCleanerScanContext();
    final selectedAppId = _appInsightsCubit.state.selectedAppId;
    final message = StringBuffer()
      ..writeln(
        'Please call get_current_app_storage to review the App Insights '
        'report I explicitly shared from CB Agent Cleaner.',
      )
      ..writeln(
        'Summarize large apps, apps not seen recently, and safely reviewable '
        'cache. Treat missing last-opened evidence as unknown.',
      );
    if (selectedAppId != null) {
      message.writeln('The currently selected app id is $selectedAppId.');
    }
    _sendToAi(message.toString());
  }

  void _askAiAboutNode(DiskTreeNode node) {
    final l10n = AppLocalizations.of(context)!;
    final msg = StringBuffer();
    msg.writeln(l10n.diskCleanerAiDeleteAnalysisIntro);
    msg.writeln('${l10n.diskCleanerAiLabelPath}: ${node.fullPath}');
    msg.writeln(
      '${l10n.diskCleanerAiLabelType}: '
      '${node.isFile ? l10n.diskCleanerAiTypeFile : l10n.diskCleanerAiTypeFolder}',
    );
    msg.writeln('${l10n.diskCleanerAiLabelName}: ${node.name}');
    msg.writeln('${l10n.diskCleanerAiLabelSize}: ${_fmt(node.sizeBytes)}');
    msg.writeln('${l10n.diskCleanerAiLabelFiles}: ${node.fileCount}');
    if (node.isJunk) {
      msg.writeln(
        l10n.diskCleanerAiCategoryMarkedJunk(
          node.junkCategoryId ?? 'unknown',
        ),
      );
    } else {
      msg.writeln(l10n.diskCleanerAiNotMarkedAsJunk);
    }
    msg.writeln();
    msg.writeln(l10n.diskCleanerAiDeleteAnalysisQuestion);
    _sendToAi(msg.toString());
  }

  void _askAiReviewPending() {
    // Ensure service has the pending items before agent calls the tool
    _service.pendingCleanupItems = _pendingCleanItems;
    _service.pendingCleanupBytes = _pendingCleanBytes;
    _sendToAi(
      'I have ${_pendingCleanItems.length} items (${_fmt(_pendingCleanBytes)}) '
      'selected for cleanup. Please call get_pending_cleanup_review to see the '
      'full list and tell me if anything looks risky.',
    );
  }

  void _sendToAi(String message) {
    final controller = AiPanelScope.maybeOf(context);
    if (controller == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                AppLocalizations.of(context)!.diskCleanerAiPanelUnavailable)),
      );
      return;
    }
    // Get active tab ID from TabManagerBloc
    final tabState = context.read<TabManagerBloc>().state;
    final tabId = tabState.activeTabId;
    if (tabId == null) return;

    _publishCleanerScanContext();
    controller.open(path: '#cb-agent-cleaner', tabId: tabId);
    final bloc = controller.blocForTab(
      tabId,
      thinkingPhrases: const ['Analyzing...', 'Checking...'],
      waitingApproval: 'Waiting for approval...',
      runningToolTemplate: 'Running {}...',
    );
    bloc.add(SendMessage(message));
  }

  String _buildAiSummary() {
    final root = _rootNode;
    if (root == null) return 'Please scan my disk for junk files.';
    final buffer = StringBuffer();
    buffer.writeln(
        'Please inspect the current CB Agent Cleaner scan. Call get_current_cleaner_scan first, then give cleanup recommendations.');
    buffer.writeln();
    buffer.writeln('I scanned drive ${root.fullPath}:');
    buffer.writeln('Total: ${_fmt(root.sizeBytes)}, ${root.fileCount} files');
    buffer.writeln('Junk found: ${_fmt(root.junkBytes)}');
    buffer.writeln('Top directories:');
    for (final child in root.children.take(8)) {
      final junkTag = child.isJunk || child.hasJunkChildren
          ? ' [JUNK: ${_fmt(child.junkBytes)}]'
          : '';
      buffer.writeln('  ${child.name}: ${_fmt(child.sizeBytes)}$junkTag');
    }
    buffer.writeln('Which junk should I clean? Any recommendations?');
    return buffer.toString();
  }

  bool _isNodeCleanable(DiskTreeNode node) {
    return node.isJunk || node.hasJunkChildren;
  }

  bool _passesTreeFilter(DiskTreeNode node) {
    if (_reviewMode) {
      return _reviewVisibleTreePaths.contains(
        AppStorageAnalyzer.normalizeWindowsPath(node.fullPath),
      );
    }
    if (_showGrowthOnly) return _isGrowthNodeOrAncestor(node);
    if (_showCleanableOnly) return _isNodeCleanable(node);
    if (_activePreset != _TreePreset.none) return _matchesPresetSubtree(node);
    return true;
  }

  /// True when [node] itself matches the active preset, ignoring descendants.
  bool _matchesPresetDirectly(DiskTreeNode node) {
    switch (_activePreset) {
      case _TreePreset.none:
        return true;
      case _TreePreset.largeFiles:
        return node.isFile && node.sizeBytes >= _largeFileThresholdBytes;
      case _TreePreset.logsAndCaches:
        return _logAndCacheCategoryIds.contains(node.junkCategoryId);
      case _TreePreset.installers:
        if (!node.isFile) return false;
        if (node.sizeBytes < _installerThresholdBytes) return false;
        final extension = p.extension(node.name).toLowerCase();
        return _installerExtensions.contains(extension);
    }
  }

  /// A node stays visible when it matches, or when anything beneath it does —
  /// otherwise the matching files would be unreachable in the tree.
  ///
  /// Results are memoised per (root, preset); [_invalidatePresetCache] clears
  /// the cache whenever either changes.
  bool _matchesPresetSubtree(DiskTreeNode node) {
    final cached = _presetMatchCache[node];
    if (cached != null) return cached;
    var matches = _matchesPresetDirectly(node);
    if (!matches) {
      for (final child in node.children) {
        if (_matchesPresetSubtree(child)) {
          matches = true;
          break;
        }
      }
    }
    _presetMatchCache[node] = matches;
    return matches;
  }

  void _invalidatePresetCache() => _presetMatchCache.clear();

  void _setTreePreset(_TreePreset preset) {
    setState(() {
      _activePreset = preset;
      if (preset != _TreePreset.none) {
        _showCleanableOnly = false;
        _showGrowthOnly = false;
      }
      _invalidatePresetCache();
      _flatRowsValid = false;
    });
    final root = _rootNode;
    if (preset != _TreePreset.none && root != null) {
      _expandPresetAncestors(root, 0);
      setState(() => _flatRowsValid = false);
    }
  }

  /// Opens the branches leading to matches so the user sees results without
  /// drilling down manually. Bounded in depth to keep very deep trees usable.
  void _expandPresetAncestors(DiskTreeNode node, int depth) {
    if (depth >= 6) return;
    if (!_matchesPresetSubtree(node)) return;
    for (final child in node.children) {
      if (child.isFile || !_matchesPresetSubtree(child)) continue;
      node.isExpanded = true;
      _expandPresetAncestors(child, depth + 1);
    }
  }

  String _presetLabel(AppLocalizations l, _TreePreset preset) {
    switch (preset) {
      case _TreePreset.none:
        return l.diskCleanerPresetAll;
      case _TreePreset.largeFiles:
        return l.diskCleanerPresetLargeFiles;
      case _TreePreset.logsAndCaches:
        return l.diskCleanerPresetLogsCaches;
      case _TreePreset.installers:
        return l.diskCleanerPresetInstallers;
    }
  }

  CleanerFolderGrowth? _growthForNode(DiskTreeNode node) {
    final nodePath = AppStorageAnalyzer.normalizeWindowsPath(node.fullPath);
    for (final growth in _recentFolderGrowth) {
      if (AppStorageAnalyzer.normalizeWindowsPath(growth.path) == nodePath) {
        return growth;
      }
    }
    return null;
  }

  bool _isGrowthNodeOrAncestor(DiskTreeNode node) {
    if (node.isFile) return false;
    final nodePath = AppStorageAnalyzer.normalizeWindowsPath(node.fullPath);
    for (final growth in _recentFolderGrowth) {
      final growthPath = AppStorageAnalyzer.normalizeWindowsPath(growth.path);
      if (growthPath == nodePath || growthPath.startsWith('$nodePath\\')) {
        return true;
      }
    }
    return false;
  }

  void _expandGrowthAncestors(DiskTreeNode node) {
    if (!_isGrowthNodeOrAncestor(node)) return;
    for (final child in node.children) {
      if (child.isFile || !_isGrowthNodeOrAncestor(child)) continue;
      node.isExpanded = true;
      _expandGrowthAncestors(child);
    }
  }

  void _setGrowthOnly(bool enabled) {
    if (enabled && _recentFolderGrowth.isEmpty) return;
    setState(() {
      _showGrowthOnly = enabled;
      if (enabled) {
        _showCleanableOnly = false;
        final root = _rootNode;
        if (root != null) _expandGrowthAncestors(root);
      }
      _flatRowsValid = false;
    });
  }

  int _countCleanableNodes(DiskTreeNode? node) {
    return DiskTreeSelection.countCleanableNodes(node);
  }

  void _ensureCleanerAggregates(DiskTreeNode root) {
    if (identical(_aggregateCacheRoot, root)) return;
    _aggregateCacheRoot = root;
    _cachedJunkBytes = root.junkBytes;
    _cachedCleanableCount = _countCleanableNodes(root);
  }

  void _setAllCleanableChecked(DiskTreeNode? node, bool checked) {
    if (node == null) return;
    final selectedPaths =
        DiskTreeSelection.setAllCleanableChecked(node, checked);
    _selectedTreePaths
      ..clear()
      ..addAll(selectedPaths);
    _selectedTreeTargets
      ..clear()
      ..addAll(DiskTreeSelection.collectDeletionTargets(node));
    _rebuildReviewVisibleTreePaths();
    _flatRowsValid = false;
    _publishTreeSelection();
    setState(() {});
  }

  /// Row label for [node]. Roll-up rows carry no real name, so they are named
  /// by how many entries the scan folded into them.
  static String _displayName(AppLocalizations l, DiskTreeNode node) {
    if (!node.isAggregate) return node.name;
    return l.diskCleanerRolledUpItems(node.aggregatedItemCount);
  }

  /// Captures only the visible expansion frontier. Expansion below a collapsed
  /// node is intentionally dropped so scan completion never walks hidden
  /// cached subtrees; [_applyExpandedPaths] still forces the selected drive
  /// root open.
  Set<String> _collectExpandedPaths(DiskTreeNode? node) {
    final paths = <String>{};
    void walk(DiskTreeNode n) {
      if (!n.isExpanded) return;
      if (n.fullPath.isNotEmpty) {
        paths.add(AppStorageAnalyzer.normalizeWindowsPath(n.fullPath));
      }
      for (final child in n.children) {
        walk(child);
      }
    }

    if (node != null) walk(node);
    return paths;
  }

  void _applyExpandedPaths(DiskTreeNode node, Set<String> paths) {
    final expandedPaths = paths
        .where((path) => path.isNotEmpty)
        .map(AppStorageAnalyzer.normalizeWindowsPath)
        .toSet();
    final pathsWithAncestors = <String>{};

    void addPathAndAncestors(String path) {
      var current = path;
      pathsWithAncestors.add(current);
      while (true) {
        final separator = current.lastIndexOf('\\');
        if (separator < 0) break;
        if (separator <= 2) {
          pathsWithAncestors.add(current.substring(0, 3));
          break;
        }
        current = current.substring(0, separator);
        pathsWithAncestors.add(current);
      }
    }

    for (final path in expandedPaths) {
      addPathAndAncestors(path);
    }

    final selectedDrive = _selectedDrive;
    final selectedDriveRoot = selectedDrive == null
        ? null
        : AppStorageAnalyzer.normalizeWindowsPath(selectedDrive);

    void apply(DiskTreeNode current) {
      final currentPath = current.fullPath.isEmpty
          ? ''
          : AppStorageAnalyzer.normalizeWindowsPath(current.fullPath);
      final shouldExpand = expandedPaths.contains(currentPath) ||
          (selectedDriveRoot != null && currentPath == selectedDriveRoot);
      current.isExpanded = shouldExpand;

      // Only inspect branches that can contain a restored expansion or that
      // carry stale expansion state from an incremental worker result. Nodes
      // outside those branches are already collapsed by construction and do
      // not need a full-tree recursive walk.
      for (final child in current.children) {
        final childPath = child.fullPath.isEmpty
            ? ''
            : AppStorageAnalyzer.normalizeWindowsPath(child.fullPath);
        if (pathsWithAncestors.contains(childPath) || child.isExpanded) {
          apply(child);
        } else {
          // Clear direct stale state without descending into an unrelated
          // subtree. Descendants with explicit expansion paths are reached via
          // pathsWithAncestors even when an ancestor itself is collapsed.
          child.isExpanded = false;
        }
      }
    }

    apply(node);
  }

  /// Remove nodes whose path was successfully deleted from the in-memory tree,
  /// and subtract their size/fileCount from all ancestors so the results view
  /// reflects the cleanup without requiring a re-scan.
  ///
  /// Returns the number of bytes pruned from [node]'s subtree.
  int _pruneDeletedPaths(DiskTreeNode node, Set<String> deletedUpper) {
    int prunedBytes = 0;
    int prunedFiles = 0;
    final survivors = <DiskTreeNode>[];

    for (final child in node.children) {
      if (deletedUpper.contains(child.fullPath.toUpperCase())) {
        // Whole subtree was deleted.
        prunedBytes += child.sizeBytes;
        prunedFiles += child.fileCount;
        continue;
      }
      // Recurse: a descendant may have been deleted even if the child wasn't.
      prunedBytes += _pruneDeletedPaths(child, deletedUpper);
      survivors.add(child);
    }

    if (survivors.length != node.children.length) {
      node.replaceChildren(survivors);
    }

    node.sizeBytes = (node.sizeBytes - prunedBytes).clamp(0, node.sizeBytes);
    node.fileCount = (node.fileCount - prunedFiles).clamp(0, node.fileCount);

    // Clear selection on whatever remains so stale row highlights do not linger.
    node.isSelectedForDeletion = false;

    return prunedBytes;
  }

  /// Drop pending-clean state and return to the results tree without re-scanning.
  void _continueToResults() {
    setState(() {
      _cleanedItems = [];
      _cleanedSkippedInUseCount = 0;
      _cleanedSkippedByUserCount = 0;
      _cleanedFailureCount = 0;
      _reviewMode = false;
      _phase = _rootNode != null ? _Phase.results : _Phase.setup;
    });
    if (_rootNode == null) _startScan();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return Scaffold(
      body: ValueListenableBuilder<_CleanerSubFeature>(
        valueListenable: _subFeatureListenable,
        builder: (context, feature, child) {
          final destinations = <CleanerUtilityDestination>[
            CleanerUtilityDestination(
              id: _CleanerSubFeature.diskCleaner.name,
              title: l.cleanerDiskUsageTitle,
              description: l.cleanerDiskUtilityDescription,
              group: l.cleanerUtilitiesStorageGroup,
              icon: PhosphorIconsLight.hardDrive,
            ),
            CleanerUtilityDestination(
              id: _CleanerSubFeature.appInsights.name,
              title: l.cleanerAppsTitle,
              description: l.cleanerAppsUtilityDescription,
              group: l.cleanerUtilitiesStorageGroup,
              icon: PhosphorIconsLight.appWindow,
            ),
          ];
          return CleanerUtilitiesShell(
            title: l.cleanerUtilitiesTitle,
            subtitle: l.cleanerUtilitiesSubtitle,
            selectedId: feature.name,
            destinations: destinations,
            navigationEnabled: !_reviewMode && !_isCleaningJunk,
            onSelected: (id) {
              final selected = _CleanerSubFeature.values.firstWhere(
                (candidate) => candidate.name == id,
                orElse: () => feature,
              );
              _setSubFeature(selected);
            },
            child: IndexedStack(
              index: feature == _CleanerSubFeature.appInsights ? 1 : 0,
              children: [
                RepaintBoundary(
                  key: const ValueKey<String>(
                    'cleaner-storage-results-pane',
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: _buildPhase(theme, l),
                  ),
                ),
                RepaintBoundary(
                  key: const ValueKey<String>('cleaner-apps-results-pane'),
                  child: _buildAppsFeature(theme, l),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhase(ThemeData theme, AppLocalizations l) {
    switch (_phase) {
      case _Phase.setup:
        return _buildSetup(theme, l);
      case _Phase.results:
        return _buildResults(theme, l);
      case _Phase.cleaned:
        return _buildCleaned(theme, l);
    }
  }

  // ---------------------------------------------------------------------------
  // Setup phase — drive picker + animated scan button
  // ---------------------------------------------------------------------------

  Widget _buildSetup(ThemeData theme, AppLocalizations l) {
    // Scroll when the drive grid + last-scan card exceed the pane height
    // (common with many volumes or a short window).
    return LayoutBuilder(
      key: const ValueKey('setup'),
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.diskCleanerScanTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.diskCleanerSelectDrives,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Drive picker — capacity bars make the drive that needs
                  // attention obvious without reading any numbers.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: _drives
                          .map((d) => _buildDriveCard(theme, l, d))
                          .toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildScanButton(l),
                  const SizedBox(height: 24),
                  _buildLastScanCard(theme, l),
                  const SizedBox(height: 18),
                  if (_aiAvailable)
                    _buildAcrylicChip(
                      theme: theme,
                      icon: PhosphorIconsLight.sparkle,
                      label: l.diskCleanerAskAgent,
                      onTap: _openAiPanel,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Selectable drive tile showing a used/total capacity bar. The bar turns
  /// amber past 85% and red past 95% so space pressure reads at a glance.
  Widget _buildDriveCard(ThemeData theme, AppLocalizations l, DriveSpace d) {
    final selected = _selectedDrive == d.path;
    final fraction = _driveUsedFraction(d);
    final isCritical = fraction >= 0.95;
    final isLow = fraction >= 0.85;
    final barColor = isCritical
        ? theme.colorScheme.error
        : (isLow ? Colors.orange : theme.colorScheme.primary);
    final label = d.label.isNotEmpty ? '${d.path} (${d.label})' : d.path;

    return SizedBox(
      width: 250,
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedDrive = d.path),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.dividerColor.withValues(alpha: 0.6),
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(PhosphorIconsLight.hardDrive,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isLow) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: barColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          l.diskCleanerDriveLowSpace,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: barColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 6,
                    backgroundColor:
                        theme.colorScheme.onSurface.withValues(alpha: 0.10),
                    valueColor: AlwaysStoppedAnimation<Color>(barColor),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l.diskCleanerDriveCapacity(
                    _fmt(d.usedBytes),
                    _fmt(d.totalBytes),
                    _fmt(d.freeBytes),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Shows what the previous scan of the selected drive found, plus a
  /// one-tap "quick clean" for the categories classified as safe. Most users
  /// only want that — the tree and pie chart are the advanced path.
  Widget _buildLastScanCard(ThemeData theme, AppLocalizations l) {
    final summary = _lastScanFor(_selectedDrive);
    if (summary == null) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(PhosphorIconsLight.clockCounterClockwise,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.diskCleanerLastScanFound(
                      _relativeTimeLabel(l, summary.scannedAt),
                      _fmt(summary.junkBytes),
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.diskCleanerQuickCleanHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(shape: _cleanerButtonShape),
                  onPressed: _isQuickCleaning ? null : _startQuickClean,
                  icon: _isQuickCleaning
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(PhosphorIconsLight.broom, size: 16),
                  label: Text(_isQuickCleaning
                      ? l.diskCleanerQuickCleanScanning
                      : l.diskCleanerQuickCleanButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Human-friendly "3 days ago" style label for the previous scan time.
  String _relativeTimeLabel(AppLocalizations l, DateTime when) {
    final delta = DateTime.now().difference(when);
    if (delta.inMinutes < 5) return l.diskCleanerTimeJustNow;
    if (delta.inHours < 24) return l.diskCleanerTimeToday;
    final days = delta.inDays;
    if (days <= 1) return l.diskCleanerTimeYesterday;
    if (days < 7) return l.diskCleanerTimeDaysAgo(days);
    final weeks = days ~/ 7;
    if (weeks < 5) return l.diskCleanerTimeWeeksAgo(weeks);
    return l.diskCleanerTimeMonthsAgo(days ~/ 30);
  }

  /// Primary call to action for the setup phase. A plain filled pill: the
  /// state that matters (a drive is picked or it isn't) is carried by the
  /// button's own enabled styling, so nothing has to animate to draw the eye.
  Widget _buildScanButton(AppLocalizations l) {
    final enabled = _selectedDrive != null && !_isScanningAppInsights;
    return FilledButton.icon(
      key: const ValueKey<String>('cleaner-scan-cta'),
      onPressed: enabled ? () => _startScan() : null,
      icon: const Icon(PhosphorIconsLight.magnifyingGlass, size: 18),
      label: Text(l.diskCleanerScanTitle),
      // The design system pins every button to a fixed height, so a taller
      // CTA has to raise that height rather than pad its way past it —
      // vertical padding alone just clips the label.
      style: FilledButton.styleFrom(
        fixedSize: const Size.fromHeight(40),
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: _cleanerButtonShape,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Results phase — 2-panel: tree (left) + pie chart (right)
  // ---------------------------------------------------------------------------

  Future<void> _deleteCurrentSelectionImmediately({
    required bool permanent,
  }) async {
    if (_isCleaningJunk) return;

    final nodes = _selectedTreeNodes();
    if (nodes.isEmpty) return;

    final l = AppLocalizations.of(context)!;
    final totalBytes = nodes.fold<int>(0, (sum, node) => sum + node.sizeBytes);

    // Confirm before deleting.
    if (permanent) {
      final confirmed = await _showPermanentDeleteDialog(
        itemCount: nodes.length,
        bytes: totalBytes,
        fromRecycleBin: false,
      );
      if (confirmed != true) return;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.diskCleanerMoveToRecycleBin),
          content: Text(
            '${nodes.length == 1 ? nodes.first.name : '${nodes.length} items'}\n${_fmt(totalBytes)}',
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(shape: _cleanerButtonShape),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(shape: _cleanerButtonShape),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.diskCleanerMoveToRecycleBin),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;

    final items = nodes
        .map((node) => JunkItem(
              path: node.fullPath,
              sizeBytes: node.sizeBytes,
              categoryId: node.junkCategoryId ?? 'selected_item',
              isContainerOnly: false,
              isUserSelected: true,
            ))
        .toList();

    setState(() {
      _pendingCleanItems = items;
      _pendingCleanBytes = totalBytes;
      _selectedCleanMode =
          permanent ? _CleanDeleteMode.permanent : _CleanDeleteMode.recycleBin;
      _reviewMode = false;
    });

    _service.pendingCleanupItems = items;
    _service.pendingCleanupBytes = totalBytes;

    await _cleanJunk(
      permanent: permanent,
      showCleanedResult: false,
    );
  }

  List<DiskTreeNode> _selectedTreeNodes() {
    return List<DiskTreeNode>.unmodifiable(_selectedTreeTargets);
  }

  void _publishTreeSelection() {
    _selectedTreePaths
      ..clear()
      ..addAll(_selectedTreeTargets.map((node) => node.fullPath));
    _selectedTreePathListenable.value = Set<String>.unmodifiable(
      _selectedTreePaths,
    );
    _publishCleanerScanContext();
  }

  void _rebuildReviewVisibleTreePaths() {
    _reviewVisibleTreePaths.clear();
    for (final target in _selectedTreeTargets) {
      var path = AppStorageAnalyzer.normalizeWindowsPath(target.fullPath);
      while (path.isNotEmpty) {
        _reviewVisibleTreePaths.add(path);
        if (path.length <= 3) break;
        final separator = path.lastIndexOf(r'\');
        if (separator < 0) break;
        path = path.substring(0, separator);
        if (path.length == 2 && path.endsWith(':')) path = '$path\\';
      }
    }
  }

  void _replaceTreeTargets(Iterable<DiskTreeNode> targets) {
    final nextTargets = targets.toSet();
    for (final current in _selectedTreeTargets) {
      if (!nextTargets.contains(current)) {
        current.isSelectedForDeletion = false;
      }
    }
    for (final target in nextTargets) {
      target.isSelectedForDeletion = true;
    }
    _selectedTreeTargets
      ..clear()
      ..addAll(nextTargets);
    _rebuildReviewVisibleTreePaths();
    _publishTreeSelection();
  }

  String? _activeTabId() {
    try {
      return context.read<TabManagerBloc>().state.activeTabId;
    } catch (_) {
      return null;
    }
  }

  void _scheduleDiskProgressContextPublication() {
    if (!mounted || _diskProgressContextTimer?.isActive == true) return;
    _diskProgressContextTimer = Timer(
      _diskProgressContextThrottle,
      () {
        _diskProgressContextTimer = null;
        if (mounted) _publishCleanerScanContext();
      },
    );
  }

  void _cancelDiskProgressContextPublication() {
    _diskProgressContextTimer?.cancel();
    _diskProgressContextTimer = null;
  }

  void _publishCleanerScanContext() {
    if (!mounted) return;
    final tabId = _activeTabId();
    if (tabId == null || tabId.isEmpty) return;
    _publishedCleanerContextTabId = tabId;
    _service.publishCleanerScanContext(
      ownerTabId: tabId,
      root: _rootNode,
      selectedPath: _selectedNode?.fullPath,
      chartPath: _chartNode?.fullPath,
      isScanning: _isScanningFullDisk || _agentScanning,
      isCached: _isShowingCachedDiskScan,
      appStorageReport: _appStorageReport,
      selectedAppId: _appInsightsCubit.state.selectedAppId,
      appInsightsSharedWithAgent: _appInsightsSharedWithAgent,
    );
  }

  Set<DiskTreeNode> _canonicalTreeTargets(Iterable<DiskTreeNode> nodes) {
    final sorted = nodes.where((node) => node.fullPath.isNotEmpty).toList()
      ..sort((a, b) {
        final aPath = AppStorageAnalyzer.normalizeWindowsPath(a.fullPath);
        final bPath = AppStorageAnalyzer.normalizeWindowsPath(b.fullPath);
        return aPath.length.compareTo(bPath.length);
      });
    final targets = <DiskTreeNode>{};
    final targetPaths = <String>[];
    for (final node in sorted) {
      final path = AppStorageAnalyzer.normalizeWindowsPath(node.fullPath);
      if (targetPaths.any(
        (parent) => AppStorageAnalyzer.isSameOrDescendant(path, parent),
      )) {
        continue;
      }
      targets.add(node);
      targetPaths.add(path);
    }
    return targets;
  }

  void _selectTreeRow(DiskTreeNode node, List<_FlatRow> visibleRows) {
    if (node.fullPath.isEmpty) return;
    _resultsFocusNode.requestFocus();
    _selectedNode = node;
    _focusedTreePathListenable.value = node.fullPath;

    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final isShift = keyboard.isShiftPressed;
    var appliedRange = false;
    if (isShift && _selectionAnchorPath != null) {
      final anchorIndex = visibleRows.indexWhere(
        (row) => row.node.fullPath == _selectionAnchorPath,
      );
      final currentIndex = visibleRows.indexWhere(
        (row) => row.node.fullPath == node.fullPath,
      );
      if (anchorIndex >= 0 && currentIndex >= 0) {
        final start = math.min(anchorIndex, currentIndex);
        final end = math.max(anchorIndex, currentIndex);
        final range =
            visibleRows.sublist(start, end + 1).map((row) => row.node);
        _replaceTreeTargets(
          _canonicalTreeTargets(
            isCtrl ? <DiskTreeNode>[..._selectedTreeTargets, ...range] : range,
          ),
        );
        appliedRange = true;
      }
    }
    if (!appliedRange && isCtrl) {
      _toggleTreeTarget(node, !_selectedTreeTargets.contains(node));
      _selectionAnchorPath = node.fullPath;
    } else if (!appliedRange) {
      _replaceTreeTargets(<DiskTreeNode>[node]);
      _selectionAnchorPath = node.fullPath;
    }
    if (_reviewMode) {
      setState(() => _flatRowsValid = false);
    }
    _scheduleChartNodeUpdate(node);
  }

  void _toggleTreeTarget(DiskTreeNode node, bool checked) {
    final targets = DiskTreeSelection.setExactTargetChecked(
      _selectedTreeTargets,
      node,
      checked,
    );
    _replaceTreeTargets(targets);
    if (_reviewMode) {
      setState(() => _flatRowsValid = false);
    }
  }

  void _scheduleChartNodeUpdate(DiskTreeNode node) {
    _chartUpdateTimer?.cancel();
    _chartUpdateTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || _chartNode == node) return;
      setState(() => _chartNode = node);
      _publishCleanerScanContext();
    });
  }

  KeyEventResult _handleResultsKeyEvent(FocusNode node, KeyEvent event) {
    if (_isCleaningJunk || _rootNode == null) return KeyEventResult.ignored;
    if (BrowserLikeKeyboardShortcuts.isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    final isKeyDown = event is KeyDownEvent || event is KeyRepeatEvent;
    if (!isKeyDown) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (_activeSubFeature == _CleanerSubFeature.appInsights) {
      if (isCtrl && key == LogicalKeyboardKey.keyA) {
        final visibleApps = _appInsightsCubit.state.visibleApps;
        if (visibleApps.isNotEmpty) {
          _appInsightsCubit.selectApp(visibleApps.first.app.id);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.delete) {
        // App Insights never maps keyboard deletion to files, app data, or an
        // uninstaller. Cleanup must go through the confirmed cache review.
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (isCtrl && key == LogicalKeyboardKey.keyA) {
      _setAllCleanableChecked(_rootNode, true);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.space) {
      final focused = _selectedNode;
      if (focused != null && focused.fullPath.isNotEmpty) {
        _toggleTreeTarget(
          focused,
          !_selectedTreeTargets.contains(focused),
        );
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete) {
      unawaited(_deleteCurrentSelectionImmediately(permanent: isShift));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _moveTreeFocus(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveTreeFocus(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _moveTreeFocusTo(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _moveTreeFocusTo((_cachedFlatRows?.length ?? 1) - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _expandOrDescendFocusedRow();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _collapseOrAscendFocusedRow();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  int _focusedRowIndex() {
    final rows = _cachedFlatRows;
    if (rows == null || rows.isEmpty) return -1;
    final focusedPath = _selectedNode?.fullPath;
    if (focusedPath == null || focusedPath.isEmpty) return -1;
    return rows.indexWhere((row) => row.node.fullPath == focusedPath);
  }

  /// Moves keyboard focus [delta] visible rows and scrolls it into view.
  void _moveTreeFocus(int delta) {
    final rows = _cachedFlatRows;
    if (rows == null || rows.isEmpty) return;
    final current = _focusedRowIndex();
    final next = current < 0
        ? (delta > 0 ? 0 : rows.length - 1)
        : (current + delta).clamp(0, rows.length - 1);
    _moveTreeFocusTo(next);
  }

  void _moveTreeFocusTo(int index) {
    final rows = _cachedFlatRows;
    if (rows == null || rows.isEmpty) return;
    final target = index.clamp(0, rows.length - 1);
    final node = rows[target].node;
    if (node.fullPath.isEmpty) return;
    setState(() {
      _selectedNode = node;
      _chartNode = node;
    });
    _focusedTreePathListenable.value = node.fullPath;
    _selectionAnchorPath = node.fullPath;
    _scrollTreeRowIntoView(target);
  }

  void _scrollTreeRowIntoView(int index) {
    if (!_treeScrollController.hasClients) return;
    final position = _treeScrollController.position;
    final rowTop = index * _treeRowExtent;
    final rowBottom = rowTop + _treeRowExtent;
    double? target;
    if (rowTop < position.pixels) {
      target = rowTop;
    } else if (rowBottom > position.pixels + position.viewportDimension) {
      target = rowBottom - position.viewportDimension;
    }
    if (target == null) return;
    _treeScrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  /// Right arrow: expand a collapsed folder, or step into its first child.
  void _expandOrDescendFocusedRow() {
    final node = _selectedNode;
    if (node == null || node.isFile || node.children.isEmpty) return;
    if (!node.isExpanded) {
      setState(() {
        node.isExpanded = true;
        _flatRowsValid = false;
      });
      return;
    }
    _moveTreeFocus(1);
  }

  /// Left arrow: collapse an expanded folder, or step out to its parent.
  void _collapseOrAscendFocusedRow() {
    final node = _selectedNode;
    if (node == null) return;
    if (!node.isFile && node.isExpanded && node.children.isNotEmpty) {
      setState(() {
        node.isExpanded = false;
        _flatRowsValid = false;
      });
      return;
    }
    final rows = _cachedFlatRows;
    final current = _focusedRowIndex();
    if (rows == null || current <= 0) return;
    final currentDepth = rows[current].depth;
    for (var index = current - 1; index >= 0; index--) {
      if (rows[index].depth < currentDepth) {
        _moveTreeFocusTo(index);
        return;
      }
    }
  }

  void _setSubFeature(_CleanerSubFeature feature) {
    if (_activeSubFeature == feature) return;
    _activeSubFeature = feature;
    _subFeatureListenable.value = feature;
    if (feature == _CleanerSubFeature.appInsights) {
      _appsFocusNode.requestFocus();
      if (_appInsightsCubit.state.status == CleanerAppInsightsStatus.idle) {
        if (_isScanningFullDisk) {
          _appInsightsCubit.setLoading();
        } else {
          unawaited(_startAppInsightsScan());
        }
      }
    } else {
      _resultsFocusNode.requestFocus();
    }
    _publishCleanerScanContext();
  }

  void _selectAppInsightsDrive(String? drivePath) {
    if (drivePath == null ||
        drivePath == _appInsightsDrive ||
        _isScanningFullDisk) {
      return;
    }
    if (_isScanningAppInsights) {
      _service.cancelFullDiskScan();
      _appInsightsGeneration++;
    }
    _appInsightsSharedWithAgent = false;
    _appInsightsProgressListenable.value = null;
    _appInsightsCubit.clear();
    setState(() {
      _appInsightsDrive = drivePath;
      _appStorageReport = null;
      _appInsightsScanResult = null;
      _isScanningAppInsights = false;
    });
    _publishCleanerScanContext();
    unawaited(_startAppInsightsScan());
  }

  String _driveDisplayName(DriveSpace drive) {
    return drive.label.trim().isEmpty
        ? drive.path
        : '${drive.path}  ${drive.label}';
  }

  Widget _buildAppsFeature(ThemeData theme, AppLocalizations l) {
    final selectedDrivePath =
        _appInsightsDrive ?? _defaultDrivePath(_drives) ?? r'C:\';
    DriveSpace? selectedDrive;
    for (final drive in _drives) {
      if (drive.path == selectedDrivePath) {
        selectedDrive = drive;
        break;
      }
    }
    final canChangeDrive = !_isScanningFullDisk;
    return Focus(
      focusNode: _appsFocusNode,
      onKeyEvent: _handleResultsKeyEvent,
      child: Column(
        key: const ValueKey<String>('cleaner-apps-feature'),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  PhosphorIconsLight.appWindow,
                  size: 19,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.cleanerAppsTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      ValueListenableBuilder<FullDiskScanProgress?>(
                        valueListenable: _appInsightsProgressListenable,
                        builder: (context, progress, child) {
                          final text = progress == null
                              ? selectedDrive == null
                                  ? selectedDrivePath
                                  : l.diskCleanerDriveFree(
                                      _driveDisplayName(selectedDrive),
                                      _fmt(selectedDrive.freeBytes),
                                    )
                              : l.diskCleanerScannedProgress(
                                  _fmt(progress.bytesScanned),
                                  progress.filesScanned,
                                );
                          return Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CbSelect<String>(
                  key: const ValueKey<String>('cleaner-apps-drive-picker'),
                  width: 190,
                  size: CbSelectSize.lg,
                  value: selectedDrive?.path,
                  placeholder: l.diskCleanerSelectDrives,
                  enabled: canChangeDrive,
                  onChanged: _selectAppInsightsDrive,
                  items: [
                    for (final drive in _drives)
                      CbSelectItem<String>(
                        value: drive.path,
                        // The menu has room for the free space, the 190px
                        // trigger does not.
                        label: l.diskCleanerDriveFree(
                          _driveDisplayName(drive),
                          _fmt(drive.freeBytes),
                        ),
                        triggerLabel: _driveDisplayName(drive),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(shape: _cleanerButtonShape),
                  key: const ValueKey<String>('cleaner-apps-rescan'),
                  onPressed: _isScanningFullDisk
                      ? null
                      : _isScanningAppInsights
                          ? _cancelAppInsightsScan
                          : () => unawaited(
                                _startAppInsightsScan(forceDiskScan: true),
                              ),
                  icon: _isScanningAppInsights
                      ? const Icon(Icons.stop_rounded, size: 16)
                      : const Icon(
                          PhosphorIconsLight.arrowCounterClockwise,
                          size: 16,
                        ),
                  label: Text(
                    _isScanningAppInsights
                        ? l.diskCleanerCancel
                        : l.diskCleanerScanAgain,
                  ),
                ),
              ],
            ),
          ),
          if (_isScanningAppInsights)
            const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1),
          Expanded(
            child: CleanerAppsView(
              cubit: _appInsightsCubit,
              onOpenFolder: _openAppStorageFolder,
              onManageApp: _manageInstalledApp,
              onReviewCleanable:
                  _isScanningAppInsights ? null : _reviewAppCleanableData,
              onAskAgent: _askAgentAboutApp,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(ThemeData theme, AppLocalizations l) {
    final root = _rootNode!;
    final viewNode = _chartNode ?? _selectedNode ?? root;
    return Focus(
      focusNode: _resultsFocusNode,
      autofocus: true,
      onKeyEvent: _handleResultsKeyEvent,
      child: Column(
        key: const ValueKey('results'),
        children: [
          // Top toolbar
          _buildResultsToolbar(theme, l, root),
          const Divider(height: 1),
          _buildOldLargeItemsPanel(theme, l, root),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                // Left: tree view (~65%)
                Expanded(
                  flex: 65,
                  child: _buildTreePanel(theme, l, root),
                ),
                const VerticalDivider(width: 1),
                // Right: pie chart (~35%). Old-large evidence is full-width
                // above this split so folder rows remain easy to discover.
                Expanded(
                  flex: 35,
                  child: _buildPiePanel(theme, l, viewNode),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<Set<String>>(
            valueListenable: _selectedTreePathListenable,
            builder: (context, _, __) => _buildBottomBar(theme, l),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsToolbar(
    ThemeData theme,
    AppLocalizations l,
    DiskTreeNode root,
  ) {
    _ensureCleanerAggregates(root);
    final junkBytes = _cachedJunkBytes;
    final cleanableCount = _cachedCleanableCount;
    final hasStatus = _isScanningFullDisk ||
        _agentScanning ||
        _isShowingCachedDiskScan ||
        _lastDiskScanResult?.scanMode == FullDiskScanMode.incremental ||
        _lastDiskScanResult?.incrementalFallbackReason != null;

    Widget buildDriveInfo() {
      final driveSummary = l.diskCleanerDriveSummary(
          root.fullPath, _fmt(root.sizeBytes), root.fileCount);
      return Row(
        children: [
          Icon(PhosphorIconsLight.hardDrive,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              driveSummary,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    Widget buildStatus() {
      if (_isScanningFullDisk) {
        final progress = _diskProgressListenable.value;
        final currentPath = progress?.currentPath ?? '';
        return Text(
          progress?.isIncremental == true
              ? (currentPath.isEmpty
                  ? l.diskCleanerIncrementalScanTitle
                  : '${l.diskCleanerIncrementalScanTitle} • $currentPath')
              : (progress == null ? l.diskCleanerScanRunning : currentPath),
          key: const ValueKey<String>('cleaner-full-scan-status'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }

      if (_agentScanning) {
        return Row(
          children: [
            AppWaveLoader(
              size: 22,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: 6),
            Icon(PhosphorIconsLight.sparkle,
                size: 14, color: theme.colorScheme.tertiary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _agentCurrentPath.isEmpty
                    ? (_agentStatus.isEmpty
                        ? l.diskCleanerScanRunning
                        : _agentStatus)
                    : l.diskCleanerAgentPath(_agentCurrentPath),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_agentItemsFound > 0) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l.diskCleanerItemsBytes(
                      _agentItemsFound, _fmt(_agentBytesFound)),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
      }

      if (_isShowingCachedDiskScan) {
        return Text(
          l.diskCleanerCachedResultStatus,
          key: const ValueKey<String>('cleaner-cached-result-status'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }

      final result = _lastDiskScanResult;
      if (result?.scanMode == FullDiskScanMode.incremental) {
        return Text(
          l.diskCleanerIncrementalScanProgress(
            result!.changedDirectoryCount,
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      if (result?.incrementalFallbackReason != null) {
        return Text(
          l.diskCleanerFullScanFallback,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }

      return const SizedBox.shrink();
    }

    Widget boundedAction(Widget child, {double maxWidth = 220}) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      );
    }

    final actions = <Widget>[
      // Junk summary badge
      boundedAction(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            l.diskCleanerJunkSummary(_fmt(junkBytes)),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.orange.shade700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      // Preset views — "how do I get space back" shortcuts that don't
      // require walking the hierarchy.
      boundedAction(
        PopupMenuButton<_TreePreset>(
          key: const ValueKey<String>('cleaner-preset-menu'),
          tooltip: l.diskCleanerPresetTooltip,
          initialValue: _activePreset,
          onSelected: _setTreePreset,
          itemBuilder: (_) => _TreePreset.values
              .map(
                (preset) => PopupMenuItem<_TreePreset>(
                  value: preset,
                  child: Text(_presetLabel(l, preset)),
                ),
              )
              .toList(growable: false),
          child: Chip(
            avatar: const Icon(PhosphorIconsLight.funnel, size: 16),
            label: Text(
              _presetLabel(l, _activePreset),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            backgroundColor: _activePreset == _TreePreset.none
                ? null
                : theme.colorScheme.primaryContainer,
          ),
        ),
      ),
      // Filter cleanable-only
      boundedAction(
        CbTooltip(
          message: l.diskCleanerShowCleanableOnly,
          child: FilterChip(
            label: Text(
              l.diskCleanerCleanableOnlyChip(cleanableCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            selected: _showCleanableOnly,
            onSelected: (v) => setState(() {
              _showCleanableOnly = v;
              if (v) _showGrowthOnly = false;
              _flatRowsValid = false;
            }),
          ),
        ),
      ),
      if (_recentFolderGrowth.isNotEmpty)
        boundedAction(
          CbTooltip(
            message: l.diskCleanerGrowthTitle,
            child: FilterChip(
              key: const ValueKey<String>('cleaner-growth-filter'),
              avatar: const Icon(PhosphorIconsLight.trendUp, size: 16),
              label: Text(
                l.diskCleanerGrowthFilter(_recentFolderGrowth.length),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              selected: _showGrowthOnly,
              onSelected: _setGrowthOnly,
            ),
          ),
        ),
      // Quick check actions
      boundedAction(
        TextButton(
          style: TextButton.styleFrom(shape: _cleanerButtonShape),
          onPressed: () => _setAllCleanableChecked(_rootNode, true),
          child: Text(
            l.diskCleanerCheckAllCleanable,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      boundedAction(
        TextButton(
          style: TextButton.styleFrom(shape: _cleanerButtonShape),
          onPressed: () => _setAllCleanableChecked(_rootNode, false),
          child: Text(
            l.diskCleanerUncheckAll,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      if (_aiAvailable)
        boundedAction(
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(shape: _cleanerButtonShape),
            onPressed: _openAiPanel,
            icon: const Icon(PhosphorIconsLight.sparkle, size: 16),
            label: Text(
              l.diskCleanerAskAgent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      if (!_isScanningFullDisk)
        boundedAction(
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(shape: _cleanerButtonShape),
            key: const ValueKey<String>('cleaner-select-drives'),
            onPressed: _returnToDriveSetup,
            icon: const Icon(PhosphorIconsLight.hardDrives, size: 16),
            label: Text(
              l.diskCleanerSelectDrives,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      boundedAction(
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(shape: _cleanerButtonShape),
          onPressed: () {
            if (_isScanningFullDisk) {
              _service.cancelFullDiskScan();
              _diskScanGeneration++;
              _cancelDiskProgressContextPublication();
              _diskProgressListenable.value = null;
              _isScanningFullDisk = false;
              setState(() {});
              return;
            }
            unawaited(_startScan(forceRefresh: true));
          },
          icon: Icon(
            _isScanningFullDisk
                ? Icons.stop_rounded
                : PhosphorIconsLight.arrowCounterClockwise,
            size: 16,
          ),
          label: Text(
            _isScanningFullDisk ? l.diskCleanerCancel : l.diskCleanerScanAgain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1120;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ValueListenableBuilder<FullDiskScanProgress?>(
                  valueListenable: _diskProgressListenable,
                  builder: (context, _, __) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      buildDriveInfo(),
                      if (hasStatus) ...[
                        const SizedBox(height: 6),
                        buildStatus(),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: actions,
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<FullDiskScanProgress?>(
                valueListenable: _diskProgressListenable,
                builder: (context, _, __) => Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: buildDriveInfo(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: buildStatus(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tree panel (left)
  // ---------------------------------------------------------------------------

  // Cached flattened rows for the tree view
  List<_FlatRow>? _cachedFlatRows;
  DiskTreeNode? _cachedFlatRoot;
  bool _flatRowsValid = false;

  Widget _buildTreePanel(
      ThemeData theme, AppLocalizations l, DiskTreeNode root) {
    // Re-flatten only when cache is invalid or the root object changed.
    if (!_flatRowsValid || _cachedFlatRows == null || _cachedFlatRoot != root) {
      // Every tree mutation invalidates the flat rows, so this is also the
      // one place that has to drop memoised preset matches.
      _invalidatePresetCache();
      final rows = <_FlatRow>[];
      void flatten(DiskTreeNode node, int depth, int parentSize) {
        if (!_passesTreeFilter(node)) return;
        rows.add(_FlatRow(node: node, depth: depth, parentSize: parentSize));
        if (node.isExpanded && !node.isFile) {
          for (final child in node.children) {
            flatten(child, depth + 1, node.sizeBytes);
          }
        }
      }

      for (final child in root.children) {
        flatten(child, 0, root.sizeBytes);
      }
      _cachedFlatRows = rows;
      _cachedFlatRoot = root;
      _flatRowsValid = true;
    }

    final flatRows = _cachedFlatRows!;

    return Column(
      children: [
        // Column headers
        Container(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 20), // expand arrow space
              Expanded(
                flex: 4,
                child: Text(l.diskCleanerColumnName,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: 80,
                child: Text(l.diskCleanerColumnSize,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: Text(l.diskCleanerColumnPercentOfParent,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: 60,
                child: Text(l.diskCleanerColumnFiles,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.right),
              ),
            ],
          ),
        ),
        // Tree rows — flat ListView.builder for smooth scrolling
        Expanded(
          child: root.children.isEmpty
              ? ValueListenableBuilder<FullDiskScanProgress?>(
                  valueListenable: _diskProgressListenable,
                  builder: (context, progress, child) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppWaveLoader(
                          size: 56,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanningFullDisk
                              ? l.diskCleanerBuildingTree
                              : l.diskCleanerNoFilesFound,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (progress != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            l.diskCleanerSizeFiles(_fmt(progress.bytesScanned),
                                progress.filesScanned),
                            key: const ValueKey<String>(
                              'cleaner-full-scan-tree-progress',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _treeScrollController,
                  itemCount: flatRows.length,
                  itemExtent: _treeRowExtent,
                  itemBuilder: (context, index) {
                    final row = flatRows[index];
                    return _FlatTreeRowWidget(
                      row: row,
                      theme: theme,
                      growth: _growthForNode(row.node),
                      selectedPaths: _selectedTreePathListenable,
                      focusedPath: _focusedTreePathListenable,
                      onTap: () => _selectTreeRow(row.node, flatRows),
                      onExpandToggle: row.node.isFile
                          ? null
                          : () => setState(() {
                                row.node.isExpanded = !row.node.isExpanded;
                                _flatRowsValid = false;
                              }),
                      onAskAi:
                          _aiAvailable ? () => _askAiAboutNode(row.node) : null,
                      onShowContextMenu: _showNodeContextMenu,
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Pie chart panel (right)
  // ---------------------------------------------------------------------------

  /// Index of the pie slice matching the currently focused tree node, so the
  /// chart and the tree visibly agree on what is selected.
  int? _pieHighlightIndex(List<DiskTreeNode> topChildren) {
    final focused = _selectedNode;
    if (focused == null) return null;
    for (var i = 0; i < topChildren.length; i++) {
      if (identical(topChildren[i], focused)) return i;
    }
    return null;
  }

  /// Maps a tap inside the pie to a slice index, mirroring the geometry in
  /// [_PieChartPainter]. Returns null for taps outside the circle or in the
  /// gap left by children beyond the top 10.
  int? _pieSegmentAt(
    Offset position,
    Size size,
    List<_PieSegment> segments,
    double total,
  ) {
    if (total <= 0) return null;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final delta = position - center;
    if (delta.distance > radius) return null;

    // The painter starts drawing at -pi/2 (12 o'clock) and sweeps clockwise.
    var angle = math.atan2(delta.dy, delta.dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    var start = 0.0;
    for (var i = 0; i < segments.length; i++) {
      final sweep = segments[i].value / total * 2 * math.pi;
      if (angle >= start && angle < start + sweep) return i;
      start += sweep;
    }
    return null;
  }

  /// Focuses [target] in the tree: expands every ancestor, selects the row,
  /// and scrolls it into view. Used by the pie slices and the legend so the
  /// chart acts as a navigator instead of a read-only picture.
  ///
  /// The chart itself deliberately stays on the current parent — re-rooting it
  /// would make the slice the user just clicked disappear from under the
  /// cursor.
  void _revealNodeInTree(DiskTreeNode target) {
    final root = _rootNode;
    if (root == null || target.fullPath.isEmpty) return;

    final targetUpper = target.fullPath.toUpperCase();
    bool expandTowards(DiskTreeNode node) {
      if (identical(node, target)) return true;
      for (final child in node.children) {
        final childUpper = child.fullPath.toUpperCase();
        // Prune branches that cannot contain the target.
        if (!identical(child, target) &&
            targetUpper != childUpper &&
            !targetUpper.startsWith('$childUpper\\')) {
          continue;
        }
        if (expandTowards(child)) {
          node.isExpanded = true;
          return true;
        }
      }
      return false;
    }

    expandTowards(root);

    setState(() {
      _selectedNode = target;
      _flatRowsValid = false;
    });
    _focusedTreePathListenable.value = target.fullPath;
    _selectionAnchorPath = target.fullPath;
    _resultsFocusNode.requestFocus();

    // The flat rows are rebuilt during the next build, so the row index is
    // only known after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _focusedRowIndex();
      if (index >= 0) _scrollTreeRowIntoView(index);
    });
  }

  Widget _buildPiePanel(
      ThemeData theme, AppLocalizations l, DiskTreeNode node) {
    if (_isScanningFullDisk) {
      return ValueListenableBuilder<FullDiskScanProgress?>(
        valueListenable: _diskProgressListenable,
        builder: (context, progress, child) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppWaveLoader(
                  size: 60,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  l.diskCleanerAnalyzingDisk,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress == null
                      ? l.diskCleanerPieChartPending
                      : l.diskCleanerScannedProgress(
                          _fmt(progress.bytesScanned), progress.filesScanned),
                  key: const ValueKey<String>(
                    'cleaner-full-scan-pie-progress',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (progress?.currentPath.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    progress!.currentPath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final children = node.children.where((c) => c.sizeBytes > 0).toList();
    if (children.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsLight.chartPie,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _isScanningFullDisk
                  ? l.diskCleanerPieChartPendingScan
                  : l.diskCleanerPieEmpty,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final topChildren = children.take(10).toList(growable: false);
    final segments = <_PieSegment>[];
    for (var i = 0; i < topChildren.length; i++) {
      final child = topChildren[i];
      segments.add(_PieSegment(
        value: child.sizeBytes.toDouble(),
        color: child.isJunk || child.hasJunkChildren
            ? Colors.orange
            : _pieColor(i),
        label: _displayName(l, child),
      ));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            node.name,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _fmt(node.sizeBytes),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          // Pie chart — clicking a slice reveals that folder in the tree.
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final index = _pieSegmentAt(
                      details.localPosition,
                      size,
                      segments,
                      node.sizeBytes.toDouble(),
                    );
                    if (index != null) {
                      _revealNodeInTree(topChildren[index]);
                    }
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _PieChartPainter(
                      segments: segments,
                      total: node.sizeBytes.toDouble(),
                      highlightIndex: _pieHighlightIndex(topChildren),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Expanded(
            child: ListView(
              children: topChildren.asMap().entries.map((entry) {
                final idx = entry.key;
                final c = entry.value;
                final color = c.isJunk || c.hasJunkChildren
                    ? Colors.orange
                    : _pieColor(idx);
                final pct = node.sizeBytes > 0
                    ? (c.sizeBytes / node.sizeBytes * 100).toStringAsFixed(1)
                    : '0';
                final isFocused =
                    _selectedNode != null && identical(_selectedNode, c);
                // The legend is the same control as the slice: tapping either
                // reveals that folder in the tree.
                return InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _revealNodeInTree(c),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    decoration: BoxDecoration(
                      color: isFocused
                          ? theme.colorScheme.primary.withValues(alpha: 0.10)
                          : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _displayName(l, c),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isFocused
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '$pct%  ${_fmt(c.sizeBytes)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOldLargeItemsPanel(
    ThemeData theme,
    AppLocalizations l,
    DiskTreeNode root,
  ) {
    if (_isScanningFullDisk || _lastDiskScanResult == null) {
      return const SizedBox.shrink();
    }

    final evidence = splitOldLargeEvidence(_lastDiskScanResult!.oldLargeItems);
    final items = filterOldLargeEvidence(
      _lastDiskScanResult!.oldLargeItems,
      _oldLargeEvidenceFilter,
    );
    final panelHeight =
        _oldLargeEvidenceExpanded ? (items.isEmpty ? 142.0 : 288.0) : 64.0;
    final foldersSection = _OldLargeEvidenceSection(
      keySuffix: 'folders',
      title: l.diskCleanerOldLargeFolders,
      items: evidence.folders,
    );
    final filesSection = _OldLargeEvidenceSection(
      keySuffix: 'files',
      title: l.diskCleanerOldLargeFiles,
      items: evidence.files,
    );

    String filterLabel(OldLargeEvidenceFilter filter) {
      switch (filter) {
        case OldLargeEvidenceFilter.all:
          return l.diskCleanerOldLargeAll;
        case OldLargeEvidenceFilter.folders:
          return l.diskCleanerOldLargeFolders;
        case OldLargeEvidenceFilter.files:
          return l.diskCleanerOldLargeFiles;
      }
    }

    int filterCount(OldLargeEvidenceFilter filter) {
      switch (filter) {
        case OldLargeEvidenceFilter.all:
          return evidence.totalCount;
        case OldLargeEvidenceFilter.folders:
          return evidence.folders.length;
        case OldLargeEvidenceFilter.files:
          return evidence.files.length;
      }
    }

    void selectFilter(OldLargeEvidenceFilter? filter) {
      if (filter == null || filter == _oldLargeEvidenceFilter) return;
      setState(() {
        _oldLargeEvidenceFilter = filter;
        if (_oldLargeItemsScrollController.hasClients) {
          _oldLargeItemsScrollController.jumpTo(0);
        }
      });
    }

    Widget buildEvidenceRow(FullDiskScanInsight item) {
      final activity = item.lastActivity;
      return InkWell(
        key: ValueKey<String>('cleaner-old-large-entry-${item.path}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          final node = findNearestDisplayedTreeNodeForPath(root, item.path);
          if (node != null) _revealNodeInTree(node);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.55,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  item.isFile
                      ? PhosphorIconsLight.file
                      : PhosphorIconsLight.folder,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.path,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _fmt(item.sizeBytes),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (activity != null)
                    Text(
                      l.diskCleanerOldLargeLastActivity(
                        _formatInsightDate(activity),
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 2),
              IconButton(
                key: ValueKey<String>('cleaner-old-large-open-${item.path}'),
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                tooltip: item.isFile ? l.openContainingFolder : l.openInNewTab,
                icon: const Icon(
                  PhosphorIconsLight.folderOpen,
                  size: 17,
                ),
                onPressed: () {
                  EntityOpenActions.openInNewTab(
                    context,
                    sourcePath: item.path,
                    preferredTabName: item.isFile
                        ? p.basename(p.dirname(item.path))
                        : p.basename(item.path),
                    openContainingFolder: item.isFile,
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSectionHeader(_OldLargeEvidenceSection section) {
      final isFolder = section.keySuffix == 'folders';
      return Padding(
        key: ValueKey<String>('cleaner-old-large-section-${section.keySuffix}'),
        padding: const EdgeInsets.fromLTRB(10, 7, 8, 5),
        child: Row(
          children: [
            Icon(
              isFolder ? PhosphorIconsLight.folder : PhosphorIconsLight.file,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                section.title,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${section.items.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSectionCard(_OldLargeEvidenceSection section) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.72),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildSectionHeader(section),
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Expanded(
              child: section.items.isEmpty
                  ? Center(
                      child: Text(
                        l.diskCleanerOldLargeEmpty,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : Scrollbar(
                      child: ListView.separated(
                        primary: false,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        itemCount: section.items.length,
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          indent: 44,
                          endIndent: 8,
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        itemBuilder: (context, index) =>
                            buildEvidenceRow(section.items[index]),
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    Widget buildStackedSections() {
      final sections = <_OldLargeEvidenceSection>[
        if (evidence.folders.isNotEmpty) foldersSection,
        if (evidence.files.isNotEmpty) filesSection,
      ];
      final children = <Widget>[];
      for (final section in sections) {
        children
          ..add(buildSectionHeader(section))
          ..addAll(section.items.map(buildEvidenceRow));
      }
      return Scrollbar(
        controller: _oldLargeItemsScrollController,
        thumbVisibility: items.length > 4,
        child: ListView(
          controller: _oldLargeItemsScrollController,
          primary: false,
          padding: const EdgeInsets.symmetric(vertical: 2),
          children: children,
        ),
      );
    }

    return Container(
      height: panelHeight,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    PhosphorIconsLight.clockCounterClockwise,
                    size: 17,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          l.diskCleanerOldLargeTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${evidence.totalCount}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_oldLargeEvidenceExpanded && evidence.totalCount > 0)
                  CbSelect<OldLargeEvidenceFilter>(
                    size: CbSelectSize.sm,
                    value: _oldLargeEvidenceFilter,
                    onChanged: selectFilter,
                    items: [
                      for (final filter in OldLargeEvidenceFilter.values)
                        CbSelectItem<OldLargeEvidenceFilter>(
                          value: filter,
                          label:
                              '${filterLabel(filter)} (${filterCount(filter)})',
                        ),
                    ],
                  ),
                const SizedBox(width: 4),
                IconButton(
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip: _oldLargeEvidenceExpanded ? l.close : l.open,
                  onPressed: () => setState(() {
                    _oldLargeEvidenceExpanded = !_oldLargeEvidenceExpanded;
                  }),
                  icon: Icon(
                    _oldLargeEvidenceExpanded
                        ? PhosphorIconsLight.caretUp
                        : PhosphorIconsLight.caretDown,
                    size: 17,
                  ),
                ),
              ],
            ),
          ),
          if (_oldLargeEvidenceExpanded) ...[
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          l.diskCleanerOldLargeEmpty,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final showColumns = _oldLargeEvidenceFilter ==
                                OldLargeEvidenceFilter.all &&
                            constraints.maxWidth >= 720;
                        if (showColumns) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: buildSectionCard(foldersSection)),
                              const SizedBox(width: 8),
                              Expanded(child: buildSectionCard(filesSection)),
                            ],
                          );
                        }
                        if (_oldLargeEvidenceFilter ==
                            OldLargeEvidenceFilter.folders) {
                          return buildSectionCard(foldersSection);
                        }
                        if (_oldLargeEvidenceFilter ==
                            OldLargeEvidenceFilter.files) {
                          return buildSectionCard(filesSection);
                        }
                        return buildStackedSections();
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom action bar
  // ---------------------------------------------------------------------------

  Widget _buildBottomBar(ThemeData theme, AppLocalizations l) {
    final root = _rootNode;
    if (root != null) _ensureCleanerAggregates(root);
    final junkBytes = root == null ? 0 : _cachedJunkBytes;
    final selectedBytes = _selectedJunkBytes(root);
    final cleaningBytes = _isCleaningJunk ? _pendingCleanBytes : selectedBytes;

    if (_isCleaningJunk) {
      // Drive the entire progress bar from the ValueNotifier so the disk
      // tree and pie chart panels (sitting in the same Scaffold) are NOT
      // rebuilt on every progress tick. This is what fixes the visible
      // stutter on the bar.
      return ValueListenableBuilder<_CleanProgressSnapshot>(
        valueListenable: _cleanProgress,
        builder: (context, snap, _) {
          final progress = snap.total > 0 ? snap.done / snap.total : null;
          final progressValue = progress?.clamp(0.0, 1.0);
          final progressPercent = progress == null
              ? null
              : (progress.clamp(0.0, 1.0) * 100).toStringAsFixed(0);
          final isPreparing = snap.total == 0;
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Icon(PhosphorIconsLight.broom,
                            size: 18, color: Colors.orange.shade700),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPreparing
                                ? l.diskCleanerPreparingFiles
                                : (snap.status.isEmpty
                                    ? l.diskCleanerCleaning
                                    : snap.status),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPreparing
                                ? (snap.currentPath.isEmpty
                                    ? l.diskCleanerScanningSelectedDirs
                                    : l.diskCleanerScanningPath(
                                        snap.currentPath))
                                : (snap.currentPath.isEmpty
                                    ? l.diskCleanerDeletingJunkHint
                                    : snap.currentPath),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const AppWaveLoader(size: 26, color: Colors.orange),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildProgressStatChip(
                      theme: theme,
                      icon: _selectedCleanMode == _CleanDeleteMode.permanent
                          ? PhosphorIconsLight.trash
                          : PhosphorIconsLight.recycle,
                      label: _selectedCleanMode == _CleanDeleteMode.permanent
                          ? l.diskCleanerPermanentDeleteLabel
                          : l.diskCleanerRecycleBinLabel,
                    ),
                    _buildProgressStatChip(
                      theme: theme,
                      icon: PhosphorIconsLight.chartBar,
                      label: l.diskCleanerProcessedCount(snap.done, snap.total),
                    ),
                    _buildProgressStatChip(
                      theme: theme,
                      icon: PhosphorIconsLight.hardDrive,
                      label: _fmt(cleaningBytes),
                    ),
                    if (progressPercent != null)
                      _buildProgressStatChip(
                        theme: theme,
                        icon: PhosphorIconsLight.percent,
                        label: '$progressPercent%',
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      progressPercent == null
                          ? l.diskCleanerDeletingItems
                          : '$progressPercent% ${l.diskCleanerCleaning}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${snap.total - snap.done} ${l.diskCleanerRemaining}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    }

    final selectionStatus = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          PhosphorIconsLight.broom,
          size: 18,
          color: Colors.orange.shade700,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            _reviewMode
                ? l.diskCleanerReviewModeSelected(_fmt(selectedBytes))
                : l.diskCleanerSelectedBytes(
                    _fmt(selectedBytes),
                    _fmt(junkBytes),
                  ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    final reviewActions = <Widget>[
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(shape: _cleanerButtonShape),
        onPressed: () => setState(() {
          _reviewMode = false;
          _flatRowsValid = false;
        }),
        icon: const Icon(PhosphorIconsLight.arrowLeft, size: 14),
        label: Text(l.diskCleanerBackToResults),
      ),
      if (_aiAvailable)
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(shape: _cleanerButtonShape),
          onPressed: _askAiReviewPending,
          icon: const Icon(PhosphorIconsLight.sparkle, size: 14),
          label: Text(l.diskCleanerReviewByAgent),
        ),
      SegmentedButton<_CleanDeleteMode>(
        segments: [
          ButtonSegment<_CleanDeleteMode>(
            value: _CleanDeleteMode.recycleBin,
            icon: const Icon(PhosphorIconsLight.recycle, size: 14),
            label: Text(l.diskCleanerMoveToRecycleBin),
          ),
          ButtonSegment<_CleanDeleteMode>(
            value: _CleanDeleteMode.permanent,
            icon: const Icon(PhosphorIconsLight.trash, size: 14),
            label: Text(l.diskCleanerPermanentDelete),
          ),
        ],
        selected: {_selectedCleanMode},
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return theme.colorScheme.onSurface;
          }),
          backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (!states.contains(WidgetState.selected)) {
              return theme.colorScheme.surface;
            }
            return _selectedCleanMode == _CleanDeleteMode.permanent
                ? Colors.red.shade700
                : theme.colorScheme.primary;
          }),
          side: WidgetStateProperty.resolveWith<BorderSide?>((states) {
            final color = states.contains(WidgetState.selected)
                ? _selectedCleanMode == _CleanDeleteMode.permanent
                    ? Colors.red.shade700
                    : theme.colorScheme.primary
                : theme.colorScheme.outlineVariant;
            return BorderSide(color: color);
          }),
          shape: WidgetStatePropertyAll<OutlinedBorder>(_cleanerButtonShape),
        ),
        onSelectionChanged: (selection) {
          if (selection.isEmpty) return;
          setState(() => _selectedCleanMode = selection.first);
        },
        showSelectedIcon: false,
      ),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: _selectedCleanMode == _CleanDeleteMode.permanent
              ? Colors.red.shade700
              : Colors.orange.shade700,
          foregroundColor: Colors.white,
          shape: _cleanerButtonShape,
        ),
        onPressed: _confirmCleanFromReview,
        icon: Icon(
          _selectedCleanMode == _CleanDeleteMode.permanent
              ? PhosphorIconsLight.trash
              : PhosphorIconsLight.recycle,
          size: 16,
        ),
        label: Text(
          _selectedCleanMode == _CleanDeleteMode.permanent
              ? l.diskCleanerDeletePermanentlyButton(_fmt(selectedBytes))
              : l.diskCleanerMoveToRecycleBinButton(_fmt(selectedBytes)),
        ),
      ),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: _reviewMode
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                selectionStatus,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: reviewActions,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: selectionStatus),
                const SizedBox(width: 12),
                FilledButton.icon(
                  key: const ValueKey<String>('cleaner-review-and-clean'),
                  style: FilledButton.styleFrom(shape: _cleanerButtonShape),
                  onPressed: selectedBytes > 0 ? _enterReviewMode : null,
                  icon: const Icon(PhosphorIconsLight.eye, size: 18),
                  label: Text(
                    l.diskCleanerReviewAndClean(_fmt(selectedBytes)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildProgressStatChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Sum of exact canonical cleanup targets without walking the scan tree.
  int _selectedJunkBytes(DiskTreeNode? root) {
    if (root == null) return 0;
    return _selectedTreeTargets.fold<int>(
      0,
      (total, node) => total + node.sizeBytes,
    );
  }

  void _enterReviewMode({List<JunkItem>? exactCleanableItems}) {
    // Build pending items list from selected tree nodes so AI tool + cleanup
    // helpers have data ready. The tree itself is filtered via _reviewMode
    // flag — no separate page, no rebuild.
    final items = exactCleanableItems ??
        _selectedTreeNodes()
            .map(
              (node) => JunkItem(
                path: node.fullPath,
                sizeBytes: node.sizeBytes,
                categoryId: node.junkCategoryId ?? 'selected_item',
                // Tree selections are explicit user choices, so deleting a
                // selected directory should delete the directory itself, not
                // only its contents. `isContainerOnly` is reserved for
                // scanner rules such as empty-only cache folders.
                isContainerOnly: false,
                isUserSelected: true,
              ),
            )
            .toList(growable: false);
    if (items.isEmpty) return;

    final root = _rootNode;
    if (root != null) {
      DiskTreeSelection.expandAncestorsOfSelection(root);
    }
    _rebuildReviewVisibleTreePaths();
    final totalBytes = items.fold<int>(0, (s, i) => s + i.sizeBytes);
    setState(() {
      _pendingCleanItems = items;
      _pendingCleanBytes = totalBytes;
      _reviewMode = true;
      _flatRowsValid = false;
    });
    _service.pendingCleanupItems = items;
    _service.pendingCleanupBytes = totalBytes;
  }

  /// Current free bytes on the selected drive, or null if it can't be read.
  Future<int?> _currentFreeBytes() async {
    final drivePath = _selectedDrive;
    if (drivePath == null) return null;
    try {
      final drives = await _service.getDriveSpace();
      for (final drive in drives) {
        if (drive.path == drivePath) return drive.freeBytes;
      }
    } catch (error) {
      debugPrint('Unable to read drive free space: $error');
    }
    return null;
  }

  /// Re-reads free space after a cleanup so the cleaned screen can show the
  /// real before/after, not just the sum of the deleted file sizes.
  Future<void> _refreshFreeSpaceAfterClean() async {
    final free = await _currentFreeBytes();
    if (!mounted || free == null) return;
    setState(() {
      _freeBytesAfterClean = free;
      _drives = _drives
          .map((d) => d.path == _selectedDrive
              ? DriveSpace(
                  path: d.path,
                  label: d.label,
                  totalBytes: d.totalBytes,
                  freeBytes: free,
                  requiresAdmin: d.requiresAdmin,
                )
              : d)
          .toList(growable: false);
    });
  }

  /// Localised title for a junk category, falling back to the English
  /// [CleanerCategory.displayName] for categories with no translation yet.
  static String _junkCategoryTitle(AppLocalizations l, String categoryId) {
    switch (categoryId) {
      case 'windows_temp':
        return l.diskCleanerCategoryWindowsTemp;
      case 'browser_cache':
        return l.diskCleanerCategoryBrowserCache;
      case 'recycle_bin':
        return l.diskCleanerCategoryRecycleBin;
      case 'thumbnail_cache':
        return l.diskCleanerCategoryThumbnailCache;
      case 'app_cache':
        return l.diskCleanerCategoryAppCache;
      case 'crash_dumps_logs':
        return l.diskCleanerCategoryCrashLogs;
      case 'windows_update_cache':
        return l.diskCleanerCategoryWindowsUpdate;
      case 'prefetch':
        return l.diskCleanerCategoryPrefetch;
      case 'delivery_optimization':
        return l.diskCleanerCategoryDeliveryOptimization;
      case 'dev_cache':
        return l.diskCleanerCategoryDevCache;
      default:
        return CleanerCategories.byId(categoryId)?.displayName ?? categoryId;
    }
  }

  /// Plain-language answer to "why is this junk?", shown next to each item so
  /// the user can judge a deletion without opening the folder.
  static String _junkReason(AppLocalizations l, String? categoryId) {
    switch (categoryId) {
      case 'windows_temp':
        return l.diskCleanerReasonWindowsTemp;
      case 'browser_cache':
        return l.diskCleanerReasonBrowserCache;
      case 'recycle_bin':
        return l.diskCleanerReasonRecycleBin;
      case 'thumbnail_cache':
        return l.diskCleanerReasonThumbnailCache;
      case 'app_cache':
        return l.diskCleanerReasonAppCache;
      case 'crash_dumps_logs':
        return l.diskCleanerReasonCrashLogs;
      case 'windows_update_cache':
        return l.diskCleanerReasonWindowsUpdate;
      case 'prefetch':
        return l.diskCleanerReasonPrefetch;
      case 'delivery_optimization':
        return l.diskCleanerReasonDeliveryOptimization;
      case 'dev_cache':
        return l.diskCleanerReasonDevCache;
      default:
        return l.diskCleanerReasonGeneric;
    }
  }

  /// Category IDs that the cleaner classifies as safe to remove without the
  /// user auditing individual paths. Derived from the declarative category
  /// table so a new safe category is picked up automatically.
  static List<String> _quickCleanCategoryIds() => CleanerCategories.all()
      .where((c) =>
          c.safety == CleanerSafety.safe &&
          c.defaultEnabled &&
          !c.requiresAdmin)
      .map((c) => c.id)
      .toList(growable: false);

  /// One-tap cleanup of the safe categories. Scans, shows a grouped preview so
  /// the user still sees exactly what will go, then reuses the normal
  /// [_cleanJunk] pipeline (Recycle Bin, never permanent).
  Future<void> _startQuickClean() async {
    if (_isQuickCleaning || _isCleaningJunk || _isScanningFullDisk) return;
    final drive = _selectedDrive;
    if (drive == null) return;

    setState(() => _isQuickCleaning = true);
    ScanReport report;
    try {
      report = await _service.scanJunk(
        drivePaths: <String>[drive],
        categoryIds: _quickCleanCategoryIds(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isQuickCleaning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.diskCleanerScanFailedMsg('$error'),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isQuickCleaning = false);

    final items = report.allItems;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.diskCleanerQuickCleanNothing),
        ),
      );
      return;
    }

    final confirmed = await _showQuickCleanPreviewDialog(report);
    if (confirmed != true || !mounted) return;

    final totalBytes = items.fold<int>(0, (sum, i) => sum + i.sizeBytes);
    setState(() {
      _pendingCleanItems = items;
      _pendingCleanBytes = totalBytes;
      _selectedCleanMode = _CleanDeleteMode.recycleBin;
    });
    await _cleanJunk(permanent: false);
  }

  /// Grouped "here is what will be deleted" sheet shown before a quick clean.
  /// Each row is a category with its item count, size, and the plain-language
  /// reason it is considered junk.
  Future<bool?> _showQuickCleanPreviewDialog(ScanReport report) {
    final l = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entries = report.itemsByCategory.entries
        .where((e) => e.value.isNotEmpty)
        .toList(growable: false)
      ..sort((a, b) {
        final aBytes = a.value.fold<int>(0, (s, i) => s + i.sizeBytes);
        final bBytes = b.value.fold<int>(0, (s, i) => s + i.sizeBytes);
        return bBytes.compareTo(aBytes);
      });

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.diskCleanerQuickCleanReviewTitle),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.diskCleanerQuickCleanReviewSubtitle(
                  report.totalCount,
                  _fmt(report.totalBytes),
                ),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 12),
                  itemBuilder: (_, index) {
                    final entry = entries[index];
                    final bytes =
                        entry.value.fold<int>(0, (s, i) => s + i.sizeBytes);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _junkCategoryTitle(l, entry.key),
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _junkReason(l, entry.key),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _fmt(bytes),
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(PhosphorIconsLight.recycle,
                      size: 15, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l.diskCleanerQuickCleanRecycleNote,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(shape: _cleanerButtonShape),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(shape: _cleanerButtonShape),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
                l.diskCleanerMoveToRecycleBinButton(_fmt(report.totalBytes))),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCleanFromReview() async {
    if (_selectedCleanMode == _CleanDeleteMode.permanent) {
      final confirmed = await _showPermanentDeleteDialog(
        itemCount: _pendingCleanItems.length,
        bytes: _pendingCleanBytes,
        fromRecycleBin: false,
      );
      if (confirmed != true) return;
    }
    setState(() {
      _reviewMode = false;
      _flatRowsValid = false;
    });
    await _cleanJunk(
        permanent: _selectedCleanMode == _CleanDeleteMode.permanent);
  }

  Future<void> _cleanJunk({
    required bool permanent,
    bool showCleanedResult = true,
  }) async {
    if (_isCleaningJunk || _pendingCleanItems.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    _freeBytesBeforeClean = await _currentFreeBytes();
    _freeBytesAfterClean = null;
    if (!mounted) return;
    setState(() {
      _isCleaningJunk = true;
      _cleanedSkippedInUseCount = 0;
      _cleanedSkippedByUserCount = 0;
      _skipAllDeleteFailures = false;
    });

    // Let Flutter paint the initial progress UI before the first native
    // delete batch starts. Without this, the bottom bar can stay visually at
    // 0 / N until the first chunk completes.
    await WidgetsBinding.instance.endOfFrame;
    _lastCleanProgressUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    _cleanProgress.value = _CleanProgressSnapshot(
      status: permanent
          ? l.diskCleanerPermanentlyDeleting
          : l.diskCleanerMovingToRecycleBin,
    );

    try {
      final items = List<JunkItem>.from(_pendingCleanItems);
      final result = await _service.cleanJunk(
        items: items,
        permanent: permanent,
        onDeleteFailure: _promptDeleteFailureAction,
        onProgress: (done, total, currentPath) {
          if (!mounted) return;
          final now = DateTime.now();
          final isFinal = total > 0 && done >= total;
          final isPreparing = total == 0;
          if (!isFinal &&
              !isPreparing &&
              now.difference(_lastCleanProgressUiUpdate) <
                  _cleanProgressUiThrottle) {
            return;
          }
          _lastCleanProgressUiUpdate = now;
          _cleanProgress.value = _CleanProgressSnapshot(
            done: done,
            total: total,
            currentPath: currentPath ?? '',
            status: permanent
                ? l.diskCleanerPermanentlyDeleting
                : l.diskCleanerMovingToRecycleBin,
          );
        },
      );

      if (!mounted) return;
      final succeededSet = result.succeeded.toSet();
      final cleanedItems =
          items.where((i) => succeededSet.contains(i.path)).toList();

      // Prune deleted paths from the in-memory tree so returning to the
      // results view shows the freed space without a re-scan.
      if (_rootNode != null && succeededSet.isNotEmpty) {
        final deletedUpper = succeededSet.map((p) => p.toUpperCase()).toSet();
        _pruneDeletedPaths(_rootNode!, deletedUpper);
        _recalculateTreeStats(_rootNode!);
        _rootNode!.invalidateJunkCache();
        _aggregateCacheRoot = null;
        // If the currently-viewed pie node was deleted, fall back to root.
        if (_selectedNode != null &&
            deletedUpper.contains(_selectedNode!.fullPath.toUpperCase())) {
          _selectedNode = _rootNode;
          _chartNode = _rootNode;
        }
        _selectedTreeTargets.removeWhere(
          (target) => deletedUpper.contains(target.fullPath.toUpperCase()),
        );
        _rebuildReviewVisibleTreePaths();
        _publishTreeSelection();
        if (_selectionAnchorPath != null &&
            deletedUpper.contains(_selectionAnchorPath!.toUpperCase())) {
          _selectionAnchorPath = null;
        }
      }

      setState(() {
        _isCleaningJunk = false;
        _pendingCleanItems = [];
        _pendingCleanBytes = 0;
        _cleanedItems =
            showCleanedResult && !permanent ? cleanedItems : const [];
        _cleanedFreedBytes = result.freedBytes;
        _cleanedFailureCount = result.failureCount;
        _cleanedSkippedInUseCount = result.skippedInUseCount;
        _cleanedSkippedByUserCount = result.skippedByUserCount;
        _lastCleanSuccessCount = result.successCount;
        _lastCleanWasPermanent = permanent;
        _phase = showCleanedResult ? _Phase.cleaned : _Phase.results;
        _cachedFlatRoot = null;
        _flatRowsValid = false;
      });
      _service.pendingCleanupItems = const [];
      _service.pendingCleanupBytes = 0;
      unawaited(_refreshFreeSpaceAfterClean());
      if (result.skippedInUseCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!
                  .diskCleanerSkippedInUseSnack(result.skippedInUseCount),
            ),
          ),
        );
      } else if (result.skippedByUserCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.diskCleanerSkippedAfterFailureSnack(
                  result.skippedByUserCount),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCleaningJunk = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .diskCleanerCleanupFailedMsg('$e'))),
      );
    }
  }

  Future<void> _permanentDeleteCleaned() async {
    if (_isPermanentDeleting) return;
    if (_cleanedItems.isEmpty) return;

    final confirmed = await _showPermanentDeleteDialog(
      itemCount: _cleanedItems.length,
      bytes: _cleanedFreedBytes,
      fromRecycleBin: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isPermanentDeleting = true;
      _skipAllDeleteFailures = false;
      _permanentDone = 0;
      _permanentTotal = _cleanedItems.length;
    });

    try {
      // Re-scan Recycle Bin to find current entries that match our cleaned
      // paths, so we can permanent-delete them via the Recycle Bin API.
      final binReport = await _service.scanJunk(
        drivePaths: [_selectedDrive ?? 'C:\\'],
        categoryIds: const ['recycle_bin'],
      );
      if (!mounted) return;

      final originalPaths =
          _cleanedItems.map((i) => i.path.toUpperCase()).toSet();
      final toDelete = binReport.allItems.where((i) {
        final orig = (i.originalPath ?? '').toUpperCase();
        return originalPaths.contains(orig);
      }).toList();

      // If we couldn't match against the bin (e.g. user emptied externally),
      // fall back to direct permanent delete of the cleaned paths if they
      // still exist on disk.
      final items = toDelete.isEmpty ? _cleanedItems : toDelete;

      final result = await _service.cleanJunk(
        items: items,
        permanent: true,
        onDeleteFailure: _promptDeleteFailureAction,
        onProgress: (done, total, currentPath) {
          if (!mounted) return;
          setState(() {
            _permanentDone = done;
            _permanentTotal = total;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isPermanentDeleting = false;
        _cleanedItems = [];
        _cleanedFreedBytes = result.freedBytes;
        _cleanedFailureCount = result.failureCount;
        _cleanedSkippedInUseCount = result.skippedInUseCount;
        _cleanedSkippedByUserCount = result.skippedByUserCount;
        _lastCleanSuccessCount = result.successCount;
        _lastCleanWasPermanent = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.skippedInUseCount > 0
              ? AppLocalizations.of(context)!
                  .diskCleanerPermanentDeletedWithInUse(result.successCount,
                      _fmt(result.freedBytes), result.skippedInUseCount)
              : result.skippedByUserCount > 0
                  ? AppLocalizations.of(context)!
                      .diskCleanerPermanentDeletedWithSkipped(
                          result.successCount,
                          _fmt(result.freedBytes),
                          result.skippedByUserCount)
                  : AppLocalizations.of(context)!
                      .diskCleanerPermanentDeletedSuccess(
                          result.successCount, _fmt(result.freedBytes))),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPermanentDeleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!
                .diskCleanerPermanentDeleteFailedMsg('$e'))),
      );
    }
  }

  Future<bool?> _showPermanentDeleteDialog({
    required int itemCount,
    required int bytes,
    required bool fromRecycleBin,
  }) {
    final l = AppLocalizations.of(context)!;
    final content = fromRecycleBin
        ? l.diskCleanerPermanentDeleteFromBinContent(itemCount, _fmt(bytes))
        : l.diskCleanerPermanentDeleteSelectedContent(itemCount, _fmt(bytes));

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.diskCleanerPermanentDeleteConfirmTitle),
        content: Text(content),
        actions: [
          TextButton(
            style: TextButton.styleFrom(shape: _cleanerButtonShape),
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: _cleanerButtonShape,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l.diskCleanerPermanentDeleteLabel),
          ),
        ],
      ),
    );
  }

  Future<CleanFailureAction> _promptDeleteFailureAction(
    CleanFailureDetails details,
  ) async {
    if (!mounted) return CleanFailureAction.skip;
    if (_skipAllDeleteFailures) return CleanFailureAction.skipAll;

    // Reflect "waiting for decision" state in the progress notifier so the
    // bottom bar updates without rebuilding the whole screen.
    final l = AppLocalizations.of(context)!;
    final prev = _cleanProgress.value;
    _cleanProgress.value = _CleanProgressSnapshot(
      done: prev.done,
      total: prev.total,
      currentPath: details.item.path,
      status: l.diskCleanerWaitingDecision,
    );

    final fileName = _fileBasename(details.item.path);
    final actionLabel = details.permanent
        ? l.diskCleanerPermanentDeleteLabel
        : l.diskCleanerRecycleBinLabel;
    final reasonText =
        details.isInUse ? l.diskCleanerFileInUse : details.reason;

    var skipAll = false;
    final action = await showDialog<CleanFailureAction>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: Text('${l.delete}: $actionLabel'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fileName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SelectableText(
                    details.item.path,
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(reasonText),
                  if (details.isInUse) ...[
                    const SizedBox(height: 8),
                    Text(
                      l.diskCleanerRetryInUseHint,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (details.blockedPath != null &&
                      details.blockedPath != details.item.path) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${l.diskCleanerBlockedBy} ${details.blockedPath}',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: skipAll,
                    onChanged: (value) {
                      setDialogState(() => skipAll = value ?? false);
                    },
                    title: Text(l.diskCleanerSkipAllRemaining),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(shape: _cleanerButtonShape),
                  onPressed: () {
                    if (skipAll) {
                      _skipAllDeleteFailures = true;
                      Navigator.of(ctx).pop(CleanFailureAction.skipAll);
                      return;
                    }
                    Navigator.of(ctx).pop(CleanFailureAction.skip);
                  },
                  child: Text(l.diskCleanerSkip),
                ),
                if (!details.isInUse)
                  FilledButton(
                    style: FilledButton.styleFrom(shape: _cleanerButtonShape),
                    onPressed: () =>
                        Navigator.of(ctx).pop(CleanFailureAction.retry),
                    child: Text(l.diskCleanerTryAgain),
                  ),
              ],
            ),
          ),
        ) ??
        CleanFailureAction.skip;

    // Reset the "Waiting for your decision..." status set when the dialog
    // opened. We MUST NOT use setState here — the cleaner screen is
    // ~3000 lines and rebuilding it (including the disk tree and pie
    // chart) right after the dialog closes is what was visibly freezing
    // the UI when users tapped Skip while Skip all was active. Push the
    // status back into the throttled progress notifier instead so only
    // the bottom progress bar repaints.
    if (mounted) {
      final prev = _cleanProgress.value;
      _cleanProgress.value = _CleanProgressSnapshot(
        done: prev.done,
        total: prev.total,
        currentPath: prev.currentPath,
        status: details.permanent
            ? l.diskCleanerPermanentlyDeleting
            : l.diskCleanerMovingToRecycleBin,
      );
    }

    return action;
  }
  // ---------------------------------------------------------------------------
  // Cleaned phase — list of files moved to Recycle Bin + permanent delete
  // ---------------------------------------------------------------------------

  /// Closes the loop after a cleanup: shows the drive's free space before and
  /// after, and what has been growing since the previous scan — so the screen
  /// answers "what changed, and what should I watch" instead of just "done".
  Widget _buildCleanedOutcomeCard(ThemeData theme, AppLocalizations l) {
    final before = _freeBytesBeforeClean;
    final after = _freeBytesAfterClean;
    final growth = _recentFolderGrowth.take(3).toList(growable: false);
    final hasFreeSpaceDelta = before != null && after != null && after > before;
    if (!hasFreeSpaceDelta && growth.isEmpty) return const SizedBox.shrink();

    final drive = _selectedDrive;
    DriveSpace? driveSpace;
    for (final candidate in _drives) {
      if (candidate.path == drive) {
        driveSpace = candidate;
        break;
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasFreeSpaceDelta) ...[
            Row(
              children: [
                Icon(PhosphorIconsLight.hardDrive,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.diskCleanerFreeSpaceBeforeAfter(
                      _fmt(before),
                      _fmt(after),
                    ),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (driveSpace != null && driveSpace.totalBytes > 0) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _driveUsedFraction(driveSpace),
                  minHeight: 6,
                  backgroundColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.10),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
              ),
            ],
          ],
          if (hasFreeSpaceDelta && growth.isNotEmpty) const Divider(height: 20),
          if (growth.isNotEmpty) ...[
            Row(
              children: [
                Icon(PhosphorIconsLight.trendUp,
                    size: 15, color: theme.colorScheme.tertiary),
                const SizedBox(width: 8),
                Text(
                  l.diskCleanerGrowthWatchTitle,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final folder in growth)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  l.diskCleanerGrowthWatchLine(
                    folder.path,
                    _fmt(folder.increasedBytes),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildCleaned(ThemeData theme, AppLocalizations l) {
    final successCount =
        _lastCleanWasPermanent ? _lastCleanSuccessCount : _cleanedItems.length;
    return Column(
      key: const ValueKey('cleaned'),
      children: [
        // Top bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(PhosphorIconsLight.checkCircle,
                  size: 20, color: Colors.green),
              const SizedBox(width: 10),
              Text(
                l.diskCleanerCleanDone,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l.diskCleanerFreedBadge(
                      _fmt(_cleanedFreedBytes), successCount),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
              if (_cleanedFailureCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    l.diskCleanerFailedBadge(_cleanedFailureCount),
                    style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                  ),
                ),
              ],
              if (_cleanedSkippedInUseCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    l.diskCleanerInUseBadge(_cleanedSkippedInUseCount),
                    style:
                        TextStyle(fontSize: 11, color: Colors.orange.shade800),
                  ),
                ),
              ],
              if (_cleanedSkippedByUserCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    l.diskCleanerSkippedBadge(_cleanedSkippedByUserCount),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (_rootNode != null) ...[
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(shape: _cleanerButtonShape),
                  onPressed: _continueToResults,
                  icon: const Icon(PhosphorIconsLight.arrowLeft, size: 16),
                  label: Text(l.diskCleanerContinue),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: _cleanerButtonShape),
                onPressed: () {
                  setState(() {
                    _cleanedItems = [];
                    _cleanedSkippedInUseCount = 0;
                    _cleanedSkippedByUserCount = 0;
                    _phase = _Phase.setup;
                  });
                  _startScan(forceRefresh: true);
                },
                icon: const Icon(PhosphorIconsLight.arrowCounterClockwise,
                    size: 16),
                label: Text(l.diskCleanerScanAgain),
              ),
            ],
          ),
        ),
        _buildCleanedOutcomeCard(theme, l),
        if (_cleanedSkippedInUseCount > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsLight.warning,
                    size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.diskCleanerSkippedInUseBanner(_cleanedSkippedInUseCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_cleanedSkippedByUserCount > 0)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsLight.arrowRight,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.diskCleanerSkippedByUserBanner(
                        _cleanedSkippedByUserCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),

        if (_lastCleanWasPermanent) ...[
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsLight.trash,
                      size: 48, color: Colors.red.shade700),
                  const SizedBox(height: 12),
                  Text(
                    l.diskCleanerDeletedPermanentlyBody(successCount),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.diskCleanerFreedSpace(_fmt(_cleanedFreedBytes)),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsLight.trash,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  l.diskCleanerPermanentDeleteFinished(successCount),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ] else ...[
          // Column header
          Container(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(l.diskCleanerColumnFileName,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 4,
                  child: Text(l.diskCleanerColumnPath,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  width: 80,
                  child: Text(l.diskCleanerColumnSize,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.right),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: Text(l.diskCleanerColumnCategory,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),

          // File list
          Expanded(
            child: _cleanedItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(PhosphorIconsLight.checkCircle,
                            size: 48, color: Colors.green),
                        const SizedBox(height: 12),
                        Text(l.diskCleanerRecycleBinEmpty,
                            style: theme.textTheme.titleSmall),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _cleanedItems.length,
                    itemExtent: 34,
                    itemBuilder: (context, index) {
                      final item = _cleanedItems[index];
                      final fileName = _fileBasename(item.path);
                      final dirPath = _fileParentDir(item.path);
                      final isEven = index % 2 == 0;

                      return Container(
                        color: isEven
                            ? Colors.transparent
                            : theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.15),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            // File name
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  Icon(PhosphorIconsLight.recycle,
                                      size: 13,
                                      color:
                                          theme.colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      fileName,
                                      style: const TextStyle(fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Path
                            Expanded(
                              flex: 4,
                              child: Text(
                                dirPath,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Size
                            SizedBox(
                              width: 80,
                              child: Text(
                                _fmt(item.sizeBytes),
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Category
                            SizedBox(
                              width: 100,
                              child: Text(
                                item.categoryId,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.orange.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Bottom bar: permanent delete
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                Icon(PhosphorIconsLight.recycle,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  _isPermanentDeleting
                      ? l.diskCleanerPermanentDeletingProgress(
                          _permanentDone, _permanentTotal)
                      : l.diskCleanerItemsInRecycleBin(
                          _cleanedItems.length, _fmt(_cleanedFreedBytes)),
                  style: theme.textTheme.bodyMedium,
                ),
                if (_isPermanentDeleting) ...[
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _isPermanentDeleting && _permanentDone == 0
                            ? null
                            : _permanentTotal > 0
                                ? (_permanentDone / _permanentTotal)
                                    .clamp(0.0, 1.0)
                                : null,
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_cleanedItems.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      shape: _cleanerButtonShape,
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                    ),
                    onPressed:
                        !_isPermanentDeleting ? _permanentDeleteCleaned : null,
                    icon: _isPermanentDeleting
                        ? const AppWaveLoader(size: 22, color: Colors.white)
                        : const Icon(PhosphorIconsLight.trash, size: 16),
                    label: Text(_isPermanentDeleting
                        ? l.diskCleanerDeletingLabel
                        : l.diskCleanerPermanentDeleteLabel),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _fileBasename(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? path : path.substring(i + 1);
  }

  static String _fileParentDir(String path) {
    final i = path.lastIndexOf(RegExp(r'[\\/]'));
    return i > 0 ? path.substring(0, i) : path;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _buildAcrylicChip({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Color _pieColor(int index) {
    const colors = [
      Color(0xFF4CAF50),
      Color(0xFF2196F3),
      Color(0xFF9C27B0),
      Color(0xFFFF9800),
      Color(0xFF00BCD4),
      Color(0xFFE91E63),
      Color(0xFF8BC34A),
      Color(0xFF3F51B5),
      Color(0xFFCDDC39),
      Color(0xFF795548),
    ];
    return colors[index % colors.length];
  }

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _formatInsightDate(DateTime date) {
    final local = date.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}';
  }

  Future<void> _refreshNodeSubtree(DiskTreeNode node) async {
    if (_isRefreshingNode || node.fullPath.isEmpty) return;

    final root = _rootNode;
    if (root == null) return;

    setState(() {
      _isRefreshingNode = true;
    });

    try {
      final expandedPaths = _collectExpandedPaths(node);
      final selectedPaths = _collectSelectedPaths(node);
      final handle = await _service.scanFullDisk(drivePath: node.fullPath);
      final result = await handle.future;
      _service.markJunkNodes(result.root);
      _applyExpandedPaths(result.root, expandedPaths);
      _applySelectedPaths(result.root, selectedPaths);

      if (!mounted) return;

      setState(() {
        _copyNodeData(node, result.root);
        _recalculateTreeStats(root);
        _service.markJunkNodes(root);
        _aggregateCacheRoot = null;
        if (_selectedNode?.fullPath == node.fullPath) {
          _selectedNode = node;
        }
        _flatRowsValid = false;
      });
      _replaceTreeTargets(DiskTreeSelection.collectDeletionTargets(root));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingNode = false;
        });
      }
    }
  }

  Set<String> _collectSelectedPaths(DiskTreeNode node) {
    final paths = <String>{};

    void visit(DiskTreeNode current) {
      if (current.isSelectedForDeletion && current.fullPath.isNotEmpty) {
        paths.add(current.fullPath.toUpperCase());
      }
      for (final child in current.children) {
        visit(child);
      }
    }

    visit(node);
    return paths;
  }

  void _applySelectedPaths(DiskTreeNode node, Set<String> paths) {
    node.isSelectedForDeletion = paths.contains(node.fullPath.toUpperCase());
    for (final child in node.children) {
      _applySelectedPaths(child, paths);
    }
  }

  void _copyNodeData(DiskTreeNode target, DiskTreeNode source) {
    target.sizeBytes = source.sizeBytes;
    target.fileCount = source.fileCount;
    target.junkCategoryId = source.junkCategoryId;
    target.isSelectedForDeletion = source.isSelectedForDeletion;
    target.replaceChildren(source.children);
  }

  void _recalculateTreeStats(DiskTreeNode node) {
    if (node.isFile) return;

    var totalBytes = 0;
    var totalFiles = 0;
    for (final child in node.children) {
      if (!child.isFile) {
        _recalculateTreeStats(child);
      }
      totalBytes += child.sizeBytes;
      totalFiles += child.fileCount;
    }
    node.sizeBytes = totalBytes;
    node.fileCount = totalFiles;
  }

  Future<void> _showNodeProperties(DiskTreeNode node) async {
    final l10n = AppLocalizations.of(context)!;
    final entity = node.isFile ? File(node.fullPath) : Directory(node.fullPath);

    try {
      final stat = await entity.stat();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.properties),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _nodePropertyRow(l10n.fileName, node.name),
                const Divider(),
                _nodePropertyRow(l10n.filePath, node.fullPath),
                const Divider(),
                _nodePropertyRow(l10n.columnSize, _fmt(node.sizeBytes)),
                const Divider(),
                _nodePropertyRow(l10n.files, '${node.fileCount}'),
                const Divider(),
                _nodePropertyRow(
                  l10n.fileModified,
                  stat.modified.toString().split('.').first,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(shape: _cleanerButtonShape),
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close.toUpperCase()),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load properties: $e')),
      );
    }
  }

  Widget _nodePropertyRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  /// Show the cleaner-specific context menu for a disk tree node.
  void _showNodeContextMenu(DiskTreeNode node, Offset globalPosition) {
    if (node.fullPath.isEmpty) return;

    final l10n = AppLocalizations.of(context)!;
    final entity = node.isFile ? File(node.fullPath) : Directory(node.fullPath);
    final isDesktopPlatform =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final isImage = node.isFile && FileTypeUtils.isImageFile(node.fullPath);
    final isVideo = node.isFile && FileTypeUtils.isVideoFile(node.fullPath);
    final canShowShellMenu = Platform.isWindows &&
        FileSystemEntity.typeSync(node.fullPath) !=
            FileSystemEntityType.notFound;
    final sections = <ContextMenuSection>[
      ContextMenuSection(
        title: l10n.open,
        actions: [
          if (_aiAvailable)
            ContextMenuAction(
              id: 'ask_cb_agent',
              label: node.isFile
                  ? l10n.askCbAgentAboutThisFile
                  : l10n.askCbAgentAboutThisFolder,
              icon: PhosphorIconsLight.sparkle,
              onSelected: (_) => _askAiAboutNode(node),
            ),
          if (node.isFile && isVideo)
            ContextMenuAction(
              id: 'play_video',
              label: l10n.playVideo,
              icon: PhosphorIconsLight.playCircle,
              onSelected: (_) => ExternalAppHelper.openFileWithApp(
                  node.fullPath, 'shell_open'),
            ),
          if (node.isFile && isImage)
            ContextMenuAction(
              id: 'view_image',
              label: l10n.viewImage,
              icon: PhosphorIconsLight.image,
              onSelected: (_) => ExternalAppHelper.openFileWithApp(
                  node.fullPath, 'shell_open'),
            ),
          if (node.isFile)
            ContextMenuAction(
              id: 'open',
              label: l10n.open,
              icon: PhosphorIconsLight.file,
              onSelected: (_) => ExternalAppHelper.openFileWithApp(
                  node.fullPath, 'shell_open'),
            ),
          if (node.isFile && isDesktopPlatform)
            ContextMenuAction(
              id: 'open_file_location',
              label: 'Open file location',
              icon: PhosphorIconsLight.folderOpen,
              onSelected: (_) => EntityOpenActions.openInNewTab(
                context,
                sourcePath: node.fullPath,
                preferredTabName: p.basename(p.dirname(node.fullPath)),
                openContainingFolder: true,
              ),
            ),
          if (isDesktopPlatform)
            ContextMenuAction(
              id: 'open_in_new_tab',
              label: l10n.openInNewTab,
              icon: PhosphorIconsLight.squaresFour,
              onSelected: (_) => EntityOpenActions.openInNewTab(
                context,
                sourcePath: node.fullPath,
              ),
            ),
          if (isDesktopPlatform)
            ContextMenuAction(
              id: 'open_in_new_window',
              label: '${l10n.open} ${l10n.newWindow.toLowerCase()}',
              icon: PhosphorIconsLight.appWindow,
              onSelected: (_) => EntityOpenActions.openInNewWindow(
                context,
                sourcePath: node.fullPath,
              ),
            ),
          if (node.isFile)
            ContextMenuAction(
              id: 'open_with',
              label: l10n.openWith,
              icon: PhosphorIconsLight.arrowSquareOut,
              onSelected: (_) => RouteUtils.showAcrylicDialog(
                context: context,
                builder: (_) => OpenWithDialog(filePath: node.fullPath),
              ),
            ),
          if (node.isFile)
            ContextMenuAction(
              id: 'choose_default_app',
              label: l10n.chooseDefaultApp,
              icon: PhosphorIconsLight.appWindow,
              onSelected: (_) => RouteUtils.showAcrylicDialog(
                context: context,
                builder: (_) => OpenWithDialog(
                  filePath: node.fullPath,
                  saveAsDefaultOnSelect: true,
                ),
              ),
            ),
          ContextMenuAction(
            id: 'refresh_subtree',
            label: l10n.refresh,
            icon: PhosphorIconsLight.arrowsClockwise,
            isEnabled: !_isRefreshingNode,
            onSelected: (_) => _refreshNodeSubtree(node),
          ),
        ],
      ),
      ContextMenuSection(
        title: l10n.copy,
        actions: [
          ContextMenuAction(
            id: 'copy',
            label: l10n.copy,
            icon: PhosphorIconsLight.copy,
            onSelected: (_) => FileOperationsHandler.copyToClipboard(
                context: context, entity: entity),
          ),
          ContextMenuAction(
            id: 'cut',
            label: l10n.cut,
            icon: PhosphorIconsLight.scissors,
            onSelected: (_) => FileOperationsHandler.cutToClipboard(
                context: context, entity: entity),
          ),
          if (!node.isFile)
            ContextMenuAction(
              id: 'paste',
              label: l10n.pasteHere,
              icon: PhosphorIconsLight.clipboard,
              onSelected: (_) => FileOperationsHandler.pasteFromClipboard(
                context: context,
                destinationPath: node.fullPath,
              ),
            ),
          ContextMenuAction(
            id: 'rename',
            label: l10n.rename,
            icon: PhosphorIconsLight.pencilSimple,
            onSelected: (_) => FileOperationsHandler.showRenameDialog(
              context: context,
              entity: entity,
            ),
          ),
          ContextMenuAction(
            id: 'tags',
            label: l10n.manageTags,
            icon: PhosphorIconsLight.tag,
            onSelected: (_) =>
                tag_dialogs.showAddTagToFileDialog(context, node.fullPath),
          ),
        ],
      ),
      ContextMenuSection(
        title: l10n.properties,
        actions: [
          ContextMenuAction(
            id: 'properties',
            label: l10n.properties,
            icon: PhosphorIconsLight.info,
            onSelected: (_) => _showNodeProperties(node),
          ),
          if (canShowShellMenu)
            ContextMenuAction(
              id: 'more_options',
              label: l10n.moreOptions,
              icon: PhosphorIconsLight.dotsThreeVertical,
              onSelected: (_) => WindowsShellContextMenu.showForPaths(
                paths: [node.fullPath],
                globalPosition: globalPosition,
                devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
              ),
            ),
        ],
      ),
    ];

    showContextMenuPopup(
      context: context,
      globalPosition: globalPosition,
      sections: sections,
    );
  }
}

// =============================================================================
// Tree row widget (recursive, collapsible)
// =============================================================================

class _TreeRow extends StatefulWidget {
  final DiskTreeNode node;
  final int depth;
  final int parentSize;
  final ThemeData theme;
  final ValueChanged<DiskTreeNode> onSelect;
  final void Function(DiskTreeNode, bool?) onToggleJunk;
  final ValueChanged<DiskTreeNode>? onAskAi;
  final void Function(DiskTreeNode, Offset)? onShowContextMenu;
  final bool Function(DiskTreeNode)? nodeFilter;

  const _TreeRow({
    required this.node,
    required this.depth,
    required this.parentSize,
    required this.theme,
    required this.onSelect,
    required this.onToggleJunk,
    this.onAskAi,
    this.onShowContextMenu,
    this.nodeFilter,
  });

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _isHovering = false;

  int _countJunkNodes(DiskTreeNode node) {
    int count = node.fullPath.isNotEmpty ? 1 : 0;
    for (final c in node.children) {
      count += _countJunkNodes(c);
    }
    return count;
  }

  int _countCheckedJunkNodes(DiskTreeNode node) {
    int count = node.fullPath.isNotEmpty && node.isSelectedForDeletion ? 1 : 0;
    for (final c in node.children) {
      count += _countCheckedJunkNodes(c);
    }
    return count;
  }

  bool? _checkboxState(DiskTreeNode node) {
    final total = _countJunkNodes(node);
    if (total == 0) return false;
    final checked = _countCheckedJunkNodes(node);
    if (checked == 0) return false;
    if (checked == total) return true;
    return null; // indeterminate (dash)
  }

  void _applyCheckRecursive(DiskTreeNode node, bool checked) {
    if (node.fullPath.isNotEmpty) {
      node.isSelectedForDeletion = checked;
    }
    for (final c in node.children) {
      _applyCheckRecursive(c, checked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final theme = widget.theme;
    final indent = 16.0 * widget.depth;
    final percent = node.percentOf(widget.parentSize);
    final hasChildren = !node.isFile && node.children.isNotEmpty;
    final isJunk = node.isJunk || node.hasJunkChildren;
    final categoryId = node.junkCategoryId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MouseRegion(
          onEnter: (_) => setState(() => _isHovering = true),
          onExit: (_) => setState(() => _isHovering = false),
          child: InkWell(
            onTap: () {
              if (hasChildren) {
                setState(() => node.isExpanded = !node.isExpanded);
              }
              widget.onSelect(node);
            },
            onSecondaryTapUp:
                widget.onShowContextMenu == null || node.fullPath.isEmpty
                    ? null
                    : (d) => widget.onShowContextMenu!(node, d.globalPosition),
            child: Container(
              color: isJunk
                  ? Colors.orange.withValues(alpha: 0.06)
                  : Colors.transparent,
              padding: EdgeInsets.only(
                  left: 12 + indent, right: 12, top: 4, bottom: 4),
              child: Row(
                children: [
                  // Selection checkbox
                  SizedBox(
                    width: 28,
                    child: Checkbox(
                      tristate: true,
                      value: _checkboxState(node),
                      onChanged: (v) {
                        // Flutter tristate cycles true -> null -> false.
                        // For cleaner UX, clicking a fully checked node
                        // unchecks the whole subtree; clicking partial or
                        // unchecked nodes checks the subtree.
                        final target = _checkboxState(node) != true;
                        setState(() {
                          _applyCheckRecursive(node, target);
                        });
                        widget.onToggleJunk(node, target);
                      },
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  // Expand arrow
                  SizedBox(
                    width: 20,
                    child: hasChildren
                        ? AnimatedRotation(
                            duration: const Duration(milliseconds: 150),
                            turns: node.isExpanded ? 0.25 : 0.0,
                            child: Icon(PhosphorIconsLight.caretRight,
                                size: 12,
                                color: theme.colorScheme.onSurfaceVariant),
                          )
                        : const SizedBox.shrink(),
                  ),
                  // Icon + Name + Junk badge
                  Expanded(
                    flex: 4,
                    child: Row(
                      children: [
                        Icon(
                          node.isFile
                              ? PhosphorIconsLight.file
                              : PhosphorIconsLight.folder,
                          size: 15,
                          color: node.isJunk
                              ? Colors.orange
                              : node.isFile
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            node.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: node.isFile
                                  ? FontWeight.normal
                                  : FontWeight.w500,
                              color: node.isJunk
                                  ? Colors.orange.shade800
                                  : theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Junk category badge
                        if (categoryId != null)
                          CbTooltip(
                            // Answers "why is this junk?" without making the
                            // user open the folder to find out.
                            message: _CbAgentCleanerScreenState._junkReason(
                              AppLocalizations.of(context)!,
                              categoryId,
                            ),
                            child: Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                _junkLabel(categoryId),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ),
                        // Ask AI button (on hover)
                        if (_isHovering && widget.onAskAi != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => widget.onAskAi!(node),
                              child: CbTooltip(
                                message: AppLocalizations.of(context)!
                                    .diskCleanerAskAgentAboutThis,
                                child: Icon(
                                  PhosphorIconsLight.sparkle,
                                  size: 14,
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Size
                  SizedBox(
                    width: 80,
                    child: Text(
                      _CbAgentCleanerScreenState._fmt(node.sizeBytes),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 10),
                  // % bar
                  SizedBox(
                    width: 90,
                    child: _PercentBar(
                      percent: percent,
                      isJunk: node.isJunk,
                    ),
                  ),
                  // File count
                  SizedBox(
                    width: 60,
                    child: Text(
                      node.isFile ? '' : '${node.fileCount}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Children (capped at 100 to avoid jank on large folders)
        if (node.isExpanded && hasChildren)
          ..._buildVisibleChildren(node, theme),
      ],
    );
  }

  static const int _maxVisibleChildren = 100;

  List<Widget> _buildVisibleChildren(DiskTreeNode node, ThemeData theme) {
    final filtered = node.children
        .where((child) => widget.nodeFilter?.call(child) ?? true)
        .toList();
    final visible = filtered.take(_maxVisibleChildren);
    final hiddenCount = filtered.length - visible.length;

    final rows = visible
        .map((child) => _TreeRow(
              node: child,
              depth: widget.depth + 1,
              parentSize: node.sizeBytes,
              theme: theme,
              onSelect: widget.onSelect,
              onToggleJunk: widget.onToggleJunk,
              onAskAi: widget.onAskAi,
              onShowContextMenu: widget.onShowContextMenu,
              nodeFilter: widget.nodeFilter,
            ))
        .toList();

    if (hiddenCount > 0) {
      rows.add(_TreeRow(
        node: DiskTreeNode(
          name: AppLocalizations.of(context)!
              .diskCleanerAndMoreItems(hiddenCount),
          fullPath: '',
          isFile: true,
          sizeBytes: 0,
        ),
        depth: widget.depth + 1,
        parentSize: node.sizeBytes,
        theme: theme,
        onSelect: (_) {},
        onToggleJunk: (_, __) {},
      ));
    }

    return rows;
  }

  static String _junkLabel(String categoryId) {
    switch (categoryId) {
      case 'windows_temp':
        return 'TEMP';
      case 'browser_cache':
        return 'BROWSER';
      case 'recycle_bin':
        return 'RECYCLE';
      case 'thumbnail_cache':
        return 'THUMBS';
      case 'app_cache':
        return 'APP CACHE';
      case 'crash_dumps_logs':
        return 'CRASH/LOG';
      case 'windows_update_cache':
        return 'WIN UPDATE';
      case 'prefetch':
        return 'PREFETCH';
      case 'delivery_optimization':
        return 'DELIVERY';
      case 'dev_cache':
        return 'DEV CACHE';
      default:
        return 'JUNK';
    }
  }
}

// =============================================================================
// Percent bar
// =============================================================================

class _PercentBar extends StatelessWidget {
  final double percent;
  final bool isJunk;

  const _PercentBar({required this.percent, this.isJunk = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isJunk ? Colors.orange : _barColor(percent);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percent.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: color,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 32,
          child: Text(
            '${(percent * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 10),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  static Color _barColor(double percent) {
    if (percent > 0.5) return Colors.green.shade600;
    if (percent > 0.25) return Colors.green.shade400;
    if (percent > 0.1) return Colors.lightGreen;
    return Colors.grey.shade400;
  }
}

// =============================================================================
// Pie chart painter
// =============================================================================

class _PieSegment {
  final double value;
  final Color color;
  final String label;
  const _PieSegment({
    required this.value,
    required this.color,
    required this.label,
  });
}

class _PieChartPainter extends CustomPainter {
  final List<_PieSegment> segments;
  final double total;

  /// Slice matching the focused tree row, drawn pulled out and outlined.
  final int? highlightIndex;

  _PieChartPainter({
    required this.segments,
    required this.total,
    this.highlightIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    double startAngle = -math.pi / 2;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final sweep = total > 0 ? (seg.value / total) * 2 * math.pi : 0.0;
      final isHighlighted = i == highlightIndex;

      // Offset the focused slice along its own mid-angle so the link to the
      // tree selection is readable at a glance.
      var sliceCenter = center;
      if (isHighlighted && sweep > 0) {
        final midAngle = startAngle + sweep / 2;
        sliceCenter =
            center + Offset(math.cos(midAngle), math.sin(midAngle)) * 6;
      }
      final rect = Rect.fromCircle(center: sliceCenter, radius: radius);

      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.fill;
      canvas.drawArc(rect, startAngle, sweep, true, paint);

      // Thin white separator
      final sepPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHighlighted ? 2.5 : 1.5;
      canvas.drawArc(rect, startAngle, sweep, true, sepPaint);

      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter old) {
    if (old.total != total ||
        old.segments.length != segments.length ||
        old.highlightIndex != highlightIndex) {
      return true;
    }
    for (var i = 0; i < segments.length; i++) {
      final a = segments[i];
      final b = old.segments[i];
      if (a.value != b.value || a.color != b.color || a.label != b.label) {
        return true;
      }
    }
    return false;
  }
}

// =============================================================================
// Scan ring painter (reused from before)
// =============================================================================

// =============================================================================
// Flat tree row model + widget for ListView.builder
// =============================================================================

class _FlatRow {
  final DiskTreeNode node;
  final int depth;
  final int parentSize;
  const _FlatRow({
    required this.node,
    required this.depth,
    required this.parentSize,
  });
}

class _FlatTreeRowWidget extends StatefulWidget {
  final _FlatRow row;
  final ThemeData theme;
  final CleanerFolderGrowth? growth;
  final ValueListenable<Set<String>> selectedPaths;
  final ValueListenable<String?> focusedPath;
  final VoidCallback onTap;
  final VoidCallback? onExpandToggle;
  final VoidCallback? onAskAi;
  final void Function(DiskTreeNode, Offset)? onShowContextMenu;

  const _FlatTreeRowWidget({
    required this.row,
    required this.theme,
    required this.growth,
    required this.selectedPaths,
    required this.focusedPath,
    required this.onTap,
    this.onExpandToggle,
    this.onAskAi,
    this.onShowContextMenu,
  });

  @override
  State<_FlatTreeRowWidget> createState() => _FlatTreeRowWidgetState();
}

class _FlatTreeRowWidgetState extends State<_FlatTreeRowWidget> {
  bool _hovering = false;
  String? _lastTapPath;
  DateTime? _lastTapAt;

  void _handleTap(bool hasChildren) {
    final path = widget.row.node.fullPath;
    final now = DateTime.now();
    final lastTapAt = _lastTapAt;
    final isDoubleTap = _lastTapPath == path &&
        lastTapAt != null &&
        now.difference(lastTapAt) <= const Duration(milliseconds: 300);

    if (isDoubleTap) {
      widget.onTap();
      final onExpandToggle = widget.onExpandToggle;
      if (hasChildren && onExpandToggle != null) {
        onExpandToggle();
      }
      _lastTapPath = null;
      _lastTapAt = null;
      return;
    }

    _lastTapPath = path;
    _lastTapAt = now;
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.row.node;
    final indent = 16.0 * widget.row.depth;
    final percent = node.percentOf(widget.row.parentSize);
    final hasChildren = !node.isFile && node.children.isNotEmpty;
    final isJunk = node.isJunk || node.hasJunkChildren;
    final categoryId = node.junkCategoryId;
    final growth = widget.growth;
    final theme = widget.theme;
    final localizations = AppLocalizations.of(context)!;

    return ValueListenableBuilder<Set<String>>(
      valueListenable: widget.selectedPaths,
      builder: (context, selectedPaths, _) {
        final isSelected = selectedPaths.contains(node.fullPath);
        return ValueListenableBuilder<String?>(
          valueListenable: widget.focusedPath,
          builder: (context, focusedPath, _) => MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleTap(hasChildren),
              onSecondaryTapUp: widget.onShowContextMenu == null ||
                      node.fullPath.isEmpty
                  ? null
                  : (d) => widget.onShowContextMenu!(node, d.globalPosition),
              child: Container(
                key: ValueKey<String>(
                  'cleaner-tree-row-${isSelected ? 'selected' : 'idle'}-${node.fullPath}',
                ),
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.14)
                    : focusedPath == node.fullPath
                        ? theme.colorScheme.primary.withValues(alpha: 0.06)
                        : _hovering
                            ? theme.colorScheme.primary.withValues(alpha: 0.06)
                            : isJunk
                                ? Colors.orange.withValues(alpha: 0.04)
                                : growth != null
                                    ? Colors.green.withValues(alpha: 0.06)
                                    : Colors.transparent,
                padding: EdgeInsets.only(left: 12 + indent, right: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: hasChildren
                          ? GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onExpandToggle,
                              child: Icon(
                                node.isExpanded
                                    ? PhosphorIconsLight.caretDown
                                    : PhosphorIconsLight.caretRight,
                                size: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Icon(
                            node.isFile
                                ? PhosphorIconsLight.file
                                : PhosphorIconsLight.folder,
                            size: 14,
                            color: node.isJunk
                                ? Colors.orange
                                : node.isFile
                                    ? theme.colorScheme.onSurfaceVariant
                                    : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              _CbAgentCleanerScreenState._displayName(
                                localizations,
                                node,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: node.isAggregate
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                fontWeight: node.isFile
                                    ? FontWeight.normal
                                    : FontWeight.w500,
                                color: node.isAggregate
                                    ? theme.colorScheme.onSurfaceVariant
                                    : node.isJunk
                                        ? Colors.orange.shade800
                                        : theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (categoryId != null)
                            CbTooltip(
                              // Answers "why is this junk?" without making the
                              // user open the folder to find out.
                              message: _CbAgentCleanerScreenState._junkReason(
                                localizations,
                                categoryId,
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  _junkLabel(categoryId),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ),
                          if (growth != null)
                            CbTooltip(
                              message:
                                  '${growth.path}\n${localizations.diskCleanerGrowthCurrentSize(_CbAgentCleanerScreenState._fmt(growth.currentSizeBytes))}',
                              child: Container(
                                key: ValueKey<String>(
                                  'cleaner-growth-badge-${node.fullPath}',
                                ),
                                margin: const EdgeInsets.only(left: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  localizations.diskCleanerGrowthIncrease(
                                    _CbAgentCleanerScreenState._fmt(
                                      growth.increasedBytes,
                                    ),
                                  ),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                            ),
                          if (widget.onAskAi != null && _hovering)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: GestureDetector(
                                onTap: widget.onAskAi,
                                child: Icon(
                                  PhosphorIconsLight.sparkle,
                                  size: 12,
                                  color: theme.colorScheme.tertiary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(
                        _CbAgentCleanerScreenState._fmt(node.sizeBytes),
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      child: _PercentBar(percent: percent, isJunk: node.isJunk),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        node.isFile ? '' : '${node.fileCount}',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static String _junkLabel(String categoryId) {
    switch (categoryId) {
      case 'windows_temp':
        return 'TEMP';
      case 'browser_cache':
        return 'BROWSER';
      case 'recycle_bin':
        return 'RECYCLE';
      case 'thumbnail_cache':
        return 'THUMBS';
      case 'app_cache':
        return 'APP CACHE';
      case 'crash_dumps_logs':
        return 'CRASH/LOG';
      case 'windows_update_cache':
        return 'WIN UPDATE';
      case 'prefetch':
        return 'PREFETCH';
      case 'delivery_optimization':
        return 'DELIVERY';
      case 'dev_cache':
        return 'DEV CACHE';
      default:
        return 'JUNK';
    }
  }
}

/// Hot progress snapshot for the cleanup phase. Lives behind a
/// [ValueNotifier] so the disk tree and pie chart do not rebuild on every
/// progress tick.
class _CleanProgressSnapshot {
  final int done;
  final int total;
  final String currentPath;
  final String status;

  const _CleanProgressSnapshot({
    this.done = 0,
    this.total = 0,
    this.currentPath = '',
    this.status = '',
  });
}
