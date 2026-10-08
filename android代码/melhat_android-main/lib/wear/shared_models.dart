import 'data.dart';

/// Only a presentation projection. Identifiers and versions always come from Spring.
class SharedModels {
  SharedModels(this.state);
  final JsonMap state;
  List<JsonMap> rows(String key) => jsonList(state[key]);
  JsonMap find(String key, Object? id) =>
      rows(key).where((r) => idOf(r['id']) == idOf(id)).firstOrNull ?? {};
  String personId(Object? ledgerId) =>
      rows('people')
          .where((p) => p['ledgerId'] == ledgerId)
          .map((p) => idOf(p['id']))
          .firstOrNull ??
      idOf(ledgerId);
  String deviceId(Object? ledgerId) =>
      rows('devices')
          .where((p) => p['ledgerId'] == ledgerId)
          .map((p) => idOf(p['id']))
          .firstOrNull ??
      idOf(ledgerId);
  static String type(Object? t) =>
      const {
        'H': 'helmet',
        'B': 'belt',
        'W': 'watch',
        'HELMET': 'helmet',
        'BELT': 'belt',
        'WATCH': 'watch',
      }[t] ??
      idOf(t);
  static const eventTypes = {
    '人员求助': 'sos',
    '电子围栏': 'geofence',
    '设备通信': 'communication',
    '低电量': 'battery',
    '位置异常': 'location',
    '安全带挂接': 'belt',
    '生命体征': 'vitals',
  };
  static const statuses = {
    '待认领': 'open',
    '待现场核验': 'field_pending',
    '处理中': 'handling',
    '已核验': 'verified',
  };

  JsonMap person(JsonMap p) => {
    ...p,
    'personCode': p['code'] ?? p['id'],
    'teamName': p['team'],
    'status': p['active'] == false ? '1' : '0',
  };
  JsonMap device(JsonMap d) {
    final a = rows('assignments')
        .where((a) => a['active'] == true && a['deviceId'] == d['ledgerId'])
        .firstOrNull;
    final realTelemetry = d['source'] == 'PLATFORM';
    return {
      ...d,
      'deviceId': d['id'],
      'sn': d['id'],
      'typeCode': type(d['type']),
      'modelName': d['name'],
      'status': d['active'] == false ? '1' : '0',
      'assetStatus':
          const {
            'STOCK': 'in_stock',
            'IN_USE': 'issued',
            'MAINTENANCE': 'maintenance',
            'DISABLED': 'disabled',
            'SCRAPPED': 'scrapped',
          }[d['lifecycle']] ??
          'unassigned',
      'online': realTelemetry
          ? (d['online'] == true
                ? 1
                : d['online'] == false
                ? 0
                : null)
          : null,
      'connectionQuality': realTelemetry && d['online'] != null
          ? 'ok'
          : 'unknown',
      'battery': realTelemetry ? d['battery'] : null,
      'batteryLevel': realTelemetry ? d['battery'] : null,
      'telemetryNote': realTelemetry ? '设备平台状态' : '暂无真实遥测，后台台账已同步',
      'capabilities': {
        'actions': realTelemetry && d['active'] != false && d['type'] == 'H'
            ? ['intercom', 'tts']
            : [],
        'metrics': <String>[],
      },
      'currentAssignment': a == null ? null : assignment(a),
    };
  }

  JsonMap assignment(JsonMap a) {
    final d = find('devices', deviceId(a['deviceId']));
    final p = find('people', personId(a['personId']));
    // Returned devices leave the employee's live device scope. Use the already
    // authorized ledger history snapshot, never fetch another owner's device.
    final history =
        rows('assignmentHistory')
            .where(
              (h) =>
                  h['assignmentId'] == a['id'] &&
                  h['personId'] == a['personId'],
            )
            .firstOrNull ??
        <String, dynamic>{};
    final startedAt = a['startedAt'] ?? history['startedAt'];
    return {
      ...a,
      'deviceId': deviceId(a['deviceId']),
      'personId': personId(a['personId']),
      'ledgerPersonId': a['personId'],
      'ledgerDeviceId': a['deviceId'],
      'personName': p['name'] ?? a['personName'],
      'sn':
          d['id'] ?? a['deviceCode'] ?? history['deviceCode'] ?? a['deviceId'],
      'typeCode': type(d['type'] ?? a['type'] ?? history['type']),
      'assignedAt': startedAt,
      'issuedAt': startedAt,
      'returnedAt': a['endedAt'],
      'deviceVersion': d['version'],
      'personVersion': p['version'],
    };
  }

