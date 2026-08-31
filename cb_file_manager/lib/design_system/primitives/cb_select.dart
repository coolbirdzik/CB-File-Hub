import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cb_tokens.dart';
import '../tokens/cb_color_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_pressable.dart';

/// One option in a [CbSelect].
@immutable
class CbSelectItem<T> {
  final T value;
  final String label;

  /// What the *trigger* shows when this item is the selected one, if that
  /// should be shorter than [label]. A menu row can afford detail the trigger
  /// cannot — "D: (412 GB free)" in the list, "D:" once chosen.
  final String? triggerLabel;

  /// Optional leading icon. If any item in a list has one, every row reserves
  /// the slot so the labels stay on a single left edge.
  final IconData? icon;

  final bool enabled;

  const CbSelectItem({
    required this.value,
    required this.label,
    this.triggerLabel,
    this.icon,
    this.enabled = true,
  });
}

enum CbSelectSize {
  /// 28px — dense toolbars, table footers.
  sm,

  /// 32px — the default.
  md,

  /// 40px — prominent pickers, mobile.
  lg,
}

enum CbSelectVariant {
  /// Field chrome: sunken fill and a hairline border, matching `CbTextField`.
  outlined,

  /// No chrome until hovered — for a value sitting inline in a row of text.
  ghost,
}

/// The single-choice picker.
///
/// Replaces `DropdownButton`. Material's dropdown is three separate tells at
/// once: the input underline under the trigger, an ink ripple on every row,
/// and a menu that opens by growing from the selected item so the list appears
/// to slide under the cursor. On a desktop file manager it reads as a phone
/// control dropped into a toolbar.
///
/// This one behaves the way a native combo box does: the trigger is a 32px
/// field with a chevron, the menu opens *below* the trigger as a flat popover
/// with a hairline border, rows highlight on hover with a colour change rather
/// than a ripple, and the selected row is marked with an accent bar on its
/// leading edge. Arrow keys move the highlight, Enter commits, Escape
/// dismisses.
class CbSelect<T> extends StatefulWidget {
  final List<CbSelectItem<T>> items;

  /// The current value. When it matches no item, [placeholder] is shown.
  final T? value;

  final ValueChanged<T>? onChanged;

  /// Label rendered above the control. Static — it does not float.
  final String? label;

  /// Shown when [value] matches no item.
  final String? placeholder;

  /// Helper text under the control. Replaced by [errorText] when that is set.
  final String? helperText;

  /// Puts the control in its error state and shows this message.
  final String? errorText;

  final CbSelectSize size;
  final CbSelectVariant variant;

  final bool enabled;

  /// Stretches the trigger to its parent's width. Off by default so a select
  /// used as a list-row `trailing` stays as narrow as its value.
  final bool expand;

  /// Fixed trigger width. Useful when the labels differ wildly in length and
  /// the control would otherwise resize as the value changes.
  final double? width;

  final String? tooltip;
  final FocusNode? focusNode;

  const CbSelect({
    Key? key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.helperText,
    this.errorText,
    this.size = CbSelectSize.md,
    this.variant = CbSelectVariant.outlined,
    this.enabled = true,
    this.expand = false,
    this.width,
    this.tooltip,
    this.focusNode,
  }) : super(key: key);

  /// Convenience constructor for a plain list of values labelled by
  /// [labelBuilder], for call sites that have nothing but the values.
  static CbSelect<V> fromValues<V>({
    Key? key,
    required List<V> values,
    required V? value,
    required ValueChanged<V>? onChanged,
    required String Function(V value) labelBuilder,
    String? label,
    String? placeholder,
    CbSelectSize size = CbSelectSize.md,
    CbSelectVariant variant = CbSelectVariant.outlined,
    bool enabled = true,
    bool expand = false,
    double? width,
    String? tooltip,
  }) {
    return CbSelect<V>(
      key: key,
      items: [
        for (final v in values)
          CbSelectItem<V>(value: v, label: labelBuilder(v)),
      ],
      value: value,
      onChanged: onChanged,
      label: label,
      placeholder: placeholder,
      size: size,
      variant: variant,
      enabled: enabled,
      expand: expand,
      width: width,
      tooltip: tooltip,
    );
  }

