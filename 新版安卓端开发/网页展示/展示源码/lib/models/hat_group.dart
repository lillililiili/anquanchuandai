/// 分组信息模型
class HatGroup {
  String? createBy;
  String? createTime;
  String? delFlag;
  /// 分组描述
  String? groupDesc;
  /// 分组名称
  String? groupName;
  /// 分组id
  int? id;
  /// 安全帽数量
  int? safetyCount;
  String? updateBy;
  String? updateTime;

  HatGroup({
    this.createBy,
    this.createTime,
    this.delFlag,
    this.groupDesc,
    this.groupName,
    this.id,
    this.safetyCount,
    this.updateBy,
    this.updateTime,
  });

  HatGroup.fromJson(Map<String, dynamic> json) {
    if (json["createBy"] is String) {
      createBy = json["createBy"];
    }
    if (json["createTime"] is String) {
      createTime = json["createTime"];
    }
    if (json["delFlag"] is String) {
      delFlag = json["delFlag"];
    }
    if (json["groupDesc"] is String) {
      groupDesc = json["groupDesc"];
    }
    if (json["groupName"] is String) {
      groupName = json["groupName"];
    }
    // id 支持 int 和 String 类型
    if (json["id"] is int) {
      id = json["id"];
    } else if (json["id"] is String) {
      id = int.tryParse(json["id"]);
    }
    if (json["safetyCount"] is int) {
      safetyCount = json["safetyCount"];
    }
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
  }

  static List<HatGroup> fromList(List<Map<String, dynamic>> list) {
    return list.map(HatGroup.fromJson).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    data["groupDesc"] = groupDesc;
    data["groupName"] = groupName;
    data["id"] = id;
    data["safetyCount"] = safetyCount;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    return data;
  }
}
