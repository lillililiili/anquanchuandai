/// 对讲记录模型
class IntercomRecord {
  /// 创建人
  String? createBy;

  /// 创建时间
  String? createTime;

  /// 删除标志
  String? delFlag;

  /// 对讲时长
  String? duration;

  /// 对讲结束时间
  String? endTime;

  /// 帽子编号:多个,分割
  String? hatNumber;

  /// 记录id
  int? id;

  /// 对讲类型：01单呼/02群呼/03组呼
  String? intercomType;

  /// 参与人员，单呼为安全帽编号，群呼为为安全帽编号拼接,分割/组呼为组id
  String? participant;

  /// 接收人数（群组/全体人员场景）
  int? recipientCount;

  /// 对讲录音存储路径
  String? recordPath;

  /// 对讲开始时间
  String? startTime;

  /// 更新人
  String? updateBy;

  /// 更新时间
  String? updateTime;

  IntercomRecord({
    this.createBy,
    this.createTime,
    this.delFlag,
    this.duration,
    this.endTime,
    this.hatNumber,
    this.id,
    this.intercomType,
    this.participant,
    this.recipientCount,
    this.recordPath,
    this.startTime,
    this.updateBy,
    this.updateTime,
  });

  IntercomRecord.fromJson(Map<String, dynamic> json) {
    if (json["createBy"] is String) {
      createBy = json["createBy"];
    }
    if (json["createTime"] is String) {
      createTime = json["createTime"];
    }
    if (json["delFlag"] is String) {
      delFlag = json["delFlag"];
    }
    if (json["duration"] is String) {
      duration = json["duration"];
    }
    if (json["endTime"] is String) {
      endTime = json["endTime"];
    }
    if (json["hatNumber"] is String) {
      hatNumber = json["hatNumber"];
    }
    if (json["id"] is int) {
      id = json["id"];
    }
    if (json["intercomType"] is String) {
      intercomType = json["intercomType"];
    }
    if (json["participant"] is String) {
      participant = json["participant"];
    }
    if (json["recipientCount"] is int) {
      recipientCount = json["recipientCount"];
    }
    if (json["recordPath"] is String) {
      recordPath = json["recordPath"];
    }
    if (json["startTime"] is String) {
      startTime = json["startTime"];
    }
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
  }

  static List<IntercomRecord> fromList(List<dynamic> list) {
    return list.map((e) => IntercomRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    data["duration"] = duration;
    data["endTime"] = endTime;
    data["hatNumber"] = hatNumber;
    data["id"] = id;
    data["intercomType"] = intercomType;
    data["participant"] = participant;
    data["recipientCount"] = recipientCount;
    data["recordPath"] = recordPath;
    data["startTime"] = startTime;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    return data;
  }
}
