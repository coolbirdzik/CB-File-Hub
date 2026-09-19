import 'package:flutter/material.dart';

import '../tokens/cb_motion_tokens.dart';

/// The thin Fluent disclosure chevron, pointing down, turned 180 degrees
/// while [flipped] — an open select menu, an expanded expander.
class CbChevron extends StatelessWidget {
  final Color color;
  final bool flipped;

  const CbChevron({super.key, required this.color, required this.flipped});

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
