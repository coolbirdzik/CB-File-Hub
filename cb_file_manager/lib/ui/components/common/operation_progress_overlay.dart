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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (OperationProgressOverlay._isDesktop) return const SizedBox.shrink();
    if (_controller.entries.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: _MobileStatusBar(controller: _controller),
      ),
    );
  }
}

class StatusCenterToolbarButton extends StatefulWidget {
  const StatusCenterToolbarButton({Key? key}) : super(key: key);

  @override
  State<StatusCenterToolbarButton> createState() =>
      _StatusCenterToolbarButtonState();
}

class _StatusCenterToolbarButtonState extends State<StatusCenterToolbarButton>
    with TickerProviderStateMixin {
  final OperationProgressController _controller =
      locator<OperationProgressController>();
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _turnAnimation;
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;
  int _lastUnseenCount = 0;
  int _lastRunningCount = 0;

  @override
  void initState() {
    super.initState();
    _lastUnseenCount = _controller.unseenCount;
    _lastRunningCount = _controller.runningCount;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.18), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 1.18, end: 0.96), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.96, end: 1.0), weight: 35),
    ]).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOutCubic,
    ));
    _turnAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.055), weight: 25),
      TweenSequenceItem(tween: Tween(begin: -0.055, end: 0.055), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 0.055, end: 0.0), weight: 30),
    ]).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
    ));
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _glowAnimation = CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeOut,
    );
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _closePanelOverlay();
    _controller.removeListener(_onChanged);
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _onChanged() {
    final unseenCount = _controller.unseenCount;
    final runningCount = _controller.runningCount;
    if (unseenCount > _lastUnseenCount) {
      _pulseController.forward(from: 0);
    }
    if (runningCount > _lastRunningCount) {
      _glowController.forward(from: 0);
    }
    _lastUnseenCount = unseenCount;
    _lastRunningCount = runningCount;
    if (mounted) setState(() {});
  }

  OverlayEntry? _panelOverlay;

  void _openStatusCenter() {
    if (_panelOverlay != null) {
      _closePanelOverlay();
      return;
    }
    _controller.markAllSeen();

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final buttonTopLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final buttonRect = buttonTopLeft & box.size;

    // Position panel: right-align to button, below it
    final panelRight = overlayBox.size.width - buttonRect.right;
    final panelTop = buttonRect.bottom + 8;

    // Capture theme colors here while we have a valid app context.
    // Blend surfaceContainer over surface to guarantee a fully opaque color —
    // surfaceContainer can carry alpha on some Material 3 themes.
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bgColor = Color.alphaBlend(cs.surfaceContainer, cs.surface);
    final shadowColor = theme.shadowColor.withValues(alpha: 0.45);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _StatusCenterOverlayPanel(
        panelRight: panelRight,
        panelTop: panelTop,
        controller: _controller,
        onDismiss: _closePanelOverlay,
        bgColor: bgColor,
        shadowColor: shadowColor,
      ),
    );
    _panelOverlay = entry;
    overlay.insert(entry);
    setState(() {});
  }

  void _closePanelOverlay() {
    _panelOverlay?.remove();
    _panelOverlay = null;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unseenCount = _controller.unseenCount;
    final runningCount = _controller.runningCount;
    final hasWork = _controller.entries.isNotEmpty;
    final hasUnread = unseenCount > 0;

    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Glow ring — fades out after a new task is queued
          AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, _) {
              final opacity = (1.0 - _glowAnimation.value).clamp(0.0, 1.0);
              final radius = 14.0 + _glowAnimation.value * 10.0;
              if (opacity == 0) return const SizedBox.shrink();
              return Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary
                      .withValues(alpha: opacity * 0.28),
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _turnAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                ),
              );
            },
            child: IconButton(
              tooltip: hasUnread
                  ? '$unseenCount new app notification${unseenCount == 1 ? '' : 's'}'
                  : 'Status Center',
              icon: Icon(
                hasWork
                    ? PhosphorIconsLight.bellRinging
                    : PhosphorIconsLight.bell,
                color: hasUnread || runningCount > 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                backgroundColor: hasUnread || runningCount > 0
                    ? theme.colorScheme.primary.withValues(alpha: 0.10)
                    : Colors.transparent,
              ),
              onPressed: _openStatusCenter,
            ),
          ),
          if (unseenCount > 0 || runningCount > 0)
            Positioned(
              right: -1,
              top: -1,
              child: _StatusBadge(
                count: unseenCount > 0 ? unseenCount : runningCount,
                isUnread: unseenCount > 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final int count;
  final bool isUnread;

  const _StatusBadge({required this.count, required this.isUnread});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = count > 99 ? '99+' : '$count';
    final color =
        isUnread ? theme.colorScheme.error : theme.colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.surface, width: 1.5),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _MobileStatusBar extends StatelessWidget {
  final OperationProgressController controller;

  const _MobileStatusBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aggregate = controller.aggregateProgress;
    final unseenCount = controller.unseenCount;
    final title = aggregate.runningCount > 0
        ? '${aggregate.runningCount} task${aggregate.runningCount == 1 ? '' : 's'} running'
        : 'Status Center';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          controller.markAllSeen();
          showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => StatusCenterPanel(controller: controller),
          );
        },
        child: Container(
          margin: const EdgeInsets.all(10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              AggregateProgressIndicator(controller: controller, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (unseenCount > 0)
                _StatusBadge(count: unseenCount, isUnread: true),
            ],
          ),
        ),
      ),
    );
  }
}

