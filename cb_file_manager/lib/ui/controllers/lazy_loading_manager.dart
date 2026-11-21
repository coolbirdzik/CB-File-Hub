import 'package:material_ui/material_ui.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_bloc.dart';
import 'package:cb_file_manager/ui/screens/folder_list/folder_list_event.dart';

/// Manages lazy loading of drives for Windows platform
class LazyLoadingManager {
  /// Start lazy loading drives in the background
  ///
  /// This method loads drives asynchronously to improve initial UI responsiveness
  static void startLazyLoadingDrives({
    required FolderListBloc folderListBloc,
    required bool Function() isMounted,
    required VoidCallback onComplete,
  }) {
    // Small delay to ensure UI is responsive first
    Future.delayed(const Duration(milliseconds: 50), () {
      if (!isMounted()) return;

      // Load drives in the background
      folderListBloc.add(const FolderListLoadDrives());

      // After a reasonable time for drives to load, update UI
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!isMounted()) return;
        onComplete();
      });
    });
  }
}
