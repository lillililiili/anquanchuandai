import 'package:rolling_intelligence_headband/models/hat.dart';

class HatLocationRecord {
  String? altitude;
  String? createBy;
  String? createTime;
  int? delFlag;
  Hat? deviceInfo;
  int? hatId;
  String? hatNumber;
  int? id;
  String? lat;
  String? lng;
  String? relatedVideoUrl;
  String? speed;
  String? timestamp;
  String? updateBy;
  String? updateTime;
  int? userId;
  String? userName;

  HatLocationRecord({
    this.altitude,
    this.createBy,
    this.createTime,
    this.delFlag,
    this.deviceInfo,
    this.hatId,
    this.hatNumber,
    this.id,
    this.lat,
    this.lng,
    this.relatedVideoUrl,
    this.speed,
    this.timestamp,
    this.updateBy,
    this.updateTime,
    this.userId,
    this.userName,
  });

  HatLocationRecord.fromJson(Map<String, dynamic> json) {
    if (json["altitude"] is String) {
      altitude = json["altitude"];
    }
    if (json["createBy"] is String) {
      createBy = json["createBy"];
    }
    if (json["createTime"] is String) {
      createTime = json["createTime"];
    }
    if (json["delFlag"] is int) {
      delFlag = json["delFlag"];
    }
    if (json["deviceInfo"] != null) {
      deviceInfo = Hat.fromJson(json["deviceInfo"]);
    }
    if (json["hatId"] is int) {
      hatId = json["hatId"];
    }
    if (json["hatNumber"] is String) {
      hatNumber = json["hatNumber"];
    }
    // id 支持 int 和 String 类型
    if (json["id"] is int) {
      id = json["id"];
    } else if (json["id"] is String) {
      id = int.tryParse(json["id"]);
    }
    if (json["lat"] is String) {
      lat = json["lat"];
    }
    if (json["lng"] is String) {
      lng = json["lng"];
    }
    if (json["relatedVideoUrl"] is String) {
      relatedVideoUrl = json["relatedVideoUrl"];
    }
    if (json["speed"] is String) {
      speed = json["speed"];
    }
    if (json["timestamp"] is String) {
      timestamp = json["timestamp"];
    }
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
    if (json["userId"] is int) {
      userId = json["userId"];
    }
    if (json["userName"] is String) {
      userName = json["userName"];
    }
  }

  static List<HatLocationRecord> fromList(List<Map<String, dynamic>> list) {
    return list.map(HatLocationRecord.fromJson).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["altitude"] = altitude;
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    if (deviceInfo != null) {
      data["deviceInfo"] = deviceInfo!.toJson();
    }
    data["hatId"] = hatId;
    data["hatNumber"] = hatNumber;
    data["id"] = id;
    data["lat"] = lat;
    data["lng"] = lng;
    data["relatedVideoUrl"] = relatedVideoUrl;
    data["speed"] = speed;
    data["timestamp"] = timestamp;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    data["userId"] = userId;
    data["userName"] = userName;
    return data;
  }
}
