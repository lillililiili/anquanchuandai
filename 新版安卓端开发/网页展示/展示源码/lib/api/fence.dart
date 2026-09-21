import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/fence.dart';

class FenceApi {
  /// 电子围栏分页列表
  static Future<DataPage<Fence>> getFencePage({
    int? current,
    int? size,
    String? fenceName,
    String? fenceType,
    String? startTime,
    String? endTime,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/electronic/fence/page',
        method: 'GET',
        params: {
          'current': current,
          'size': size,
          'fenceName': fenceName,
          'fenceType': fenceType,
          'startTime': startTime,
          'endTime': endTime,
        },
      ),
    );
    return DataPage.fromJson(response, Fence.fromJson);
  }

  /// 保存电子围栏
  static Future<dynamic> saveFence(Fence fence) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/electronic/fence',
        method: 'POST',
        data: {
          'fence': fence.toJson(),
          'coordinates': fence.coordinates?.map((e) => e.toJson()).toList(),
        },
      ),
    );
    return response;
  }

  /// 修改电子围栏
  static Future<dynamic> updateFence(Fence fence) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/electronic/fence',
        method: 'PUT',
        data: {
          'fence': fence.toJson(),
          'coordinates': fence.coordinates?.map((e) => e.toJson()).toList(),
        },
      ),
    );
    return response;
  }

  /// 查询电子围栏详情
  static Future<Fence> getFenceById(String id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/electronic/fence/$id', method: 'GET'),
    );
    return Fence.fromJson(response);
  }

  /// 删除电子围栏
  static Future<dynamic> deleteFence(String id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/electronic/fence/$id', method: 'DELETE'),
    );
    return response;
  }
}
