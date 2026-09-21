import 'package:dio/dio.dart';
import '../config/backend_config.dart';
import 'data.dart';

class WearApiException implements Exception {
  final int code;
  final String message;
  const WearApiException(this.code, this.message);
  @override
  String toString() => message;
}

class StaleSessionException extends WearApiException {
  const StaleSessionException() : super(-1, '会话或厂站已变化');
}

/// The request captures the identity and site; late responses never enter a new session.
class WearApi {
  final Dio dio;
  final String? Function() token;
  final String? Function() siteId;
  final int Function() epoch;
  final void Function()? onUnauthorized;
  CancelToken _cancel = CancelToken();
  WearApi({
    Dio? dio,
    required this.token,
    required this.siteId,
    required this.epoch,
    this.onUnauthorized,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: BackendConfig.baseUrl,
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 20),
               contentType: Headers.jsonContentType,
             ),
           );

  void invalidate() {
    _cancel.cancel('session changed');
    _cancel = CancelToken();
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      request('GET', path, query: query);
  Future<dynamic> post(String path, {Object? data}) =>
      request('POST', path, data: data);
  Future<dynamic> put(String path, {Object? data}) =>
      request('PUT', path, data: data);
  Future<dynamic> delete(String path) => request('DELETE', path);
  Future<WearPage> page(
    String path, {
    Map<String, dynamic>? query,
    int current = 1,
    int size = 20,
  }) async => WearPage.fromJson(
    await get(path, query: {'current': current, 'size': size, ...?query}),
  );

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? data,
    bool raw = false,
  }) async {
    final requestEpoch = epoch();
    final headers = <String, dynamic>{};
    final accessToken = token();
    if (path != '/login' && accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    final station = siteId();
    if (station != null &&
        path.startsWith('/api/v1/') &&
        !const [
          '/api/v1/me',
          '/api/v1/sites',
          '/api/v1/me/current-site',
        ].contains(path)) {
      headers['X-Site-Id'] = station;
    }
    try {
      final response = await dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        cancelToken: _cancel,
        options: Options(
          method: method,
          headers: headers,
          validateStatus: (_) => true,
        ),
      );
      if (requestEpoch != epoch()) throw const StaleSessionException();
      final body = jsonMap(response.data);
      final code = intOf(body['code'], response.statusCode ?? 0);
      if (code != 200 || (response.statusCode ?? 500) >= 400) {
        final effectiveCode = (response.statusCode ?? 0) >= 400
            ? response.statusCode!
            : code;
        if (effectiveCode == 401 && path != '/login') onUnauthorized?.call();
        throw WearApiException(
          effectiveCode,
          _safeMessage(body['msg'], effectiveCode),
        );
      }
      if (response.data is! Map) {
        throw const WearApiException(502, '服务响应格式不正确，请稍后重试');
      }
      return raw ? body : body['data'];
    } on DioException catch (error) {
      if (requestEpoch != epoch() || error.type == DioExceptionType.cancel) {
        throw const StaleSessionException();
      }
      throw WearApiException(0, switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout => '网络超时，请检查连接后重试',
        DioExceptionType.badCertificate => '连接证书校验失败，请联系管理员',
        _ => '无法连接服务，请检查网络后重试',
      });
    }
  }

  static String _safeMessage(Object? value, int code) {
    final message = value?.toString() ?? '';
    if (message.isNotEmpty &&
        message.length < 180 &&
        !RegExp(
          r'Exception|SELECT |INSERT |UPDATE |Bearer |password|token|jdbc:',
          caseSensitive: false,
        ).hasMatch(message)) {
      return message;
    }
    return switch (code) {
      401 => '登录已过期，请重新登录',
      403 => '没有权限执行该操作',
      404 => '记录或接口不存在，请刷新后重试',
      409 => '当前状态已变化，请刷新后重试',
      _ => '操作未完成，请稍后重试',
    };
  }
}
