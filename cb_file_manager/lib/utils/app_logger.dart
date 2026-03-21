import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// Centralized logging utility for the application.
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
      methodCount: 2,
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
    _emitToConsole(
      'DEBUG',
      message,
      error: error,
      stackTrace: stackTrace,
      level: 500,
    );
  }

  /// Log an info message
  static void info(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.i(message, error: error, stackTrace: stackTrace);
    _emitToConsole(
      'INFO',
      message,
      error: error,
      stackTrace: stackTrace,
      level: 800,
    );
  }

  /// Log a warning message
  static void warning(dynamic message,
      {Object? error, StackTrace? stackTrace}) {
    _logger.w(message, error: error, stackTrace: stackTrace);
    _emitToConsole(
      'WARN',
      message,
      error: error,
      stackTrace: stackTrace,
      level: 900,
    );
  }

  /// Log an error message
  static void error(dynamic message, {Object? error, StackTrace? stackTrace}) {
    _logger.e(message, error: error, stackTrace: stackTrace);
    _emitToConsole(
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
    _emitToConsole(
      'FATAL',
      message,
      error: error,
      stackTrace: stackTrace,
      level: 1200,
    );
  }

  /// Performance log helper — writes to logger and appends to a perf log file
  /// Only writes to disk in non-release builds to avoid I/O in production.
  static void perf(String message) {
    // Always emit to the in-memory logger
    _logger.d(message);

    // Also emit via dart:developer so Flutter DevTools Logging definitely captures it
    try {
      developer.log(message, name: 'cb_file_manager.perf', level: 800);
    } catch (_) {}

    // Ensure it also appears in the stdout/terminal
    try {
      debugPrint(message);
    } catch (_) {}

    // Append to a persistent perf log file in debug/profile for offline analysis
    if (!kReleaseMode) {
      _appendPerfLog(message); // fire-and-forget
    }
  }

  static Future<void> _appendPerfLog(String message) async {
    try {
      final dir = await getTemporaryDirectory();
      final file =
          File('${dir.path}${Platform.pathSeparator}cb_file_manager_perf.log');
      final ts = DateTime.now().toIso8601String();
      await file.writeAsString('[$ts] $message\n',
          mode: FileMode.append, flush: true);
    } catch (_) {
      // ignore — logging must not crash the app
    }
  }

  static void _emitToConsole(
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
    _recentLogs.add(text);
    if (_recentLogs.length > 200) {
      _recentLogs.removeRange(0, _recentLogs.length - 200);
    }

    try {
      developer.log(
        text,
        name: 'cb_file_manager',
        level: level,
        error: error,
        stackTrace: stackTrace,
      );
    } catch (_) {}

    try {
      debugPrint(text);
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }
    } catch (_) {}

    try {
      print(text);
      if (stackTrace != null) {
        print(stackTrace.toString());
      }
    } catch (_) {}
  }

  static String get recentLogsText => _recentLogs.join('\n');

  static String get recentLogsTail {
    final start = _recentLogs.length > 40 ? _recentLogs.length - 40 : 0;
    return _recentLogs.sublist(start).join('\n');
  }

  /// Set the log level
  static void setLevel(Level level) {
    Logger.level = level;
  }
}
