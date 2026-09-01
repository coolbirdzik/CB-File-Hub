import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import 'package:cb_file_manager/helpers/files/archive_path_utils.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';
import 'package:cb_file_manager/ui/tab_manager/core/tab_manager.dart';

/// Opens an archive for in-tab browsing (Windows Explorer style).
class ArchiveNavigation {
  ArchiveNavigation._();

  static void openBrowse(
    BuildContext context, {
    required String archiveFilePath,
    String? tabId,
    FolderListBloc? folderListBloc,
  }) {
    final virtualPath = ArchivePathUtils.build(archiveFile: archiveFilePath);
    final tabBloc = context.read<TabManagerBloc>();
    final effectiveTabId = tabId ?? tabBloc.state.activeTabId;
    if (effectiveTabId == null) return;

    tabBloc.add(UpdateTabPath(effectiveTabId, virtualPath));
    tabBloc.add(UpdateTabName(effectiveTabId, p.basename(archiveFilePath)));

    final bloc = folderListBloc;
    if (bloc != null) {
      bloc.add(FolderListLoad(virtualPath));
    }
  }
}
