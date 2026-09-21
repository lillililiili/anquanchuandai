import 'dart:async';

import 'package:openai_dart/openai_dart.dart';

/// AI 服务异常类
/// 包含用户友好的错误信息和错误类型
class AIServiceException implements Exception {
  /// 错误类型
  final AIServiceErrorType type;

  /// 用户友好的错误信息
  final String message;

  /// 技术细节（用于日志）
  final String? details;

  /// 原始异常
  final dynamic originalError;

  const AIServiceException({
    required this.type,
    required this.message,
    this.details,
    this.originalError,
  });

  @override
  String toString() => 'AIServiceException(${type.name}): $message';
}

/// AI 服务错误类型枚举
enum AIServiceErrorType {
  /// 免费额度用完
  quotaExhausted,

  /// API Key 无效或过期
  invalidApiKey,

  /// 认证失败
  authenticationFailed,

  /// 请求频率超限
  rateLimited,

  /// 网络连接错误
  networkError,

  /// 请求超时
  timeout,

  /// 模型不存在或不可用
  modelNotFound,

  /// 请求内容被拒绝（内容安全）
  contentFiltered,

  /// 服务器内部错误
  serverError,

  /// 参数错误
  invalidRequest,

  /// 未知错误
  unknown,
}

/// 错误处理器 - 将原始异常转换为用户友好的 AIServiceException
class AIErrorHandler {
  /// 处理异常，返回 AIServiceException
  /// 优先通过异常类型判断，字符串匹配作为 fallback
  static AIServiceException handle(dynamic error) {
    // 优先：基于异常类型的精确匹配（openai_dart 包）
    if (error is PermissionDeniedException) {
      return AIServiceException(
        type: AIServiceErrorType.quotaExhausted,
        message: 'AI 服务额度已用完，请稍后再试或联系管理员充值',
        details: error.toString(),
        originalError: error,
      );
    }
    if (error is AuthenticationException) {
      return AIServiceException(
        type: AIServiceErrorType.invalidApiKey,
        message: 'API 配置错误，请联系管理员',
        details: error.toString(),
        originalError: error,
      );
    }
    if (error is RateLimitException) {
      return AIServiceException(
        type: AIServiceErrorType.rateLimited,
        message: '请求太频繁，请稍后再试',
        details: error.toString(),
        originalError: error,
      );
    }
    if (error is NotFoundException) {
      return AIServiceException(
        type: AIServiceErrorType.modelNotFound,
        message: 'AI 模型暂时不可用，请稍后再试',
        details: error.toString(),
        originalError: error,
      );
    }
    if (error is BadRequestException) {
      return AIServiceException(
        type: AIServiceErrorType.invalidRequest,
        message: '请求参数错误，请重试',
        details: error.toString(),
        originalError: error,
      );
    }
    if (error is InternalServerException) {
      return AIServiceException(
        type: AIServiceErrorType.serverError,
        message: 'AI 服务暂时不可用，请稍后再试',
        details: error.toString(),
        originalError: error,
      );
    }
    if (error is ConflictException) {
      return AIServiceException(
        type: AIServiceErrorType.serverError,
        message: 'AI 服务冲突，请稍后再试',
        details: error.toString(),
        originalError: error,
      );
    }
    if (error is UnprocessableEntityException) {
      return AIServiceException(
        type: AIServiceErrorType.contentFiltered,
        message: '内容被安全策略拦截，请换个话题试试',
        details: error.toString(),
        originalError: error,
      );
    }

    // 次优：基于 Dart/Flutter 异常类型
    if (error is TimeoutException) {
      return AIServiceException(
        type: AIServiceErrorType.timeout,
        message: '请求超时，请检查网络或稍后重试',
        details: error.toString(),
        originalError: error,
      );
    }

    // Fallback：字符串匹配（处理非类型化的异常）
    final errorStr = error.toString().toLowerCase();

    if (errorStr.contains('socketexception') ||
        errorStr.contains('connection') ||
        errorStr.contains('network') ||
        errorStr.contains('clientexception')) {
      return AIServiceException(
        type: AIServiceErrorType.networkError,
        message: '网络连接失败，请检查网络设置',
        details: error.toString(),
        originalError: error,
      );
    }

    if (errorStr.contains('timeout') || errorStr.contains('deadline exceeded')) {
      return AIServiceException(
        type: AIServiceErrorType.timeout,
        message: '请求超时，请检查网络或稍后重试',
        details: error.toString(),
        originalError: error,
      );
    }

    // 未知错误
    return AIServiceException(
      type: AIServiceErrorType.unknown,
      message: '出错了，请稍后重试',
      details: error.toString(),
      originalError: error,
    );
  }
}
