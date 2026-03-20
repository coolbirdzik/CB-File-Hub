import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cb_file_manager/services/album_service.dart';

class BatchAddDialog extends StatefulWidget {
  final int albumId;

  const BatchAddDialog({Key? key, required this.albumId}) : super(key: key);

  @override
  State<BatchAddDialog> createState() => _BatchAddDialogState();
}

class _BatchAddDialogState extends State<BatchAddDialog> {
  bool _isProcessing = false;
  String _statusMessage = '';

  Future<void> _addFromFolder() async {
    try {
      final directoryPath = await FilePicker.platform.getDirectoryPath();
      if (directoryPath != null) {
        // Chạy thêm vào album ở background, không chặn UI
        AlbumService.instance.addFilesFromDirectoryInBackground(
          widget.albumId,
          directoryPath,
        );

        if (mounted) {
          Navigator.pop(context, {'background': true});
        }
      } else {
        // User cancelled folder selection
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _addSelectedFiles() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Selecting files...';
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null) {
        setState(() => _statusMessage = 'Adding selected files...');

        final filePaths =
            result.paths.where((p) => p != null).cast<String>().toList();
        final addResult = await AlbumService.instance
            .addFilesToAlbum(widget.albumId, filePaths);

        if (mounted) {
          Navigator.pop(
              context, {'added': addResult, 'total': filePaths.length});
        }
      } else {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add to Album'),
      content: _isProcessing
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_statusMessage),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(PhosphorIconsLight.folderOpen),
                  title: const Text('Add from a folder'),
                  subtitle: const Text('Add all images from a selected folder'),
                  onTap: _addFromFolder,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(PhosphorIconsLight.images),
                  title: const Text('Add selected photos'),
                  subtitle: const Text('Choose specific image files to add'),
                  onTap: _addSelectedFiles,
                ),
              ],
            ),
      actions: _isProcessing
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
    );
  }
}
