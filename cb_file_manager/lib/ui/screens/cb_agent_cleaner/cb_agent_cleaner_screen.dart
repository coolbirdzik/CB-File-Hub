import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../bloc/ai_agent/ai_agent_event.dart';
import '../../../config/languages/app_localizations.dart';
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
  bool _showCleanableOnly = false;
  bool _reviewMode = false; // when true, tree shows only selected items

  // Agent activity (when CB Agent triggers scan_disk_junk from AI panel)
  StreamSubscription<DiskCleanerAgentActivity>? _agentActivitySub;
  bool _agentScanning = false;
  String _agentStatus = '';
  int _agentItemsFound = 0;
  int _agentBytesFound = 0;
  String _agentCurrentPath = '';

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
    _cleanProgress.dispose();
    _pulseController.dispose();
    _scanRingController.dispose();
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
        break;
      case DiskCleanerAgentActivityType.scanProgress:
        setState(() {
          _agentScanning = true;
          _agentStatus = event.message;
          _agentItemsFound = event.itemsFound;
          _agentBytesFound = event.bytesFound;
          _agentCurrentPath = event.currentPath;
        });
        break;
      case DiskCleanerAgentActivityType.scanDone:
        setState(() {
          _agentScanning = false;
          _agentStatus = '';
          _agentCurrentPath = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'CB Agent found ${event.itemsFound} junk items (${_fmt(event.bytesFound)})'),
          ),
        );
        break;
      case DiskCleanerAgentActivityType.scanFailed:
        setState(() {
          _agentScanning = false;
          _agentStatus = '';
          _agentCurrentPath = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(event.message)),
        );
        break;
    }
  }

  Future<void> _loadSetup() async {
    _drives = await _service.getDriveSpace();
    if (_drives.isNotEmpty) _selectedDrive = _drives.first.path;
    try {
      final providers =
          await GetIt.instance<AiProviderService>().getEnabledProviders();
      _aiAvailable = providers.isNotEmpty;
    } catch (_) {}
    if (mounted) setState(() {});
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
          _phase = _Phase.results;
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
          SnackBar(content: Text('Scan failed: $e')),
        );
      }
    }
  }

  void _openAiPanel() {
    _sendToAi(_buildAiSummary());
  }

  void _askAiAboutNode(DiskTreeNode node) {
    final msg = StringBuffer();
    msg.writeln('I want to know if I can safely delete this:');
    msg.writeln('Path: ${node.fullPath}');
    msg.writeln('Size: ${_fmt(node.sizeBytes)}');
    msg.writeln('Files: ${node.fileCount}');
    if (node.isJunk) {
      msg.writeln('Category: ${node.junkCategoryId} (marked as junk)');
    } else {
      msg.writeln('Not marked as junk by rules.');
    }
    msg.writeln();
    msg.writeln('Is it safe to delete? What is this folder/file used for?');
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
        const SnackBar(content: Text('AI panel not available in this context')),
      );
      return;
    }
    // Get active tab ID from TabManagerBloc
    final tabState = context.read<TabManagerBloc>().state;
    final tabId = tabState.activeTabId;
    if (tabId == null) return;

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
    if (node.isSelectedForDeletion && node.junkCategoryId != null) return true;
    for (final c in node.children) {
      if (_subtreeHasSelection(c)) return true;
    }
    return false;
  }

  int _countCleanableNodes(DiskTreeNode? node) {
    if (node == null) return 0;
    int count = 0;
    void walk(DiskTreeNode n) {
      if (n.isJunk) {
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
      if (n.isJunk) {
        n.isSelectedForDeletion = checked;
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(node);
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
                label: Text('$label  ${_fmt(d.freeBytes)} free'),
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
                            '${_lastProgress!.filesScanned} files',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            '${_lastProgress!.directoriesScanned} dirs',
                            style: theme.textTheme.bodySmall,
                          ),
                        ] else
                          Text('Starting...',
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
            label: 'Cancel',
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

  Widget _buildResults(ThemeData theme, AppLocalizations l) {
    final root = _rootNode!;
    final viewNode = _selectedNode ?? root;
    return Column(
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
                child: _buildTreePanel(theme, root),
              ),
              const VerticalDivider(width: 1),
              // Right: pie chart (~35%)
              Expanded(
                flex: 35,
                child: _buildPiePanel(theme, viewNode),
              ),
            ],
          ),
        ),
        // Bottom action bar
        _buildBottomBar(theme, l),
      ],
    );
  }

  Widget _buildResultsToolbar(
      ThemeData theme, AppLocalizations l, DiskTreeNode root) {
    final junkBytes = root.junkBytes;
    final cleanableCount = _countCleanableNodes(root);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Left: drive info (fixed)
          Icon(PhosphorIconsLight.hardDrive,
              size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '${root.fullPath}  ${_fmt(root.sizeBytes)}  •  ${root.fileCount} files',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 16),
          // Middle: scanning status (takes remaining space, keeps buttons fixed)
          Expanded(
            child: _isScanningFullDisk
                ? Row(
                    children: [
                      Expanded(
                        child: Text(
                          _lastProgress == null
                              ? 'Scanning...'
                              : _lastProgress!.currentPath,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : _agentScanning
                    ? Row(
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
                                      ? 'CB Agent is scanning...'
                                      : _agentStatus)
                                  : 'CB Agent: $_agentCurrentPath',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.tertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_agentItemsFound > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '$_agentItemsFound items • ${_fmt(_agentBytesFound)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      )
                    : const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          // Right: badges + buttons (fixed position)
          // Junk summary badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Junk: ${_fmt(junkBytes)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filter cleanable-only
          Tooltip(
            message: 'Show cleanable only',
            child: FilterChip(
              label: Text('Cleanable only ($cleanableCount)'),
              selected: _showCleanableOnly,
              onSelected: (v) => setState(() => _showCleanableOnly = v),
            ),
          ),
          const SizedBox(width: 8),
          // Quick check actions
          TextButton(
            onPressed: () => _setAllCleanableChecked(_rootNode, true),
            child: const Text('Check all cleanable'),
          ),
          TextButton(
            onPressed: () => _setAllCleanableChecked(_rootNode, false),
            child: const Text('Uncheck all'),
          ),
          const SizedBox(width: 8),
          if (_aiAvailable)
            FilledButton.tonalIcon(
              onPressed: _openAiPanel,
              icon: const Icon(PhosphorIconsLight.sparkle, size: 16),
              label: Text(l.diskCleanerAskAgent),
            ),
          const SizedBox(width: 8),
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
              });
            },
            icon: Icon(
              _isScanningFullDisk
                  ? Icons.stop_rounded
                  : PhosphorIconsLight.arrowCounterClockwise,
              size: 16,
            ),
            label:
                Text(_isScanningFullDisk ? 'Cancel' : l.diskCleanerScanAgain),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tree panel (left)
  // ---------------------------------------------------------------------------

  Widget _buildTreePanel(ThemeData theme, DiskTreeNode root) {
    // Flatten the visible tree into a list for ListView.builder (lazy render).
    final flatRows = <_FlatRow>[];
    void flatten(DiskTreeNode node, int depth, int parentSize) {
      if (!_passesTreeFilter(node)) return;
      flatRows.add(_FlatRow(node: node, depth: depth, parentSize: parentSize));
      if (node.isExpanded && !node.isFile) {
        for (final child in node.children) {
          flatten(child, depth + 1, node.sizeBytes);
        }
      }
    }

    for (final child in root.children) {
      flatten(child, 0, root.sizeBytes);
    }

    return Column(
      children: [
        // Column headers
        Container(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 28), // checkbox space
              const SizedBox(width: 20), // expand arrow space
              Expanded(
                flex: 4,
                child: Text('Name',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: 80,
                child: Text('Size',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 90,
                child: Text('% of Parent',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              SizedBox(
                width: 60,
                child: Text('Files',
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
                            ? 'Building disk tree...'
                            : 'No files found',
                        style: theme.textTheme.titleSmall,
                      ),
                      if (_lastProgress != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_fmt(_lastProgress!.bytesScanned)} • ${_lastProgress!.filesScanned} files',
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
                      onTap: () {
                        if (!row.node.isFile) {
                          setState(
                              () => row.node.isExpanded = !row.node.isExpanded);
                        }
                        _selectedNode = row.node;
                      },
                      onToggleJunk: (target) => setState(() {
                        _applyCheckRecursiveGlobal(row.node, target);
                      }),
                      onAskAi:
                          _aiAvailable ? () => _askAiAboutNode(row.node) : null,
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _applyCheckRecursiveGlobal(DiskTreeNode node, bool checked) {
    void walk(DiskTreeNode n) {
      if (n.isJunk) {
        n.isSelectedForDeletion = checked;
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(node);
  }

  // ---------------------------------------------------------------------------
  // Pie chart panel (right)
  // ---------------------------------------------------------------------------

  Widget _buildPiePanel(ThemeData theme, DiskTreeNode node) {
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
                'Analyzing disk usage...',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _lastProgress == null
                    ? 'Pie chart will appear after scan completes.'
                    : '${_fmt(_lastProgress!.bytesScanned)} scanned • ${_lastProgress!.filesScanned} files',
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
                  ? 'Pie chart will appear as soon as scan completes'
                  : 'Empty',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
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
                segments: children
                    .take(10)
                    .map((c) => _PieSegment(
                          value: c.sizeBytes.toDouble(),
                          color: c.isJunk || c.hasJunkChildren
                              ? Colors.orange
                              : _pieColor(children.indexOf(c)),
                          label: c.name,
                        ))
                    .toList(),
                total: node.sizeBytes.toDouble(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Expanded(
            child: ListView(
              children: children.take(10).map((c) {
                final idx = children.indexOf(c);
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
                                ? 'Preparing files...'
                                : (snap.status.isEmpty
                                    ? 'Cleaning...'
                                    : snap.status),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPreparing
                                ? (snap.currentPath.isEmpty
                                    ? 'Scanning selected directories...'
                                    : 'Scanning ${snap.currentPath}')
                                : (snap.currentPath.isEmpty
                                    ? 'Deleting selected junk items. If a file fails, you can skip it or try again.'
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
                          ? 'Permanent delete'
                          : 'Recycle Bin',
                    ),
                    _buildProgressStatChip(
                      theme: theme,
                      icon: PhosphorIconsLight.chartBar,
                      label: '${snap.done} / ${snap.total} processed',
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
                          ? 'Deleting items...'
                          : '$progressPercent% complete',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${snap.total - snap.done} remaining',
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
                ? (_cleanStatus.isEmpty ? 'Cleaning...' : _cleanStatus)
                : _reviewMode
                    ? 'Review mode • Selected: ${_fmt(selectedBytes)}'
                    : 'Selected: ${_fmt(selectedBytes)} / ${_fmt(junkBytes)}',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          if (_reviewMode && !_isCleaningJunk) ...[
            OutlinedButton.icon(
              onPressed: () => setState(() => _reviewMode = false),
              icon: const Icon(PhosphorIconsLight.arrowLeft, size: 14),
              label: const Text('Back to results'),
            ),
            const SizedBox(width: 8),
            if (_aiAvailable)
              OutlinedButton.icon(
                onPressed: _askAiReviewPending,
                icon: const Icon(PhosphorIconsLight.sparkle, size: 14),
                label: const Text('Review by CB Agent'),
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
                    ? 'Delete ${_fmt(selectedBytes)} permanently'
                    : 'Move ${_fmt(selectedBytes)} to Recycle Bin',
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
                  ? 'Cleaning...'
                  : 'Review ${_fmt(selectedBytes)} & clean'),
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
      if (n.isSelectedForDeletion && n.junkCategoryId != null) {
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
      if (n.isSelectedForDeletion && n.junkCategoryId != null) {
        items.add(JunkItem(
          path: n.fullPath,
          sizeBytes: n.sizeBytes,
          categoryId: n.junkCategoryId!,
          isContainerOnly: !n.isFile,
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
    setState(() => _reviewMode = false);
    await _cleanJunk(
        permanent: _selectedCleanMode == _CleanDeleteMode.permanent);
  }

  Future<void> _cleanJunk({required bool permanent}) async {
    if (_isCleaningJunk || _pendingCleanItems.isEmpty) return;
    setState(() {
      _isCleaningJunk = true;
      _cleanedSkippedInUseCount = 0;
      _cleanedSkippedByUserCount = 0;
      _skipAllDeleteFailures = false;
      _cleanStatus =
          permanent ? 'Permanently deleting...' : 'Moving to Recycle Bin...';
    });

    // Let Flutter paint the initial progress UI before the first native
    // delete batch starts. Without this, the bottom bar can stay visually at
    // 0 / N until the first chunk completes.
    await WidgetsBinding.instance.endOfFrame;
    _lastCleanProgressUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    _cleanProgress.value = _CleanProgressSnapshot(
      status:
          permanent ? 'Permanently deleting...' : 'Moving to Recycle Bin...',
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
                ? 'Permanently deleting...'
                : 'Moving to Recycle Bin...',
          );
        },
      );

      if (!mounted) return;
      final succeededSet = result.succeeded.toSet();
      final cleanedItems =
          items.where((i) => succeededSet.contains(i.path)).toList();

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
      });
      _service.pendingCleanupItems = const [];
      _service.pendingCleanupBytes = 0;
      if (result.skippedInUseCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Skipped ${result.skippedInUseCount} file(s) currently in use. Details were logged.',
            ),
          ),
        );
      } else if (result.skippedByUserCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Skipped ${result.skippedByUserCount} file(s) after delete failed.',
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
        SnackBar(content: Text('Cleanup failed: $e')),
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
              ? 'Permanently deleted ${result.successCount} items (${_fmt(result.freedBytes)}). Skipped ${result.skippedInUseCount} in-use file(s); details were logged.'
              : result.skippedByUserCount > 0
                  ? 'Permanently deleted ${result.successCount} items (${_fmt(result.freedBytes)}). Skipped ${result.skippedByUserCount} file(s) after delete failed.'
                  : 'Permanently deleted ${result.successCount} items (${_fmt(result.freedBytes)})'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isPermanentDeleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permanent delete failed: $e')),
      );
    }
  }

  Future<bool?> _showPermanentDeleteDialog({
    required int itemCount,
    required int bytes,
    required bool fromRecycleBin,
  }) {
    final content = fromRecycleBin
        ? 'This will permanently delete $itemCount items '
            '(${_fmt(bytes)}) from your Recycle Bin. '
            'They cannot be restored after this.'
        : 'This will permanently delete $itemCount selected items '
            '(${_fmt(bytes)}). They cannot be restored after this.';

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanent delete?'),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Permanent delete'),
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
    final prev = _cleanProgress.value;
    _cleanProgress.value = _CleanProgressSnapshot(
      done: prev.done,
      total: prev.total,
      currentPath: details.item.path,
      status: 'Waiting for your decision...',
    );

    final fileName = _fileBasename(details.item.path);
    final actionLabel =
        details.permanent ? 'permanently delete' : 'move to Recycle Bin';
    final reasonText = details.isInUse
        ? 'This file appears to be in use by another application.'
        : details.reason;

    var skipAll = false;
    final action = await showDialog<CleanFailureAction>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: Text('Could not $actionLabel'),
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
                      'Retrying now will usually fail again until the app or process using this file is closed.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  if (details.blockedPath != null &&
                      details.blockedPath != details.item.path) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Blocked by: ${details.blockedPath}',
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
                    title: const Text('Skip all remaining items'),
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
                  child: const Text('Skip'),
                ),
                if (!details.isInUse)
                  FilledButton(
                    onPressed: () =>
                        Navigator.of(ctx).pop(CleanFailureAction.retry),
                    child: const Text('Try again'),
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
            ? 'Permanently deleting...'
            : 'Moving to Recycle Bin...',
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
                  'Freed ${_fmt(_cleanedFreedBytes)}  •  $successCount items',
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
                    '$_cleanedFailureCount failed',
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
                    '$_cleanedSkippedInUseCount in use',
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
                    '$_cleanedSkippedByUserCount skipped',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const Spacer(),
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
                    'Skipped $_cleanedSkippedInUseCount file(s) currently in use. See logs for the full path list.',
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
                    'Skipped $_cleanedSkippedByUserCount file(s) after delete failed because you chose Skip.',
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
                    'Deleted $successCount items permanently.',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Freed ${_fmt(_cleanedFreedBytes)}',
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
                  'Permanent delete finished for $successCount items.',
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
                  child: Text('File name',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  flex: 4,
                  child: Text('Path',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  width: 80,
                  child: Text('Size',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      textAlign: TextAlign.right),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 100,
                  child: Text('Category',
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
                        Text('No items are currently in the Recycle Bin.',
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
                      ? 'Permanently deleting... $_permanentDone / $_permanentTotal'
                      : '${_cleanedItems.length} items in Recycle Bin (${_fmt(_cleanedFreedBytes)})',
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
                        ? 'Deleting...'
                        : 'Permanent delete'),
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
                  Text(label,
                      style: TextStyle(color: theme.colorScheme.primary)),
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
  final bool Function(DiskTreeNode)? nodeFilter;

  const _TreeRow({
    required this.node,
    required this.depth,
    required this.parentSize,
    required this.theme,
    required this.onSelect,
    required this.onToggleJunk,
    this.onAskAi,
    this.nodeFilter,
  });

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _isHovering = false;

  bool _subtreeHasJunk(DiskTreeNode node) {
    if (node.isJunk) return true;
    for (final c in node.children) {
      if (_subtreeHasJunk(c)) return true;
    }
    return false;
  }

  int _countJunkNodes(DiskTreeNode node) {
    int count = node.isJunk ? 1 : 0;
    for (final c in node.children) {
      count += _countJunkNodes(c);
    }
    return count;
  }

  int _countCheckedJunkNodes(DiskTreeNode node) {
    int count = node.isJunk && node.isSelectedForDeletion ? 1 : 0;
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
    // If this folder itself is not a cleanable target, but descendants are
    // selected, keep the parent as indeterminate. This makes it clear that
    // only cleanable children (e.g. Logs) are selected, not the surrounding
    // parent folder.
    if (!node.isJunk) return null;
    if (checked == total) return true;
    return null; // indeterminate (dash)
  }

  void _applyCheckRecursive(DiskTreeNode node, bool checked) {
    if (node.isJunk) {
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
            child: Container(
              color: isJunk
                  ? Colors.orange.withValues(alpha: 0.06)
                  : Colors.transparent,
              padding: EdgeInsets.only(
                  left: 12 + indent, right: 12, top: 4, bottom: 4),
              child: Row(
                children: [
                  // Junk checkbox (only for junk nodes)
                  SizedBox(
                    width: 28,
                    child: _subtreeHasJunk(node)
                        ? Checkbox(
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
                          )
                        : const SizedBox.shrink(),
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
                                message: 'Ask CB Agent about this',
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
              nodeFilter: widget.nodeFilter,
            ))
        .toList();

    if (hiddenCount > 0) {
      rows.add(_TreeRow(
        node: DiskTreeNode(
          name: '... and $hiddenCount more items',
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
  bool shouldRepaint(_PieChartPainter old) => true;
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
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleJunk;
  final VoidCallback? onAskAi;

  const _FlatTreeRowWidget({
    required this.row,
    required this.theme,
    required this.onTap,
    required this.onToggleJunk,
    this.onAskAi,
  });

  @override
  State<_FlatTreeRowWidget> createState() => _FlatTreeRowWidgetState();
}

class _FlatTreeRowWidgetState extends State<_FlatTreeRowWidget> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.row.node;
    final indent = 16.0 * widget.row.depth;
    final percent = node.percentOf(widget.row.parentSize);
    final hasChildren = !node.isFile && node.children.isNotEmpty;
    final isJunk = node.isJunk || node.hasJunkChildren;
    final categoryId = node.junkCategoryId;
    final theme = widget.theme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          color: _hovering
              ? theme.colorScheme.primary.withValues(alpha: 0.06)
              : isJunk
                  ? Colors.orange.withValues(alpha: 0.04)
                  : Colors.transparent,
          padding: EdgeInsets.only(left: 12 + indent, right: 12),
          child: Row(
            children: [
              // Checkbox
              SizedBox(
                width: 28,
                child: (node.isJunk || node.hasJunkChildren)
                    ? GestureDetector(
                        onTap: () {
                          final current = _checkState(node);
                          widget.onToggleJunk(current != true);
                        },
                        child: Icon(
                          _checkState(node) == true
                              ? Icons.check_box
                              : _checkState(node) == null
                                  ? Icons.indeterminate_check_box
                                  : Icons.check_box_outline_blank,
                          size: 18,
                          color: Colors.orange.shade700,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // Expand arrow
              SizedBox(
                width: 20,
                child: hasChildren
                    ? Icon(
                        node.isExpanded
                            ? PhosphorIconsLight.caretDown
                            : PhosphorIconsLight.caretRight,
                        size: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : const SizedBox.shrink(),
              ),
              // Icon + Name + badge
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
                          fontWeight:
                              node.isFile ? FontWeight.normal : FontWeight.w500,
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
              // Size
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
              // % bar
              SizedBox(
                width: 90,
                child: _PercentBar(percent: percent, isJunk: node.isJunk),
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
    );
  }

  bool? _checkState(DiskTreeNode node) {
    int total = 0;
    int checked = 0;
    void walk(DiskTreeNode n) {
      if (n.isJunk) {
        total++;
        if (n.isSelectedForDeletion) checked++;
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(node);
    if (total == 0) return false;
    if (checked == 0) return false;
    if (!node.isJunk && checked > 0) return null;
    if (checked == total) return true;
    return null;
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
