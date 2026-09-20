import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../wear/core.dart';

class PreviewCredentials implements CredentialStore {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String? token) async => _token = token;
}

WearSession createPreviewSession() => WearSession(
  credentials: PreviewCredentials(),
  dio: Dio(BaseOptions(baseUrl: 'https://preview.invalid'))
    ..httpClientAdapter = PreviewAdapter(),
);

/// All requests terminate here; no network adapter or production credentials.
class PreviewAdapter implements HttpClientAdapter {
  String account = 'demo';
  String? siteId;
  final actions = <String, List<JsonMap>>{};
  final handovers = <JsonMap>[];
  final calls = <String, JsonMap>{};
  final people = <JsonMap>[
    {
      'id': '101',
      'name': '陈建国',
      'personCode': 'P-001',
      'status': 'active',
      'phone': '138****0101',
      'teamName': '设备检修班',
    },
    {
      'id': '102',
      'name': '周明',
      'personCode': 'P-002',
      'status': 'active',
      'phone': '138****0102',
      'teamName': '设备检修班',
    },
    {
      'id': '103',
      'name': '李志远',
      'personCode': 'P-003',
      'status': 'active',
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
      'status': 'active',
      'battery': 86,
      'batteryLevel': 86,
      'demo': true,
      'capabilities': {
        'actions': ['intercom', 'video', 'monitor', 'tts'],
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
      'status': 'active',
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
      'status': 'active',
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
    'title': '东区巡检',
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
      'severity': 'medium',
      'status': 'claimed',
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
      'severity': 'critical',
      'status': 'open',
      'occurredAt': '2026-09-17T10:39:00+08:00',
      'receivedAt': '2026-09-17T10:39:01+08:00',
      'personId': '102',
      'personName': '周明',
      'personCode': 'P-002',
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

  List<JsonMap> get equipment => devices
      .map(
        (d) => <String, dynamic>{
          ...d,
          'deviceId': d['id'],
          'personId': '101',
          'personName': '陈建国',
          'assignedAt': '2026-09-17T08:30:00+08:00',
          'typeName': d['modelName'],
        },
      )
      .toList();
  JsonMap get identity => {
    'userId': '12',
    'userName': account,
    'username': account,
    'nickName': '陈建国',
    'name': '陈建国',
    'personId': '101',
    'sipId': '10001',
    'status': '0',
    'roles': ['wear_duty', 'wear_team_lead', 'wear_reviewer'],
    'permissions': ['*:*:*', 'wear:call:start', 'wear:command:tts'],
    'authorizedSites': [
      {'id': '1', 'status': '0', 'name': '演示厂站A'},
      {'id': '2', 'status': '0', 'name': '演示厂站B'},
    ],
    'currentSiteId': siteId,
  };
  JsonMap page(List<JsonMap> rows, RequestOptions o) {
    final current = intOf(o.queryParameters['current'], 1);
    final size = intOf(o.queryParameters['size'], 20);
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
    String msg = '演示操作成功',
  }) => ResponseBody.fromString(
    jsonEncode(raw ? data : {'code': code, 'msg': msg, 'data': data}),
    code,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    final p = o.path;
    final body = jsonMap(o.data);
    if (p == '/captchaImage') {
      return reply({
        'code': 200,
        'captchaEnabled': true,
        'uuid': 'local-preview',
      }, raw: true);
    }
    if (p == '/login') {
      account = textOf(body['username']);
      siteId = null;
      return reply({'code': 200, 'token': 'local-preview-only'}, raw: true);
    }
    if (p == '/logout') return reply(null);
    if (p == '/api/v1/me') return reply(identity);
    if (p == '/api/v1/me/current-site') {
      siteId = idOf(body['siteId']);
      return reply({'currentSiteId': siteId});
    }
    if (p == '/api/v1/events/inbox/count') {
      return reply({
        'count': events.where((e) => e['status'] != 'closed').length,
      });
    }
    if (p == '/api/v1/duty/summary') {
      return reply({
        'unclaimed': 1,
        'activeTasks': [task],
        'recentEvents': events,
        'pendingEvents': events,
        'myClaimed': 1,
        'onlineDevices': 3,
      });
    }
    if (p == '/api/v1/duty/operators') {
      return reply([
        {'userId': '12', 'nickName': '陈建国', 'name': '陈建国'},
        {'userId': '13', 'nickName': '李志远', 'name': '李志远'},
      ]);
    }
    if (p == '/api/v1/duty/handovers') {
      if (o.method != 'GET') {
        handovers.add({
          ...body,
          'id': '${handovers.length + 1}',
          'status': 'pending',
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
      return reply(o.method == 'GET' ? handovers : handovers.last);
    }
    if (p.startsWith('/api/v1/duty/handovers/')) {
      return reply({'status': 'confirmed'});
    }
    if (p.endsWith('/equipment')) return reply(equipment);
    if (p == '/api/v1/work-tasks' || p == '/api/v1/work-tasks/mine') {
      return reply(page([task], o));
    }
    if (p.endsWith('/equipment-check')) {
      return reply(equipment.map((e) => {...e, 'result': 'ok'}).toList());
    }
    if (p.startsWith('/api/v1/work-tasks/')) {
      return reply(p.endsWith('/events') ? events : task);
    }
    if (p == '/api/v1/people/options') return reply(people);
    if (p == '/api/v1/people') {
      final name = textOf(o.queryParameters['name'], '');
      return reply(
        page(
          people.where((e) => e['name'].toString().contains(name)).toList(),
          o,
        ),
      );
    }
    if (p.startsWith('/api/v1/people/')) {
      return reply(
        p.endsWith('/assignments')
            ? equipment
            : people.firstWhere(
                (e) => e['id'] == p.split('/').last,
                orElse: () => people.first,
              ),
      );
    }
    if (p == '/api/v1/devices') return reply(page(devices, o));
    if (p.endsWith('/calls') && o.method == 'GET') {
      return reply(calls.values.toList());
    }
    if (p.startsWith('/api/v1/devices/')) {
      return reply(
        p.endsWith('/assignments')
            ? equipment
            : devices.firstWhere(
                (e) => e['id'] == p.split('/').last,
                orElse: () => devices.first,
              ),
      );
    }
    if (p == '/api/v1/events') {
      final filtered = events.where((e) {
        for (final k in [
          'type',
          'status',
          'personId',
          'taskId',
          'claimantUserId',
        ]) {
          final v = idOf(o.queryParameters[k]);
          if (v.isNotEmpty && idOf(e[k]) != v) return false;
        }
        if (o.queryParameters['excludeClosed'] == true &&
            e['status'] == 'closed') {
          return false;
        }
        return true;
      }).toList();
      return reply(page(filtered, o));
    }
    if (p.startsWith('/api/v1/events/')) {
      final parts = p.split('/');
      final event = events.where((e) => e['id'] == parts[4]).firstOrNull;
      if (event == null) return reply(null, code: 404, msg: '没有该演示事件');
      if (parts.length == 5) return reply(event);
      final action = parts.last;
      if (action == 'actions') return reply(actions[event['id']] ?? []);
      if (o.method != 'GET') {
        event['version'] = intOf(event['version']) + 1;
        if (action == 'claim') {
          event['status'] = 'claimed';
          event['claimantUserId'] = '12';
        }
        if (action == 'handle') event['status'] = 'handled';
        if (action == 'close') event['status'] = 'closed';
        if (action == 'reopen') event['status'] = 'open';
        if (action == 'assign-task') event['taskId'] = body['taskId'];
        if (action == 'transfer') {
          event['claimantUserId'] = body['targetUserId'];
        }
        (actions[event['id']] ??= []).add({
          'id': '${event['version']}',
          'action': action,
          'actorUserId': '12',
          'actorName': '陈建国',
          'comment': body['comment'],
          'createdAt': DateTime.now().toIso8601String(),
        });
        return reply(event);
      }
    }
    if (p == '/api/v1/calls') {
      final id = '${calls.length + 1}';
      calls[id] = {
        ...body,
        'id': id,
        'requesterUserId': '12',
        'siteId': siteId,
        'demo': true,
        'status': 'offered',
        'sn': 'RL-H001',
        'startedAt': DateTime.now().toIso8601String(),
      };
      return reply(calls[id]);
    }
    if (p.startsWith('/api/v1/calls/')) {
      final call = calls[p.split('/')[4]];
      if (call != null && p.endsWith('/end')) call['status'] = 'ended';
      return reply(call ?? {'demo': true});
    }
    if (p == '/api/v1/commands/tts') {
      return reply([
        {'id': 'demo-tts', 'status': 'demo', 'demo': true, ...body},
      ]);
    }
    if (p == '/api/v1/fences') {
      return reply(
        page([
          {
            'id': '501',
            'name': '东区作业围栏',
            'status': 'active',
            'type': 'restricted',
          },
        ], o),
      );
    }
    if (p.startsWith('/api/v1/fences/')) {
      return reply({
        'id': '501',
        'name': '东区作业围栏',
        'status': 'active',
        'type': 'restricted',
        'geometry': null,
      });
    }
    if (p.contains('/tracks')) return reply([]);
    return reply(null, code: 404, msg: '网页演示暂未提供此操作');
  }

  @override
  void close({bool force = false}) {}
}
