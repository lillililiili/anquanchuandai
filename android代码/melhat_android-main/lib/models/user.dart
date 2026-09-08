/// 用户数据模型
class UserInfo {
  final String createBy;
  final String createTime;
  final String? updateBy;
  final String? updateTime;
  final String remark;
  final String userId;
  final String deptId;
  final String userName;
  final String userType;
  final String nickName;
  final String email;
  final String phonenumber;
  final String sex;
  final String avatar;
  final String password;
  final String status;
  final String delFlag;
  final String loginIp;
  final String loginDate;
  final String? sipId;
  final String? melHatSip;
  final String? melHat;

  UserInfo({
    required this.createBy,
    required this.createTime,
    this.updateBy,
    this.updateTime,
    required this.remark,
    required this.userId,
    required this.deptId,
    required this.userName,
    required this.userType,
    required this.nickName,
    required this.email,
    required this.phonenumber,
    required this.sex,
    required this.avatar,
    required this.password,
    required this.status,
    required this.delFlag,
    required this.loginIp,
    required this.loginDate,
    this.sipId,
    this.melHatSip,
    this.melHat,
  });

  /// 从 JSON 创建
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      createBy: json['createBy'] ?? '',
      createTime: json['createTime'] ?? '',
      updateBy: json['updateBy'],
      updateTime: json['updateTime'],
      remark: json['remark'] ?? '',
      userId: json['userId'] ?? '',
      deptId: json['deptId'] ?? '',
      userName: json['userName'] ?? '',
      userType: json['userType'] ?? '',
      nickName: json['nickName'] ?? '',
      email: json['email'] ?? '',
      phonenumber: json['phonenumber'] ?? '',
      sex: json['sex'] ?? '',
      avatar: json['avatar'] ?? '',
      password: json['password'] ?? '',
      status: json['status'] ?? '',
      delFlag: json['delFlag'] ?? '',
      loginIp: json['loginIp'] ?? '',
      loginDate: json['loginDate'] ?? '',
      sipId: json['sipId'],
      melHatSip: json['melHatSip'],
      melHat: json['melHat'],
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'createBy': createBy,
      'createTime': createTime,
      'updateBy': updateBy,
      'updateTime': updateTime,
      'remark': remark,
      'userId': userId,
      'deptId': deptId,
      'userName': userName,
      'userType': userType,
      'nickName': nickName,
      'email': email,
      'phonenumber': phonenumber,
      'sex': sex,
      'avatar': avatar,
      'password': password,
      'status': status,
      'delFlag': delFlag,
      'loginIp': loginIp,
      'loginDate': loginDate,
      'sipId': sipId,
      'melHatSip': melHatSip,
      'melHat': melHat,
    };
  }
}
