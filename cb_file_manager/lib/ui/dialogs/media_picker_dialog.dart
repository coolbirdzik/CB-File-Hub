// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/platform_paths.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/components/common/skeleton.dart';
import 'package:cb_file_manager/ui/dialogs/video_frame_picker_dialog.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:path/path.dart' as path;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';

typedef MediaPickerFileMatcher = bool Function(String path);

class MediaPickerFilterOption {
  final String id;
  final String label;
  final MediaPickerFileMatcher matches;

  const MediaPickerFilterOption({
    required this.id,
    required this.label,
    required this.matches,
  });
}

enum MediaPickerViewMode {
  grid,
  list,
}

enum MediaPickerSort {
  name,
  modified,
}

class MediaPickerConfig {
  final String initialPath;
  final String? rootPath;
  final bool restrictToRoot;
  final String? title;
  final String? emptyMessage;
  final MediaPickerFileMatcher? fileFilter;
  final List<MediaPickerFilterOption> filters;
  final String? initialFilterId;
  final MediaPickerViewMode initialViewMode;
  final MediaPickerSort initialSort;
  final bool showSearch;
  final bool showSort;
  final bool showViewToggle;
  final bool showHidden;
  final bool showFolders;
  final bool showFiles;

  /// When true, the modal shows a mode toggle that lets the user browse the
  /// filesystem or search files by tag. Selecting a tagged file returns its
  /// path just like a browsed file.
  final bool enableTagSearch;

  /// When set (and [enableTagSearch] is true), the picker opens directly in tag
  /// search mode with this tag pre-filled and searched, so the user immediately
  /// sees the files carrying that tag instead of the folder browser.
  final String? initialTagQuery;

  /// When true, choosing a video file opens the [VideoFramePickerDialog] so the
  /// user can pick a specific frame; the modal then returns the extracted
  /// frame's path instead of the video path. Non-video selections are returned
  /// as-is.
  final bool extractVideoFrame;

  /// When true (desktop only), shows a Windows-Explorer-style left rail listing
  /// quick-access folders and drives ("This PC"). Ignored when [restrictToRoot]
  /// is set, since browsing is sandboxed to a single folder in that case.
  final bool showSidebar;

  const MediaPickerConfig({
    required this.initialPath,
    this.rootPath,
    this.restrictToRoot = false,
    this.title,
    this.emptyMessage,
    this.fileFilter,
    this.filters = const [],
    this.initialFilterId,
    this.initialViewMode = MediaPickerViewMode.grid,
    this.initialSort = MediaPickerSort.name,
    this.showSearch = true,
    this.showSort = true,
    this.showViewToggle = true,
    this.showHidden = false,
    this.showFolders = true,
    this.showFiles = true,
    this.enableTagSearch = false,
    this.initialTagQuery,
    this.extractVideoFrame = false,
    this.showSidebar = true,
  });
}

/// The two browsing modes the picker can operate in.
enum MediaPickerMode {
  /// Navigate the filesystem folder by folder.
  browse,

  /// Search files across the device by tag.
  tags,
}

/// A single entry in the picker's left rail (quick-access folder or drive).
class _SidebarEntry {
  final String label;
  final String path;
  final IconData icon;
  final bool requiresAdmin;

  const _SidebarEntry({
    required this.label,
    required this.path,
    required this.icon,
    this.requiresAdmin = false,
  });
}

Future<String?> showMediaPickerDialog(
  BuildContext context,
  MediaPickerConfig config,
) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final mediaQuery = MediaQuery.of(dialogContext);
      final dialogWidth = mediaQuery.size.width * 0.92;
      final dialogHeight = mediaQuery.size.height * 0.78;

      return AlertDialog(
        title: Text(
            config.title ?? AppLocalizations.of(dialogContext)!.browseFiles),
        content: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: _MediaPickerDialog(
            config: config,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child:
                Text(AppLocalizations.of(dialogContext)!.cancel.toUpperCase()),
          ),
        ],
      );
    },
  );
}

class _MediaPickerDialog extends StatefulWidget {
  final MediaPickerConfig config;

  const _MediaPickerDialog({
    required this.config,
  });

  @override
  State<_MediaPickerDialog> createState() => _MediaPickerDialogState();
}

