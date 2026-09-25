import 'dart:io';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Error toast for a failed delete, shared by every screen that deletes files.
///
/// When [retryPaths] is non-empty on Windows the toast carries a
/// "Retry (admin access)" action that hands those paths to
/// [onRetryAsAdministrator]; otherwise it is a plain error toast.
class DeleteFailureToast {
  const DeleteFailureToast._();

  static void show(
    BuildContext context,
    String message, {
    List<String> retryPaths = const [],
    void Function(List<String> retryPaths)? onRetryAsAdministrator,
  }) {
    if (retryPaths.isEmpty ||
        onRetryAsAdministrator == null ||
        !Platform.isWindows) {
      AppToast.error(context, message, duration: const Duration(seconds: 7));
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final paths = List<String>.unmodifiable(retryPaths);
    AppToast.show(
      context,
      message,
      icon: PhosphorIconsLight.warningCircle,
      accentColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 12),
      actionLabel: '${l10n.retry} (${l10n.adminAccess})',
      onAction: () => onRetryAsAdministrator(paths),
    );
  }

  /// The subset of [failedPaths] whose error was "access denied" — the only
  /// failures an elevated retry can fix.
  static List<String> accessDeniedPaths(
    Iterable<String> failedPaths,
    Map<String, Object> errorsByPath,
  ) {
    return failedPaths
        .where((path) {
          final error = errorsByPath[path];
          return error is FileSystemException && error.osError?.errorCode == 5;
        })
        .toList(growable: false);
  }
}
