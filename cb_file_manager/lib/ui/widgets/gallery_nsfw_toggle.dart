import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:flutter/material.dart';

class GalleryNsfwToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const GalleryNsfwToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(l10n.galleryNsfwLabel),
      subtitle: Text(l10n.galleryNsfwDescription),
      contentPadding: EdgeInsets.zero,
    );
  }
}

PopupMenuEntry<String> galleryNsfwMenuItem(BuildContext context, bool isNsfw) =>
    CheckedPopupMenuItem<String>(
      value: 'nsfw',
      checked: isNsfw,
      child: Text(AppLocalizations.of(context)!.galleryNsfwLabel),
    );
