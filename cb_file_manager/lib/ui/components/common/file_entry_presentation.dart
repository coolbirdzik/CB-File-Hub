import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

/// Display names for indexed files whose storage names may be content hashes.
/// Paths retain their real identity for selection, icons and file operations.
class FileEntryPresentation extends InheritedWidget {
  final Map<String, String> names;
  final Set<String> virtualPaths;

  const FileEntryPresentation({
    super.key,
    required this.names,
    this.virtualPaths = const {},
    required super.child,
  });

  static String nameOf(
    BuildContext context,
    String filePath, {
    String? fallback,
  }) =>
      context
          .dependOnInheritedWidgetOfExactType<FileEntryPresentation>()
          ?.names[filePath] ??
      fallback ??
      path.basename(filePath);

  @override
  bool updateShouldNotify(FileEntryPresentation oldWidget) =>
      names != oldWidget.names || virtualPaths != oldWidget.virtualPaths;

  static bool isVirtual(BuildContext context, String filePath) =>
      context
          .dependOnInheritedWidgetOfExactType<FileEntryPresentation>()
          ?.virtualPaths
          .contains(filePath) ??
      false;
}
