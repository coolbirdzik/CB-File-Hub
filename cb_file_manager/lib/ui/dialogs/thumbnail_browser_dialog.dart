import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/helpers/platform_paths.dart';
import 'package:cb_file_manager/ui/dialogs/image_crop_dialog.dart';
import 'package:cb_file_manager/ui/dialogs/media_picker_dialog.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:flutter/material.dart';

/// Opens the shared media browser configured for picking a thumbnail image.
///
/// This is the app-wide, common entry point for "browse and pick an image to
/// use as a thumbnail" (tags, folders, albums, …). It reuses
/// [showMediaPickerDialog] so the browsing UX is identical to the Windows-style
/// file browser, and adds two thumbnail-specific behaviors:
///
///   * **Tag search** — a mode toggle lets the user find media by tag instead
///     of navigating folders (enabled by default; set [enableTagSearch] false
///     to hide it). Pass [initialTagQuery] to open straight into tag search
///     showing that tag's files (e.g. the tag being assigned a thumbnail).
///   * **Video-frame extraction** — choosing a video opens the frame picker so
///     the user scrubs to a frame; the returned path is the extracted JPEG, not
///     the video file. This makes the returned path always safe to store as a
///     still-image thumbnail.
///   * **Cropping** — after an image (or extracted video frame) is picked, the
///     user is offered a crop step so the stored thumbnail can be framed
///     exactly. The cropped result is written as a fresh JPEG. Set [enableCrop]
///     false to return the picked path unchanged.
///
/// Returns the path to the chosen (and optionally cropped) image, or `null`
/// if the user cancelled.
///
/// [initialPath] defaults to the platform "all images" location. Pass a folder
/// and set [restrictToRoot] to sandbox browsing to that folder.
Future<String?> showThumbnailBrowserDialog(
  BuildContext context, {
  String? title,
  String? initialPath,
  String? rootPath,
  bool restrictToRoot = false,
  bool enableTagSearch = true,
  String? initialTagQuery,
  bool enableCrop = true,
  double? cropAspectRatio,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final startPath = initialPath ?? await PlatformPaths.getAllImagesPath();

  if (!context.mounted) {
    return null;
  }

  final pickedPath = await showMediaPickerDialog(
    context,
    MediaPickerConfig(
      title: title ?? l10n.chooseThumbnail,
      initialPath: startPath,
      rootPath: rootPath,
      restrictToRoot: restrictToRoot,
      emptyMessage: l10n.noMediaFilesFound,
      enableTagSearch: enableTagSearch,
      initialTagQuery: initialTagQuery,
      extractVideoFrame: true,
      fileFilter: (path) =>
          FileTypeUtils.isImageFile(path) ||
          VideoThumbnailHelper.isSupportedVideoFormat(path),
      filters: [
        MediaPickerFilterOption(
          id: 'all',
          label: l10n.all,
          matches: (_) => true,
        ),
        MediaPickerFilterOption(
          id: 'images',
          label: l10n.images,
          matches: FileTypeUtils.isImageFile,
        ),
        MediaPickerFilterOption(
          id: 'videos',
          label: l10n.videos,
          matches: VideoThumbnailHelper.isSupportedVideoFormat,
        ),
      ],
    ),
  );

  if (pickedPath == null || !enableCrop || !context.mounted) {
    return pickedPath;
  }

  // Offer a crop step so the stored thumbnail can be framed exactly.
  return showImageCropDialog(context, pickedPath, aspectRatio: cropAspectRatio);
}
