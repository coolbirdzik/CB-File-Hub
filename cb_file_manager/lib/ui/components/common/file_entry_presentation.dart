import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'file_browser_options_scope.dart';

/// Display names for indexed files and storage roots. Indexed files can have
/// content-hash storage names; drive roots have no filename component.
/// Paths retain their real identity for selection, icons and file operations.
class FileEntryPresentation extends InheritedWidget {
  final Map<String, String> names;
  final Set<String> virtualPaths;
  final Widget? Function(BuildContext context, String path, double size)?
  leadingBuilder;

  const FileEntryPresentation({
    super.key,
    required this.names,
    this.virtualPaths = const {},
    this.leadingBuilder,
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

  /// Display-only extension preference. Folders, input fields and paths keep
  /// their original names.
  static String fileNameOf(
    BuildContext context,
    String filePath, {
    String? fallback,
  }) => FileBrowserOptionsScope.of(
    context,
  ).fileLabel(nameOf(context, filePath, fallback: fallback));

  @override
  bool updateShouldNotify(FileEntryPresentation oldWidget) =>
      names != oldWidget.names ||
      virtualPaths != oldWidget.virtualPaths ||
      leadingBuilder != oldWidget.leadingBuilder;

  static bool isVirtual(BuildContext context, String filePath) =>
      context
          .dependOnInheritedWidgetOfExactType<FileEntryPresentation>()
          ?.virtualPaths
          .contains(filePath) ??
      false;

  static Widget? leadingOf(
    BuildContext context,
    String filePath, {
    double size = 20,
  }) => context
      .dependOnInheritedWidgetOfExactType<FileEntryPresentation>()
      ?.leadingBuilder
      ?.call(context, filePath, size);
}
