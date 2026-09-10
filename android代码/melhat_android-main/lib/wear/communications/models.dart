typedef JsonMap = Map<String, dynamic>;

String _stringOf(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text == 'null' ? fallback : text;
}

bool _boolOf(Object? value) =>
    value == true || value == 1 || value?.toString().toLowerCase() == 'true';

enum WearCallStatus {
  requesting,
  offered,
  connected,
  ended,
  failed,
  timedOut,
  unknown,
}

extension WearCallStatusView on WearCallStatus {
  bool get isTerminal =>
      this == WearCallStatus.ended ||
      this == WearCallStatus.failed ||
      this == WearCallStatus.timedOut;

  String get label => switch (this) {
    WearCallStatus.requesting => '正在请求设备',
    WearCallStatus.offered => '等待加入',
    WearCallStatus.connected => '已接通',
    WearCallStatus.ended => '已结束',
    WearCallStatus.failed => '通话失败',
    WearCallStatus.timedOut => '等待超时',
    WearCallStatus.unknown => '未知状态',
  };
}

WearCallStatus callStatusOf(Object? raw) => switch (_stringOf(raw)) {
  'requesting' => WearCallStatus.requesting,
  'offered' => WearCallStatus.offered,
  'connected' => WearCallStatus.connected,
  'ended' => WearCallStatus.ended,
  'failed' => WearCallStatus.failed,
  'timed_out' => WearCallStatus.timedOut,
  _ => WearCallStatus.unknown,
};

class CallSession {
  const CallSession({
    required this.id,
    required this.kind,
    required this.status,
    required this.deviceId,
    required this.requesterUserId,
    this.eventId,
    this.personId,
    this.siteId,
    this.sn = '',
    this.channelName = '',
    this.video = false,
    this.demo = false,
    this.connectionQuality = '',
    this.expiresAt,
    this.startedAt,
    this.connectedAt,
    this.endedAt,
    this.failReason = '',
    this.version = 0,
  });

  factory CallSession.fromJson(JsonMap json) => CallSession(
    id: _stringOf(json['id']),
    kind: _stringOf(json['kind'], 'single'),
    status: callStatusOf(json['status']),
    eventId: _nullableString(json['eventId']),
    deviceId: _stringOf(json['deviceId']),
    sn: _stringOf(json['sn']),
    personId: _nullableString(json['personId']),
    siteId: _nullableString(json['siteId']),
    requesterUserId: _stringOf(json['requesterUserId']),
    channelName: _stringOf(json['channelName']),
    video: _boolOf(json['video']),
    demo: _boolOf(json['demo']),
    connectionQuality: _stringOf(json['connectionQuality']),
    expiresAt: _dateOf(json['expiresAt']),
    startedAt: _dateOf(json['startedAt']),
    connectedAt: _dateOf(json['connectedAt']),
    endedAt: _dateOf(json['endedAt']),
    failReason: _stringOf(json['failReason']),
    version: int.tryParse(_stringOf(json['version'])) ?? 0,
  );

  final String id;
  final String kind;
  final WearCallStatus status;
  final String? eventId;
  final String deviceId;
  final String sn;
  final String? personId;
  final String? siteId;
  final String requesterUserId;
  final String channelName;
  final bool video;
  final bool demo;
  final String connectionQuality;
  final DateTime? expiresAt;
  final DateTime? startedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final String failReason;
  final int version;

  bool get isConnected => status == WearCallStatus.connected && !demo;
  bool get isTerminal => status.isTerminal;
  String get statusLabel => demo ? '演示状态（未连接真实设备）' : status.label;
}

class RtcCredentials {
  const RtcCredentials({
    required this.appId,
    required this.channelName,
    required this.uid,
    required this.token,
    this.expiresAt,
    this.demo = false,
    this.video = false,
  });

  factory RtcCredentials.fromJson(JsonMap json) => RtcCredentials(
    appId: _stringOf(json['agoraAppId']),
    channelName: _stringOf(json['channelName']),
    uid: int.tryParse(_stringOf(json['agoraUid'])) ?? 0,
    token: _stringOf(json['agoraToken']),
    expiresAt: _dateOf(json['expiresAt']),
    demo: _boolOf(json['demo']),
    video: _boolOf(json['video']),
  );

  final String appId;
  final String channelName;
  final int uid;
  final String token;
  final DateTime? expiresAt;
  final bool demo;
  final bool video;

  bool get isUsable =>
      appId.isNotEmpty && channelName.isNotEmpty && uid > 0 && token.isNotEmpty;
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());
}

class StartedCall {
  const StartedCall(this.session, this.credentials);
  final CallSession session;
  final RtcCredentials? credentials;
}

class PersonOption {
  const PersonOption({
    required this.id,
    required this.name,
    required this.personCode,
  });

  factory PersonOption.fromJson(JsonMap json) => PersonOption(
    id: _stringOf(json['id']),
    name: _stringOf(json['name'], '未命名人员'),
    personCode: _stringOf(json['personCode']),
  );

  final String id;
  final String name;
  final String personCode;
}

class CommunicationDevice {
  const CommunicationDevice({
    required this.id,
    required this.sn,
    required this.actions,
    this.personId,
    this.personName,
    this.typeCode = '',
    this.modelName = '',
    this.demo = false,
  });

  factory CommunicationDevice.fromJson(JsonMap json, {JsonMap? assignment}) {
    final capabilities = json['capabilities'];
    final actions = capabilities is Map
        ? _strings(capabilities['actions'])
        : const <String>{};
    return CommunicationDevice(
      id: _stringOf(json['id'] ?? assignment?['deviceId']),
      sn: _stringOf(json['sn'] ?? assignment?['sn']),
      personId: _nullableString(assignment?['personId']),
      personName: _nullableString(assignment?['personName']),
      typeCode: _stringOf(json['typeCode'] ?? assignment?['typeCode']),
      modelName: _stringOf(json['modelName']),
      actions: actions,
      demo: _boolOf(json['demo']),
    );
  }

  final String id;
  final String sn;
  final String? personId;
  final String? personName;
  final String typeCode;
  final String modelName;
  final Set<String> actions;
  final bool demo;

  bool supports(String action) => actions.contains(action);
}

enum TtsCommandStatus { accepted, sent, failed, unknown }

class TtsCommand {
  const TtsCommand({
    required this.id,
    required this.deviceId,
    required this.status,
    this.vendorMessage = '',
  });

  factory TtsCommand.fromJson(JsonMap json) => TtsCommand(
    id: _stringOf(json['id']),
    deviceId: _stringOf(json['deviceId']),
    status: switch (_stringOf(json['status'])) {
      'accepted' => TtsCommandStatus.accepted,
      'sent' => TtsCommandStatus.sent,
      'failed' => TtsCommandStatus.failed,
      _ => TtsCommandStatus.unknown,
    },
    vendorMessage: _stringOf(json['vendorMsg']),
  );

  final String id;
  final String deviceId;
  final TtsCommandStatus status;
  final String vendorMessage;
}

String? _nullableString(Object? value) {
  final text = _stringOf(value);
  return text.isEmpty ? null : text;
}

DateTime? _dateOf(Object? value) {
  final text = _stringOf(value);
  return text.isEmpty ? null : DateTime.tryParse(text);
}

Set<String> _strings(Object? value) {
  if (value is! List) return const <String>{};
  return value.map(_stringOf).where((item) => item.isNotEmpty).toSet();
}
