import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/helpers/core/user_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'app_toast.dart';

/// Shared labels, platform availability and persistence for Settings and
/// the folder browser's more menu.
enum FileBrowserPreferenceOption {
  extensions,
  renameExtension,
  hidden,
  system,
  checkboxes,
  singleClick;

  static List<FileBrowserPreferenceOption> available([
    TargetPlatform? platform,
  ]) {
    final target = platform ?? defaultTargetPlatform;
    return [
      extensions,
      renameExtension,
      hidden,
      if (target == TargetPlatform.windows) system,
      checkboxes,
      if (target == TargetPlatform.windows ||
          target == TargetPlatform.macOS ||
          target == TargetPlatform.linux)
        singleClick,
    ];
  }

  String get menuId => this == renameExtension
      ? 'toggle_file_extension_rename'
      : 'file_browser_$name';

  String label(AppLocalizations l) => switch (this) {
    extensions => l.showFileExtensions,
    renameExtension => l.allowFileExtensionRename,
    hidden => l.showHiddenItems,
    system => l.showSystemItems,
    checkboxes => l.fileSelectionCheckboxes,
    singleClick => l.singleClickToOpen,
  };

  String description(AppLocalizations l) => switch (this) {
    extensions => l.showFileExtensionsDescription,
    renameExtension => l.fileBrowserRenameExtensionDescription,
    hidden => l.showHiddenItemsDescription,
    system => l.showSystemItemsDescription,
    checkboxes => l.fileSelectionCheckboxesDescription,
    singleClick => l.singleClickToOpenDescription,
  };

  IconData get icon => switch (this) {
    extensions => PhosphorIconsLight.fileText,
    renameExtension => PhosphorIconsLight.pencilSimple,
    hidden => PhosphorIconsLight.eyeSlash,
    system => PhosphorIconsLight.shieldCheck,
    checkboxes => PhosphorIconsLight.checkSquare,
    singleClick => PhosphorIconsLight.cursorClick,
  };

  bool isEnabled(UserPreferences preferences) {
    final options = preferences.fileBrowserOptions.value;
    return switch (this) {
      extensions => options.showExtensions,
      renameExtension => preferences.allowFileExtensionRename.value,
      hidden => options.showHidden,
      system => options.showSystem,
      checkboxes => options.selectionCheckboxes,
      singleClick => options.singleClickToOpen,
    };
  }

  Future<bool> setEnabled(UserPreferences preferences, bool value) {
    final options = preferences.fileBrowserOptions.value;
    return switch (this) {
      extensions => preferences.setFileBrowserOptions(
        options.copyWith(showExtensions: value),
      ),
      renameExtension => preferences.setAllowFileExtensionRename(value),
      hidden => preferences.setFileBrowserOptions(
        options.copyWith(showHidden: value),
      ),
      system => preferences.setFileBrowserOptions(
        options.copyWith(showSystem: value),
      ),
      checkboxes => preferences.setFileBrowserOptions(
        options.copyWith(selectionCheckboxes: value),
      ),
      singleClick => preferences.setFileBrowserOptions(
        options.copyWith(singleClickToOpen: value),
      ),
    };
  }

  Future<void> toggleFromMenu(BuildContext context) async {
    final preferences = UserPreferences.instance;
    try {
      if (await setEnabled(preferences, !isEnabled(preferences))) return;
    } catch (_) {
      // Use the same localized save error as the Settings section.
    }
    if (context.mounted) {
      AppToast.error(
        context,
        AppLocalizations.of(context)!.fileBrowserSaveFailed,
      );
    }
  }
}
