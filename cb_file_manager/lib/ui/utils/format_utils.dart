import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Utility class for formatting common data types like file sizes and dates
class FormatUtils {
  /// Formats file size in bytes to human-readable format
  ///
  /// Examples:
  /// - 512 -> "512 B"
  /// - 1024 -> "1.0 KB"
  /// - 1048576 -> "1.0 MB"
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  /// Formats DateTime to user-friendly relative or absolute format
  ///
  /// Examples:
  /// - Today: "Today 14:30"
  /// - Yesterday: "Yesterday 09:15"
  /// - Within week: "3 days ago"
  /// - Older: "Dec 25, 2025"
  ///
  /// Note: This returns English strings. Use formatDateLocalized for i18n support.
  static String formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Today ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Formats DateTime to user-friendly relative or absolute format with localization
  ///
  /// Uses DateFormat from intl package for proper localization support.
  /// Falls back to default locale if context is not available.
  ///
  /// Requires BuildContext to access localized date formatting
  static String formatDateLocalized(DateTime date, BuildContext context) {
    final now = DateTime.now();
    final difference = now.difference(date);

    // Get locale from context
    final locale = Localizations.localeOf(context);

    if (difference.inDays == 0) {
      // Today - use localized "Today" if available in AppLocalizations
      final timeStr = DateFormat.Hm(locale.toString()).format(date);
      // TODO: Add 'today' key to AppLocalizations
      return 'Today $timeStr'; // Fallback to English for now
    } else if (difference.inDays == 1) {
      // Yesterday
      final timeStr = DateFormat.Hm(locale.toString()).format(date);
      // TODO: Add 'yesterday' key to AppLocalizations
      return 'Yesterday $timeStr'; // Fallback to English for now
    } else if (difference.inDays < 7) {
      // X days ago
      // TODO: Add 'daysAgo' method to AppLocalizations
      return '${difference.inDays} days ago'; // Fallback to English for now
    } else {
      // Absolute date using locale
      return DateFormat.yMd(locale.toString()).format(date);
    }
  }

  /// Formats DateTime with time for more detailed display
  /// Uses today/yesterday detection
  static String formatDateWithTime(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(date.year, date.month, date.day);

    if (dateToCheck == today) {
      return 'Today, ${DateFormat.jm().format(date)}';
    } else if (dateToCheck == yesterday) {
      return 'Yesterday, ${DateFormat.jm().format(date)}';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  /// Formats file size with exact byte calculation (no rounding for small files)
  static String formatFileSizeExact(int size) {
    if (size < 1024) {
      return '$size B';
    } else if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    } else if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }
}
