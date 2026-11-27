import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'app_toast.dart';
import 'operation_progress_overlay.dart';

/// Acknowledges acceptance immediately, without claiming deletion succeeded.
class DeleteQueuedToast {
  static void show(
    BuildContext context, {
    required int count,
    required bool permanent,
    required OperationProgressController controller,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context, rootNavigator: true);
    AppToast.show(
      context,
      l10n.deleteQueued(count, permanent),
      icon: PhosphorIconsLight.trash,
      duration: const Duration(seconds: 4),
      actionLabel: l10n.viewOperationProgress,
      onAction: () {
        if (!navigator.mounted) return;
        controller.markAllSeen();
        showDialog<void>(
          context: navigator.context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: StatusCenterPanel(controller: controller),
          ),
        );
      },
    );
  }
}
