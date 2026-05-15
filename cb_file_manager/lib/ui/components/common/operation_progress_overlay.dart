import 'dart:async';
import 'dart:io' show Platform;

import 'package:cb_file_manager/config/languages/app_localizations.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/ui/controllers/operation_progress_controller.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class OperationProgressOverlay extends StatefulWidget {
  const OperationProgressOverlay({Key? key}) : super(key: key);

  static bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @override
  State<OperationProgressOverlay> createState() =>
      _OperationProgressOverlayState();
}

class _OperationProgressOverlayState extends State<OperationProgressOverlay> {
  final OperationProgressController _controller =
      locator<OperationProgressController>();

  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final active = _controller.active;
    _autoDismissTimer?.cancel();

    if (active == null) {
      if (mounted) setState(() {});
      return;
    }

    if (!OperationProgressOverlay._isDesktop &&
        !active.isMinimized &&
        active.isRunning) {
      _showMobileDialog();
      return;
    }

    // Auto-dismiss for minimized status-bar entries on mobile.
    if (active.isFinished && active.isMinimized) {
      if (active.status == OperationProgressStatus.success) {
        _autoDismissTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          final latest = _controller.active;
          if (latest != null &&
              latest.id == active.id &&
              latest.status == OperationProgressStatus.success) {
            _controller.dismiss();
          }
        });
      }
    }

    if (mounted) setState(() {});
  }

  void _showMobileDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _MobileProgressDialog(
          controller: _controller,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _controller.active;

    if (OperationProgressOverlay._isDesktop) {
      if (active == null || active.isMinimized) {
        return const SizedBox.shrink();
      }

      return Positioned(
        right: 20,
        bottom: 20,
        child: SafeArea(
          top: false,
          left: false,
          child: _DesktopProgressWindow(
            controller: _controller,
            onClose: _controller.dismiss,
          ),
        ),
      );
    }

    // On mobile, show the bottom status bar overlay
    if (active == null || !active.isMinimized) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: _OperationProgressStatusBar(
          entry: active,
          onDismiss: _controller.dismiss,
        ),
      ),
    );
  }
}

class _OperationProgressStatusBar extends StatelessWidget {
  final OperationProgressEntry entry;
  final VoidCallback onDismiss;

  const _OperationProgressStatusBar({
    required this.entry,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.92)
        : theme.colorScheme.surface.withValues(alpha: 0.95);

    final Color accent;
    switch (entry.status) {
      case OperationProgressStatus.running:
        accent = theme.colorScheme.primary;
        break;
      case OperationProgressStatus.success:
        accent = theme.colorScheme.tertiary;
        break;
      case OperationProgressStatus.error:
        accent = theme.colorScheme.error;
        break;
    }

    final label = entry.isRunning
        ? (entry.isIndeterminate
            ? l10n.processing
            : '${entry.completed}/${entry.total}')
        : (entry.status == OperationProgressStatus.success
            ? l10n.done
            : l10n.errorTitle);

    final IconData icon;
    switch (entry.status) {
      case OperationProgressStatus.running:
        icon = PhosphorIconsLight.arrowsClockwise;
        break;
      case OperationProgressStatus.success:
        icon = PhosphorIconsLight.checkCircle;
        break;
      case OperationProgressStatus.error:
        icon = PhosphorIconsLight.warningCircle;
        break;
    }

    return Material(
      elevation: 0,
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value:
                        entry.isIndeterminate ? null : entry.progressFraction,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            if (!entry.isRunning)
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(PhosphorIconsLight.x, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

/// Desktop-style progress window shown as a non-modal overlay (no focus steal)
class _DesktopProgressWindow extends StatefulWidget {
  final OperationProgressController controller;
  final VoidCallback onClose;

  const _DesktopProgressWindow({
    required this.controller,
    required this.onClose,
  });

  @override
  State<_DesktopProgressWindow> createState() => _DesktopProgressWindowState();
}

class _MobileProgressDialog extends StatefulWidget {
  final OperationProgressController controller;

  const _MobileProgressDialog({
    required this.controller,
  });

  @override
  State<_MobileProgressDialog> createState() => _MobileProgressDialogState();
}

class _MobileProgressDialogState extends State<_MobileProgressDialog> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final active = widget.controller.active;
    _autoDismissTimer?.cancel();

    if (active == null || active.isMinimized) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      return;
    }

    if (active.isFinished && active.status == OperationProgressStatus.success) {
      _autoDismissTimer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        final latest = widget.controller.active;
        if (latest != null &&
            latest.id == active.id &&
            latest.status == OperationProgressStatus.success) {
          if (Navigator.canPop(context)) {
            Navigator.of(context).pop();
          }
          widget.controller.dismiss();
        }
      });
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.active;
    if (active == null) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenWidth.clamp(280.0, 420.0),
        ),
        child: _ProgressWindowContent(
          entry: active,
          onMinimize: widget.controller.minimize,
          onDismiss: () {
            widget.controller.dismiss();
            if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
    );
  }
}

