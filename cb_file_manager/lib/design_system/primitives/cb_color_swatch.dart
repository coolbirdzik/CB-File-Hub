import 'package:flutter/material.dart';

import '../cb_tokens.dart';
import '../tokens/cb_motion_tokens.dart';
import 'cb_decorations.dart';
import 'cb_pressable.dart';

/// A round, pressable colour choice — accent pickers, tag, album and
/// library colours.
///
/// Flat: the selected swatch carries a check mark in whichever ink reads on
/// it, instead of a ring around it. Hover nudges the swatch up in scale;
/// keyboard focus shows the shared focus ring.
///
/// Pass [child] instead of a [color] for a neutral swatch that shows a glyph
/// — a text-colour sample, or the "no colour" choice. Those have no colour to
/// put a check on, so selection is the accent tint fill.
class CbColorSwatch extends StatelessWidget {
  final Color? color;
  final Widget? child;
  final bool selected;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  const CbColorSwatch({
    super.key,
    required Color this.color,
    required this.selected,
    required this.onPressed,
    this.tooltip,
    this.size = 28,
  }) : child = null;

  const CbColorSwatch.glyph({
    super.key,
    required Widget this.child,
    required this.selected,
    required this.onPressed,
    this.tooltip,
    this.size = 28,
  }) : color = null;

  @override
  Widget build(BuildContext context) {
    final c = context.cbColors;
    return CbPressable(
      onPressed: onPressed,
      tooltip: tooltip,
      semanticLabel: tooltip,
      cursor: SystemMouseCursors.click,
      builder: (context, state) {
        final Color fill =
            color ??
            (selected
                ? c.accent.tintStrong
                : CbDecorations.controlFill(
                    c,
                    hovered: state.hovered,
                    pressed: state.pressed,
                  ));
        final Widget? content =
            child ??
            (selected
                ? Icon(
                    Icons.check_rounded,
                    size: size * 0.55,
                    color:
                        ThemeData.estimateBrightnessForColor(fill) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  )
                : null);
        return AnimatedScale(
          duration: CbDurations.fast,
          curve: CbCurves.standard,
          scale: color != null && state.hovered && !selected ? 1.08 : 1.0,
          child: AnimatedContainer(
            duration: CbDurations.fast,
            curve: CbCurves.standard,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              boxShadow: state.focused ? CbDecorations.focusRing(c) : null,
            ),
            child: content,
          ),
        );
      },
    );
  }
}