  @override
  State<CbSelect<T>> createState() => _CbSelectState<T>();
}

class _CbSelectState<T> extends State<CbSelect<T>> {
  /// Anchors the popover to the trigger specifically. `context` would give the
  /// whole column when a label or helper text is present, which would drop the
  /// menu below the helper line instead of below the control.
  final GlobalKey _triggerKey = GlobalKey(debugLabel: 'CbSelect trigger');

  bool _isOpen = false;

  double get _height {
    switch (widget.size) {
      case CbSelectSize.sm:
        return CbSizes.controlSm;
      case CbSelectSize.md:
        return CbSizes.controlMd;
      case CbSelectSize.lg:
        return CbSizes.controlLg;
    }
  }

  double get _hPadding =>
      widget.size == CbSelectSize.lg ? CbSpacing.md : CbSpacing.sm + 2;

  double get _iconSize =>
      widget.size == CbSelectSize.sm ? CbSizes.iconSm : CbSizes.iconMd;

  TextStyle get _textStyle =>
      widget.size == CbSelectSize.sm ? CbTypography.bodySm : CbTypography.body;

  CbSelectItem<T>? get _selected {
    for (final item in widget.items) {
      if (item.value == widget.value) return item;
    }
    return null;
  }

  bool get _interactive =>
      widget.enabled && widget.onChanged != null && widget.items.isNotEmpty;

  Future<void> _openMenu() async {
    final RenderBox? anchorBox =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    final NavigatorState navigator = Navigator.of(context);
    final RenderBox? overlayBox =
        navigator.overlay?.context.findRenderObject() as RenderBox?;
    if (anchorBox == null || !anchorBox.hasSize || overlayBox == null) return;

    final Offset origin =
        anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final Rect anchor = origin & anchorBox.size;
    final Rect rect = _menuRect(anchor, overlayBox.size);

    setState(() => _isOpen = true);
    await navigator.push(_CbSelectRoute<T>(
      rect: rect,
      openedBelow: rect.top >= anchor.bottom,
      capturedThemes:
          InheritedTheme.capture(from: context, to: navigator.context),
      menu: _CbSelectMenu<T>(
        items: widget.items,
        value: widget.value,
        rowHeight: _height,
        textStyle: _textStyle,
        iconSize: _iconSize,
        onSelected: (item) => widget.onChanged?.call(item.value),
      ),
    ));
    if (mounted) setState(() => _isOpen = false);
  }

  /// Where the popover lands: below the trigger when it fits, flipped above
  /// when it does not, and never past the edge of the window.
  Rect _menuRect(Rect anchor, Size screen) {
    const double gap = CbSpacing.xs;
    const double margin = CbSpacing.sm;
    const double maxHeight = 320;

    final double width = math.min(
      math.max(anchor.width, _intrinsicMenuWidth()),
      math.max(screen.width - margin * 2, 1),
    );

    final double contentHeight =
        widget.items.length * _height + CbSpacing.xs * 2;
    final double spaceBelow = screen.height - anchor.bottom - gap - margin;
    final double spaceAbove = anchor.top - gap - margin;

    final bool below = contentHeight <= spaceBelow || spaceBelow >= spaceAbove;
    final double available = below ? spaceBelow : spaceAbove;
    final double height =
        math.max(math.min(math.min(contentHeight, maxHeight), available), 0);

    final double left = anchor.left
        .clamp(margin, math.max(screen.width - width - margin, margin));
    final double top = below ? anchor.bottom + gap : anchor.top - gap - height;

    return Rect.fromLTWH(left, top, width, height);
  }

