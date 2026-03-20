import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/file_details_screen.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart';
import 'package:cb_file_manager/ui/components/common/skeleton.dart';
import 'package:cb_file_manager/ui/components/common/soft_checkbox.dart';
import 'package:cb_file_manager/ui/widgets/selection_rectangle_painter.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path/path.dart' as pathlib;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_data.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/uri_utils.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../utils/route.dart';

class TagManagementScreen extends StatefulWidget {
  final String startingDirectory;

  /// Callback when a tag is selected, used for opening in a new tab
  final Function(String)? onTagSelected;

  const TagManagementScreen({
    Key? key,
    this.startingDirectory = '',
    this.onTagSelected,
  }) : super(key: key);

  @override
  State<TagManagementScreen> createState() => _TagManagementScreenState();
}

class _TagManagementScreenState extends State<TagManagementScreen> {
  late TagColorManager _tagColorManager;
  StreamSubscription<String>? _tagChangeSubscription;
  Timer? _tagReloadDebounce;

  bool _isInitializing = true;
  bool _isInitialLoading = true;
  bool _isLoading = false;
  List<String> _allTags = [];
  List<String> _filteredTags = [];

  // Tags created standalone (not yet assigned to any file)
  final Set<String> _standaloneCreatedTags = {};

  // Single tag selection - for showing files list (previously _selectedTag)
  String? _selectedTagForFiles;
  List<Map<String, dynamic>> _filesBySelectedTag = [];

  // Focused tag - for visual selection highlight (click to select)
  String? _focusedTag;

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // Pagination variables
  int _currentPage = 0;
  int _tagsPerPage = 60;
  int _totalPages = 0;
  List<String> _currentPageTags = [];

  // Sorting options
  String _sortCriteria = 'name';
  bool _sortAscending = true;

  // View mode options
  bool _isGridView = false;

  // Multi-selection state
  final Set<String> _selectedTags = {};
  bool _isMultiSelectMode = false;

  // Inline rename state (desktop)
  String? _editingTag;
  TextEditingController? _editingTagController;

  /// Check if running on desktop platform
  bool get _isDesktop {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  bool get _isMobile {
    return Platform.isAndroid || Platform.isIOS;
  }

  // Keyboard state for Ctrl and Shift
  bool _isCtrlPressed = false;
  bool _isShiftPressed = false;

  // Drag selection state (with rectangle selection - like Windows Explorer)
  bool _isDraggingRect = false;
  Offset? _dragStartPosition;
  Offset? _dragCurrentPosition;
  final Map<String, Rect> _tagItemPositions = {};

  @override
  void initState() {
    super.initState();
    _initializeDatabase();

    _tagColorManager = TagColorManager.instance;
    _initTagColorManager();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setDefaultViewMode();
    });

    _searchController.addListener(_filterTags);

    // Listen to keyboard events for Ctrl and Shift
    HardwareKeyboard.instance.addHandler(_onKeyEvent);

