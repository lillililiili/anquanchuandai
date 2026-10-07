import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/user.dart';

/// 响应数据结构（类似 axios 的 AxiosResponse）
class BaseResponse {
  final int code;
  final String msg;

  BaseResponse({required this.code, required this.msg});

  bool get isSuccess => code == 200;

  @override
  String toString() => 'BaseResponse(code: $code, msg: $msg)';
}

class LoginResponse extends BaseResponse {
  final String token;

  UserInfo? user;

  LoginResponse({
    required super.code,
    required super.msg,
    required this.token,
    this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      code: json['code'] as int,
      msg: json['msg'] as String,
      token: json['token'] ?? "",
      user: json['user'] != null ? UserInfo.fromJson(json['user']) : null,
    );
  }

  @override
  String toString() =>
      'LoginResponse(code: $code, msg: $msg, token: [redacted])';
}

class CommonResponse<T> extends BaseResponse {
  final T? data;

  CommonResponse({required super.code, required super.msg, this.data});

  factory CommonResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    return CommonResponse<T>(
      code: json['code'] as int,
      msg: json['msg'] as String,
      data: json['data'] != null
          ? fromJsonT(json['data'] as Map<String, dynamic>)
          : null,
    );
  }

  @override
  String toString() => 'CommonResponse(code: $code, msg: $msg, data: $data)';
}

class PageResponse<T> extends CommonResponse<DataPage<T>> {
  PageResponse({required super.code, required super.msg, super.data});

  factory PageResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    return PageResponse<T>(
      code: json['code'] as int,
      msg: json['msg'] as String,
      data: json['data'] != null
          ? DataPage.fromJson(json['data'], fromJsonT)
          : null,
    );
  }

  @override
  String toString() {
    return 'PageResponse(code: $code, msg: $msg, data: $data)';
  }
}

class BadResException implements Exception {
  final int code;
  final String msg;

  BadResException({required this.code, required this.msg});

  // 可以添加 message getter，让调用者通过 exception.message 访问
  String get message => '($code)$msg';

  @override
  String toString() => '错误码: $code, 原因: $msg';
}
