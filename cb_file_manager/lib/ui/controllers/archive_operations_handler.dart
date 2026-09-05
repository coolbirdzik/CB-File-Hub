import 'dart:io';

import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/archive/archive_service.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// UI-facing archive extract/browse helpers.
class ArchiveOperationsHandler {
  static ArchiveService get _service => locator<ArchiveService>();

  static Future<void> extractHere({
    required BuildContext context,
    required File archiveFile,
    FolderListBloc? folderListBloc,
  }) {
    return extractToDirectory(
      context: context,
      archiveFile: archiveFile,
      destinationDir: archiveFile.parent.path,
      folderListBloc: folderListBloc,
    );
  }

  static Future<void> extractToDirectory({
    required BuildContext context,
    required File archiveFile,
    String? destinationDir,
    FolderListBloc? folderListBloc,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final dest =
        destinationDir ??
        await FilePicker.getDirectoryPath(
          dialogTitle: l10n.archiveExtractToTitle,
        );
    if (dest == null || dest.isEmpty) return;
    if (!context.mounted) return;

    final progress = locator<OperationProgressController>();
    final progressId = progress.begin(
      title: l10n.archiveExtracting,
      total: 1,
      sourcePath: archiveFile.path,
      destinationPath: dest,
      kind: OperationProgressKind.generic,
    );

    try {
      await _service.extractAll(
        archivePath: archiveFile.path,
        destinationDir: dest,
        onProgress: (completed, total) {
          progress.update(
            progressId,
            completed: completed,
            total: total,
            detail: p.basename(archiveFile.path),
          );
        },
      );
      progress.succeed(progressId, detail: l10n.archiveExtractComplete);

      if (context.mounted) {
        AppToast.success(context, l10n.archiveExtractComplete);
      }

      folderListBloc?.add(FolderListRefresh(dest));
    } catch (e) {
      progress.fail(progressId, detail: e.toString());
      if (context.mounted) {
        AppToast.error(context, l10n.archiveExtractFailed(e.toString()));
      }
    }
  }
}
