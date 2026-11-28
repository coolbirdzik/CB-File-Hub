import 'package:material_ui/material_ui.dart';

import '../../config/languages/app_localizations.dart';
import '../cb_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import '../tokens/cb_type_tokens.dart';

/// Indeterminate activity, expressed as a moving colour highlight on text.
/// Use [text] for the actual work, or leave it unset for the localized loading
/// label. Tight icon slots may use [compact] without losing the accessible label.
class CbLoadingText extends StatefulWidget {
  final String? text;
  final TextStyle? style;
  final Color? baseColor;
  final Color? highlightColor;
  final bool compact;
  final int? maxLines;
  final TextAlign textAlign;

  const CbLoadingText({
    super.key,
    this.text,
    this.style,
    this.baseColor,
    this.highlightColor,
    this.compact = false,
    this.maxLines = 1,
    this.textAlign = TextAlign.center,
  });

  @override
  State<CbLoadingText> createState() => _CbLoadingTextState();
}

class _CbLoadingTextState extends State<CbLoadingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CbDurations.ambient,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.cbColors;
    final label =
        widget.text ?? AppLocalizations.of(context)?.loading ?? 'Loading';
    final highlight = widget.highlightColor ?? colors.accent.text;
    final base =
        widget.baseColor ??
        widget.style?.color ??
        (widget.highlightColor == null
            ? colors.textSecondary
            : highlight.withValues(alpha: highlight.a * .65));
    final style =
        widget.style ??
        (widget.compact ? CbTypography.labelXs : CbTypography.bodySm);
    final labelText = Text(
      widget.compact ? '…' : label,
      semanticsLabel: widget.compact ? label : null,
      maxLines: widget.maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: widget.textAlign,
      style: style.copyWith(color: _reduceMotion ? highlight : Colors.white),
    );
    final text = widget.compact
        ? FittedBox(fit: BoxFit.scaleDown, child: labelText)
        : labelText;
    if (_reduceMotion) return text;

    return AnimatedBuilder(
      animation: _controller,
      child: text,
      builder: (context, child) {
        // Move an entire highlight band from outside the left edge to outside
        // the right edge. Both ends are base-coloured so the loop has no jump.
        final left = -0.55 + 1.55 * _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(left * 2 - 1, 0),
            end: Alignment((left + .55) * 2 - 1, 0),
            colors: [base, highlight, base],
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}
