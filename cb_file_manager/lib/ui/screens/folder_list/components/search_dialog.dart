import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/helpers/core/io_extensions.dart';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import 'package:cb_file_manager/ui/screens/folder_list/file_details_screen.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class SearchDialog extends StatefulWidget {
  final String currentPath;
  final List<File> files;
  final List<Directory> folders;
  final Function(String)? onFolderSelected; // Callback khi chọn folder
  final Function(File)? onFileSelected; // Callback khi chọn file

  const SearchDialog({
    Key? key,
    required this.currentPath,
    required this.files,
    required this.folders,
    this.onFolderSelected,
    this.onFileSelected,
  }) : super(key: key);

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<SearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<File> _filteredFiles = [];
  List<Directory> _filteredFolders = [];
  bool _isSearchingTags = false;
  List<String> _suggestedTags = [];

  // Overlay entry for tag suggestions
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _filteredFiles = widget.files;
    _filteredFolders = widget.folders;

    // Load all tags and files with tags
    _preloadTagData();

    // Add listener for search text changes
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        _removeOverlay();
      }
    });
  }

  // Preload tag data for better performance
  Future<void> _preloadTagData() async {
    // Preload tags for all files in the current directory
    for (final file in widget.files) {
      await TagManager.getTags(file.path);
    }

    // Load popular tags for suggestions
    final popularTags = await TagManager.instance.getPopularTags(limit: 15);
    setState(() {
      _suggestedTags = popularTags.keys.toList();
    });
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();

    // Check if we're in tag search mode
    if (query.contains('#')) {
      final int hashPosition = query.lastIndexOf('#');
      final String tagQuery = query.substring(hashPosition + 1).trim();

      if (_searchFocusNode.hasFocus) {
        // Show tag suggestions if we're after a # character
        _updateTagSuggestions(tagQuery);
      }

      setState(() {
        _isSearchingTags = true;
      });
    } else {
      // Close tag suggestions overlay if not searching by tag
      _removeOverlay();
      setState(() {
        _isSearchingTags = false;
      });
    }

    // Filter files and folders based on the query
    _updateFilteredItems(query);
  }

  Future<void> _updateTagSuggestions(String tagQuery) async {
    if (tagQuery.isEmpty) {
      // Show popular tags
      _showOverlay(_suggestedTags);
    } else {
      // Search for tags matching the query
      final matchingTags = await TagManager.instance.searchTags(tagQuery);
      _showOverlay(matchingTags);
    }
  }

  void _updateFilteredItems(String query) async {
    if (query.isEmpty) {
      setState(() {
        _filteredFiles = widget.files;
        _filteredFolders = widget.folders;
      });
      return;
    }

    if (_isSearchingTags) {
      final int hashPosition = query.lastIndexOf('#');
      final String tagQuery = query.substring(hashPosition + 1).trim();

      if (tagQuery.isEmpty) {
        setState(() {
          _filteredFiles = widget.files;
          _filteredFolders = widget.folders;
        });
        return;
      }

      // Use TagManager's improved findFilesByTag method for better search results
      setState(() {
        // Show loading indicator while searching
        _filteredFiles = [];
        _filteredFolders = [];
      });

      // Get all tagged files including in subdirectories
      final results =
          await TagManager.findFilesByTag(widget.currentPath, tagQuery);

      // Tất cả kết quả đều là file do đã sửa đổi findFilesByTag
      final List<File> taggedFiles = results.cast<File>().toList();

      // Cập nhật UI với kết quả tìm kiếm
      setState(() {
        _filteredFiles = taggedFiles;
        _filteredFolders =
            []; // Không hiển thị thư mục trong kết quả tìm kiếm tag
      });
    } else {
      // Regular text search
      setState(() {
        _filteredFiles = widget.files
            .where((file) => file.path.toLowerCase().contains(query))
            .toList();
        _filteredFolders = widget.folders
            .where((folder) => folder.path.toLowerCase().contains(query))
            .toList();
      });
    }
  }

  void _showOverlay(List<String> tags) {
    if (tags.isEmpty) {
      _removeOverlay();
      return;
    }

    _removeOverlay();

    // Get the position of the search field for positioning the overlay
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Size size = renderBox.size;
    final Offset position = renderBox.localToGlobal(Offset.zero);

    // Create and insert overlay
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: position.dy + AppBar().preferredSize.height,
        left: position.dx,
        width: size.width,
        child: Material(
          elevation: 0,
          child: Container(
            height: min(300, tags.length * 50.0), // Limit height
            color: Theme.of(context).cardColor,
            child: ListView.builder(
              itemCount: tags.length,
              itemBuilder: (context, index) {
                return ListTile(
                  leading: const Icon(PhosphorIconsLight.tag),
                  title: Text(tags[index]),
                  onTap: () {
                    // Insert tag into search query
                    final text = _searchController.text;
                    final hashIndex = text.lastIndexOf('#');
                    final newText =
                        text.substring(0, hashIndex + 1) + tags[index];
                    _searchController.value = TextEditingValue(
                      text: newText,
                      selection:
                          TextSelection.collapsed(offset: newText.length),
                    );
                    _removeOverlay();

                    // Automatically trigger tag search when a tag is selected
                    _performTagSearch(tags[index]);
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // Phương thức để thực hiện tìm kiếm tag toàn cục
  Future<void> _performTagSearch(String tag) async {
    setState(() {
      _filteredFiles = [];
      _filteredFolders = [];
      _isSearchingTags = true;
    });

    try {
      // Hiển thị loading indicator
      final loadingOverlay = OverlayEntry(
        builder: (context) => Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        ),
      );
      Overlay.of(context).insert(loadingOverlay);

      // Clear TagManager cache trước khi tìm kiếm
      TagManager.clearCache();

      // Thực hiện tìm kiếm toàn cục
      final results = await TagManager.findFilesByTagGlobally(tag);

      // Loại bỏ loading indicator
      loadingOverlay.remove();

      if (mounted) {
        // Phân loại kết quả thành files và folders
        final List<File> files = [];
        final List<Directory> folders = [];

        for (var entity in results) {
          if (entity is File) {
            files.add(entity);
          } else if (entity is Directory) {
            folders.add(entity);
          }
        }

        // Cập nhật state để hiển thị kết quả
        setState(() {
          _filteredFiles = files;
          _filteredFolders = folders;
        });

        // Hiển thị thông báo kết quả
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Đã tìm thấy ${results.length} kết quả với tag "$tag"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Lỗi khi tìm kiếm tag: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi tìm kiếm: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          decoration: InputDecoration(
            hintText: _isSearchingTags
                ? 'Đang tìm kiếm theo tag... (ví dụ: #important)'
                : 'Tìm kiếm tệp hoặc dùng # để tìm theo tag',
            border: InputBorder.none,
            hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            prefixIcon: _isSearchingTags
                ? Icon(PhosphorIconsLight.tag,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)
                : Icon(PhosphorIconsLight.magnifyingGlass,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          autofocus: true,
        ),
      ),
      body: Column(
        children: [
          // Tag search hint
          if (_suggestedTags.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8.0,
                children: [
                  const Text('Tags phổ biến:',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                  ...(_suggestedTags.take(5).map((tag) => ActionChip(
                        label: Text('#$tag'),
                        onPressed: () {
                          _searchController.text = '#$tag';
                          // Tự động thực hiện tìm kiếm khi chọn tag từ phần gợi ý
                          _performTagSearch(tag);
                        },
                      ))),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Kết quả tìm kiếm trong: ${widget.currentPath}',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
          Expanded(
            child: _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_filteredFiles.isEmpty && _filteredFolders.isEmpty) {
      return const Center(
        child: Text('Không tìm thấy kết quả'),
      );
    }

    return ListView(
      children: [
        if (_filteredFolders.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Thư mục',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ..._filteredFolders.map(_buildFolderItem).toList(),
        ],
        if (_filteredFiles.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Tệp',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ..._filteredFiles.map(_buildFileItem).toList(),
        ],
      ],
    );
  }

  Widget _buildFolderItem(Directory folder) {
    return ListTile(
      leading: Icon(PhosphorIconsLight.folder,
          color: Theme.of(context).colorScheme.primary),
      title: Text(folder.basename()),
      onTap: () {
        Navigator.pop(context); // Close search dialog
        // Sử dụng callback để trả về path cho tab hiện tại
        widget.onFolderSelected!(folder.path);
      },
    );
  }

  Widget _buildFileItem(File file) {
    final theme = Theme.of(context);
    IconData icon;
    Color? iconColor;

    // Determine file type and icon using FileTypeUtils
    if (FileTypeUtils.isImageFile(file.path)) {
      icon = PhosphorIconsLight.image;
      iconColor = theme.colorScheme.primary;
    } else if (FileTypeUtils.isVideoFile(file.path)) {
      icon = PhosphorIconsLight.videoCamera;
      iconColor = theme.colorScheme.error;
    } else if (FileTypeUtils.isAudioFile(file.path)) {
      icon = PhosphorIconsLight.musicNote;
      iconColor = theme.colorScheme.tertiary;
    } else if (FileTypeUtils.isDocumentFile(file.path) ||
        FileTypeUtils.isSpreadsheetFile(file.path) ||
        FileTypeUtils.isPresentationFile(file.path)) {
      icon = PhosphorIconsLight.fileText;
      iconColor = theme.colorScheme.primary;
    } else {
      icon = PhosphorIconsLight.file;
      iconColor = theme.colorScheme.onSurfaceVariant;
    }

    // Get tags for the file if we're in tag search mode
    if (_isSearchingTags) {
      return FutureBuilder<List<String>>(
          future: TagManager.getTags(file.path),
          builder: (context, snapshot) {
            final tags = snapshot.data ?? [];

            return ListTile(
              leading: Icon(icon, color: iconColor),
              title: Text(file.path.split('/').last),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.path.replaceFirst(widget.currentPath, '')),
                  if (tags.isNotEmpty)
                    Wrap(
                      spacing: 4,
                      children: tags
                          .map((tag) => Chip(
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                label: Text(tag,
                                    style: const TextStyle(fontSize: 10)),
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                              ))
                          .toList(),
                    ),
                ],
              ),
              onTap: () {
                Navigator.pop(context); // Close search dialog

                if (widget.onFileSelected != null) {
                  // Sử dụng callback để trả về file cho tab hiện tại
                  widget.onFileSelected!(file);
                } else {
                  // Fallback cho màn hình cũ
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FileDetailsScreen(file: file),
                    ),
                  );
                }
              },
            );
          });
    }

    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(file.path.split('/').last),
      subtitle: Text(file.path.replaceFirst(widget.currentPath, '')),
      onTap: () {
        Navigator.pop(context); // Close search dialog

        if (widget.onFileSelected != null) {
          // Sử dụng callback để trả về file cho tab hiện tại
          widget.onFileSelected!(file);
        } else {
          // Fallback cho màn hình cũ
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FileDetailsScreen(file: file),
            ),
          );
        }
      },
    );
  }
}
