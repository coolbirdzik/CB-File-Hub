import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// Centralized logging utility for the application.
///
/// Uses the `logger` package for pretty console output and `dart:developer`
/// for Flutter DevTools integration. Log level filtering is handled by the
/// `logger` package — adjust via [setLevel].
///
/// Usage:
/// ```dart
/// AppLogger.debug('Debug message');
/// AppLogger.info('Info message');
/// AppLogger.warning('Warning message');
/// AppLogger.error('Error message', error: e, stackTrace: st);
/// AppLogger.perf('Perf message') // performance logs (written to perf log file in debug)
/// ```
class AppLogger {
  static final List<String> _recentLogs = <String>[];

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
    ),
    level: Level.debug,
  );

  /// Log a debug message
  static void debug(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.d(message, error: error, stackTrace: stackTrace);
    _record('DEBUG', message, error: error, stackTrace: stackTrace, level: 500);
  }

  /// Log an info message
  static void info(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
    _record('INFO', message, error: error, stackTrace: stackTrace, level: 800);
  }

  /// Log a warning message
  static void warning(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _logger.w(message, error: error, stackTrace: stackTrace);
    _record('WARN', message, error: error, stackTrace: stackTrace, level: 900);
  }

  /// Log an error message
  static void error(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    _record(
      'ERROR',
      message,
      error: error,
      stackTrace: stackTrace,
      level: 1000,
    );
  }

  /// Log a fatal error message
  static void fatal(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.f(message, error: error, stackTrace: stackTrace);
    _record(
      'FATAL',
      message,
      error: error,
      stackTrace: stackTrace,
      level: 1200,
    );
  }

  /// Performance log helper — writes to logger and appends to a perf log file.
  /// Only writes to disk in non-release builds to avoid I/O in production.
  static void perf(String message) {
    _logger.d(message);
    _record('PERF', message, level: 800);

    // Append to a persistent perf log file in debug/profile for offline analysis
    if (!kReleaseMode) {
      _appendPerfLog(message);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Records the message to the in-memory buffer and emits to `dart:developer`
  /// for Flutter DevTools visibility.
  static void _record(
    String levelName,
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    required int level,
  }) {
    final buffer = StringBuffer()
      ..write('[$levelName] ')
      ..write(message);

    if (error != null) {
      buffer
        ..write(' | error=')
        ..write(error);
    }

    final text = buffer.toString();

    // In-memory circular buffer (last 200 entries)
    _recentLogs.add(text);
    if (_recentLogs.length > 200) {
      _recentLogs.removeRange(0, _recentLogs.length - 200);
    }

    // Emit to dart:developer (visible in DevTools Logging tab)
    try {
      developer.log(
        text,
        name: 'cb_file_manager',
        level: level,
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {}
  }

  static Future<void> _appendPerfLog(String message) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}cb_file_manager_perf.log',
      );
      final ts = DateTime.now().toIso8601String();
      await file.writeAsString(
        '[$ts] $message\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // ignore — logging must not crash the app
    }
  }

  // ---------------------------------------------------------------------------
  // Public accessors
  // ---------------------------------------------------------------------------

  static String get recentLogsText => _recentLogs.join('\n');

  static String get recentLogsTail {
    final start = _recentLogs.length > 40 ? _recentLogs.length - 40 : 0;
    return _recentLogs.sublist(start).join('\n');
  }

  /// Adjust the minimum log level at runtime.
  /// Example: `AppLogger.setLevel(Level.info)` to hide debug messages.
  static void setLevel(Level level) {
    Logger.level = level;
  }
}
