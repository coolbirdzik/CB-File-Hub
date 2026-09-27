import 'package:cb_file_manager/ui/widgets/gallery_nsfw_toggle.dart';
import 'package:flutter/material.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/models/objectbox/album.dart';
import 'package:cb_file_manager/models/objectbox/album_config.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/utils/route.dart';
import 'package:cb_file_manager/services/smart_album_service.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/directory_list_widget.dart';
import 'package:file_picker/file_picker.dart';

class CreateAlbumDialog extends StatefulWidget {
  final Album? editingAlbum;
  final bool sourceMode;
  final Future<String?> Function()? directoryPicker;

  const CreateAlbumDialog({
    super.key,
    this.editingAlbum,
    this.sourceMode = false,
    this.directoryPicker,
  });

  @override
  State<CreateAlbumDialog> createState() => _CreateAlbumDialogState();
}

class _CreateAlbumDialogState extends State<CreateAlbumDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final AlbumService _albumService = AlbumService.instance;
  final List<String> _selectedDirectories = [];

  String? _selectedColor;
  bool _isLoading = false;
  bool _includeSubdirectories = true;
  bool _isSmartAlbum = false;
  bool _isNsfw = false;

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
      _isNsfw = widget.editingAlbum!.isNsfw;
    }
    if (widget.sourceMode) {
      _loadSourceConfig();
    } else {
      _loadSmartFlag();
    }
  }

  Future<void> _loadSourceConfig() async {
    final album = widget.editingAlbum;
    if (album == null) return;
    final config = await _albumService.getAlbumConfig(album.id);
    if (!mounted || config == null) return;
    setState(() {
      _selectedDirectories
        ..clear()
        ..addAll(config.directoriesList);
      _includeSubdirectories = config.includeSubdirectories;
    });
  }

  Future<void> _pickDirectory() async {
    final directory =
        await (widget.directoryPicker?.call() ?? FilePicker.getDirectoryPath());
    if (!mounted || directory == null || directory.isEmpty) return;
    if (!_selectedDirectories.contains(directory)) {
      setState(() => _selectedDirectories.add(directory));
    }
  }

  Future<void> _loadSmartFlag() async {
    try {
      if (widget.editingAlbum != null) {
        final isSmart = await SmartAlbumService.instance.isSmartAlbum(
          widget.editingAlbum!.id,
        );
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

    final l10n = AppLocalizations.of(context)!;
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
          isNsfw: _isNsfw,
        );

        final success = await _albumService.updateAlbum(updatedAlbum);
        if (success) {
          result = updatedAlbum;
          if (widget.sourceMode) {
            final existing = await _albumService.getAlbumConfig(result.id);
            final config = (existing ?? AlbumConfig(albumId: result.id))
                .copyWith(
                  includeSubdirectories: _includeSubdirectories,
                  fileExtensions: _imageExtensions,
                  directories: _selectedDirectories.join(','),
                );
            await _albumService.updateAlbumConfig(config);
            await _albumService.refreshAlbum(result.id);
          }
        }
      } else {
        // Create new album
        result = await _albumService.createAlbum(
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          colorTheme: _selectedColor,
          isNsfw: _isNsfw,
          directories: widget.sourceMode ? _selectedDirectories : null,
          config: widget.sourceMode
              ? AlbumConfig(
                  albumId: 0,
                  includeSubdirectories: _includeSubdirectories,
                  fileExtensions: _imageExtensions,
                )
              : null,
        );
      }

      if (result != null) {
        // Persist smart flag mapping
        if (!widget.sourceMode) {
          try {
            await SmartAlbumService.instance.setSmartAlbum(
              result.id,
              _isSmartAlbum,
            );
          } catch (_) {}
        }
        if (mounted) {
          Navigator.of(context).pop(result);
        }
      } else {
        if (mounted) {
          AppToast.error(
            context,
            widget.editingAlbum != null
                ? l10n.failedToUpdateAlbum
                : l10n.failedToCreateAlbum,
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving album: $e');
      if (mounted) {
        AppToast.error(context, l10n.errorWithMessage(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  static const _imageExtensions = '.jpg,.jpeg,.png,.gif,.bmp,.webp,.tiff,.tif';

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
            CbColorSwatch.glyph(
              size: 40,
              selected: _selectedColor == null,
              onPressed: () {
                setState(() {
                  _selectedColor = null;
                });
              },
              child: Icon(
                PhosphorIconsLight.x,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
            // Color options
            ..._colorOptions.map((color) {
              return CbColorSwatch(
                size: 40,
                color: Color(int.parse(color.replaceFirst('#', '0xFF'))),
                selected: _selectedColor == color,
                onPressed: () {
                  setState(() {
                    _selectedColor = color;
                  });
                },
              );
            }),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(
        widget.sourceMode
            ? (widget.editingAlbum != null
                  ? l10n.editImageSource
                  : l10n.createImageSource)
            : (widget.editingAlbum != null ? 'Edit Album' : 'Create New Album'),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 500,
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
                GalleryNsfwToggle(
                  value: _isNsfw,
                  onChanged: _isLoading
                      ? null
                      : (value) => setState(() => _isNsfw = value),
                ),
                _buildColorPicker(),
                const SizedBox(height: 16),
                if (widget.sourceMode) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.imageSources,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      TextButton.icon(
                        key: const ValueKey('add-image-source-directory'),
                        onPressed: _isLoading ? null : _pickDirectory,
                        icon: const Icon(PhosphorIconsLight.plus),
                        label: Text(l10n.addImageSource),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DirectoryListWidget(
                    directories: _selectedDirectories,
                    onRemove: (directory) =>
                        setState(() => _selectedDirectories.remove(directory)),
                    emptyMessage: l10n.noImageSources,
                    removeTooltip: l10n.removeImageSource,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _includeSubdirectories,
                    onChanged: _isLoading
                        ? null
                        : (value) => setState(
                            () => _includeSubdirectories = value ?? true,
                          ),
                    title: Text(l10n.includeSubdirectories),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ] else
                  SwitchListTile(
                    title: const Text('Dynamic (Smart) Album'),
                    subtitle: const Text(
                      'Content is defined by Auto Rules. No files are stored explicitly.',
                    ),
                    value: _isSmartAlbum,
                    onChanged: (val) {
                      setState(() => _isSmartAlbum = val);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading
              ? null
              : () => RouteUtils.safePopDialog(context),
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
