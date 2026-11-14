import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../core/service_locator.dart';
import '../../services/windowing/desktop_windowing_service.dart';
import '../tab_manager/core/tab_manager.dart';

/// Opens output in the app. A separate player routes to a file-browser
/// window; an in-window fullscreen player returns to its new browser tab.
Future<void> openVideoOutputFolderInApp(
  BuildContext context,
  String folderPath, {
  String? highlightedFileName,
  DesktopWindowingService? windows,
}) async {
  final path = p.normalize(p.absolute(folderPath));
  if (!await Directory(path).exists()) {
    throw FileSystemException('Output folder does not exist.', path);
  }
  if (!context.mounted) return;
  TabManagerBloc? tabs;
  try {
    tabs = context.read<TabManagerBloc>();
  } on ProviderNotFoundException {
    // Dedicated players and root navigator routes have no tab provider.
  }
  if (tabs != null && !tabs.isClosed) {
    final name = p.basename(path);
    tabs.add(
      AddTab(
        path: path,
        name: name.isEmpty ? path : name,
        highlightedFileName: highlightedFileName,
      ),
    );
  } else {
    final service =
        windows ??
        (locator.isRegistered<DesktopWindowingService>()
            ? locator<DesktopWindowingService>()
            : DesktopWindowingService());
    if (!await service.openFolderInNewTab(
      path,
      highlightedFileName: highlightedFileName,
    )) {
      throw StateError('Could not open output folder in an app tab: $path');
    }
  }
  if (!context.mounted) return;
  final route = ModalRoute.of(context);
  if (route is PageRoute &&
      route.fullscreenDialog &&
      route.isCurrent &&
      Navigator.of(context).canPop()) {
    Navigator.of(context).pop();
  }
}
