import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:path/path.dart' as path;
import 'dart:async';

class FileSearchDialog extends StatefulWidget {
  final int albumId;
  final String? initialSearchPath;

  const FileSearchDialog({
    Key? key,
    required this.albumId,
    this.initialSearchPath,
  }) : super(key: key);

  @override
  State<FileSearchDialog> createState() => _FileSearchDialogState();
}

class _FileSearchDialogState extends State<FileSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final AlbumService _albumService = AlbumService.instance;

  List<File> _searchResults = [];
  Set<String> _selectedFiles = {};
  bool _isSearching = false;
  Timer? _debounceTimer;
  String? _currentSearchQuery;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // Start with initial search if no query provided
    if (_searchController.text.isEmpty) {
      _performSearch('');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.trim();
      if (query != _currentSearchQuery) {
        _performSearch(query);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    setState(() {
      _isSearching = true;
      _currentSearchQuery = query;
    });

    try {
      final results = await _albumService.searchImageFiles(
        query,
        rootPath: widget.initialSearchPath,
      );

      // Filter out files that are already in the album
      final filteredResults = <File>[];
      for (final file in results) {
        final isInAlbum =
            await _albumService.isFileInAlbum(widget.albumId, file.path);
        if (!isInAlbum) {
          filteredResults.add(file);
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = filteredResults;
          _isSearching = false;
          // Clear selection when search results change
          _selectedFiles.clear();
        });
      }
    } catch (e) {
      debugPrint('Error searching files: $e');
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  void _toggleFileSelection(String filePath) {
    setState(() {
      if (_selectedFiles.contains(filePath)) {
        _selectedFiles.remove(filePath);
      } else {
        _selectedFiles.add(filePath);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedFiles.length == _searchResults.length) {
        _selectedFiles.clear();
      } else {
        _selectedFiles = _searchResults.map((file) => file.path).toSet();
      }
    });
  }

  Future<void> _addSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Adding files to album...'),
          ],
        ),
      ),
    );

    try {
      final successCount = await _albumService.addFilesToAlbum(
        widget.albumId,
        _selectedFiles.toList(),
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        Navigator.of(context).pop(successCount);
      }
    } catch (e) {
      debugPrint('Error adding files to album: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding files: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildFileItem(File file) {
    final isSelected = _selectedFiles.contains(file.path);
    final fileName = path.basename(file.path);
    final fileDir = path.dirname(file.path);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Icon(PhosphorIconsLight.imageBroken,
                    color: Theme.of(context).colorScheme.onSurfaceVariant);
              },
            ),
          ),
        ),
        title: Text(
          fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14),
        ),
        subtitle: Text(
          fileDir,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Checkbox(
          value: isSelected,
          onChanged: (value) => _toggleFileSelection(file.path),
        ),
        onTap: () => _toggleFileSelection(file.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.magnifyingGlass, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Search and Select Images',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(PhosphorIconsLight.x, color: Colors.white),
                    onPressed: () => RouteUtils.safePopDialog(context),
                  ),
                ],
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search for images...',
                  prefixIcon: Icon(PhosphorIconsLight.magnifyingGlass),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(PhosphorIconsLight.x),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ),
            // Selection controls
            if (_searchResults.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      '${_selectedFiles.length} of ${_searchResults.length} selected',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _selectAll,
                      child: Text(
                        _selectedFiles.length == _searchResults.length
                            ? 'Deselect All'
                            : 'Select All',
                      ),
                    ),
                  ],
                ),
              ),
            // Search results
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : _searchResults.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                PhosphorIconsLight.magnifyingGlass,
                                size: 64,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _currentSearchQuery?.isEmpty == true
                                    ? 'Loading images...'
                                    : 'No images found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              if (_currentSearchQuery?.isNotEmpty == true)
                                Text(
                                  'Try a different search term',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            return _buildFileItem(_searchResults[index]);
                          },
                        ),
            ),
            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => RouteUtils.safePopDialog(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed:
                        _selectedFiles.isEmpty ? null : _addSelectedFiles,
                    child: Text(
                      'Add ${_selectedFiles.length} ${_selectedFiles.length == 1 ? 'Image' : 'Images'}',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
