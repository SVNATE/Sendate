import 'package:flutter/foundation.dart';

/// Lightweight logger for Sendate services.
/// Provides structured logging with service context.
class AppLogger {
  final String _tag;

  const AppLogger(this._tag);

  void debug(String message) {
    if (kDebugMode) {
      debugPrint('[$_tag] $message');
    }
  }

  void info(String message) {
    debugPrint('[$_tag] ℹ️ $message');
  }

  void warn(String message) {
    debugPrint('[$_tag] ⚠️ $message');
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('[$_tag] ❌ $message');
    if (error != null) debugPrint('[$_tag]    Error: $error');
    if (stackTrace != null && kDebugMode) {
      debugPrint('[$_tag]    Stack: $stackTrace');
    }
  }
}
