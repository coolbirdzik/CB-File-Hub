import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:cb_file_manager/helpers/files/file_browser_options.dart';
import 'package:material_ui/material_ui.dart';

/// A single live configuration for both Material and Fluent host apps.
class FileBrowserOptionsScope
    extends InheritedNotifier<ValueNotifier<FileBrowserOptions>> {
  FileBrowserOptionsScope({
    super.key,
    ValueNotifier<FileBrowserOptions>? options,
    required super.child,
  }) : super(notifier: options ?? UserPreferences.instance.fileBrowserOptions);

  static FileBrowserOptions of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FileBrowserOptionsScope>()
          ?.notifier
          ?.value ??
      UserPreferences.instance.fileBrowserOptions.value;
}

/// Independent checkbox hit target: clicking it adds/removes an item, rather
/// than opening it or replacing the selection. The normal row gestures remain.
class FileSelectionFrame extends StatelessWidget {
  const FileSelectionFrame({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.child,
    this.grid = false,
    this.details = false,
  });

  final bool selected, grid, details;
  final VoidCallback? onToggle;
  final Widget child;
  static const double checkWidth = 28;

  @override
  Widget build(BuildContext context) {
    if (!FileBrowserOptionsScope.of(context).selectionCheckboxes ||
        onToggle == null) {
      return child;
    }
    final checkbox = SizedBox(
      width: checkWidth,
      height: checkWidth,
      child: Checkbox(
        key: const ValueKey('browser-selection-checkbox'),
        value: selected,
        onChanged: (_) => onToggle!(),
        semanticLabel: AppLocalizations.of(context)?.selectItems,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
    if (grid || details) {
      return Stack(
        children: [
          child,
          Positioned(
            left: grid ? 4 : 0,
            top: grid ? 4 : 0,
            bottom: grid ? null : 0,
            child: Center(
              child: grid
                  ? Material(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(5),
                      child: checkbox,
                    )
                  : checkbox,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        checkbox,
        Expanded(child: child),
      ],
    );
  }
}
