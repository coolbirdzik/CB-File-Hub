import 'package:flutter/material.dart';
import 'dart:io';
import 'package:cb_file_manager/helpers/tags/tag_manager.dart';
import '../../utils/route.dart';

/// Dialog for searching files by tag
class TagSearchDialog extends StatefulWidget {
  final String currentPath;
  final Function(List<FileSystemEntity>, String) onSearchComplete;

  const TagSearchDialog({
    Key? key,
    required this.currentPath,
    required this.onSearchComplete,
  }) : super(key: key);

  @override
  State<TagSearchDialog> createState() => _TagSearchDialogState();
}

class _TagSearchDialogState extends State<TagSearchDialog> {
  final TextEditingController _tagController = TextEditingController();
  bool _isGlobalSearch = false;
  bool _isSearching = false;
  List<String> _availableTags = [];

  @override
  void initState() {
    super.initState();
    _loadAvailableTags();
  }

  Future<void> _loadAvailableTags() async {
    final tags = await TagManager.getAllUniqueTags(widget.currentPath);
    setState(() {
      _availableTags = tags.toList()..sort();
    });
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    if (_tagController.text.trim().isEmpty) {
      return;
    }

    setState(() {
      _isSearching = true;
    });

    // Pre-extract context-dependent values before async gap
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      List<FileSystemEntity> results;
      if (_isGlobalSearch) {
        results =
            await TagManager.findFilesByTagGlobally(_tagController.text.trim());
      } else {
        results = await TagManager.findFilesByTag(
          widget.currentPath,
          _tagController.text.trim(),
        );
      }

      try {
        navigator.pop();
      } catch (_) {}
      widget.onSearchComplete(results, _tagController.text.trim());
    } catch (e) {
      try {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Lỗi tìm kiếm: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } catch (_) {}
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tìm kiếm theo tag'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return _availableTags;
              }
              return _availableTags.where((tag) => tag
                  .toLowerCase()
                  .contains(textEditingValue.text.toLowerCase()));
            },
            onSelected: (String selection) {
              _tagController.text = selection;
              // Tự động thực hiện tìm kiếm khi người dùng chọn một tag từ auto-complete
              _performSearch();
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              _tagController.text = controller.text;
              return TextField(
                controller: controller,
                focusNode: focusNode,
                decoration: const InputDecoration(
                  labelText: 'Nhập tag để tìm kiếm',
                  hintText: 'Ví dụ: important, work, personal',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _performSearch(),
              );
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('Tìm kiếm toàn cục'),
            subtitle: const Text('Tìm kiếm bất kỳ đâu trên thiết bị của bạn'),
            value: _isGlobalSearch,
            onChanged: (value) {
              setState(() {
                _isGlobalSearch = value;
              });
            },
          ),
          const SizedBox(height: 8),
          if (_availableTags.isNotEmpty)
            Wrap(
              spacing: 8.0,
              runSpacing: 4.0,
              children: _availableTags
                  .map((tag) => ActionChip(
                        label: Text(tag),
                        onPressed: () {
                          setState(() {
                            _tagController.text = tag;
                          });
                          // Tự động thực hiện tìm kiếm khi người dùng chọn một tag
                          _performSearch();
                        },
                      ))
                  .toList(),
            )
          else
            const Text('Không có tag nào hiện có'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            RouteUtils.safePopDialog(context);
          },
          child: const Text('HỦY'),
        ),
        ElevatedButton(
          onPressed: _isSearching ? null : _performSearch,
          child: _isSearching
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : const Text('TÌM KIẾM'),
        ),
      ],
    );
  }
}

/// Shows the tag search dialog
void showTagSearchDialog(
  BuildContext context,
  String currentPath,
  Function(List<FileSystemEntity>, String) onSearchComplete,
) {
  showDialog(
    context: context,
    builder: (context) => TagSearchDialog(
      currentPath: currentPath,
      onSearchComplete: onSearchComplete,
    ),
  );
}