class _MediaPickerDialogState extends State<_MediaPickerDialog> {
  late String _currentPath;
  late MediaPickerViewMode _viewMode;
  late MediaPickerSort _sortBy;
  String _searchQuery = '';
  String? _activeFilterId;
  bool _isLoading = false;
  String? _errorMessage;
  List<Directory> _directories = [];
  List<File> _files = [];
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  final FocusNode _pathFocusNode = FocusNode();
  String? _rootPath;

  // Tag-search mode state.
  MediaPickerMode _mode = MediaPickerMode.browse;
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _tagFocusNode = FocusNode();
  List<String> _allTags = [];
  bool _tagGlobalSearch = true;
  String? _activeTagQuery;
  bool _isTagSearching = false;
  List<File> _tagResults = [];
  bool _extractingFrame = false;

  // Sidebar (Windows-Explorer-style left rail) state.
  List<_SidebarEntry> _quickAccess = [];
  List<_SidebarEntry> _drives = [];

  /// Whether the left rail should be shown. Only on desktop, when enabled by
  /// config, and when not sandboxed to a single root folder.
  bool get _showSidebar =>
      widget.config.showSidebar &&
      !_restrictToRoot &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _currentPath = path.normalize(widget.config.initialPath);
    _pathController.text = _currentPath;
    _rootPath = widget.config.rootPath != null
        ? path.normalize(widget.config.rootPath!)
        : null;
    _viewMode = widget.config.initialViewMode;
    _sortBy = widget.config.initialSort;
    if (widget.config.filters.isNotEmpty) {
      _activeFilterId =
          widget.config.initialFilterId ?? widget.config.filters.first.id;
    }
    _loadEntries();
    if (widget.config.enableTagSearch) {
      _loadAllTags();
      final initialTag = widget.config.initialTagQuery?.trim();
      if (initialTag != null && initialTag.isNotEmpty) {
        // Open directly in tag search mode showing the given tag's files.
        _mode = MediaPickerMode.tags;
        _tagController.text = initialTag;
        _performTagSearch(initialTag);
      }
    }
    if (_showSidebar) {
      _loadSidebar();
    }
  }

  Future<void> _loadSidebar() async {
    // Quick-access folders (best-effort; skip any that don't resolve).
    final quick = <_SidebarEntry>[];
    Future<void> addQuick(
      String label,
      IconData icon,
      Future<String> Function() resolve,
    ) async {
      try {
        final p = await resolve();
        if (p.isNotEmpty && Directory(p).existsSync()) {
          quick.add(_SidebarEntry(
            label: label,
            path: path.normalize(p),
            icon: icon,
          ));
        }
      } catch (_) {
        // Ignore unresolved quick-access entries.
      }
    }

    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];

    void addHomeChild(String folder, String label, IconData icon) {
      if (home == null || home.isEmpty) return;
      final p = path.join(home, folder);
      if (Directory(p).existsSync()) {
        quick.add(_SidebarEntry(
          label: label,
          path: path.normalize(p),
          icon: icon,
        ));
      }
    }

    if (home != null && home.isNotEmpty && Directory(home).existsSync()) {
      quick.add(_SidebarEntry(
        label: 'Home',
        path: path.normalize(home),
        icon: PhosphorIconsLight.house,
      ));
    }
    addHomeChild('Desktop', 'Desktop', PhosphorIconsLight.desktop);
    addHomeChild('Documents', 'Documents', PhosphorIconsLight.fileText);
    await addQuick(
      'Downloads',
      PhosphorIconsLight.downloadSimple,
      PlatformPaths.getDownloadsPath,
    );
    await addQuick(
      'Pictures',
      PhosphorIconsLight.image,
      PlatformPaths.getPicturesPath,
    );
    addHomeChild('Videos', 'Videos', PhosphorIconsLight.filmSlate);
    addHomeChild('Music', 'Music', PhosphorIconsLight.musicNotes);

    // Drives / storage volumes.
    List<_SidebarEntry> drives = [];
    try {
      final locations = await getAllStorageLocations();
      drives = locations.map((dir) {
        return _SidebarEntry(
          label: _driveLabel(dir),
          path: dir.path,
          icon: _driveIcon(dir),
          requiresAdmin: dir.requiresAdmin,
        );
      }).toList();
    } catch (e) {
      debugPrint('MediaPickerDialog: failed to load drives: $e');
    }

    if (!mounted) return;
    setState(() {
      _quickAccess = quick;
      _drives = drives;
    });
  }

  String _driveLabel(Directory drive) {
    var p = drive.path;
    if (p.length > 1 && p.endsWith(Platform.pathSeparator)) {
      p = p.substring(0, p.length - 1);
    }
    if (Platform.isWindows && p.contains(':')) {
      final letter = p.split(r'\')[0];
      return p.startsWith('C:') ? '$letter (System)' : '$letter (Drive)';
    }
    return p;
  }

  IconData _driveIcon(Directory drive) {
    if (Platform.isWindows && drive.path.startsWith('C:')) {
      return PhosphorIconsLight.desktop;
    }
    return PhosphorIconsLight.hardDrives;
  }

  Future<void> _loadAllTags() async {
    try {
      final tags = await TagManager.getAllUniqueTags('');
      if (!mounted) return;
      setState(() {
        _allTags = tags.toList()..sort();
      });
    } catch (e) {
      debugPrint('MediaPickerDialog: failed to load tags: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tagController.dispose();
    _tagFocusNode.dispose();
    _pathController.dispose();
    _pathFocusNode.dispose();
    super.dispose();
  }

  String _normalizePath(String value) {
    final normalized = path.normalize(value);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  bool _isWithinRoot(String candidate) {
    if (_rootPath == null) {
      return true;
    }

    final root = _normalizePath(_rootPath!);
    final normalizedCandidate = _normalizePath(candidate);
    if (normalizedCandidate == root) {
      return true;
    }

    return path.isWithin(root, normalizedCandidate);
  }

  bool get _restrictToRoot => widget.config.restrictToRoot && _rootPath != null;

  bool get _canNavigateUp {
    final parent = path.dirname(_currentPath);
    if (parent == _currentPath) {
      return false;
    }

    if (!_restrictToRoot) {
      return true;
    }

    return _isWithinRoot(parent);
  }

  void _navigateToDirectory(String dirPath) {
    final normalized = path.normalize(dirPath);
    if (_restrictToRoot && !_isWithinRoot(normalized)) {
      return;
    }
    setState(() {
      _currentPath = normalized;
      _pathController.text = normalized;
    });
    _loadEntries();
  }

  void _navigateUp() {
    if (!_canNavigateUp) {
      return;
    }
    _navigateToDirectory(path.dirname(_currentPath));
  }

  /// Navigate to a path typed/pasted into the path bar. Trims surrounding
  /// quotes and whitespace so paths pasted from Windows Explorer (which wraps
  /// them in quotes) work. A typed file path is treated as selecting that file;
  /// a typed folder path navigates into it.
  Future<void> _submitTypedPath(String value) async {
    var trimmed = value.trim();
    if (trimmed.startsWith('"') &&
        trimmed.endsWith('"') &&
        trimmed.length >= 2) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
    if (trimmed.isEmpty) {
      _pathController.text = _currentPath;
      return;
    }

    final normalized = path.normalize(trimmed);
    final type = FileSystemEntity.typeSync(normalized);

    void reject() {
      if (!mounted) return;
      setState(() {
        _pathController.text = _currentPath;
        _errorMessage = AppLocalizations.of(context)!.pathNotAccessible;
      });
    }

    // A typed file path: honor it like selecting the file.
    if (type == FileSystemEntityType.file) {
      final filter = widget.config.fileFilter;
      if (filter != null && !filter(normalized)) {
        reject();
        return;
      }
      if (_restrictToRoot && !_isWithinRoot(path.dirname(normalized))) {
        reject();
        return;
      }
      _pathFocusNode.unfocus();
      await _selectFile(File(normalized));
      return;
    }

    if (type != FileSystemEntityType.directory) {
      reject();
      return;
    }

    if (_restrictToRoot && !_isWithinRoot(normalized)) {
      reject();
      return;
    }

    _pathFocusNode.unfocus();
    _navigateToDirectory(normalized);
  }

  Future<void> _loadEntries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final directory = Directory(_currentPath);
      if (!await directory.exists()) {
        setState(() {
          _directories = [];
          _files = [];
          _isLoading = false;
          _errorMessage = AppLocalizations.of(context)!.pathNotAccessible;
        });
        return;
      }

      final entities = await directory.list(followLinks: false).toList();
      final dirs = <Directory>[];
      final files = <File>[];

      for (final entity in entities) {
        final name = path.basename(entity.path);
        if (!widget.config.showHidden && name.startsWith('.')) {
          continue;
        }

        if (entity is Directory) {
          if (widget.config.showFolders) {
            dirs.add(entity);
          }
          continue;
        }

        if (entity is File) {
          if (!widget.config.showFiles) {
            continue;
          }
          final filter = widget.config.fileFilter;
          if (filter != null && !filter(entity.path)) {
            continue;
          }
          files.add(entity);
        }
      }

      _sortEntries(dirs, files);

      if (mounted) {
        setState(() {
          _directories = dirs;
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('MediaPickerDialog: Error loading directory: $e');
      if (mounted) {
        setState(() {
          _directories = [];
          _files = [];
          _isLoading = false;
          _errorMessage = AppLocalizations.of(context)!.pathNotAccessible;
        });
      }
    }
  }

  void _sortEntries(List<Directory> dirs, List<File> files) {
    int compareByName(FileSystemEntity a, FileSystemEntity b) {
      return path
          .basename(a.path)
          .toLowerCase()
          .compareTo(path.basename(b.path).toLowerCase());
    }

    DateTime modified(FileSystemEntity entity) {
      try {
        return entity.statSync().modified;
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    }

    switch (_sortBy) {
      case MediaPickerSort.name:
        dirs.sort(compareByName);
        files.sort(compareByName);
        break;
      case MediaPickerSort.modified:
        dirs.sort((a, b) => modified(b).compareTo(modified(a)));
        files.sort((a, b) => modified(b).compareTo(modified(a)));
        break;
    }
  }

  MediaPickerFilterOption? _activeFilter() {
    if (widget.config.filters.isEmpty) {
      return null;
    }
    final match = widget.config.filters
        .where((option) => option.id == _activeFilterId)
        .toList();
    return match.isNotEmpty ? match.first : widget.config.filters.first;
  }

  bool _matchesSearch(FileSystemEntity entity) {
    if (_searchQuery.isEmpty) {
      return true;
    }
    return path
        .basename(entity.path)
        .toLowerCase()
        .contains(_searchQuery.toLowerCase());
  }

  bool _matchesFilter(File file) {
    final filter = _activeFilter();
    if (filter == null) {
      return true;
    }
    return filter.matches(file.path);
  }

  Future<void> _performTagSearch(String tag) async {
    final query = tag.trim();
    if (query.isEmpty) {
      return;
    }

    setState(() {
      _isTagSearching = true;
      _activeTagQuery = query;
      _errorMessage = null;
    });

    try {
      final entities = _tagGlobalSearch
          ? await TagManager.findFilesByTagGlobally(query)
          : await TagManager.findFilesByTag(_currentPath, query);

      final files = <File>[];
      for (final entity in entities) {
        if (entity is File) {
          final f = entity;
          final filter = widget.config.fileFilter;
          if (filter != null && !filter(f.path)) {
            continue;
          }
          if (!_matchesFilter(f)) {
            continue;
          }
          files.add(f);
        }
      }

      files.sort((a, b) => path
          .basename(a.path)
          .toLowerCase()
          .compareTo(path.basename(b.path).toLowerCase()));

      if (!mounted) return;
      setState(() {
        _tagResults = files;
        _isTagSearching = false;
      });
    } catch (e) {
      debugPrint('MediaPickerDialog: tag search failed: $e');
      if (!mounted) return;
      setState(() {
        _tagResults = [];
        _isTagSearching = false;
      });
    }
  }

  /// Handles a file selection. When [MediaPickerConfig.extractVideoFrame] is on
  /// and the file is a video, opens the frame picker and returns the extracted
  /// frame path instead of the video path.
  Future<void> _selectFile(File file) async {
    final filePath = file.path;

    if (widget.config.extractVideoFrame &&
        VideoThumbnailHelper.isSupportedVideoFormat(filePath)) {
      if (_extractingFrame) return;
      setState(() => _extractingFrame = true);
      try {
        final framePath = await VideoFramePickerDialog.show(context, filePath);
        if (!mounted) return;
        setState(() => _extractingFrame = false);
        if (framePath == null) {
          // User cancelled the frame picker; keep the browser open.
          return;
        }
        if (mounted) {
          Navigator.pop(context, framePath);
        }
      } catch (e) {
        debugPrint('MediaPickerDialog: frame extraction failed: $e');
        if (mounted) {
          setState(() => _extractingFrame = false);
        }
      }
      return;
    }

    Navigator.pop(context, filePath);
  }

  @override
  Widget build(BuildContext context) {
    final visibleDirs =
        _directories.where(_matchesSearch).toList(growable: false);
    final visibleFiles = _files
        .where((file) => _matchesSearch(file) && _matchesFilter(file))
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width < 520
            ? 2
            : width < 820
                ? 3
                : 4;

        final inTagMode = _mode == MediaPickerMode.tags;
        // Show the rail only in browse mode and when there is room for it.
        final showSidebar = _showSidebar && !inTagMode && width >= 640;

        final mainArea = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.config.enableTagSearch) ...[
              _buildModeToggle(context),
              const SizedBox(height: 8),
            ],
            if (inTagMode)
              _buildTagToolbar(context)
            else ...[
              _buildPathBar(context),
              const SizedBox(height: 8),
              _buildToolbar(context),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: inTagMode
                  ? _buildTagContent(context, crossAxisCount)
                  : _isLoading
                      ? Skeleton(
                          type: _viewMode == MediaPickerViewMode.grid
                              ? SkeletonType.grid
                              : SkeletonType.list,
                          crossAxisCount: crossAxisCount,
                          itemCount: 12,
                        )
                      : _buildContent(
                          context,
                          visibleDirs,
                          visibleFiles,
                          crossAxisCount,
                        ),
            ),
          ],
        );

        if (!showSidebar) {
          return mainArea;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 220,
              child: _buildSidebar(context),
            ),
            const SizedBox(width: 12),
            const VerticalDivider(width: 1),
            const SizedBox(width: 12),
            Expanded(child: mainArea),
          ],
        );
      },
    );
  }

  Widget _buildModeToggle(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SegmentedButton<MediaPickerMode>(
      segments: [
        ButtonSegment(
          value: MediaPickerMode.browse,
          icon: const Icon(PhosphorIconsLight.folder, size: 18),
          label: Text(l10n.browseFiles),
        ),
        ButtonSegment(
          value: MediaPickerMode.tags,
          icon: const Icon(PhosphorIconsLight.tag, size: 18),
          label: Text(l10n.searchByTags),
        ),
      ],
      selected: {_mode},
      showSelectedIcon: false,
      onSelectionChanged: (selection) {
        setState(() {
          _mode = selection.first;
        });
      },
    );
  }

  /// Windows-Explorer-style left rail: quick-access folders + drives.
  Widget _buildSidebar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Container(
      width: 200,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.only(right: 8),
        children: [
          if (_quickAccess.isNotEmpty) ...[
            _SectionHeader(label: l10n.quickAccess),
            ..._quickAccess.map(_buildSidebarTile),
            const SizedBox(height: 8),
          ],
          _SectionHeader(label: l10n.thisPC),
          if (_drives.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l10n.loading,
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            ..._drives.map(_buildSidebarTile),
        ],
      ),
    );
  }

  Widget _buildSidebarTile(_SidebarEntry entry) {
    final selected = _normalizePath(entry.path) == _normalizePath(_currentPath);
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      selected: selected,
      selectedTileColor:
          theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      leading: Icon(entry.icon, size: 20),
      title: Text(
        entry.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: entry.requiresAdmin
          ? Text(
              AppLocalizations.of(context)!.requiresAdminPrivileges,
              style: TextStyle(
                fontSize: 10,
                color: theme.colorScheme.error,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      onTap: () => _navigateToDirectory(entry.path),
    );
  }

  Widget _buildPathBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        IconButton(
          onPressed: _canNavigateUp ? _navigateUp : null,
          tooltip: l10n.parentFolder,
          icon: const Icon(PhosphorIconsLight.arrowUp),
        ),
        Expanded(
          child: TextField(
            controller: _pathController,
            focusNode: _pathFocusNode,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              hintText: _currentPath,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              suffixIcon: IconButton(
                onPressed: () => _submitTypedPath(_pathController.text),
                tooltip: l10n.open,
                icon: const Icon(PhosphorIconsLight.arrowRight, size: 18),
              ),
            ),
            onSubmitted: _submitTypedPath,
          ),
        ),
        IconButton(
          onPressed: _loadEntries,
          tooltip: l10n.refresh,
          icon: const Icon(PhosphorIconsLight.arrowsClockwise),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showFilters = widget.config.filters.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.config.showSearch)
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value.trim();
              });
            },
            decoration: InputDecoration(
              hintText: l10n.search,
              prefixIcon: const Icon(PhosphorIconsLight.magnifyingGlass),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(PhosphorIconsLight.x),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
              isDense: true,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.config.showSort)
              CbSelect<MediaPickerSort>(
                value: _sortBy,
                onChanged: (value) {
                  setState(() {
                    _sortBy = value;
                    _sortEntries(_directories, _files);
                  });
                },
                items: [
                  CbSelectItem(
                    value: MediaPickerSort.name,
                    label: l10n.sortByName,
                  ),
                  CbSelectItem(
                    value: MediaPickerSort.modified,
                    label: l10n.sortByDate,
                  ),
                ],
              ),
            if (widget.config.showViewToggle)
              ToggleButtons(
                isSelected: [
                  _viewMode == MediaPickerViewMode.grid,
                  _viewMode == MediaPickerViewMode.list,
                ],
                onPressed: (index) {
                  setState(() {
                    _viewMode = index == 0
                        ? MediaPickerViewMode.grid
                        : MediaPickerViewMode.list;
                  });
                },
                borderRadius: BorderRadius.circular(16.0),
                constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
                children: const [
                  Icon(PhosphorIconsLight.squaresFour),
                  Icon(PhosphorIconsLight.listBullets),
                ],
              ),
          ],
        ),
        if (showFilters) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.config.filters.map((filter) {
              return ChoiceChip(
                label: Text(filter.label),
                selected: filter.id == _activeFilterId,
                onSelected: (selected) {
                  if (!selected) {
                    return;
                  }
                  setState(() {
                    _activeFilterId = filter.id;
                  });
                },
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Directory> directories,
    List<File> files,
    int crossAxisCount,
  ) {
    final l10n = AppLocalizations.of(context)!;
    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    if (directories.isEmpty && files.isEmpty) {
      final emptyMessage = _searchQuery.isNotEmpty
          ? l10n.noFilesMatchFilter(_searchQuery)
          : (widget.config.emptyMessage ?? l10n.emptyFolder);
      return Center(
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
        ),
      );
    }

    return CustomScrollView(
      cacheExtent: 600,
      slivers: [
        if (directories.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(label: l10n.folders),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final directory = directories[index];
                return _DirectoryTile(
                  name: path.basename(directory.path),
                  onTap: () => _navigateToDirectory(directory.path),
                );
              },
              childCount: directories.length,
            ),
          ),
        ],
        if (files.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionHeader(label: l10n.files),
          ),
          _viewMode == MediaPickerViewMode.grid
              ? SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.86,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final file = files[index];
                      return _FileGridTile(
                        file: file,
                        onTap: () => _selectFile(file),
                      );
                    },
                    childCount: files.length,
                  ),
                )
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final file = files[index];
                      return _FileListTile(
                        file: file,
                        onTap: () => _selectFile(file),
                      );
                    },
                    childCount: files.length,
                  ),
                ),
        ],
      ],
    );
  }

  Widget _buildTagToolbar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final suggestions = _tagController.text.trim().isEmpty
        ? _allTags
        : _allTags
            .where((tag) => tag
                .toLowerCase()
                .contains(_tagController.text.trim().toLowerCase()))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: RawAutocomplete<String>(
                textEditingController: _tagController,
                focusNode: _tagFocusNode,
                optionsBuilder: (value) {
                  final query = value.text.trim().toLowerCase();
                  if (query.isEmpty) {
                    return _allTags;
                  }
                  return _allTags
                      .where((tag) => tag.toLowerCase().contains(query));
                },
                onSelected: (selection) {
                  _tagController.text = selection;
                  _performTagSearch(selection);
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: l10n.searchByTags,
                      prefixIcon: const Icon(PhosphorIconsLight.tag),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                controller.clear();
                                setState(() {
                                  _activeTagQuery = null;
                                  _tagResults = [];
                                });
                              },
                              icon: const Icon(PhosphorIconsLight.x),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (value) => _performTagSearch(value),
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  final items = options.toList();
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxHeight: 240, maxWidth: 360),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final option = items[index];
                            return ListTile(
                              dense: true,
                              leading:
                                  const Icon(PhosphorIconsLight.tag, size: 18),
                              title: Text(option),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: l10n.search,
              onPressed: () => _performTagSearch(_tagController.text),
              icon: const Icon(PhosphorIconsLight.magnifyingGlass),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.searchInSubfolders),
                value: _tagGlobalSearch,
                onChanged: (value) {
                  setState(() {
                    _tagGlobalSearch = value;
                  });
                  if (_activeTagQuery != null) {
                    _performTagSearch(_activeTagQuery!);
                  }
                },
              ),
            ),
            if (widget.config.showViewToggle)
              ToggleButtons(
                isSelected: [
                  _viewMode == MediaPickerViewMode.grid,
                  _viewMode == MediaPickerViewMode.list,
                ],
                onPressed: (index) {
                  setState(() {
                    _viewMode = index == 0
                        ? MediaPickerViewMode.grid
                        : MediaPickerViewMode.list;
                  });
                },
                borderRadius: BorderRadius.circular(16.0),
                constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
                children: const [
                  Icon(PhosphorIconsLight.squaresFour),
                  Icon(PhosphorIconsLight.listBullets),
                ],
              ),
          ],
        ),
        if (_activeTagQuery == null && suggestions.isNotEmpty) ...[
          const SizedBox(height: 4),
          _SectionHeader(label: l10n.suggestedTags),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tag = suggestions[index];
                return ActionChip(
                  avatar: const Icon(PhosphorIconsLight.tag, size: 16),
                  label: Text(tag),
                  onPressed: () {
                    _tagController.text = tag;
                    _performTagSearch(tag);
                  },
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTagContent(BuildContext context, int crossAxisCount) {
    final l10n = AppLocalizations.of(context)!;

    if (_isTagSearching) {
      return Skeleton(
        type: _viewMode == MediaPickerViewMode.grid
            ? SkeletonType.grid
            : SkeletonType.list,
        crossAxisCount: crossAxisCount,
        itemCount: 12,
      );
    }

    if (_activeTagQuery == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsLight.tag,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _allTags.isEmpty ? l10n.noMatchingTags : l10n.searchByTags,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_tagResults.isEmpty) {
      return Center(
        child: Text(
          l10n.noFilesWithTag,
          textAlign: TextAlign.center,
        ),
      );
    }

    final files = _tagResults;
    return CustomScrollView(
      cacheExtent: 600,
      slivers: [
        SliverToBoxAdapter(
          child: _SectionHeader(
            label: '${l10n.files} · ${files.length} ${l10n.results}',
          ),
        ),
        _viewMode == MediaPickerViewMode.grid
            ? SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.86,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final file = files[index];
                    return _FileGridTile(
                      file: file,
                      onTap: () => _selectFile(file),
                    );
                  },
                  childCount: files.length,
                ),
              )
            : SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final file = files[index];
                    return _FileListTile(
                      file: file,
                      onTap: () => _selectFile(file),
                    );
                  },
                  childCount: files.length,
                ),
              ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.secondary,
            ),
      ),
    );
  }
}

