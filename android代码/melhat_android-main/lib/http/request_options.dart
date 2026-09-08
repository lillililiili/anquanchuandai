import 'package:dio/dio.dart';

/// 请求配置选项（类似 axios 的 AxiosRequestConfig）
class ReqOptions {
  /// 是否打印请求日志
  final bool? logEnabled;

  /// 是否打印响应日志
  final bool? responseLogEnabled;

  /// 自定义请求头
  final Map<String, dynamic>? headers;

  /// 请求超时时间（毫秒）
  final int? connectTimeout;

  /// 响应超时时间（毫秒）
  final int? receiveTimeout;

  /// 是否需要认证（默认需要）
  final bool? requiresAuth;

  final dynamic data;

  final dynamic params;

  final String? method;

  final String path;

  const ReqOptions({
    this.logEnabled,
    this.responseLogEnabled,
    this.headers,
    this.connectTimeout,
    this.receiveTimeout,
    this.requiresAuth = true,
    this.data,
    this.params,
    this.method,
    required this.path,
  });

  /// 转换为 Dio Options
  Options toDioOptions() {
    return Options(
      headers: headers,
      sendTimeout: connectTimeout != null
          ? Duration(milliseconds: connectTimeout!)
          : null,
      receiveTimeout: receiveTimeout != null
          ? Duration(milliseconds: receiveTimeout!)
          : null,
      connectTimeout: connectTimeout != null
          ? Duration(milliseconds: connectTimeout!)
          : null,
      extra: {
        'logEnabled': logEnabled ?? true,
        'responseLogEnabled': responseLogEnabled ?? true,
        'requiresAuth': requiresAuth ?? true,
      },
      method: method,
    );
  }
}
