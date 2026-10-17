import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cb_file_manager/services/album_service.dart';
import 'package:cb_file_manager/config/translation_helper.dart';

class BatchAddDialog extends StatefulWidget {
  final int albumId;

  const BatchAddDialog({super.key, required this.albumId});

  @override
  State<BatchAddDialog> createState() => _BatchAddDialogState();
}

class _BatchAddDialogState extends State<BatchAddDialog> {
  bool _isProcessing = false;
  String _statusMessage = '';

  Future<void> _addFromFolder() async {
    try {
      final directoryPath = await FilePicker.getDirectoryPath();
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
          _statusMessage = context.tr.errorWithDetail(e.toString());
        });
      }
    }
  }

  Future<void> _addSelectedFiles() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = context.tr.albumSelectingFiles;
    });

    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);

      if (picked.isNotEmpty) {
        setState(() => _statusMessage = context.tr.albumAddingSelectedFiles);

        final filePaths = picked
            .map((f) => f.path)
            .whereType<String>()
            .toList();
        final addResult = await AlbumService.instance.addFilesToAlbum(
          widget.albumId,
          filePaths,
        );

        if (mounted) {
          Navigator.pop(context, {
            'added': addResult,
            'total': filePaths.length,
          });
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
          _statusMessage = context.tr.errorWithDetail(e.toString());
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr.albumAddTo),
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
                  title: Text(context.tr.albumAddFromFolder),
                  subtitle: Text(context.tr.albumAddFromFolderDesc),
                  onTap: _addFromFolder,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(PhosphorIconsLight.images),
                  title: Text(context.tr.albumAddSelectedPhotos),
                  subtitle: Text(context.tr.albumAddSelectedPhotosDesc),
                  onTap: _addSelectedFiles,
                ),
              ],
            ),
      actions: _isProcessing
          ? null
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.tr.cancel),
              ),
            ],
    );
  }
}
