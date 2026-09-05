import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import '../tokens/cb_type_tokens.dart';
import 'cb_button.dart';
import 'cb_surface.dart';

/// Characters Windows — the strictest of the three desktop targets — refuses
/// in a file or folder name. Blocked at the keystroke so the field can never
/// hold a value the filesystem would reject.
final RegExp cbInvalidNameChars = RegExp(r'[\\/:*?"<>|]');

/// How far a lifted rename editor may grow before it starts scrolling
/// instead. Five lines of a grid label is already a ~200-character name; past
/// that, wrapping stops helping and the box just swallows the view behind it.
const int cbInlineRenameMaxLines = 5;

/// The global rect a widget currently occupies, for anchoring the rename
/// popover to the row the user acted on. Null when the element is not laid out.
Rect? cbAnchorRectOf(BuildContext context) {
  final RenderObject? object = context.findRenderObject();
  if (object is! RenderBox || !object.hasSize || !object.attached) return null;
  return object.localToGlobal(Offset.zero) & object.size;
}

/// The in-place rename editor.
///
/// Replaces a file, folder or tag label exactly where it sits, so the row
/// never jumps and the user keeps their place in the list. It reads as a
/// lifted slab of the row rather than a form control: an overlay fill, a
/// hairline that thickens to the accent on focus, and a crisp accent ring so
/// the name being edited is unmistakable in a dense grid.
///
/// [lockedSuffix] renders the part of the name the user is not editing — the
/// file extension when extension renaming is off — dimmed and inside the
/// field, so the full resulting name stays visible while typing instead of
/// being silently re-appended on commit.
class CbInlineRenameField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Enter, and the confirm affordance where one is shown.
  final VoidCallback onCommit;

  /// Escape.
  final VoidCallback onCancel;

  /// Focus left the field. Deliberately not defaulted: "blur commits" and
  /// "blur cancels" are both defensible, and the surrounding view decides.
  final VoidCallback? onBlur;

  /// Immutable trailing run, shown dimmed inside the field.
  final String? lockedSuffix;

  /// Leading glyph — usually the item's own icon, so the field still reads as
  /// that row rather than as a floating input.
  final Widget? leading;

  final TextStyle? textStyle;
  final TextAlign textAlign;
  final int maxLines;
  final int? maxLength;
  final bool autofocus;

  /// Tightens the vertical padding for grid tiles, where the label sits in a
  /// fixed-height band.
  final bool dense;

  /// Paints the field in its invalid state. Validation itself belongs to the
  /// caller, the only thing that knows whether a name collides.
  final bool hasError;

  /// Blocks the characters no filesystem accepts. On for file and folder
  /// names; off for tags, which are free-form labels and never become paths.
  final bool restrictToFilesystemSafeCharacters;

  final ValueChanged<String>? onChanged;

  const CbInlineRenameField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCommit,
    required this.onCancel,
    this.onBlur,
    this.lockedSuffix,
    this.leading,
    this.textStyle,
    this.textAlign = TextAlign.start,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = true,
    this.dense = false,
    this.hasError = false,
    this.restrictToFilesystemSafeCharacters = true,
    this.onChanged,
  });

  @override
  State<CbInlineRenameField> createState() => _CbInlineRenameFieldState();
}

