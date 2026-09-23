typedef EventJson = Map<String, dynamic>;

String _text(Object? value) => value?.toString().trim() ?? '';

int _integer(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse(_text(value)) ?? fallback;

bool _boolean(Object? value) =>
    value == true || value == 1 || _text(value).toLowerCase() == 'true';

enum EventCommand {
  ack,
  claim,
  confirm,
  handle,
  transfer,
  close,
  reopen,
  assignTask,
}

class WearEvent {
  const WearEvent({
    required this.id,
    required this.type,
    required this.severity,
    required this.status,
    required this.occurredAt,
    required this.receivedAt,
    required this.personId,
    required this.personCode,
    required this.personName,
    required this.deviceId,
    required this.sn,
    required this.siteId,
    required this.locationLat,
    required this.locationLng,
    required this.locationQuality,
    required this.claimantUserId,
    required this.repeatCount,
    required this.escalated,
    required this.demo,
    required this.source,
    required this.sourceEventId,
    required this.ruleVersion,
    required this.taskId,
    required this.taskMatch,
    required this.fenceId,
    required this.fenceAction,
    required this.version,
    this.reminderOnly = false,
    this.reporterUserId = '',
    this.deviceType = '',
    this.alarmCode = '',
    this.alarmName = '',
    this.alarmDescription = '',
  });

  factory WearEvent.fromJson(EventJson json) {
    final id = _text(json['id']);
    if (id.isEmpty) throw const FormatException('事件缺少有效编号');
    return WearEvent(
      id: id,
      type: _text(json['type']),
      reminderOnly: _boolean(json['reminderOnly']),
      deviceType: _text(json['deviceType']),
      alarmCode: _text(json['alarmCode']),
      alarmName: _text(json['alarmName']),
      alarmDescription: _text(json['alarmDescription']),
      severity: _text(json['severity']),
      status: _text(json['status']),
      occurredAt: _text(json['occurredAt']),
      receivedAt: _text(json['receivedAt']),
      personId: _text(json['personId']),
      reporterUserId: _text(json['reporterUserId']),
      personCode: _text(json['personCode']),
      personName: _text(json['personName']),
      deviceId: _text(json['deviceId']),
      sn: _text(json['sn']),
      siteId: _text(json['siteId']),
      locationLat: _text(json['locationLat']),
      locationLng: _text(json['locationLng']),
      locationQuality: _text(json['locationQuality']),
      claimantUserId: _text(json['claimantUserId']),
      repeatCount: _integer(json['repeatCount']),
      escalated: _boolean(json['escalated']),
      demo: _boolean(json['demo']),
      source: _text(json['source']),
      sourceEventId: _text(json['sourceEventId']),
      ruleVersion: _text(json['ruleVersion']),
      taskId: _text(json['taskId']),
      taskMatch: _text(json['taskMatch']),
      fenceId: _text(json['fenceId']),
      fenceAction: _text(json['fenceAction']),
      version: _integer(json['version']),
    );
  }

  final String id;
  final String type;
  final bool reminderOnly;
  final String deviceType;
  final String alarmCode;
  final String alarmName;
  final String alarmDescription;
  final String severity;
  final String status;
  final String occurredAt;
  final String receivedAt;
  final String personId;
  final String reporterUserId;
  final String personCode;
  final String personName;
  final String deviceId;
  final String sn;
  final String siteId;
  final String locationLat;
  final String locationLng;
  final String locationQuality;
  final String claimantUserId;
  final int repeatCount;
  final bool escalated;
  final bool demo;
  final String source;
  final String sourceEventId;
  final String ruleVersion;
  final String taskId;
  final String taskMatch;
  final String fenceId;
  final String fenceAction;
  final int version;

  bool get isWarning => severity == 'warning';
  bool get isEmergency => severity == 'emergency';
  bool get isHighRisk => isEmergency;
  String get severityLabel => isEmergency
      ? '紧急'
      : isWarning
      ? '警告'
      : '异常';
  String get deviceTypeLabel =>
      const {'helmet': '智能安全帽', 'belt': '智能安全带', 'watch': '智能手表'}[deviceType] ??
      '设备';
  bool get isClosed => status == 'closed';

  // Names describe the event-time alarm, never the device's current state.
  String get alarmLabel => alarmName.isNotEmpty
      ? alarmName
      : alarmCode.isNotEmpty
      ? alarmCode
      : '告警名称未提供';

  String get descriptionLabel => alarmDescription.isNotEmpty
      ? alarmDescription
      : alarmName.isNotEmpty
      ? alarmName
      : '核心系统暂未提供告警描述';

  String get typeLabel =>
      const {
        'sos': 'SOS 求助',
        'fall': '跌落（设备告警）',
        'impact': '撞击',
        'geofence': '围栏',
        'realtime': '实时告警',
      }[type] ??
      (type.isEmpty ? '未知类型' : type);

  String statusFor({required bool admin}) => statusLabel;

  String get statusLabel =>
      const {
        'open': '待处理',
        'claimed': '待处理',
        'handling': '处置中',
        'pending_review': '待管理员审批',
        'closed': '已关闭',
      }[status] ??
      (status.isEmpty ? '未知状态' : status);
}

class EventAction {
  const EventAction({
    required this.id,
    required this.action,
    required this.actor,
    required this.reason,
    required this.fromStatus,
    required this.toStatus,
    required this.createTime,
  });

  factory EventAction.fromJson(EventJson json) => EventAction(
    id: _text(json['id']),
    action: _text(json['action']),
    actor: _text(json['actor']),
    reason: _text(json['reason']),
    fromStatus: _text(json['fromStatus']),
    toStatus: _text(json['toStatus']),
    createTime: _text(json['createTime']),
  );

  final String id;
  final String action;
  final String actor;
  final String reason;
  final String fromStatus;
  final String toStatus;
  final String createTime;
}

class DutyOperator {
  const DutyOperator({
    required this.userId,
    required this.userName,
    required this.nickName,
  });

  factory DutyOperator.fromJson(EventJson json) => DutyOperator(
    userId: _text(json['userId']),
    userName: _text(json['userName']),
    nickName: _text(json['nickName']),
  );

  final String userId;
  final String userName;
  final String nickName;
  String get displayName => nickName.isNotEmpty ? nickName : userName;
}

class WorkTaskCandidate {
  const WorkTaskCandidate({
    required this.id,
    required this.title,
    required this.status,
    required this.workType,
    required this.spaceName,
    required this.plannedStart,
    required this.plannedEnd,
    required this.demo,
  });

  factory WorkTaskCandidate.fromJson(EventJson json) {
    final id = _text(json['id']);
    if (id.isEmpty) throw const FormatException('作业任务缺少有效编号');
    return WorkTaskCandidate(
      id: id,
      title: _text(json['title']),
      status: _text(json['status']),
      workType: _text(json['workType']),
      spaceName: _text(json['spaceName']),
      plannedStart: _text(json['plannedStart']),
      plannedEnd: _text(json['plannedEnd']),
      demo: _boolean(json['demo']),
    );
  }

  final String id;
  final String title;
  final String status;
  final String workType;
  final String spaceName;
  final String plannedStart;
  final String plannedEnd;
  final bool demo;
}

class TaskCandidatePage {
  const TaskCandidatePage({
    required this.records,
    required this.total,
    required this.current,
    required this.size,
  });

  final List<WorkTaskCandidate> records;
  final int total;
  final int current;
  final int size;
  bool get hasMore => current * size < total;
}

class EventFilters {
  const EventFilters({
    this.status = 'active',
    this.type = '',
    this.severity = '',
    this.reminderOnly = false,
    this.alarmCode = '',
    this.alarmLabel = '',
    this.deviceTypes = const [],
    this.statuses = const [],
    this.types = const [],
    this.alarmCodes = const [],
    this.alarmLabels = const {},
    this.personId = '',
    this.taskId = '',
    this.claimantUserId = '',
    this.escalated = false,
  });

  factory EventFilters.fromJson(Object? value) {
    if (value is! Map) return const EventFilters();
    final status = _text(value['status']);
    return EventFilters(
      status: status.isEmpty ? 'active' : status,
      type: _text(value['type']),
      severity: _text(value['severity']),
      alarmCode: _text(value['alarmCode']),
      alarmLabel: _text(value['alarmLabel']),
      statuses: _strings(value['statuses']),
      types: _strings(value['types']),
      alarmCodes: _strings(value['alarmCodes']),
      alarmLabels: value['alarmLabels'] is Map
          ? (value['alarmLabels'] as Map).map(
              (k, v) => MapEntry(_text(k), _text(v)),
            )
          : const {},
      deviceTypes: value['deviceTypes'] is List
          ? (value['deviceTypes'] as List)
                .map(_text)
                .where((v) => const ['helmet', 'belt', 'watch'].contains(v))
                .toSet()
                .toList()
          : const [],
      personId: _text(value['personId']),
      taskId: _text(value['taskId']),
      claimantUserId: _text(value['claimantUserId']),
      escalated: _boolean(value['escalated']),
    );
  }

  final String status;
  final String type;
  final String severity;
  final bool reminderOnly;
  final String alarmCode;
  final String alarmLabel;
  final List<String> deviceTypes;
  final List<String> statuses;
  final List<String> types;
  final List<String> alarmCodes;
  final Map<String, String> alarmLabels;
  List<String> get selectedStatuses => statuses.isNotEmpty
      ? statuses
      : status == 'all'
      ? const []
      : status == 'active' || status.isEmpty
      ? const ['open', 'claimed', 'handling', 'pending_review']
      : [status];
  List<String> get selectedTypes => types.isNotEmpty
      ? types
      : type.isEmpty
      ? const []
      : [type];
  List<String> get selectedAlarmCodes => alarmCodes.isNotEmpty
      ? alarmCodes
      : alarmCode.isEmpty
      ? const []
      : [alarmCode];
  static List<String> _strings(Object? value) => value is List
      ? value.map(_text).where((v) => v.isNotEmpty).toSet().toList()
      : const [];
  final String personId;
  final String taskId;
  final String claimantUserId;
  final bool escalated;

  EventJson toJson() => {
    'status': status,
    'type': type,
    'severity': severity,
    'alarmCode': alarmCode,
    'alarmLabel': alarmLabel,
    'deviceTypes': deviceTypes,
    'statuses': statuses,
    'types': types,
    'alarmCodes': alarmCodes,
    'alarmLabels': alarmLabels,
    'personId': personId,
    'taskId': taskId,
    'claimantUserId': claimantUserId,
    'escalated': escalated,
  };

  EventFilters copyWith({
    String? status,
    String? type,
    String? severity,
    String? alarmCode,
    String? alarmLabel,
    List<String>? deviceTypes,
    List<String>? statuses,
    List<String>? types,
    List<String>? alarmCodes,
    Map<String, String>? alarmLabels,
    String? personId,
    String? taskId,
    String? claimantUserId,
    bool? escalated,
  }) => EventFilters(
    status: status ?? this.status,
    type: type ?? this.type,
    severity: severity ?? this.severity,
    alarmCode: alarmCode ?? this.alarmCode,
    alarmLabel: alarmLabel ?? this.alarmLabel,
    deviceTypes: deviceTypes ?? this.deviceTypes,
    statuses: statuses ?? (status != null ? const [] : this.statuses),
    types: types ?? (type != null ? const [] : this.types),
    alarmCodes: alarmCodes ?? (alarmCode != null ? const [] : this.alarmCodes),
    alarmLabels: alarmLabels ?? this.alarmLabels,
    personId: personId ?? this.personId,
    taskId: taskId ?? this.taskId,
    claimantUserId: claimantUserId ?? this.claimantUserId,
    escalated: escalated ?? this.escalated,
  );
}

class EventDraft {
  const EventDraft({
    this.handleComment = '',
    this.photoPaths = const [],
    this.transferUserId = '',
    this.transferReason = '',
    this.closeReason = '',
    this.reopenReason = '',
    this.taskId = '',
  });

  factory EventDraft.fromJson(Object? value) {
    if (value is! Map) return const EventDraft();
    return EventDraft(
      handleComment: _text(value['handleComment']),
      photoPaths: value['photoPaths'] is List
          ? (value['photoPaths'] as List)
                .map(_text)
                .where((p) => p.isNotEmpty)
                .toList()
          : const [],
      transferUserId: _text(value['transferUserId']),
      transferReason: _text(value['transferReason']),
      closeReason: _text(value['closeReason']),
      reopenReason: _text(value['reopenReason']),
      taskId: _text(value['taskId']),
    );
  }

  final String handleComment;
  final List<String> photoPaths;
  final String transferUserId;
  final String transferReason;
  final String closeReason;
  final String reopenReason;
  final String taskId;

  bool get isEmpty =>
      photoPaths.isEmpty &&
      handleComment.isEmpty &&
      transferUserId.isEmpty &&
      transferReason.isEmpty &&
      closeReason.isEmpty &&
      reopenReason.isEmpty &&
      taskId.isEmpty;

  EventJson toJson() => {
    'handleComment': handleComment,
    'photoPaths': photoPaths,
    'transferUserId': transferUserId,
    'transferReason': transferReason,
    'closeReason': closeReason,
    'reopenReason': reopenReason,
    'taskId': taskId,
  };

  EventDraft copyWith({
    String? handleComment,
    List<String>? photoPaths,
    String? transferUserId,
    String? transferReason,
    String? closeReason,
    String? reopenReason,
    String? taskId,
  }) => EventDraft(
    handleComment: handleComment ?? this.handleComment,
    photoPaths: photoPaths ?? this.photoPaths,
    transferUserId: transferUserId ?? this.transferUserId,
    transferReason: transferReason ?? this.transferReason,
    closeReason: closeReason ?? this.closeReason,
    reopenReason: reopenReason ?? this.reopenReason,
    taskId: taskId ?? this.taskId,
  );
}

class EventPageData {
  const EventPageData({
    required this.records,
    required this.total,
    required this.current,
    required this.size,
  });

  final List<WearEvent> records;
  final int total;
  final int current;
  final int size;
  bool get hasMore => current * size < total;
}

class EventWorkspaceState {
  const EventWorkspaceState({
    this.filters = const EventFilters(),
    this.current = 1,
    this.selectedEventId = '',
    this.scrollOffset = 0,
    this.drafts = const {},
  });

  factory EventWorkspaceState.fromJson(Object? value) {
    if (value is! Map) return const EventWorkspaceState();
    final rawDrafts = value['drafts'];
    return EventWorkspaceState(
      filters: EventFilters.fromJson(value['filters']),
      current: _integer(value['current'], 1).clamp(1, 1 << 30),
      selectedEventId: _text(value['selectedEventId']),
      scrollOffset: double.tryParse(_text(value['scrollOffset'])) ?? 0,
      drafts: rawDrafts is Map
          ? rawDrafts.map(
              (key, draft) => MapEntry(_text(key), EventDraft.fromJson(draft)),
            )
          : const {},
    );
  }

  final EventFilters filters;
  final int current;
  final String selectedEventId;
  final double scrollOffset;
  final Map<String, EventDraft> drafts;

  EventJson toJson() => {
    'filters': filters.toJson(),
    'current': current,
    'selectedEventId': selectedEventId,
    'scrollOffset': scrollOffset,
    'drafts': drafts.map((key, value) => MapEntry(key, value.toJson())),
  };
}

class EventConflict implements Exception {
  const EventConflict(this.message);
  final String message;
  @override
  String toString() => message;
}

class EventStaleScope implements Exception {
  const EventStaleScope();
}
