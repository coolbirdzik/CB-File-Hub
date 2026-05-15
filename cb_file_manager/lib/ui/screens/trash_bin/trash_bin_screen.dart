import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import '../mixins/selection_mixin.dart';
import 'package:cb_file_manager/ui/widgets/selection_rectangle_painter.dart';
import 'package:cb_file_manager/ui/widgets/selection_summary_tooltip.dart';
import 'widgets/widgets.dart';

/// Trash Bin screen - displays deleted items with restore/delete functionality.
/// This is essentially a file browsing screen with different data source and actions.
class TrashBinScreen extends StatefulWidget {
  final String tabId;
  const TrashBinScreen({Key? key, required this.tabId}) : super(key: key);

  @override
  State<TrashBinScreen> createState() => _TrashBinScreenState();
}

class _TrashBinScreenState extends State<TrashBinScreen> with SelectionMixin {
  final TrashManager _trashManager = TrashManager();
  List<TrashItem> _trashItems = [];
  bool _isLoading = true;
  String? _errorCode;
  List<String> _errorArgs = [];
  bool _showSystemOptions = false;

  // UI state
  ViewMode _viewMode = ViewMode.list;
  SortOption _sortOption = SortOption.dateDesc;
  String _searchQuery = '';
  bool _showSearch = false;
  int _gridZoomLevel = UserPreferences.defaultGridZoomLevel;
  final TextEditingController _searchController = TextEditingController();