class _CbInlineRenameFieldState extends State<CbInlineRenameField> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(CbInlineRenameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      _focused = widget.focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    final bool has = widget.focusNode.hasFocus;
    if (has != _focused && mounted) {
      setState(() => _focused = has);
    }
    if (!has) widget.onBlur?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.onCommit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cb;
    final c = tokens.colors;

    final Color accent = widget.hasError ? c.status.danger : c.accent.base;
    final TextStyle style = (widget.textStyle ?? CbTypography.body).copyWith(
      color: c.textPrimary,
    );

    final field = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      style: style,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      // Without this a multi-line field reserves all `maxLines` up front, so
      // renaming "a.txt" opens a box five lines tall. The field should start
      // at one line and grow only as the name actually wraps.
      minLines: widget.maxLines > 1 ? 1 : null,
      maxLength: widget.maxLength,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onCommit(),
      cursorColor: accent,
      cursorWidth: CbStrokes.emphasis,
      cursorRadius: const Radius.circular(CbRadii.xs),
      inputFormatters: widget.restrictToFilesystemSafeCharacters
          ? [FilteringTextInputFormatter.deny(cbInvalidNameChars)]
          : null,
      // `collapsed` strips Material's decorator — its floating label, animated
      // underline and 48px floor all fight the row this field stands in.
      decoration: const InputDecoration.collapsed(hintText: null).copyWith(
        counterText: '',
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: AnimatedContainer(
          duration: CbDurations.fast,
          curve: CbCurves.standard,
          padding: EdgeInsets.symmetric(
            horizontal: CbSpacing.sm,
            vertical: widget.dense ? CbSpacing.xxs : CbSpacing.xs + 1,
          ),
          decoration: BoxDecoration(
            color: c.surfaceOverlay,
            borderRadius: CbRadii.mdAll,
            border: Border.all(
              color: _focused || widget.hasError ? accent : c.stroke,
              width: _focused || widget.hasError
                  ? CbStrokes.emphasis
                  : CbStrokes.hairline,
            ),
            boxShadow: [
              ...tokens.shadowLevel2,
              // A crisp ring rather than a blur: at 13px type a soft halo only
              // muddies the edge the border already draws.
              if (_focused)
                BoxShadow(
                  color: accent.withValues(alpha: tokens.isDark ? 0.30 : 0.18),
                  spreadRadius: CbStrokes.emphasis,
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: widget.maxLines > 1
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: CbSpacing.xs + 2),
              ],
              Flexible(child: field),
              if (widget.lockedSuffix != null &&
                  widget.lockedSuffix!.isNotEmpty) ...[
                const SizedBox(width: CbSpacing.xxs),
                Text(
                  widget.lockedSuffix!,
                  style: style.copyWith(color: c.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lifts the in-place editor out of the layout for as long as a rename runs.
///
/// A grid tile budgets a fixed-height band for its label — 40px, 58px with
/// tags — and that budget is measured for the bare text. An editor has a
/// border and padding on top of that, and it has to show the *whole* name
/// rather than the two ellipsised lines the label settles for, because the
/// one thing a rename box must never do is hide the text being typed.
///
/// Those two demands cannot both be met inside the band, and the tile cannot
/// grow: the grid gives every tile the same extent. So the editor is pinned to
/// the band and drawn in the overlay instead, free to wrap downward over the
/// tiles below. The label keeps its slot underneath, invisible, so nothing
/// reflows while the editor is open.
class CbInlineRenameOverlay extends StatefulWidget {
  /// Whether the rename is running. Toggling this shows or hides the editor.
  final bool active;

  /// The normal label. Stays in the layout while [active] so the tile keeps
  /// its shape, just hidden under the editor.
  final Widget label;

  /// Builds the editor. Called only while [active].
  final WidgetBuilder editorBuilder;

  /// Floor for the editor's width, and the width used on the first frame,
  /// before the label has been laid out and reported its own. The editor is
  /// otherwise exactly as wide as the label it covers.
  final double minWidth;

  const CbInlineRenameOverlay({
    super.key,
    required this.active,
    required this.label,
    required this.editorBuilder,
    this.minWidth = 160,
  });

  @override
  State<CbInlineRenameOverlay> createState() => _CbInlineRenameOverlayState();
}

class _CbInlineRenameOverlayState extends State<CbInlineRenameOverlay> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  /// The label's width, republished on every layout so the editor tracks the
  /// tile through grid zoom and window resizes.
  final ValueNotifier<double> _anchorWidth = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    if (widget.active) _portal.show();
  }

  @override
  void didUpdateWidget(CbInlineRenameOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  @override
  void dispose() {
    _anchorWidth.dispose();
    super.dispose();
  }

  Widget _buildEditor(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _anchorWidth,
      builder: (context, width, _) {
        // Positioned so the follower is laid out loose against the overlay's
        // stack; the transform below is what actually places it.
        return Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.topCenter,
            child: SizedBox(
              width: math.max(width, widget.minWidth),
              child: Material(
                type: MaterialType.transparency,
                child: widget.editorBuilder(context),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: _buildEditor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedWidth) {
            // Layout-phase write, so defer to avoid marking the notifier's
            // listeners dirty during this frame's build.
            final double width = constraints.maxWidth;
            if (width != _anchorWidth.value) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _anchorWidth.value = width;
              });
            }
          }
          return CompositedTransformTarget(
            link: _link,
            child: Opacity(
              opacity: widget.active ? 0 : 1,
              child: IgnorePointer(
                ignoring: widget.active,
                child: widget.label,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The rename popover, for the places a name cannot be edited in place — the
/// trash bin, the drive list, the tag manager, and mobile, where no row is
/// wide enough to type into.
///
/// Deliberately not a dialog: no 24px insets, no title bar, no all-caps
/// buttons. It is the inline field with just enough chrome to stand on its
/// own, opening against the row it belongs to when the caller can say where
/// that row is.
class CbInlineRenamePanel extends StatefulWidget {
  final String title;

  /// The name being replaced, set small under the title so the user can
  /// confirm they are editing the row they meant.
  final String? subtitle;

  final String initialValue;
  final String? lockedSuffix;
  final IconData? icon;
  final Color? iconColor;

  /// The keyboard-affordance line, e.g. "Enter to save · Esc to cancel".
  final String? hintText;

  final String confirmLabel;
  final String cancelLabel;
  final int? maxLength;
  final double width;

  /// Returns an error message for [value], or null when it is acceptable.
  /// Called on every keystroke; confirm stays disabled while it returns
  /// non-null.
  final String? Function(String value)? validator;

  const CbInlineRenamePanel({
    super.key,
    required this.title,
    required this.initialValue,
    required this.confirmLabel,
    required this.cancelLabel,
    this.subtitle,
    this.lockedSuffix,
    this.icon,
    this.iconColor,
    this.hintText,
    this.maxLength,
    this.width = 360,
    this.validator,
  });

  @override
  State<CbInlineRenamePanel> createState() => _CbInlineRenamePanelState();
}

class _CbInlineRenamePanelState extends State<CbInlineRenamePanel> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _error;
  bool _empty = false;

  /// Enter reaches the field twice — once as a key event, once as the text
  /// input's submit action — and each would pop a route. Latch the first.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.initialValue.length,
    );
    _focusNode = FocusNode();
    _empty = widget.initialValue.trim().isEmpty;
    _error = widget.validator?.call(widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canCommit => !_empty && _error == null;

  void _onChanged(String value) {
    final String? nextError = widget.validator?.call(value);
    final bool nextEmpty = value.trim().isEmpty;
    if (nextError != _error || nextEmpty != _empty) {
      setState(() {
        _error = nextError;
        _empty = nextEmpty;
      });
    }
  }

  void _commit() {
    if (!_canCommit || _closing) return;
    _closing = true;
    Navigator.of(context).pop(_controller.text.trim());
  }

  void _cancel() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;

    // The panel keeps its desktop width until the window cannot hold it —
    // on a phone that means edge-to-edge minus the same margin the anchor
    // layout keeps.
    final double available =
        MediaQuery.sizeOf(context).width - CbSpacing.md * 2;

    return SizedBox(
      width: math.min(widget.width, math.max(240, available)),
      child: CbSurface(
        level: CbSurfaceLevel.overlay,
        bordered: true,
        radius: CbRadii.lg,
        padding: const EdgeInsets.all(CbSpacing.md + 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.icon != null) ...[
                  Container(
                    width: CbSizes.controlXs,
                    height: CbSizes.controlXs,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (widget.iconColor ?? c.accent.base).withValues(
                        alpha: 0.14,
                      ),
                      borderRadius: CbRadii.smAll,
                    ),
                    child: Icon(
                      widget.icon,
                      size: CbSizes.iconSm,
                      color: widget.iconColor ?? c.accent.text,
                    ),
                  ),
                  const SizedBox(width: CbSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: CbTypography.label.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: CbTypography.caption.copyWith(
                            color: c.textTertiary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: CbSpacing.md),
            CbInlineRenameField(
              controller: _controller,
              focusNode: _focusNode,
              onCommit: _commit,
              onCancel: _cancel,
              lockedSuffix: widget.lockedSuffix,
              maxLength: widget.maxLength,
              hasError: _error != null,
              onChanged: _onChanged,
            ),
            if (_error != null) ...[
              const SizedBox(height: CbSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: CbSizes.iconSm,
                    color: c.status.danger,
                  ),
                  const SizedBox(width: CbSpacing.xs + 2),
                  Expanded(
                    child: Text(
                      _error!,
                      style: CbTypography.caption.copyWith(
                        color: c.status.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: CbSpacing.md + 2),
            Row(
              children: [
                if (widget.hintText != null)
                  Expanded(
                    child: Text(
                      widget.hintText!,
                      style: CbTypography.caption.copyWith(
                        color: c.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: CbSpacing.sm),
                CbButton(
                  label: widget.cancelLabel,
                  size: CbButtonSize.sm,
                  variant: CbButtonVariant.ghost,
                  onPressed: _cancel,
                ),
                const SizedBox(width: CbSpacing.xs + 2),
                CbButton(
                  label: widget.confirmLabel,
                  size: CbButtonSize.sm,
                  variant: CbButtonVariant.primary,
                  onPressed: _canCommit ? _commit : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Places the panel against [anchor] — opening downward from just below the
/// row, flipping above when the bottom of the window is close, and clamping
/// into the viewport either way.
class _CbAnchorLayout extends SingleChildLayoutDelegate {
  /// Keep-out distance from the window edges.
  static const double margin = CbSpacing.md;

  final Rect anchor;

  const _CbAnchorLayout(this.anchor);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final double maxX = math.max(margin, size.width - childSize.width - margin);
    final double maxY = math.max(
      margin,
      size.height - childSize.height - margin,
    );

    // Callers hand us whatever context they have, and that is sometimes the
    // whole list rather than the row. Anchoring to a rect that large would
    // park the panel off the bottom of the window, so fall back to centring.
    if (anchor.height > size.height * 0.4) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }

    double dx = anchor.left - CbSpacing.md;
    double dy = anchor.bottom + CbSpacing.xs;

    if (dy > maxY) {
      final double above = anchor.top - childSize.height - CbSpacing.xs;
      dy = above >= margin ? above : maxY;
    }

    return Offset(dx.clamp(margin, maxX), dy.clamp(margin, maxY));
  }

  @override
  bool shouldRelayout(_CbAnchorLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// Shows [CbInlineRenamePanel] and completes with the trimmed new name, or
/// null when the user backed out.
///
/// Pass [anchorRect] (see [cbAnchorRectOf]) to open the panel against the row
/// being renamed instead of in the middle of the window — that is what makes
/// the interaction read as inline rather than modal.
Future<String?> showCbInlineRename({
  required BuildContext context,
  required String title,
  required String initialValue,
  required String confirmLabel,
  required String cancelLabel,
  String? subtitle,
  String? lockedSuffix,
  IconData? icon,
  Color? iconColor,
  String? hintText,
  Rect? anchorRect,
  int? maxLength,
  String? Function(String value)? validator,
  double width = 360,
}) {
  final c = context.cbColors;

  final panel = CbInlineRenamePanel(
    title: title,
    subtitle: subtitle,
    initialValue: initialValue,
    lockedSuffix: lockedSuffix,
    icon: icon,
    iconColor: iconColor,
    hintText: hintText,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    maxLength: maxLength,
    width: width,
    validator: validator,
  );

  return showGeneralDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: title,
    // Lighter than a dialog scrim: this is a local edit, and dimming the whole
    // window for it would overstate what is happening.
    barrierColor: c.scrim.withValues(alpha: 0.18),
    transitionDuration: CbDurations.fast,
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, _) {
      final Animation<double> curved = CurvedAnimation(
        parent: animation,
        curve: CbCurves.standard,
        reverseCurve: CbCurves.exit,
      );

      final Widget body = FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
          alignment: anchorRect == null ? Alignment.center : Alignment.topLeft,
          child: Material(type: MaterialType.transparency, child: panel),
        ),
      );

      if (anchorRect == null) {
        return Center(child: body);
      }
      return CustomSingleChildLayout(
        delegate: _CbAnchorLayout(anchorRect),
        child: body,
      );
    },
  );
}
