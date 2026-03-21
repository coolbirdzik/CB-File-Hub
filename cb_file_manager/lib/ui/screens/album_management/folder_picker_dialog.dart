import 'dart:io';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:path/path.dart' as path;
import 'package:cb_file_manager/helpers/core/filesystem_utils.dart';

class FolderPickerDialog extends StatefulWidget {
  final int albumId;
  final String? initialPath;

  const FolderPickerDialog({
    Key? key,
    required this.albumId,
    this.initialPath,
  }) : super(key: key);

  @override
  State<FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<FolderPickerDialog> {
  final AlbumService _albumService = AlbumService.instance;

  String _currentPath = '';
  List<Directory> _directories = [];
  bool _isLoading = false;
  bool _includeSubfolders = true;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath ?? '/storage/emulated/0';
    _loadDirectories();
  }

  Future<void> _loadDirectories() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final currentDir = Directory(_currentPath);
      if (await currentDir.exists()) {
        final entities = await currentDir.list().toList();
        final directories = entities
            .whereType<Directory>()
            .where((dir) => !path.basename(dir.path).startsWith('.'))
            .toList();

        directories.sort((a, b) => path
            .basename(a.path)
            .toLowerCase()
            .compareTo(path.basename(b.path).toLowerCase()));

        if (mounted) {
          setState(() {
            _directories = directories;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading directories: $e');
      if (mounted) {
        setState(() {
          _directories = [];
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToDirectory(String dirPath) {
    setState(() {
      _currentPath = dirPath;
    });
    _loadDirectories();
  }

  void _navigateUp() {
    final parentPath = path.dirname(_currentPath);
    if (parentPath != _currentPath) {
      _navigateToDirectory(parentPath);
    }
  }

  Future<void> _addFolderToAlbum() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Folder to Album'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add all images from this folder to the album?'),
            const SizedBox(height: 8),
            Text(
              'Folder: ${path.basename(_currentPath)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _includeSubfolders,
                  onChanged: (value) {
                    setState(() {
                      _includeSubfolders = value ?? true;
                    });
                  },
                ),
                const Expanded(
                  child: Text('Include images from subfolders'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add Folder'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading dialog
    if (context.mounted) {
      showDialog(
        // ignore: use_build_context_synchronously
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Adding folder to album...'),
            ],
          ),
        ),
      );
    }

    try {
      final successCount = await _albumService.addFolderToAlbum(
        widget.albumId,
        _currentPath,
        recursive: _includeSubfolders,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        Navigator.of(context).pop(successCount);
      }
    } catch (e) {
      debugPrint('Error adding folder to album: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding folder: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildDirectoryItem(Directory directory) {
    final dirName = path.basename(directory.path);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: const Icon(PhosphorIconsLight.folder, color: Colors.amber),
        title: Text(
          dirName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: FutureBuilder<int>(
          future: _getImageCount(directory.path),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final count = snapshot.data!;
              return Text(
                count > 0
                    ? '$count ${count == 1 ? 'image' : 'images'}'
                    : 'No images',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            }
            return const Text('Counting...');
          },
        ),
        trailing: const Icon(PhosphorIconsLight.caretRight),
        onTap: () => _navigateToDirectory(directory.path),
      ),
    );
  }

  Future<int> _getImageCount(String dirPath) async {
    try {
      final images = await getAllImages(dirPath, recursive: false);
      return images.length;
    } catch (e) {
      return 0;
    }
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
                  const Icon(PhosphorIconsLight.folderOpen, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Select Folder',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(PhosphorIconsLight.x, color: Colors.white),
                    onPressed: () => RouteUtils.safePopDialog(context),
                  ),
                ],
              ),
            ),
            // Current path and navigation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(PhosphorIconsLight.arrowLeft),
                        onPressed: path.dirname(_currentPath) != _currentPath
                            ? _navigateUp
                            : null,
                        tooltip: 'Go up',
                      ),
                      Expanded(
                        child: Text(
                          _currentPath,
                          style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: _includeSubfolders,
                        onChanged: (value) {
                          setState(() {
                            _includeSubfolders = value ?? true;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text('Include images from subfolders'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Directory list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _directories.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                PhosphorIconsLight.folderOpen,
                                size: 64,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No folders found',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _directories.length,
                          itemBuilder: (context, index) {
                            return _buildDirectoryItem(_directories[index]);
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current: ${path.basename(_currentPath)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => RouteUtils.safePopDialog(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addFolderToAlbum,
                        child: const Text('Add This Folder'),
                      ),
                    ],
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
