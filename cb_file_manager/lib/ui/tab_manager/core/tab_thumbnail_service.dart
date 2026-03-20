import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Service for capturing tab thumbnails
class TabThumbnailService {
  /// Capture screenshot from RepaintBoundary
  static Future<Uint8List?> captureTabThumbnail(GlobalKey key) async {
    try {
      // Get the RenderRepaintBoundary
      final RenderRepaintBoundary? boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;

      if (boundary == null) {
        debugPrint('TabThumbnailService: RepaintBoundary not found');
        return null;
      }

      // Capture the image with reduced quality for smaller file size
      final ui.Image image = await boundary.toImage(pixelRatio: 0.5);

      // Convert to byte data
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('TabThumbnailService: Failed to convert image to bytes');
        return null;
      }

      final Uint8List pngBytes = byteData.buffer.asUint8List();

      debugPrint(
          'TabThumbnailService: Captured thumbnail (${pngBytes.length} bytes)');
      return pngBytes;
    } catch (e) {
      debugPrint('TabThumbnailService: Error capturing thumbnail: $e');
      return null;
    }
  }

  /// Check if thumbnail is stale (older than 5 minutes)
  static bool isThumbnailStale(DateTime? capturedAt) {
    if (capturedAt == null) return true;
    final age = DateTime.now().difference(capturedAt);
    return age.inMinutes > 5;
  }

  /// Calculate memory usage of thumbnail
  static double getThumbnailMemoryMB(Uint8List? thumbnail) {
    if (thumbnail == null) return 0;
    return thumbnail.length / (1024 * 1024);
  }
}
