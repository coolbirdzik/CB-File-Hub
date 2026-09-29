import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/design_system/cb_design_system.dart';
import 'package:cb_file_manager/services/app_update/app_update_models.dart';
import 'package:cb_file_manager/services/app_update/app_update_service.dart';
import 'package:cb_file_manager/services/app_update/release_notes.dart';
import 'package:cb_file_manager/ui/utils/format_utils.dart';

/// Opens the update details, starting a check when nothing is known yet.
///
/// Startup checks never open this on their own: a found update shows in the
/// Status Center (the toolbar bell), where [AppUpdateStatusCard] drives the
/// download and install. This dialog is for reading what changed and for the
/// explicit "Check for updates" action in Settings.
Future<void> showAppUpdateDialog(BuildContext context) {
  final service = AppUpdateService.instance;
  if (!service.hasUpdate && service.phase != AppUpdatePhase.checking) {
    service.checkForUpdates();
  }
  service.markUpdateSeen();
  return showDialog<void>(
    context: context,
    barrierColor: context.cbColors.scrim,
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
      // Installing closes the app; that step must not be dismissed.
      builder: (context, _) => PopScope(
        canPop: service.phase != AppUpdatePhase.installing,
        child: _buildForPhase(context, service),
      ),
    );
  }

  Widget _buildForPhase(BuildContext context, AppUpdateService service) {
    final l10n = AppLocalizations.of(context)!;
    final update = service.update;
    final notes = update?.releaseNotes ?? '';
    // Store updates carry no notes: no empty box then.
    final notesView = trimReleaseNotes(notes).isEmpty
        ? null
        : ReleaseNotesView(notes: notes);
    void close() => Navigator.of(context).maybePop();

    Widget? versions() => update == null
        ? null
        : _VersionTransition(
            current: service.currentVersion,
            next: update.version,
            size: update.assetSize,
          );

    switch (service.phase) {
      case AppUpdatePhase.idle:
      case AppUpdatePhase.checking:
        return _UpdateDialogFrame(
          tone: _Tone.accent,
          icon: PhosphorIconsLight.arrowsClockwise,
          title: l10n.checkForUpdates,
          footer: _BusyRow(text: l10n.updateChecking),
        );

      case AppUpdatePhase.upToDate:
        return _UpdateDialogFrame(
          tone: _Tone.success,
          icon: PhosphorIconsLight.checkCircle,
          title: l10n.updateUpToDate,
          subtitle: service.currentVersion.isEmpty
              ? null
              : Text(
                  l10n.updateCurrentVersion(service.currentVersion),
                  style: CbTypography.body.copyWith(
                    color: context.cbColors.textSecondary,
                  ),
                ),
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
        return _UpdateDialogFrame(
          tone: _Tone.accent,
          icon: PhosphorIconsLight.arrowCircleUp,
          title: l10n.updateAvailableTitle,
          subtitle: versions(),
          body: notesView,
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
        return _UpdateDialogFrame(
          tone: _Tone.accent,
          icon: PhosphorIconsLight.downloadSimple,
          title: l10n.updateDownloading,
          subtitle: versions(),
          body: notesView,
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DownloadProgress(service: service),
              if (service.distribution?.isSelfUpdating == true) ...[
                const SizedBox(height: CbSpacing.sm),
                Text(
                  l10n.updateBackgroundHint,
                  style: CbTypography.bodySm.copyWith(
                    color: context.cbColors.textTertiary,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            // Store downloads keep going in the background; ours can stop.
            if (service.canCancelDownload)
              CbButton(
                label: MaterialLocalizations.of(context).cancelButtonLabel,
                variant: CbButtonVariant.secondary,
                onPressed: service.cancelDownload,
              ),
            CbButton(
              label: MaterialLocalizations.of(context).closeButtonLabel,
              variant: CbButtonVariant.secondary,
              onPressed: close,
            ),
          ],
        );

      case AppUpdatePhase.readyToInstall:
        return _UpdateDialogFrame(
          tone: _Tone.success,
          icon: PhosphorIconsLight.checkCircle,
          title: l10n.updateReadyTitle,
          subtitle: versions(),
          body: notesView,
          footer: _InstallNotice(service: service),
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
        return _UpdateDialogFrame(
          tone: _Tone.accent,
          icon: PhosphorIconsLight.arrowCircleUp,
          title: l10n.updateInstalling,
          subtitle: versions(),
          showClose: false,
          footer: _BusyRow(text: l10n.updateInstalling),
        );

      case AppUpdatePhase.error:
        return _UpdateDialogFrame(
          tone: _Tone.danger,
          icon: PhosphorIconsLight.warningCircle,
          title: l10n.updateFailed,
          subtitle: service.error == null
              ? null
              : Text(
                  service.error!,
                  style: CbTypography.body.copyWith(
                    color: context.cbColors.textSecondary,
                  ),
                ),
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

/// The update entry in the Status Center: what is available and the one
/// action that moves it forward (download, install), with live progress.
class AppUpdateStatusCard extends StatelessWidget {
  const AppUpdateStatusCard({super.key});

  /// Whether the Status Center has an update entry to show.
  static bool isVisible(AppUpdateService service) =>
      service.hasUpdate ||
      (service.phase == AppUpdatePhase.error && service.update != null);

  @override
  Widget build(BuildContext context) {
    final service = AppUpdateService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!isVisible(service)) return const SizedBox.shrink();
        return _buildCard(context, service);
      },
    );
  }

  Widget _buildCard(BuildContext context, AppUpdateService service) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.cbColors;
    final update = service.update!;
    final hasNotes = trimReleaseNotes(update.releaseNotes).isNotEmpty;

    final whatsNew = CbButton(
      label: l10n.updateReleaseNotes,
      variant: CbButtonVariant.ghost,
      size: CbButtonSize.sm,
      onPressed: () => showAppUpdateDialog(context),
    );

    final (_Tone tone, IconData icon, String title) = switch (service.phase) {
      AppUpdatePhase.downloading => (
        _Tone.accent,
        PhosphorIconsLight.downloadSimple,
        l10n.updateDownloading,
      ),
      AppUpdatePhase.readyToInstall => (
        _Tone.success,
        PhosphorIconsLight.checkCircle,
        l10n.updateReadyTitle,
      ),
      AppUpdatePhase.installing => (
        _Tone.accent,
        PhosphorIconsLight.arrowCircleUp,
        l10n.updateInstalling,
      ),
      AppUpdatePhase.error => (
        _Tone.danger,
        PhosphorIconsLight.warningCircle,
        l10n.updateFailed,
      ),
      _ => (
        _Tone.accent,
        PhosphorIconsLight.arrowCircleUp,
        l10n.updateAvailableTitle,
      ),
    };

    final Widget? body;
    final List<Widget> actions;
    switch (service.phase) {
      case AppUpdatePhase.downloading:
        body = _DownloadProgress(service: service, compact: true);
        actions = [
          if (service.canCancelDownload)
            CbButton(
              label: MaterialLocalizations.of(context).cancelButtonLabel,
              variant: CbButtonVariant.secondary,
              size: CbButtonSize.sm,
              onPressed: service.cancelDownload,
            ),
        ];
      case AppUpdatePhase.readyToInstall:
        body = _InstallNotice(service: service, compact: true);
        actions = [
          if (hasNotes) whatsNew,
          CbButton(
            label: l10n.updateInstallNow,
            icon: PhosphorIconsLight.arrowClockwise,
            variant: CbButtonVariant.primary,
            size: CbButtonSize.sm,
            onPressed: service.installAndRestart,
          ),
        ];
      case AppUpdatePhase.installing:
        body = _BusyRow(text: l10n.updateInstalling);
        actions = const [];
      case AppUpdatePhase.error:
        body = service.error == null
            ? null
            : Text(
                service.error!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: CbTypography.bodySm.copyWith(color: c.textSecondary),
              );
        actions = [
          CbButton(
            label: l10n.updateRetry,
            variant: CbButtonVariant.secondary,
            size: CbButtonSize.sm,
            onPressed: service.startDownload,
          ),
        ];
      default:
        body = null;
        actions = [
          if (hasNotes) whatsNew,
          CbButton(
            label: service.distribution?.isStore == true
                ? l10n.updateAction
                : l10n.updateDownload,
            icon: PhosphorIconsLight.downloadSimple,
            variant: CbButtonVariant.primary,
            size: CbButtonSize.sm,
            onPressed: service.startDownload,
          ),
        ];
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: CbSpacing.xs),
      padding: const EdgeInsets.all(CbSpacing.md),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: CbRadii.lgAll,
        border: Border.all(color: tone.border(c)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ToneIcon(tone: tone, icon: icon, size: 32),
              const SizedBox(width: CbSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CbTypography.headingSm.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: CbSpacing.xxs),
                    _VersionTransition(
                      current: service.currentVersion,
                      next: update.version,
                      size: update.assetSize,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (body != null) ...[const SizedBox(height: CbSpacing.md), body],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: CbSpacing.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: CbSpacing.xs,
              runSpacing: CbSpacing.xs,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}

/// The change list of a release, grouped into features, fixes and
/// improvements. Falls back to the raw Markdown for notes without a list.
class ReleaseNotesView extends StatelessWidget {
  final String notes;

  const ReleaseNotesView({super.key, required this.notes});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.cbColors;
    final changes = parseReleaseChanges(notes);

    if (changes.isEmpty) {
      if (releaseNotesHaveList(notes)) {
        return Text(
          l10n.updateMinorChanges,
          style: CbTypography.body.copyWith(color: c.textSecondary),
        );
      }
      final trimmed = trimReleaseNotes(notes);
      if (trimmed.isEmpty) return const SizedBox.shrink();
      return MarkdownBody(
        data: trimmed,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: CbTypography.body.copyWith(color: c.textPrimary),
          listBullet: CbTypography.body.copyWith(color: c.textSecondary),
        ),
      );
    }

    final sections = [
      (
        ReleaseChangeKind.feature,
        l10n.updateSectionFeatures,
        PhosphorIconsLight.sparkle,
        c.accent.text,
      ),
      (
        ReleaseChangeKind.fix,
        l10n.updateSectionFixes,
        PhosphorIconsLight.wrench,
        c.status.success,
      ),
      (
        ReleaseChangeKind.improvement,
        l10n.updateSectionImprovements,
        PhosphorIconsLight.trendUp,
        c.status.info,
      ),
    ];

    final children = <Widget>[];
    for (final (kind, label, icon, color) in sections) {
      final items = changes.where((change) => change.kind == kind).toList();
      if (items.isEmpty) continue;
      if (children.isNotEmpty) {
        children.add(const SizedBox(height: CbSpacing.lg));
      }
      children.add(
        Row(
          children: [
            Icon(icon, size: CbSizes.iconSm, color: color),
            const SizedBox(width: CbSpacing.xs + CbSpacing.xxs),
            Text(
              label.toUpperCase(),
              style: CbTypography.overline.copyWith(color: c.textTertiary),
            ),
            const SizedBox(width: CbSpacing.xs + CbSpacing.xxs),
            Text(
              '${items.length}',
              style: CbTypography.labelXs.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      );
      for (final item in items) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: CbSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  // Centres the dot on the first 18px line of body text.
                  margin: const EdgeInsets.only(
                    top: 6.5,
                    left: CbSpacing.xs,
                    right: CbSpacing.sm + CbSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text(
                    item.text,
                    style: CbTypography.body.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

enum _Tone {
  accent,
  success,
  danger;

  Color fill(CbColorTokens c) => switch (this) {
    accent => c.accent.tint,
    success => c.status.successSurface,
    danger => c.status.dangerSurface,
  };

  Color foreground(CbColorTokens c) => switch (this) {
    accent => c.accent.text,
    success => c.status.success,
    danger => c.status.danger,
  };

  Color border(CbColorTokens c) => switch (this) {
    accent => c.accent.border,
    success => c.status.success.withValues(alpha: 0.35),
    danger => c.status.danger.withValues(alpha: 0.35),
  };
}

class _ToneIcon extends StatelessWidget {
  final _Tone tone;
  final IconData icon;
  final double size;

  const _ToneIcon({required this.tone, required this.icon, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.fill(c),
        borderRadius: size >= 40 ? CbRadii.lgAll : CbRadii.mdAll,
      ),
      child: Icon(icon, size: size * 0.55, color: tone.foreground(c)),
    );
  }
}

/// `1.1.16 → 1.1.17 · 32 MB`, or just the new version when the current one
/// is unknown.
class _VersionTransition extends StatelessWidget {
  final String current;
  final String next;
  final int? size;
  final bool compact;

  const _VersionTransition({
    required this.current,
    required this.next,
    this.size,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final mono = compact ? CbTypography.monoSm : CbTypography.mono;
    final meta = compact ? CbTypography.caption : CbTypography.bodySm;
    final sizeLabel = size != null && size! > 0
        ? FormatUtils.formatFileSize(size!)
        : null;

    Widget chip(String version, {required bool highlighted}) => Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? CbSpacing.xs : CbSpacing.sm - CbSpacing.xxs,
        vertical: compact ? 0 : CbSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: highlighted ? c.accent.tint : c.fillSubtle,
        borderRadius: CbRadii.smAll,
      ),
      child: Text(
        version,
        style: mono.copyWith(
          color: highlighted ? c.accent.text : c.textSecondary,
          fontWeight: highlighted ? FontWeight.w600 : null,
        ),
      ),
    );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: CbSpacing.xs + CbSpacing.xxs,
      runSpacing: CbSpacing.xxs,
      children: [
        if (current.isNotEmpty && next.isNotEmpty) ...[
          chip(current, highlighted: false),
          Icon(
            PhosphorIconsLight.arrowRight,
            size: CbSizes.iconXs,
            color: c.textTertiary,
          ),
        ],
        if (next.isNotEmpty) chip(next, highlighted: true),
        if (sizeLabel != null)
          Text(sizeLabel, style: meta.copyWith(color: c.textTertiary)),
      ],
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  final AppUpdateService service;
  final bool compact;

  const _DownloadProgress({required this.service, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.cbColors;
    final progress = service.progress;
    final String? percent = progress == null
        ? null
        : '${(progress * 100).floor()}%';
    final String detail;
    if (progress == null) {
      detail = l10n.updateStoreDownloading;
    } else if (service.totalBytes > 0) {
      detail =
          '${FormatUtils.formatFileSize(service.receivedBytes)}'
          ' / ${FormatUtils.formatFileSize(service.totalBytes)}';
    } else {
      detail = '';
    }
    final textStyle = compact ? CbTypography.caption : CbTypography.bodySm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(CbRadii.full),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: compact ? 4 : 6,
            color: c.accent.base,
            backgroundColor: c.fillSubtle,
          ),
        ),
        const SizedBox(height: CbSpacing.xs + CbSpacing.xxs),
        Row(
          children: [
            Expanded(
              child: Text(
                detail,
                style: textStyle.copyWith(color: c.textSecondary),
              ),
            ),
            if (percent != null)
              Text(
                percent,
                style: CbTypography.monoSm.copyWith(color: c.textSecondary),
              ),
          ],
        ),
      ],
    );
  }
}

/// What happens when installing: the app closes and reopens.
class _InstallNotice extends StatelessWidget {
  final AppUpdateService service;
  final bool compact;

  const _InstallNotice({required this.service, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final c = context.cbColors;
    final message = service.distribution == AppDistribution.windowsInstaller
        ? '${l10n.updateReadyMessage} ${l10n.updateAdminHint}'
        : l10n.updateReadyMessage;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            PhosphorIconsLight.info,
            size: CbSizes.iconSm,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(width: CbSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: (compact ? CbTypography.caption : CbTypography.bodySm)
                .copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _BusyRow extends StatelessWidget {
  final String text;

  const _BusyRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return Row(
      children: [
        SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: c.accent.base,
          ),
        ),
        const SizedBox(width: CbSpacing.md),
        Expanded(
          child: Text(
            text,
            style: CbTypography.body.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Header (tone icon, title, version line), scrollable body, a pinned footer
/// for progress/notices and the action row. The body scrolls on its own so
/// long release notes never push the buttons off screen.
class _UpdateDialogFrame extends StatelessWidget {
  final _Tone tone;
  final IconData icon;
  final String title;
  final Widget? subtitle;
  final Widget? body;
  final Widget? footer;
  final List<Widget> actions;
  final bool showClose;

  const _UpdateDialogFrame({
    required this.tone,
    required this.icon,
    required this.title,
    this.subtitle,
    this.body,
    this.footer,
    this.actions = const [],
    this.showClose = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final hasBody = body != null;

    return Dialog(
      insetPadding: const EdgeInsets.all(CbSpacing.xl),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height - CbSpacing.xxxl * 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CbSpacing.xl,
                CbSpacing.xl,
                CbSpacing.md,
                CbSpacing.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ToneIcon(tone: tone, icon: icon),
                  const SizedBox(width: CbSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: CbTypography.headingMd.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: CbSpacing.xs + CbSpacing.xxs),
                          subtitle!,
                        ],
                      ],
                    ),
                  ),
                  if (showClose) ...[
                    const SizedBox(width: CbSpacing.sm),
                    CbButton.icon(
                      icon: PhosphorIconsLight.x,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      size: CbButtonSize.sm,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ],
              ),
            ),
            if (hasBody)
              Flexible(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: CbSpacing.xl),
                  constraints: const BoxConstraints(maxHeight: 320),
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    borderRadius: CbRadii.lgAll,
                    border: Border.all(color: c.strokeSubtle),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(CbSpacing.lg),
                    child: body,
                  ),
                ),
              ),
            if (footer != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  CbSpacing.xl,
                  hasBody ? CbSpacing.lg : 0,
                  CbSpacing.xl,
                  0,
                ),
                child: footer,
              ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(CbSpacing.xl),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: CbSpacing.sm,
                  runSpacing: CbSpacing.sm,
                  children: actions,
                ),
              )
            else
              const SizedBox(height: CbSpacing.xl),
          ],
        ),
      ),
    );
  }
}
