import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/app_update/app_update_models.dart';
import 'package:cb_file_manager/services/app_update/app_update_service.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

/// Opens the update dialog, starting a check when nothing is known yet.
Future<void> showAppUpdateDialog(BuildContext context) {
  final service = AppUpdateService.instance;
  if (!service.hasUpdate && service.phase != AppUpdatePhase.checking) {
    service.checkForUpdates();
  }
  return showDialog<void>(
    context: context,
    barrierColor: context.cbColors.scrim,
    // Installing closes the app; outside clicks must not hide that step.
    barrierDismissible: false,
    builder: (_) => const AppUpdateDialog(),
  );
}

/// The dialog body, rebuilt from [AppUpdateService] state.
class AppUpdateDialog extends StatelessWidget {
  const AppUpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final service = AppUpdateService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) => _buildForPhase(context, service),
    );
  }

  Widget _buildForPhase(BuildContext context, AppUpdateService service) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.cbColors;
    final update = service.update;
    final versionLabel = update != null && update.version.isNotEmpty
        ? l10n.updateAvailableVersion(update.version)
        : l10n.updateAvailableGeneric;
    final currentLabel = service.currentVersion.isEmpty
        ? null
        : l10n.updateCurrentVersion(service.currentVersion);

    void close() => Navigator.of(context).pop();

    switch (service.phase) {
      case AppUpdatePhase.idle:
      case AppUpdatePhase.checking:
        return CbDialog(
          title: l10n.checkForUpdates,
          icon: PhosphorIconsLight.arrowsClockwise,
          content: _StatusRow(busy: true, text: l10n.updateChecking),
        );

      case AppUpdatePhase.upToDate:
        return CbDialog(
          title: l10n.updateUpToDate,
          subtitle: currentLabel,
          icon: PhosphorIconsLight.checkCircle,
          actions: [
            CbButton(
              label: MaterialLocalizations.of(context).okButtonLabel,
              variant: CbButtonVariant.primary,
              autofocus: true,
              onPressed: close,
            ),
          ],
        );

      case AppUpdatePhase.available:
        final notes = trimReleaseNotes(update?.releaseNotes ?? '');
        return CbDialog(
          title: l10n.updateAvailableTitle,
          subtitle: currentLabel == null
              ? versionLabel
              : '$versionLabel\n$currentLabel',
          icon: PhosphorIconsLight.arrowCircleUp,
          width: 520,
          content: notes.isEmpty
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.updateReleaseNotes,
                      style: CbTypography.headingSm.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: CbSpacing.sm),
                    MarkdownBody(data: notes),
                  ],
                ),
          actions: [
            CbButton(
              label: l10n.updateLater,
              variant: CbButtonVariant.secondary,
              onPressed: close,
            ),
            CbButton(
              label: service.distribution?.isStore == true
                  ? l10n.updateAction
                  : l10n.updateDownload,
              icon: PhosphorIconsLight.downloadSimple,
              variant: CbButtonVariant.primary,
              autofocus: true,
              onPressed: service.startDownload,
            ),
          ],
        );

      case AppUpdatePhase.downloading:
        final progress = service.progress;
        final String detail;
        if (progress == null) {
          detail = l10n.updateStoreDownloading;
        } else {
          final percent = '${(progress * 100).floor()}%';
          detail = service.totalBytes > 0
              ? '$percent · ${FormatUtils.formatFileSize(service.receivedBytes)}'
                    ' / ${FormatUtils.formatFileSize(service.totalBytes)}'
              : percent;
        }
        return CbDialog(
          title: l10n.updateDownloading,
          subtitle: versionLabel,
          icon: PhosphorIconsLight.downloadSimple,
          showCloseButton: false,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(CbRadii.full),
                child: LinearProgressIndicator(value: progress, minHeight: 6),
              ),
              const SizedBox(height: CbSpacing.sm),
              Text(
                detail,
                style: CbTypography.body.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          actions: [
            // Store downloads keep going in the background; ours can stop.
            if (service.canCancelDownload)
              CbButton(
                label: MaterialLocalizations.of(context).cancelButtonLabel,
                variant: CbButtonVariant.secondary,
                onPressed: service.cancelDownload,
              )
            else
              CbButton(
                label: l10n.updateLater,
                variant: CbButtonVariant.secondary,
                onPressed: close,
              ),
          ],
        );

      case AppUpdatePhase.readyToInstall:
        final message = service.distribution == AppDistribution.windowsInstaller
            ? '${l10n.updateReadyMessage}\n${l10n.updateAdminHint}'
            : l10n.updateReadyMessage;
        return CbDialog(
          title: l10n.updateReadyTitle,
          subtitle: versionLabel,
          icon: PhosphorIconsLight.checkCircle,
          content: Text(
            message,
            style: CbTypography.body.copyWith(color: c.textSecondary),
          ),
          actions: [
            CbButton(
              label: l10n.updateLater,
              variant: CbButtonVariant.secondary,
              onPressed: close,
            ),
            CbButton(
              label: l10n.updateInstallNow,
              icon: PhosphorIconsLight.arrowClockwise,
              variant: CbButtonVariant.primary,
              autofocus: true,
              onPressed: service.installAndRestart,
            ),
          ],
        );

      case AppUpdatePhase.installing:
        return CbDialog(
          title: l10n.updateInstalling,
          subtitle: versionLabel,
          icon: PhosphorIconsLight.arrowCircleUp,
          showCloseButton: false,
          content: _StatusRow(busy: true, text: l10n.updateInstalling),
        );

      case AppUpdatePhase.error:
        return CbDialog(
          title: l10n.updateFailed,
          subtitle: service.error,
          icon: PhosphorIconsLight.warningCircle,
          destructive: true,
          actions: [
            CbButton(
              label: MaterialLocalizations.of(context).closeButtonLabel,
              variant: CbButtonVariant.secondary,
              onPressed: close,
            ),
            CbButton(
              label: l10n.updateRetry,
              variant: CbButtonVariant.primary,
              autofocus: true,
              onPressed: update != null
                  ? service.startDownload
                  : () => service.checkForUpdates(),
            ),
          ],
        );
    }
  }
}

/// Keeps the "What's changed" part of the generated GitHub release notes and
/// drops the title plus the download/installation instructions that follow.
String trimReleaseNotes(String notes) {
  final kept = <String>[];
  for (final line in notes.replaceAll('\r\n', '\n').split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('# ')) continue;
    if (trimmed.startsWith('## ') &&
        (trimmed.contains('Downloads') || trimmed.contains('Installation'))) {
      break;
    }
    kept.add(line);
  }
  return kept.join('\n').trim();
}

class _StatusRow extends StatelessWidget {
  final bool busy;
  final String text;

  const _StatusRow({required this.busy, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (busy) ...[
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: CbSpacing.md),
        ],
        Expanded(
          child: Text(
            text,
            style: CbTypography.body.copyWith(
              color: context.cbColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
