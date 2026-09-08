class HatLocationFileRecord {
  String? createBy;
  String? createTime;
  String? delFlag;
  String? deviceInfo;
  String? fileName;
  num? fileSize;
  String? fileType;
  String? fileUrl;
  int? hatId;
  String? hatNumber;
  int? id;
  String? updateBy;
  String? updateTime;
  String? uploadTime;
  String? userName;

  HatLocationFileRecord({
    this.createBy,
    this.createTime,
    this.delFlag,
    this.deviceInfo,
    this.fileName,
    this.fileSize,
    this.fileType,
    this.fileUrl,
    this.hatId,
    this.hatNumber,
    this.id,
    this.updateBy,
    this.updateTime,
    this.uploadTime,
    this.userName,
  });

  HatLocationFileRecord.fromJson(Map<String, dynamic> json) {
    if (json["createBy"] is String) {
      createBy = json["createBy"];
    }
    if (json["createTime"] is String) {
      createTime = json["createTime"];
    }
    if (json["delFlag"] is String) {
      delFlag = json["delFlag"];
    }
    if (json["deviceInfo"] is String) {
      deviceInfo = json["deviceInfo"];
    }
    if (json["fileName"] is String) {
      fileName = json["fileName"];
    }
    if (json["fileSize"] is num) {
      fileSize = json["fileSize"];
    }
    if (json["fileType"] is String) {
      fileType = json["fileType"];
    }
    if (json["fileUrl"] is String) {
      fileUrl = json["fileUrl"];
    }
    if (json["hatId"] is int) {
      hatId = json["hatId"];
    }
    if (json["hatNumber"] is String) {
      hatNumber = json["hatNumber"];
    }
    if (json["id"] is int) {
      id = json["id"];
    }
    if (json["updateBy"] is String) {
      updateBy = json["updateBy"];
    }
    if (json["updateTime"] is String) {
      updateTime = json["updateTime"];
    }
    if (json["uploadTime"] is String) {
      uploadTime = json["uploadTime"];
    }
    if (json["userName"] is String) {
      userName = json["userName"];
    }
  }

  static List<HatLocationFileRecord> fromList(List<Map<String, dynamic>> list) {
    return list.map(HatLocationFileRecord.fromJson).toList();
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = <String, dynamic>{};
    data["createBy"] = createBy;
    data["createTime"] = createTime;
    data["delFlag"] = delFlag;
    data["deviceInfo"] = deviceInfo;
    data["fileName"] = fileName;
    data["fileSize"] = fileSize;
    data["fileType"] = fileType;
    data["fileUrl"] = fileUrl;
    data["hatId"] = hatId;
    data["hatNumber"] = hatNumber;
    data["id"] = id;
    data["updateBy"] = updateBy;
    data["updateTime"] = updateTime;
    data["uploadTime"] = uploadTime;
    data["userName"] = userName;
    return data;
  }
}
