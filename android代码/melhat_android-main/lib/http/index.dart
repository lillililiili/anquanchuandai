import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/http/response/response.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:rolling_intelligence_headband/store/user_store.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';

/// HTTP 客户端封装（类似前端 axios 封装）
class Http {
  /// 单例实例
  static final Http instance = Http._internal();

  /// Dio 实例
  late final Dio _dio;

  /// 私有构造函数
  Http._internal() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Content-Type': 'application/json'},
        baseUrl: const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://10.0.2.2:18084',
        ),
        // baseUrl: 'http://182.37.81.234:28884',
      ),
    );

    // 添加拦截器
    _dio.interceptors.add(_httpInterceptor());

    dio.interceptors.add(
      PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseBody: true,
        responseHeader: false,
        error: true,
        compact: true,
        maxWidth: 90,
        filter: (options, args) {
          final logEnabled = options.extra['logEnabled'] as bool? ?? false;
          // don't print responses with unit8 list data
          return logEnabled || !args.isResponse || !args.hasUint8ListData;
        },
      ),
    );
  }

  /// 工厂构造函数 - 返回单例
  factory Http() => instance;

  /// 获取 dio 实例
  Dio get dio => _dio;

  /// 设置通用请求头
  void setHeader(String key, String value) {
    _dio.options.headers[key] = value;
  }

  /// 移除通用请求头
  void removeHeader(String key) {
    _dio.options.headers.remove(key);
  }

  /// 清除所有拦截器
  void clearInterceptors() {
    _dio.interceptors.clear();
  }

  /// 添加拦截器
  void addInterceptor(Interceptor interceptor) {
    _dio.interceptors.add(interceptor);
  }

  /// HTTP 拦截器
  Interceptor _httpInterceptor() {
    return InterceptorsWrapper(
      /// 请求拦截器
      onRequest:
          (RequestOptions options, RequestInterceptorHandler handler) async {
            // 从 UserStore 获取 Token
            final token = UserStore.instance.token;

            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }

            handler.next(options);
          },

      /// 响应拦截器 - 错误
      onError: (DioException error, ErrorInterceptorHandler handler) async {
        // 统一错误处理
        final errorMessage = _handleError(error);

        // TODO: 可以在这里添加统一错误处理逻辑
        // 例如：401 未授权 -> 跳转登录页
        // if (error.response?.statusCode == 401) {
        //   _handleUnauthorized();
        // }

        handler.next(
          DioException(
            requestOptions: error.requestOptions,
            response: error.response,
            type: error.type,
            error: error.error,
            message: errorMessage,
          ),
        );
      },
    );
  }

  /// 处理 Dio 错误
  String _handleError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return '网络连接超时，请检查网络设置';
      case DioExceptionType.sendTimeout:
        return '发送数据超时，请重试';
      case DioExceptionType.receiveTimeout:
        return '接收数据超时，请重试';
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 0;
        return _handleStatusCode(statusCode);
      case DioExceptionType.cancel:
        return '请求已取消';
      case DioExceptionType.connectionError:
        return '网络连接失败，请检查网络';
      case DioExceptionType.badCertificate:
        return '证书验证失败';
      case DioExceptionType.unknown:
        return '网络请求失败，请稍后重试';
    }
  }

  /// 处理 HTTP 状态码
  String _handleStatusCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return '请求参数错误';
      case 401:
        return '未授权，请重新登录';
      case 403:
        return '拒绝访问';
      case 404:
        return '请求资源不存在';
      case 405:
        return '请求方法不允许';
      case 408:
        return '请求超时';
      case 413:
        return '请求体过大';
      case 414:
        return '请求 URI 过长';
      case 422:
        return '请求参数验证失败';
      case 500:
        return '服务器内部错误';
      case 502:
        return '网关错误';
      case 503:
        return '服务不可用';
      case 504:
        return '网关超时';
      default:
        return '请求失败 (状态码：$statusCode)';
    }
  }

  Future<dynamic> request(ReqOptions options) async {
    final mergedOptions = options.toDioOptions();

    try {
      final response = await _dio.request(
        options.path,
        data: options.data,
        queryParameters: options.params,
        options: mergedOptions,
      );

      final map = response.data as Map<String, dynamic>;
      final code = map['code'] as int;
      final msg = map['msg'] as String;
      final data = map['data'];

      if (code == 200) {
        return data;
      }

      if (code == 401) {
        // 401 错误 - 可能是 Token 无效或过期
        // 在下一帧执行登出，避免在请求过程中直接操作状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          UserStore.instance.logout();
        });
        // 或者发送一个全局事件通知其他组件
      }

      throw BadResException(code: code, msg: msg);
    } on DioException catch (e, stackTrace) {
      AppLogger.e('DioException', e, stackTrace);
      if (e.response?.statusCode == 401) {
        // 在下一帧执行登出，避免在请求过程中直接操作状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          UserStore.instance.logout();
        });
      }
      rethrow;
    } catch (e, stackTrace) {
      AppLogger.e('Exception', e, stackTrace);
      rethrow;
    }
  }

  Future<LoginResponse> loginRequest(ReqOptions options) async {
    final mergedOptions = options.toDioOptions();

    try {
      final response = await _dio.request(
        options.path,
        data: options.data,
        queryParameters: options.params,
        options: mergedOptions,
      );

      return LoginResponse.fromJson(response.data);
    } on DioException catch (e, stackTrace) {
      AppLogger.e('DioException', e, stackTrace);
      return LoginResponse(
        code: e.response?.statusCode ?? 500,
        msg: e.message ?? '服务器内部错误，请稍后重试',
        token: "",
      );
    } catch (e, stackTrace) {
      AppLogger.e('Exception', e, stackTrace);
      return LoginResponse(code: 500, msg: e.toString(), token: "");
    }
  }
}

/// 全局便捷的 http 实例
final http = Http.instance;
