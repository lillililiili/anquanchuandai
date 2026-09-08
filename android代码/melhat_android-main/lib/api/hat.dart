import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/hat.dart';
import 'package:rolling_intelligence_headband/models/hat_location_file_record.dart';
import 'package:rolling_intelligence_headband/models/hat_location_record.dart';

class HatApi {
  /// 安全帽分页列表
  static Future<DataPage<Hat>> getHatPage({
    int? current,
    int? size,
    String? bindGroup,
    String? bindUserName,
    String? hatNumber,
    String? status,
    String? startTime,
    String? endTime,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/safety/info/page',
        method: 'GET',
        params: {
          'current': current,
          'size': size,
          'bindGroup': bindGroup,
          'bindUserName': bindUserName,
          'hatNumber': hatNumber,
          'status': status,
          'startTime': startTime,
          'endTime': endTime,
        },
      ),
    );
    return DataPage.fromJson(response, Hat.fromJson);
  }

  /// 查询轨迹点
  static Future<List<HatLocationRecord>> queryHatLocationRecord({
    required List<String> hatIds,
    required String startTime,
    required String endTime,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/location/record/query',
        method: 'POST',
        data: {'hatIds': hatIds, 'startTime': startTime, 'endTime': endTime},
      ),
    );
    if (response is List) {
      return HatLocationRecord.fromList(
        (response).map((e) => e as Map<String, dynamic>).toList(),
      );
    }
    return [];
  }

  /// 获取单个设备的历史轨迹
  static Future<List<HatLocationRecord>> getSingleHatHistory({
    required String hatId,
    String? startTime,
    String? endTime,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/location/record/single/$hatId',
        method: 'GET',
        params: {'startTime': startTime, 'endTime': endTime},
      ),
    );
    if (response is List) {
      return HatLocationRecord.fromList(
        (response).map((e) => e as Map<String, dynamic>).toList(),
      );
    }
    return [];
  }

  /// 获取轨迹关联文件
  /// fileType文件类型：video:视频/audio:音频/ image:图片
  static Future<List<HatLocationFileRecord>> getRelatedFiles({
    required String hatNumber,
    String? startTime,
    String? endTime,
    String? fileType,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/location/record/relatedFiles',
        method: 'GET',
        params: {
          'hatNumber': hatNumber,
          'startTime': startTime,
          'endTime': endTime,
          'fileType': fileType,
        },
      ),
    );
    if (response is List) {
      return HatLocationFileRecord.fromList(
        response.cast<Map<String, dynamic>>().toList(),
      );
    }
    return [];
  }

  /// 根据userId获取绑定安全帽的信息
  static Future<Hat?> getHatByUserId(String userId) async {
    final response = await http.request(
      ReqOptions(path: '/hat/safety/info/user/$userId', method: 'GET'),
    );
    if (response != null) {
      return Hat.fromJson(response as Map<String, dynamic>);
    }
    return null;
  }

  /// 根据id获取安全帽详情
  static Future<Hat> getHatById(String id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/safety/info/$id', method: 'GET'),
    );
    return Hat.fromJson(response as Map<String, dynamic>);
  }

  /// 根据安全帽编号获取安全帽详情
  static Future<Hat> getHatByNumber(String hatNumber) async {
    final response = await http.request(
      ReqOptions(path: '/hat/safety/info/number/$hatNumber', method: 'GET'),
    );
    return Hat.fromJson(response as Map<String, dynamic>);
  }
}