class _DesktopProgressWindowState extends State<_DesktopProgressWindow> {
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final active = widget.controller.active;
    _autoDismissTimer?.cancel();

    // Close overlay if operation is dismissed
    if (active == null) {
      widget.onClose();
      return;
    }

    // Close overlay if user minimized it
    if (active.isMinimized && !active.isRunning) {
      widget.onClose();
      return;
    }

    if (active.isFinished) {
      // Auto-dismiss success after a short delay
      if (active.status == OperationProgressStatus.success) {
        _autoDismissTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          final latest = widget.controller.active;
          if (latest != null &&
              latest.id == active.id &&
              latest.status == OperationProgressStatus.success) {
            widget.controller.dismiss();
            widget.onClose();
          }
        });
      }
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.active;
    final theme = Theme.of(context);
    if (active == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: _ProgressWindowContent(
        entry: active,
        onMinimize: widget.controller.minimize,
        onDismiss: () {
          widget.controller.dismiss();
          widget.onClose();
        },
      ),
    );
  }
}

class _ProgressWindowContent extends StatelessWidget {
  final OperationProgressEntry entry;
  final VoidCallback onMinimize;
  final VoidCallback onDismiss;

  const _ProgressWindowContent({
    required this.entry,
    required this.onMinimize,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelColor = _opaqueColor(
      isDark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerHigh,
    );
    final panelBorderColor = _opaqueColor(theme.colorScheme.outlineVariant);

    final Color accent;
    switch (entry.status) {
      case OperationProgressStatus.running:
        accent = theme.colorScheme.primary;
        break;
      case OperationProgressStatus.success:
        accent = theme.colorScheme.tertiary;
        break;
      case OperationProgressStatus.error:
        accent = theme.colorScheme.error;
        break;
    }

    final label = entry.isRunning
        ? (entry.isIndeterminate
            ? l10n.processing
            : '${entry.completed} / ${entry.total}')
        : (entry.status == OperationProgressStatus.success
            ? l10n.done
            : l10n.errorTitle);

    final IconData icon;
    switch (entry.status) {
      case OperationProgressStatus.running:
        icon = PhosphorIconsLight.arrowsClockwise;
        break;
      case OperationProgressStatus.success:
        icon = PhosphorIconsLight.checkCircle;
        break;
      case OperationProgressStatus.error:
        icon = PhosphorIconsLight.warningCircle;
        break;
    }

    return Material(
      elevation: 6,
      color: panelColor,
      shadowColor: theme.shadowColor.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(
          minHeight: 120,
          maxHeight: 180,
        ),
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: panelBorderColor,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title bar
            _WindowTitleBar(
              title: entry.title,
              onMinimize: onMinimize,
              onClose: entry.isRunning ? null : onDismiss,
            ),
            // Content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 24, color: accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (entry.detail != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  entry.detail!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LinearProgressIndicator(
                          value: entry.isIndeterminate
                              ? null
                              : entry.progressFraction,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(16.0),
                        ),
                        if (!entry.isIndeterminate) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${(entry.progressFraction * 100).toStringAsFixed(0)}%',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowTitleBar extends StatelessWidget {
  final String title;
  final VoidCallback onMinimize;
  final VoidCallback? onClose;

  const _WindowTitleBar({
    required this.title,
    required this.onMinimize,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleBarColor = _opaqueColor(
      isDark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLow,
    );

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: titleBarColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Minimize button
          _TitleBarButton(
            icon: PhosphorIconsLight.minus,
            onPressed: onMinimize,
            tooltip: 'Minimize',
          ),
          // Close button (only enabled when operation is finished)
          _TitleBarButton(
            icon: PhosphorIconsLight.x,
            onPressed: onClose,
            tooltip: 'Close',
            enabled: onClose != null,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool enabled;

  const _TitleBarButton({
    required this.icon,
    this.onPressed,
    required this.tooltip,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}

Color _opaqueColor(Color color) {
  return color.withAlpha(255);
}
