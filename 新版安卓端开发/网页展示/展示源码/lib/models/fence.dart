import 'dart:convert';
import 'package:rolling_intelligence_headband/utils/summarizable.dart';

class Fence with Summarizable {
  int? alertCount;
  List<Coordinates>? coordinates;
  String? createBy;
  String? createTime;
  String? delFlag;
  String? fenceName;
  String? fenceShape;
  String? fenceType;
  String? id;
  String? lastAlarmTime;
  int? status;
  String? updateBy;
  String? updateTime;

  Fence({
    this.alertCount,
    this.coordinates,
    this.createBy,
    this.createTime,
    this.delFlag,
    this.fenceName,
    this.fenceShape,
    this.fenceType,
    this.id,
    this.lastAlarmTime,
    this.status,
    this.updateBy,
    this.updateTime,
  });

  Fence.fromJson(Map<String, dynamic> json) {
    if (json["alertCount"] is int) {
      alertCount = json["alertCount"];
    }
    if (json["coordinates"] is List) {
      coordinates = json["coordinates"] == null
          ? null
          : (json["coordinates"] as List)
                .map((e) => Coordinates.fromJson(e))
                .toList();
    }
    if (json["createBy"] is String) {
      createBy = json["createBy"];
    }
    if (json["createTime"] is String) {
      createTime = json["createTime"];
    }
    if (json["delFlag"] is String) {
      delFlag = json["delFlag"];
    }
    if (json["fenceName"] is String) {
      fenceName = json["fenceName"];
    }
    if (json["fenceShape"] is String) {
      fenceShape = json["fenceShape"];
    }
    if (json["fenceType"] is String) {
      fenceType = json["fenceType"];
    }
    // id 支持 int 和 String 类型
    if (json["id"] is int) {
      id = json["id"].toString();
    } else if (json["id"] is String) {
      id = json["id"];
    }
    if (json["lastAlarmTime"] is String) {
      lastAlarmTime = json["lastAlarmTime"];
    }
    if (json["status"] is int) {
      status = json["status"];
    }
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
  }

  static List<Fence> fromList(List<Map<String, dynamic>> list) {
    return list.map(Fence.fromJson).toList();
  }

  /// 围栏形状映射
  static const shapeMap = {
    'circle': '圆形',
    'polygon': '多边形',
    'rectangle': '矩形',
  };

  @override
  String toSummary() {
    final shapeText = shapeMap[fenceShape] ?? '围栏';
    final statusText = status == 1 ? '启用中' : '已作废';
    return '• [$id] $fenceName ($shapeText, $statusText, 告警${alertCount ?? 0}次)';
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["alertCount"] = alertCount;
    // if (coordinates != null) {
    //   data["coordinates"] = coordinates?.map((e) => e.toJson()).toList();
    // }
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    data["fenceName"] = fenceName;
    data["fenceShape"] = fenceShape;
    data["fenceType"] = fenceType;
    data["id"] = id;
    data["lastAlarmTime"] = lastAlarmTime;
    data["status"] = status;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}

class Coordinates {
  String? createBy;
  String? createTime;
  String? delFlag;
  String? fenceId;
  String? id;
  double? latitude;
  double? longitude;
  String? updateBy;
  String? updateTime;

  Coordinates({
    this.createBy,
    this.createTime,
    this.delFlag,
    this.fenceId,
    this.id,
    this.latitude,
    this.longitude,
    this.updateBy,
    this.updateTime,
  });

  Coordinates.fromJson(Map<String, dynamic> json) {
    if (json["createBy"] is String) {
      createBy = json["createBy"];
    }
    if (json["createTime"] is String) {
      createTime = json["createTime"];
    }
    // delFlag 支持 int 和 String
    if (json["delFlag"] is int) {
      delFlag = json["delFlag"].toString();
    } else if (json["delFlag"] is String) {
      delFlag = json["delFlag"];
    }
    // fenceId 支持 int 和 String
    if (json["fenceId"] is int) {
      fenceId = json["fenceId"].toString();
    } else if (json["fenceId"] is String) {
      fenceId = json["fenceId"];
    }
    // id 支持 int 和 String
    if (json["id"] is int) {
      id = json["id"].toString();
    } else if (json["id"] is String) {
      id = json["id"];
    }
    // latitude 支持 int 和 double
    if (json["latitude"] is int) {
      latitude = (json["latitude"] as int).toDouble();
    } else if (json["latitude"] is double) {
      latitude = json["latitude"];
    }
    // longitude 支持 int 和 double
    if (json["longitude"] is int) {
      longitude = (json["longitude"] as int).toDouble();
    } else if (json["longitude"] is double) {
      longitude = json["longitude"];
    }
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
  }

  static List<Coordinates> fromList(List<Map<String, dynamic>> list) {
    return list.map(Coordinates.fromJson).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    data["fenceId"] = fenceId;
    data["id"] = id;
    data["latitude"] = latitude;
    data["longitude"] = longitude;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    return data;
  }
}
