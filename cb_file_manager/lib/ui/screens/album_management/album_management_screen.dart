import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/ui/utils/base_screen.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
// import 'package:cb_file_manager/services/album_auto_rule_service.dart';
import 'dart:math' as math;

import 'create_album_dialog.dart';
import 'dart:io';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';
import 'package:cb_file_manager/services/smart_album_service.dart';
import 'package:cb_file_manager/ui/components/common/skeleton_helper.dart';
import 'package:cb_file_manager/core/service_locator.dart';

class AlbumManagementScreen extends StatefulWidget {
  const AlbumManagementScreen({Key? key}) : super(key: key);

  @override
  State<AlbumManagementScreen> createState() => _AlbumManagementScreenState();
}

class _AlbumManagementScreenState extends State<AlbumManagementScreen> {
  // Migration to dependency injection: Use locator instead of .instance
  // Old way: final AlbumService _albumService = AlbumService.instance;
  // New way: Use service locator for better testability and dependency management
  final AlbumService _albumService = locator<AlbumService>();
  List<Album> _albums = [];
  bool _isLoading = true;
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final albums = await _albumService.getAllAlbums();
      if (mounted) {
        setState(() {
          _albums = albums;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading albums: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showCreateAlbumDialog() async {
    final result = await showDialog<Album>(
      context: context,
      builder: (context) => const CreateAlbumDialog(),
    );

    if (result != null) {
      await _loadAlbums();
    }
  }

  Future<void> _deleteAlbum(Album album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteAlbum),
        content: Text(
          'Are you sure you want to delete the album "${album.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _albumService.deleteAlbum(album.id);
      if (success) {
        await _loadAlbums();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Album "${album.name}" deleted successfully'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete album'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<int> _getAlbumImageCount(Album album) async {
    try {
      final isSmart = await SmartAlbumService.instance.isSmartAlbum(album.id);
      if (isSmart) {
        final cached =
            await SmartAlbumService.instance.getCachedFiles(album.id);
        return cached.length;
      }
      final files = await _albumService.getAlbumFiles(album.id);
      return files.length;
    } catch (_) {
      return 0;
    }
  }

  // Removed auto rule processing from listing screen as requested

  Widget _buildAlbumCard(Album album) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: () {
          // Navigate to album detail within current tab
          final tabBloc = BlocProvider.of<TabManagerBloc>(context);
          final activeTab = tabBloc.state.activeTab;
          final path = '#album/${album.id}';
          if (activeTab != null) {
            TabNavigator.updateTabPath(context, activeTab.id, path);
            tabBloc.add(UpdateTabName(activeTab.id, album.name));
          } else {
            // Fallback: if no active tab, open as new tab
            tabBloc.add(AddTab(
              path: path,
              name: album.name,
              switchToTab: true,
            ));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Album cover or placeholder
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: album.colorTheme != null
                      ? Color(int.parse(
                          album.colorTheme!.replaceFirst('#', '0xFF')))
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
                child: album.coverImagePath != null &&
                        File(album.coverImagePath!).existsSync()
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(
                          File(album.coverImagePath!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(PhosphorIconsLight.imageSquare,
                                size: 30);
                          },
                        ),
                      )
                    : Icon(PhosphorIconsLight.imageSquare,
                        size: 30, color: Colors.white),
              ),
              const SizedBox(width: 16),
              // Album info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (album.description != null &&
                        album.description!.isNotEmpty)
                      Text(
                        album.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    FutureBuilder<int>(
                      future: _getAlbumImageCount(album),
                      builder: (context, snapshot) {
                        final fileCount = snapshot.data ?? 0;
                        return Text(
                          '$fileCount ${fileCount == 1 ? 'image' : 'images'}',
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // More options menu
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'delete':
                      _deleteAlbum(album);
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsLight.trash, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.delete,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreen(
      title: 'Albums',
      actions: [
        IconButton(
          icon: Icon(_isGridView
              ? PhosphorIconsLight.listBullets
              : PhosphorIconsLight.gridFour),
          tooltip: _isGridView ? 'List view' : 'Grid view',
          onPressed: () {
            setState(() => _isGridView = !_isGridView);
          },
        ),
        IconButton(
          icon: Icon(PhosphorIconsLight.plus),
          onPressed: _showCreateAlbumDialog,
          tooltip: 'Create Album',
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'refresh':
                _loadAlbums();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'refresh',
              child: Row(
                children: [
                  Icon(PhosphorIconsLight.arrowClockwise),
                  SizedBox(width: 8),
                  Text('Refresh'),
                ],
              ),
            ),
          ],
        ),
      ],
      body: _isLoading
          ? SkeletonHelper.responsive(
              isGridView: _isGridView,
              isAlbum: true,
              crossAxisCount: 3,
              itemCount: 12,
            )
          : _albums.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        PhosphorIconsLight.imageSquare,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No albums yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your first album to organize your images',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _showCreateAlbumDialog,
                        icon: Icon(PhosphorIconsLight.plus),
                        label: const Text('Create Album'),
                      ),
                    ],
                  ),
                )
              : _isGridView
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        int crossAxisCount = 2;
                        if (width > 1200) {
                          crossAxisCount = 5;
                        } else if (width > 900) {
                          crossAxisCount = 4;
                        } else if (width > 600) {
                          crossAxisCount = 3;
                        }

                        return GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.2,
                          ),
                          itemCount: _albums.length,
                          itemBuilder: (context, index) {
                            return _buildAlbumGridTile(_albums[index]);
                          },
                        );
                      },
                    )
                  : ListView.builder(
                      itemCount: _albums.length,
                      itemBuilder: (context, index) {
                        return _buildAlbumCard(_albums[index]);
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateAlbumDialog,
        tooltip: 'Create Album',
        child: Icon(PhosphorIconsLight.plus),
      ),
    );
  }

  Widget _buildAlbumGridTile(Album album) {
    return InkWell(
      onTap: () {
        // Navigate to album detail within current tab
        final tabBloc = BlocProvider.of<TabManagerBloc>(context);
        final activeTab = tabBloc.state.activeTab;
        final path = '#album/${album.id}';
        if (activeTab != null) {
          TabNavigator.updateTabPath(context, activeTab.id, path);
          tabBloc.add(UpdateTabName(activeTab.id, album.name));
        } else {
          tabBloc.add(AddTab(path: path, name: album.name, switchToTab: true));
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _buildAlbumCover(album)),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: PopupMenuButton<String>(
                      tooltip: 'Album options',
                      onSelected: (value) async {
                        switch (value) {
                          case 'set_cover':
                            await _showPickCoverDialog(album);
                            break;
                          case 'random_cover':
                            final files =
                                await _albumService.getAlbumFiles(album.id);
                            if (files.isNotEmpty) {
                              final rnd = math.Random();
                              final chosen = files[rnd.nextInt(files.length)];
                              final updated = album.copyWith(
                                  coverImagePath: chosen.filePath);
                              await _albumService.updateAlbum(updated);
                              _loadAlbums();
                            }
                            break;
                          case 'delete':
                            _deleteAlbum(album);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'set_cover',
                          child: Row(
                            children: [
                              Icon(PhosphorIconsLight.image, size: 16),
                              SizedBox(width: 8),
                              Text('Set Cover…')
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'random_cover',
                          child: Row(
                            children: [
                              Icon(PhosphorIconsLight.shuffle, size: 16),
                              SizedBox(width: 8),
                              Text('Random Cover')
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(PhosphorIconsLight.trash,
                                  size: 16, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete')
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  FutureBuilder<int>(
                    future: _getAlbumImageCount(album),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Text(
                        '$count ${count == 1 ? 'image' : 'images'}',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      );
                    },
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumCover(Album album) {
    // If explicit cover is set and exists, show it
    if (album.coverImagePath != null &&
        File(album.coverImagePath!).existsSync()) {
      return Image.file(
        File(album.coverImagePath!),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Icon(PhosphorIconsLight.imageSquare, size: 30),
      );
    }

    // Otherwise pick a deterministic "random" file from album images
    return FutureBuilder(
      future: _albumService.getAlbumFiles(album.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return SkeletonHelper.box(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(16),
          );
        }
        final files = (snapshot.data as List?) ?? [];
        if (files.isEmpty) {
          return SkeletonHelper.box(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(16),
          );
        }
        final idx = album.id % files.length;
        final path = files[idx].filePath as String;
        if (!File(path).existsSync()) {
          return SkeletonHelper.box(
            width: double.infinity,
            height: double.infinity,
            borderRadius: BorderRadius.circular(16),
          );
        }
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              Icon(PhosphorIconsLight.imageSquare, size: 30),
        );
      },
    );
  }

  Future<void> _showPickCoverDialog(Album album) async {
    final files = await _albumService.getAlbumFiles(album.id);
    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No images to pick as cover')));
      }
      return;
    }

    String? selected;
    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Choose Cover Image'),
            content: SizedBox(
              width: 600,
              height: 400,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: files.length,
                itemBuilder: (context, index) {
                  final p = files[index].filePath;
                  return GestureDetector(
                    onTap: () {
                      selected = p;
                      Navigator.of(context).pop();
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        File(p),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Icon(PhosphorIconsLight.imageBroken),
                      ),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    }

    if (selected != null) {
      final updated = album.copyWith(coverImagePath: selected);
      await _albumService.updateAlbum(updated);
      _loadAlbums();
    }
  }
}
