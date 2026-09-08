import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/tts_broadcast_record.dart';

/// TTS 广播 API
class TtsBroadcastApi {
  /// 创建群播
  /// 接口地址: POST /dev-api/hat/tts/broadcast/group-broadcast
  static Future<void> createGroupBroadcast({
    String? content,
    String? groupId,
    String? hatNumber,
    String? participant,
  }) async {
    await http.request(
      ReqOptions(
        path: '/hat/tts/broadcast/group-broadcast',
        method: 'POST',
        data: {
          'content': content,
          'groupId': groupId,
          'hatNumber': hatNumber,
          'participant': participant,
        },
      ),
    );
  }

  /// 创建单播
  /// 接口地址: POST /dev-api/hat/tts/broadcast/single-broadcast
  static Future<void> createSingleBroadcast({
    String? content,
    String? groupId,
    String? hatNumber,
    String? participant,
  }) async {
    await http.request(
      ReqOptions(
        path: '/hat/tts/broadcast/single-broadcast',
        method: 'POST',
        data: {
          'content': content,
          'groupId': groupId,
          'hatNumber': hatNumber,
          'participant': participant,
        },
      ),
    );
  }

  /// 创建组播
  /// 接口地址: POST /dev-api/hat/tts/broadcast/team-broadcast
  static Future<void> createTeamBroadcast({
    String? content,
    String? groupId,
    String? hatNumber,
    String? participant,
  }) async {
    await http.request(
      ReqOptions(
        path: '/hat/tts/broadcast/team-broadcast',
        method: 'POST',
        data: {
          'content': content,
          'groupId': groupId,
          'hatNumber': hatNumber,
          'participant': participant,
        },
      ),
    );
  }

  /// 分页查询广播记录
  /// 接口地址: GET /dev-api/hat/tts/broadcast/page
  ///
  /// [broadcastType] 广播类型: 01单播/02群播/03组播
  /// [current] 当前页码
  /// [size] 每页大小
  /// [sendTimeFrom] 发送时间起始
  /// [sendTimeTo] 发送时间结束
  static Future<DataPage<TtsBroadcastRecord>> getBroadcastPage({
    String? broadcastType,
    int current = 1,
    int size = 10,
    String? sendTimeFrom,
    String? sendTimeTo,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/tts/broadcast/page',
        method: 'GET',
        params: {
          if (broadcastType != null) 'broadcastType': broadcastType,
          'current': current,
          'size': size,
          if (sendTimeFrom != null) 'sendTimeFrom': sendTimeFrom,
          if (sendTimeTo != null) 'sendTimeTo': sendTimeTo,
        },
      ),
    );

    return DataPage<TtsBroadcastRecord>.fromJson(
      response as Map<String, dynamic>,
      (json) => TtsBroadcastRecord.fromJson(json),
    );
  }

  /// 根据ID获取广播记录详情
  /// 接口地址: GET /dev-api/hat/tts/broadcast/{id}
  ///
  /// [id] 记录id
  static Future<TtsBroadcastRecord> getBroadcastById(int id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/tts/broadcast/$id', method: 'GET'),
    );
    return TtsBroadcastRecord.fromJson(response);
  }

  /// 逻辑删除广播记录
  /// 接口地址: DELETE /dev-api/hat/tts/broadcast/{id}
  ///
  /// [id] 记录id
  static Future<dynamic> deleteBroadcast(int id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/tts/broadcast/$id', method: 'DELETE'),
    );
    return response;
  }
}
