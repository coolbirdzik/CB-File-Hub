import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../helpers/files/file_type_registry.dart';
import '../components/common/file_entry_presentation.dart';
import '../components/common/optimized_interaction_handler.dart';
import '../controllers/inline_rename_controller.dart';
import 'inline_rename_field.dart';
import 'compact_list_content.dart';

/// Lightweight List content: no thumbnails, metadata or directory-size scans.
class CompactFileListContent extends StatelessWidget {
  const CompactFileListContent({
    super.key,
    required this.path,
    this.isFolder = false,
    this.displayName,
    this.isTag = false,
  });

  final String path;
  final bool isFolder;
  final String? displayName;
  final bool isTag;

  @override
  Widget build(BuildContext context) {
    final name = displayName ?? FileEntryPresentation.nameOf(context, path);
    final rename = InlineRenameScope.maybeOf(context);
    final isRenaming = rename != null && rename.renamingPath == path;
    final style = Theme.of(context).textTheme.bodyMedium;
    return CompactListContent(
      leading: !isFolder && !isTag
          ? OptimizedFileIcon(
              file: File(path),
              isVideo: false,
              isImage: false,
              size: 20,
              fallbackIcon: FileTypeRegistry.getIcon(p.extension(path)),
              fallbackColor: FileTypeRegistry.getColor(p.extension(path)),
            )
          : Icon(
              isTag ? PhosphorIconsLight.tag : PhosphorIconsFill.folder,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
      label: isRenaming
          ? InlineRenameField(
              controller: rename,
              onCommit: () => rename.commitRename(context),
              onCancel: rename.cancelRename,
              textStyle: style,
              textAlign: TextAlign.start,
            )
          : Text(
              name,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }
}
