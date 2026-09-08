import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/agora_credentials.dart';
import 'package:rolling_intelligence_headband/models/intercom_record.dart';

class IntercomApi {
  /// 创建单呼
  ///
  /// 接口地址: /dev-api/hat/intercom/record/single-call
  /// 请求方式: POST
  ///
  /// [enableRecodring] 是否开启录制: true/false
  /// [groupId] 组呼用:组id
  /// [hatNumber] 单呼/群呼传：帽子编号，多个用,分割
  /// [participant] 参与人员：单呼/群呼为安全帽绑定人员的名字、多个时用,分割; 组呼时不用传
  static Future<dynamic> singleCall({
    bool? enableRecodring,
    String? groupId,
    String? hatNumber,
    String? participant,
    String? clientId,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/intercom/record/single-call',
        method: 'POST',
        data: {
          'enableRecodring': enableRecodring,
          'groupId': groupId,
          'hatNumber': hatNumber,
          'participant': participant,
          'clientId': clientId,
        },
      ),
    );
    return AgoraCredentials.fromJson(response);
  }

  /// 创建群呼
  ///
  /// 接口地址: /dev-api/hat/intercom/record/group-call
  /// 请求方式: POST
  ///
  /// [enableRecodring] 是否开启录制: true/false
  /// [groupId] 组呼用:组id
  /// [hatNumber] 单呼/群呼传：帽子编号，多个用,分割
  /// [participant] 参与人员：单呼/群呼为安全帽绑定人员的名字、多个时用,分割; 组呼时不用传
  static Future<dynamic> groupCall({
    bool? enableRecodring,
    String? groupId,
    String? hatNumber,
    String? participant,
    String? clientId,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/intercom/record/group-call',
        method: 'POST',
        data: {
          'clientId': clientId,
          'enableRecodring': enableRecodring,
          'groupId': groupId,
          'hatNumber': hatNumber,
          'participant': participant,
        },
      ),
    );
    return AgoraCredentials.fromJson(response);
  }

  /// 创建组呼
  ///
  /// 接口地址: /dev-api/hat/intercom/record/team-call
  /// 请求方式: POST
  ///
  /// [enableRecodring] 是否开启录制: true/false
  /// [groupId] 组呼用:组id（必填）
  /// [hatNumber] 单呼/群呼传：帽子编号，多个用,分割
  /// [participant] 参与人员：单呼/群呼为为安全帽绑定人员的名字、多个时用,分割; 组呼时不用传
  static Future<dynamic> teamCall({
    bool? enableRecodring,
    String? groupId,
    String? hatNumber,
    String? participant,
    String? clientId,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/intercom/record/team-call',
        method: 'POST',
        data: {
          'enableRecodring': enableRecodring,
          'groupId': groupId,
          'hatNumber': hatNumber,
          'participant': participant,
          'clientId': clientId,
        },
      ),
    );
    return AgoraCredentials.fromJson(response);
  }

  /// 对讲记录列表（分页）
  ///
  /// 接口地址: /dev-api/hat/intercom/record/page
  /// 请求方式: GET
  ///
  /// [current] 当前页
  /// [size] 每页大小
  /// [intercomType] 对讲类型：01单呼/02群呼/03组呼
  /// [startTimeFrom] 开始时间起
  /// [startTimeTo] 开始时间止
  static Future<DataPage<IntercomRecord>> getRecordPage({
    int? current,
    int? size,
    String? intercomType,
    String? startTimeFrom,
    String? startTimeTo,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/intercom/record/page',
        method: 'GET',
        params: {
          'current': current,
          'size': size,
          'intercomType': intercomType,
          'startTimeFrom': startTimeFrom,
          'startTimeTo': startTimeTo,
        },
      ),
    );
    return DataPage.fromJson(response, IntercomRecord.fromJson);
  }

  /// 根据ID获取对讲记录详情
  ///
  /// 接口地址: /dev-api/hat/intercom/record/{id}
  /// 请求方式: GET
  ///
  /// [id] 记录id
  static Future<IntercomRecord> getRecordById(int id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/intercom/record/$id', method: 'GET'),
    );
    return IntercomRecord.fromJson(response);
  }

  /// 逻辑删除对讲记录
  ///
  /// 接口地址: /dev-api/hat/intercom/record/{id}
  /// 请求方式: DELETE
  ///
  /// [id] 记录id
  static Future<dynamic> deleteRecord(int id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/intercom/record/$id', method: 'DELETE'),
    );
    return response;
  }
}
