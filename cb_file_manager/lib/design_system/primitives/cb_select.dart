import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cb_tokens.dart';
import '../tokens/cb_color_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_chevron.dart';
import 'cb_decorations.dart';
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

  /// Extra text matched by a searchable select's filter, beyond [label] — an
  /// alias, a translation, a code. Never shown.
  final String? keywords;

  const CbSelectItem({
    required this.value,
    required this.label,
    this.triggerLabel,
    this.icon,
    this.enabled = true,
    this.keywords,
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
  /// Field chrome: tonal fill and a focus indicator, matching `CbTextField`.
  filled,

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
/// lifted by its shadow, rows highlight on hover with a colour change rather
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

  /// Puts a filter field at the top of the menu. Typing narrows the rows by
  /// label and [CbSelectItem.keywords]; Up/Down/Enter still drive the list
  /// while the field has focus. For long or unfamiliar lists — languages,
  /// time zones — where scanning by eye is slower than typing.
  final bool searchable;

  /// Placeholder for the filter field. Only used when [searchable].
  final String? searchPlaceholder;

  /// Shown when the filter matches nothing. Only used when [searchable].
  final String? searchEmptyText;

  /// Glyph at the start of the filter row. Only used when [searchable].
  final IconData searchIcon;

  const CbSelect({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.label,
    this.placeholder,
    this.helperText,
    this.errorText,
    this.size = CbSelectSize.md,
    this.variant = CbSelectVariant.filled,
    this.enabled = true,
    this.expand = false,
    this.width,
    this.tooltip,
    this.focusNode,
    this.searchable = false,
    this.searchPlaceholder,
    this.searchEmptyText,
    this.searchIcon = Icons.search_rounded,
  });

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
    CbSelectVariant variant = CbSelectVariant.filled,
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

    final Offset origin = anchorBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final Rect anchor = origin & anchorBox.size;
    final Rect rect = _menuRect(anchor, overlayBox.size);

    setState(() => _isOpen = true);
    await navigator.push(
      _CbSelectRoute<T>(
        rect: rect,
        openedBelow: rect.top >= anchor.bottom,
        fitContent: widget.searchable,
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: navigator.context,
        ),
        menu: _CbSelectMenu<T>(
          items: widget.items,
          value: widget.value,
          rowHeight: _height,
          textStyle: _textStyle,
          iconSize: _iconSize,
          searchable: widget.searchable,
          searchPlaceholder: widget.searchPlaceholder,
          searchEmptyText: widget.searchEmptyText,
          searchIcon: widget.searchIcon,
          onSelected: (item) => widget.onChanged?.call(item.value),
        ),
      ),
    );
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

    // A searchable menu carries a filter row above the list.
    final double contentHeight =
        widget.items.length * _height +
        CbSpacing.xs * 2 +
        (widget.searchable ? _height + CbSpacing.xs : 0);
    final double spaceBelow = screen.height - anchor.bottom - gap - margin;
    final double spaceAbove = anchor.top - gap - margin;

    final bool below = contentHeight <= spaceBelow || spaceBelow >= spaceAbove;
    final double available = below ? spaceBelow : spaceAbove;
    final double height = math.max(
      math.min(math.min(contentHeight, maxHeight), available),
      0,
    );

    final double left = anchor.left.clamp(
      margin,
      math.max(screen.width - width - margin, margin),
    );
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
    final double chrome =
        CbSpacing.md * 2 +
        (hasIcons ? _iconSize + CbSpacing.sm : 0) +
        CbSpacing.md;

    return math.max(widest + chrome, scaler.scale(120));
  }

  _CbSelectPaint _paint(CbColorTokens c, CbInteractionState s) {
    if (s.disabled) {
      return _CbSelectPaint(
        background: widget.variant == CbSelectVariant.filled
            ? c.fillSubtle
            : Colors.transparent,
        foreground: c.textDisabled,
        chevron: c.textDisabled,
      );
    }

    final bool active = s.pressed || _isOpen;

    switch (widget.variant) {
      case CbSelectVariant.filled:
        return _CbSelectPaint(
          background: CbDecorations.controlFill(
            c,
            hovered: s.hovered,
            pressed: active,
          ),
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
    final bool fillsWidth = widget.expand || widget.width != null;

    Widget trigger = CbPressable(
      key: _triggerKey,
      onPressed: _interactive ? _openMenu : null,
      enabled: _interactive,
      tooltip: widget.tooltip,
      focusNode: widget.focusNode,
      semanticLabel: widget.label ?? text,
      builder: (context, state) {
        final paint = _paint(c, state);
        final Color labelColor = selected == null && !state.disabled
            ? c.textTertiary
            : paint.foreground;
        final Widget labelText = Text(
          text,
          style: _textStyle.copyWith(color: labelColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );

        return AnimatedContainer(
          duration: CbDurations.instant,
          curve: CbCurves.standard,
          height: _height,
          width: widget.width,
          padding: EdgeInsets.symmetric(horizontal: _hPadding),
          decoration: BoxDecoration(
            color: paint.background,
            borderRadius: CbRadii.smAll,
            // Open reads as focused: the same bottom indicator a text field
            // shows, so a select and an input side by side stay in step.
            border: CbDecorations.fieldIndicator(
              c,
              focused: _isOpen && widget.variant == CbSelectVariant.filled,
              error: hasError,
              enabled: !state.disabled,
            ),
            // Like CbButton, the keyboard focus ring sits outside the shape.
            boxShadow: state.focused ? CbDecorations.focusRing(c) : null,
          ),
          child: Row(
            // `min` matters beyond sizing: a select dropped straight into a
            // `Row` or `Wrap` is laid out with unbounded width, and a flex
            // child under unbounded constraints is only an error when the
            // flex itself asks for `max`.
            mainAxisSize: fillsWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (selected?.icon != null) ...[
                Icon(selected!.icon, size: _iconSize, color: paint.foreground),
                const SizedBox(width: CbSpacing.sm),
              ],
              // A trigger with a set width has room to spare: the label takes
              // it so the chevron sits on the trailing edge like a native
              // combo box, rather than trailing right after short text.
              if (fillsWidth)
                Expanded(child: labelText)
              else
                Flexible(child: labelText),
              const SizedBox(width: CbSpacing.sm),
              // The chevron is drawn rather than taken from an icon font, so
              // its weight matches the hairline borders around it at any size.
              CbChevron(color: paint.chevron, flipped: _isOpen),
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
  final Color foreground;
  final Color chevron;

  const _CbSelectPaint({
    required this.background,
    required this.foreground,
    required this.chevron,
  });
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

  /// Sizes the popover to its content, up to [rect]'s height, instead of
  /// pinning it to [rect]. A filtered list shrinks as rows drop out; a fixed
  /// box would leave a hollow tail under the last match.
  final bool fitContent;

  _CbSelectRoute({
    required this.rect,
    required this.openedBelow,
    required this.menu,
    required this.capturedThemes,
    this.fitContent = false,
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
    final Animation<double> curved = animation.drive(
      CurveTween(curve: CbCurves.standard),
    );

    final Widget popover = FadeTransition(
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
    );

    if (fitContent) {
      return LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned(
              left: rect.left,
              width: rect.width,
              // Anchored on the edge nearest the trigger, so a menu opened
              // upwards shrinks away from the trigger rather than towards it.
              top: openedBelow ? rect.top : null,
              bottom: openedBelow ? null : constraints.maxHeight - rect.bottom,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: rect.height),
                child: popover,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: popover,
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
  ) => child;
}

class _CbSelectMenu<T> extends StatefulWidget {
  final List<CbSelectItem<T>> items;
  final T? value;
  final double rowHeight;
  final TextStyle textStyle;
  final double iconSize;
  final bool searchable;
  final String? searchPlaceholder;
  final String? searchEmptyText;
  final IconData searchIcon;
  final ValueChanged<CbSelectItem<T>> onSelected;

  const _CbSelectMenu({
    required this.items,
    required this.value,
    required this.rowHeight,
    required this.textStyle,
    required this.iconSize,
    required this.searchable,
    required this.searchIcon,
    required this.onSelected,
    this.searchPlaceholder,
    this.searchEmptyText,
  });

  @override
  State<_CbSelectMenu<T>> createState() => _CbSelectMenuState<T>();
}

class _CbSelectMenuState<T> extends State<_CbSelectMenu<T>> {
  late final ScrollController _scrollController;
  final FocusNode _focusNode = FocusNode(debugLabel: 'CbSelect menu');
  final TextEditingController _query = TextEditingController();
  late final FocusNode _searchFocusNode;
  late List<CbSelectItem<T>> _visible;
  late int _highlighted;

  @override
  void initState() {
    super.initState();
    _visible = widget.items;
    // The field owns focus while it is open, so the list keys have to be
    // taken here, ahead of the text editing shortcuts, not from a parent.
    _searchFocusNode = FocusNode(
      debugLabel: 'CbSelect search',
      onKeyEvent: _onKey,
    );
    _highlighted = _visible.indexWhere((item) => item.value == widget.value);
    // Open with the selected row already in view, so a long list does not
    // start at the top with the current value somewhere off-screen.
    _scrollController = ScrollController(
      initialScrollOffset: _highlighted > 0
          ? _highlighted * widget.rowHeight
          : 0,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    _query.dispose();
    super.dispose();
  }

  void _onQueryChanged(String raw) {
    final String query = raw.trim().toLowerCase();
    setState(() {
      _visible = query.isEmpty
          ? widget.items
          : [
              for (final item in widget.items)
                if ('${item.label} ${item.keywords ?? ''}'
                    .toLowerCase()
                    .contains(query))
                  item,
            ];
      _highlighted = _visible.indexWhere((item) => item.enabled);
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _move(int delta) {
    if (_visible.isEmpty) return;
    int next = _highlighted < 0 ? (delta > 0 ? -1 : 0) : _highlighted;
    for (int i = 0; i < _visible.length; i++) {
      next = (next + delta) % _visible.length;
      if (next < 0) next += _visible.length;
      if (_visible[next].enabled) break;
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
    if (_highlighted < 0 || _highlighted >= _visible.length) return;
    final item = _visible[_highlighted];
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

    // With a filter field, Space, Home and End belong to the text.
    if (widget.searchable &&
        (key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.home ||
            key == LogicalKeyboardKey.end)) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.home) {
      setState(() => _highlighted = 0);
      _revealHighlighted();
    } else if (key == LogicalKeyboardKey.end) {
      setState(() => _highlighted = _visible.length - 1);
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

    final Widget list = ListView.builder(
      controller: _scrollController,
      shrinkWrap: widget.searchable,
      padding: const EdgeInsets.symmetric(vertical: CbSpacing.xs),
      itemExtent: widget.rowHeight,
      itemCount: _visible.length,
      itemBuilder: (context, index) => _row(c, index),
    );

    return Focus(
      focusNode: _focusNode,
      autofocus: !widget.searchable,
      onKeyEvent: _onKey,
      child: Container(
        decoration: CbDecorations.floating(context),
        clipBehavior: Clip.antiAlias,
        child: widget.searchable
            // The popover lives in the Navigator's overlay, above any Material
            // ancestor; the filter field's TextField needs one.
            ? Material(
                type: MaterialType.transparency,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _searchHeader(c),
                    Flexible(
                      child: _visible.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(CbSpacing.md),
                              child: Text(
                                widget.searchEmptyText ?? '',
                                textAlign: TextAlign.center,
                                style: widget.textStyle.copyWith(
                                  color: c.textTertiary,
                                ),
                              ),
                            )
                          : list,
                    ),
                  ],
                ),
              )
            : list,
      ),
    );
  }

  /// The filter row: a flat strip one step up the fill ramp, running the full
  /// width of the popover. No field chrome and no focus indicator — the menu
  /// is the container and the caret is the focus cue. A boxed input inside a
  /// popover stacks a second surface on the first.
  Widget _searchHeader(CbColorTokens c) {
    return Container(
      height: widget.rowHeight + CbSpacing.xs,
      color: c.fillSubtle,
      padding: const EdgeInsets.symmetric(horizontal: CbSpacing.md),
      child: Row(
        children: [
          Icon(widget.searchIcon, size: CbSizes.iconMd, color: c.iconSubtle),
          const SizedBox(width: CbSpacing.sm),
          Expanded(
            child: TextField(
              controller: _query,
              focusNode: _searchFocusNode,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              style: widget.textStyle.copyWith(color: c.textPrimary),
              cursorColor: c.accent.base,
              cursorWidth: CbStrokes.hairline,
              cursorRadius: const Radius.circular(CbRadii.xs),
              // `collapsed` strips the Material decorator; the strip above
              // does the drawing. Every state border is cleared so the app's
              // input theme cannot draw one back in.
              decoration:
                  InputDecoration.collapsed(
                    hintText: widget.searchPlaceholder,
                    hintStyle: widget.textStyle.copyWith(color: c.textTertiary),
                  ).copyWith(
                    isDense: true,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(CbColorTokens c, int index) {
    final item = _visible[index];
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
      onEnter: item.enabled
          ? (_) => setState(() => _highlighted = index)
          : null,
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
