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
  bool _isShowingDialog = false;

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

    // Show as a modal dialog when explicitly requested.
    if (active != null &&
        !active.isMinimized &&
        active.isRunning &&
        !_isShowingDialog) {
      if (OperationProgressOverlay._isDesktop) {
        _showDesktopWindow();
      } else {
        _showMobileDialog();
      }
      return;
    }

    if (active != null && active.isFinished) {
      // Auto-dismiss success after a short delay, keep errors until user dismisses.
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

  void _showDesktopWindow() {
    if (_isShowingDialog) return;
    _isShowingDialog = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isShowingDialog = false;
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _DesktopProgressWindow(
          controller: _controller,
        ),
      ).then((_) {
        _isShowingDialog = false;
      });
    });
  }

  void _showMobileDialog() {
    if (_isShowingDialog) return;
    _isShowingDialog = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isShowingDialog = false;
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _MobileProgressDialog(
          controller: _controller,
        ),
      ).then((_) {
        _isShowingDialog = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final active = _controller.active;

    // On desktop, don't show the overlay (show window dialog instead)
    if (OperationProgressOverlay._isDesktop) {
      return const SizedBox.shrink();
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

/// Desktop-style progress window shown as a dialog
class _DesktopProgressWindow extends StatefulWidget {
  final OperationProgressController controller;

  const _DesktopProgressWindow({
    required this.controller,
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

    // Close dialog if operation is dismissed
    if (active == null) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      return;
    }

    // Close dialog if user minimized it
    if (active.isMinimized && !active.isRunning) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
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
            if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
            widget.controller.dismiss();
          }
        });
      }
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.controller.active;
    if (active == null) {
      return const SizedBox.shrink();
    }

    return Dialog(
      alignment: Alignment.bottomRight,
      insetPadding: const EdgeInsets.all(20),
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
      elevation: 0,
      color: Colors.transparent,
      shadowColor: theme.shadowColor.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 400,
        constraints: const BoxConstraints(
          minHeight: 120,
          maxHeight: 180,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.surfaceContainerHigh
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
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

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerLow,
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
