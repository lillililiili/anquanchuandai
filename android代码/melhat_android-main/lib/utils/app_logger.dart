import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

/// 全局日志单例
///
/// 使用示例:
/// ```dart
/// AppLogger.d('debug message');
/// AppLogger.i('info message');
/// AppLogger.w('warning message');
/// AppLogger.e('error message', error: e, stackTrace: stackTrace);
/// ```
class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 2,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  /// 仅在调试模式打印
  static bool _isDebug = kDebugMode;

  /// 设置是否启用日志
  static void setEnabled(bool enabled) {
    _isDebug = enabled;
  }

  /// Debug级别日志
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.d(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Info级别日志
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.i(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Warning级别日志
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.w(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Error级别日志
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.e(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Fatal级别日志
  static void f(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.f(message, error: error, stackTrace: stackTrace);
    }
  }

  /// Trace级别日志
  static void t(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    if (_isDebug) {
      _logger.t(message, error: error, stackTrace: stackTrace);
    }
  }

  /// 关闭Logger
  static void close() {
    _logger.close();
  }
}
