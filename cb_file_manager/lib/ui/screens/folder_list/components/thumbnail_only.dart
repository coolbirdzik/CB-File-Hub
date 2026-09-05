import 'package:flutter/material.dart';
import 'dart:io'; // Import dart:io for FileSystemEntity
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/ui/widgets/thumbnail_loader.dart';
import 'package:cb_file_manager/helpers/files/file_type_registry.dart';
import 'package:cb_file_manager/helpers/files/file_icon_helper.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// A widget that displays only the thumbnail of a file item.
/// This widget is designed to be constant and not rebuild on selection changes.
class ThumbnailOnly extends StatefulWidget {
  final FileSystemEntity file;
  final double iconSize;

  const ThumbnailOnly({super.key, required this.file, this.iconSize = 48.0});

  @override
  State<ThumbnailOnly> createState() => _ThumbnailOnlyState();
}

class _ThumbnailOnlyState extends State<ThumbnailOnly>
    with AutomaticKeepAliveClientMixin {
  late Future<Widget> _iconFuture;

  @override
  bool get wantKeepAlive {
    final extension = p.extension(widget.file.path).toLowerCase();
    final category = FileTypeRegistry.getCategory(extension);
    return category == FileCategory.video || category == FileCategory.image;
  }

  @override
  void initState() {
    super.initState();
    // Initialize the icon future for non-media files
    final extension = p.extension(widget.file.path).toLowerCase();
    final category = FileTypeRegistry.getCategory(extension);
    final isVideo = category == FileCategory.video;
    final isImage = category == FileCategory.image;

    if (!isVideo && !isImage && widget.file is File) {
      _iconFuture = FileIconHelper.getIconForFile(
        widget.file as File,
        size: widget.iconSize,
      );
    }
  }

  @override
  void didUpdateWidget(ThumbnailOnly oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file.path != oldWidget.file.path) {
      final extension = p.extension(widget.file.path).toLowerCase();
      final category = FileTypeRegistry.getCategory(extension);
      final isVideo = category == FileCategory.video;
      final isImage = category == FileCategory.image;

      if (!isVideo && !isImage && widget.file is File) {
        _iconFuture = FileIconHelper.getIconForFile(
          widget.file as File,
          size: widget.iconSize,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final extension = p.extension(widget.file.path).toLowerCase();
    final category = FileTypeRegistry.getCategory(extension);
    final isVideo = category == FileCategory.video;
    final isImage = category == FileCategory.image;
    final genericIcon = FileTypeRegistry.getIcon(extension);

    // For non-media files, show icon directly (Windows Explorer style - no background/border)
    if (!isVideo && !isImage && widget.file is File) {
      return RepaintBoundary(
        child: Center(
          child: FutureBuilder<Widget>(
            future: _iconFuture,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return snapshot.data!;
              }
              // Show generic icon while loading
              return Icon(
                genericIcon,
                size: widget.iconSize,
                color: Theme.of(context).colorScheme.secondary,
              );
            },
          ),
        ),
      );
    }

    // For media files (video/image), use ThumbnailLoader with no border radius
    return ValueListenableBuilder<FileThumbnailFitMode>(
      valueListenable: UserPreferences.instance.fileThumbnailFitMode,
      builder: (context, fitMode, _) => RepaintBoundary(
        child: ThumbnailLoader(
          key: ValueKey('thumb-loader-${widget.file.path}'),
          filePath: widget.file.path,
          isVideo: isVideo,
          isImage: isImage,
          width: double.infinity,
          height: double.infinity,
          fit: fitMode == FileThumbnailFitMode.contain
              ? BoxFit.contain
              : BoxFit.cover,
          isPriority:
              false, // Don't mark all as priority to reduce concurrent loads
          borderRadius: BorderRadius.circular(0),
          showLoadingIndicator: true,
          fallbackBuilder: () => isVideo
              ? Center(
                  child: Icon(
                    PhosphorIconsLight.playCircle,
                    size: widget.iconSize,
                    color: Colors.white70,
                  ),
                )
              : Center(
                  child: Icon(
                    genericIcon,
                    size: widget.iconSize,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
        ),
      ),
    );
  }
}