  List<JsonMap> equipment(String id) => rows('assignments')
      .where((a) => a['active'] == true && personId(a['personId']) == id)
      .map(assignment)
      .toList();
  JsonMap work(JsonMap w) => {
    ...w,
    'title': w['name'],
    'status': w['status'] == '已结束'
        ? 'ended'
        : w['status'] == '待开始'
        ? 'ready'
        : 'in_progress',
    'spaceName': w['area'],
    'workType': w['category'] ?? w['type'],
    'ownerUserId': '',
    'ownerPersonId': w['leader'],
    'ownerName':
        jsonMap(w['participantNames'])[idOf(w['leader'])] ??
        find('people', w['leader'])['name'],
    'guardianPersonId': w['supervisor'],
    'guardianName':
        jsonMap(w['participantNames'])[idOf(w['supervisor'])] ??
        find('people', w['supervisor'])['name'],
    'ticketNo': w['id'],
    'ticketRequired': true,
    'ticketStatus': w['source'] == '工作票' ? 'provided' : 'unverified',
    'sourceName': w['source'],
    'sourceStatus': w['synced'] == true ? '已同步' : '待同步',
    'demo': idOf(w['sync']).contains('示例'),
    'plannedStartAt': '${w['date']}T${w['start']}:00+08:00',
    'plannedEndAt': '${w['date']}T${w['end']}:00+08:00',
    'members': [
      (w['members'] as List? ?? []).map(
        (id) => {
          'personId': id,
          'name':
              jsonMap(w['participantNames'])[idOf(id)] ??
              find('people', id)['name'] ??
              '作业成员（资料未授权）',
          'personCode': find('people', id)['code'] ?? id,
        },
      ),
    ].expand((r) => r).toList(),
  };
  JsonMap event(JsonMap e) {
    final a = jsonMap(
      e['assistance'] ?? jsonMap(state['assistance'])[idOf(e['id'])],
    );
    final snapshot = jsonMap(e['snapshot']);
    return {
      ...e,
      'type': eventTypes[e['type']] ?? e['type'],
      'status': statuses[e['status']] ?? e['status'],
      'severity': e['type'] == '人员求助' ? 'emergency' : 'abnormal',
      'occurredAt': e['createdAt'] ?? '${e['date']}T${e['time']}+08:00',
      'receivedAt': e['createdAt'] ?? '${e['date']}T${e['time']}+08:00',
      'personName':
          snapshot['personName'] ?? find('people', e['personId'])['name'],
      'personCode': find('people', e['personId'])['code'] ?? e['personId'],
      'sn': e['deviceId'],
      'deviceType': type(find('devices', e['deviceId'])['type']),
      'taskId': e['workId'],
      'claimantUserId': e['claimedBy'],
      'sourceEventId': e['externalId'],
      'externalClosureStatus': 'not_synced',
      'alarmCode': eventTypes[e['type']] ?? e['type'],
      'alarmName': e['title'],
      'alarmDescription': e['description'] ?? e['title'],
      'location': e['locationDescription'],
      'locationQuality': 'unknown',
      'verificationDraft': e['draft'],
      'verification': {
        ...jsonMap(e['verification']),
        'actor': jsonMap(e['verification'])['actorName'],
        'createdAt': jsonMap(e['verification'])['submittedAt'],
      },
      'verificationStatus': e['status'] == '已核验' ? 'verified' : 'pending',
      'assistance': {...a, 'state': a['status']},
      'observations': [
        for (final o in jsonList(e['observations']))
          {
            ...o,
            'actor': o['actorName'],
            'userName': o['actorName'],
            'comment': o['situation'],
          },
      ],
    };
  }

  static JsonMap identity(JsonMap native, String? siteId) {
    final site =
        siteId ??
        (jsonList(native['sites']).length == 1
            ? idOf(jsonList(native['sites']).single['id'])
            : '');
    final operations =
        (jsonMap(native['permissionsBySite'])[site] as List? ?? [])
            .map(idOf)
            .toSet();
    final manager = operations.any(
      (p) => const ['events:read', 'assets:write', 'people:read'].contains(p),
    );
    final permission = <String>{'wear:site:list', 'wear:site:select'};
    void grant(String operation, List<String> permissions) {
      if (operations.contains(operation)) permission.addAll(permissions);
    }

    grant('self:read', [
      'wear:person:list',
      'wear:person:query',
      'wear:device:list',
      'wear:device:query',
      'wear:event:list',
      'wear:event:query',
    ]);
    grant('people:read', ['wear:person:list', 'wear:person:query']);
    grant('assets:read', ['wear:device:list', 'wear:device:query']);
    grant('assets:write', ['wear:assignment:issue', 'wear:assignment:return']);
    grant('works:read', ['wear:task:list', 'wear:task:query']);
    grant('events:read', ['wear:event:list', 'wear:event:query']);
    grant('events:observe', ['wear:event:report']);
    grant('events:claim', ['wear:event:claim']);
    grant('events:verify', ['wear:event:review']);
    grant('sos:assist', ['wear:sos:assist']);
    grant('communications:voice', ['wear:call:start']);
    grant('communications:broadcast', ['wear:command:tts']);
    return {
      ...native,
      'userId': native['accountId'],
      'userName': native['loginName'],
      'nickName': native['name'],
      'status': '0',
      'admin': manager,
      'roles': manager ? ['admin'] : ['member'],
      'permissions': permission.toList(),
      'currentSiteId': site,
      'authorizedSites': [
        for (final s in jsonList(native['sites'])) {...s, 'status': '0'},
      ],
      'sharedOperations': operations.toList(),
    };
  }
}
