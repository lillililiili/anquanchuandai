class AgoraCredentials {
  final String agoraAppId;
  final String channelName;
  final int agoraUid;
  final String? agoraToken;

  AgoraCredentials({
    required this.agoraAppId,
    required this.channelName,
    required this.agoraUid,
    this.agoraToken,
  });

  factory AgoraCredentials.fromJson(Map<String, dynamic> json) {
    return AgoraCredentials(
      agoraAppId: json['agoraAppId'],
      channelName: json['channelName'],
      agoraUid: json['agoraUid'] ?? 0,
      agoraToken: json['agoraToken'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'agoraAppId': agoraAppId,
      'channelName': channelName,
      'agoraUid': agoraUid,
      'agoraToken': agoraToken,
    };
  }
}
