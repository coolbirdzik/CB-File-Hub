part of 'tabbed_folder_list_screen.dart';

extension _TabbedFolderListMobileActions on _TabbedFolderListScreenState {
  // Register mobile actions controller to connect mobile action buttons with this screen
  void _registerMobileActionsControllerImpl() {
    final controller = MobileFileActionsController.forTab(widget.tabId);

    // Register callbacks
    controller.onSearchPressed = () => _toggleSearchBar(context);
    controller.onSearchSubmitted = (query) => _handleMobileSearch(query);
    controller.onSortOptionSelected = (option) {
      _folderListBloc.add(SetSortOption(option, folderPath: _currentPath));
    };
    controller.onViewModeToggled = _setViewMode;
    controller.onBack = _handleMouseBackButton;
    controller.onForward = _handleMouseForwardButton;
    controller.onRefresh = _refreshFileList;
    controller.onGridSizePressed = () => SharedActionBar.showGridSizeDialog(
      context,
      currentGridSize: _folderListBloc.state.gridZoomLevel,
      onApply: handleGridZoomChange,
      sizeMode: GridSizeMode.referenceWidth,
    );
    controller.onSelectionModeToggled = _toggleSelectionMode;
    controller.onMasonryToggled = () {
      _setMasonryLayout(controller.isMasonryLayout);
    };
    controller.onManageTagsPressed = () {
      tab_components.showManageTagsDialog(
        context,
        _folderListBloc.state.allTags.toList(),
        _folderListBloc.state.currentPath.path,
      );
    };
    // Register create folder callback - delegates to FolderContextMenu's create folder dialog
    controller.onCreateFolder = () => _showMobileCreateFolderDialog();
    controller.onAllowFileExtensionRenameChanged = _setAllowFileExtensionRename;
    controller.folderListBloc = _folderListBloc;
    controller.allowFileExtensionRename = _allowFileExtensionRename;
    controller.isMasonryLayout = _isMasonryLayout;
    // Set initial state
    controller.currentSortOption = _folderListBloc.state.sortOption;
    controller.currentViewMode = _folderListBloc.state.viewMode;
    controller.currentGridSize = _folderListBloc.state.gridZoomLevel;
    controller.currentPath = _currentPath;
    controller.actionBarProfile = _isDrivesPathValue(_currentPath)
        ? MobileActionBarProfile.drivesMinimal
        : MobileActionBarProfile.full;

    // Update controller state when bloc state changes
    _folderListBloc.stream.listen((state) {
      controller.folderListBloc = _folderListBloc;
      controller.allowFileExtensionRename = _allowFileExtensionRename;
      controller.currentSortOption = state.sortOption;
      controller.currentViewMode = state.viewMode;
      controller.currentGridSize = state.gridZoomLevel;
      controller.currentPath = _currentPath;
      controller.actionBarProfile = _isDrivesPathValue(_currentPath)
          ? MobileActionBarProfile.drivesMinimal
          : MobileActionBarProfile.full;
    });
  }

  // Handle mobile inline search
  void _handleMobileSearchImpl(String? query) {
    if (query == null || query.isEmpty) {
      // Clear search
      _folderListBloc.add(const ClearSearchAndFilters());
      return;
    }

    // Get recursive setting from controller
    final controller = MobileFileActionsController.forTab(widget.tabId);
    final isRecursive = controller.isRecursiveSearch;

    // Check if it's a tag search (contains # character)
    if (query.contains('#')) {
      // Extract tags from query
      final tags = query
          .split(' ')
          .where((word) => word.startsWith('#'))
          .map((tag) => tag.substring(1).trim())
          .where((tag) => tag.isNotEmpty)
          .toList();

      if (tags.isEmpty) return;

      // Search by tag (local only for mobile, no recursive for tags)
      if (tags.length == 1) {
        _folderListBloc.add(SearchByTag(tags.first));
      } else {
        _folderListBloc.add(SearchByMultipleTags(tags));
      }
    } else {
      // Search by filename with recursive option
      _folderListBloc.add(SearchByFileName(query, recursive: isRecursive));
    }
  }

  /// Show create folder dialog for mobile
  void _showMobileCreateFolderDialog() async {
    await RouteUtils.showAcrylicDialog(
      context: context,
      builder: (dialogContext) => _MobileCreateFolderDialog(
        onCreateFolder: (folderName) => _createNewFolder(folderName),
      ),
    );
  }

  /// Create a new folder
  Future<void> _createNewFolder(String folderName) async {
    if (_currentPath.isEmpty) return;

    final toast = AppToast.capture(context);
    try {
      final newFolderPath = '$_currentPath${Platform.pathSeparator}$folderName';
      await Directory(newFolderPath).create(recursive: true);
      _folderListBloc.add(FolderListRefresh(_currentPath));
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      toast.error(l10n.errorCreatingFolder(e.toString()));
    }
  }
}

class _MobileCreateFolderDialog extends StatefulWidget {
  final Future<void> Function(String folderName) onCreateFolder;

  const _MobileCreateFolderDialog({required this.onCreateFolder});

  @override
  State<_MobileCreateFolderDialog> createState() =>
      _MobileCreateFolderDialogState();
}

class _MobileCreateFolderDialogState extends State<_MobileCreateFolderDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final folderName = _nameController.text.trim();
    if (folderName.isEmpty) {
      return;
    }

    Navigator.of(context).pop();
    await widget.onCreateFolder(folderName);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Folder'),
      content: TextField(
        controller: _nameController,
        decoration: const InputDecoration(
          labelText: 'Folder name',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
