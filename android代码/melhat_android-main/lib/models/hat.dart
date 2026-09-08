import 'dart:convert';

class Hat {
  int? alarmCount;
  String? bindGroup;
  int? bindGroupId;
  String? bindTime;
  int? bindUserId;
  String? bindUserName;
  num? cpuUsage;
  String? createBy;
  String? createTime;
  String? delFlag;
  num? electricityUsage;
  String? electricityColor;
  String? hatNumber;
  String? id;
  String? rtcPlayConfig;
  String? status;
  num? storageUsage;
  String? updateBy;
  String? updateTime;
  String? videoUrl;
  String? latitude;
  String? longitude;

  Hat({
    this.alarmCount,
    this.bindGroup,
    this.bindGroupId,
    this.bindTime,
    this.bindUserId,
    this.bindUserName,
    this.cpuUsage,
    this.createBy,
    this.createTime,
    this.delFlag,
    this.electricityUsage,
    this.hatNumber,
    this.id,
    this.rtcPlayConfig,
    this.status,
    this.storageUsage,
    this.updateBy,
    this.updateTime,
    this.videoUrl,
    this.latitude,
    this.longitude,
  });

  Hat.fromJson(Map<String, dynamic> json) {
    if (json["alarmCount"] is int) {
      alarmCount = json["alarmCount"];
    }
    if (json["bindGroup"] is String) {
      bindGroup = json["bindGroup"];
    }
    bindGroupId = int.tryParse(json["bindGroupId"]?.toString() ?? "");
    if (json["bindTime"] is String) {
      bindTime = json["bindTime"];
    }
    bindUserId = int.tryParse(json["bindUserId"]?.toString() ?? "");
    if (json["bindUserName"] is String) {
      bindUserName = json["bindUserName"];
    }
    if (json["cpuUsage"] is num) {
      cpuUsage = json["cpuUsage"];
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
    if (json["electricityUsage"] is num) {
      electricityUsage = json["electricityUsage"];
    }
    if (json["hatNumber"] is String) {
      hatNumber = json["hatNumber"];
    }
    if (json["id"] != null) {
      id = json["id"].toString();
    }
    if (json["rtcPlayConfig"] is String) {
      rtcPlayConfig = json["rtcPlayConfig"];
    }
    if (json["status"] is String) {
      status = json["status"];
    }
    if (json["storageUsage"] is num) {
      storageUsage = json["storageUsage"];
    }
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
    if (json["videoUrl"] is String) {
      videoUrl = json["videoUrl"];
    }
    if (json["latitude"] is String) {
      latitude = json["latitude"];
    }
    if (json["longitude"] is String) {
      longitude = json["longitude"];
    }
  }

  static List<Hat> fromList(List<Map<String, dynamic>> list) {
    return list.map(Hat.fromJson).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["alarmCount"] = alarmCount;
    data["bindGroup"] = bindGroup;
    data["bindGroupId"] = bindGroupId;
    data["bindTime"] = bindTime;
    data["bindUserId"] = bindUserId;
    data["bindUserName"] = bindUserName;
    data["cpuUsage"] = cpuUsage;
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    data["electricityUsage"] = electricityUsage;
    data["hatNumber"] = hatNumber;
    data["id"] = id;
    data["rtcPlayConfig"] = rtcPlayConfig;
    data["status"] = status;
    data["storageUsage"] = storageUsage;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    data["videoUrl"] = videoUrl;
    data["latitude"] = latitude;
    data["longitude"] = longitude;
    return data;
  }

  @override
  String toString() {
    return jsonEncode(this.toJson());
  }
}
