import 'package:flutter/material.dart';
import 'dart:io'; // Import dart:io for FileSystemEntity
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:path/path.dart' as p;

/// A widget that displays the core content of a file item (thumbnail and name).
/// This widget is designed to be constant and not rebuild on selection changes.
class ThumbnailContent extends StatelessWidget {
  final FileSystemEntity file;
  final double iconSize;

  const ThumbnailContent({
    Key? key,
    required this.file,
    this.iconSize = 48.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final extension = p.extension(file.path).toLowerCase();
    final category = FileTypeRegistry.getCategory(extension);
    final isVideo = category == FileCategory.video;
    final isImage = category == FileCategory.image;
    final icon = FileTypeRegistry.getIcon(extension);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: RepaintBoundary(
              child: ThumbnailLoader(
                key: ValueKey('thumb-loader-${file.path}'),
                filePath: file.path,
                isVideo: isVideo,
                isImage: isImage,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
                isPriority: true,
                borderRadius: BorderRadius.circular(16.0),
                showLoadingIndicator: true, // Re-enable skeleton loading
                fallbackBuilder: () => Icon(
                  icon,
                  size: iconSize,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
