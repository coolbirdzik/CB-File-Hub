import 'package:flutter/material.dart';
import 'package:path/path.dart' as pathlib;

/// Shared utilities for video player: duration formatting, path, and BoxFit.
class VideoPlayerUtils {
  VideoPlayerUtils._();

  /// Format duration as H:MM:SS when hours > 0, otherwise MM:SS.
  /// Used by video player controls and PiP overlay.
  static String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  /// Format duration as HH:MM:SS (always include hours, zero-padded).
  /// Used by common controls overlay.
  static String formatDurationAlwaysHms(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  /// Format duration as MM:SS (minutes and seconds only).
  /// Used by streaming speed overlay.
  static String formatDurationMmSs(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get file extension from path (e.g. ".mp4").
  static String extensionFromPath(String path) {
    final name = pathlib.basename(path);
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return name.substring(dotIndex).toLowerCase();
  }

  /// Build a label-value row (e.g. for streaming speed overlay). [labelWidth] for the left column.
  static Widget buildLabelValueRow(
    String label,
    String value, {
    Color? textColor,
    double labelWidth = 60,
  }) {
    final c = textColor ?? Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: TextStyle(color: c.withValues(alpha: 0.8), fontSize: 10),
          ),
        ),
        Text(
          value,
          style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  /// Map scale mode string to [BoxFit].
  static BoxFit getBoxFitFromString(String scaleMode) {
    switch (scaleMode) {
      case 'cover':
        return BoxFit.cover;
      case 'contain':
        return BoxFit.contain;
      case 'fill':
        return BoxFit.fill;
      case 'fitWidth':
        return BoxFit.fitWidth;
      case 'fitHeight':
        return BoxFit.fitHeight;
      case 'none':
        return BoxFit.none;
      case 'scaleDown':
        return BoxFit.scaleDown;
      default:
        return BoxFit.cover;
    }
  }
}
