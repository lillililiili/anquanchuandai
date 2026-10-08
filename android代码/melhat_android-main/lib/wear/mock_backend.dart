import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'data.dart';

/// In-memory transport. Every request ends here, including unsupported paths.
/// There is deliberately no IO adapter and no fallback to a backend.
class MockBackend implements HttpClientAdapter {
  static final shared = MockBackend();
  final bool _scoped;
  MockBackend({bool scoped = false}) : _scoped = scoped {
    for (var i = 0; i < people.length; i++) {
      people[i].addAll({'teamId': i < 2 ? '1' : '2', 'demo': true});
    }
    for (var i = 0; i < devices.length; i++) {
      devices[i].addAll({
        'assetStatus': 'issued',
        'simulation': true,
        'currentAssignment': {
          'id': '${601 + i}',
          'personId': i == 2 ? '102' : '101',
          'personName': i == 2 ? '周明' : '陈建国',
        },
      });
    }
    for (final d in devices) {
      assignmentHistory.add({
        ...jsonMap(d['currentAssignment']),
        'deviceId': d['id'],
        'sn': d['sn'],
        'typeCode': d['typeCode'],
        'assignedAt': _now,
        'returnedAt': null,
      });
    }
    devices.add({
      ...devices.first,
      'id': '204',
      'sn': 'RL-H002',
      'assetStatus': 'in_stock',
      'currentAssignment': null,
    });
    task['demo'] = true;
    task['ownerUserId'] = '12';
    for (final event in events) {
      event.addAll({
        'deviceType': 'helmet',
        'source': 'device',
        'observations': <JsonMap>[],
        'verification': <String, dynamic>{},
        'verificationDraft': <String, dynamic>{},
        if (event['type'] == 'sos')
          'assistance': {'state': 'waiting', 'members': <String>[]},
        'externalClosureStatus': 'unknown',
        'fieldReportStatus': 'not_reported',
        'verificationStatus': 'pending',
        'reviewStatus': 'not_required',
        'alarmCode': event['type'] == 'sos' ? 'SOS' : 'FENCE_ENTER',
        'alarmName': event['type'] == 'sos' ? '人员求助' : '进入作业禁区',
        'alarmDescription': '本地模拟事件，用于演示页面处置流程',
      });
    }
  }
  String account = 'demo';
  String? siteId;
  final actions = <String, List<JsonMap>>{};
  final calls = <String, JsonMap>{};
  final assignmentHistory = <JsonMap>[];
  final people = <JsonMap>[
    {
      'id': '101',
      'name': '陈建国',
      'personCode': 'P-001',
      'status': '0',
      'phone': '138****0101',
      'teamName': '设备检修班',
    },
    {
      'id': '102',
      'name': '周明',
      'personCode': 'P-002',
      'status': '0',
      'phone': '138****0102',
      'teamName': '设备检修班',
    },
    {
      'id': '103',
      'name': '李志远',
      'personCode': 'P-003',
      'status': '0',
      'phone': '138****0103',
      'teamName': '运行班',
    },
  ];
  final devices = <JsonMap>[
    {
      'id': '201',
      'sn': 'RL-H001',
      'typeCode': 'helmet',
      'modelName': '智能安全帽',
      'online': 1,
      'connectionQuality': 'ok',
      'onlineStatus': 'online',
      'status': '0',
      'battery': 86,
      'batteryLevel': 86,
      'demo': true,
      'capabilities': {
        'actions': ['intercom', 'tts'],
        'metrics': ['battery'],
      },
    },
    {
      'id': '202',
      'sn': 'RL-B001',
      'typeCode': 'belt',
      'modelName': '智能安全带',
      'online': 1,
      'connectionQuality': 'ok',
      'onlineStatus': 'online',
      'status': '0',
      'battery': 92,
      'demo': true,
      'capabilities': {
        'actions': [],
        'metrics': ['battery'],
      },
    },
    {
      'id': '203',
      'sn': 'RL-W001',
      'typeCode': 'watch',
      'modelName': '智能手环',
      'online': 1,
      'connectionQuality': 'ok',
      'onlineStatus': 'online',
      'status': '0',
      'battery': 78,
      'demo': true,
      'capabilities': {
        'actions': [],
        'metrics': ['battery'],
      },
    },
  ];
  final task = <String, dynamic>{
    'id': '301',
    'title': '东区高处检修作业',
    'status': 'in_progress',
    'workType': 'height',
    'spaceName': '东区作业区',
    'ownerUserId': '103',
    'ownerName': '李志远',
    'guardianPersonId': '102',
    'guardianName': '周明',
    'ticketRequired': true,
    'ticketStatus': 'provided',
    'ticketNo': 'GL-20260917-018',
    'plannedStartAt': '2026-09-17T09:00:00+08:00',
    'plannedEndAt': '2026-09-17T18:00:00+08:00',
    'members': [
      {'personId': '101', 'name': '陈建国', 'personCode': 'P-001'},
      {'personId': '102', 'name': '周明', 'personCode': 'P-002'},
    ],
  };
  final events = <JsonMap>[
    {
      'id': '401',
      'type': 'geofence',
      'severity': 'abnormal',
      'status': 'handling',
      'claimantUserId': '12',
      'occurredAt': '2026-09-17T10:24:00+08:00',
      'receivedAt': '2026-09-17T10:24:02+08:00',
      'personId': '101',
      'personName': '陈建国',
      'personCode': 'P-001',
      'deviceId': '201',
      'sn': 'RL-H001',
      'siteId': '1',
      'demo': true,
      'version': 1,
      'taskId': '301',
      'sourceEventId': 'AJ-20260917-001',
      'source': 'device',
      'fenceId': '501',
      'fenceAction': 'enter',
    },
    {
      'id': '402',
      'type': 'sos',
      'severity': 'emergency',
      'status': 'open',
      'occurredAt': '2026-09-17T10:39:00+08:00',
      'receivedAt': '2026-09-17T10:39:01+08:00',
      'personId': '101',
      'personName': '陈建国',
      'personCode': 'P-001',
      'deviceId': '201',
      'sn': 'RL-H001',
      'siteId': '1',
      'demo': true,
      'escalated': true,
      'version': 1,
      'taskId': '301',
      'source': 'device',
    },
  ];