  /// Measures the widest label so the popover is never narrower than its
  /// content — the trigger is often sized to the *current* value alone.
  double _intrinsicMenuWidth() {
    final bool hasIcons = widget.items.any((item) => item.icon != null);
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    double widest = 0;

    for (final item in widget.items) {
      final painter = TextPainter(
        text: TextSpan(text: item.label, style: _textStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }

    // Row insets, the icon column when one is in use, and breathing room past
    // the longest label so the list never looks packed against its edge.
    final double chrome = CbSpacing.md * 2 +
        (hasIcons ? _iconSize + CbSpacing.sm : 0) +
        CbSpacing.md;

    return math.max(widest + chrome, scaler.scale(120));
  }

  _CbSelectPaint _paint(CbColorTokens c, CbInteractionState s, bool hasError) {
    if (s.disabled) {
      final bool outlined = widget.variant == CbSelectVariant.outlined;
      return _CbSelectPaint(
        background:
            outlined ? c.surfaceSunken.withValues(alpha: 0.5) : Colors.transparent,
        border: outlined ? c.strokeSubtle : Colors.transparent,
        foreground: c.textDisabled,
        chevron: c.textDisabled,
      );
    }

    final bool active = s.pressed || _isOpen;

    switch (widget.variant) {
      case CbSelectVariant.outlined:
        return _CbSelectPaint(
          background: active
              ? c.surfaceRaised
              : s.hovered
                  ? c.surfaceHover
                  : c.surfaceSunken,
          border: hasError
              ? c.status.danger
              : (active || s.hovered)
                  ? c.strokeStrong
                  : c.stroke,
          foreground: c.textPrimary,
          chevron: c.iconSubtle,
        );

      case CbSelectVariant.ghost:
        return _CbSelectPaint(
          background: active
              ? c.surfacePressed
              : s.hovered
                  ? c.surfaceHover
                  : Colors.transparent,
          border: Colors.transparent,
          foreground: c.textPrimary,
          chevron: c.iconSubtle,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final bool hasError = widget.errorText != null;
    final CbSelectItem<T>? selected = _selected;
    final String text = selected == null
        ? widget.placeholder ?? ''
        : selected.triggerLabel ?? selected.label;

    Widget trigger = CbPressable(
      key: _triggerKey,
      onPressed: _interactive ? _openMenu : null,
      enabled: _interactive,
      tooltip: widget.tooltip,
      focusNode: widget.focusNode,
      semanticLabel: widget.label ?? text,
      builder: (context, state) {
        final paint = _paint(c, state, hasError);
        final Color labelColor = selected == null && !state.disabled
            ? c.textTertiary
            : paint.foreground;

        return AnimatedContainer(
          duration: CbDurations.instant,
          curve: CbCurves.standard,
          height: _height,
          width: widget.width,
          padding: EdgeInsets.symmetric(horizontal: _hPadding),
          decoration: BoxDecoration(
            color: paint.background,
            borderRadius: CbRadii.smAll,
            border: Border.all(
              color: paint.border,
              width: hasError ? CbStrokes.emphasis : CbStrokes.hairline,
            ),
            // Like CbButton, the focus ring sits outside the border instead of
            // recolouring it, so focus stays visible on every variant.
            boxShadow: state.focused
                ? [
                    BoxShadow(
                      color: c.focusRing,
                      spreadRadius: CbStrokes.emphasis,
                    ),
                  ]
                : null,
          ),
          child: Row(
            // `min` matters beyond sizing: a select dropped straight into a
            // `Row` or `Wrap` is laid out with unbounded width, and a flex
            // child under unbounded constraints is only an error when the
            // flex itself asks for `max`.
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (selected?.icon != null) ...[
                Icon(selected!.icon, size: _iconSize, color: paint.foreground),
                const SizedBox(width: CbSpacing.sm),
              ],
              Flexible(
                child: Text(
                  text,
                  style: _textStyle.copyWith(color: labelColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: CbSpacing.sm),
              // The chevron is drawn rather than taken from an icon font, so
              // its weight matches the hairline borders around it at any size.
              _CbChevron(color: paint.chevron, flipped: _isOpen),
            ],
          ),
        );
      },
    );

    if (widget.expand) {
      trigger = SizedBox(width: double.infinity, child: trigger);
    }

    if (widget.label == null && !hasError && widget.helperText == null) {
      return trigger;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: CbTypography.labelSm.copyWith(
              color: widget.enabled ? c.textSecondary : c.textDisabled,
            ),
          ),
          const SizedBox(height: CbSpacing.xs + 2),
        ],
        trigger,
        if (hasError || widget.helperText != null) ...[
          const SizedBox(height: CbSpacing.xs),
          Text(
            widget.errorText ?? widget.helperText!,
            style: CbTypography.caption.copyWith(
              color: hasError ? c.status.danger : c.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

@immutable
class _CbSelectPaint {
  final Color background;
  final Color border;
  final Color foreground;
  final Color chevron;

  const _CbSelectPaint({
    required this.background,
    required this.border,
    required this.foreground,
    required this.chevron,
  });
}

/// The disclosure chevron, rotated 180 degrees while the menu is open.
class _CbChevron extends StatelessWidget {
  final Color color;
  final bool flipped;

  const _CbChevron({required this.color, required this.flipped});

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: flipped ? 0.5 : 0,
      duration: CbDurations.fast,
      curve: CbCurves.standard,
      child: CustomPaint(
        size: const Size(9, 6),
        painter: _CbChevronPainter(color),
      ),
    );
  }
}

class _CbChevronPainter extends CustomPainter {
  final Color color;

  const _CbChevronPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(0.5, size.height * 0.25)
      ..lineTo(size.width / 2, size.height * 0.8)
      ..lineTo(size.width - 0.5, size.height * 0.25);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CbChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The popover route.
///
/// The barrier is transparent rather than a scrim: picking a value is a local
/// choice, and dimming the whole window for it — which Material's dropdown
/// effectively does by taking over the screen — overstates what is happening.
class _CbSelectRoute<T> extends PopupRoute<void> {
  final Rect rect;
  final bool openedBelow;
  final Widget menu;
  final CapturedThemes capturedThemes;

  _CbSelectRoute({
    required this.rect,
    required this.openedBelow,
    required this.menu,
    required this.capturedThemes,
  });

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Duration get transitionDuration => CbDurations.fast;

  @override
  Duration get reverseTransitionDuration => CbDurations.instant;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    // `drive` rather than a `CurvedAnimation`, which the route would have to
    // own and dispose.
    final Animation<double> curved =
        animation.drive(CurveTween(curve: CbCurves.standard));

    return Stack(
      children: [
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: FadeTransition(
            opacity: curved,
            child: AnimatedBuilder(
              animation: curved,
              builder: (context, child) {
                // A 4px rise out of the trigger rather than a grow-from-centre:
                // the popover should read as attached to the control it
                // belongs to, not as a surface of its own.
                final double dy = (1 - curved.value) * (openedBelow ? -4 : 4);
                return Transform.translate(offset: Offset(0, dy), child: child);
              },
              child: capturedThemes.wrap(menu),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

class _CbSelectMenu<T> extends StatefulWidget {
  final List<CbSelectItem<T>> items;
  final T? value;
  final double rowHeight;
  final TextStyle textStyle;
  final double iconSize;
  final ValueChanged<CbSelectItem<T>> onSelected;

  const _CbSelectMenu({
    required this.items,
    required this.value,
    required this.rowHeight,
    required this.textStyle,
    required this.iconSize,
    required this.onSelected,
  });

  @override
  State<_CbSelectMenu<T>> createState() => _CbSelectMenuState<T>();
}

class _CbSelectMenuState<T> extends State<_CbSelectMenu<T>> {
  late final ScrollController _scrollController;
  final FocusNode _focusNode = FocusNode(debugLabel: 'CbSelect menu');
  late int _highlighted;

  @override
  void initState() {
    super.initState();
    _highlighted =
        widget.items.indexWhere((item) => item.value == widget.value);
    // Open with the selected row already in view, so a long list does not
    // start at the top with the current value somewhere off-screen.
    _scrollController = ScrollController(
      initialScrollOffset:
          _highlighted > 0 ? _highlighted * widget.rowHeight : 0,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _move(int delta) {
    if (widget.items.isEmpty) return;
    int next = _highlighted < 0 ? (delta > 0 ? -1 : 0) : _highlighted;
    for (int i = 0; i < widget.items.length; i++) {
      next = (next + delta) % widget.items.length;
      if (next < 0) next += widget.items.length;
      if (widget.items[next].enabled) break;
    }
    setState(() => _highlighted = next);
    _revealHighlighted();
  }

  void _revealHighlighted() {
    if (!_scrollController.hasClients) return;
    final double top = _highlighted * widget.rowHeight;
    final double bottom = top + widget.rowHeight;
    final double viewport = _scrollController.position.viewportDimension;
    final double viewTop = _scrollController.offset;

    double? target;
    if (top < viewTop) target = top;
    if (bottom > viewTop + viewport) target = bottom - viewport;
    if (target == null) return;

    _scrollController.animateTo(
      target.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: CbDurations.instant,
      curve: CbCurves.standard,
    );
  }

  void _commit() {
    if (_highlighted < 0 || _highlighted >= widget.items.length) return;
    final item = widget.items[_highlighted];
    if (!item.enabled) return;
    _select(item);
  }

  void _select(CbSelectItem<T> item) {
    Navigator.of(context).pop();
    widget.onSelected(item);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    // `LogicalKeyboardKey` overrides `==`, so these cannot be switch cases.
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.home) {
      setState(() => _highlighted = 0);
      _revealHighlighted();
    } else if (key == LogicalKeyboardKey.end) {
      setState(() => _highlighted = widget.items.length - 1);
      _revealHighlighted();
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      _commit();
    } else if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else {
      return KeyEventResult.ignored;
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cb;
    final c = tokens.colors;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceOverlay,
          borderRadius: CbRadii.lgAll,
          border: Border.all(color: c.stroke, width: CbStrokes.hairline),
          boxShadow: tokens.shadowLevel3,
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: CbSpacing.xs),
          itemExtent: widget.rowHeight,
          itemCount: widget.items.length,
          itemBuilder: (context, index) => _row(c, index),
        ),
      ),
    );
  }

  Widget _row(CbColorTokens c, int index) {
    final item = widget.items[index];
    final bool isSelected = item.value == widget.value;
    final bool isActive = index == _highlighted && item.enabled;

    final Color background = isActive
        ? c.surfaceHover
        : isSelected
            ? c.surfaceSelected
            : Colors.transparent;
    final Color foreground = !item.enabled
        ? c.textDisabled
        : isSelected
            ? c.textPrimary
            : c.textSecondary;

    return MouseRegion(
      onEnter:
          item.enabled ? (_) => setState(() => _highlighted = index) : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: item.enabled ? () => _select(item) : null,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: CbSpacing.xs),
          padding: const EdgeInsets.only(right: CbSpacing.md),
          decoration: BoxDecoration(
            color: background,
            borderRadius: CbRadii.smAll,
          ),
          child: Row(
            children: [
              // The selection marker is an accent bar on the leading edge, as
              // native list controls use — a checkmark column would push every
              // label right for the sake of one row.
              SizedBox(
                width: CbSpacing.md,
                child: Center(
                  child: AnimatedContainer(
                    duration: CbDurations.fast,
                    curve: CbCurves.standard,
                    width: CbSpacing.xxs + 1,
                    height: isSelected ? widget.rowHeight * 0.45 : 0,
                    decoration: BoxDecoration(
                      color: c.accent.base,
                      borderRadius: CbRadii.all(CbRadii.full),
                    ),
                  ),
                ),
              ),
              if (item.icon != null) ...[
                Icon(
                  item.icon,
                  size: widget.iconSize,
                  color: item.enabled ? c.icon : c.textDisabled,
                ),
                const SizedBox(width: CbSpacing.sm),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: widget.textStyle.copyWith(color: foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
