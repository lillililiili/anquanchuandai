import 'package:rolling_intelligence_headband/utils/summarizable.dart';

class Alarm with Summarizable {
  String? alarmEndTime;
  String? id;
  String? alarmLevel;
  String? alarmStartTime;
  String? alarmType;
  String? createBy;
  String? createTime;
  String? delFlag;
  String? description;
  String? handleTime;
  int? hatId;
  String? hatNumber;
  int? isHandled;
  String? updateBy;
  String? updateTime;
  int? userId;
  String? userName;
  double? longitude;
  double? latitude;

  Alarm({
    this.alarmEndTime,
    this.id,
    this.alarmLevel,
    this.alarmStartTime,
    this.alarmType,
    this.createBy,
    this.createTime,
    this.delFlag,
    this.description,
    this.handleTime,
    this.hatId,
    this.hatNumber,
    this.isHandled,
    this.updateBy,
    this.updateTime,
    this.userId,
    this.userName,
    this.longitude,
    this.latitude,
  });

  Alarm.fromJson(Map<String, dynamic> json) {
    if (json["alarmEndTime"] is String) {
      alarmEndTime = json["alarmEndTime"];
    }
    if (json["id"] != null) {
      id = json["id"].toString();
    }
    if (json["alarmLevel"] is String) {
      alarmLevel = json["alarmLevel"];
    }
    if (json["alarmStartTime"] is String) {
      alarmStartTime = json["alarmStartTime"];
    }
    if (json["alarmType"] is String) {
      alarmType = json["alarmType"];
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
    if (json["description"] is String) {
      description = json["description"];
    }
    if (json["handleTime"] is String) {
      handleTime = json["handleTime"];
    }
    hatId = int.tryParse(json["hatId"]?.toString() ?? "");
    if (json["hatNumber"] is String) {
      hatNumber = json["hatNumber"];
    }
    isHandled = int.tryParse(json["isHandled"]?.toString() ?? "");
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
    userId = int.tryParse(json["userId"]?.toString() ?? "");
    if (json["userName"] is String) {
      userName = json["userName"];
    }
    if (json["longitude"] is double) {
      longitude = json["longitude"];
    }
    if (json["latitude"] is double) {
      latitude = json["latitude"];
    }
  }

  static List<Alarm> fromList(List<Map<String, dynamic>> list) {
    return list.map(Alarm.fromJson).toList();
  }

  /// 告警类型映射
  static const alarmTypeMap = {
    'sos': 'SOS告警',
    'fall': '跌倒告警',
    'removal': '脱帽告警',
    'silent': '静止告警',
    'proximity': '近电告警',
  };

  /// 告警级别映射
  static const alarmLevelMap = {'0': '普通', '1': '紧急', '2': '严重'};

  @override
  String toSummary() {
    final type = alarmTypeMap[alarmType] ?? '未知告警';
    final level = alarmLevelMap[alarmLevel] ?? '普通';
    final status = isHandled == 1 ? '已处理' : '未处理';
    final time = alarmStartTime ?? '';
    final user = userName ?? '未知';
    return '• [$level]$type - $user($status) $time';
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["alarmEndTime"] = alarmEndTime;
    data["id"] = id;
    data["alarmLevel"] = alarmLevel;
    data["alarmStartTime"] = alarmStartTime;
    data["alarmType"] = alarmType;
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    data["description"] = description;
    data["handleTime"] = handleTime;
    data["hatId"] = hatId;
    data["hatNumber"] = hatNumber;
    data["isHandled"] = isHandled;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    data["userId"] = userId;
    data["userName"] = userName;
    data["longitude"] = longitude;
    data["latitude"] = latitude;
    return data;
  }
}
