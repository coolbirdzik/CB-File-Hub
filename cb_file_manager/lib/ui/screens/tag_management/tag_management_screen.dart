import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_color_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_thumbnail_manager.dart';
import 'package:cb_file_manager/helpers/tags/tag_hierarchy_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/file_details_screen.dart';
import 'package:cb_file_manager/ui/dialogs/video_frame_picker_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cb_file_manager/ui/widgets/tag_chip.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/components/common/shared_file_context_menu.dart';
import 'package:cb_file_manager/ui/components/common/shared_action_bar.dart';
import 'package:cb_file_manager/ui/components/common/skeleton.dart';
import 'package:cb_file_manager/ui/components/common/soft_checkbox.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_state.dart';
import 'package:cb_file_manager/ui/widgets/selection_rectangle_painter.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/utils/app_logger.dart';
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
import 'package:cb_file_manager/ui/components/common/breadcrumb_address_bar.dart';
import 'package:cb_file_manager/ui/widgets/tree_view/tree_view.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/utils/grid_zoom_constraints.dart';
import 'package:cb_file_manager/ui/utils/view_mode_spectrum.dart';
import 'package:cb_file_manager/ui/widgets/ctrl_scroll_zoom.dart';
import '../../utils/route.dart';

/// Tag view modes (cycled by the toolbar icon button).
enum _TagViewMode { list, grid, tree }

class _TagTreeLayoutMetrics {
  final double rowExtent;
  final double thumbnailSize;
  final double fontSize;
  final double spacing;
  final double indentPerDepth;