    // Auto-reload when tags change (e.g., after seeding from dev tools)
    // Debounce to avoid flooding with multiple rapid tag additions
    _tagChangeSubscription = TagManager.onTagChanged.listen((event) {
      if (event.startsWith('global:') && mounted && !_isInitializing) {
        _tagReloadDebounce?.cancel();
        _tagReloadDebounce = Timer(const Duration(milliseconds: 600), () {
          if (mounted && !_isInitializing) {
            _loadAllTags();
          }
        });
      }
    });
  }

  bool _onKeyEvent(KeyEvent event) {
    setState(() {
      _isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
      _isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    });
    return false;
  }

  void _setDefaultViewMode() {
    if (!mounted) return;
    final screenWidth = MediaQuery.of(context).size.width;
    _isGridView = screenWidth > 600;
  }

  @override
  void dispose() {
    _tagReloadDebounce?.cancel();
    _tagChangeSubscription?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _searchController.removeListener(_filterTags);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initTagColorManager() async {
    await _tagColorManager.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _initializeDatabase() async {
    setState(() {
      _isInitializing = true;
    });

    try {
      await _loadAllTags();
    } catch (e) {
      // Handle initialization error
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _loadAllTags() async {
    try {
      await TagManager.initialize();
      final Set<String> tags = await TagManager.getAllUniqueTags("");
      final standaloneTags = await TagManager.getStandaloneTags();

      debugPrint(
          'TagManagementScreen: Found ${tags.length} unique tags (${standaloneTags.length} standalone)');

      if (mounted) {
        // Use addPostFrameCallback to ensure skeleton shows first
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _allTags = tags.toList();
              _allTags
                  .sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              _filterTags();
              _isInitialLoading = false;
            });
          }
        });
      }
    } catch (e) {
      debugPrint('TagManagementScreen: Error loading tags: $e');
      if (mounted) {
        final theme = Theme.of(context);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content:
                Text('${AppLocalizations.of(context)!.errorLoadingTags}$e'),
            backgroundColor: theme.colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _allTags = [];
          _filterTags();
        });
      }
    }
  }

  void _filterTags() {
    if (!mounted) return;

    final String query = _searchController.text.toLowerCase().trim();
    debugPrint('TagManagementScreen: Filtering tags with query: "$query"');
    debugPrint('TagManagementScreen: _allTags count: ${_allTags.length}');

    setState(() {
      if (query.isEmpty) {
        _filteredTags = List.from(_allTags);
      } else {
        _filteredTags =
            _allTags.where((tag) => tag.toLowerCase().contains(query)).toList();
      }

      debugPrint(
          'TagManagementScreen: _filteredTags count: ${_filteredTags.length}');

      _sortTags();
      _updatePagination();

      debugPrint(
          'TagManagementScreen: _currentPageTags count: ${_currentPageTags.length}');
    });
  }

  /// Sort the filtered tags based on the current sort criteria.
  /// For 'name' sort: alphabetical (case-insensitive).
  /// For 'popularity' and 'recent' sorts: loads counts/timestamps asynchronously
  /// and re-sorts the list once data is available, then updates the UI.
  void _sortTags() {
    switch (_sortCriteria) {
      case 'name':
        _filteredTags.sort((a, b) {
          final result = a.toLowerCase().compareTo(b.toLowerCase());
          return _sortAscending ? result : -result;
        });
        break;
      case 'popularity':
      case 'recent':
        // Defer to async sort — load data then re-sort
        _loadSortDataForFilteredTags();
        break;
    }
  }

  /// Loads sort data (file counts for popularity, timestamps for recent)
  /// for all filtered tags and applies the appropriate sort.
  /// Calls setState to refresh the UI after sorting.
  Future<void> _loadSortDataForFilteredTags() async {
    if (_filteredTags.isEmpty) return;

    try {
      if (_sortCriteria == 'popularity') {
        // Get file count for each tag
        final tagCounts = <String, int>{};
        for (final tag in _filteredTags) {
          final files = await TagManager.findFilesByTagGlobally(tag);
          tagCounts[tag] = files.length;
        }

        if (!mounted) return;
        setState(() {
          _filteredTags.sort((a, b) {
            final countA = tagCounts[a] ?? 0;
            final countB = tagCounts[b] ?? 0;
            final result = countA.compareTo(countB);
            return _sortAscending ? result : -result;
          });
          _updatePagination();
        });
      } else if (_sortCriteria == 'recent') {
        // Sort by most recently used (based on tag creation order in the allTags list).
        // Tags that appear earlier in allTags are considered "older".
        // This is a placeholder: true recent sorting would need modification timestamps.
        if (!mounted) return;
        setState(() {
          _filteredTags.sort((a, b) {
            final idxA = _allTags.indexOf(a);
            final idxB = _allTags.indexOf(b);
            final result = idxA.compareTo(idxB);
            // Ascending: older first (idxA < idxB means A is older). Descending: newer first.
            return _sortAscending ? result : -result;
          });
          _updatePagination();
        });
      }
    } catch (e) {
      debugPrint('TagManagementScreen: Error sorting by $_sortCriteria: $e');
    }
  }

  void _updatePagination() {
    final screenHeight = MediaQuery.of(context).size.height;
    // Increase tags per page to fill more space
    _tagsPerPage = _isDesktop
        ? (screenHeight ~/ 25).clamp(60, 300)
        : 60; // Fixed size for mobile to ensure consistent layout

    _totalPages = (_filteredTags.length / _tagsPerPage).ceil();
    if (_totalPages == 0) _totalPages = 1;

    if (_currentPage >= _totalPages) {
      _currentPage = _totalPages - 1;
    }
    if (_currentPage < 0) {
      _currentPage = 0;
    }

    final startIndex = _currentPage * _tagsPerPage;
    final endIndex = startIndex + _tagsPerPage;

    if (startIndex < _filteredTags.length) {
      _currentPageTags = _filteredTags.sublist(startIndex,
          endIndex > _filteredTags.length ? _filteredTags.length : endIndex);
    } else {
      _currentPageTags = [];
    }

    debugPrint(
        'TagManagementScreen: Pagination - _filteredTags: ${_filteredTags.length}, _tagsPerPage: $_tagsPerPage, _totalPages: $_totalPages, _currentPage: $_currentPage, _currentPageTags: ${_currentPageTags.length}');
  }

  void _goToPage(int page) {
    if (page >= 0 && page < _totalPages) {
      setState(() {
        _currentPage = page;
        _updatePagination();
      });
    }
  }

  void _nextPage() {
    _goToPage(_currentPage + 1);
  }

  void _previousPage() {
    _goToPage(_currentPage - 1);
  }

  void _changeSortCriteria(String criteria) {
    setState(() {
      if (_sortCriteria == criteria) {
        _sortAscending = !_sortAscending;
      } else {
        _sortCriteria = criteria;
        _sortAscending = true;
      }

      _sortTags();
      _updatePagination();
    });
  }

  Future<void> _directTagSearch(String tag) async {
    try {
      final tabManagerBloc = BlocProvider.of<TabManagerBloc>(context);
      final tagSearchPath = UriUtils.buildTagSearchPath(tag);

      final existingTab = tabManagerBloc.state.tabs.firstWhere(
        (tab) => tab.path == tagSearchPath,
        orElse: () => TabData(id: '', name: '', path: ''),
      );

      if (existingTab.id.isNotEmpty) {
        tabManagerBloc.add(SwitchToTab(existingTab.id));
      } else {
        tabManagerBloc.add(
          AddTab(
            path: tagSearchPath,
            name: 'Tag: $tag',
            switchToTab: true,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error opening tag in new tab: $e');
    }
  }

  /// Select a tag (click to select, similar to file/folder selection)
  /// This highlights the tag and shows it as selected
  void _selectTag(String tag) {
    setState(() {
      if (_isCtrlPressed) {
        // Ctrl + Click: toggle selection (add/remove from multi-select)
        if (_selectedTags.contains(tag)) {
          _selectedTags.remove(tag);
          _isMultiSelectMode = _selectedTags.isNotEmpty;
        } else {
          _selectedTags.add(tag);
          _isMultiSelectMode = _selectedTags.isNotEmpty;
        }
        // Update focused tag for future Shift+Click
        _focusedTag = tag;
      } else if (_isShiftPressed && _focusedTag != null) {
        // Shift + Click: select range from focused tag to clicked tag
        final startIndex = _currentPageTags.indexOf(_focusedTag!);
        final endIndex = _currentPageTags.indexOf(tag);
        if (startIndex != -1 && endIndex != -1) {
          final start = startIndex < endIndex ? startIndex : endIndex;
          final end = startIndex < endIndex ? endIndex : startIndex;
          for (int i = start; i <= end; i++) {
            _selectedTags.add(_currentPageTags[i]);
          }
          _isMultiSelectMode = true;
        }
      } else {
        // Normal click: select single tag (toggle) and enter multi-select mode
        if (_focusedTag == tag) {
          // Already focused, enter multi-select mode with this tag selected
          _focusedTag = null;
          _selectedTags.clear();
        } else {
          // First click on this tag - enter multi-select mode
          _focusedTag = tag;
          _selectedTags.clear();
          _selectedTags.add(tag);
          _isMultiSelectMode = true;
        }
      }
    });
  }

  /// Register tag item position for rectangle selection
  void _registerTagPosition(String tag, Rect position) {
    _tagItemPositions[tag] = position;
  }

  /// Clear all registered tag positions
  void _clearTagPositions() {
    _tagItemPositions.clear();
  }

  /// Start drag selection with rectangle (like Windows Explorer)
  void _startRectDragSelection(Offset position) {
    if (_isDraggingRect) return;
    setState(() {
      _isDraggingRect = true;
      _dragStartPosition = position;
      _dragCurrentPosition = position;
      _selectedTags.clear();
      _isMultiSelectMode = true;
    });
  }

  /// Update drag selection rectangle
  void _updateRectDragSelection(Offset position) {
    if (!_isDraggingRect) return;
    setState(() {
      _dragCurrentPosition = position;
      _selectTagsInRect();
    });
  }

  /// End drag selection
  void _endRectDragSelection() {
    setState(() {
      _isDraggingRect = false;
      _dragStartPosition = null;
      _dragCurrentPosition = null;
    });
  }

  /// Select all tags that intersect with the selection rectangle
  void _selectTagsInRect() {
    if (_dragStartPosition == null || _dragCurrentPosition == null) return;

    final selectionRect =
        Rect.fromPoints(_dragStartPosition!, _dragCurrentPosition!);

    // Check which tags intersect with the selection rectangle
    final Set<String> newlySelected = {};
    _tagItemPositions.forEach((tag, itemRect) {
      if (selectionRect.overlaps(itemRect)) {
        newlySelected.add(tag);
      }
    });

    // Get keyboard state for Ctrl/Shift
    final keyboard = HardwareKeyboard.instance;
    final bool isCtrlPressed = keyboard.isControlPressed;
    final bool isShiftPressed = keyboard.isShiftPressed;

    setState(() {
      if (isCtrlPressed) {
        // Ctrl: add to existing selection
        _selectedTags.addAll(newlySelected);
      } else if (isShiftPressed && _focusedTag != null) {
        // Shift: extend from focused tag
        _selectedTags.addAll(newlySelected);
      } else {
        // Normal: replace selection
        _selectedTags.clear();
        _selectedTags.addAll(newlySelected);
      }
      _isMultiSelectMode = _selectedTags.isNotEmpty;
    });
  }

  /// Build the selection rectangle overlay
  Widget _buildSelectionOverlay() {
    if (!_isDraggingRect ||
        _dragStartPosition == null ||
        _dragCurrentPosition == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final selectionRect =
        Rect.fromPoints(_dragStartPosition!, _dragCurrentPosition!);

    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: SelectionRectanglePainter(
            selectionRect: selectionRect,
            fillColor:
                theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderColor: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }

  /// Open tag (double click or button) to show files with this tag
  Future<void> _openTag(String tag) async {
    // First load files for this tag
    setState(() {
      _selectedTagForFiles = tag;
      _isLoading = true;
    });

    try {
      final files = await TagManager.findFilesByTagGlobally(tag);
      final filesData = files.map((file) => {'path': file.path}).toList();

      if (mounted) {
        setState(() {
          _filesBySelectedTag = filesData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading files for tag: $e');
      if (mounted) {
        setState(() {
          _filesBySelectedTag = [];
          _isLoading = false;
        });
      }
    }
  }

  void _clearTagSelection() {
    setState(() {
      _selectedTagForFiles = null;
      _filesBySelectedTag = [];
    });
  }

  Future<void> _confirmDeleteTag(String tag) async {
    final theme = Theme.of(context);
    final AppLocalizations localizations = AppLocalizations.of(context)!;
    final bool result = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.deleteTagConfirmation(tag)),
        content: Text(localizations.tagDeleteConfirmationText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              localizations.delete,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteTag(tag);
    }
  }

  Future<void> _deleteTag(String tag) async {
    final AppLocalizations localizations = AppLocalizations.of(context)!;
    final operation = locator<OperationProgressController>();
    final operationId = operation.begin(
      title: localizations.deleteTag,
      total: 1,
      detail: tag,
      isIndeterminate: true,
      showModal: true,
    );

    setState(() {
      _isLoading = true;
    });

    try {
      _standaloneCreatedTags.remove(tag);
      await TagManager.deleteTagGlobally(tag);
      await _loadAllTags();

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(localizations.tagDeleted(tag))),
        );
      }

      await _tagColorManager.removeTagColor(tag);

      if (_selectedTagForFiles == tag) {
        _clearTagSelection();
      }
      operation.succeed(
        operationId,
        detail: localizations.tagDeleted(tag),
      );
    } catch (e) {
      operation.fail(
        operationId,
        detail: localizations.errorDeletingTag(e.toString()),
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(localizations.errorDeletingTag(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Start inline rename for desktop
  void _startTagRename(String tag) {
    debugPrint('[TAG_RENAME] _startTagRename called with tag="$tag"');
    setState(() {
      _editingTag = tag;
      _editingTagController = TextEditingController(text: tag);
    });
  }

  /// Commit tag rename
  Future<void> _commitTagRename(String oldTag) async {
    debugPrint(
        '[TAG_RENAME] _commitTagRename called with oldTag="$oldTag", _editingTag=$_editingTag, controller=${_editingTagController != null ? "exists" : "null"}');
    if (_editingTagController == null || _editingTag == null) {
      debugPrint('[TAG_RENAME] EARLY RETURN: controller or editingTag is null');
      return;
    }

    final newTag = _editingTagController!.text.trim();
    debugPrint('[TAG_RENAME] newTag="$newTag", oldTag="$oldTag"');

    // Clear editing state FIRST to prevent the next tag at the same index
    // from entering edit mode when the list rebuilds after rename.
    _editingTag = null;
    final controller = _editingTagController;
    _editingTagController = null;
    setState(() {});
    controller?.dispose();

    if (newTag.isEmpty || newTag == oldTag) {
      debugPrint('[TAG_RENAME] No change or empty, skipping rename');
      return;
    }

    final localizations = AppLocalizations.of(context)!;

    // Check if tag already exists
    final allTagsLowercase = _allTags.map((t) => t.toLowerCase()).toSet();
    if (allTagsLowercase.contains(newTag.toLowerCase())) {
      debugPrint('[TAG_RENAME] Tag already exists: $newTag');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(localizations.tagAlreadyExists(newTag))),
        );
      }
      return;
    }

    debugPrint('[TAG_RENAME] Proceeding with rename: "$oldTag" -> "$newTag"');
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await TagManager.renameTag(oldTag, newTag);
      debugPrint('[TAG_RENAME] TagManager.renameTag returned: $success');
      if (success) {
        // Rename the color as well
        final oldColor = TagColorManager.instance.getTagColor(oldTag);
        await TagColorManager.instance.setTagColor(newTag, oldColor);
        await TagColorManager.instance.removeTagColor(oldTag);

        await _loadAllTags();

        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(localizations.tagRenamed(oldTag, newTag))),
          );
        }
      } else {
        debugPrint('[TAG_RENAME] TagManager.renameTag FAILED');
      }
    } catch (e) {
      debugPrint('[TAG_RENAME] EXCEPTION: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Cancel tag rename
  void _cancelTagRename() {
    final oldController = _editingTagController;
    setState(() {
      _editingTag = null;
      _editingTagController = null;
    });
    oldController?.dispose();
  }

  // ── Multi-selection methods ──

  void _enterMultiSelectMode(String tag) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedTags.add(tag);
    });
  }

  void _exitMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedTags.clear();
    });
  }

  void _toggleTagSelection(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
        if (_selectedTags.isEmpty) {
          _isMultiSelectMode = false;
        }
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  void _selectAllFilteredTags() {
    setState(() {
      _selectedTags.addAll(_filteredTags);
      _isMultiSelectMode = true;
    });
  }

  void _deselectAllTags() {
    setState(() {
      _selectedTags.clear();
      _isMultiSelectMode = false;
    });
  }

  bool get _allFilteredSelected =>
      _filteredTags.isNotEmpty &&
      _filteredTags.every((t) => _selectedTags.contains(t));

  bool get _someSelected => _selectedTags.isNotEmpty && !_allFilteredSelected;

  Future<void> _confirmBulkDeleteTags() async {
    if (_selectedTags.isEmpty) return;
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final count = _selectedTags.length;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(localizations.bulkDeleteConfirmationTitle()),
        content: Text(localizations.bulkDeleteConfirmationText(count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              localizations.delete,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      await _bulkDeleteTags();
    }
  }

  Future<void> _bulkDeleteTags() async {
    final localizations = AppLocalizations.of(context)!;
    final tagsToDelete = Set<String>.from(_selectedTags);
    final count = tagsToDelete.length;
    final operation = locator<OperationProgressController>();
    final operationId = operation.begin(
      title: localizations.deleteTag,
      total: count,
      detail: count > 0 ? tagsToDelete.first : null,
      showModal: true,
    );

    setState(() => _isLoading = true);

    try {
      int completed = 0;
      for (final tag in tagsToDelete) {
        _standaloneCreatedTags.remove(tag);
        await TagManager.deleteTagGlobally(tag);
        await _tagColorManager.removeTagColor(tag);
        completed++;
        operation.update(
          operationId,
          completed: completed,
          detail: tag,
        );
      }

      _selectedTags.clear();
      _isMultiSelectMode = false;
      await _loadAllTags();

      operation.succeed(
        operationId,
        detail: localizations.bulkDeleteSuccess(count),
      );

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(localizations.bulkDeleteSuccess(count))),
        );
      }

      if (_selectedTagForFiles != null &&
          tagsToDelete.contains(_selectedTagForFiles)) {
        _clearTagSelection();
      }
    } catch (e) {
      operation.fail(
        operationId,
        detail: localizations.errorDeletingTag(e.toString()),
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(localizations.errorDeletingTag(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildBulkActionBar() {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;
    final isMobile = !_isDesktop;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isMobile ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: isMobile
            // Mobile: stack vertically for narrow screens
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localizations.tagsSelected(_selectedTags.length),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!_allFilteredSelected)
                        OutlinedButton.icon(
                          onPressed: _selectAllFilteredTags,
                          icon: const Icon(PhosphorIconsLight.checkSquare,
                              size: 18),
                          label: Text(localizations.selectAllTags),
                        ),
                      OutlinedButton.icon(
                        onPressed: _deselectAllTags,
                        icon: const Icon(PhosphorIconsLight.x, size: 18),
                        label: Text(localizations.deselectAllTags),
                      ),
                      FilledButton.icon(
                        onPressed: _confirmBulkDeleteTags,
                        icon: const Icon(PhosphorIconsLight.trash, size: 18),
                        label: Text(localizations.deleteSelected),
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            // Desktop: single row
            : Row(
                children: [
                  Text(
                    localizations.tagsSelected(_selectedTags.length),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  if (!_allFilteredSelected)
                    TextButton.icon(
                      onPressed: _selectAllFilteredTags,
                      icon:
                          const Icon(PhosphorIconsLight.checkSquare, size: 18),
                      label: Text(localizations.selectAllTags),
                    ),
                  if (!_allFilteredSelected) const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _deselectAllTags,
                    icon: const Icon(PhosphorIconsLight.x, size: 18),
                    label: Text(localizations.deselectAllTags),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _confirmBulkDeleteTags,
                    icon: const Icon(PhosphorIconsLight.trash, size: 18),
                    label: Text(localizations.deleteSelected),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Show rename dialog for mobile
  Future<void> _showRenameDialog(String tag) async {
    final localizations = AppLocalizations.of(context)!;

    final newTag = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final controller = TextEditingController(text: tag);
        return AlertDialog(
          title: Text(localizations.renameTag),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: localizations.tagName,
              hintText: localizations.enterNewTagName,
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(localizations.rename),
            ),
          ],
        );
      },
    );

    if (newTag != null && newTag.isNotEmpty && newTag != tag) {
      final allTagsLowercase = _allTags.map((t) => t.toLowerCase()).toSet();
      if (allTagsLowercase.contains(newTag.toLowerCase())) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(localizations.tagAlreadyExists(newTag))),
          );
        }
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        final success = await TagManager.renameTag(tag, newTag);
        if (success) {
          // Rename the color as well
          final oldColor = TagColorManager.instance.getTagColor(tag);
          await TagColorManager.instance.setTagColor(newTag, oldColor);
          await TagColorManager.instance.removeTagColor(tag);

          await _loadAllTags();

          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text(localizations.tagRenamed(tag, newTag))),
            );
          }
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _showColorPickerDialog(String tag) {
    final AppLocalizations localizations = AppLocalizations.of(context)!;
    Color currentColor = _tagColorManager.getTagColor(tag);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(localizations.chooseTagColor(tag)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: TagChip(
                    tag: tag,
                    customColor: currentColor,
                  ),
                ),
                ColorPicker(
                  pickerColor: currentColor,
                  onColorChanged: (color) {
                    currentColor = color;
                  },
                  pickerAreaHeightPercent: 0.8,
                  enableAlpha: false,
                  displayThumbColor: true,
                  labelTypes: const [ColorLabelType.rgb, ColorLabelType.hsv],
                  pickerAreaBorderRadius:
                      const BorderRadius.all(Radius.circular(12)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                RouteUtils.safePopDialog(context);
              },
              child: Text(localizations.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                await _tagColorManager.setTagColor(tag, currentColor);
                if (mounted) {
                  setState(() {});
                  RouteUtils.safePopDialog(context);

                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    SnackBar(
                      content: Text(localizations.tagColorUpdated(tag)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Text(localizations.save),
            ),
          ],
        );
      },
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;
    final bool showingTaggedFiles = _selectedTagForFiles != null;

    Widget body;
    if (_isInitialLoading) {
      // Show skeleton while loading tags for the first time
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Skeleton(
          type: SkeletonType.list,
          itemCount: 8,
        ),
      );
    } else if (showingTaggedFiles) {
      body = _buildFilesByTagList();
    } else {
      body = _buildTagsList();
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header bar aligned with the mobile file management layout.
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(PhosphorIconsLight.arrowLeft),
                  onPressed: showingTaggedFiles
                      ? _clearTagSelection
                      : () => _handleBack(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _isSearching && !showingTaggedFiles
                      ? TextField(
                          controller: _searchController,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          style: TextStyle(color: theme.colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: localizations.searchTagsHint,
                            hintStyle: TextStyle(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.5)),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        )
                      : showingTaggedFiles
                          ? _buildTaggedFilesHeaderTitle(theme, localizations)
                          : Text(
                              localizations.tagManagementTitle,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w500),
                            ),
                ),
                if (!showingTaggedFiles || !_isMobile) ...[
                  IconButton(
                    icon: const Icon(PhosphorIconsLight.arrowsClockwise),
                    onPressed: _isLoading
                        ? null
                        : showingTaggedFiles
                            ? _refreshSelectedTagFiles
                            : () async {
                                setState(() => _isLoading = true);
                                await _loadAllTags();
                                if (mounted) setState(() => _isLoading = false);
                              },
                    tooltip: localizations.refresh,
                  ),
                ],
                if (!showingTaggedFiles)
                  IconButton(
                    icon: Icon(_isSearching
                        ? PhosphorIconsLight.x
                        : PhosphorIconsLight.magnifyingGlass),
                    onPressed: _toggleSearch,
                    tooltip: localizations.searchTags,
                  ),
              ],
            ),
          ),
          if (showingTaggedFiles && _isMobile) _buildMobileTaggedFilesToolbar(),
          Expanded(child: body),
        ],
      ),
      floatingActionButton: _selectedTagForFiles == null
          ? FloatingActionButton(
              heroTag: null,
              onPressed: _showCreateTagDialog,
              backgroundColor: theme.colorScheme.primary,
              tooltip: localizations.newTagTooltip,
              child: Icon(
                PhosphorIconsLight.plus,
                color: theme.colorScheme.onPrimary,
                size: 24,
              ),
            )
          : null,
    );
  }

  Widget _buildTaggedFilesHeaderTitle(
    ThemeData theme,
    AppLocalizations localizations,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedTagForFiles ?? localizations.tagManagementTitle,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          '${_filesBySelectedTag.length} ${localizations.filesWithTagCount}',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildMobileTaggedFilesToolbar() {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
            tooltip: localizations.backToAllTags,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: _clearTagSelection,
          ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.folderSimple, size: 20),
            tooltip: localizations.openInNewTab,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: _selectedTagForFiles == null
                ? null
                : () => _directTagSearch(_selectedTagForFiles!),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.palette, size: 20),
            tooltip: localizations.changeColor,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: _selectedTagForFiles == null
                ? null
                : () => _showColorPickerDialog(_selectedTagForFiles!),
          ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.arrowsClockwise, size: 20),
            tooltip: localizations.refresh,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: _isLoading ? null : _refreshSelectedTagFiles,
          ),
          IconButton(
            icon: const Icon(PhosphorIconsLight.dotsThreeVertical, size: 20),
            tooltip: localizations.moreOptions,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: _showTaggedFilesMoreOptions,
          ),
        ],
      ),
    );
  }

  void _showTaggedFilesMoreOptions() {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _selectedTagForFiles ?? localizations.moreOptions,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(PhosphorIconsLight.folderSimple),
              title: Text(localizations.openInNewTab),
              onTap: _selectedTagForFiles == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      _directTagSearch(_selectedTagForFiles!);
                    },
            ),
            ListTile(
              leading: const Icon(PhosphorIconsLight.palette),
              title: Text(localizations.changeColor),
              onTap: _selectedTagForFiles == null
                  ? null
                  : () {
                      Navigator.pop(context);
                      _showColorPickerDialog(_selectedTagForFiles!);
                    },
            ),
            ListTile(
              leading: const Icon(PhosphorIconsLight.arrowsClockwise),
              title: Text(localizations.refresh),
              onTap: () {
                Navigator.pop(context);
                _refreshSelectedTagFiles();
              },
            ),
            ListTile(
              leading: const Icon(PhosphorIconsLight.arrowLeft),
              title: Text(localizations.backToAllTags),
              onTap: () {
                Navigator.pop(context);
                _clearTagSelection();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshSelectedTagFiles() async {
    final selectedTag = _selectedTagForFiles;
    if (selectedTag == null) {
      return;
    }

    await _openTag(selectedTag);
  }

  /// Handle back navigation - close tab or pop navigator
  void _handleBack(BuildContext context) {
    // Try to get TabManagerBloc
    TabManagerBloc? tabBloc;
    try {
      tabBloc = context.read<TabManagerBloc>();
    } catch (_) {
      tabBloc = null;
    }

    if (tabBloc != null) {
      final activeTab = tabBloc.state.activeTab;
      if (activeTab != null) {
        // Close the tags tab
        tabBloc.add(CloseTab(activeTab.id));
        return;
      }
    }

    // Fallback to navigator pop
    Navigator.of(context).pop();
  }

  void _showTagOptions(String tag) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(PhosphorIconsLight.folder),
                title: Text(AppLocalizations.of(context)!.viewFilesWithTag),
                onTap: () {
                  Navigator.pop(context);
                  _directTagSearch(tag);
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.pencilSimple),
                title: Text(AppLocalizations.of(context)!.renameTag),
                onTap: () {
                  Navigator.pop(context);
                  if (_isDesktop) {
                    _startTagRename(tag);
                  } else {
                    _showRenameDialog(tag);
                  }
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.palette),
                title: Text(AppLocalizations.of(context)!.changeTagColor),
                onTap: () {
                  Navigator.pop(context);
                  _showColorPickerDialog(tag);
                },
              ),
              if (widget.onTagSelected == null)
                ListTile(
                  leading: const Icon(PhosphorIconsLight.appWindow),
                  title: Text(AppLocalizations.of(context)!.openInNewTab),
                  onTap: () {
                    Navigator.pop(context);
                    _directTagSearch(tag);
                  },
                ),
              ListTile(
                leading: Icon(PhosphorIconsLight.trash,
                    color: theme.colorScheme.error),
                title: Text(AppLocalizations.of(context)!.deleteTag,
                    style: TextStyle(color: theme.colorScheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteTag(tag);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show context menu for multi-selected tags (right-click on PC)
  /// Reuses the same pattern as shared_file_context_menu.dart
  void _showMultiSelectContextMenu(Offset globalPosition) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    );

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(PhosphorIconsLight.trash,
                  size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Text(
                l10n.deleteSelected,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'delete') {
        _confirmBulkDeleteTags();
      }
    });
  }

  Widget _buildTagsList() {
    final theme = Theme.of(context);

    if (_allTags.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsLight.tag,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.noTagsFoundMessage,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noTagsFoundDescription,
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showCreateTagDialog,
              icon: const Icon(PhosphorIconsLight.plus),
              label: Text(AppLocalizations.of(context)!.createNewTagButton),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    if (_filteredTags.isEmpty && _searchController.text.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsLight.magnifyingGlass,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!
                  .noMatchingTagsMessage(_searchController.text),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
              },
              icon: const Icon(PhosphorIconsLight.x, size: 20),
              label: Text(AppLocalizations.of(context)!.clearSearch),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    final localizations = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with tag count and controls
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              // Select all checkbox with label - larger tap target
              InkWell(
                onTap: () {
                  if (_allFilteredSelected) {
                    _deselectAllTags();
                  } else {
                    _selectAllFilteredTags();
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SoftCheckbox(
                        value: _allFilteredSelected
                            ? true
                            : _someSelected
                                ? null
                                : false,
                        tristate: true,
                        onChanged: (_) {
                          if (_allFilteredSelected) {
                            _deselectAllTags();
                          } else {
                            _selectAllFilteredTags();
                          }
                        },
                        size: 24,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _allFilteredSelected
                            ? localizations.deselectAllTags
                            : localizations.selectAllTags,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(PhosphorIconsLight.tag,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: _isMultiSelectMode
                    ? Text(
                        localizations.tagsSelected(_selectedTags.length),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : Text(
                        '${_filteredTags.length} ${localizations.tagsCreated}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              if (_isMultiSelectMode) ...[
                IconButton(
                  icon: const Icon(PhosphorIconsLight.trash, size: 20),
                  onPressed:
                      _selectedTags.isNotEmpty ? _confirmBulkDeleteTags : null,
                  tooltip: localizations.deleteSelected,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsLight.x, size: 20),
                  onPressed: _deselectAllTags,
                  tooltip: localizations.deselectAllTags,
                  visualDensity: VisualDensity.compact,
                ),
              ],
              if (!_isMultiSelectMode && screenWidth > 600) ...[
                PopupMenuButton<String>(
                  tooltip: localizations.sortTags,
                  onSelected: _changeSortCriteria,
                  icon: Icon(PhosphorIconsLight.sortAscending,
                      size: 20, color: theme.colorScheme.onSurfaceVariant),
                  itemBuilder: (context) => [
                    _buildSortMenuItem('name', PhosphorIconsLight.sortAscending,
                        localizations.sortByAlphabet),
                    _buildSortMenuItem(
                        'popularity',
                        PhosphorIconsLight.chartBar,
                        localizations.sortByPopular),
                    _buildSortMenuItem(
                        'recent',
                        PhosphorIconsLight.clockCounterClockwise,
                        localizations.sortByRecent),
                  ],
                ),
                IconButton(
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                  icon: Icon(
                    _isGridView
                        ? PhosphorIconsLight.listBullets
                        : PhosphorIconsLight.squaresFour,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  tooltip: _isGridView
                      ? localizations.listViewMode
                      : localizations.gridViewMode,
                ),
              ],
            ],
          ),
        ),

        // Tags list or grid
        Expanded(
          child: _isGridView ? _buildTagsGridView() : _buildTagsListView(),
        ),

        // Bottom pagination controls
        if (_totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(PhosphorIconsLight.skipBack),
                  iconSize: 20,
                  onPressed: _currentPage > 0 ? () => _goToPage(0) : null,
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsLight.caretLeft),
                  iconSize: 20,
                  onPressed: _currentPage > 0 ? _previousPage : null,
                ),
                ..._buildPageIndicators(),
                IconButton(
                  icon: const Icon(PhosphorIconsLight.caretRight),
                  iconSize: 20,
                  onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
                ),
                IconButton(
                  icon: const Icon(PhosphorIconsLight.skipForward),
                  iconSize: 20,
                  onPressed: _currentPage < _totalPages - 1
                      ? () => _goToPage(_totalPages - 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(
      String value, IconData icon, String label) {
    final theme = Theme.of(context);
    final isActive = _sortCriteria == value;
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 18, color: isActive ? theme.colorScheme.primary : null),
          const SizedBox(width: 12),
          Text(label),
          if (isActive)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(
                _sortAscending
                    ? PhosphorIconsLight.arrowUp
                    : PhosphorIconsLight.arrowDown,
                size: 16,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildPageIndicators() {
    final theme = Theme.of(context);
    List<Widget> indicators = [];

    int startPage = _currentPage - 2;
    int endPage = _currentPage + 2;

    if (startPage < 0) {
      endPage -= startPage;
      startPage = 0;
    }

    if (endPage >= _totalPages) {
      startPage =
          (startPage - (endPage - _totalPages + 1)).clamp(0, _totalPages - 1);
      endPage = _totalPages - 1;
    }

    if (startPage > 0) {
      indicators.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text('...',
            style: TextStyle(
                fontSize: 16, color: theme.colorScheme.onSurfaceVariant)),
      ));
    }

    for (int i = startPage; i <= endPage; i++) {
      indicators.add(
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: () => _goToPage(i),
            borderRadius: BorderRadius.circular(16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: i == _currentPage
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16.0),
              ),
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      i == _currentPage ? FontWeight.w600 : FontWeight.normal,
                  color: i == _currentPage
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (endPage < _totalPages - 1) {
      indicators.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text('...',
            style: TextStyle(
                fontSize: 16, color: theme.colorScheme.onSurfaceVariant)),
      ));
    }

    return indicators;
  }

  /// Build a single tag list tile with proper widget key for position tracking
  Widget _buildTagListTile(String tag, int index, Color tagColor,
      bool isEditing, bool isSelected, bool isFocused) {
    final theme = Theme.of(context);
    final isDesktop = _isDesktop;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Register this item's position after layout
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final RenderBox? renderBox =
                context.findRenderObject() as RenderBox?;
            if (renderBox != null && renderBox.hasSize) {
              final position = renderBox.localToGlobal(Offset.zero);
              final size = renderBox.size;
              _registerTagPosition(
                  tag,
                  Rect.fromLTWH(
                      position.dx, position.dy, size.width, size.height));
            }
          }
        });

        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
            side: isEditing
                ? BorderSide(color: theme.colorScheme.primary, width: 2)
                : isSelected || isFocused
                    ? BorderSide(
                        color: theme.colorScheme.primary.withValues(alpha: 0.5),
                        width: 1.5)
                    : BorderSide.none,
          ),
          tileColor: isSelected || isFocused
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : tagColor.withValues(alpha: 0.08),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: tagColor, shape: BoxShape.circle),
              ),
            ],
          ),
          title: isEditing && _editingTagController != null
              ? TextField(
                  controller: _editingTagController,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: theme.colorScheme.primary, width: 2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: theme.colorScheme.primary, width: 2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: theme.colorScheme.primary, width: 2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                  ),
                  cursorColor: theme.colorScheme.primary,
                  onSubmitted: (_) => _commitTagRename(tag),
                  onTapOutside: (_) => _commitTagRename(tag),
                )
              : GestureDetector(
                  onDoubleTap: _isMultiSelectMode ? null : () => _openTag(tag),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDesktop && !_isMultiSelectMode) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message:
                              AppLocalizations.of(context)!.doubleClickToRename,
                          child: Icon(PhosphorIconsLight.pencilSimple,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.5)),
                        ),
                      ],
                    ],
                  ),
                ),
          onTap: isEditing
              ? null
              : _isMultiSelectMode
                  ? () => _toggleTagSelection(tag)
                  : () {
                      if (_isDesktop) {
                        _selectTag(tag);
                      } else {
                        // On mobile, tap directly opens the tag
                        _directTagSearch(tag);
                      }
                    },
          onLongPress: isEditing
              ? null
              : _isMultiSelectMode
                  ? () => _showTagOptions(tag)
                  : () => _enterMultiSelectMode(tag),
          trailing: _isMultiSelectMode
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(PhosphorIconsLight.pencilSimple,
                          size: 20,
                          color: isEditing
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3)
                              : theme.colorScheme.onSurfaceVariant),
                      onPressed: isEditing
                          ? null
                          : () {
                              if (isDesktop) {
                                _startTagRename(tag);
                              } else {
                                _showRenameDialog(tag);
                              }
                            },
                      tooltip: AppLocalizations.of(context)!.renameTag,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(PhosphorIconsLight.folder,
                          size: 20,
                          color: isEditing
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3)
                              : theme.colorScheme.primary),
                      onPressed: isEditing ? null : () => _directTagSearch(tag),
                      tooltip: AppLocalizations.of(context)!.viewFilesWithTag,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(PhosphorIconsLight.palette,
                          size: 20,
                          color: isEditing
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3)
                              : theme.colorScheme.onSurfaceVariant),
                      onPressed:
                          isEditing ? null : () => _showColorPickerDialog(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(PhosphorIconsLight.trash,
                          size: 20,
                          color: isEditing
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.3)
                              : theme.colorScheme.error.withValues(alpha: 0.7)),
                      onPressed:
                          isEditing ? null : () => _confirmDeleteTag(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTagsListView() {
    final isDesktop = _isDesktop;

    // Clear tag positions when building the list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearTagPositions();
    });

    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            // Tap to deselect when not in edit mode
            if (_editingTag == null && _isMultiSelectMode) {
              _deselectAllTags();
            }
          },
          onSecondaryTapUp: (details) {
            // Right-click to show context menu for selected tags (like file/folder)
            if (_selectedTags.isNotEmpty) {
              _showMultiSelectContextMenu(details.globalPosition);
            }
          },
          // Drag selection - only on desktop, and not when editing
          onPanStart: isDesktop
              ? (details) {
                  // Don't start drag selection if user is editing text (inline rename)
                  final focused = FocusManager.instance.primaryFocus;
                  final focusedContext = focused?.context;
                  if (focusedContext != null) {
                    final isEditableText =
                        focusedContext.widget is EditableText ||
                            focusedContext.findAncestorWidgetOfExactType<
                                    EditableText>() !=
                                null;
                    if (isEditableText) {
                      return; // Don't start drag selection
                    }
                  }
                  _startRectDragSelection(details.localPosition);
                }
              : null,
          onPanUpdate: isDesktop
              ? (details) {
                  _updateRectDragSelection(details.localPosition);
                }
              : null,
          onPanEnd: isDesktop
              ? (details) {
                  _endRectDragSelection();
                }
              : null,
          behavior: HitTestBehavior.translucent,
          child: ListView.separated(
            padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: _isMultiSelectMode ? 80 : 8),
            itemCount: _currentPageTags.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final tag = _currentPageTags[index];
              final tagColor = TagColorManager.instance.getTagColor(tag);
              final isEditing = _editingTag == tag && isDesktop;
              final isSelected = _selectedTags.contains(tag);
              final isFocused = _focusedTag == tag;

              return _buildTagListTile(
                  tag, index, tagColor, isEditing, isSelected, isFocused);
            },
          ),
        ),
        // Selection rectangle overlay
        _buildSelectionOverlay(),
      ],
    );
  }

  Widget _buildTagsGridView() {
    final theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = _isDesktop;

    // Larger grid for desktop
    final crossAxisCount = isDesktop
        ? (screenWidth / 200).floor().clamp(4, 10)
        : screenWidth > 1200
            ? 8
            : screenWidth > 900
                ? 6
                : screenWidth > 600
                    ? 5
                    : 3;

    // Larger fonts and spacing for desktop
    final fontSize = isDesktop ? 14.0 : 12.0;
    final iconSize = isDesktop ? 20.0 : 16.0;
    final spacing = isDesktop ? 8.0 : 4.0;

    // Clear tag positions when building the grid
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearTagPositions();
    });

    // GridView with drag selection support (same as ListView)
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            // Tap to deselect when not in edit mode
            if (_editingTag == null && _isMultiSelectMode) {
              _deselectAllTags();
            }
          },
          onSecondaryTapUp: (details) {
            // Right-click to show context menu for selected tags (like file/folder)
            if (_selectedTags.isNotEmpty) {
              _showMultiSelectContextMenu(details.globalPosition);
            }
          },
          // Drag selection - only on desktop
          onPanStart: isDesktop
              ? (details) {
                  // Don't start drag selection if user is editing text (inline rename)
                  final focused = FocusManager.instance.primaryFocus;
                  final focusedContext = focused?.context;
                  if (focusedContext != null) {
                    final isEditableText =
                        focusedContext.widget is EditableText ||
                            focusedContext.findAncestorWidgetOfExactType<
                                    EditableText>() !=
                                null;
                    if (isEditableText) {
                      return; // Don't start drag selection
                    }
                  }
                  _startRectDragSelection(details.localPosition);
                }
              : null,
          onPanUpdate: isDesktop
              ? (details) {
                  _updateRectDragSelection(details.localPosition);
                }
              : null,
          onPanEnd: isDesktop
              ? (details) {
                  _endRectDragSelection();
                }
              : null,
          behavior: HitTestBehavior.translucent,
          child: GridView.builder(
            padding: EdgeInsets.only(
              left: isDesktop ? 16 : 12,
              right: isDesktop ? 16 : 12,
              top: isDesktop ? 16 : 12,
              bottom: _isMultiSelectMode ? 80 : (isDesktop ? 16 : 12),
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: isDesktop ? 1.8 : 1.6,
              crossAxisSpacing: isDesktop ? 12 : 8,
              mainAxisSpacing: isDesktop ? 12 : 8,
            ),
            itemCount: _currentPageTags.length,
            itemBuilder: (context, index) {
              final tag = _currentPageTags[index];
              final tagColor = TagColorManager.instance.getTagColor(tag);
              final isEditing = _editingTag == tag;
              final isSelected = _selectedTags.contains(tag);
              final isFocused = _focusedTag == tag;

              return LayoutBuilder(
                builder: (context, constraints) {
                  // Register this item's position after layout for drag selection
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      final RenderBox? renderBox =
                          context.findRenderObject() as RenderBox?;
                      if (renderBox != null && renderBox.hasSize) {
                        final position = renderBox.localToGlobal(Offset.zero);
                        final size = renderBox.size;
                        _registerTagPosition(
                            tag,
                            Rect.fromLTWH(position.dx, position.dy, size.width,
                                size.height));
                      }
                    }
                  });

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16.0),
                      onTap: isEditing
                          ? null
                          : _isMultiSelectMode
                              ? () => _toggleTagSelection(tag)
                              : () {
                                  if (_isDesktop) {
                                    _selectTag(tag);
                                  } else {
                                    // On mobile, tap directly opens the tag
                                    _directTagSearch(tag);
                                  }
                                },
                      onLongPress: isEditing
                          ? null
                          : _isMultiSelectMode
                              ? () => _showTagOptions(tag)
                              : () => _enterMultiSelectMode(tag),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected || isFocused
                              ? theme.colorScheme.primary
                                  .withValues(alpha: 0.15)
                              : tagColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16.0),
                          border: isEditing
                              ? Border.all(
                                  color: theme.colorScheme.primary, width: 2)
                              : isSelected || isFocused
                                  ? Border.all(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: 0.5),
                                      width: 1.5)
                                  : null,
                        ),
                        child: Column(
                          children: [
                            // Top area: color dot only (no checkbox)
                            Expanded(
                              child: Center(
                                child: Container(
                                  width: isDesktop ? 32 : 24,
                                  height: isDesktop ? 32 : 24,
                                  decoration: BoxDecoration(
                                      color: tagColor, shape: BoxShape.circle),
                                ),
                              ),
                            ),
                            // Bottom area: tag name + action buttons
                            Padding(
                              padding: EdgeInsets.only(
                                top: spacing,
                                left: isDesktop ? 8 : 6,
                                right: isDesktop ? 8 : 6,
                                bottom: isDesktop ? 8 : 6,
                              ),
                              child: Column(
                                children: [
                                  // Tag name or rename TextField
                                  if (isEditing &&
                                      _editingTagController != null)
                                    SizedBox(
                                      width: double.infinity,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Opacity(
                                            opacity: 0,
                                            child: Text(
                                              tag,
                                              style: TextStyle(
                                                  fontSize: fontSize,
                                                  fontWeight: FontWeight.w600),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Positioned.fill(
                                            child: TextField(
                                              controller: _editingTagController,
                                              autofocus: true,
                                              style: TextStyle(
                                                  fontSize: fontSize,
                                                  fontWeight: FontWeight.w600,
                                                  color: theme
                                                      .colorScheme.onSurface),
                                              textAlign: TextAlign.center,
                                              maxLines: 2,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 2),
                                                border: OutlineInputBorder(
                                                  borderSide: BorderSide(
                                                      color: theme
                                                          .colorScheme.primary,
                                                      width: 2),
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                                enabledBorder:
                                                    OutlineInputBorder(
                                                  borderSide: BorderSide(
                                                      color: theme
                                                          .colorScheme.primary,
                                                      width: 2),
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                                focusedBorder:
                                                    OutlineInputBorder(
                                                  borderSide: BorderSide(
                                                      color: theme
                                                          .colorScheme.primary,
                                                      width: 2),
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                                filled: true,
                                                fillColor:
                                                    theme.colorScheme.surface,
                                              ),
                                              cursorColor:
                                                  theme.colorScheme.primary,
                                              onSubmitted: (_) =>
                                                  _commitTagRename(tag),
                                              onTapOutside: (_) =>
                                                  _commitTagRename(tag),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    GestureDetector(
                                      onDoubleTap: _isMultiSelectMode
                                          ? null
                                          : () => _openTag(tag),
                                      child: Tooltip(
                                        message: !_isMultiSelectMode
                                            ? 'Double click to open'
                                            : '',
                                        child: Text(
                                          tag,
                                          style: TextStyle(
                                              fontSize: fontSize,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  theme.colorScheme.onSurface),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  if (!_isMultiSelectMode) ...[
                                    SizedBox(height: spacing),
                                    // Action buttons row (hidden in multi-select mode)
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        InkWell(
                                          onTap: isEditing
                                              ? null
                                              : () {
                                                  if (isDesktop) {
                                                    _startTagRename(tag);
                                                  } else {
                                                    _showRenameDialog(tag);
                                                  }
                                                },
                                          borderRadius:
                                              BorderRadius.circular(16.0),
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                                isDesktop ? 6 : 4),
                                            child: Icon(
                                                PhosphorIconsLight.pencilSimple,
                                                size: iconSize,
                                                color: isEditing
                                                    ? theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: 0.3)
                                                    : theme.colorScheme
                                                        .onSurfaceVariant),
                                          ),
                                        ),
                                        SizedBox(width: isDesktop ? 8 : 4),
                                        InkWell(
                                          onTap: isEditing
                                              ? null
                                              : () => _directTagSearch(tag),
                                          borderRadius:
                                              BorderRadius.circular(16.0),
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                                isDesktop ? 6 : 4),
                                            child: Icon(
                                                PhosphorIconsLight.folder,
                                                size: iconSize,
                                                color: isEditing
                                                    ? theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: 0.3)
                                                    : theme
                                                        .colorScheme.primary),
                                          ),
                                        ),
                                        SizedBox(width: isDesktop ? 8 : 4),
                                        InkWell(
                                          onTap: isEditing
                                              ? null
                                              : () =>
                                                  _showColorPickerDialog(tag),
                                          borderRadius:
                                              BorderRadius.circular(16.0),
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                                isDesktop ? 6 : 4),
                                            child: Icon(
                                                PhosphorIconsLight.palette,
                                                size: iconSize,
                                                color: isEditing
                                                    ? theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: 0.3)
                                                    : theme.colorScheme
                                                        .onSurfaceVariant),
                                          ),
                                        ),
                                        SizedBox(width: isDesktop ? 8 : 4),
                                        InkWell(
                                          onTap: isEditing
                                              ? null
                                              : () => _confirmDeleteTag(tag),
                                          borderRadius:
                                              BorderRadius.circular(16.0),
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                                isDesktop ? 6 : 4),
                                            child: Icon(
                                                PhosphorIconsLight.trash,
                                                size: iconSize,
                                                color: isEditing
                                                    ? theme
                                                        .colorScheme.onSurface
                                                        .withValues(alpha: 0.3)
                                                    : theme.colorScheme.error
                                                        .withValues(
                                                            alpha: 0.7)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        // Selection rectangle overlay
        _buildSelectionOverlay(),
      ],
    );
  }

  Widget _buildFilesByTagList() {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filesBySelectedTag.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              PhosphorIconsLight.fileMagnifyingGlass,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.noFilesWithTag,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!
                  .debugInfo(_selectedTagForFiles ?? 'none'),
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
                  label: Text(AppLocalizations.of(context)!.backToAllTags),
                  onPressed: _clearTagSelection,
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon:
                      const Icon(PhosphorIconsLight.arrowsClockwise, size: 20),
                  label: Text(AppLocalizations.of(context)!.tryAgain),
                  onPressed: _selectedTagForFiles != null
                      ? () => _directTagSearch(_selectedTagForFiles!)
                      : null,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.22),
          ),
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          child: Row(
            children: [
              if (_selectedTagForFiles != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: TagColorManager.instance
                        .getTagColor(_selectedTagForFiles!),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _selectedTagForFiles!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_filesBySelectedTag.length} ${localizations.filesWithTagCount}',
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (!_isMobile && _selectedTagForFiles != null) ...[
                TextButton.icon(
                  icon: const Icon(PhosphorIconsLight.arrowLeft, size: 20),
                  label: Text(localizations.backToAllTags),
                  onPressed: _clearTagSelection,
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(PhosphorIconsLight.palette, size: 20),
                  label: Text(localizations.changeColor),
                  onPressed: () =>
                      _showColorPickerDialog(_selectedTagForFiles!),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding:
                const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            itemCount: _filesBySelectedTag.length,
            itemBuilder: (context, index) {
              final file = _filesBySelectedTag[index];
              final String path = file['path'] as String;
              final String fileName = pathlib.basename(path);
              final String dirName = pathlib.dirname(path);

              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onSecondaryTap: () => _showFileOptions(path),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          PhosphorIconsLight.fileText,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                      ),
                      title: Text(
                        fileName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        dirName,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        PhosphorIconsLight.caretRight,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FileDetailsScreen(
                              file: File(path),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showFileOptions(String filePath) {
    final theme = Theme.of(context);
    final File file = File(filePath);
    final String fileName = pathlib.basename(filePath);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                ),
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      filePath,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.info),
                title: Text(AppLocalizations.of(context)!.viewDetails),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FileDetailsScreen(
                        file: file,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.folderOpen),
                title: Text(AppLocalizations.of(context)!.openContainingFolder),
                onTap: () {
                  Navigator.pop(context);
                  final directory = pathlib.dirname(filePath);
                  _openContainingFolder(directory);
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsLight.pencilSimple),
                title: Text(AppLocalizations.of(context)!.editTags),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FileDetailsScreen(
                        file: file,
                        initialTab: 1,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCreateTagDialog() async {
    final TextEditingController tagController = TextEditingController();

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.newTagTitle),
          content: TextField(
            controller: tagController,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.enterTagName,
              prefixIcon: const Icon(PhosphorIconsLight.hash),
            ),
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(context).pop();
                _createNewTag(value.trim());
              }
            },
          ),
          actions: <Widget>[
            TextButton(
              child: Text(AppLocalizations.of(context)!.cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(AppLocalizations.of(context)!.create),
              onPressed: () {
                final tagName = tagController.text.trim();
                if (tagName.isNotEmpty) {
                  Navigator.of(context).pop();
                  _createNewTag(tagName);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _createNewTag(String tagName) async {
    final normalizedTagName = tagName.trim();
    if (normalizedTagName.isEmpty) {
      return;
    }

    final hasExistingTag = _allTags.any(
      (existingTag) =>
          existingTag.toLowerCase() == normalizedTagName.toLowerCase(),
    );

    if (hasExistingTag) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .tagAlreadyExists(normalizedTagName)),
        ),
      );
      return;
    }

    _standaloneCreatedTags.add(normalizedTagName);

    try {
      final saved = await TagManager.addStandaloneTag(normalizedTagName);
      if (!saved) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Failed to save tag to local database'),
            ),
          );
        }
        return;
      }
    } catch (e) {
      debugPrint('Error saving standalone tag: $e');
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Failed to save tag: $e'),
          ),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    final currentQuery = _searchController.text.trim().toLowerCase();
    if (currentQuery.isNotEmpty &&
        !normalizedTagName.toLowerCase().contains(currentQuery)) {
      _searchController.clear();
    }

    await _loadAllTags();

    if (!mounted) {
      return;
    }

    setState(() {
      _currentPage = 0;
      _focusedTag = normalizedTagName;
      _selectedTags
        ..clear()
        ..add(normalizedTagName);
      _isMultiSelectMode = false;
      _updatePagination();
    });

    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!
              .tagCreatedSuccessfully(normalizedTagName)),
        ),
      );
    }
  }

  void _openContainingFolder(String folderPath) {
    if (Directory(folderPath).existsSync()) {
      try {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
              content: Text(
                  '${AppLocalizations.of(context)!.openingFolder}$folderPath')),
        );

        final bool isInTabContext = context.findAncestorWidgetOfExactType<
                BlocProvider<TabManagerBloc>>() !=
            null;

        if (isInTabContext) {
          try {
            final tabManagerBloc = BlocProvider.of<TabManagerBloc>(context);

            final existingTab = tabManagerBloc.state.tabs.firstWhere(
              (tab) => tab.path == folderPath,
              orElse: () => TabData(id: '', name: '', path: ''),
            );

            if (existingTab.id.isNotEmpty) {
              tabManagerBloc.add(SwitchToTab(existingTab.id));
            } else {
              final folderName = pathlib.basename(folderPath);
              tabManagerBloc.add(
                AddTab(
                  path: folderPath,
                  name: folderName,
                  switchToTab: true,
                ),
              );
            }
          } catch (e) {}
        } else {
          RouteUtils.safePopDialog(context);
        }
      } catch (e) {}
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content: Text(
                '${AppLocalizations.of(context)!.folderNotFound}$folderPath')),
      );
    }
  }
}
