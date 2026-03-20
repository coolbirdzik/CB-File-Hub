import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../config/languages/app_localizations.dart';
import '../../../utils/route.dart';

/// A component that displays video information.
class VideoInfoDialog extends StatelessWidget {
  final File file;
  final Map<String, dynamic>? videoMetadata;

  const VideoInfoDialog({
    Key? key,
    required this.file,
    this.videoMetadata,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.videoInfo),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _infoRow(
                l10n.fileName, file.path.split(Platform.pathSeparator).last),
            const Divider(),
            _infoRow(l10n.filePath, file.path),
            const Divider(),
            _infoRow(l10n.fileType, file.path.split('.').last.toUpperCase()),
            if (videoMetadata != null) ...[
              const Divider(),
              _infoRow(l10n.duration, l10n.unknown),
              const Divider(),
              _infoRow(l10n.resolution, l10n.unknown),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => RouteUtils.safePopDialog(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