  const _TagTreeLayoutMetrics({
    required this.rowExtent,
    required this.thumbnailSize,
    required this.fontSize,
    required this.spacing,
    required this.indentPerDepth,
  });
}

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
  late TagThumbnailManager _tagThumbnailManager;
  late TagHierarchyManager _tagHierarchyManager;
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

  // Filter options
  /// 'all' | 'parents' | 'children' | 'standalone'
  String _hierarchyFilter = 'all';

  /// 'all' | 'with' | 'without'
  String _thumbnailFilter = 'all';

  // View mode options
  _TagViewMode _viewMode = _TagViewMode.list;

  // Grid item-size zoom level (2 = biggest items / fewest columns,
  // maxGridZoomLevel = smallest items / most columns). Persisted to
  // UserPreferences with key 'tags_grid_zoom_level'.
  int _tagGridZoomLevel = UserPreferences.defaultGridZoomLevel;

  // Tree layout size level (0 = densest, 2 = default, 4 = most spacious).
  // Kept in memory; only grid zoom has an existing tag preference today.
  static const int _minTagTreeSizeLevel = 0;
  static const int _defaultTagTreeSizeLevel = 2;
  static const int _maxTagTreeSizeLevel = 4;
  int _tagTreeSizeLevel = _defaultTagTreeSizeLevel;

  // Cached tree roots ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â rebuilt only when tag data changes (not on every setState)
  List<TreeNode<String>> _cachedTreeRoots = const [];
  String? _treeRootsSignature;

  /// Maps normalized (lowercase) tag name -> display-cased name from
  /// [_allTags]. Used by the tree view because [TagHierarchyManager] stores
  /// relationships normalized while [_allTags] keeps original case.
  Map<String, String> get _normalizedToDisplay => {
        for (final t in _allTags) t.trim().toLowerCase(): t,
      };

  // Selection state
  final Set<String> _selectedTags = {};

  // Single-vs-double click detection (per tag)
  Timer? _singleTapTimer;
  String? _pendingSingleTapTag;

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
    _tagThumbnailManager = TagThumbnailManager.instance;
    _tagHierarchyManager = TagHierarchyManager.instance;
    _initTagColorManager();
    _initThumbnailAndHierarchy();

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
    final isCtrlOrMetaPressed = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isSelectAll = event is KeyDownEvent &&
        isCtrlOrMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyA;

    if (isSelectAll &&
        _selectedTagForFiles == null &&
        _editingTag == null &&
        !_isTextInputFocused()) {
      _selectAllFilteredTags();
      return true;
    }

    setState(() {
      _isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
      _isShiftPressed = HardwareKeyboard.instance.isShiftPressed;
    });
    return false;
  }

  bool _isTextInputFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    return focusedContext.widget is EditableText ||
        focusedContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _setDefaultViewMode() {
    if (!mounted) return;
    final screenWidth = MediaQuery.of(context).size.width;
    _viewMode = screenWidth > 600 ? _TagViewMode.grid : _TagViewMode.list;
    // Load persisted grid zoom level after the default view mode is set.
    _loadTagGridZoom();
  }

  /// Loads the persisted tag-grid zoom level from SharedPreferences.
  Future<void> _loadTagGridZoom() async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      final loaded = await prefs.getTagsGridZoomLevel();
      if (mounted) setState(() => _tagGridZoomLevel = loaded);
    } catch (_) {}
  }

  /// Persists the tag-grid zoom level to SharedPreferences.
  Future<void> _saveTagGridZoom(int level) async {
    try {
      final prefs = UserPreferences.instance;
      await prefs.init();
      await prefs.setTagsGridZoomLevel(level);
    } catch (_) {}
  }

  /// Handles a Ctrl+scroll view-scale delta on the tags page.
  ///
  /// Maps the tags page's three-mode spectrum (tree ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ list ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ grid with zoom)
  /// to the shared [ViewModeSpectrum] helper and applies the result.
  void _handleTagViewScaleDelta(int delta) {
    if (!_isDesktop) return;
    if (_viewMode == _TagViewMode.tree) {
      final nextTreeSize = (_tagTreeSizeLevel + delta)
          .clamp(_minTagTreeSizeLevel, _maxTagTreeSizeLevel)
          .toInt();
      if (nextTreeSize != _tagTreeSizeLevel) {
        setState(() => _tagTreeSizeLevel = nextTreeSize);
        return;
      }
    }

    // Convert _TagViewMode to the shared ViewMode for the spectrum helper.
    ViewMode sharedMode;
    switch (_viewMode) {
      case _TagViewMode.tree:
        sharedMode = ViewMode.tree;
        break;
      case _TagViewMode.list:
        sharedMode = ViewMode.list;
        break;
      case _TagViewMode.grid:
        sharedMode = ViewMode.grid;
        break;
    }

    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );

    final result = ViewModeSpectrum.step(
      currentMode: sharedMode,
      currentZoom: _tagGridZoomLevel,
      // Explorer convention: scroll-up (delta = -1 from CtrlScrollZoom) ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ bigger items.
      // FileViewShell already inverts the sign, so delta here is already Explorer-signed.
      delta: delta,
      supported: const {ViewMode.tree, ViewMode.list, ViewMode.grid},
      maxZoom: maxZoom,
    );

    // Convert result back to _TagViewMode.
    _TagViewMode newTagMode;
    switch (result.mode) {
      case ViewMode.tree:
        newTagMode = _TagViewMode.tree;
        break;
      case ViewMode.list:
        newTagMode = _TagViewMode.list;
        break;
      default:
        newTagMode = _TagViewMode.grid;
        break;
    }

    if (newTagMode == _viewMode && result.gridZoomLevel == _tagGridZoomLevel) {
      return;
    }

    setState(() {
      _viewMode = newTagMode;
      _tagGridZoomLevel = result.gridZoomLevel;
    });
    _saveTagGridZoom(result.gridZoomLevel);
  }

  _TagTreeLayoutMetrics get _tagTreeLayoutMetrics {
    switch (_tagTreeSizeLevel) {
      case 0:
        return const _TagTreeLayoutMetrics(
          rowExtent: 28,
          thumbnailSize: 18,
          fontSize: 12,
          spacing: 6,
          indentPerDepth: 14,
        );
      case 1:
        return const _TagTreeLayoutMetrics(
          rowExtent: 32,
          thumbnailSize: 21,
          fontSize: 12.5,
          spacing: 7,
          indentPerDepth: 15,
        );
      case 3:
        return const _TagTreeLayoutMetrics(
          rowExtent: 44,
          thumbnailSize: 30,
          fontSize: 14,
          spacing: 10,
          indentPerDepth: 17,
        );
      case 4:
        return const _TagTreeLayoutMetrics(
          rowExtent: 52,
          thumbnailSize: 36,
          fontSize: 15,
          spacing: 12,
          indentPerDepth: 18,
        );
      case _defaultTagTreeSizeLevel:
      default:
        return const _TagTreeLayoutMetrics(
          rowExtent: 36,
          thumbnailSize: 24,
          fontSize: 13,
          spacing: 8,
          indentPerDepth: 16,
        );
    }
  }

  /// Builds a single tag view mode entry for the toolbar PopupMenuButton.
  /// Mirrors the file/network browsers' menu styling (active row gets
  /// primary color, bold weight, and a trailing check icon).
  PopupMenuItem<_TagViewMode> _buildTagViewModeMenuItem(
    BuildContext context,
    _TagViewMode mode,
    IconData icon,
    String label,
  ) {
    final theme = Theme.of(context);
    final isActive = _viewMode == mode;
    return PopupMenuItem<_TagViewMode>(
      value: mode,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isActive ? theme.colorScheme.primary : null,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? theme.colorScheme.primary : null,
            ),
          ),
          const Spacer(),
          if (isActive)
            Icon(
              PhosphorIconsLight.check,
              color: theme.colorScheme.primary,
              size: 20,
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tagReloadDebounce?.cancel();
    _tagChangeSubscription?.cancel();
    _singleTapTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _searchController.removeListener(_filterTags);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initTagColorManager() async {
    await _tagColorManager.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _initThumbnailAndHierarchy() async {
    await Future.wait([
      _tagThumbnailManager.initialize(),
      _tagHierarchyManager.initialize(),
    ]);
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
      if (mounted) {
        AppToast.error(
            context, '${AppLocalizations.of(context)!.errorLoadingTags}$e');
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

    setState(() {
      // Step 1: Text search
      List<String> result;
      if (query.isEmpty) {
        result = List.from(_allTags);
      } else {
        result =
            _allTags.where((tag) => tag.toLowerCase().contains(query)).toList();
      }

      // Step 2: Hierarchy filter
      if (_hierarchyFilter != 'all') {
        result = result.where((tag) {
          final isParent = _tagHierarchyManager.isParent(tag);
          final isChild = _tagHierarchyManager.isChild(tag);
          switch (_hierarchyFilter) {
            case 'parents':
              return isParent;
            case 'children':
              return isChild;
            case 'standalone':
              return !isParent && !isChild;
            default:
              return true;
          }
        }).toList();
      }

      // Step 3: Thumbnail filter
      if (_thumbnailFilter != 'all') {
        result = result.where((tag) {
          final hasThumbnail =
              _tagThumbnailManager.getThumbnailSync(tag) != null;
          return _thumbnailFilter == 'with' ? hasThumbnail : !hasThumbnail;
        }).toList();
      }

      _filteredTags = result;
      _sortTags();
      _updatePagination();
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
        // Defer to async sort ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â load data then re-sort
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
      AppLogger.warning(
          'TagManagementScreen: Error sorting by $_sortCriteria: $e');
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
      AppLogger.warning('Error opening tag in new tab: $e');
    }
  }

  /// Handle a single tap on a tag with double-click detection.
  ///
  /// On desktop: schedules a delayed `_selectTag()` call. If a second tap comes
  /// within 250ms, the timer is cancelled and `_directTagSearch()` runs instead.
  ///
  /// On mobile: tap immediately opens the tag (no double-tap on touch).
  void _handleTagTap(String tag) {
    if (!_isDesktop) {
      _directTagSearch(tag);
      return;
    }

    // If there's a pending single-tap on the SAME tag, treat as double-click
    if (_singleTapTimer?.isActive == true && _pendingSingleTapTag == tag) {
      _singleTapTimer!.cancel();
      _pendingSingleTapTag = null;
      _directTagSearch(tag);
      return;
    }

    // Cancel any pending tap on a different tag and start a new timer
    _singleTapTimer?.cancel();
    _pendingSingleTapTag = tag;
    _singleTapTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted && _pendingSingleTapTag == tag) {
        _selectTag(tag);
        _pendingSingleTapTag = null;
      }
    });
  }

  /// Select a tag (click to select, similar to file/folder selection)
  /// This highlights the tag and shows it as selected
  void _selectTag(String tag) {
    setState(() {
      if (_isCtrlPressed) {
        // Ctrl + Click: toggle selection (add/remove from multi-select)
        if (_selectedTags.contains(tag)) {
          _selectedTags.remove(tag);
        } else {
          _selectedTags.add(tag);
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
        }
      } else {
        // Normal click: select exactly this tag, same as file/folder items.
        _focusedTag = tag;
        _selectedTags
          ..clear()
          ..add(tag);
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
      AppLogger.warning('Error loading files for tag: $e');
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
    final children = _tagHierarchyManager.getChildren(tag);

    if (children.isNotEmpty) {
      // Parent tag ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â show hierarchy-aware delete dialog
      final result = await RouteUtils.showAcrylicDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(localizations.deleteTagConfirmation(tag)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This tag has ${children.length} child tag${children.length > 1 ? "s" : ""}: ${children.join(", ")}',
              ),
              const SizedBox(height: 16),
              const Text(
                'What would you like to do?',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(localizations.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('keep_children'),
              child: const Text('Delete parent only'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('delete_all'),
              child: Text(
                'Delete parent and children',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      );

      if (result == 'keep_children') {
        // Remove hierarchy relationships only, then delete the parent tag
        await _tagHierarchyManager.removeAllForTag(tag);
        await _deleteTag(tag);
      } else if (result == 'delete_all') {
        // Delete parent and all children
        final tagsToDelete = [tag, ...children];
        for (final t in tagsToDelete) {
          await _tagHierarchyManager.removeAllForTag(t);
        }
        for (final t in tagsToDelete) {
          await _deleteTag(t, silent: tagsToDelete.length > 1);
        }
        if (mounted) {
          AppToast.success(context,
              'Deleted ${tagsToDelete.length} tags: ${tagsToDelete.join(", ")}');
        }
      }
      return;
    }

    // Non-parent tag ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â simple confirmation
    final bool result = await RouteUtils.showAcrylicDialog(
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
      // Clean up hierarchy relationships (if this tag is a child of something)
      await _tagHierarchyManager.removeAllForTag(tag);
      await _deleteTag(tag);
    }
  }

  Future<void> _deleteTag(String tag, {bool silent = false}) async {
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

      if (mounted && !silent) {
        AppToast.success(context, localizations.tagDeleted(tag));
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
        AppToast.error(context, localizations.errorDeletingTag(e.toString()));
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
    setState(() {
      _editingTag = tag;
      _editingTagController = TextEditingController(text: tag);
    });
  }

  /// Commit tag rename
  Future<void> _commitTagRename(String oldTag) async {
    if (_editingTagController == null || _editingTag == null) return;

    final newTag = _editingTagController!.text.trim();

    // Clear editing state FIRST to prevent the next tag at the same index
    // from entering edit mode when the list rebuilds after rename.
    _editingTag = null;
    final controller = _editingTagController;
    _editingTagController = null;
    setState(() {});
    controller?.dispose();

    if (newTag.isEmpty || newTag == oldTag) return;

    final localizations = AppLocalizations.of(context)!;

    // Check if tag already exists
    final allTagsLowercase = _allTags.map((t) => t.toLowerCase()).toSet();
    if (allTagsLowercase.contains(newTag.toLowerCase())) {
      if (mounted) {
        AppToast.warning(context, localizations.tagAlreadyExists(newTag));
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await TagManager.renameTag(oldTag, newTag);
      if (success) {
        // Rename the color as well
        final oldColor = TagColorManager.instance.getTagColor(oldTag);
        await TagColorManager.instance.setTagColor(newTag, oldColor);
        await TagColorManager.instance.removeTagColor(oldTag);
        await _loadAllTags();

        if (mounted) {
          AppToast.success(context, localizations.tagRenamed(oldTag, newTag));
        }
      }
    } catch (e) {
      AppLogger.warning('[TAG] Rename failed: "$oldTag" -> "$newTag": $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ Selection methods ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬

  void _toggleTagSelection(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
      _focusedTag = tag;
    });
  }

  void _selectAllFilteredTags() {
    setState(() {
      _selectedTags.addAll(_filteredTags);
      if (_selectedTags.isNotEmpty) {
        _focusedTag = _selectedTags.last;
      }
    });
  }

  void _deselectAllTags() {
    setState(() {
      _selectedTags.clear();
      _focusedTag = null;
    });
  }

  Future<void> _confirmBulkDeleteTags() async {
    if (_selectedTags.isEmpty) return;
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final count = _selectedTags.length;

    final result = await RouteUtils.showAcrylicDialog<bool>(
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
      await _loadAllTags();

      operation.succeed(
        operationId,
        detail: localizations.bulkDeleteSuccess(count),
      );

      if (mounted) {
        AppToast.success(context, localizations.bulkDeleteSuccess(count));
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
        AppToast.error(context, localizations.errorDeletingTag(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ignore: unused_element
  Widget _buildBulkActionBar() {
    // Reserved for future multi-select bulk action bar UI
    return const SizedBox.shrink();
  }

  /// Show rename dialog for mobile
  Future<void> _showRenameDialog(String tag) async {
    final localizations = AppLocalizations.of(context)!;

    final newTag = await RouteUtils.showAcrylicDialog<String>(
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
          AppToast.warning(context, localizations.tagAlreadyExists(newTag));
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
            AppToast.success(context, localizations.tagRenamed(tag, newTag));
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

  /// Full hierarchy management dialog for a tag.
  /// Shows current parent(s), current children, and allows editing both.
  Future<void> _showManageHierarchyDialog(String tag) async {
    await RouteUtils.showAcrylicDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _ManageHierarchyDialog(
          tag: tag,
          hierarchyManager: _tagHierarchyManager,
          allTags: _allTags,
          onChanged: () async {
            await _loadAllTags();
            if (mounted) setState(() {});
          },
        );
      },
    );
  }

  Future<void> _showThumbnailPicker(String tag) async {
    final currentThumbnail = _tagThumbnailManager.getThumbnailSync(tag);
    final theme = Theme.of(context);

    final result = await RouteUtils.showAcrylicDialog<String?>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Thumbnail for "$tag"'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Preview area
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: currentThumbnail != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.file(
                              File(currentThumbnail),
                              width: 160,
                              height: 160,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(PhosphorIconsLight.imageSquare,
                                        size: 48,
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(height: 8),
                                    Text('File not found',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(PhosphorIconsLight.image,
                                    size: 48,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5)),
                                const SizedBox(height: 8),
                                Text('No thumbnail',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    )),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
              actions: [
                if (currentThumbnail != null)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop('remove'),
                    child: Text(
                      'Remove',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop('video'),
                  icon: const Icon(PhosphorIconsLight.filmSlate, size: 18),
                  label: const Text('From Video'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop('image'),
                  icon: const Icon(PhosphorIconsLight.folderOpen, size: 18),
                  label: const Text('Browse Image'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == 'image') {
      await _pickThumbnailImage(tag);
    } else if (result == 'video') {
      await _pickThumbnailFromVideo(tag);
    } else if (result == 'remove') {
      await _tagThumbnailManager.deleteThumbnail(tag);
      if (mounted) {
        AppToast.success(context, 'Thumbnail removed for "$tag"');
        setState(() {});
      }
    }
  }

  Future<void> _pickThumbnailImage(String tag) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        dialogTitle: 'Choose thumbnail for "$tag"',
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final ok = await _tagThumbnailManager.setThumbnail(tag, filePath);
      if (mounted) {
        if (ok) {
          AppToast.success(context, 'Thumbnail set for "$tag"');
          setState(() {});
        } else {
          AppToast.error(context, 'Failed to set thumbnail');
        }
      }
    } catch (e) {
      AppLogger.error('Error picking thumbnail: $e');
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    }
  }

  /// Pick a video file, then open the video frame picker to extract a frame.
  Future<void> _pickThumbnailFromVideo(String tag) async {
    try {
      // Step 1: Pick a video file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        dialogTitle: 'Choose video for "$tag" thumbnail',
      );

      if (result == null || result.files.isEmpty) return;

      final videoPath = result.files.single.path;
      if (videoPath == null) return;

      // Step 2: Open video frame picker dialog
      if (!mounted) return;
      final framePath = await VideoFramePickerDialog.show(context, videoPath);

      if (framePath == null) return;

      // Step 3: Set the extracted frame as thumbnail
      final ok = await _tagThumbnailManager.setThumbnail(tag, framePath);
      if (mounted) {
        if (ok) {
          AppToast.success(context, 'Video frame thumbnail set for "$tag"');
          setState(() {});
        } else {
          AppToast.error(context, 'Failed to set video frame thumbnail');
        }
      }
    } catch (e) {
      AppLogger.error('Error picking video thumbnail: $e');
      if (mounted) {
        AppToast.error(context, 'Error: $e');
      }
    }
  }

  Future<void> _showColorPickerDialog(String tag) async {
    final AppLocalizations localizations = AppLocalizations.of(context)!;
    Color currentColor = _tagColorManager.getTagColor(tag);

    final Color? selectedColor = await RouteUtils.showAcrylicDialog<Color>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                        setDialogState(() {
                          currentColor = color;
                        });
                      },
                      pickerAreaHeightPercent: 0.8,
                      enableAlpha: false,
                      displayThumbColor: true,
                      labelTypes: const [
                        ColorLabelType.rgb,
                        ColorLabelType.hsv
                      ],
                      pickerAreaBorderRadius:
                          const BorderRadius.all(Radius.circular(12)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext, rootNavigator: true).pop();
                  },
                  child: Text(localizations.cancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext, rootNavigator: true)
                        .pop(currentColor);
                  },
                  child: Text(localizations.save),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedColor == null || !mounted) {
      return;
    }

    await _tagColorManager.setTagColor(tag, selectedColor);
    if (!mounted) {
      return;
    }

    setState(() {});
    AppToast.success(context, localizations.tagColorUpdated(tag));
  }

  KeyEventResult _handleInlineRenameKey(
      FocusNode node, KeyEvent event, String tag) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _commitTagRename(tag);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _editingTag = null;
        _editingTagController?.dispose();
        _editingTagController = null;
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
                  icon: Icon(_selectedTags.isNotEmpty && !showingTaggedFiles
                      ? PhosphorIconsLight.x
                      : PhosphorIconsLight.arrowLeft),
                  onPressed: _selectedTags.isNotEmpty && !showingTaggedFiles
                      ? _deselectAllTags
                      : showingTaggedFiles
                          ? _clearTagSelection
                          : () => _handleBack(context),
                ),
                const SizedBox(width: 8),
                if (_isSearching && !showingTaggedFiles)
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: localizations.searchTagsHint,
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  )
                else if (showingTaggedFiles)
                  Expanded(
                    child: _buildTaggedFilesHeaderTitle(theme, localizations),
                  )
                else
                  const Spacer(),
                if (_selectedTags.isNotEmpty &&
                    !showingTaggedFiles &&
                    _isMobile) ...[
                  IconButton(
                    icon: const Icon(PhosphorIconsLight.trash),
                    onPressed: _selectedTags.isNotEmpty
                        ? _confirmBulkDeleteTags
                        : null,
                    tooltip: localizations.deleteSelected,
                  ),
                ],
                if (!showingTaggedFiles)
                  ..._buildTagToolbarActions(theme, localizations),
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
                if (!showingTaggedFiles)
                  PopupMenuButton<String>(
                    icon: const Icon(PhosphorIconsLight.dotsThreeVertical),
                    tooltip: localizations.moreOptionsTooltip,
                    onSelected: (value) {
                      switch (value) {
                        case 'select_all':
                          _selectAllFilteredTags();
                          break;
                        case 'new_tag':
                          _showCreateTagDialog();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'select_all',
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsLight.checks, size: 20),
                            const SizedBox(width: 10),
                            Text(localizations.selectAllTags),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: 'new_tag',
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsLight.plus, size: 20),
                            const SizedBox(width: 10),
                            Text(localizations.createNewTagButton),
                          ],
                        ),
                      ),
                    ],
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
    return BreadcrumbAddressBar(
      segments: [
        BreadcrumbSegment(
          label: localizations.tagManagementTitle,
          icon: PhosphorIconsLight.tag,
        ),
        BreadcrumbSegment(
          label: _selectedTagForFiles ?? localizations.tagManagementTitle,
          badge: '${_filesBySelectedTag.length}',
        ),
      ],
    );
  }

  List<Widget> _buildTagToolbarActions(
    ThemeData theme,
    AppLocalizations localizations,
  ) {
    return [
      _buildFilterButton(theme, localizations),
      _buildSortMenuButton(theme, localizations),
      _buildViewModeMenuButton(theme, localizations),
      if (_viewMode == _TagViewMode.grid)
        _buildTagGridSizeButton(theme, localizations),
    ];
  }

  Widget _buildTagGridSizeButton(
    ThemeData theme,
    AppLocalizations localizations,
  ) {
    final dynamicMax = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final clampedMax = dynamicMax
        .clamp(
          UserPreferences.minGridZoomLevel,
          UserPreferences.maxGridZoomLevel,
        )
        .toInt();
    final clampedZoom = _tagGridZoomLevel
        .clamp(
          UserPreferences.minGridZoomLevel,
          clampedMax,
        )
        .toInt();

    if (_isMobile) {
      return IconButton(
        icon: Icon(
          PhosphorIconsLight.squaresFour,
          color: theme.colorScheme.onSurfaceVariant,
          size: 20,
        ),
        tooltip: localizations.adjustGridSizeTooltip,
        onPressed: () => SharedActionBar.showGridSizeDialog(
          context,
          currentGridSize: clampedZoom,
          onApply: _setTagGridZoomLevel,
        ),
      );
    }

    return PopupMenuButton<void>(
      icon: Icon(
        PhosphorIconsLight.squaresFour,
        color: theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      tooltip: localizations.adjustGridSizeTooltip,
      offset: const Offset(0, 50),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: GridSizeSliderMenu(
            currentValue: clampedZoom,
            minValue: UserPreferences.minGridZoomLevel,
            maxValue: clampedMax,
            onChanged: _setTagGridZoomLevel,
          ),
        ),
      ],
    );
  }

  void _setTagGridZoomLevel(int value) {
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final next = value.clamp(UserPreferences.minGridZoomLevel, maxZoom).toInt();
    if (next == _tagGridZoomLevel) return;
    setState(() => _tagGridZoomLevel = next);
    _saveTagGridZoom(next);
  }

  Widget _buildSortMenuButton(
    ThemeData theme,
    AppLocalizations localizations,
  ) {
    return PopupMenuButton<String>(
      tooltip: localizations.sortTags,
      onSelected: _changeSortCriteria,
      icon: Icon(
        PhosphorIconsLight.sortAscending,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      itemBuilder: (context) => [
        _buildSortMenuItem(
          'name',
          PhosphorIconsLight.sortAscending,
          localizations.sortByAlphabet,
        ),
        _buildSortMenuItem(
          'popularity',
          PhosphorIconsLight.chartBar,
          localizations.sortByPopular,
        ),
        _buildSortMenuItem(
          'recent',
          PhosphorIconsLight.clockCounterClockwise,
          localizations.sortByRecent,
        ),
      ],
    );
  }

  Widget _buildViewModeMenuButton(
    ThemeData theme,
    AppLocalizations localizations,
  ) {
    return PopupMenuButton<_TagViewMode>(
      icon: Icon(
        PhosphorIconsLight.eye,
        color: theme.colorScheme.onSurfaceVariant,
        size: 20,
      ),
      tooltip: localizations.viewModeTooltip,
      offset: const Offset(0, 50),
      initialValue: _viewMode,
      itemBuilder: (context) => [
        _buildTagViewModeMenuItem(
          context,
          _TagViewMode.list,
          PhosphorIconsLight.list,
          localizations.viewModeList,
        ),
        _buildTagViewModeMenuItem(
          context,
          _TagViewMode.grid,
          PhosphorIconsLight.squaresFour,
          localizations.viewModeGrid,
        ),
        _buildTagViewModeMenuItem(
          context,
          _TagViewMode.tree,
          PhosphorIconsLight.treeView,
          localizations.viewModeTree,
        ),
      ],
      onSelected: (mode) {
        if (mode != _viewMode) {
          setState(() => _viewMode = mode);
        }
      },
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

  Future<void> _showTagOptions(String tag, {Offset? globalPosition}) async {
    final l10n = AppLocalizations.of(context)!;
    final sections = _buildTagContextMenuSections(tag, l10n);

    if (_isMobile || globalPosition == null) {
      await showContextMenuSheet(
        context: context,
        title: tag,
        icon: PhosphorIconsLight.tag,
        sections: sections,
      );
      return;
    }

    await showContextMenuPopup(
      context: context,
      sections: sections,
      globalPosition: globalPosition,
    );
  }

  List<ContextMenuSection> _buildTagContextMenuSections(
    String tag,
    AppLocalizations l10n,
  ) {
    return [
      ContextMenuSection(
        actions: [
          ContextMenuAction(
            id: 'view_files',
            label: l10n.viewFilesWithTag,
            icon: PhosphorIconsLight.folder,
            onSelected: (_) => _directTagSearch(tag),
          ),
          if (widget.onTagSelected == null)
            ContextMenuAction(
              id: 'open_tab',
              label: l10n.openInNewTab,
              icon: PhosphorIconsLight.appWindow,
              onSelected: (_) => _directTagSearch(tag),
            ),
        ],
      ),
      ContextMenuSection(
        actions: [
          ContextMenuAction(
            id: 'rename',
            label: l10n.renameTag,
            icon: PhosphorIconsLight.pencilSimple,
            onSelected: (_) {
              if (_isDesktop) {
                _startTagRename(tag);
              } else {
                _showRenameDialog(tag);
              }
            },
          ),
          ContextMenuAction(
            id: 'color',
            label: l10n.changeTagColor,
            icon: PhosphorIconsLight.palette,
            onSelected: (_) => _showColorPickerDialog(tag),
          ),
          ContextMenuAction(
            id: 'thumbnail',
            label: 'Set Thumbnail',
            icon: PhosphorIconsLight.image,
            onSelected: (_) => _showThumbnailPicker(tag),
          ),
          ContextMenuAction(
            id: 'hierarchy',
            label: 'Manage Hierarchy',
            icon: PhosphorIconsLight.treeStructure,
            onSelected: (_) => _showManageHierarchyDialog(tag),
          ),
        ],
      ),
      ContextMenuSection(
        actions: [
          ContextMenuAction(
            id: 'delete',
            label: l10n.deleteTag,
            icon: PhosphorIconsLight.trash,
            isDestructive: true,
            onSelected: (_) => _confirmDeleteTag(tag),
          ),
        ],
      ),
    ];
  }

  /// Show context menu for multi-selected tags (right-click on PC)
  Future<void> _showMultiSelectContextMenu(Offset globalPosition) async {
    final l10n = AppLocalizations.of(context)!;
    final sections = [
      ContextMenuSection(
        actions: [
          ContextMenuAction(
            id: 'delete',
            label: l10n.deleteSelected,
            icon: PhosphorIconsLight.trash,
            isDestructive: true,
            onSelected: (_) => _confirmBulkDeleteTags(),
          ),
        ],
      ),
    ];

    await showContextMenuPopup(
      context: context,
      sections: sections,
      globalPosition: globalPosition,
    );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with tag count
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Icon(PhosphorIconsLight.tag,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_filteredTags.length} ${localizations.tagsCreated}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (_selectedTags.isNotEmpty && !_isDesktop) ...[
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
            ],
          ),
        ),

        // Active filters chip row
        if (_hierarchyFilter != 'all' || _thumbnailFilter != 'all')
          _buildActiveFiltersBar(theme),

        // Tags list, grid or tree
        Expanded(
          child: _buildTagsContent(),
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

  /// Filter button with badge showing active filter count.
  Widget _buildFilterButton(ThemeData theme, AppLocalizations localizations) {
    final activeCount = (_hierarchyFilter != 'all' ? 1 : 0) +
        (_thumbnailFilter != 'all' ? 1 : 0);
    final hasActive = activeCount > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            PhosphorIconsLight.funnel,
            size: 20,
            color: hasActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          tooltip: 'Filter tags',
          onPressed: _showFilterDialog,
        ),
        if (hasActive)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                '$activeCount',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  /// Bar showing active filters as removable chips.
  Widget _buildActiveFiltersBar(ThemeData theme) {
    final chips = <Widget>[];

    if (_hierarchyFilter != 'all') {
      String label;
      IconData icon;
      switch (_hierarchyFilter) {
        case 'parents':
          label = 'Parent tags';
          icon = PhosphorIconsLight.treeStructure;
          break;
        case 'children':
          label = 'Child tags';
          icon = PhosphorIconsLight.arrowBendUpLeft;
          break;
        case 'standalone':
          label = 'Standalone';
          icon = PhosphorIconsLight.tag;
          break;
        default:
          label = '';
          icon = PhosphorIconsLight.funnel;
      }
      chips.add(_buildFilterChip(
        theme,
        label: label,
        icon: icon,
        onRemove: () {
          setState(() => _hierarchyFilter = 'all');
          _filterTags();
        },
      ));
    }

    if (_thumbnailFilter != 'all') {
      chips.add(_buildFilterChip(
        theme,
        label: _thumbnailFilter == 'with' ? 'Has thumbnail' : 'No thumbnail',
        icon: PhosphorIconsLight.image,
        onRemove: () {
          setState(() => _thumbnailFilter = 'all');
          _filterTags();
        },
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(PhosphorIconsLight.funnel,
              size: 14,
              color: theme.colorScheme.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 6,
                children: chips,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _hierarchyFilter = 'all';
                _thumbnailFilter = 'all';
              });
              _filterTags();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Clear all', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    ThemeData theme, {
    required String label,
    required IconData icon,
    required VoidCallback onRemove,
  }) {
    return Chip(
      avatar: Icon(icon, size: 14, color: theme.colorScheme.primary),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      deleteIcon: const Icon(PhosphorIconsLight.x, size: 14),
      onDeleted: onRemove,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      side: BorderSide(
        color: theme.colorScheme.primary.withValues(alpha: 0.3),
      ),
    );
  }

  /// Show the filter selection dialog.
  Future<void> _showFilterDialog() async {
    final theme = Theme.of(context);

    await RouteUtils.showAcrylicDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(PhosphorIconsLight.funnel,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text('Filter tags'),
                ],
              ),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hierarchy',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                        )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterOption(
                          theme,
                          label: 'All',
                          selected: _hierarchyFilter == 'all',
                          onTap: () =>
                              setDialogState(() => _hierarchyFilter = 'all'),
                        ),
                        _buildFilterOption(
                          theme,
                          label: 'Parent tags',
                          icon: PhosphorIconsLight.treeStructure,
                          selected: _hierarchyFilter == 'parents',
                          onTap: () => setDialogState(
                              () => _hierarchyFilter = 'parents'),
                        ),
                        _buildFilterOption(
                          theme,
                          label: 'Child tags',
                          icon: PhosphorIconsLight.arrowBendUpLeft,
                          selected: _hierarchyFilter == 'children',
                          onTap: () => setDialogState(
                              () => _hierarchyFilter = 'children'),
                        ),
                        _buildFilterOption(
                          theme,
                          label: 'Standalone',
                          icon: PhosphorIconsLight.tag,
                          selected: _hierarchyFilter == 'standalone',
                          onTap: () => setDialogState(
                              () => _hierarchyFilter = 'standalone'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Thumbnail',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: theme.colorScheme.primary,
                        )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterOption(
                          theme,
                          label: 'All',
                          selected: _thumbnailFilter == 'all',
                          onTap: () =>
                              setDialogState(() => _thumbnailFilter = 'all'),
                        ),
                        _buildFilterOption(
                          theme,
                          label: 'Has thumbnail',
                          icon: PhosphorIconsLight.image,
                          selected: _thumbnailFilter == 'with',
                          onTap: () =>
                              setDialogState(() => _thumbnailFilter = 'with'),
                        ),
                        _buildFilterOption(
                          theme,
                          label: 'No thumbnail',
                          icon: PhosphorIconsLight.imageBroken,
                          selected: _thumbnailFilter == 'without',
                          onTap: () => setDialogState(
                              () => _thumbnailFilter = 'without'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      _hierarchyFilter = 'all';
                      _thumbnailFilter = 'all';
                    });
                  },
                  child: const Text('Reset'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _filterTags();
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFilterOption(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
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

  /// Builds a thumbnail image or a color dot fallback for a tag.
  Widget _buildTagThumbnailOrDot(String tag, Color tagColor,
      {double size = 40}) {
    final thumbnailPath = _tagThumbnailManager.getThumbnailSync(tag);
    if (thumbnailPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size > 40 ? 12 : 8),
        child: Image.file(
          File(thumbnailPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: tagColor,
              borderRadius: BorderRadius.circular(size > 40 ? 12 : 8),
            ),
            child: Icon(
              PhosphorIconsLight.image,
              size: size * 0.5,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
    }
    // Fallback: color dot (larger for grid, smaller for list)
    final dotSize = size > 40 ? 32.0 : 12.0;
    return Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(color: tagColor, shape: BoxShape.circle),
    );
  }

  /// Edge-to-edge thumbnail for the grid card top area. Fills the available
  /// space (cover) so the card reads like a media/tag card. Falls back to a
  /// color-tinted panel with a centered icon when no thumbnail exists.
  Widget _buildTagCardThumbnailFill(String tag, Color tagColor) {
    final thumbnailPath = _tagThumbnailManager.getThumbnailSync(tag);
    if (thumbnailPath != null) {
      return Image.file(
        File(thumbnailPath),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _buildTagCardThumbnailPlaceholder(
          tagColor,
          PhosphorIconsLight.image,
        ),
      );
    }
    return _buildTagCardThumbnailPlaceholder(tagColor, PhosphorIconsLight.tag);
  }

  Widget _buildTagCardThumbnailPlaceholder(Color tagColor, IconData icon) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tagColor.withValues(alpha: 0.55),
            tagColor.withValues(alpha: 0.22),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.85),
          size: 40,
        ),
      ),
    );
  }

  /// Builds a small hierarchy context label below the tag name.
  Widget _buildHierarchyContext(String tag, ThemeData theme,
      {bool centered = false}) {
    final parents = _tagHierarchyManager.getParents(tag);
    final children = _tagHierarchyManager.getChildren(tag);

    if (parents.isEmpty && children.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Column(
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (parents.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsLight.arrowBendUpLeft,
                  size: 12,
                  color: theme.colorScheme.primary.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    parents.join(', '),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          if (children.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIconsLight.treeStructure,
                  size: 12,
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    '${children.length}: ${children.take(3).join(", ")}${children.length > 3 ? "..." : ""}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.tertiary.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
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

        return GestureDetector(
          onSecondaryTapUp: isEditing
              ? null
              : (details) =>
                  _showTagOptions(tag, globalPosition: details.globalPosition),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.0),
              side: isEditing
                  ? BorderSide(color: theme.colorScheme.primary, width: 2)
                  : isSelected || isFocused
                      ? BorderSide(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.5),
                          width: 1.5)
                      : BorderSide.none,
            ),
            tileColor: isSelected || isFocused
                ? theme.colorScheme.primary.withValues(alpha: 0.12)
                : tagColor.withValues(alpha: 0.08),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  SoftCheckbox(
                    value: isSelected,
                    onChanged: (_) => _toggleTagSelection(tag),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                ],
                _buildTagThumbnailOrDot(tag, tagColor, size: 40),
              ],
            ),
            title: isEditing && _editingTagController != null
                ? Focus(
                    onKeyEvent: (node, event) =>
                        _handleInlineRenameKey(node, event, tag),
                    child: TextField(
                      controller: _editingTagController,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
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
                      onEditingComplete: () => _commitTagRename(tag),
                      onSubmitted: (_) => _commitTagRename(tag),
                      onTapOutside: (_) => _commitTagRename(tag),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
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
                            if (isDesktop) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: AppLocalizations.of(context)!
                                    .doubleClickToRename,
                                child: Icon(PhosphorIconsLight.pencilSimple,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5)),
                              ),
                            ],
                          ],
                        ),
                        _buildHierarchyContext(tag, theme),
                      ],
                    ),
                  ),
            onTap: isEditing ? null : () => _handleTagTap(tag),
            onLongPress: isEditing ? null : () => _showTagOptions(tag),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(PhosphorIconsLight.pencilSimple,
                      size: 20,
                      color: isEditing
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
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
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                          : theme.colorScheme.primary),
                  onPressed: isEditing ? null : () => _directTagSearch(tag),
                  tooltip: AppLocalizations.of(context)!.viewFilesWithTag,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(PhosphorIconsLight.palette,
                      size: 20,
                      color: isEditing
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                          : theme.colorScheme.onSurfaceVariant),
                  onPressed:
                      isEditing ? null : () => _showColorPickerDialog(tag),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(PhosphorIconsLight.image,
                      size: 20,
                      color: isEditing
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                          : theme.colorScheme.onSurfaceVariant),
                  onPressed: isEditing ? null : () => _showThumbnailPicker(tag),
                  tooltip: 'Set thumbnail',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(PhosphorIconsLight.treeStructure,
                      size: 20,
                      color: isEditing
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                          : (_tagHierarchyManager.isParent(tag) ||
                                  _tagHierarchyManager.isChild(tag)
                              ? theme.colorScheme.tertiary
                              : theme.colorScheme.onSurfaceVariant)),
                  onPressed:
                      isEditing ? null : () => _showManageHierarchyDialog(tag),
                  tooltip: 'Manage hierarchy (parent/child)',
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(PhosphorIconsLight.trash,
                      size: 20,
                      color: isEditing
                          ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                          : theme.colorScheme.error.withValues(alpha: 0.7)),
                  onPressed: isEditing ? null : () => _confirmDeleteTag(tag),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagsContent() {
    final Widget content;
    switch (_viewMode) {
      case _TagViewMode.list:
        content = _buildTagsListView();
        break;
      case _TagViewMode.grid:
        content = _buildTagsGridView();
        break;
      case _TagViewMode.tree:
        content = _buildTagsTreeView();
        break;
    }

    return CtrlScrollZoom(
      onDelta: _isDesktop ? (delta) => _handleTagViewScaleDelta(-delta) : null,
      child: content,
    );
  }

  /// Builds the tag tree.
  ///
  /// Roots = parent tags (from [TagHierarchyManager.getRootParents]) plus
  /// standalone tags (no parents and no children). Children are pulled
  /// synchronously from the in-memory hierarchy.
  ///
  /// Search and the active filters (`_hierarchyFilter`, `_thumbnailFilter`)
  /// are honoured: any node whose subtree contains a match is kept (so
  /// ancestors of matches stay visible). Result respects the current
  /// `_filteredTags` set.
  Widget _buildTagsTreeView() {
    final visibleSet = _filteredTags.toSet();
    final treeLayout = _tagTreeLayoutMetrics;

    // The hierarchy manager stores tags NORMALIZED (lowercased + trimmed),
    // but _allTags / _filteredTags hold the original display case. Build a
    // normalized -> display map so tree nodes use display names that match
    // the visible set (otherwise every parent/child gets filtered out).
    String displayOf(String normalized) =>
        _normalizedToDisplay[normalized] ?? normalized;

    // Only rebuild tree structure when tag data actually changes.
    // Signature captures all tags + the full hierarchy tree so adding a
    // child to an existing parent also invalidates the cache.
    final rootParents = _tagHierarchyManager.getRootParents();
    final hierarchyTree = _tagHierarchyManager.getHierarchyTree();
    final hierarchySig = (hierarchyTree.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}>${e.value.join("+")}')
        .join("|");
    final sig = '${_allTags.length}|$hierarchySig';
    if (sig != _treeRootsSignature) {
      _treeRootsSignature = sig;
      final standalone = _allTags
          .where((t) =>
              !_tagHierarchyManager.isParent(t) &&
              !_tagHierarchyManager.isChild(t))
          .toList();

      // [tag] here is a NORMALIZED hierarchy name; nodes store the display
      // form so selection/filtering line up with _allTags / _filteredTags.
      TreeNode<String> buildTagNode(String tag, Set<String> ancestry) {
        final children = _tagHierarchyManager
            .getChildren(tag)
            .where((c) => !ancestry.contains(c))
            .toList();
        final nextAncestry = {...ancestry, tag};
        return TreeNode<String>(
          id: displayOf(tag),
          data: displayOf(tag),
          isLeaf: children.isEmpty,
          children: children.map((c) => buildTagNode(c, nextAncestry)).toList(),
        );
      }

      _cachedTreeRoots = <TreeNode<String>>[
        ...rootParents.map((p) => buildTagNode(p, const <String>{})),
        ...standalone.map(
          (t) => TreeNode<String>(
            id: t,
            data: t,
            isLeaf: true,
            children: const <TreeNode<String>>[],
          ),
        ),
      ];
    }

    // Compute the "should show" set: any node whose data is in
    // visibleSet, plus all of its ancestors.
    final showIds = <String>{};
    bool walk(TreeNode<String> node, List<String> path) {
      var matched = visibleSet.contains(node.data);
      for (final c in node.children ?? const <TreeNode<String>>[]) {
        if (walk(c, [...path, node.id])) matched = true;
      }
      if (matched) {
        showIds.add(node.id);
        showIds.addAll(path);
      }
      return matched;
    }

    for (final r in _cachedTreeRoots) {
      walk(r, const <String>[]);
    }

    return GestureDetector(
      onTap: () {
        if (_selectedTags.isNotEmpty && _editingTag == null) {
          _deselectAllTags();
        }
      },
      onSecondaryTapUp: (details) {
        if (_selectedTags.isNotEmpty) {
          _showMultiSelectContextMenu(details.globalPosition);
        }
      },
      behavior: HitTestBehavior.translucent,
      child: GenericTreeView<String>(
        roots: _cachedTreeRoots,
        itemExtent: treeLayout.rowExtent,
        indentPerDepth: treeLayout.indentPerDepth,
        expandOnRowTap: true,
        nodeFilter: (node) => showIds.contains(node.id),
        selectedIds: _selectedTags,
        focusedId: _focusedTag,
        // Tree rows: select immediately. The tree row shell does its own
        // double-tap detection (fires onDoubleTap), so we must NOT route
        // through _handleTagTap's 250ms timer here or a double-tap would
        // both open and select.
        onTap: (node) => _selectTag(node.data),
        onDoubleTap: (node) => _directTagSearch(node.data),
        onSecondary: (node, globalPosition) => _showTagOptions(
          node.data,
          globalPosition: globalPosition,
        ),
        emptyState: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              AppLocalizations.of(context)!.noTagsFound,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        itemBuilder: (context, node, depth) {
          final tag = node.data;
          final tagColor = TagColorManager.instance.getTagColor(tag);
          return _buildTagTreeDragDropRow(
            tag: tag,
            child: _TagTreeRowContent(
              tag: tag,
              tagColor: tagColor,
              thumbnailSize: treeLayout.thumbnailSize,
              fontSize: treeLayout.fontSize,
              spacing: treeLayout.spacing,
              buildThumbnail: (size) =>
                  _buildTagThumbnailOrDot(tag, tagColor, size: size),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTagTreeDragDropRow({
    required String tag,
    required Widget child,
  }) {
    if (!_isDesktop || _viewMode != _TagViewMode.tree) return child;

    final draggable = Draggable<String>(
      data: tag,
      maxSimultaneousDrags: 1,
      feedback: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              tag,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.55, child: child),
      child: child,
    );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          _canDropTagOnParent(details.data, tag),
      onAcceptWithDetails: (details) => _moveTagUnderParent(
        childTag: details.data,
        parentTag: tag,
      ),
      builder: (context, candidateData, rejectedData) {
        if (candidateData.isEmpty) return draggable;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: draggable,
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
            if (_editingTag == null && _selectedTags.isNotEmpty) {
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
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 8),
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

  /// A single compact action button used inside the grid hover toolbar.
  Widget _buildTagToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required Color color,
    required double iconSize,
    double padding = 7.0,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.0),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }

  /// Desktop hover toolbar shown floating near the bottom of a tag thumbnail.
  ///
  /// Surfaces the three most-used actions (view files, rename, delete) plus an
  /// overflow button that opens the full tag context menu anchored to itself.
  Widget _buildTagHoverToolbar(
    String tag,
    ThemeData theme,
    double iconSize, {
    required double maxWidth,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final compact = maxWidth < 144;
    final effectiveIconSize =
        compact ? (iconSize - 2).clamp(14.0, 18.0) : iconSize;
    final buttonPadding = compact ? 4.0 : 7.0;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(24.0),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth - 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTagToolbarButton(
                icon: PhosphorIconsLight.folder,
                tooltip: l10n.viewFilesWithTag,
                onTap: () => _directTagSearch(tag),
                color: theme.colorScheme.primary,
                iconSize: effectiveIconSize,
                padding: buttonPadding,
              ),
              _buildTagToolbarButton(
                icon: PhosphorIconsLight.pencilSimple,
                tooltip: l10n.renameTag,
                onTap: () => _startTagRename(tag),
                color: theme.colorScheme.onSurfaceVariant,
                iconSize: effectiveIconSize,
                padding: buttonPadding,
              ),
              _buildTagToolbarButton(
                icon: PhosphorIconsLight.trash,
                tooltip: l10n.deleteTag,
                onTap: () => _confirmDeleteTag(tag),
                color: theme.colorScheme.error.withValues(alpha: 0.85),
                iconSize: effectiveIconSize,
                padding: buttonPadding,
              ),
              Builder(
                builder: (btnContext) => _buildTagToolbarButton(
                  icon: PhosphorIconsLight.dotsThreeOutline,
                  tooltip: l10n.moreOptions,
                  onTap: () => _showTagOptions(
                    tag,
                    globalPosition: _anchorOf(btnContext),
                  ),
                  color: theme.colorScheme.onSurfaceVariant,
                  iconSize: effectiveIconSize,
                  padding: buttonPadding,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Overflow ("ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦") button used on mobile (and as the touch fallback) that
  /// opens the full tag context menu.
  Widget _buildTagOverflowButton(String tag, ThemeData theme) {
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.7),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showTagOptions(tag),
        child: Padding(
          padding: const EdgeInsets.all(5.0),
          child: Icon(
            PhosphorIconsLight.dotsThreeOutline,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Returns the global position to anchor a context-menu popup to the given
  /// element (its center), falling back to null when unavailable.
  Offset? _anchorOf(BuildContext elementContext) {
    final renderBox = elementContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return null;
    return renderBox.localToGlobal(renderBox.size.center(Offset.zero));
  }

  Widget _buildTagsGridView() {
    final theme = Theme.of(context);
    final isDesktop = _isDesktop;

    // Use zoom-level-driven column count (same math as the file browser).
    // _tagGridZoomLevel is the number of columns at the 960 px reference width.
    final maxZoom = GridZoomConstraints.maxGridSizeForContext(
      context,
      mode: GridSizeMode.referenceWidth,
    );
    final effectiveZoom = _tagGridZoomLevel
        .clamp(UserPreferences.minGridZoomLevel, maxZoom)
        .toInt();
    final crossAxisCount = GridZoomConstraints.columnCountForZoom(
      effectiveZoom,
      MediaQuery.of(context).size.width,
    ).clamp(1, 20);

    // Larger fonts and spacing for desktop
    final fontSize = isDesktop ? 14.0 : 12.0;
    final iconSize = isDesktop ? 20.0 : 16.0;
    final spacing = isDesktop ? 8.0 : 4.0;

    // Clear tag positions when building the grid
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clearTagPositions();
    });

    // GridView with drag selection support (same as ListView).
    // Ctrl+scroll is handled by _buildTagsContent so it works in all modes.
    return Stack(
      children: [
        GestureDetector(
          onTap: () {
            // Tap to deselect when not in edit mode
            if (_editingTag == null && _selectedTags.isNotEmpty) {
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
              bottom: isDesktop ? 16 : 12,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: isDesktop ? 1.25 : 1.15,
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
                      onTap: isEditing ? null : () => _handleTagTap(tag),
                      onDoubleTap:
                          isEditing ? null : () => _directTagSearch(tag),
                      onLongPress:
                          isEditing ? null : () => _showTagOptions(tag),
                      onSecondaryTapUp: isEditing
                          ? null
                          : (details) => _showTagOptions(
                                tag,
                                globalPosition: details.globalPosition,
                              ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16.0),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: isSelected || isFocused
                                          ? [
                                              theme.colorScheme.primary
                                                  .withValues(alpha: 0.26),
                                              theme.colorScheme.primary
                                                  .withValues(alpha: 0.16),
                                            ]
                                          : [
                                              theme.colorScheme.surface
                                                  .withValues(alpha: 0.34),
                                              Color.alphaBlend(
                                                tagColor.withValues(
                                                    alpha: 0.10),
                                                theme.colorScheme.surface
                                                    .withValues(alpha: 0.22),
                                              ),
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(16.0),
                                    border: Border.all(
                                      color: isEditing
                                          ? theme.colorScheme.primary
                                          : isSelected || isFocused
                                              ? theme.colorScheme.primary
                                                  .withValues(alpha: 0.55)
                                              : Colors.white
                                                  .withValues(alpha: 0.14),
                                      width: isEditing
                                          ? 2
                                          : isSelected || isFocused
                                              ? 1.5
                                              : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.08),
                                        blurRadius: 18,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: [
                                      // Top area: thumbnail or color dot, with a
                                      // hover toolbar (desktop) / overflow button
                                      // (mobile) revealed over the bottom edge.
                                      Expanded(
                                        child: _HoverReveal(
                                          enabled: isDesktop && !isEditing,
                                          builder: (context, hovering) => Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Positioned.fill(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      const BorderRadius
                                                          .vertical(
                                                    top: Radius.circular(16.0),
                                                  ),
                                                  child:
                                                      _buildTagCardThumbnailFill(
                                                          tag, tagColor),
                                                ),
                                              ),
                                              // Desktop: floating action toolbar
                                              // that slides up + fades in on hover.
                                              if (isDesktop && !isEditing)
                                                Positioned(
                                                  left: 0,
                                                  right: 0,
                                                  // Float over the bottom edge of
                                                  // the full-bleed thumbnail.
                                                  bottom: 6,
                                                  child: Center(
                                                    child: AnimatedSlide(
                                                      offset: Offset(0,
                                                          hovering ? 0 : 0.35),
                                                      duration: const Duration(
                                                          milliseconds: 160),
                                                      curve:
                                                          Curves.easeOutCubic,
                                                      child: AnimatedOpacity(
                                                        opacity: hovering
                                                            ? 1.0
                                                            : 0.0,
                                                        duration:
                                                            const Duration(
                                                                milliseconds:
                                                                    160),
                                                        child: IgnorePointer(
                                                          ignoring: !hovering,
                                                          child: _buildTagHoverToolbar(
                                                              tag,
                                                              theme,
                                                              iconSize,
                                                              maxWidth:
                                                                  constraints
                                                                      .maxWidth),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              // Mobile: always-visible overflow
                                              if (_isMobile && !isEditing)
                                                Positioned(
                                                  top: 4,
                                                  right: 4,
                                                  child:
                                                      _buildTagOverflowButton(
                                                          tag, theme),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Bottom area: tag name
                                      Container(
                                        margin: const EdgeInsets.only(top: 1),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surface
                                              .withValues(alpha: 0.28),
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.white
                                                  .withValues(alpha: 0.12),
                                            ),
                                          ),
                                        ),
                                        child: Padding(
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
                                                              fontSize:
                                                                  fontSize,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600),
                                                          textAlign:
                                                              TextAlign.center,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      Positioned.fill(
                                                        child: Focus(
                                                          onKeyEvent: (node,
                                                                  event) =>
                                                              _handleInlineRenameKey(
                                                                  node,
                                                                  event,
                                                                  tag),
                                                          child: TextField(
                                                            controller:
                                                                _editingTagController,
                                                            autofocus: true,
                                                            textInputAction:
                                                                TextInputAction
                                                                    .done,
                                                            style: TextStyle(
                                                                fontSize:
                                                                    fontSize,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: theme
                                                                    .colorScheme
                                                                    .onSurface),
                                                            textAlign: TextAlign
                                                                .center,
                                                            maxLines: 2,
                                                            decoration:
                                                                InputDecoration(
                                                              isDense: true,
                                                              contentPadding:
                                                                  const EdgeInsets
                                                                      .symmetric(
                                                                      horizontal:
                                                                          4,
                                                                      vertical:
                                                                          2),
                                                              border:
                                                                  OutlineInputBorder(
                                                                borderSide: BorderSide(
                                                                    color: theme
                                                                        .colorScheme
                                                                        .primary,
                                                                    width: 2),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            2),
                                                              ),
                                                              enabledBorder:
                                                                  OutlineInputBorder(
                                                                borderSide: BorderSide(
                                                                    color: theme
                                                                        .colorScheme
                                                                        .primary,
                                                                    width: 2),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            2),
                                                              ),
                                                              focusedBorder:
                                                                  OutlineInputBorder(
                                                                borderSide: BorderSide(
                                                                    color: theme
                                                                        .colorScheme
                                                                        .primary,
                                                                    width: 2),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            2),
                                                              ),
                                                              filled: true,
                                                              fillColor: theme
                                                                  .colorScheme
                                                                  .surface,
                                                            ),
                                                            cursorColor: theme
                                                                .colorScheme
                                                                .primary,
                                                            onEditingComplete: () =>
                                                                _commitTagRename(
                                                                    tag),
                                                            onSubmitted: (_) =>
                                                                _commitTagRename(
                                                                    tag),
                                                            onTapOutside: (_) =>
                                                                _commitTagRename(
                                                                    tag),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              else
                                                Tooltip(
                                                  message:
                                                      'Double click to open in new tab',
                                                  child: Column(
                                                    children: [
                                                      Text(
                                                        tag,
                                                        style: TextStyle(
                                                            fontSize: fontSize,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            color: theme
                                                                .colorScheme
                                                                .onSurface),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      _buildHierarchyContext(
                                                          tag, theme,
                                                          centered: true),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
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

    return RouteUtils.showAcrylicDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(AppLocalizations.of(context)!.newTagTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: tagController,
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.enterTagName,
                  prefixIcon: const Icon(PhosphorIconsLight.hash),
                  helperText:
                      'Use parent:child format for hierarchy\ne.g. Actress:Hung or Actress:Hung,Van',
                  helperMaxLines: 3,
                  helperStyle: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
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
            ],
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

    // Parse parent:child format (e.g. "Actress:Hung" or "Actress:Hung,Van,Linh")
    if (normalizedTagName.contains(':')) {
      await _createHierarchyTag(normalizedTagName);
      return;
    }

    final hasExistingTag = _allTags.any(
      (existingTag) =>
          existingTag.toLowerCase() == normalizedTagName.toLowerCase(),
    );

    if (hasExistingTag) {
      AppToast.warning(
        context,
        AppLocalizations.of(context)!.tagAlreadyExists(normalizedTagName),
      );
      return;
    }

    _standaloneCreatedTags.add(normalizedTagName);

    try {
      final saved = await TagManager.addStandaloneTag(normalizedTagName);
      if (!saved) {
        if (mounted) {
          AppToast.error(
            context,
            AppLocalizations.of(context)!.saveTagToLocalDatabaseFailed,
          );
        }
        return;
      }
    } catch (e) {
      AppLogger.warning('Error saving standalone tag: $e');
      if (mounted) {
        AppToast.error(
          context,
          AppLocalizations.of(context)!.saveTagFailed(e.toString()),
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
      _updatePagination();
    });

    if (mounted) {
      AppToast.success(
        context,
        AppLocalizations.of(context)!.tagCreatedSuccessfully(normalizedTagName),
      );
    }
  }

  /// Create tags with parent:child hierarchy format.
  /// Supports: "Parent:Child" and "Parent:Child1,Child2,Child3"
  Future<void> _createHierarchyTag(String input) async {
    final colonIndex = input.indexOf(':');
    final parentName = input.substring(0, colonIndex).trim();
    final childrenPart = input.substring(colonIndex + 1).trim();

    if (parentName.isEmpty || childrenPart.isEmpty) {
      if (mounted) {
        AppToast.warning(context,
            'Invalid format. Use parent:child or parent:child1,child2');
      }
      return;
    }

    final childNames = childrenPart
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    if (childNames.isEmpty) {
      if (mounted) {
        AppToast.warning(context, 'No child tags specified');
      }
      return;
    }

    try {
      // Ensure parent tag exists
      final parentExists =
          _allTags.any((t) => t.toLowerCase() == parentName.toLowerCase());
      if (!parentExists) {
        await TagManager.addStandaloneTag(parentName);
        _standaloneCreatedTags.add(parentName);
      }

      // Create child tags and hierarchy relationships
      int createdCount = 0;
      for (final childName in childNames) {
        final childExists =
            _allTags.any((t) => t.toLowerCase() == childName.toLowerCase());
        if (!childExists) {
          await TagManager.addStandaloneTag(childName);
          _standaloneCreatedTags.add(childName);
        }

        final ok = await _tagHierarchyManager.addChild(parentName, childName);
        if (ok) {
          createdCount++;
        } else {
          if (mounted) {
            AppToast.warning(context,
                'Could not create relationship: $parentName -> $childName (circular reference?)');
          }
        }
      }

      await _loadAllTags();

      if (!mounted) return;

      final currentQuery = _searchController.text.trim().toLowerCase();
      if (currentQuery.isNotEmpty &&
          !parentName.toLowerCase().contains(currentQuery)) {
        _searchController.clear();
      }

      setState(() {
        _currentPage = 0;
        _focusedTag = parentName;
        _selectedTags
          ..clear()
          ..add(parentName);
        _updatePagination();
      });

      if (mounted) {
        AppToast.success(context,
            'Created hierarchy: $parentName -> ${childNames.join(", ")} ($createdCount relationships)');
      }
    } catch (e) {
      AppLogger.warning('Error creating hierarchy tag: $e');
      if (mounted) {
        AppToast.error(
            context, AppLocalizations.of(context)!.saveTagFailed(e.toString()));
      }
    }
  }

  bool _canDropTagOnParent(String childTag, String parentTag) {
    final child = childTag.trim().toLowerCase();
    final parent = parentTag.trim().toLowerCase();
    if (child.isEmpty || parent.isEmpty || child == parent) return false;
    return !_tagDescendantsContain(child, parent);
  }

  bool _tagDescendantsContain(String sourceTag, String targetTag) {
    final normalizedTarget = targetTag.trim().toLowerCase();
    final visited = <String>{};

    bool walk(String current) {
      final normalizedCurrent = current.trim().toLowerCase();
      if (!visited.add(normalizedCurrent)) return false;
      for (final child in _tagHierarchyManager.getChildren(normalizedCurrent)) {
        final normalizedChild = child.trim().toLowerCase();
        if (normalizedChild == normalizedTarget) return true;
        if (walk(normalizedChild)) return true;
      }
      return false;
    }

    return walk(sourceTag);
  }

  Future<void> _moveTagUnderParent({
    required String childTag,
    required String parentTag,
  }) async {
    if (!_canDropTagOnParent(childTag, parentTag)) {
      AppToast.warning(context, 'Cannot create circular tag hierarchy');
      return;
    }

    final oldParents = _tagHierarchyManager.getParents(childTag);
    if (oldParents.length == 1 &&
        oldParents.first.toLowerCase() == parentTag.toLowerCase()) {
      return;
    }

    final added = await _tagHierarchyManager.addChild(parentTag, childTag);
    if (!mounted) return;
    if (!added) {
      AppToast.warning(context, 'Cannot create circular tag hierarchy');
      return;
    }

    for (final oldParent in oldParents) {
      if (oldParent.toLowerCase() == parentTag.toLowerCase()) continue;
      await _tagHierarchyManager.removeChild(oldParent, childTag);
    }
    if (!mounted) return;

    setState(() {
      _treeRootsSignature = null;
      _focusedTag = childTag;
      _selectedTags
        ..clear()
        ..add(childTag);
    });
    _filterTags();
    AppToast.success(context, 'Moved "$childTag" under "$parentTag"');
  }

  void _openContainingFolder(String folderPath) {
    if (Directory(folderPath).existsSync()) {
      try {
        AppToast.info(
          context,
          '${AppLocalizations.of(context)!.openingFolder}$folderPath',
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
            // ignore: empty_catches
          } catch (e) {}
        } else {
          RouteUtils.safePopDialog(context);
        }
        // ignore: empty_catches
      } catch (e) {}
    } else {
      AppToast.warning(
        context,
        '${AppLocalizations.of(context)!.folderNotFound}$folderPath',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Manage Hierarchy Dialog ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â a StatefulWidget shown in a dialog
// ---------------------------------------------------------------------------

class _ManageHierarchyDialog extends StatefulWidget {
  final String tag;
  final TagHierarchyManager hierarchyManager;
  final List<String> allTags;
  final VoidCallback onChanged;

  const _ManageHierarchyDialog({
    required this.tag,
    required this.hierarchyManager,
    required this.allTags,
    required this.onChanged,
  });

  @override
  State<_ManageHierarchyDialog> createState() => _ManageHierarchyDialogState();
}

class _ManageHierarchyDialogState extends State<_ManageHierarchyDialog> {
  late List<String> _parents;
  late List<String> _children;
  final _addChildController = TextEditingController();
  final _setParentController = TextEditingController();
  List<String> _childSuggestions = [];
  List<String> _parentSuggestions = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _parents = widget.hierarchyManager.getParents(widget.tag);
    _children = widget.hierarchyManager.getChildren(widget.tag);
  }

  @override
  void dispose() {
    _addChildController.dispose();
    _setParentController.dispose();
    super.dispose();
  }

  void _updateChildSuggestions(String query) {
    if (query.trim().isEmpty) {
      setState(() => _childSuggestions = []);
      return;
    }
    final q = query.toLowerCase().trim();
    final suggestions = widget.allTags
        .where((t) {
          final tl = t.toLowerCase();
          return tl.contains(q) &&
              tl != widget.tag.toLowerCase() &&
              !_children.any((c) => c.toLowerCase() == tl);
        })
        .take(8)
        .toList();
    setState(() => _childSuggestions = suggestions);
  }

  void _updateParentSuggestions(String query) {
    if (query.trim().isEmpty) {
      setState(() => _parentSuggestions = []);
      return;
    }
    final q = query.toLowerCase().trim();
    final suggestions = widget.allTags
        .where((t) {
          final tl = t.toLowerCase();
          return tl.contains(q) &&
              tl != widget.tag.toLowerCase() &&
              !_parents.any((p) => p.toLowerCase() == tl);
        })
        .take(8)
        .toList();
    setState(() => _parentSuggestions = suggestions);
  }

  Future<void> _addChild(String childName) async {
    if (childName.trim().isEmpty) return;

    // Create tag if it doesn't exist
    final exists =
        widget.allTags.any((t) => t.toLowerCase() == childName.toLowerCase());
    if (!exists) {
      await TagManager.addStandaloneTag(childName.trim());
    }

    final ok =
        await widget.hierarchyManager.addChild(widget.tag, childName.trim());
    if (ok) {
      _addChildController.clear();
      _refresh();
      widget.onChanged();
      if (mounted) setState(() => _childSuggestions = []);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Cannot add "$childName" ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â circular reference or error')),
      );
    }
  }

  Future<void> _removeChild(String child) async {
    await widget.hierarchyManager.removeChild(widget.tag, child);
    _refresh();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  Future<void> _addParent(String parentName) async {
    if (parentName.trim().isEmpty) return;

    final exists =
        widget.allTags.any((t) => t.toLowerCase() == parentName.toLowerCase());
    if (!exists) {
      await TagManager.addStandaloneTag(parentName.trim());
    }

    final ok =
        await widget.hierarchyManager.addChild(parentName.trim(), widget.tag);
    if (ok) {
      _setParentController.clear();
      _refresh();
      widget.onChanged();
      if (mounted) setState(() => _parentSuggestions = []);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Cannot set "$parentName" as parent ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â circular reference or error')),
      );
    }
  }

  Future<void> _removeParent(String parent) async {
    await widget.hierarchyManager.removeChild(parent, widget.tag);
    _refresh();
    widget.onChanged();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(PhosphorIconsLight.treeStructure,
              size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Hierarchy: "${widget.tag}"',
                style: const TextStyle(fontSize: 18)),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ Parents section ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬
              Text('Parents',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: theme.colorScheme.primary,
                  )),
              const SizedBox(height: 6),
              if (_parents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('No parent tags',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      )),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _parents
                      .map((parent) => Chip(
                            avatar: Icon(PhosphorIconsLight.arrowBendUpLeft,
                                size: 14, color: theme.colorScheme.primary),
                            label: Text(parent,
                                style: const TextStyle(fontSize: 13)),
                            deleteIcon:
                                const Icon(PhosphorIconsLight.x, size: 14),
                            onDeleted: () => _removeParent(parent),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              const SizedBox(height: 6),
              // Add parent input
              _buildAutocompleteInput(
                controller: _setParentController,
                hint: 'Add parent...',
                suggestions: _parentSuggestions,
                onChanged: _updateParentSuggestions,
                onSubmit: _addParent,
              ),

              const SizedBox(height: 20),
              Divider(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 12),

              // ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ Children section ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚ÂÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬
              Text('Children',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: theme.colorScheme.tertiary,
                  )),
              const SizedBox(height: 6),
              if (_children.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('No child tags',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      )),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _children
                      .map((child) => Chip(
                            avatar: Icon(PhosphorIconsLight.treeStructure,
                                size: 14, color: theme.colorScheme.tertiary),
                            label: Text(child,
                                style: const TextStyle(fontSize: 13)),
                            deleteIcon:
                                const Icon(PhosphorIconsLight.x, size: 14),
                            onDeleted: () => _removeChild(child),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ))
                      .toList(),
                ),
              const SizedBox(height: 6),
              // Add child input
              _buildAutocompleteInput(
                controller: _addChildController,
                hint: 'Add child... (comma-separated)',
                suggestions: _childSuggestions,
                onChanged: _updateChildSuggestions,
                onSubmit: (value) async {
                  // Support comma-separated
                  final names = value
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty);
                  for (final name in names) {
                    await _addChild(name);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }

  Widget _buildAutocompleteInput({
    required TextEditingController controller,
    required String hint,
    required List<String> suggestions,
    required ValueChanged<String> onChanged,
    required Future<void> Function(String) onSubmit,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            suffixIcon: IconButton(
              icon: const Icon(PhosphorIconsLight.plus, size: 18),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  onSubmit(text);
                }
              },
              visualDensity: VisualDensity.compact,
            ),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: onChanged,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              onSubmit(value.trim());
            }
          },
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = suggestions[index];
                return InkWell(
                  onTap: () => onSubmit(suggestion),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(PhosphorIconsLight.tag,
                            size: 14,
                            color: TagColorManager.instance
                                .getTagColor(suggestion)),
                        const SizedBox(width: 8),
                        Text(suggestion, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Compact row content used inside the tag tree view. Renders the tag's
/// thumbnail + name + a hierarchy badge if the tag is a parent or child.
/// All gestures (tap, double-tap, secondary) are handled by the
/// `GenericTreeView` shell, so this widget is purely visual.
class _TagTreeRowContent extends StatelessWidget {
  final String tag;
  final Color tagColor;
  final double thumbnailSize;
  final double fontSize;
  final double spacing;
  final Widget Function(double size) buildThumbnail;

  const _TagTreeRowContent({
    Key? key,
    required this.tag,
    required this.tagColor,
    required this.thumbnailSize,
    required this.fontSize,
    required this.spacing,
    required this.buildThumbnail,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        buildThumbnail(thumbnailSize),
        SizedBox(width: spacing),
        Expanded(
          child: Text(
            tag,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Wraps a subtree with a local hover state so that hovering a single grid
/// card only rebuilds that card instead of the whole grid.
///
/// When [enabled] is false (e.g. on mobile, or while inline-renaming) the
/// builder is invoked once with `hovering == false` and no `MouseRegion` is
/// attached.
class _HoverReveal extends StatefulWidget {
  final bool enabled;
  final Widget Function(BuildContext context, bool hovering) builder;

  const _HoverReveal({
    Key? key,
    required this.enabled,
    required this.builder,
  }) : super(key: key);

  @override
  State<_HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<_HoverReveal> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.builder(context, false);
    }

    return MouseRegion(
      onEnter: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      child: widget.builder(context, _hovering),
    );
  }
}