  final _scopes = <String, MockBackend>{};
  final _media = <String, List<JsonMap>>{};
  final _requests = <String, String>{};
  int _sequence = 1000;
  bool get _admin => account == 'demo';
  String get _userId => _admin ? '12' : '13';
  String get _personId => _admin ? '101' : '102';
  String get _name => _admin ? '陈建国' : '周明';
  String get _now => DateTime.now().toIso8601String();
  String get _nextId => '${++_sequence}';

  JsonMap get identity => {
    'userId': _userId,
    'userName': account,
    'username': account,
    'nickName': _name,
    'name': _name,
    'personId': _personId,
    'status': '0',
    'admin': _admin,
    'roles': _admin ? ['wear_platform_admin'] : ['wear_member'],
    'permissions': [
      if (_admin) '*:*:*',
      'wear:event:list',
      'wear:event:query',
      'wear:event:report',
      'wear:task:list',
      'wear:task:query',
      'wear:device:list',
      'wear:device:query',
      'wear:person:list',
      'wear:person:query',
      'wear:site:list',
      'wear:site:select',
      if (_admin) 'wear:call:start',
      if (_admin) 'wear:command:tts',
    ],
    'authorizedSites': [
      {'id': '1', 'status': '0', 'name': '演示厂站A'},
      if (_admin) {'id': '2', 'status': '0', 'name': '演示厂站B'},
    ],
    'currentSiteId': siteId,
  };

  List<JsonMap> equipmentFor(String person) => [
    for (final d in devices)
      if (idOf(jsonMap(d['currentAssignment'])['personId']) == person)
        {
          ...d,
          ...jsonMap(d['currentAssignment']),
          'deviceId': d['id'],
          'assignedAt': _now,
          'typeName': d['modelName'],
        },
  ];

  JsonMap page(List<JsonMap> rows, RequestOptions o) {
    final current = intOf(o.queryParameters['current'], 1).clamp(1, 100000);
    final size = intOf(o.queryParameters['size'], 20).clamp(1, 1000);
    return {
      'records': rows.skip((current - 1) * size).take(size).toList(),
      'total': rows.length,
      'current': current,
      'size': size,
    };
  }

