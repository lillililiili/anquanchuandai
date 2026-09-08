import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/http/request_options.dart';
import 'package:rolling_intelligence_headband/hooks/use_dict.dart';
import 'package:rolling_intelligence_headband/http/response/page.dart';
import 'package:rolling_intelligence_headband/models/dept.dart';
import 'package:rolling_intelligence_headband/models/user.dart';

class SystemApi {
  /// 根据字典类型查询字典数据信息
  static Future<List<DictItem>> getDictByType(String dictType) async {
    final response = await http.request(
      ReqOptions(path: '/system/dict/data/type/$dictType', method: 'GET'),
    );

    if (response is List) {
      return response
          .map((e) => DictItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  /// 用户分页列表
  static Future<DataPage<UserInfo>> getUserList({
    int? current,
    int? size,
    String? nickName,
    String? deptName,
  }) async {
    final response = await http.request(
      ReqOptions(
        path: '/system/user/app/user/list',
        method: 'GET',
        params: {
          'current': current,
          'size': size,
          'nickName': nickName,
          'deptName': deptName,
        },
      ),
    );
    return DataPage.fromJson(response, UserInfo.fromJson);
  }

  static Future<List<DeptTree>> getDeptTree() async {
    final response = await http.request(
      ReqOptions(path: '/system/user/deptTree', method: 'GET'),
    );

    if (response is List) {
      return response
          .cast<Map<String, dynamic>>()
          .map((e) => DeptTree.fromJson(e))
          .toList();
    }

    return [];
  }
}
