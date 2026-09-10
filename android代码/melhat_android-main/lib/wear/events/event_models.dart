typedef EventJson = Map<String, dynamic>;

String _text(Object? value) => value?.toString().trim() ?? '';

int _integer(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse(_text(value)) ?? fallback;

bool _boolean(Object? value) =>
    value == true || value == 1 || _text(value).toLowerCase() == 'true';

enum EventCommand { ack, claim, handle, transfer, close, reopen, assignTask }

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
  });

  factory WearEvent.fromJson(EventJson json) {
    final id = _text(json['id']);
    if (id.isEmpty) throw const FormatException('事件缺少有效编号');
    return WearEvent(
      id: id,
      type: _text(json['type']),
      severity: _text(json['severity']),
      status: _text(json['status']),
      occurredAt: _text(json['occurredAt']),
      receivedAt: _text(json['receivedAt']),
      personId: _text(json['personId']),
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
  final String severity;
  final String status;
  final String occurredAt;
  final String receivedAt;
  final String personId;
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

  bool get isHighRisk => const {'sos', 'fall', 'impact'}.contains(type);
  bool get isClosed => status == 'closed';

  String get typeLabel =>
      const {
        'sos': 'SOS 求助',
        'fall': '跌倒',
        'impact': '撞击',
        'geofence': '围栏',
        'realtime': '实时告警',
      }[type] ??
      (type.isEmpty ? '未知类型' : type);

  String get statusLabel =>
      const {
        'open': '待认领',
        'claimed': '已认领',
        'handling': '处置中',
        'pending_review': '待复核',
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
      personId: _text(value['personId']),
      taskId: _text(value['taskId']),
      claimantUserId: _text(value['claimantUserId']),
      escalated: _boolean(value['escalated']),
    );
  }

  final String status;
  final String type;
  final String personId;
  final String taskId;
  final String claimantUserId;
  final bool escalated;

  EventJson toJson() => {
    'status': status,
    'type': type,
    'personId': personId,
    'taskId': taskId,
    'claimantUserId': claimantUserId,
    'escalated': escalated,
  };

  EventFilters copyWith({
    String? status,
    String? type,
    String? personId,
    String? taskId,
    String? claimantUserId,
    bool? escalated,
  }) => EventFilters(
    status: status ?? this.status,
    type: type ?? this.type,
    personId: personId ?? this.personId,
    taskId: taskId ?? this.taskId,
    claimantUserId: claimantUserId ?? this.claimantUserId,
    escalated: escalated ?? this.escalated,
  );
}

class EventDraft {
  const EventDraft({
    this.handleComment = '',
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
      transferUserId: _text(value['transferUserId']),
      transferReason: _text(value['transferReason']),
      closeReason: _text(value['closeReason']),
      reopenReason: _text(value['reopenReason']),
      taskId: _text(value['taskId']),
    );
  }

  final String handleComment;
  final String transferUserId;
  final String transferReason;
  final String closeReason;
  final String reopenReason;
  final String taskId;

  bool get isEmpty =>
      handleComment.isEmpty &&
      transferUserId.isEmpty &&
      transferReason.isEmpty &&
      closeReason.isEmpty &&
      reopenReason.isEmpty &&
      taskId.isEmpty;

  EventJson toJson() => {
    'handleComment': handleComment,
    'transferUserId': transferUserId,
    'transferReason': transferReason,
    'closeReason': closeReason,
    'reopenReason': reopenReason,
    'taskId': taskId,
  };

  EventDraft copyWith({
    String? handleComment,
    String? transferUserId,
    String? transferReason,
    String? closeReason,
    String? reopenReason,
    String? taskId,
  }) => EventDraft(
    handleComment: handleComment ?? this.handleComment,
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
