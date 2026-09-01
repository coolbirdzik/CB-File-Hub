import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cb_tokens.dart';
import '../tokens/cb_geometry_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import '../tokens/cb_type_tokens.dart';

/// The text input primitive.
///
/// Wraps a bare [EditableText]-backed [TextField] with `InputDecoration.
/// collapsed` and paints the chrome itself. Material's `InputDecorator` brings
/// along the floating label, the animated underline and a 48px minimum height
/// that cannot be fully overridden — all of which are unmistakably Material
/// and all of which are wrong for a dense desktop app. Here the label sits
/// above the field, the field is 32px, and focus uses a neutral raised fill.
class CbTextField extends StatefulWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Label rendered above the field. Static — it does not float on focus.
  final String? label;

  final String? placeholder;

  /// Helper text under the field. Replaced by [errorText] when that is set.
  final String? helperText;

  /// Puts the field in its error state and shows this message.
  final String? errorText;

  final IconData? prefixIcon;

  /// Trailing affordance — a clear button, a unit suffix, a picker trigger.
  final Widget? suffix;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autofocus;

  /// Grows the field to this many lines. 1 keeps it a single-line control.
  final int maxLines;
  final int? maxLength;

  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlign textAlign;

  /// Uses the monospace face — for paths, hashes and numeric input.
  final bool mono;

  const CbTextField({
    Key? key,
    this.controller,
    this.focusNode,
    this.label,
    this.placeholder,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
    this.textInputAction,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.mono = false,
  }) : super(key: key);

  @override
  State<CbTextField> createState() => _CbTextFieldState();
}

class _CbTextFieldState extends State<CbTextField> {
  FocusNode? _ownedFocusNode;
  bool _focused = false;
  bool _hovered = false;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(CbTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      _ownedFocusNode?.removeListener(_onFocusChange);
      _focusNode.addListener(_onFocusChange);
    }
  }

  void _onFocusChange() {
    if (_focused == _focusNode.hasFocus) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
    _ownedFocusNode?.removeListener(_onFocusChange);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    final bool hasError = widget.errorText != null;
    final bool isEnabled = widget.enabled;
    final bool multiline = widget.maxLines > 1;

    final Color borderColor = !isEnabled
        ? c.strokeSubtle
        : hasError
            ? c.status.danger
            : (_focused || _hovered)
                ? c.strokeStrong
                : c.stroke;
    final Color fillColor = !isEnabled
        ? c.surfaceSunken.withValues(alpha: 0.5)
        : _focused
            ? c.surfaceRaised
            : c.surfaceSunken;

    final TextStyle textStyle =
        (widget.mono ? CbTypography.mono : CbTypography.body).copyWith(
      color: isEnabled ? c.textPrimary : c.textDisabled,
    );

    final field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: isEnabled,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines,
      maxLength: widget.maxLength,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      textAlign: widget.textAlign,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: widget.onTap,
      style: textStyle,
      cursorColor: c.accent.base,
      cursorWidth: CbStrokes.hairline,
      cursorRadius: const Radius.circular(CbRadii.xs),
      // `collapsed` is the point of this widget: it strips the Material
      // decorator entirely, leaving the container below to do the drawing.
      decoration: InputDecoration.collapsed(
        hintText: widget.placeholder,
        hintStyle: CbTypography.body.copyWith(color: c.textTertiary),
      ).copyWith(
        counterText: '',
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: CbTypography.labelSm.copyWith(
              color: isEnabled ? c.textSecondary : c.textDisabled,
            ),
          ),
          const SizedBox(height: CbSpacing.xs + 2),
        ],
        MouseRegion(
          cursor:
              isEnabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: CbDurations.instant,
            curve: CbCurves.standard,
            height: multiline ? null : CbSizes.controlMd,
            padding: EdgeInsets.symmetric(
              horizontal: CbSpacing.sm + 2,
              vertical: multiline ? CbSpacing.sm : 0,
            ),
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: CbRadii.smAll,
              border: Border.all(
                color: borderColor,
                // Focus now reads through the fill; only errors need the
                // heavier outline so the field does not look alarmed.
                width: hasError ? CbStrokes.emphasis : CbStrokes.hairline,
              ),
            ),
            child: Row(
              crossAxisAlignment: multiline
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                if (widget.prefixIcon != null) ...[
                  Icon(
                    widget.prefixIcon,
                    size: CbSizes.iconMd,
                    color: isEnabled ? c.iconSubtle : c.textDisabled,
                  ),
                  const SizedBox(width: CbSpacing.sm),
                ],
                Expanded(child: field),
                if (widget.suffix != null) ...[
                  const SizedBox(width: CbSpacing.sm),
                  widget.suffix!,
                ],
              ],
            ),
          ),
        ),
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