  ResponseBody reply(
    Object? data, {
    bool raw = false,
    int code = 200,
    String msg = '本地模拟操作完成',
  }) => ResponseBody.fromString(
    jsonEncode(raw ? data : {'code': code, 'msg': msg, 'data': data}),
    code,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  ResponseBody missing() => reply(null, code: 404, msg: '本地模拟数据中没有此记录或操作');

  JsonMap _body(Object? data) => data is FormData
      ? {for (final field in data.fields) field.key: field.value}
      : jsonMap(data is String ? jsonDecode(data) : data);

  Future<List<JsonMap>> _attachments(Object? data) async {
    if (data is! FormData) return [];
    final result = <JsonMap>[];
    for (final file in data.files) {
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in file.value.clone().finalize()) {
        bytes.add(chunk);
      }
      final name = file.value.filename ?? 'photo.jpg';
      if (!RegExp(r'\.(jpe?g|png)$', caseSensitive: false).hasMatch(name) ||
          bytes.length == 0 ||
          bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('仅支持 JPG/PNG，单张不超过 10MB');
      }
      result.add({
        'id': _nextId,
        'filename': name,
        'mediaType': name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg',
        'localData': base64Encode(bytes.takeBytes()),
        'demo': true,
      });
    }
    return result;
  }

  bool _canReadEvent(JsonMap event) =>
      _admin ||
      event['personId'] == _personId ||
      (event['taskId'] == task['id'] &&
          event['source'] != 'manual_sos' &&
          jsonList(task['members']).any((m) => m['personId'] == _personId));
  List<JsonMap> get _visibleEvents {
    final rows = events.where(_canReadEvent).toList();
    int priority(JsonMap e) =>
        e['type'] == 'sos' && e['status'] != 'verified' ? 0 : 1;
    rows.sort((a, b) {
      final group = priority(a).compareTo(priority(b));
      return group != 0
          ? group
          : idOf(b['occurredAt']).compareTo(idOf(a['occurredAt']));
    });
    return rows;
  }

  ResponseBody forbidden() => reply(null, code: 403, msg: '当前模拟账号无此操作或数据权限');
  ResponseBody invalid(String msg) => reply(null, code: 400, msg: msg);

