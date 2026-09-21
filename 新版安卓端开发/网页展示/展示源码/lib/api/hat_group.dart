import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/hat_group.dart';

class HatGroupApi {
  /// 获取分组信息分页列表
  static Future<DataPage<HatGroup>> getGroupPage({
    int? current,
    int? size,
    String? groupName,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/hat/group/info',
        method: 'GET',
        params: {'current': current, 'size': size, 'groupName': groupName},
      ),
    );
    return DataPage.fromJson(response, HatGroup.fromJson);
  }

  /// 根据id查询分组详情
  static Future<HatGroup?> getGroupById(int id) async {
    final response = await http.request(
      ReqOptions(path: '/hat/group/info/$id', method: 'GET'),
    );
    if (response != null) {
      return HatGroup.fromJson(response as Map<String, dynamic>);
    }
    return null;
  }
}
