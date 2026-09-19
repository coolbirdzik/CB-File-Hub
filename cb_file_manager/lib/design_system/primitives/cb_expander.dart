import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_chevron.dart';
import 'cb_decorations.dart';
import 'cb_pressable.dart';

/// A row that discloses a group of controls below it — the Fluent expander.
///
/// Replaces Material's `ExpansionTile`, whose divider lines, ink and
/// `ListTile` metrics read as Android settings. Flat, and at home inside a
/// section card: the header is a plain row that takes the hover and press
/// fill like any other row, the chevron turns to show the state, and the
/// disclosed controls sit in a fill block of their own instead of under a
/// divider line.
///
/// [flush] drops that block for navigation lists — sidebar sections — whose
/// children are already rows of their own.
class CbExpander extends StatefulWidget {
  final Widget title;
  final Widget? subtitle;

  /// Usually an [Icon]; it picks up the standard icon size and colour unless
  /// it sets its own.
  final Widget? leading;

  /// A control in the header ahead of the chevron — typically the switch
  /// that turns on the feature the expander configures. It stays operable
  /// and focusable on its own; clicking it does not toggle the expander.
  final Widget? trailing;

  final List<Widget> children;

  /// Whether the expander is open. It toggles itself when the header is
  /// clicked and reports through [onExpansionChanged]; a different value
  /// passed in later — a parent restoring a stored state — animates it there
  /// without remounting it, so a parent never has to key it by this value.
  final bool expanded;

  final ValueChanged<bool>? onExpansionChanged;

  /// Disclose [children] straight under the header, with no fill block.
  final bool flush;

  final EdgeInsetsGeometry headerPadding;

  /// Padding around [children] — inside the fill block, or under the header
  /// when [flush].
  final EdgeInsetsGeometry contentPadding;

  const CbExpander({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    required this.children,
    this.expanded = false,
    this.onExpansionChanged,
    this.flush = false,
    this.headerPadding = const EdgeInsets.symmetric(
      horizontal: CbSpacing.lg,
      vertical: CbSpacing.sm,
    ),
    this.contentPadding = const EdgeInsets.symmetric(vertical: CbSpacing.xs),
  });

  @override
  State<CbExpander> createState() => _CbExpanderState();
}

class _CbExpanderState extends State<CbExpander>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.expanded;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CbDurations.normal,
    value: _expanded ? 1 : 0,
  );
  late final Animation<double> _reveal = CurvedAnimation(
    parent: _controller,
    curve: CbCurves.standard,
    reverseCurve: CbCurves.exit,
  );

  @override
  void didUpdateWidget(CbExpander oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a change the parent made: echoing back the state a tap already
    // set is a no-op, so the animation that tap started is not restarted.
    if (widget.expanded != oldWidget.expanded && widget.expanded != _expanded) {
      _setExpanded(widget.expanded);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setExpanded(bool value) {
    setState(() => _expanded = value);
    if (value) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _toggle() {
    _setExpanded(!_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;

    final header = CbPressable(
      onPressed: _toggle,
      cursor: SystemMouseCursors.click,
      descendantsAreFocusable: widget.trailing != null,
      builder: (context, state) => AnimatedContainer(
        duration: CbDurations.instant,
        padding: widget.headerPadding,
        decoration: BoxDecoration(
          color: state.pressed
              ? c.fillPressed
              : (state.hovered ? c.fillHover : Colors.transparent),
          borderRadius: CbRadii.smAll,
          boxShadow: state.focused ? CbDecorations.focusRing(c) : null,
        ),
        child: Row(
          children: [
            if (widget.leading != null) ...[
              IconTheme.merge(
                data: IconThemeData(size: CbSizes.iconLg, color: c.icon),
                child: widget.leading!,
              ),
              const SizedBox(width: CbSpacing.lg),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DefaultTextStyle.merge(
                    style: CbTypography.label.copyWith(color: c.textPrimary),
                    child: widget.title,
                  ),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: CbSpacing.xxs),
                    DefaultTextStyle.merge(
                      style: CbTypography.bodySm.copyWith(
                        color: c.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: widget.subtitle!,
                    ),
                  ],
                ],
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: CbSpacing.md),
              widget.trailing!,
            ],
            const SizedBox(width: CbSpacing.md),
            CbChevron(color: c.iconSubtle, flipped: _expanded),
          ],
        ),
      ),
    );

    final Widget content = Padding(
      padding: widget.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.children,
      ),
    );
    // One fill step over the surrounding surface groups the disclosed
    // controls under their header, which is the job a divider used to do.
    final Widget body = widget.flush
        ? content
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              CbSpacing.sm,
              CbSpacing.xxs,
              CbSpacing.sm,
              CbSpacing.sm,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.fillSubtle,
                borderRadius: CbRadii.smAll,
              ),
              child: content,
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(expanded: _expanded, child: header),
        AnimatedBuilder(
          animation: _reveal,
          // Collapsed content is not built at all, so its controls cannot
          // take focus or be read out while hidden.
          builder: (context, child) => _controller.isDismissed
              ? const SizedBox.shrink()
              : ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: _reveal.value,
                    child: child,
                  ),
                ),
          child: ExcludeFocus(excluding: !_expanded, child: body),
        ),
      ],
    );
  }
}
