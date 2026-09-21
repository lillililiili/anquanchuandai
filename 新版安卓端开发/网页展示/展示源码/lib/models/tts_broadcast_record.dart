/// TTS 广播记录模型
class TtsBroadcastRecord {
  /// 广播类型：01单播/02群播/03组播
  String? broadcastType;

  /// 发送内容
  String? content;

  /// 创建人
  String? createBy;

  /// 创建时间
  String? createTime;

  /// 删除标志
  String? delFlag;

  /// 帽子编号:多个,分割
  String? hatNumber;

  /// 记录id
  int? id;

  /// 操作人
  String? operator;

  /// 接收对象：用户名称，多个,分割
  String? recipient;

  /// 接收人数（群组/全体人员场景）
  int? recipientCount;

  /// 发送时间
  String? sendTime;

  /// 更新人
  String? updateBy;

  /// 更新时间
  String? updateTime;

  TtsBroadcastRecord({
    this.broadcastType,
    this.content,
    this.createBy,
    this.createTime,
    this.delFlag,
    this.hatNumber,
    this.id,
    this.operator,
    this.recipient,
    this.recipientCount,
    this.sendTime,
    this.updateBy,
    this.updateTime,
  });

  TtsBroadcastRecord.fromJson(Map<String, dynamic> json) {
    if (json["broadcastType"] is String) {
      broadcastType = json["broadcastType"];
    }
    if (json["content"] is String) {
      content = json["content"];
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
    if (json["hatNumber"] is String) {
      hatNumber = json["hatNumber"];
    }
    if (json["id"] is int) {
      id = json["id"];
    }
    if (json["operator"] is String) {
      operator = json["operator"];
    }
    if (json["recipient"] is String) {
      recipient = json["recipient"];
    }
    if (json["recipientCount"] is int) {
      recipientCount = json["recipientCount"];
    }
    if (json["sendTime"] is String) {
      sendTime = json["sendTime"];
    }
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
  }

  static List<TtsBroadcastRecord> fromList(List<dynamic> list) {
    return list.map((e) => TtsBroadcastRecord.fromJson(e as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["broadcastType"] = broadcastType;
    data["content"] = content;
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    data["hatNumber"] = hatNumber;
    data["id"] = id;
    data["operator"] = operator;
    data["recipient"] = recipient;
    data["recipientCount"] = recipientCount;
    data["sendTime"] = sendTime;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    return data;
  }
}