class _DirectoryTile extends StatelessWidget {
  final String name;
  final VoidCallback onTap;

  const _DirectoryTile({
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(PhosphorIconsLight.folder, color: Colors.amber),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(PhosphorIconsLight.caretRight),
      onTap: onTap,
    );
  }
}

class _FileGridTile extends StatelessWidget {
  final File file;
  final VoidCallback onTap;

  const _FileGridTile({
    required this.file,
    required this.onTap,
  });

  bool get _isVideo => VideoThumbnailHelper.isSupportedVideoFormat(file.path);

  bool get _isImage => FileTypeUtils.isImageFile(file.path);

  @override
  Widget build(BuildContext context) {
    final fileName = path.basename(file.path);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: _FilePreview(
                file: file,
                isVideo: _isVideo,
                isImage: _isImage,
                previewSize: 180,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  final File file;
  final VoidCallback onTap;

  const _FileListTile({
    required this.file,
    required this.onTap,
  });

  bool get _isVideo => VideoThumbnailHelper.isSupportedVideoFormat(file.path);

  bool get _isImage => FileTypeUtils.isImageFile(file.path);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fileName = path.basename(file.path);
    final typeLabel = _isVideo
        ? l10n.video
        : _isImage
            ? l10n.image
            : l10n.file;

    return ListTile(
      dense: true,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: SizedBox(
          width: 56,
          height: 56,
          child: _FilePreview(
            file: file,
            isVideo: _isVideo,
            isImage: _isImage,
            previewSize: 80,
          ),
        ),
      ),
      title: Text(
        fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(typeLabel),
      onTap: onTap,
    );
  }
}

class _FilePreview extends StatelessWidget {
  final File file;
  final bool isVideo;
  final bool isImage;
  final double previewSize;

