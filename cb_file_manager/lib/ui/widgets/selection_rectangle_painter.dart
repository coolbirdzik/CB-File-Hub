import 'package:flutter/material.dart';

class SelectionRectanglePainter extends CustomPainter {
  final Rect selectionRect;
  final Color fillColor;
  final Color borderColor;

  SelectionRectanglePainter({
    required this.selectionRect,
    required this.fillColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final Gradient borderGradient = LinearGradient(
      colors: [
        borderColor.withValues(alpha: 0.8),
        borderColor.withValues(alpha: 0.6),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final Paint borderPaint = Paint()
      ..shader = borderGradient.createShader(selectionRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final RRect roundedRect = RRect.fromRectAndRadius(
      selectionRect,
      const Radius.circular(4.0),
    );

    canvas.drawRRect(roundedRect, fillPaint);
    canvas.drawRRect(roundedRect, borderPaint);

    final Rect innerHighlight = selectionRect.deflate(2.0);
    if (innerHighlight.width > 0 && innerHighlight.height > 0) {
      final RRect innerRRect = RRect.fromRectAndRadius(
        innerHighlight,
        const Radius.circular(2.0),
      );

      final Paint highlightPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      canvas.drawRRect(innerRRect, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(SelectionRectanglePainter oldDelegate) {
    return oldDelegate.selectionRect != selectionRect ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor;
  }
}
