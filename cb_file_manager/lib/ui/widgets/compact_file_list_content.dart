import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../helpers/files/file_type_registry.dart';
import '../components/common/optimized_interaction_handler.dart';
import '../controllers/inline_rename_controller.dart';
import 'inline_rename_field.dart';

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
    final name = displayName ?? p.basename(path);
    final rename = InlineRenameScope.maybeOf(context);
    final isRenaming = rename != null && rename.renamingPath == path;
    final style = Theme.of(context).textTheme.bodyMedium;
    return SizedBox(
      height:
          40 *
          (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
            1.0,
            double.infinity,
          ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (!isFolder && !isTag)
              OptimizedFileIcon(
                file: File(path),
                isVideo: false,
                isImage: false,
                size: 20,
                fallbackIcon: FileTypeRegistry.getIcon(p.extension(path)),
                fallbackColor: FileTypeRegistry.getColor(p.extension(path)),
              )
            else
              Icon(
                isTag ? PhosphorIconsLight.tag : PhosphorIconsFill.folder,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: isRenaming
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
            ),
          ],
        ),
      ),
    );
  }
}
