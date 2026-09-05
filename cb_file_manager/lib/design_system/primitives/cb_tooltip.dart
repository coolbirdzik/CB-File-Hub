import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

/// A Material tooltip whose accessibility anchor cannot be merged with a
/// sibling tooltip anchor.
///
/// Flutter's [Tooltip] is backed by an `OverlayPortal`. On affected Flutter
/// versions, two tooltip anchors inside one indexed sliver item can be merged
/// into a single semantics node. One traversal-parent id is then discarded and
/// the Windows accessibility bridge rejects the whole AX tree update.
///
/// The semantics container is intentionally outside [Tooltip]. It gives each
/// overlay anchor its own node while preserving the tooltip's visual and
/// screen-reader behavior.
class CbTooltip extends StatelessWidget {
  final String message;
  final Widget child;
  final Duration? waitDuration;
  final Duration? showDuration;
  final Duration? exitDuration;
  final bool? preferBelow;
  final double? verticalOffset;
  final TooltipTriggerMode? triggerMode;
  final bool? enableFeedback;
  final bool? excludeFromSemantics;

  const CbTooltip({
    super.key,
    required this.message,
    required this.child,
    this.waitDuration,
    this.showDuration,
    this.exitDuration,
    this.preferBelow,
    this.verticalOffset,
    this.triggerMode,
    this.enableFeedback,
    this.excludeFromSemantics,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Tooltip(
        message: message,
        waitDuration: waitDuration,
        showDuration: showDuration,
        exitDuration: exitDuration,
        preferBelow: preferBelow,
        verticalOffset: verticalOffset,
        triggerMode: triggerMode,
        enableFeedback: enableFeedback,
        excludeFromSemantics: excludeFromSemantics,
        child: child,
      ),
    );
  }
}

/// A Fluent tooltip whose child keeps its semantics identity when a mouse is
/// first detected.
///
/// fluent_ui's [fluent.Tooltip] only wraps its child in a `GestureDetector` and
/// a `MouseRegion` once `MouseTracker.mouseIsConnected` is true. On Windows that
/// flips from false to true the first time a pointer arrives after launch, which
/// changes the widget type sitting at that slot and remounts the entire child
/// subtree. Every semantics node under every visible tooltip is destroyed and an
/// equivalent one created in the same frame.
///
/// The Windows accessibility bridge cannot serialize a batch that drops ids and
/// reclaims their slots at once, so it rejects the whole `ui::AXTree` update. It
/// does not resynchronise afterwards, which is why a single bad frame turns into
/// the endless, always-identical
/// "Failed to update ui::AXTree, error: Nodes left pending by the update: ..."
/// flood on stderr.
///
/// Three things together keep the tree stable across that reshape:
///  * the child is held by a [GlobalKey], so it is reparented instead of rebuilt;
///  * fluent's own `Semantics` wrapper is silenced, because it lives inside the
///    reshaped slot and would still be handed a new id;
///  * the tooltip text is published from a [Semantics] node placed outside the
///    tooltip, which never moves.
///
/// See also [CbTooltip], the Material counterpart, which fixes a different
/// semantics defect.
class CbFluentTooltip extends StatefulWidget {
  final String message;
  final Widget child;

  const CbFluentTooltip({
    super.key,
    required this.message,
    required this.child,
  });

  @override
  State<CbFluentTooltip> createState() => _CbFluentTooltipState();
}

class _CbFluentTooltipState extends State<CbFluentTooltip> {
  // Has to outlive the rebuild that inserts the MouseRegion, so it cannot be
  // created inside build().
  final GlobalKey _childKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      tooltip: widget.message,
      child: fluent.Tooltip(
        message: widget.message,
        excludeFromSemantics: true,
        child: KeyedSubtree(key: _childKey, child: widget.child),
      ),
    );
  }
}
