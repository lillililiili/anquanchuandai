import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/alarm.dart';

class AlarmApi {
  static Future<DataPage<Alarm>> getAlarmPage({
    int? current,
    int? size,
    String? alarmType,
    int? isHandled,
    String? startTimeFrom,
    String? startTimeTo,
    String? userName,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/alarm/page',
        method: 'GET',
        logEnabled: false,
        params: {
          'current': current,
          'size': size,
          'alarmType': alarmType,
          'isHandled': isHandled,
          'startTimeFrom': startTimeFrom,
          'startTimeTo': startTimeTo,
          'userName': userName,
        },
      ),
    );
    return DataPage.fromJson(response, Alarm.fromJson);
  }

  static Future<void> answer(String id) async {
    await http.request(
      ReqOptions(path: '/hat/alarm/answer/$id', method: 'PUT'),
    );
  }

  static Future<void> handle(Alarm alarm) async {
    await http.request(
      ReqOptions(
        path: '/hat/alarm/handle',
        method: 'PUT',
        data: alarm.toJson(),
      ),
    );
  }

  static Future<void> receive(Alarm alarm) async {
    await http.request(
      ReqOptions(
        path: '/hat/alarm/receive',
        method: 'POST',
        data: alarm.toJson(),
      ),
    );
  }

  static Future<Map<String, dynamic>> getUnhandledCount() async {
    final response = await http.request(
      ReqOptions(path: '/hat/alarm/unhandled-count', method: 'GET'),
    );
    return response as Map<String, dynamic>;
  }

  static Future<Alarm> getById(String id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/alarm/$id', method: 'GET'),
    );
    return Alarm.fromJson(response as Map<String, dynamic>);
  }

  static Future<void> delete(int id) async {
    await http.request(ReqOptions(path: '/hat/alarm/$id', method: 'DELETE'));
  }
}
