import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/bloc/selection/selection_bloc.dart';
import 'package:cb_file_manager/bloc/selection/selection_event.dart';
import 'package:cb_file_manager/bloc/selection/selection_state.dart';
import 'package:cb_file_manager/helpers/files/trash_manager.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_action_handlers.dart';
import 'package:cb_file_manager/ui/components/common/browser_like_collection_view.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/components/common/file_view_shell.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/components/common/skeleton_helper.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
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

class _TrashSelectionSummaryData {
  final List<String> paths;
  final bool visible;

  const _TrashSelectionSummaryData({
    required this.paths,
    required this.visible,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _TrashSelectionSummaryData &&
        visible == other.visible &&
        _listEquals(paths, other.paths);
  }

  @override
  int get hashCode => Object.hash(visible, Object.hashAll(paths));
}

class _TrashItemSelectionData {
  final bool isSelected;
  final bool isSelectionMode;

  const _TrashItemSelectionData({
    required this.isSelected,
    required this.isSelectionMode,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _TrashItemSelectionData &&
        isSelected == other.isSelected &&
        isSelectionMode == other.isSelectionMode;
  }

  @override
  int get hashCode => Object.hash(isSelected, isSelectionMode);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

class _TrashBinScreenState extends State<TrashBinScreen> {
  final TrashManager _trashManager = TrashManager();
  late final SelectionBloc _selectionBloc;
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
  Set<String> _preDragSelectedPaths = const <String>{};

  @override
  void initState() {
    super.initState();
    _selectionBloc = SelectionBloc();
    _loadPreferences();
    _loadTrashItems();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _selectionBloc.close();
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

      // Update thumbnail loader with file paths for priority loading
      _updateThumbnailDisplayIndex();
    } catch (e) {
      setState(() {
        _errorCode = 'load';
        _errorArgs = [e.toString()];
        _isLoading = false;
      });
    }
  }

  void _updateThumbnailDisplayIndex() {
    final sortedItems = _getSortedAndFilteredItems();
    final filePaths = sortedItems.map((item) => item.actualFilePath).toList();
    ThumbnailLoader.updateDisplayIndexMap(filePaths);
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
    final confirm = await BrowserLikeActionHandlers.showConfirmationDialog(
      context: context,
      dialog: AlertDialog(
        title: Text(l10n.permanentDeleteTitle),
        content: Text(l10n.confirmDeletePermanent(item.displayNameValue)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (!confirm) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = item.isSystemTrashItem && Platform.isWindows
          ? await _trashManager.deleteFromWindowsRecycleBin(item.trashFileName)
          : await _trashManager.deleteFromTrash(item.trashFileName);

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
    final confirm = await BrowserLikeActionHandlers.showConfirmationDialog(
      context: context,
      dialog: AlertDialog(
        title: Text(l10n.emptyTrashButton),
        content: Text(l10n.emptyTrashConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.emptyTrash,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (!confirm) return;

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
  // Selection helpers
  // ---------------------------------------------------------------------------

  SelectionState get _selectionState => _selectionBloc.state;
  Set<String> get _selectedPaths => _selectionState.selectedFilePaths;

  void _toggleSelectionMode() {
    _selectionBloc.add(
      ToggleSelectionMode(forceValue: !_selectionState.isSelectionMode),
    );
  }

  void _clearSelection() {
    _selectionBloc.add(ClearSelection());
  }

  void _handleEscape() {
    if (_selectionBloc.state.selectedCount > 0) {
      _clearSelection();
      return;
    }
    if (_showSearch) {
      _closeSearch();
    }
  }

  void _toggleItemSelection(String key) {
    final keyboard = HardwareKeyboard.instance;
    final isShiftPressed = keyboard.isShiftPressed;
    final isCtrlPressed = keyboard.isControlPressed || keyboard.isMetaPressed;

    if (!isShiftPressed) {
      _selectionBloc.add(
        ToggleFileSelection(
          key,
          shiftSelect: false,
          ctrlSelect: isCtrlPressed,
        ),
      );
      return;
    }

    final selectionState = _selectionState;
    if (selectionState.lastSelectedPath == null) {
      _selectionBloc.add(
        ToggleFileSelection(
          key,
          shiftSelect: false,
          ctrlSelect: isCtrlPressed,
        ),
      );
      return;
    }

    final visiblePaths =
        _getSortedAndFilteredItems().map((item) => item.trashFileName).toList();
    final currentIndex = visiblePaths.indexOf(key);
    final lastIndex = visiblePaths.indexOf(selectionState.lastSelectedPath!);
    if (currentIndex == -1 || lastIndex == -1) return;

    final start = currentIndex < lastIndex ? currentIndex : lastIndex;
    final end = currentIndex < lastIndex ? lastIndex : currentIndex;
    _selectionBloc.add(
      SelectItemsInRect(
        folderPaths: const <String>{},
        filePaths: visiblePaths.sublist(start, end + 1).toSet(),
        isCtrlPressed: isCtrlPressed,
        isShiftPressed: true,
        lastSelectedPath: key,
      ),
    );
  }

  void _selectAll() {
    _selectionBloc.add(
      SelectAll(
        allFilePaths: _trashItems.map((e) => e.trashFileName).toList(),
        allFolderPaths: const <String>[],
      ),
    );
  }

  Future<void> _deleteSelectedItems() async {
    final l10n = AppLocalizations.of(context)!;
    final keys = List<String>.from(_selectedPaths);
    final confirm = await BrowserLikeActionHandlers.showConfirmationDialog(
      context: context,
      dialog: AlertDialog(
        title: Text(l10n.permanentDeleteTitle),
        content: Text(l10n.confirmDeletePermanentMultiple(keys.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n.delete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (!confirm) return;

    _clearSelection();
    setState(() {
      _isLoading = true;
    });

    try {
      final successCount =
          await BrowserLikeActionHandlers.runBatchOperation<String>(
        items: keys,
        operation: (key) async {
          final item = _trashItems.firstWhere(
            (entry) => entry.trashFileName == key,
            orElse: () => throw StateError('not found'),
          );
          if (item.isSystemTrashItem && Platform.isWindows) {
            return _trashManager.deleteFromWindowsRecycleBin(key);
          }
          return _trashManager.deleteFromTrash(key);
        },
      );

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
    final keyboard = HardwareKeyboard.instance;
    setState(() {
      _isDraggingRect = true;
      _dragStartPosition = localPosition;
      _dragCurrentPosition = localPosition;
      _preDragSelectedPaths =
          keyboard.isControlPressed || keyboard.isMetaPressed
              ? Set<String>.from(_selectedPaths)
              : const <String>{};
    });
  }

  void _updateDragSelection(Offset position) {
    if (!_isDraggingRect) return;
    final matched = _computeMatchedItems(position);
    final keyboard = HardwareKeyboard.instance;
    final isCtrlPressed = keyboard.isControlPressed || keyboard.isMetaPressed;
    setState(() {
      _dragCurrentPosition = position;
    });
    _selectionBloc.add(
      SelectItemsInRect(
        folderPaths: const <String>{},
        filePaths: matched,
        isCtrlPressed: isCtrlPressed,
        isShiftPressed: false,
        preCtrlDragFiles: _preDragSelectedPaths,
        preCtrlDragFolders: const <String>{},
      ),
    );
  }

  void _endDragSelection() {
    if (!_isDraggingRect) return;
    setState(() {
      _isDraggingRect = false;
      _dragStartPosition = null;
      _dragCurrentPosition = null;
      _preDragSelectedPaths = const <String>{};
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  VoidCallback _onEnterSelection(String key) => () {
        _selectionBloc.add(const ToggleSelectionMode(forceValue: true));
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
        _updateThumbnailDisplayIndex();
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
        _updateThumbnailDisplayIndex();
      },
      onRefresh: _loadTrashItems,
      currentGridZoomLevel: _viewMode == ViewMode.grid ? _gridZoomLevel : null,
      onGridZoomChanged: (size) {
        setState(() => _gridZoomLevel = size);
        UserPreferences.instance.setTrashGridZoomLevel(size);
        _updateThumbnailDisplayIndex();
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
      onChanged: (v) {
        setState(() => _searchQuery = v);
        _updateThumbnailDisplayIndex();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _selectionBloc,
      child: Scaffold(
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
              onDelete: ({required bool permanent}) async {
                if (_selectionBloc.state.selectedFilePaths.isEmpty) {
                  return;
                }
                await _deleteSelectedItems();
              },
              onEscape: _showSearch || _selectionBloc.state.selectedCount > 0
                  ? _handleEscape
                  : null,
              child: _buildBody(),
            ),
            if (_isDesktop)
              BlocSelector<SelectionBloc, SelectionState,
                  _TrashSelectionSummaryData>(
                selector: (state) => _TrashSelectionSummaryData(
                  paths: state.selectedFilePaths.toList(),
                  visible: state.selectedFilePaths.length > 1,
                ),
                builder: (context, selection) {
                  if (!selection.visible) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: SelectionSummaryTooltip(
                      selectedFileCount: selection.paths.length,
                      selectedFolderCount: 0,
                      selectedFilePaths: selection.paths,
                      selectedFolderPaths: const [],
                    ),
                  );
                },
              ),
          ],
        ),
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

    if (_isLoading && _trashItems.isEmpty) {
      return _buildSkeletonLoader();
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

    return _buildItemsView(items, l10n);
  }

  Widget _buildItemsView(List<TrashItem> items, AppLocalizations l10n) {
    // Invalidate stale item positions after each build (never during an active drag).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDraggingRect) _itemPositions.clear();
    });
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.columns,
    );
    final crossAxisCount =
        _gridZoomLevel.clamp(UserPreferences.minGridZoomLevel, maxZoom).toInt();

    return BrowserLikeCollectionView<TrashItem>(
      viewMode: _viewMode,
      items: items,
      isDesktop: _isDesktop,
      stackKey: _stackKey,
      onRefresh: _loadTrashItems,
      onDragStart: _isDesktop ? _startDragSelection : null,
      onDragUpdate: _isDesktop ? _updateDragSelection : null,
      onDragEnd: _isDesktop ? _endDragSelection : null,
      itemIdentity: (item) => item.trashFileName,
      registerItemPosition: _registerItemPosition,
      dragSelectionOverlay: _buildDragSelectionOverlay(),
      gridCrossAxisCount: crossAxisCount,
      padding: const EdgeInsets.all(8.0),
      gridSpacing: GridZoomConstraints.fileGridSpacing,
      gridChildAspectRatio: 0.8,
      gridCacheExtent: _isDesktop ? 600 : 400,
      listItemBuilder: (itemContext, item) =>
          _buildSelectableListItem(itemContext, item, l10n),
      gridItemBuilder: (itemContext, item) =>
          _buildSelectableGridItem(itemContext, item),
      detailsHeader: _buildDetailsHeader(l10n),
      detailsItemBuilder: (itemContext, item) =>
          _buildSelectableDetailsItem(itemContext, item, l10n),
    );
  }

  void _registerItemPosition(String key, Rect rect) {
    if (mounted) {
      _itemPositions[key] = rect;
    }
  }

  Widget _buildSelectableListItem(
    BuildContext itemContext,
    TrashItem item,
    AppLocalizations l10n,
  ) {
    return BlocSelector<SelectionBloc, SelectionState, _TrashItemSelectionData>(
      selector: (state) => _TrashItemSelectionData(
        isSelected: state.selectedFilePaths.contains(item.trashFileName),
        isSelectionMode: _isDesktop
            ? state.selectedFilePaths.length > 1
            : state.isSelectionMode,
      ),
      builder: (context, selection) => TrashListItem(
        key: ValueKey(item.trashFileName),
        item: item,
        isSelected: selection.isSelected,
        isSelectionMode: selection.isSelectionMode,
        isDesktop: _isDesktop,
        onTap: item.isFolder && !_isDesktop ? () => _openFolder(item) : null,
        onDoubleTap:
            item.isFolder && _isDesktop ? () => _openFolder(item) : null,
        onToggleSelection: () => _toggleItemSelection(item.trashFileName),
        onEnterSelectionMode: _onEnterSelection(item.trashFileName),
        onContextMenu: (pos) => _showContextMenu(itemContext, item, pos),
        formatDate: (date) =>
            FormatUtils.formatDateLocalized(date, itemContext),
        formatSize: _formatFileSize,
        l10n: l10n,
      ),
    );
  }

  Widget _buildSelectableGridItem(BuildContext itemContext, TrashItem item) {
    return BlocSelector<SelectionBloc, SelectionState, _TrashItemSelectionData>(
      selector: (state) => _TrashItemSelectionData(
        isSelected: state.selectedFilePaths.contains(item.trashFileName),
        isSelectionMode: _isDesktop
            ? state.selectedFilePaths.length > 1
            : state.isSelectionMode,
      ),
      builder: (context, selection) => TrashGridItem(
        key: ValueKey(item.trashFileName),
        item: item,
        isSelected: selection.isSelected,
        isSelectionMode: selection.isSelectionMode,
        isDesktop: _isDesktop,
        onTap: item.isFolder && !_isDesktop ? () => _openFolder(item) : null,
        onDoubleTap:
            item.isFolder && _isDesktop ? () => _openFolder(item) : null,
        onToggleSelection: () => _toggleItemSelection(item.trashFileName),
        onEnterSelectionMode: _onEnterSelection(item.trashFileName),
        onContextMenu: (pos) => _showContextMenu(itemContext, item, pos),
      ),
    );
  }

  Widget _buildSelectableDetailsItem(
    BuildContext itemContext,
    TrashItem item,
    AppLocalizations l10n,
  ) {
    return BlocSelector<SelectionBloc, SelectionState, _TrashItemSelectionData>(
      selector: (state) => _TrashItemSelectionData(
        isSelected: state.selectedFilePaths.contains(item.trashFileName),
        isSelectionMode: _isDesktop
            ? state.selectedFilePaths.length > 1
            : state.isSelectionMode,
      ),
      builder: (context, selection) => TrashDetailsRow(
        key: ValueKey(item.trashFileName),
        item: item,
        isSelected: selection.isSelected,
        isSelectionMode: selection.isSelectionMode,
        isDesktop: _isDesktop,
        onTap: item.isFolder && !_isDesktop ? () => _openFolder(item) : null,
        onDoubleTap:
            item.isFolder && _isDesktop ? () => _openFolder(item) : null,
        onToggleSelection: () => _toggleItemSelection(item.trashFileName),
        onEnterSelectionMode: _onEnterSelection(item.trashFileName),
        onContextMenu: (pos) => _showContextMenu(itemContext, item, pos),
        formatDate: (date) =>
            FormatUtils.formatDateLocalized(date, itemContext),
        formatSize: _formatFileSize,
        l10n: l10n,
      ),
    );
  }

  Widget _buildDetailsHeader(AppLocalizations l10n) {
    return BlocSelector<SelectionBloc, SelectionState, bool>(
      selector: (state) => _isDesktop
          ? state.selectedFilePaths.length > 1
          : state.isSelectionMode,
      builder: (context, visualSelectionMode) => Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                if (visualSelectionMode) const SizedBox(width: 40),
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      const SizedBox(width: 36),
                      Text(
                        l10n.fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    l10n.columnOriginalPath,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    l10n.columnDateDeleted,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    l10n.columnSize,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
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

  Widget _buildSkeletonLoader() {
    return SkeletonHelper.responsive(
      isGridView: _viewMode == ViewMode.grid,
      isAlbum: false,
      crossAxisCount: _gridZoomLevel,
      itemCount: 12,
      wrapInCardOnDesktop: true,
    );
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
