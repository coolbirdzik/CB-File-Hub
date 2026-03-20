/// Base class for all failures in the application.
///
/// Failures represent errors that occur during business logic execution
/// and are used with the Either type for explicit error handling.
abstract class Failure {
  /// Human-readable error message
  final String message;

  /// Optional error code for categorization
  final String? code;

  /// Original error object if available
  final dynamic originalError;

  const Failure({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'Failure(message: $message, code: $code)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Failure && other.message == message && other.code == code;
  }

  @override
  int get hashCode => message.hashCode ^ code.hashCode;
}

/// Failure related to file system operations.
///
/// Examples: file not found, permission denied, disk full, etc.
class FileSystemFailure extends Failure {
  const FileSystemFailure({
    required String message,
    String? code,
    dynamic originalError,
  }) : super(
          message: message,
          code: code,
          originalError: originalError,
        );

  @override
  String toString() => 'FileSystemFailure(message: $message, code: $code)';
}

/// Failure related to network operations.
///
/// Examples: connection timeout, no internet, server error, etc.
class NetworkFailure extends Failure {
  const NetworkFailure({
    required String message,
    String? code,
    dynamic originalError,
  }) : super(
          message: message,
          code: code,
          originalError: originalError,
        );

  @override
  String toString() => 'NetworkFailure(message: $message, code: $code)';
}

/// Failure related to database operations.
///
/// Examples: query failed, connection error, data corruption, etc.
class DatabaseFailure extends Failure {
  const DatabaseFailure({
    required String message,
    String? code,
    dynamic originalError,
  }) : super(
          message: message,
          code: code,
          originalError: originalError,
        );

  @override
  String toString() => 'DatabaseFailure(message: $message, code: $code)';
}

/// Failure related to permission issues.
///
/// Examples: storage permission denied, camera permission denied, etc.
class PermissionFailure extends Failure {
  const PermissionFailure({
    required String message,
    String? code,
    dynamic originalError,
  }) : super(
          message: message,
          code: code,
          originalError: originalError,
        );

  @override
  String toString() => 'PermissionFailure(message: $message, code: $code)';
}
