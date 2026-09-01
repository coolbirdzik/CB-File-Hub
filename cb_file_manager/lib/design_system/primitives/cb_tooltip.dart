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
    Key? key,
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
  }) : super(key: key);

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
