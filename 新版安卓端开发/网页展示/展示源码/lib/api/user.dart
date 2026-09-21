import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/http/response/response.dart';
import 'package:rolling_intelligence_headband/models/app_statistics.dart';

class UserApi {
  /// 用户登录
  static Future<LoginResponse> login(String username, String password) async {
    final response = await http.loginRequest(
      ReqOptions(
        path: '/login',
        method: 'POST',
        data: {'username': username, 'password': password},
      ),
    );
    return response;
  }

  static Future<LoginResponse> getUserProfile() async {
    final response = await http.loginRequest(
      ReqOptions(path: '/getInfo', method: 'GET'),
    );
    return response;
  }

  /// 获取 APP 数据统计信息
  static Future<AppStatistics> getAppStatistics() async {
    final response = await http.request(
      ReqOptions(path: '/hat/data/statistics/app/query', method: 'GET'),
    );
    return AppStatistics.fromJson(response);
  }
}
