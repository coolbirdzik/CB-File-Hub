import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cb_file_manager/ui/components/common/app_toast.dart';

/// Helper class for common video library operations
class VideoLibraryHelpers {
  /// Pick a directory using FilePicker
  static Future<String?> pickDirectory() async {
    try {
      return await FilePicker.platform.getDirectoryPath();
    } catch (e) {
      debugPrint('Error picking directory: $e');
      return null;
    }
  }

  /// Show a success toast message.
  static void showSuccessMessage(BuildContext context, String message) {
    AppToast.success(context, message);
  }

  /// Show an error toast message.
  static void showErrorMessage(BuildContext context, String message) {
    AppToast.error(context, message);
  }

  /// Parse color from hex string (e.g., "#FF0000" or "#FF0000FF")
  static Color? parseColorFromHex(String? hexString) {
    if (hexString == null || hexString.isEmpty) return null;

    try {
      // Remove # if present
      String hex = hexString.replaceFirst('#', '');

      // Handle both formats: RRGGBB and AARRGGBB
      if (hex.length == 6) {
        hex = 'FF$hex'; // Add alpha channel if missing
      }

      return Color(int.parse(hex, radix: 16));
    } catch (e) {
      debugPrint('Error parsing color: $e');
      return null;
    }
  }

  /// Get color from hex string with fallback
  static Color getColorFromHex(String? hexString, Color fallback) {
    return parseColorFromHex(hexString) ?? fallback;
  }
}
