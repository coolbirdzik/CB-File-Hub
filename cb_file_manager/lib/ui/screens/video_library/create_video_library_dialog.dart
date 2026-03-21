import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:cb_file_manager/services/video_library_service.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/video_library_helpers.dart';
import 'package:cb_file_manager/ui/screens/video_library/widgets/directory_list_widget.dart';

/// Dialog for creating a new video library
class CreateVideoLibraryDialog extends StatefulWidget {
  const CreateVideoLibraryDialog({Key? key}) : super(key: key);

  @override
  State<CreateVideoLibraryDialog> createState() =>
      _CreateVideoLibraryDialogState();
}

class _CreateVideoLibraryDialogState extends State<CreateVideoLibraryDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<String> _selectedDirectories = [];
  bool _includeSubdirectories = true;
  String? _selectedColorTheme;

  final List<Color> _colorOptions = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.amber,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final selectedDirectory = await VideoLibraryHelpers.pickDirectory();
    if (selectedDirectory != null &&
        !_selectedDirectories.contains(selectedDirectory)) {
      setState(() {
        _selectedDirectories.add(selectedDirectory);
      });
    }
  }

  void _removeDirectory(String directory) {
    setState(() {
      _selectedDirectories.remove(directory);
    });
  }

  Future<void> _createLibrary() async {
    final localizations = AppLocalizations.of(context)!;

    if (_nameController.text.trim().isEmpty) {
      VideoLibraryHelpers.showErrorMessage(context, localizations.enterTagName);
      return;
    }

    final service = VideoLibraryService();
    final library = await service.createLibrary(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      colorTheme: _selectedColorTheme,
      directories: _selectedDirectories,
    );

    if (library != null && mounted) {
      VideoLibraryHelpers.showSuccessMessage(
          context, localizations.libraryCreatedSuccessfully);
      Navigator.of(context).pop(library);
    } else if (mounted) {
      VideoLibraryHelpers.showErrorMessage(
          context, localizations.operationFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.createVideoLibrary),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Library Name
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '${localizations.fileName} *',
                  hintText: 'My Movies',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // Description
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: localizations.aboutTagsDescription,
                  hintText: 'Personal movie collection',
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // Color Theme Picker
              Text(
                localizations.changeColor,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colorOptions.map((color) {
                  final colorHex =
                      '#${color.toARGB32().toRadixString(16).substring(2)}';
                  final isSelected = _selectedColorTheme == colorHex;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedColorTheme = colorHex;
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(PhosphorIconsLight.check,
                              color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Video Sources
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    localizations.videoSources,
                    style: theme.textTheme.titleSmall,
                  ),
                  TextButton.icon(
                    onPressed: _pickDirectory,
                    icon: const Icon(PhosphorIconsLight.plus),
                    label: Text(localizations.addVideoSource),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              DirectoryListWidget(
                directories: _selectedDirectories,
                onRemove: _removeDirectory,
              ),
              const SizedBox(height: 16),

              // Include subdirectories toggle
              CheckboxListTile(
                value: _includeSubdirectories,
                onChanged: (value) {
                  setState(() {
                    _includeSubdirectories = value ?? true;
                  });
                },
                title: Text(localizations.includeSubdirectories),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localizations.cancel),
        ),
        FilledButton(
          onPressed: _createLibrary,
          child: Text(localizations.create),
        ),
      ],
    );
  }
}