  const _FilePreview({
    required this.file,
    required this.isVideo,
    required this.isImage,
    required this.previewSize,
  });

  @override
  Widget build(BuildContext context) {
    if (isImage) {
      final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final cacheSize = (previewSize * devicePixelRatio).round();
      return Image.file(
        file,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        cacheWidth: cacheSize,
        cacheHeight: cacheSize,
        errorBuilder: (_, __, ___) => _fallbackTile(
          isVideo: false,
          isImage: true,
        ),
      );
    }

    if (isVideo) {
      return _PickerVideoThumbnail(
        videoPath: file.path,
        thumbnailSize: previewSize.round(),
        thumbnailQuality: previewSize >= 140 ? 55 : 45,
      );
    }

    return _fallbackTile(
      isVideo: false,
      isImage: false,
    );
  }
}

Widget _fallbackTile({
  required bool isVideo,
  required bool isImage,
}) {
  if (isVideo) {
    return Container(
      color: Colors.blueGrey[900],
      child: const Center(
        child: Icon(
          PhosphorIconsLight.videoCamera,
          color: Colors.white70,
          size: 36,
        ),
      ),
    );
  }

  if (isImage) {
    return Container(
      color: Colors.black12,
      child: const Center(
        child: Icon(
          PhosphorIconsLight.image,
          color: Colors.blueGrey,
          size: 36,
        ),
      ),
    );
  }

  return Container(
    color: Colors.black12,
    child: const Center(
      child: Icon(
        PhosphorIconsLight.file,
        color: Colors.blueGrey,
        size: 36,
      ),
    ),
  );
}

class _PickerVideoThumbnail extends StatefulWidget {
  final String videoPath;
  final int thumbnailSize;
  final int thumbnailQuality;

