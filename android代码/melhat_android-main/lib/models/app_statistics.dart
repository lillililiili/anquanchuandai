/// APP 数据统计信息模型
class AppStatistics {
  /// 需要处理的告警数
  int? alarmCount;

  /// 安全帽数量
  int? hatCount;

  /// 拍摄图片数量
  int? photoCount;

  /// 录音数量
  int? recordCount;

  /// TTS 广播数量
  int? ttsBroadcastCount;

  AppStatistics({
    this.alarmCount,
    this.hatCount,
    this.photoCount,
    this.recordCount,
    this.ttsBroadcastCount,
  });

  AppStatistics.fromJson(Map<String, dynamic> json) {
    if (json["alarmCount"] is int) {
      alarmCount = json["alarmCount"];
    }
    if (json["hatCount"] is int) {
      hatCount = json["hatCount"];
    }
    if (json["photoCount"] is int) {
      photoCount = json["photoCount"];
    }
    if (json["recordCount"] is int) {
      recordCount = json["recordCount"];
    }
    if (json["ttsBroadcastCount"] is int) {
      ttsBroadcastCount = json["ttsBroadcastCount"];
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["alarmCount"] = alarmCount;
    data["hatCount"] = hatCount;
    data["photoCount"] = photoCount;
    data["recordCount"] = recordCount;
    data["ttsBroadcastCount"] = ttsBroadcastCount;
    return data;
  }
}
