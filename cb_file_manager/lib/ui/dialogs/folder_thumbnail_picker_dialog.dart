import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/media/video_thumbnail_helper.dart';
import 'package:cb_file_manager/ui/dialogs/media_picker_dialog.dart';
import 'package:cb_file_manager/ui/utils/file_type_utils.dart';
import 'package:material_ui/material_ui.dart';

Future<String?> showFolderThumbnailPickerDialog(
  BuildContext context,
  String folderPath,
) {
  final l10n = AppLocalizations.of(context)!;

  return showMediaPickerDialog(
    context,
    MediaPickerConfig(
      title: l10n.chooseThumbnail,
      initialPath: folderPath,
      rootPath: folderPath,
      restrictToRoot: true,
      emptyMessage: l10n.noMediaFilesFound,
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
}
