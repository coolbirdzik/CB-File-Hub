import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/screens/album_management/album_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The image-library root.
///
/// Image sources use the existing album model so covers, NSFW visibility,
/// selection, view preferences, and album contents all stay in one place.
class GalleryHubScreen extends StatelessWidget {
  final String tabId;

  const GalleryHubScreen({super.key, required this.tabId});

  @override
  Widget build(BuildContext context) {
    return AlbumManagementScreen(
      tabId: tabId,
      rootPath: '#gallery',
      title: AppLocalizations.of(context)!.imageGallery,
      icon: PhosphorIconsLight.images,
      sourceGalleryMode: true,
    );
  }
}