  bool _eventMatches(JsonMap event, Map<String, dynamic> query) {
    for (final key in [
      'type',
      'personId',
      'taskId',
      'claimantUserId',
      'alarmCode',
    ]) {
      final value = idOf(query[key]);
      if (value.isNotEmpty && value != idOf(event[key])) return false;
    }
    final status = idOf(query['status']);
    if (status == 'active' ||
        query['excludeClosed'] == true ||
        (status.isEmpty && idOf(query['statuses']).isEmpty)) {
      if (['verified', 'confirmed', 'closed'].contains(event['status'])) {
        return false;
      }
    } else if (status.isNotEmpty &&
        status != 'all' &&
        status != event['status']) {
      return false;
    }
    for (final entry in {
      'statuses': 'status',
      'types': 'type',
      'alarmCodes': 'alarmCode',
      'deviceTypes': 'deviceType',
    }.entries) {
      final values = idOf(query[entry.key]);
      if (values.isNotEmpty &&
          !values.split(',').contains(idOf(event[entry.value]))) {
        return false;
      }
    }
    final severity = idOf(query['severity']);
    if (severity.isNotEmpty && severity != event['severity']) return false;
    if (idOf(query['escalated']) == 'true' && event['escalated'] != true) {
      return false;
    }
    return true;
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    final p = o.path;
    final body = _body(o.data);
    final write = o.method != 'GET';
    if (p == '/captchaImage') {
      return reply({'code': 200, 'captchaEnabled': false}, raw: true);
    }
    if (p == '/login' && o.method == 'POST') {
      final name = textOf(body['username'], '');
      if (!['demo', 'member'].contains(name) || body['password'] != '123456') {
        return reply(null, code: 401, msg: '请使用指定模拟账号及密码 123456');
      }
      account = name;
      siteId = null;
      return reply({'code': 200, 'token': 'local-mock-only'}, raw: true);
    }
    if (p == '/logout') {
      siteId = null;
      return reply(null);
    }
    if (p == '/api/v1/me') return reply(identity);
    if (p == '/api/v1/sites') return reply(identity['authorizedSites']);
    if (p == '/api/v1/me/current-site') {
      final selected = idOf(body['siteId']);
      if (!(_admin ? ['1', '2'] : ['1']).contains(selected)) {
        return reply(null, code: 403, msg: '没有该模拟厂站');
      }
      siteId = selected;
      return reply({'currentSiteId': siteId});
    }
    if (p.contains('/inspection') ||
        p.startsWith('/api/v1/account-recovery') ||
        p.startsWith('/api/v1/lab/') ||
        p.startsWith('/api/v1/duty/') && p != '/api/v1/duty/summary') {
      return missing();
    }
    if (write && p.startsWith('/api/v1/work-tasks/')) return forbidden();
    if (!_admin &&
        (p.startsWith('/api/v1/assignments') ||
            write &&
                (p.startsWith('/api/v1/calls') ||
                    p.startsWith('/api/v1/commands')))) {
      return forbidden();
    }
    // Separate mutable business data by site; switching sites never leaks changes.
    final requestedSite = idOf(o.headers['X-Site-Id']);
    if (requestedSite.isNotEmpty &&
        !(_admin ? ['1', '2'] : ['1']).contains(requestedSite)) {
      return forbidden();
    }
    if (!_scoped && requestedSite.isNotEmpty) {
      final scoped = _scopes.putIfAbsent(requestedSite, () {
        final value = MockBackend(scoped: true);
        for (final event in value.events) {
          event['siteId'] = requestedSite;
        }
        return value;
      });
      scoped.account = account;
      scoped.siteId = requestedSite;
      return scoped.fetch(o, stream, cancelFuture);
    }
    if (p == '/api/v1/me/equipment') return reply(equipmentFor(_personId));
    if (p == '/api/v1/duty/summary') {
      return reply({
        'unclaimed': _visibleEvents.where((e) => e['status'] == 'open').length,
        'activeTasks': task['status'] == 'ended' ? [] : [task],
        'recentEvents': _visibleEvents,
        'pendingEvents': _visibleEvents
            .where(
              (e) => !['verified', 'confirmed', 'closed'].contains(e['status']),
            )
            .toList(),
        'myClaimed': _visibleEvents
            .where((e) => e['claimantUserId'] == _userId)
            .length,
        'onlineDevices': _admin
            ? devices.length
            : equipmentFor(_personId).length,
        'peopleCount': _admin ? people.length : 1,
        'deviceCount': _admin ? devices.length : equipmentFor(_personId).length,
        'lostSupervision': 0,
      });
    }
    final parts = p.split('/');
    if (p == '/api/v1/work-tasks' || p == '/api/v1/work-tasks/mine') {
      final status = idOf(o.queryParameters['status']);
      return reply(
        page(status.isEmpty || status == task['status'] ? [task] : [], o),
      );
    }
    if (p.startsWith('/api/v1/work-tasks/')) {
      if (parts[4] != task['id']) return missing();
      if (parts.length == 5) return reply(task);
      final action = parts[5];
      if (action == 'events') {
        return reply(
          _visibleEvents.where((e) => e['taskId'] == task['id']).toList(),
        );
      }
      if (action == 'equipment-check') {
        return reply([
          for (final member in jsonList(task['members']))
            for (final device in equipmentFor(idOf(member['personId'])))
              {...device, 'result': 'ok'},
        ]);
      }
      return missing();
    }
    if (p == '/api/v1/people/options') {
      return reply(
        people.where((p) => _admin || p['id'] == _personId).toList(),
      );
    }
    if (p == '/api/v1/people') {
      final name = textOf(o.queryParameters['name'], '');
      return reply(
        page(
          people
              .where(
                (r) =>
                    (_admin || r['id'] == _personId) &&
                    idOf(r['name']).contains(name),
              )
              .toList(),
          o,
        ),
      );
    }
    if (p.startsWith('/api/v1/people/')) {
      final person = people.where((r) => r['id'] == parts[4]).firstOrNull;
      if (person == null) return missing();
      if (!_admin && person['id'] != _personId) return forbidden();
      if (parts.length == 5) return reply(person);
      if (parts.last == 'equipment') return reply(equipmentFor(parts[4]));
      if (parts.last == 'assignments') {
        return reply(
          assignmentHistory.where((a) => a['personId'] == parts[4]).toList(),
        );
      }
      return missing();
    }
    if (p == '/api/v1/devices') {
      final query = o.queryParameters;
      return reply(
        page(
          devices
              .where(
                (r) =>
                    (_admin ||
                        jsonMap(r['currentAssignment'])['personId'] ==
                            _personId) &&
                    idOf(r['sn']).contains(textOf(query['sn'], '')) &&
                    (idOf(query['typeCode']).isEmpty ||
                        r['typeCode'] == query['typeCode']) &&
                    (idOf(query['assetStatus']).isEmpty ||
                        r['assetStatus'] == query['assetStatus']),
              )
              .toList(),
          o,
        ),
      );
    }
    if (p.startsWith('/api/v1/devices/')) {
      final device = devices.where((r) => r['id'] == parts[4]).firstOrNull;
      if (device == null) return missing();
      if (!_admin &&
          jsonMap(device['currentAssignment'])['personId'] != _personId) {
        return forbidden();
      }
      if (parts.length == 5) return reply(device);
      if (parts.last == 'assignments') {
        return reply(
          assignmentHistory
              .where((a) => a['deviceId'] == device['id'])
              .toList(),
        );
      }
      if (parts.last == 'calls') {
        return reply(
          calls.values.where((r) => r['deviceId'] == device['id']).toList(),
        );
      }
      return missing();
    }
    if (p == '/api/v1/assignments' && write) {
      final device = devices
          .where((r) => r['id'] == body['deviceId'])
          .firstOrNull;
      final person = people
          .where((r) => r['id'] == body['personId'])
          .firstOrNull;
      if (device == null || person == null) return missing();
      if (device['currentAssignment'] != null) {
        return reply(null, code: 409, msg: '此模拟装备已分配');
      }
      final assignment = {
        'id': _nextId,
        'personId': person['id'],
        'personName': person['name'],
        'deviceId': device['id'],
        'sn': device['sn'],
        'typeCode': device['typeCode'],
        'assignedAt': _now,
        'returnedAt': null,
      };
      assignmentHistory.add(assignment);
      device.addAll({'currentAssignment': assignment, 'assetStatus': 'issued'});
      return reply(assignment);
    }
    if (p.startsWith('/api/v1/assignments/') &&
        parts.last == 'return' &&
        write) {
      final device = devices
          .where((r) => jsonMap(r['currentAssignment'])['id'] == parts[4])
          .firstOrNull;
      if (device == null) return missing();
      final history = assignmentHistory
          .where((a) => a['id'] == parts[4])
          .firstOrNull;
      if (history != null) history['returnedAt'] = _now;
      device.addAll({'currentAssignment': null, 'assetStatus': 'in_stock'});
      return reply({'demo': true});
    }
    if (p == '/api/v1/events/filter-options') {
      return reply([
        for (final event in _visibleEvents)
          {
            'type': event['type'],
            'deviceType': event['deviceType'],
            'code': event['alarmCode'] ?? event['type'],
            'label': event['alarmName'],
            'severity': event['severity'],
          },
      ]);
    }
    if (p == '/api/v1/events/manual-sos' && write) {
      final requestId = idOf(body['requestId']);
      if (requestId.isEmpty) return invalid('求助请求编号不能为空');
      if (textOf(body['description'], '').length > 500 ||
          textOf(body['location'], '').length > 200) {
        return invalid('描述过长');
      }
      final request = '$_userId:$requestId';
      final previous = _requests[request];
      if (previous != null) {
        return reply(events.firstWhere((r) => r['id'] == previous));
      }
      final event = _newEvent(body, type: 'sos');
      if (request.isNotEmpty) _requests[request] = idOf(event['id']);
      return reply(event);
    }
    if (p == '/api/v1/events/inbox/count') {
      return reply({
        'count': _visibleEvents
            .where(
              (e) => !['verified', 'confirmed', 'closed'].contains(e['status']),
            )
            .length,
      });
    }
    if (p == '/api/v1/events') {
      return reply(
        page(
          _visibleEvents
              .where((e) => _eventMatches(e, o.queryParameters))
              .toList(),
          o,
        ),
      );
    }
    if (p.startsWith('/api/v1/events/')) {
      final event = events.where((r) => r['id'] == parts[4]).firstOrNull;
      if (event == null) return missing();
      if (!_canReadEvent(event)) return forbidden();
      if (parts.length == 5 && !write) return reply(event);
      final action = parts.skip(5).join('/');
      if (!write) {
        if (action == 'media') return reply(_media[idOf(event['id'])] ?? []);
        if (action == 'actions') return reply(actions[idOf(event['id'])] ?? []);
        if (action == 'calls') {
          return reply(
            calls.values.where((r) => r['eventId'] == event['id']).toList(),
          );
        }
        return missing();
      }
      if (![
        'claim',
        'report',
        'verification-draft',
        'verify',
        'assistance/join',
        'assistance/end',
      ].contains(action)) {
        return missing();
      }
      if (action != 'report' && !_admin) return forbidden();
      if (intOf(body['version'], -1) != intOf(event['version'])) {
        return reply(null, code: 409, msg: '模拟记录已更新，请刷新核对后重试');
      }
      final active = [
        'open',
        'field_pending',
        'claimed',
        'handling',
      ].contains(event['status']);
      if (!active && action != 'assistance/end') {
        return reply(null, code: 409, msg: '已核验记录只读');
      }
      if (action == 'claim' &&
          !['open', 'field_pending'].contains(event['status'])) {
        return reply(null, code: 409, msg: '事件已认领');
      }
      final comment = textOf(body['comment'], '').trim();
      final conclusion = textOf(body['conclusion'], '').trim();
      final situation = textOf(body['situation'], '').trim();
      final measures = textOf(body['measures'], '').trim();
      if ([comment, situation, measures].any((v) => v.length > 500)) {
        return invalid('文字不超过 500 字');
      }
      if (action == 'report' && comment.isEmpty) return invalid('请填写现场情况');
      if (action == 'verify' &&
          (!['设备通信异常', '需现场处理', '暂无法确认'].contains(conclusion) ||
              situation.isEmpty)) {
        return invalid('请选择核验结论并填写现场情况');
      }
      final assistance = jsonMap(event['assistance']);
      if (action.startsWith('assistance/')) {
        if (event['type'] != 'sos') return invalid('仅 SOS 事件具有协助记录');
        if (action == 'assistance/join' && assistance['state'] == 'ended' ||
            action == 'assistance/end' && assistance['state'] != 'active') {
          return reply(null, code: 409, msg: '协助状态已变更');
        }
      }
      List<JsonMap> photos;
      try {
        photos = await _attachments(o.data);
      } on FormatException catch (error) {
        return invalid(error.message);
      }
      // Check again after asynchronous file reads to prevent two concurrent writes.
      if (intOf(body['version'], -1) != intOf(event['version'])) {
        return reply(null, code: 409, msg: '模拟记录已更新，请刷新核对后重试');
      }
      final from = event['status'];
      final timestamp = _now;
      switch (action) {
        case 'claim':
          event.addAll({'status': 'handling', 'claimantUserId': _userId});
          if (event['type'] == 'sos' && assistance['state'] == 'waiting') {
            event['assistance'] = {
              ...assistance,
              'state': 'accepted',
              'acceptedBy': _name,
              'acceptedAt': timestamp,
            };
          }
        case 'report':
          event['observations'] = [
            ...jsonList(event['observations']),
            {
              'id': _nextId,
              'actor': _name,
              'userId': _userId,
              'comment': comment,
              'createdAt': timestamp,
              'photos': photos,
            },
          ];
        case 'verification-draft':
        case 'verify':
          final verification = {
            'conclusion': conclusion,
            'situation': situation,
            'measures': measures,
            'actor': _name,
            'userId': _userId,
            'createdAt': timestamp,
            'photos': [
              ...jsonList(jsonMap(event['verificationDraft'])['photos']),
              ...photos,
            ],
          };
          if (action == 'verify') {
            event.addAll({
              'verification': verification,
              'status': 'verified',
              'verificationStatus': 'verified',
              'verificationDraft': <String, dynamic>{},
            });
          } else {
            event['verificationDraft'] = verification;
          }
        case 'assistance/join':
          final members = <String>{
            ...((assistance['members'] as List? ?? []).map(idOf)),
            _userId,
          }.toList();
          event['assistance'] = {
            ...assistance,
            'state': 'active',
            'members': members,
            'startedAt': assistance['startedAt'] ?? timestamp,
          };
          if (['open', 'field_pending'].contains(event['status'])) {
            event.addAll({'status': 'handling', 'claimantUserId': _userId});
          }
        case 'assistance/end':
          event['assistance'] = {
            ...assistance,
            'state': 'ended',
            'endedAt': timestamp,
            'endedBy': _name,
          };
      }
      _media.putIfAbsent(idOf(event['id']), () => []).addAll(photos);
      event['version'] = intOf(event['version']) + 1;
      (actions[idOf(event['id'])] ??= []).add({
        'id': _nextId,
        'action': action,
        'actor': _name,
        'userId': _userId,
        'reason':
            '${const {'claim': '认领事件', 'report': '补充现场情况', 'verification-draft': '保存核验草稿', 'verify': '提交最终核验', 'assistance/join': '接警并加入协助', 'assistance/end': '结束协助'}[action]}（本地模拟）${comment.isEmpty ? '' : '：$comment'}',
        'fromStatus': from,
        'toStatus': event['status'],
        'createTime': timestamp,
      });
      return reply(event);
    }
    if (p == '/api/v1/calls' && write) {
      if (body['video'] == true) return invalid('本轮仅支持设备语音');
      final id = _nextId;
      final call = {
        ...body,
        'id': id,
        'requesterUserId': _userId,
        'siteId': siteId,
        'demo': true,
        'status': 'offered',
        'sn': 'RL-H001',
        'startedAt': _now,
      };
      calls[id] = call;
      return reply(call);
    }
    if (p.startsWith('/api/v1/calls/')) {
      final call = calls[parts[4]];
      if (call == null) return missing();
      if (parts.last == 'credentials') return reply({'demo': true});
      if (parts.last == 'end' && write) {
        call['status'] = 'ended';
        call['endedAt'] = _now;
      }
      return reply(call);
    }
    if (p == '/api/v1/commands/tts' && write) {
      return reply([
        for (final id in (body['deviceIds'] as List? ?? []))
          {
            'id': _nextId,
            'deviceId': id,
            'status': 'accepted',
            'demo': true,
            'vendorMsg': '本地模拟，未向真实设备发送或播放',
            'text': body['text'],
          },
      ]);
    }
    if (p.startsWith('/api/v1/locations/people/')) {
      return reply({
        'personId': parts.last,
        'lat': 30.2741,
        'lng': 120.1551,
        'locationQuality': 'demo',
        'occurredAt': _now,
        'demo': true,
      });
    }
    return missing();
  }

  JsonMap _newEvent(JsonMap body, {required String type}) {
    final event = <String, dynamic>{
      'id': _nextId,
      'type': type,
      'severity': type == 'sos' ? 'emergency' : 'abnormal',
      'alarmName': '人员求助',
      'alarmDescription': textOf(body['description'], '').trim().isEmpty
          ? '位置和现场情况待补充'
          : body['description'],
      'description': body['description'],
      'location': body['location'],
      'status': 'open',
      'version': 1,
      'siteId': siteId ?? '1',
      'personId': _personId,
      'personName': _name,
      'reporterUserId': _userId,
      'taskId': '',
      'deviceId': '',
      'sn': '',
      'deviceType': '',
      'observations': <JsonMap>[],
      'verification': <String, dynamic>{},
      'verificationDraft': <String, dynamic>{},
      'assistance': {'state': 'waiting', 'members': <String>[]},
      'source': type == 'sos' ? 'manual_sos' : 'inspection',
      'occurredAt': _now,
      'receivedAt': _now,
      'demo': true,
      'externalClosureStatus': 'unknown',
      'verificationStatus': 'pending',
    };
    events.insert(0, event);
    return event;
  }

  @override
  void close({bool force = false}) {}
}
