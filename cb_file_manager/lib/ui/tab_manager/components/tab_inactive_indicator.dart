import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/tab_activity/tab_activity_manager.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Small visual indicator shown on a tab header when the tab has been
/// auto-suspended due to inactivity (>= 60 minutes idle).
///
/// Renders a snooze/moon glyph with a tooltip explaining why the tab is
/// marked. When the corresponding tab is not inactive, the widget collapses
/// to zero size (returns [SizedBox.shrink]).
class TabInactiveIndicator extends StatefulWidget {
  /// The id of the tab that this indicator represents.
  final String tabId;

  /// Optional override for the displayed icon size. Defaults to 14.
  final double iconSize;

  const TabInactiveIndicator({
    Key? key,
    required this.tabId,
    this.iconSize = 14,
  }) : super(key: key);

  @override
  State<TabInactiveIndicator> createState() => _TabInactiveIndicatorState();
}

class _TabInactiveIndicatorState extends State<TabInactiveIndicator> {
  TabActivityManager? _manager;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(TabInactiveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabId != widget.tabId) {
      // Listener references the same manager regardless of tab id, but the
      // rebuild must use the new tab id. Trigger a rebuild explicitly.
      if (mounted) setState(() {});
    }
  }

  void _attach() {
    if (!locator.isRegistered<TabActivityManager>()) return;
    _manager = locator<TabActivityManager>();
    _manager?.addListener(_handleActivityChanged);
  }

  void _handleActivityChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _manager?.removeListener(_handleActivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    if (manager == null) return const SizedBox.shrink();
    if (!manager.isInactive(widget.tabId)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: 'Inactive (auto-suspended after 60 minutes)',
        waitDuration: const Duration(milliseconds: 350),
        child: Icon(
          PhosphorIconsLight.moon,
          size: widget.iconSize,
          color: color,
        ),
      ),
    );
  }
}