class AggregateProgressIndicator extends StatelessWidget {
  final OperationProgressController controller;
  final double size;

  const AggregateProgressIndicator({
    Key? key,
    required this.controller,
    required this.size,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aggregate = controller.aggregateProgress;
    final color = aggregate.hasError
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: aggregate.isIndeterminate ? null : aggregate.fraction,
            strokeWidth: 3,
            color: color,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
          Icon(
            aggregate.hasError
                ? PhosphorIconsLight.warningCircle
                : PhosphorIconsLight.arrowsClockwise,
            size: size * 0.52,
            color: color,
          ),
        ],
      ),
    );
  }
}

class StatusCenterPanel extends StatefulWidget {
  final OperationProgressController controller;
  final Color? solidBackground;

  const StatusCenterPanel(
      {Key? key, required this.controller, this.solidBackground})
      : super(key: key);

  @override
  State<StatusCenterPanel> createState() => _StatusCenterPanelState();
}

class _StatusCenterPanelState extends State<StatusCenterPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    final running = controller.runningEntries;
    final finished = controller.finishedEntries;

    final bg = widget.solidBackground ??
        Color.alphaBlend(
          theme.colorScheme.surfaceContainer,
          theme.colorScheme.surface,
        );

    return Material(
      color: bg,
      child: ColoredBox(
        color: bg,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                child: Row(
                  children: [
                    const Icon(PhosphorIconsLight.bell, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Status Center',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (finished.isNotEmpty)
                      TextButton(
                        onPressed: controller.dismissFinished,
                        child: const Text('Clear completed'),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    if (running.isNotEmpty) ...[
                      const _SectionHeader(title: 'Running'),
                      for (final entry in running)
                        _StatusCenterTaskTile(
                          entry: entry,
                          controller: controller,
                        ),
                    ],
                    if (finished.isNotEmpty) ...[
                      const _SectionHeader(title: 'Notifications'),
                      for (final entry in finished)
                        _StatusCenterTaskTile(
                          entry: entry,
                          controller: controller,
                        ),
                    ],
                    if (running.isEmpty && finished.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No internal notifications',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusCenterTaskTile extends StatelessWidget {
  final OperationProgressEntry entry;
  final OperationProgressController controller;

  const _StatusCenterTaskTile({required this.entry, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final color = _statusColor(theme, entry.status);
    final statusText = _statusText(l10n, entry);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_statusIcon(entry.status), size: 20, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  statusText,
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
                if (entry.isFinished)
                  IconButton(
                    tooltip: 'Dismiss',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => controller.dismiss(entry.id),
                    icon: const Icon(PhosphorIconsLight.x, size: 16),
                  ),
              ],
            ),
            if (entry.detail != null) ...[
              const SizedBox(height: 6),
              Text(
                entry.detail!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: entry.isIndeterminate ? null : entry.progressFraction,
              minHeight: 7,
              borderRadius: BorderRadius.circular(999),
              color: color,
            ),
            if (entry.canCancel && entry.isRunning) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => controller.cancel(entry.id),
                  child: Text(l10n.cancel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(ThemeData theme, OperationProgressStatus status) {
    switch (status) {
      case OperationProgressStatus.running:
        return theme.colorScheme.primary;
      case OperationProgressStatus.success:
        return theme.colorScheme.tertiary;
      case OperationProgressStatus.error:
        return theme.colorScheme.error;
    }
  }

  IconData _statusIcon(OperationProgressStatus status) {
    switch (status) {
      case OperationProgressStatus.running:
        return PhosphorIconsLight.arrowsClockwise;
      case OperationProgressStatus.success:
        return PhosphorIconsLight.checkCircle;
      case OperationProgressStatus.error:
        return PhosphorIconsLight.warningCircle;
    }
  }

  String _statusText(AppLocalizations l10n, OperationProgressEntry entry) {
    if (entry.isRunning) {
      if (entry.isIndeterminate) return l10n.processing;
      return '${(entry.progressFraction * 100).toStringAsFixed(0)}%';
    }
    return entry.status == OperationProgressStatus.success
        ? l10n.done
        : l10n.errorTitle;
  }
}

/// Full-screen overlay that renders the Status Center panel as a solid opaque
/// widget positioned below the toolbar bell button. A transparent barrier
/// behind it dismisses the panel on tap-outside.
class _StatusCenterOverlayPanel extends StatelessWidget {
  final double panelRight;
  final double panelTop;
  final OperationProgressController controller;
  final VoidCallback onDismiss;
  final Color bgColor;
  final Color shadowColor;

  const _StatusCenterOverlayPanel({
    required this.panelRight,
    required this.panelTop,
    required this.controller,
    required this.onDismiss,
    required this.bgColor,
    required this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    // OverlayEntry context has no app Theme — use the pre-captured colors
    // and inject a Theme so child widgets resolve colors correctly.
    final appTheme = Theme.of(context);
    return Stack(
      children: [
        // Barrier — dismiss on tap outside
        Positioned.fill(
          child: GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        // Panel — solid opaque surface with explicit background
        Positioned(
          right: panelRight,
          top: panelTop,
          child: Theme(
            data: appTheme,
            child: Material(
              elevation: 12,
              color: bgColor,
              shadowColor: shadowColor,
              borderRadius: BorderRadius.circular(18),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ColoredBox(
                  color: bgColor,
                  child: StatusCenterPanel(
                    controller: controller,
                    solidBackground: bgColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
