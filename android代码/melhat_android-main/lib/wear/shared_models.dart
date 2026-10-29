import 'data.dart';
import 'demo_visibility.dart';
import 'device_features.dart';
import 'person_equipment_context.dart';

/// Only a presentation projection. Identifiers and versions always come from Spring.
class SharedModels {
  SharedModels(JsonMap state) : state = visibleBusinessState(state);
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
    'personEquipmentContext': jsonMap(
      jsonMap(state['personEquipmentContext'])[idOf(p['id'])],
    ),
    'personCode': p['code'] ?? p['id'],
    'teamName': p['team'],
    'status': p['active'] == false ? '1' : '0',
  };
  JsonMap device(JsonMap d) {
    final demoWatch = isDemoWatch(d);
    final equipmentContext = equipmentContextForDevice(state, idOf(d['id']));
    final a = rows('assignments')
        .where((a) => a['active'] == true && a['deviceId'] == d['ledgerId'])
        .firstOrNull;
    final realTelemetry = const [
      'PLATFORM',
      'DIRECT_HELMET',
      'DIRECT_BELT',
    ].contains(d['source']);
    final freshness = idOf(d['freshness']).toUpperCase();
    final observed = DateTime.tryParse(idOf(d['sourceTime'] ?? d['updated']));
    final age = observed == null ? null : DateTime.now().difference(observed);
    final current =
        realTelemetry &&
        freshness == 'CURRENT' &&
        age != null &&
        !age.isNegative &&
        age <= const Duration(minutes: 5);
    final stale =
        realTelemetry &&
        (freshness == 'STALE' ||
            (age != null && age > const Duration(minutes: 5)));
    final nativeCapabilities = d['capabilities'];
    final declaredActions = nativeCapabilities is List
        ? nativeCapabilities
        : jsonMap(nativeCapabilities)['actions'] as List? ?? const [];
    final declaredMetrics = nativeCapabilities is List
        ? nativeCapabilities
              .where(
                (metric) =>
                    const ['battery', 'wear', 'location'].contains(metric),
              )
              .toList()
        : jsonMap(nativeCapabilities)['metrics'] as List? ?? const [];
    final protocol = idOf(
      d['mediaProtocol'] ?? d['communicationProtocol'],
    ).toUpperCase();
    final rtcSupported =
        protocol == 'SIP' ||
        protocol == 'AGORA' ||
        (protocol.isEmpty && d['source'] == 'PLATFORM');
    bool fieldCurrent(String field) =>
        d['source'] != 'DIRECT_HELMET' ||
        idOf(d['${field}Freshness']).toUpperCase() == 'CURRENT';
    final features = <String, JsonMap>{
      for (final key in deviceFeatureLabels.keys)
        key: deviceFeature(d, key).toJson(),
    };
    for (final key in [
      'voice',
      'video',
      'videoCall',
      'photo',
      'recording',
      'broadcast',
    ]) {
      features[key] = contextualFeature(d, equipmentContext, key);
      if (!current || d['online'] != true || d['active'] == false) {
        features[key]!['available'] = false;
        if (features[key]!['verified'] == true) {
          features[key]!['reason'] = '设备离线或状态已过期';
        }
      }
    }
    final actions =
        current &&
            d['online'] == true &&
            d['active'] != false &&
            d['type'] == 'H'
        ? declaredActions
              .where(
                (action) =>
                    actionFeature({
                      'featureStates': features,
                    }, idOf(action)).available &&
                    (action == 'tts' ||
                        (action == 'intercom' && rtcSupported) ||
                        (action == 'video' &&
                            protocol == 'SIP' &&
                            d['mediaAvailable'] == true)),
              )
              .map(idOf)
              .toSet()
              .toList()
        : <String>[];
    final rawBattery = d['battery'];
    final battery = rawBattery is num
        ? rawBattery
        : num.tryParse(idOf(rawBattery));
    final validBattery =
        battery != null && battery.isFinite && battery >= 0 && battery <= 100;
    final site = jsonList(
      jsonMap(state['operator'])['sites'],
    ).where((site) => idOf(site['id']) == idOf(d['siteId'])).firstOrNull;
    return {
      ...d,
      if (demoWatch) 'demo': true,
      if (isWatchRecord(d) && hasRealDeviceSource(d)) 'demo': false,
      'deviceId': d['id'],
      'sn': textOf(d['sn'], textOf(d['deviceNumber'], idOf(d['id']))),
      'typeCode': type(d['type']),
      'modelName': d['name'],
      'siteName': d['siteName'] ?? site?['name'],
      // sourceTime is the server's last received device report. A ledger edit or
      // a stored location must not imply that the device reported again.
      'lastReportedAt':
          d['lastReportedAt'] ?? (realTelemetry ? d['sourceTime'] : null),
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
      'online': demoWatch
          ? (d['online'] == true
                ? 1
                : d['online'] == false
                ? 0
                : null)
          : realTelemetry && d['online'] == false
          ? 0
          : current
          ? (d['online'] == true
                ? 1
                : d['online'] == false
                ? 0
                : null)
          : null,
      'connectionQuality': demoWatch && d['online'] is bool
          ? 'ok'
          : realTelemetry && d['online'] == false
          ? 'ok'
          : stale
          ? 'stale'
          : current && d['online'] != null
          ? 'ok'
          : 'unknown',
      'battery':
          (demoWatch || current && fieldCurrent('battery')) && validBattery
          ? battery
          : null,
      'batteryLevel':
          (demoWatch || current && fieldCurrent('battery')) && validBattery
          ? battery
          : null,
      'worn': current && fieldCurrent('isWeared') && d['worn'] is bool
          ? d['worn']
          : null,
      'hookAEngaged': current && d['hookAEngaged'] is bool
          ? d['hookAEngaged']
          : null,
      'hookBEngaged': current && d['hookBEngaged'] is bool
          ? d['hookBEngaged']
          : null,
      'telemetryNote': demoWatch
          ? '智能手表示例数据 · 非实测'
          : d['source'] == 'DIRECT_BELT'
          ? '安全带直接上报；佩戴及挂钩状态含义以厂家确认结果为准'
          : d['source'] == 'DIRECT_HELMET'
          ? '安全帽直接上报；通信能力以已接入协议为准'
          : realTelemetry
          ? '设备平台状态'
          : '暂无真实遥测，后台台账已同步',
      'capabilities': {
        'actions': actions,
        'metrics': realTelemetry ? declaredMetrics : const [],
      },
      'featureStates': features,
      'equipmentContext': equipmentContext,
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
      'sn': textOf(
        d['sn'],
        textOf(
          d['deviceNumber'],
          textOf(
            d['id'],
            idOf(a['deviceCode'] ?? history['deviceCode'] ?? a['deviceId']),
          ),
        ),
      ),
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
    'simulatedWatchVisible':
        jsonMap(state['businessConfig'])['simulatedWatchVisible'] != false,
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
    'sourceStatus': textOf(
      w['externalStatus'],
      textOf(w['sourceStatus'], '未接入'),
    ),
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
      'sn': e['sn'] ?? snapshot['deviceSn'] ?? e['deviceId'],
      'deviceType': type(find('devices', e['deviceId'])['type']),
      'taskId': e['workId'],
      'claimantUserId': e['claimedBy'],
      'sourceEventId': e['externalId'],
      'externalClosureStatus': 'not_synced',
      'alarmCode': eventTypes[e['type']] ?? e['type'],
      'alarmName': e['title'],
      'alarmDescription': e['description'] ?? e['title'],
      'location': e['locationDescription'],
      'locationQuality': e['locationQuality'] ?? 'unknown',
      'coordinateSystem': e['coordinateSystem'] ?? 'UNKNOWN',
      'locationLat': e['locationLat'],
      'locationLng': e['locationLng'],
      'locationReportedAt': e['locationReportedAt'],
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
        (site.isEmpty
                ? const []
                : jsonMap(native['permissionsBySite'])[site] as List? ?? [])
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
