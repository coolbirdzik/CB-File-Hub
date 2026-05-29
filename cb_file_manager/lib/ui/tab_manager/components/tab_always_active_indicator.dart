import 'package:cb_file_manager/config/translation_helper.dart';
import 'package:cb_file_manager/core/service_locator.dart';
import 'package:cb_file_manager/services/tab_activity/tab_activity_manager.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Small visual indicator shown on a tab header when the tab has been
/// pinned as always-active by the user (right-click menu → "Keep tab always
/// active"). Renders a pin glyph with a localized tooltip; collapses to
/// zero size for any tab that is not pinned.
///
/// Intentionally split from [TabInactiveIndicator] so the two states never
/// coexist visually: a pinned tab can never be inactive (the activity
/// manager refuses both automatic and manual transitions), so the existing
/// inactive moon glyph is naturally hidden whenever this pin is shown.
class TabAlwaysActiveIndicator extends StatefulWidget {
  /// The id of the tab that this indicator represents.
  final String tabId;

  /// Optional override for the displayed icon size. Defaults to 14.
  final double iconSize;

  const TabAlwaysActiveIndicator({
    Key? key,
    required this.tabId,
    this.iconSize = 14,
  }) : super(key: key);

  @override
  State<TabAlwaysActiveIndicator> createState() =>
      _TabAlwaysActiveIndicatorState();
}

class _TabAlwaysActiveIndicatorState extends State<TabAlwaysActiveIndicator> {
  TabActivityManager? _manager;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(TabAlwaysActiveIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabId != widget.tabId) {
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
    if (!manager.isAlwaysActive(widget.tabId)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final color = theme.colorScheme.primary.withValues(alpha: 0.85);

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: context.tr.tabAlwaysActiveTooltip,
        waitDuration: const Duration(milliseconds: 350),
        child: Icon(
          PhosphorIconsFill.pushPin,
          size: widget.iconSize,
          color: color,
        ),
      ),
    );
  }
}
