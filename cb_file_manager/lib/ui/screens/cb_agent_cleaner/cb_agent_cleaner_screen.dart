import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:path/path.dart' as p;
import '../../../e2e/cb_e2e_config.dart';

import '../../../bloc/ai_agent/ai_agent_event.dart';
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
import '../../../services/disk_cleaner/cleaner_models.dart';
import '../../../services/disk_cleaner/disk_cleaner_service.dart';
import '../../../services/disk_cleaner/disk_tree_node.dart';
import '../../tab_manager/core/tab_manager.dart';
import '../../widgets/app_progress_indicator.dart';
import '../ai_chat/ai_panel_controller.dart';

/// Full disk analyzer + cleaner screen (TreeSize-style).
///
/// 2-panel layout after scan: collapsible tree view (left) + pie chart (right).
/// Junk categories are highlighted and tickable for deletion.
class CbAgentCleanerScreen extends StatefulWidget {
  const CbAgentCleanerScreen({Key? key}) : super(key: key);

  @override
  State<CbAgentCleanerScreen> createState() => _CbAgentCleanerScreenState();
}

enum _Phase { setup, scanning, results, cleaned }

enum _CleanDeleteMode { recycleBin, permanent }

class _CbAgentCleanerScreenState extends State<CbAgentCleanerScreen>
    with TickerProviderStateMixin {
  final DiskCleanerService _service = DiskCleanerService.instance;

  _Phase _phase = _Phase.setup;

  // Animation
  late final AnimationController _pulseController;
  late final AnimationController _scanRingController;

  // Setup
  List<DriveSpace> _drives = [];
  String? _selectedDrive;
  bool _aiAvailable = false;

  // Scan progress
  FullDiskScanProgress? _lastProgress;
  bool _isScanningFullDisk = false;

  // Cleanup progress
  bool _isCleaningJunk = false;
  String _cleanStatus = '';
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
  bool _lastCleanWasPermanent = false;
  bool _skipAllDeleteFailures = false;
  bool _isPermanentDeleting = false;
  int _permanentDone = 0;
  int _permanentTotal = 0;

  // Results
  DiskTreeNode? _rootNode;
  DiskTreeNode? _selectedNode; // node shown in pie chart
  DiskTreeNode? _chartNode;
  Timer? _chartUpdateTimer;
  final Set<String> _selectedTreePaths = <String>{};
  final ValueNotifier<Set<String>> _selectedTreePathListenable =
      ValueNotifier<Set<String>>(const <String>{});
  String? _selectionAnchorPath;
  int _selectionMutationVersion = 0;
  String? _publishedCleanerContextTabId;
  bool _showCleanableOnly = false;
  bool _reviewMode = false; // when true, tree shows only selected items
  bool _isRefreshingNode = false;

  // Agent activity (when CB Agent triggers scan_disk_junk from AI panel)
  StreamSubscription<DiskCleanerAgentActivity>? _agentActivitySub;
  bool _agentScanning = false;
  String _agentStatus = '';
  int _agentItemsFound = 0;
  int _agentBytesFound = 0;
  String _agentCurrentPath = '';

  final FocusNode _resultsFocusNode = FocusNode(debugLabel: 'cbCleanerResults');

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scanRingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _loadSetup();
    _agentActivitySub = _service.agentActivityStream.listen(_onAgentActivity);
  }

  @override
  void dispose() {
    _agentActivitySub?.cancel();
    if (_publishedCleanerContextTabId != null) {
      _service.clearCleanerScanContext(_publishedCleanerContextTabId!);
    }
    _chartUpdateTimer?.cancel();
    _selectedTreePathListenable.dispose();
    _cleanProgress.dispose();
    _pulseController.dispose();
    _scanRingController.dispose();
    _resultsFocusNode.dispose();
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
      ];
      _selectedDrive = _drives.first.path;
      _aiAvailable = true;
      _seedE2EResultsDemo();
      if (mounted) setState(() {});
      return;
    }

    _drives = await _service.getDriveSpace();
    if (_drives.isNotEmpty) _selectedDrive = _drives.first.path;
    try {
      final providers =
          await GetIt.instance<AiProviderService>().getEnabledProviders();
      _aiAvailable = providers.isNotEmpty;
    } catch (_) {}
    if (mounted) setState(() {});
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
          name: '4Recycle.Bin',
          fullPath: 'C:\\4Recycle.Bin',
          sizeBytes: 3100 * 1024 * 1024,
          fileCount: 126,
          junkCategoryId: 'recycle_bin',
        ),
      ],
    );

    setState(() {
      _phase = _Phase.results;
      _isScanningFullDisk = false;
      _rootNode = root;
      _selectedNode = root.children.first;
      _chartNode = root.children.first;
      _selectedTreePaths.clear();
      _publishTreeSelection();
      _selectionAnchorPath = root.children.first.fullPath;
      _showCleanableOnly = false;
      _cachedFlatRoot = null;
      _flatRowsValid = false;
    });
  }

  Future<void> _startScan() async {
    if (_selectedDrive == null) return;
    final drive = _selectedDrive!;
    final driveRoot = drive.endsWith('\\') ? drive : '$drive\\';
    setState(() {
      // Show the TreeSize layout immediately. The tree is populated when the
      // scan completes, while progress is shown inline in the same view.
      _phase = _Phase.results;
      _lastProgress = null;
      _isScanningFullDisk = true;
      _rootNode = DiskTreeNode(
        name: driveRoot,
        fullPath: driveRoot,
        isExpanded: true,
      );
      _selectedNode = _rootNode;
      _chartNode = _rootNode;
      _selectedTreePaths.clear();
      _publishTreeSelection();
      _selectionAnchorPath = null;
    });
    _scanRingController.repeat();

    try {
      final handle = await _service.scanFullDisk(
        drivePath: drive,
      );
      handle.progress.listen((p) {
        if (mounted) {
          setState(() {
            _lastProgress = p;
            // Keep the visible root counters moving while the full tree is
            // still being built inside the isolate.
            _rootNode?.sizeBytes = p.bytesScanned;
            _rootNode?.fileCount = p.filesScanned;
          });
          _publishCleanerScanContext();
        }
      });
      handle.treeSnapshots.listen((root) {
        if (!mounted) return;
        final expandedPaths = _collectExpandedPaths(_rootNode);
        _service.markJunkNodes(root);
        _applyExpandedPaths(root, expandedPaths);
        setState(() {
          _rootNode = root;
          _selectedNode = root;
          _chartNode = root;
          _selectedTreePaths.clear();
          _publishTreeSelection();
          _selectionAnchorPath = null;
          _cachedFlatRoot = null;
          _flatRowsValid = false;
        });
      });
      final result = await handle.future;
      if (mounted) {
        final expandedPaths = _collectExpandedPaths(_rootNode);
        _service.markJunkNodes(result.root);
        _applyExpandedPaths(result.root, expandedPaths);
        _scanRingController.stop();
        setState(() {
          _isScanningFullDisk = false;
          _rootNode = result.root;
          _selectedNode = result.root;
          _chartNode = result.root;
          _phase = _Phase.results;
          _selectedTreePaths.clear();
          _publishTreeSelection();
          _selectionAnchorPath = null;
          _cachedFlatRoot = null;
          _flatRowsValid = false;
        });
      }
    } catch (e) {
      if (mounted) {
        _scanRingController.stop();
        setState(() {
          _isScanningFullDisk = false;
          _phase = _Phase.setup;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .diskCleanerScanFailedMsg('$e'))),
        );
      }
    }
  }

  void _openAiPanel() {
    _sendToAi(_buildAiSummary());
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
      return _subtreeHasSelection(node);
    }
    if (!_showCleanableOnly) return true;
    return _isNodeCleanable(node);
  }

  /// Whether this node OR any descendant has been ticked for deletion.
  /// Used by review mode to keep ancestor folders visible in the tree.
  bool _subtreeHasSelection(DiskTreeNode node) {
    if (node.isSelectedForDeletion && node.fullPath.isNotEmpty) return true;
    for (final c in node.children) {
      if (_subtreeHasSelection(c)) return true;
    }
    return false;
  }

  int _countCleanableNodes(DiskTreeNode? node) {
    if (node == null) return 0;
    int count = 0;
    void walk(DiskTreeNode n) {
      if (n.fullPath.isNotEmpty) {
        count++;
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(node);
    return count;
  }

  void _setAllCleanableChecked(DiskTreeNode? node, bool checked) {
    if (node == null) return;
    void walk(DiskTreeNode n) {
      if (n.fullPath.isNotEmpty) {
        n.isSelectedForDeletion = checked;
        if (checked) {
          _selectedTreePaths.add(n.fullPath);
        } else {
          _selectedTreePaths.remove(n.fullPath);
        }
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(node);
    _publishTreeSelection();
    setState(() {});
  }

  Set<String> _collectExpandedPaths(DiskTreeNode? node) {
    final paths = <String>{};
    void walk(DiskTreeNode n) {
      if (n.isExpanded) paths.add(n.fullPath.toUpperCase());
      for (final child in n.children) {
        walk(child);
      }
    }

    if (node != null) walk(node);
    return paths;
  }

  void _applyExpandedPaths(DiskTreeNode node, Set<String> paths) {
    node.isExpanded = paths.contains(node.fullPath.toUpperCase()) ||
        node.fullPath == _selectedDrive ||
        node.fullPath == '${_selectedDrive ?? ''}\\';
    for (final child in node.children) {
      _applyExpandedPaths(child, paths);
    }
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
      node.children
        ..clear()
        ..addAll(survivors);
    }

    node.sizeBytes = (node.sizeBytes - prunedBytes).clamp(0, node.sizeBytes);
    node.fileCount = (node.fileCount - prunedFiles).clamp(0, node.fileCount);

    // Clear selection on whatever remains so stale checkboxes don't linger.
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildPhase(theme, l),
      ),
    );
  }

  Widget _buildPhase(ThemeData theme, AppLocalizations l) {
    switch (_phase) {
      case _Phase.setup:
        return _buildSetup(theme, l);
      case _Phase.scanning:
        return _buildScanning(theme, l);
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
    return Center(
      key: const ValueKey('setup'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated scan button
          _buildScanButton(theme),
          const SizedBox(height: 28),
          Text(l.diskCleanerScanTitle,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          // Drive picker chips
          Wrap(
            spacing: 10,
            children: _drives.map((d) {
              final selected = _selectedDrive == d.path;
              final label =
                  d.label.isNotEmpty ? '${d.path} (${d.label})' : d.path;
              return ChoiceChip(
                label: Text(l.diskCleanerDriveFree(label, _fmt(d.freeBytes))),
                selected: selected,
                onSelected: (_) => setState(() => _selectedDrive = d.path),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          if (_aiAvailable)
            _buildAcrylicChip(
              theme: theme,
              icon: PhosphorIconsLight.sparkle,
              label: l.diskCleanerAskAgent,
              onTap: _openAiPanel,
            ),
        ],
      ),
    );
  }

  Widget _buildScanButton(ThemeData theme) {
    final enabled = _selectedDrive != null;
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = enabled ? _pulseController.value : 0.0;
        final scale = 1.0 + pulse * 0.05;
        final glow = enabled ? 0.12 + pulse * 0.18 : 0.04;
        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTap: enabled ? _startScan : null,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.7)
                    : theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: glow),
                    blurRadius: 32 + pulse * 20,
                    spreadRadius: 6 + pulse * 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Center(
                    child: Icon(
                      PhosphorIconsLight.magnifyingGlass,
                      size: 56,
                      color: enabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Scanning phase — progress ring
  // ---------------------------------------------------------------------------

  Widget _buildScanning(ThemeData theme, AppLocalizations l) {
    return Center(
      key: const ValueKey('scanning'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _scanRingController,
            builder: (context, child) {
              return SizedBox(
                width: 220,
                height: 220,
                child: CustomPaint(
                  painter: _ScanRingPainter(
                    progress: _scanRingController.value,
                    color: theme.colorScheme.primary,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIconsLight.hardDrive,
                            size: 36, color: theme.colorScheme.primary),
                        const SizedBox(height: 10),
                        if (_lastProgress != null) ...[
                          Text(
                            _fmt(_lastProgress!.bytesScanned),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            l.diskCleanerFilesCount(
                                _lastProgress!.filesScanned),
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            l.diskCleanerDirsCount(
                                _lastProgress!.directoriesScanned),
                            style: theme.textTheme.bodySmall,
                          ),
                        ] else
                          Text(l.diskCleanerStarting,
                              style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(l.diskCleanerScanRunning, style: theme.textTheme.titleLarge),
          if (_lastProgress != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 320,
              child: Text(
                _lastProgress!.currentPath,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 24),
          _buildAcrylicChip(
            theme: theme,
            icon: Icons.stop_rounded,
            label: l.diskCleanerCancel,
            onTap: () {
              _service.cancelFullDiskScan();
              _scanRingController.stop();
              setState(() => _phase = _Phase.setup);
            },
          ),
        ],
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
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.cancel),
            ),
            FilledButton(
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

    await _cleanJunk(permanent: permanent);
  }

  List<DiskTreeNode> _selectedTreeNodes() {
    final root = _rootNode;
    if (root == null) return const [];
    final nodes = <DiskTreeNode>[];
    void walk(DiskTreeNode node) {
      if (node.fullPath.isNotEmpty && node.isSelectedForDeletion) {
        nodes.add(node);
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(root);
    return nodes;
  }

  void _publishTreeSelection() {
    _selectedTreePathListenable.value = Set<String>.unmodifiable(
      _selectedTreePaths,
    );
    _publishCleanerScanContext();
  }

  String? _activeTabId() {
    try {
      return context.read<TabManagerBloc>().state.activeTabId;
    } catch (_) {
      return null;
    }
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
    );
  }

  void _setCleanSelectedRecursive(DiskTreeNode node, bool selected) {
    if (node.fullPath.isNotEmpty) {
      node.isSelectedForDeletion = selected;
      if (selected) {
        _selectedTreePaths.add(node.fullPath);
      } else {
        _selectedTreePaths.remove(node.fullPath);
      }
    }
    for (final child in node.children) {
      _setCleanSelectedRecursive(child, selected);
    }
  }

  void _applyCleanSelectionAfterPaint(
    Iterable<DiskTreeNode> nodes,
    bool selected,
  ) {
    final version = ++_selectionMutationVersion;
    final targets = List<DiskTreeNode>.of(nodes, growable: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || version != _selectionMutationVersion) return;
      for (final target in targets) {
        _setCleanSelectedRecursive(target, selected);
      }
      _publishTreeSelection();
      setState(() {});
    });
  }

  void _selectTreeRow(DiskTreeNode node, List<_FlatRow> visibleRows) {
    if (node.fullPath.isEmpty) return;
    _resultsFocusNode.requestFocus();

    final keyboard = HardwareKeyboard.instance;
    final isCtrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final isShift = keyboard.isShiftPressed;
    final path = node.fullPath;

    _selectedNode = node;

    if (isShift && _selectionAnchorPath != null) {
      final anchorIndex = visibleRows.indexWhere(
        (row) => row.node.fullPath == _selectionAnchorPath,
      );
      final currentIndex = visibleRows.indexWhere(
        (row) => row.node.fullPath == path,
      );
      if (anchorIndex >= 0 && currentIndex >= 0) {
        final start = math.min(anchorIndex, currentIndex);
        final end = math.max(anchorIndex, currentIndex);
        final checked = !node.isSelectedForDeletion;
        node.isSelectedForDeletion = checked;
        if (checked) {
          _selectedTreePaths.add(path);
        } else {
          _selectedTreePaths.remove(path);
        }
        _publishTreeSelection();
        for (var i = start; i <= end; i++) {
          visibleRows[i].node.isSelectedForDeletion = checked;
          final rowPath = visibleRows[i].node.fullPath;
          if (rowPath.isEmpty) continue;
          if (checked) {
            _selectedTreePaths.add(rowPath);
          } else {
            _selectedTreePaths.remove(rowPath);
          }
        }
        _publishTreeSelection();
        _applyCleanSelectionAfterPaint(
          visibleRows.sublist(start, end + 1).map((row) => row.node),
          checked,
        );
        _scheduleChartNodeUpdate(node);
        return;
      }
    }

    if (isCtrl) {
      final checked = !node.isSelectedForDeletion;
      node.isSelectedForDeletion = checked;
      if (checked) {
        _selectedTreePaths.add(path);
      } else {
        _selectedTreePaths.remove(path);
      }
      _selectionAnchorPath = path;
      _publishTreeSelection();
      _applyCleanSelectionAfterPaint([node], checked);
      _scheduleChartNodeUpdate(node);
      return;
    }

    final checked = !node.isSelectedForDeletion;
    node.isSelectedForDeletion = checked;
    if (checked) {
      _selectedTreePaths.add(path);
    } else {
      _selectedTreePaths.remove(path);
    }
    _selectionAnchorPath = path;
    _publishTreeSelection();
    _applyCleanSelectionAfterPaint([node], checked);

    _scheduleChartNodeUpdate(node);
  }

  void _scheduleChartNodeUpdate(DiskTreeNode node) {
    _chartUpdateTimer?.cancel();
    _chartUpdateTimer = Timer(const Duration(milliseconds: 80), () {
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

    if (isCtrl && key == LogicalKeyboardKey.keyA) {
      final rows = _cachedFlatRows ?? const <_FlatRow>[];
      setState(() {
        for (final row in rows) {
          _setCleanSelectedRecursive(row.node, true);
        }
        if (rows.isNotEmpty) {
          _selectedNode = rows.last.node;
          _selectionAnchorPath = rows.first.node.fullPath;
          _scheduleChartNodeUpdate(rows.last.node);
        }
        _publishTreeSelection();
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete) {
      unawaited(_deleteCurrentSelectionImmediately(permanent: isShift));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
          // 2-panel body
          Expanded(
            child: Row(
              children: [
                // Left: tree view (~65%)
                Expanded(
                  flex: 65,
                  child: _buildTreePanel(theme, l, root),
                ),
                const VerticalDivider(width: 1),
                // Right: pie chart (~35%)
                Expanded(
                  flex: 35,
                  child: _buildPiePanel(theme, l, viewNode),
                ),
              ],
            ),
          ),
          // Bottom action bar
          _buildBottomBar(theme, l),
        ],
      ),
    );
  }

  Widget _buildResultsToolbar(
      ThemeData theme, AppLocalizations l, DiskTreeNode root) {
    final junkBytes = root.junkBytes;
    final cleanableCount = _countCleanableNodes(root);
    final driveSummary = l.diskCleanerDriveSummary(
        root.fullPath, _fmt(root.sizeBytes), root.fileCount);
    final hasStatus = _isScanningFullDisk || _agentScanning;

    Widget buildDriveInfo() {
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
        return Text(
          _lastProgress == null
              ? l.diskCleanerScanRunning
              : _lastProgress!.currentPath,
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
      // Filter cleanable-only
      boundedAction(
        Tooltip(
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
              _flatRowsValid = false;
            }),
          ),
        ),
      ),
      // Quick check actions
      boundedAction(
        TextButton(
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
            onPressed: _openAiPanel,
            icon: const Icon(PhosphorIconsLight.sparkle, size: 16),
            label: Text(
              l.diskCleanerAskAgent,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      boundedAction(
        OutlinedButton.icon(
          onPressed: () {
            if (_isScanningFullDisk) {
              _service.cancelFullDiskScan();
              _scanRingController.stop();
            }
            setState(() {
              _phase = _Phase.setup;
              _isScanningFullDisk = false;
              _rootNode = null;
              _selectedNode = null;
              _chartNode = null;
              _selectedTreePaths.clear();
              _publishTreeSelection();
              _selectionAnchorPath = null;
              _cachedFlatRoot = null;
              _flatRowsValid = false;
            });
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
    final spacedActions = <Widget>[
      for (final action in actions) ...[
        action,
        const SizedBox(width: 8),
      ],
    ]..removeLast();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1120;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildDriveInfo(),
                if (hasStatus) ...[
                  const SizedBox(height: 6),
                  buildStatus(),
                ],
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

          return Row(
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
              const SizedBox(width: 12),
              ...spacedActions,
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
              ? Center(
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
                      if (_lastProgress != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          l.diskCleanerSizeFiles(
                              _fmt(_lastProgress!.bytesScanned),
                              _lastProgress!.filesScanned),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: flatRows.length,
                  itemExtent: 28,
                  itemBuilder: (context, index) {
                    final row = flatRows[index];
                    return _FlatTreeRowWidget(
                      row: row,
                      theme: theme,
                      selectedPaths: _selectedTreePathListenable,
                      onTap: () => _selectTreeRow(row.node, flatRows),
                      onExpandToggle: row.node.isFile
                          ? null
                          : () => setState(() {
                                row.node.isExpanded = !row.node.isExpanded;
                                _flatRowsValid = false;
                              }),
                      onToggleJunk: (node, target) => setState(() {
                        _applyCheckRecursiveGlobal(node, target);
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

  void _applyCheckRecursiveGlobal(DiskTreeNode node, bool checked) {
    void walk(DiskTreeNode n) {
      if (n.fullPath.isNotEmpty) {
        n.isSelectedForDeletion = checked;
        if (checked) {
          _selectedTreePaths.add(n.fullPath);
        } else {
          _selectedTreePaths.remove(n.fullPath);
        }
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(node);
    _publishTreeSelection();
  }

  // ---------------------------------------------------------------------------
  // Pie chart panel (right)
  // ---------------------------------------------------------------------------

  Widget _buildPiePanel(
      ThemeData theme, AppLocalizations l, DiskTreeNode node) {
    if (_isScanningFullDisk) {
      return Center(
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
                _lastProgress == null
                    ? l.diskCleanerPieChartPending
                    : l.diskCleanerScannedProgress(
                        _fmt(_lastProgress!.bytesScanned),
                        _lastProgress!.filesScanned),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              if (_lastProgress?.currentPath.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  _lastProgress!.currentPath,
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
        label: child.name,
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
          // Pie chart
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: _PieChartPainter(
                segments: segments,
                total: node.sizeBytes.toDouble(),
              ),
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
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
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
                          c.name,
                          style: const TextStyle(fontSize: 12),
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
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom action bar
  // ---------------------------------------------------------------------------

  Widget _buildBottomBar(ThemeData theme, AppLocalizations l) {
    final root = _rootNode;
    final junkBytes = root?.junkBytes ?? 0;
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(PhosphorIconsLight.broom,
              size: 18, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Text(
            _isCleaningJunk
                ? (_cleanStatus.isEmpty ? l.diskCleanerCleaning : _cleanStatus)
                : _reviewMode
                    ? l.diskCleanerReviewModeSelected(_fmt(selectedBytes))
                    : l.diskCleanerSelectedBytes(
                        _fmt(selectedBytes), _fmt(junkBytes)),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          if (_reviewMode && !_isCleaningJunk) ...[
            OutlinedButton.icon(
              onPressed: () => setState(() => _reviewMode = false),
              icon: const Icon(PhosphorIconsLight.arrowLeft, size: 14),
              label: Text(l.diskCleanerBackToResults),
            ),
            const SizedBox(width: 8),
            if (_aiAvailable)
              OutlinedButton.icon(
                onPressed: _askAiReviewPending,
                icon: const Icon(PhosphorIconsLight.sparkle, size: 14),
                label: Text(l.diskCleanerReviewByAgent),
              ),
            const SizedBox(width: 8),
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
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                setState(() => _selectedCleanMode = selection.first);
              },
              showSelectedIcon: false,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    _selectedCleanMode == _CleanDeleteMode.permanent
                        ? Colors.red.shade700
                        : Colors.orange.shade700,
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
          ] else
            FilledButton.icon(
              onPressed: !_isCleaningJunk && selectedBytes > 0
                  ? _enterReviewMode
                  : null,
              icon: _isCleaningJunk
                  ? const AppWaveLoader(size: 24, color: Colors.white)
                  : const Icon(PhosphorIconsLight.eye, size: 18),
              label: Text(_isCleaningJunk
                  ? l.diskCleanerCleaning
                  : l.diskCleanerReviewAndClean(_fmt(selectedBytes))),
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

  /// Sum of sizes of all selected junk nodes (top-most selected only, since
  /// _applyCheckRecursive marks both parent and descendants).
  int _selectedJunkBytes(DiskTreeNode? root) {
    if (root == null) return 0;
    int total = 0;
    void walk(DiskTreeNode n) {
      if (n.isSelectedForDeletion && n.fullPath.isNotEmpty) {
        total += n.sizeBytes;
        return; // top-most selected node already covers the subtree
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(root);
    return total;
  }

  void _enterReviewMode() {
    // Build pending items list from selected tree nodes so AI tool + cleanup
    // helpers have data ready. The tree itself is filtered via _reviewMode
    // flag — no separate page, no rebuild.
    final items = <JunkItem>[];
    void walk(DiskTreeNode n) {
      if (n.isSelectedForDeletion && n.fullPath.isNotEmpty) {
        items.add(JunkItem(
          path: n.fullPath,
          sizeBytes: n.sizeBytes,
          categoryId: n.junkCategoryId ?? 'selected_item',
          // Tree selections are explicit user choices, so deleting a selected
          // directory should delete the directory itself, not only its
          // contents. `isContainerOnly` is reserved for scanner rules such as
          // empty-only cache folders.
          isContainerOnly: false,
          isUserSelected: true,
        ));
        return;
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    final root = _rootNode;
    if (root != null) walk(root);
    if (items.isEmpty) return;

    final totalBytes = items.fold<int>(0, (s, i) => s + i.sizeBytes);
    setState(() {
      _pendingCleanItems = items;
      _pendingCleanBytes = totalBytes;
      _reviewMode = true;
    });
    _service.pendingCleanupItems = items;
    _service.pendingCleanupBytes = totalBytes;
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

  Future<void> _cleanJunk({required bool permanent}) async {
    if (_isCleaningJunk || _pendingCleanItems.isEmpty) return;
    final l = AppLocalizations.of(context)!;
    setState(() {
      _isCleaningJunk = true;
      _cleanedSkippedInUseCount = 0;
      _cleanedSkippedByUserCount = 0;
      _skipAllDeleteFailures = false;
      _cleanStatus = permanent
          ? l.diskCleanerPermanentlyDeleting
          : l.diskCleanerMovingToRecycleBin;
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
        // If the currently-viewed pie node was deleted, fall back to root.
        if (_selectedNode != null &&
            deletedUpper.contains(_selectedNode!.fullPath.toUpperCase())) {
          _selectedNode = _rootNode;
          _chartNode = _rootNode;
        }
        _selectedTreePaths.removeWhere(
          (path) => deletedUpper.contains(path.toUpperCase()),
        );
        _publishTreeSelection();
        if (_selectionAnchorPath != null &&
            deletedUpper.contains(_selectionAnchorPath!.toUpperCase())) {
          _selectionAnchorPath = null;
        }
      }

      setState(() {
        _isCleaningJunk = false;
        _cleanStatus = '';
        _pendingCleanItems = [];
        _pendingCleanBytes = 0;
        _cleanedItems = permanent ? [] : cleanedItems;
        _cleanedFreedBytes = result.freedBytes;
        _cleanedFailureCount = result.failureCount;
        _cleanedSkippedInUseCount = result.skippedInUseCount;
        _cleanedSkippedByUserCount = result.skippedByUserCount;
        _lastCleanSuccessCount = result.successCount;
        _lastCleanWasPermanent = permanent;
        _phase = _Phase.cleaned;
        _cachedFlatRoot = null;
        _flatRowsValid = false;
      });
      _service.pendingCleanupItems = const [];
      _service.pendingCleanupBytes = 0;
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
        _cleanStatus = '';
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
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
                  onPressed: _continueToResults,
                  icon: const Icon(PhosphorIconsLight.arrowLeft, size: 16),
                  label: Text(l.diskCleanerContinue),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _cleanedItems = [];
                    _cleanedSkippedInUseCount = 0;
                    _cleanedSkippedByUserCount = 0;
                    _phase = _Phase.setup;
                  });
                  _startScan();
                },
                icon: const Icon(PhosphorIconsLight.arrowCounterClockwise,
                    size: 16),
                label: Text(l.diskCleanerScanAgain),
              ),
            ],
          ),
        ),
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
        if (_selectedNode?.fullPath == node.fullPath) {
          _selectedNode = node;
        }
      });
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
    target.children
      ..clear()
      ..addAll(source.children);
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
                          Container(
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
                        // Ask AI button (on hover)
                        if (_isHovering && widget.onAskAi != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => widget.onAskAi!(node),
                              child: Tooltip(
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

  _PieChartPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    double startAngle = -math.pi / 2;

    for (final seg in segments) {
      final sweep = total > 0 ? (seg.value / total) * 2 * math.pi : 0.0;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.fill;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        true,
        paint,
      );
      // Thin white separator
      final sepPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        true,
        sepPaint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(_PieChartPainter old) {
    if (old.total != total || old.segments.length != segments.length) {
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
  final ValueListenable<Set<String>> selectedPaths;
  final VoidCallback onTap;
  final VoidCallback? onExpandToggle;
  final void Function(DiskTreeNode, bool) onToggleJunk;
  final VoidCallback? onAskAi;
  final void Function(DiskTreeNode, Offset)? onShowContextMenu;

  const _FlatTreeRowWidget({
    required this.row,
    required this.theme,
    required this.selectedPaths,
    required this.onTap,
    this.onExpandToggle,
    required this.onToggleJunk,
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
  bool? _tapSequenceWasSelected;

  void _handleTap(bool hasChildren) {
    final path = widget.row.node.fullPath;
    final now = DateTime.now();
    final lastTapAt = _lastTapAt;
    final wasSelected = widget.selectedPaths.value.contains(path);
    final isDoubleTap = _lastTapPath == path &&
        lastTapAt != null &&
        now.difference(lastTapAt) <= const Duration(milliseconds: 300);

    if (isDoubleTap) {
      if (_tapSequenceWasSelected == true && !wasSelected) {
        widget.onTap();
      }
      final onExpandToggle = widget.onExpandToggle;
      if (hasChildren && onExpandToggle != null) {
        onExpandToggle();
      }
      _lastTapPath = null;
      _lastTapAt = null;
      _tapSequenceWasSelected = null;
      return;
    }

    _lastTapPath = path;
    _lastTapAt = now;
    _tapSequenceWasSelected = wasSelected;
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
    final theme = widget.theme;

    return ValueListenableBuilder<Set<String>>(
      valueListenable: widget.selectedPaths,
      builder: (context, selectedPaths, _) {
        final isSelected = selectedPaths.contains(node.fullPath);
        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleTap(hasChildren),
            onSecondaryTapUp:
                widget.onShowContextMenu == null || node.fullPath.isEmpty
                    ? null
                    : (d) => widget.onShowContextMenu!(node, d.globalPosition),
            child: Container(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : _hovering
                      ? theme.colorScheme.primary.withValues(alpha: 0.06)
                      : isJunk
                          ? Colors.orange.withValues(alpha: 0.04)
                          : Colors.transparent,
              padding: EdgeInsets.only(left: 12 + indent, right: 12),
              child: Row(
                children: [
                  const SizedBox(width: 28),
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
                        if (categoryId != null)
                          Container(
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

class _ScanRingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _ScanRingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 12;

    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius, bgPaint);

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final startAngle = progress * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle - math.pi / 2,
      math.pi * 0.7,
      false,
      arcPaint,
    );

    final arc2Paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle + math.pi - math.pi / 2,
      math.pi * 0.35,
      false,
      arc2Paint,
    );
  }

  @override
  bool shouldRepaint(_ScanRingPainter old) =>
      old.progress != progress || old.color != color;
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