  const _PickerVideoThumbnail({
    required this.videoPath,
    required this.thumbnailSize,
    required this.thumbnailQuality,
  });

  @override
  State<_PickerVideoThumbnail> createState() => _PickerVideoThumbnailState();
}

class _PickerVideoThumbnailState extends State<_PickerVideoThumbnail> {
  String? _thumbnailPath;
  bool _isLoading = false;
  bool _requested = false;
  StreamSubscription<String>? _thumbReadySubscription;

  @override
  void initState() {
    super.initState();
    _thumbReadySubscription =
        VideoThumbnailHelper.onThumbnailReady.listen((readyPath) async {
      if (readyPath != widget.videoPath) {
        return;
      }
      final cached = await VideoThumbnailHelper.getFromCache(readyPath);
      if (!mounted || cached == null) {
        return;
      }
      setState(() {
        _thumbnailPath = cached;
        _isLoading = false;
      });
    });
    _loadCached();
  }

  @override
  void dispose() {
    _thumbReadySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCached() async {
    final cached = await VideoThumbnailHelper.getFromCache(widget.videoPath);
    if (!mounted || cached == null) {
      return;
    }
    setState(() {
      _thumbnailPath = cached;
    });
  }

  void _startGeneration() {
    if (_requested || _isLoading) {
      return;
    }
    _requested = true;
    setState(() {
      _isLoading = true;
    });

    VideoThumbnailHelper.generateThumbnail(
      widget.videoPath,
      isPriority: true,
      quality: widget.thumbnailQuality,
      thumbnailSize: widget.thumbnailSize,
    ).then((path) {
      if (!mounted) return;
      setState(() {
        _thumbnailPath = path ?? _thumbnailPath;
        _isLoading = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        VisibilityDetector(
          key: ValueKey('media-picker-video-${widget.videoPath}'),
          onVisibilityChanged: (info) {
            if (info.visibleFraction > 0.15 && _thumbnailPath == null) {
              _startGeneration();
            }
          },
          child: _buildContent(),
        ),
        const Positioned(
          right: 6,
          bottom: 6,
          child: Icon(
            PhosphorIconsLight.playCircle,
            color: Colors.white,
            size: 20,
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    final path = _thumbnailPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }

    if (_isLoading) {
      return ShimmerBox(
        width: double.infinity,
        height: double.infinity,
        borderRadius: BorderRadius.circular(16.0),
      );
    }

    return _fallbackTile(isVideo: true, isImage: false);
  }
}
