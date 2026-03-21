import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/services/smart_album_service.dart';

class CreateAlbumDialog extends StatefulWidget {
  final Album? editingAlbum;

  const CreateAlbumDialog({
    Key? key,
    this.editingAlbum,
  }) : super(key: key);

  @override
  State<CreateAlbumDialog> createState() => _CreateAlbumDialogState();
}

class _CreateAlbumDialogState extends State<CreateAlbumDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final AlbumService _albumService = AlbumService.instance;

  String? _selectedColor;
  bool _isLoading = false;
  bool _isSmartAlbum = false;

  // Predefined color options
  final List<String> _colorOptions = [
    '#FF5722', // Deep Orange
    '#E91E63', // Pink
    '#9C27B0', // Purple
    '#673AB7', // Deep Purple
    '#3F51B5', // Indigo
    '#2196F3', // Blue
    '#03A9F4', // Light Blue
    '#00BCD4', // Cyan
    '#009688', // Teal
    '#4CAF50', // Green
    '#8BC34A', // Light Green
    '#CDDC39', // Lime
    '#FFC107', // Amber
    '#FF9800', // Orange
    '#795548', // Brown
    '#607D8B', // Blue Grey
  ];

  @override
  void initState() {
    super.initState();
    if (widget.editingAlbum != null) {
      _nameController.text = widget.editingAlbum!.name;
      _descriptionController.text = widget.editingAlbum!.description ?? '';
      _selectedColor = widget.editingAlbum!.colorTheme;
    }
    _loadSmartFlag();
  }

  Future<void> _loadSmartFlag() async {
    try {
      if (widget.editingAlbum != null) {
        final isSmart = await SmartAlbumService.instance
            .isSmartAlbum(widget.editingAlbum!.id);
        if (mounted) setState(() => _isSmartAlbum = isSmart);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveAlbum() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      Album? result;

      if (widget.editingAlbum != null) {
        // Update existing album
        final updatedAlbum = widget.editingAlbum!.copyWith(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          colorTheme: _selectedColor,
        );

        final success = await _albumService.updateAlbum(updatedAlbum);
        if (success) {
          result = updatedAlbum;
        }
      } else {
        // Create new album
        result = await _albumService.createAlbum(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          colorTheme: _selectedColor,
        );
      }

      if (result != null) {
        // Persist smart flag mapping
        try {
          await SmartAlbumService.instance
              .setSmartAlbum(result.id, _isSmartAlbum);
        } catch (_) {}
        if (mounted) {
          Navigator.of(context).pop(result);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.editingAlbum != null
                  ? 'Failed to update album'
                  : 'Failed to create album'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving album: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
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

  Widget _buildColorPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Album Color (Optional)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Clear selection option
            GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = null;
                });
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedColor == null
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: _selectedColor == null ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  PhosphorIconsLight.x,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ),
            // Color options
            ..._colorOptions.map((color) {
              final isSelected = _selectedColor == color;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedColor = color;
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: isSelected
                      ? const Icon(
                          PhosphorIconsLight.check,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                ),
              );
            }).toList(),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          Text(widget.editingAlbum != null ? 'Edit Album' : 'Create New Album'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Album Name *',
                  hintText: 'Enter album name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Album name is required';
                  }
                  if (value.trim().length > 50) {
                    return 'Album name must be 50 characters or less';
                  }
                  return null;
                },
                maxLength: 50,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'Enter album description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                maxLength: 200,
                validator: (value) {
                  if (value != null && value.trim().length > 200) {
                    return 'Description must be 200 characters or less';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _buildColorPicker(),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Dynamic (Smart) Album'),
                subtitle: const Text(
                    'Content is defined by Auto Rules. No files are stored explicitly.'),
                value: _isSmartAlbum,
                onChanged: (val) {
                  setState(() => _isSmartAlbum = val);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _isLoading ? null : () => RouteUtils.safePopDialog(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveAlbum,
          child: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.editingAlbum != null ? 'Update' : 'Create'),
        ),
      ],
    );
  }
}