  // Drag-to-select state (desktop only — lasso / rubber-band selection)
  bool _isDraggingRect = false;
  Offset? _dragStartPosition;
  Offset? _dragCurrentPosition;
  final Map<String, Rect> _itemPositions = {};
  final GlobalKey _stackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadTrashItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = UserPreferences.instance;
    final viewMode = await prefs.getTrashViewMode();
    final sortOption = await prefs.getTrashSortOption();
    final gridZoom = await prefs.getTrashGridZoomLevel();
    if (mounted) {
      setState(() {
        _viewMode = viewMode;
        _sortOption = sortOption;
        _gridZoomLevel = gridZoom;
      });
    }
  }

  void _handleGridZoomDelta(int delta) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.columns,
    );
    final next = (_gridZoomLevel + delta)
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();
    if (next == _gridZoomLevel) return;
    setState(() => _gridZoomLevel = next);
    UserPreferences.instance.setTrashGridZoomLevel(next);
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> _loadTrashItems() async {
    setState(() {
      _isLoading = true;
      _errorCode = null;
      _errorArgs = [];
    });

    try {
      final items = await _trashManager.getTrashItems();
      setState(() {
        _trashItems = items;
        _isLoading = false;
        _showSystemOptions =
            Platform.isWindows && items.any((item) => item.isSystemTrashItem);
      });
    } catch (e) {
      setState(() {
        _errorCode = 'load';
        _errorArgs = [e.toString()];
        _isLoading = false;
      });
    }
  }

  Future<void> _restoreItem(TrashItem item) async {
    setState(() {
      _isLoading = true;
    });

    try {
      bool success = false;

      if (item.isSystemTrashItem && Platform.isWindows) {
        success = await _trashManager
            .restoreFromWindowsRecycleBin(item.trashFileName);
      } else {
        success = await _trashManager.restoreFromTrash(item.trashFileName);
      }

      if (success) {
        if (mounted) {
          final l10n = AppLocalizations.of(context)!;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(l10n.itemRestoredSuccess(item.displayNameValue))),
          );
        }
        await _loadTrashItems();
      } else {
        setState(() {
          _isLoading = false;
          _errorCode = 'restore_failed';
          _errorArgs = [item.displayNameValue];
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorCode = 'restore_error';
        _errorArgs = [e.toString()];
      });
    }
  }

  Future<void> _deleteItem(TrashItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.permanentDeleteTitle),
            content: Text(l10n.confirmDeletePermanent(item.displayNameValue)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.delete,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() {
        _isLoading = true;
      });

      try {
        bool success = false;

        if (item.isSystemTrashItem && Platform.isWindows) {
          success = await _trashManager
              .deleteFromWindowsRecycleBin(item.trashFileName);
        } else {
          success = await _trashManager.deleteFromTrash(item.trashFileName);
        }

        if (success) {
          await _loadTrashItems();
        } else {
          setState(() {
            _isLoading = false;
            _errorCode = 'delete_failed';
            _errorArgs = [item.displayNameValue];
          });
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorCode = 'delete_error';
          _errorArgs = [e.toString()];
        });
      }
    }
  }

  /// Open a folder item from the trash bin by navigating the current tab
  /// to its actual path (where the data still exists on disk).
  void _openFolder(TrashItem item) {
    if (!item.isFolder) return;

    // For system trash items, the trashFileName is the recycleBinPath
    // which is the actual path where the folder data resides.
    // For internal trash items, the folder is in our internal trash directory.
    final String folderPath = item.trashFileName;

    // Verify the folder actually exists before navigating
    final dir = Directory(folderPath);
    if (!dir.existsSync()) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.folderNotFound)),
      );
      return;
    }

    TabNavigator.updateTabPath(context, widget.tabId, folderPath);
  }

  Future<void> _emptyTrash() async {
    final l10n = AppLocalizations.of(context)!;
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.emptyTrashButton),
            content: Text(l10n.emptyTrashConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.emptyTrash,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() {
        _isLoading = true;
      });

      try {
        final success = await _trashManager.emptyTrash();

        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.trashEmptiedSuccess)),
            );
          }
          await _loadTrashItems();
        } else {
          setState(() {
            _isLoading = false;
            _errorCode = 'empty_failed';
          });
        }
      } catch (e) {
        setState(() {
          _isLoading = false;
          _errorCode = 'empty_error';
          _errorArgs = [e.toString()];
        });
      }
    }
  }

  Future<void> _openSystemRecycleBin() async {
    try {
      await _trashManager.openWindowsRecycleBin();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening recycle bin: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Selection helpers — thin wrappers around SelectionMixin
  // ---------------------------------------------------------------------------

  void _toggleSelectionMode() => toggleSelectionMode();

  void _toggleItemSelection(String key) {
    toggleSelection(key);
    // Auto-enter / auto-exit selection mode like browse does.
    if (selectedPaths.isNotEmpty && !isSelectionMode) {
      enterSelectionMode();
    } else if (selectedPaths.isEmpty && isSelectionMode) {
      exitSelectionMode();
    }
  }

  void _selectAll() =>
      selectAll(_trashItems.map((e) => e.trashFileName).toList());

  Future<void> _deleteSelectedItems() async {
    final l10n = AppLocalizations.of(context)!;
    final keys = List<String>.from(selectedPaths);
    final bool confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.permanentDeleteTitle),
            content: Text(l10n.confirmDeletePermanentMultiple(keys.length)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.delete,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    exitSelectionMode();
    setState(() {
      _isLoading = true;
    });

    try {
      int successCount = 0;
      for (final key in keys) {
        final item = _trashItems.firstWhere((e) => e.trashFileName == key,
            orElse: () => throw StateError('not found'));
        bool success = false;

        if (item.isSystemTrashItem && Platform.isWindows) {
          success = await _trashManager.deleteFromWindowsRecycleBin(key);
        } else {
          success = await _trashManager.deleteFromTrash(key);
        }

        if (success) successCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.itemsPermanentlyDeletedCount(successCount)),
          ),
        );
      }

      await _loadTrashItems();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorCode = 'delete_items_error';
        _errorArgs = [e.toString()];
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Drag selection
  // ---------------------------------------------------------------------------

  void _startDragSelection(Offset localPosition) {
    setState(() {
      _isDraggingRect = true;
      _dragStartPosition = localPosition;
      _dragCurrentPosition = localPosition;
    });
  }

  void _updateDragSelection(Offset position) {
    if (!_isDraggingRect) return;
    final matched = _computeMatchedItems(position);
    setState(() {
      _dragCurrentPosition = position;
      selectedPaths.clear();
      selectedPaths.addAll(matched);
    });
    // Auto-enter selection mode the moment the first item is captured.
    if (matched.isNotEmpty && !isSelectionMode) {
      enterSelectionMode();
    }
  }

  void _endDragSelection() {
    if (!_isDraggingRect) return;
    setState(() {
      _isDraggingRect = false;
      _dragStartPosition = null;
      _dragCurrentPosition = null;
    });
  }

  /// Returns the set of trash-item keys whose registered global rects overlap
  /// the current drag selection rectangle (converted to global coords).
  Set<String> _computeMatchedItems(Offset currentPosition) {
    if (_dragStartPosition == null) return {};
    final selectionRect = Rect.fromPoints(_dragStartPosition!, currentPosition);
    // Convert Stack-local rect → global screen coords so it matches the
    // item positions, which are registered in global coords via localToGlobal.
    final RenderBox? stackBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final Rect globalRect = stackBox != null
        ? selectionRect.shift(stackBox.localToGlobal(Offset.zero))
        : selectionRect;
    final Set<String> matched = {};
    _itemPositions.forEach((key, rect) {
      if (globalRect.overlaps(rect)) matched.add(key);
    });
    return matched;
  }

  /// Overlay that draws the lasso rectangle while the user is dragging.
  Widget _buildDragSelectionOverlay() {
    if (!_isDraggingRect ||
        _dragStartPosition == null ||
        _dragCurrentPosition == null) {
      return const SizedBox.shrink();
    }
    final selectionRect =
        Rect.fromPoints(_dragStartPosition!, _dragCurrentPosition!);
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: SelectionRectanglePainter(
            selectionRect: selectionRect,
            fillColor: Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.4),
            borderColor: Theme.of(context).primaryColor,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) {
      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    if (date.year == now.year) {
      return '$month ${date.day}';
    }
    return '$month ${date.day}, ${date.year}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  VoidCallback _onEnterSelection(String key) => () {
        _toggleSelectionMode();
        _toggleItemSelection(key);
      };

  // ---------------------------------------------------------------------------
  // App bar
  // ---------------------------------------------------------------------------

  AppBar _buildAppBar(AppLocalizations l10n) {
    return AppBar(
      backgroundColor: _isDesktop ? Colors.transparent : null,
      elevation: _isDesktop ? 0 : null,
      title: _showSearch
          ? _buildInlineSearchField(l10n)
          : BreadcrumbAddressBar(
              segments: [
                BreadcrumbSegment(
                  label: l10n.trashBin,
                  icon: PhosphorIconsLight.trash,
                ),
              ],
            ),
      actions: _buildNormalActions(l10n),
    );
  }

  List<Widget> _buildNormalActions(AppLocalizations l10n) {
    return SharedActionBar.buildCommonActions(
      context: context,
      onSearchPressed: () => setState(() => _showSearch = true),
      onSortOptionSelected: (option) {
        setState(() => _sortOption = option);
        UserPreferences.instance.setTrashSortOption(option);
      },
      currentSortOption: _sortOption,
      viewMode: _viewMode,
      onViewModeToggled: () {},
      onViewModeSelected: (mode) {
        setState(() {
          // Cancel any in-progress drag selection before switching views.
          _isDraggingRect = false;
          _dragStartPosition = null;
          _dragCurrentPosition = null;
          _viewMode = mode;
        });
        UserPreferences.instance.setTrashViewMode(mode);
      },
      onRefresh: _loadTrashItems,
      currentGridZoomLevel: _viewMode == ViewMode.grid ? _gridZoomLevel : null,
      onGridZoomChanged: (size) {
        setState(() => _gridZoomLevel = size);
        UserPreferences.instance.setTrashGridZoomLevel(size);
      },
      onSelectionModeToggled: () {
        if (_trashItems.isNotEmpty) _toggleSelectionMode();
      },
      additionalMoreOptions: [
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'empty',
          enabled: _trashItems.isNotEmpty,
          child: Row(
            children: [
              Icon(
                PhosphorIconsLight.trash,
                size: 20,
                color: _trashItems.isNotEmpty
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                l10n.emptyTrash,
                style: TextStyle(
                  color: _trashItems.isNotEmpty
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
              ),
            ],
          ),
        ),
        if (Platform.isWindows && _showSystemOptions)
          PopupMenuItem<String>(
            value: 'recycle',
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.arrowSquareOut, size: 20),
                const SizedBox(width: 10),
                Text(l10n.openRecycleBin),
              ],
            ),
          ),
      ],
      onAdditionalMoreOptionSelected: (value) async {
        if (value == 'empty') {
          await _emptyTrash();
        } else if (value == 'recycle') {
          await _openSystemRecycleBin();
        }
      },
    );
  }

  Widget _buildInlineSearchField(AppLocalizations l10n) {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: l10n.search,
        border: InputBorder.none,
        hintStyle: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        suffixIcon: IconButton(
          icon: const Icon(PhosphorIconsLight.x),
          tooltip: l10n.cancel,
          onPressed: () => _closeSearch(),
        ),
      ),
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      onChanged: (v) => setState(() => _searchQuery = v),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDesktop ? Colors.transparent : null,
      appBar: _buildAppBar(AppLocalizations.of(context)!),
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          FileViewShell(
            viewMode: _viewMode,
            onGridZoomDelta: _handleGridZoomDelta,
            onRefresh: _loadTrashItems,
            onSelectAll: _trashItems.isNotEmpty ? _selectAll : null,
            onDelete: selectedPaths.isNotEmpty
                ? ({required bool permanent}) => _deleteSelectedItems()
                : null,
            onEscape: isSelectionMode
                ? exitSelectionMode
                : (_showSearch ? _closeSearch : null),
            child: _buildBody(),
          ),
          if (isSelectionMode && _isDesktop)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SelectionSummaryTooltip(
                selectedFileCount: selectedPaths.length,
                selectedFolderCount: 0,
                selectedFilePaths: selectedPaths.toList(),
                selectedFolderPaths: const [],
              ),
            ),
        ],
      ),
    );
  }

  void _closeSearch() {
    setState(() {
      _showSearch = false;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  String _getErrorMessage(AppLocalizations l10n) {
    if (_errorCode == null) return '';
    final a = _errorArgs;
    switch (_errorCode!) {
      case 'load':
        return l10n.errorLoadingTrashItemsWithError(a.isEmpty ? '' : a[0]);
      case 'restore_failed':
        return l10n.failedToRestore(a.isEmpty ? '' : a[0]);
      case 'restore_error':
        return l10n.errorRestoringItemWithError(a.isEmpty ? '' : a[0]);
      case 'delete_failed':
        return l10n.failedToDelete(a.isEmpty ? '' : a[0]);
      case 'delete_error':
        return l10n.errorDeletingItemWithError(a.isEmpty ? '' : a[0]);
      case 'empty_failed':
        return l10n.failedToEmptyTrash;
      case 'empty_error':
        return l10n.errorEmptyingTrashWithError(a.isEmpty ? '' : a[0]);
      case 'restore_items_error':
        return l10n.errorRestoringItemsWithError(a.isEmpty ? '' : a[0]);
      case 'delete_items_error':
        return l10n.errorDeletingItemsWithError(a.isEmpty ? '' : a[0]);
      default:
        return a.join(' ');
    }
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorCode != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PhosphorIconsLight.warning,
                color: Theme.of(context).colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _getErrorMessage(l10n),
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadTrashItems,
                icon: const Icon(PhosphorIconsLight.arrowsClockwise),
                label: Text(l10n.tryAgain),
              ),
            ],
          ),
        ),
      );
    }

    if (_trashItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsLight.trash,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.trashIsEmpty,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.itemsDeletedWillAppearHere,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTrashItems,
              icon: const Icon(PhosphorIconsLight.arrowsClockwise),
              label: Text(l10n.refresh),
            ),
          ],
        ),
      );
    }

    final items = _getSortedAndFilteredItems();

    if (items.isEmpty && _searchQuery.isNotEmpty) {
      return Center(
        child: Text(
          l10n.noFilesFoundQuery({'query': _searchQuery}),
          textAlign: TextAlign.center,
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (_viewMode == ViewMode.grid) {
      return _buildGridView(items, l10n);
    } else if (_viewMode == ViewMode.details) {
      return _buildDetailsView(items, l10n);
    } else {
      return _buildListView(items, l10n);
    }
  }

  // ---------------------------------------------------------------------------
  // List view
  // ---------------------------------------------------------------------------

  Widget _buildListView(List<TrashItem> items, AppLocalizations l10n) {
    // Invalidate stale item positions after each build (never during an active drag).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDraggingRect) _itemPositions.clear();
    });
    return Stack(
      key: _stackKey,
      children: [
        GestureDetector(
          onPanStart:
              _isDesktop ? (d) => _startDragSelection(d.localPosition) : null,
          onPanUpdate:
              _isDesktop ? (d) => _updateDragSelection(d.localPosition) : null,
          onPanEnd: _isDesktop ? (_) => _endDragSelection() : null,
          behavior: HitTestBehavior.translucent,
          child: RefreshIndicator(
            onRefresh: _loadTrashItems,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (itemContext, index) {
                final item = items[index];
                return LayoutBuilder(
                  builder: (layoutContext, _) {
                    // Register global rect for hit-testing during drag.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final rb = layoutContext.findRenderObject() as RenderBox?;
                      if (rb != null && rb.hasSize) {
                        final pos = rb.localToGlobal(Offset.zero);
                        _registerItemPosition(
                          item.trashFileName,
                          Rect.fromLTWH(
                              pos.dx, pos.dy, rb.size.width, rb.size.height),
                        );
                      }
                    });
                    return TrashListItem(
                      key: ValueKey(item.trashFileName),
                      item: item,
                      isSelected: selectedPaths.contains(item.trashFileName),
                      isSelectionMode: isSelectionMode,
                      isDesktop: _isDesktop,
                      onTap: item.isFolder && !_isDesktop
                          ? () => _openFolder(item)
                          : null,
                      onDoubleTap: item.isFolder && _isDesktop
                          ? () => _openFolder(item)
                          : null,
                      onToggleSelection: () =>
                          _toggleItemSelection(item.trashFileName),
                      onEnterSelectionMode:
                          _onEnterSelection(item.trashFileName),
                      onContextMenu: (pos) =>
                          _showContextMenu(itemContext, item, pos),
                      formatDate: _formatDate,
                      formatSize: _formatFileSize,
                      l10n: l10n,
                    );
                  },
                );
              },
            ),
          ),
        ),
        _buildDragSelectionOverlay(),
      ],
    );
  }

  void _registerItemPosition(String key, Rect rect) {
    if (mounted) {
      _itemPositions[key] = rect;
    }
  }

  // ---------------------------------------------------------------------------
  // Grid view
  // ---------------------------------------------------------------------------

  Widget _buildGridView(List<TrashItem> items, AppLocalizations l10n) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.columns,
    );
    final crossAxisCount =
        _gridZoomLevel.clamp(UserPreferences.minGridZoomLevel, maxZoom).toInt();

    // Invalidate stale item positions after each build (never during an active drag).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDraggingRect) _itemPositions.clear();
    });
    return Stack(
      key: _stackKey,
      children: [
        GestureDetector(
          onPanStart:
              _isDesktop ? (d) => _startDragSelection(d.localPosition) : null,
          onPanUpdate:
              _isDesktop ? (d) => _updateDragSelection(d.localPosition) : null,
          onPanEnd: _isDesktop ? (_) => _endDragSelection() : null,
          behavior: HitTestBehavior.translucent,
          child: RefreshIndicator(
            onRefresh: _loadTrashItems,
            child: GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
                childAspectRatio: 0.8,
              ),
              itemCount: items.length,
              itemBuilder: (itemContext, index) {
                final item = items[index];
                return LayoutBuilder(
                  builder: (layoutContext, _) {
                    // Register global rect for hit-testing during drag.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      final rb = layoutContext.findRenderObject() as RenderBox?;
                      if (rb != null && rb.hasSize) {
                        final pos = rb.localToGlobal(Offset.zero);
                        _registerItemPosition(
                          item.trashFileName,
                          Rect.fromLTWH(
                              pos.dx, pos.dy, rb.size.width, rb.size.height),
                        );
                      }
                    });
                    return TrashGridItem(
                      key: ValueKey(item.trashFileName),
                      item: item,
                      isSelected: selectedPaths.contains(item.trashFileName),
                      isSelectionMode: isSelectionMode,
                      isDesktop: _isDesktop,
                      onTap: item.isFolder && !_isDesktop
                          ? () => _openFolder(item)
                          : null,
                      onDoubleTap: item.isFolder && _isDesktop
                          ? () => _openFolder(item)
                          : null,
                      onToggleSelection: () =>
                          _toggleItemSelection(item.trashFileName),
                      onEnterSelectionMode:
                          _onEnterSelection(item.trashFileName),
                      onContextMenu: (pos) =>
                          _showContextMenu(itemContext, item, pos),
                    );
                  },
                );
              },
            ),
          ),
        ),
        _buildDragSelectionOverlay(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Details view
  // ---------------------------------------------------------------------------

  Widget _buildDetailsView(List<TrashItem> items, AppLocalizations l10n) {
    // Invalidate stale item positions after each build (never during an active drag).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDraggingRect) _itemPositions.clear();
    });
    return Stack(
      key: _stackKey,
      children: [
        GestureDetector(
          onPanStart:
              _isDesktop ? (d) => _startDragSelection(d.localPosition) : null,
          onPanUpdate:
              _isDesktop ? (d) => _updateDragSelection(d.localPosition) : null,
          onPanEnd: _isDesktop ? (_) => _endDragSelection() : null,
          behavior: HitTestBehavior.translucent,
          child: RefreshIndicator(
            onRefresh: _loadTrashItems,
            child: Column(
              children: [
                // Header row — matches FileDetailsItem column header style
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      if (isSelectionMode) const SizedBox(width: 40),
                      // Name column header (flex 3) with icon padding offset
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            const SizedBox(width: 36), // icon + gap space
                            Text(
                              l10n.fileName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          l10n.columnOriginalPath,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          l10n.columnDateDeleted,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          l10n.columnSize,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (itemContext, index) {
                      final item = items[index];
                      return LayoutBuilder(
                        builder: (layoutContext, _) {
                          // Register global rect for hit-testing during drag.
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            final rb =
                                layoutContext.findRenderObject() as RenderBox?;
                            if (rb != null && rb.hasSize) {
                              final pos = rb.localToGlobal(Offset.zero);
                              _registerItemPosition(
                                item.trashFileName,
                                Rect.fromLTWH(pos.dx, pos.dy, rb.size.width,
                                    rb.size.height),
                              );
                            }
                          });
                          return TrashDetailsRow(
                            key: ValueKey(item.trashFileName),
                            item: item,
                            isSelected:
                                selectedPaths.contains(item.trashFileName),
                            isSelectionMode: isSelectionMode,
                            isDesktop: _isDesktop,
                            onTap: item.isFolder && !_isDesktop
                                ? () => _openFolder(item)
                                : null,
                            onDoubleTap: item.isFolder && _isDesktop
                                ? () => _openFolder(item)
                                : null,
                            onToggleSelection: () =>
                                _toggleItemSelection(item.trashFileName),
                            onEnterSelectionMode:
                                _onEnterSelection(item.trashFileName),
                            onContextMenu: (pos) =>
                                _showContextMenu(itemContext, item, pos),
                            formatDate: _formatDate,
                            formatSize: _formatFileSize,
                            l10n: l10n,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildDragSelectionOverlay(),
      ],
    );
  }

  List<TrashItem> _getSortedAndFilteredItems() {
    List<TrashItem> items = _trashItems;

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      items = items.where((item) {
        return item.displayNameValue.toLowerCase().contains(query) ||
            item.originalPath.toLowerCase().contains(query);
      }).toList();
    }

    // Sort items
    switch (_sortOption) {
      case SortOption.nameAsc:
        items.sort((a, b) => a.displayNameValue
            .toLowerCase()
            .compareTo(b.displayNameValue.toLowerCase()));
        break;
      case SortOption.nameDesc:
        items.sort((a, b) => b.displayNameValue
            .toLowerCase()
            .compareTo(a.displayNameValue.toLowerCase()));
        break;
      case SortOption.dateAsc:
        items.sort((a, b) => a.trashedDate.compareTo(b.trashedDate));
        break;
      case SortOption.dateDesc:
        items.sort((a, b) => b.trashedDate.compareTo(a.trashedDate));
        break;
      case SortOption.sizeAsc:
        items.sort((a, b) => a.size.compareTo(b.size));
        break;
      case SortOption.sizeDesc:
        items.sort((a, b) => b.size.compareTo(a.size));
        break;
      case SortOption.typeAsc:
        items.sort((a, b) => _getExtension(a.displayNameValue)
            .compareTo(_getExtension(b.displayNameValue)));
        break;
      case SortOption.typeDesc:
        items.sort((a, b) => _getExtension(b.displayNameValue)
            .compareTo(_getExtension(a.displayNameValue)));
        break;
      default:
        items.sort((a, b) => b.trashedDate.compareTo(a.trashedDate));
    }
    return items;
  }

  String _getExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  void _showContextMenu(BuildContext context, TrashItem item, Offset position) {
    final l10n = AppLocalizations.of(context)!;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        if (item.isFolder)
          PopupMenuItem<String>(
            value: 'open',
            child: Row(
              children: [
                const Icon(PhosphorIconsLight.folderOpen, size: 20),
                const SizedBox(width: 10),
                Text(l10n.openFolder),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'restore',
          child: Row(
            children: [
              const Icon(PhosphorIconsLight.arrowsClockwise, size: 20),
              const SizedBox(width: 10),
              Text(l10n.restoreTooltip),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(PhosphorIconsLight.trash,
                  size: 20, color: Theme.of(context).colorScheme.error),
              const SizedBox(width: 10),
              Text(
                l10n.deletePermanentlyTooltip,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'open') {
        _openFolder(item);
      } else if (value == 'restore') {
        _restoreItem(item);
      } else if (value == 'delete') {
        _deleteItem(item);
      }
    });
  }
}
