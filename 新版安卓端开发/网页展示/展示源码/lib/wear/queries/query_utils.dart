import '../core.dart';
import '../device_status.dart';

String personStatusLabel(Object? value) => switch (value?.toString()) {
  '0' => '在职',
  '1' => '停用',
  _ => '未知',
};

String deviceTypeLabel(Object? value) => switch (value?.toString()) {
  'helmet' => '安全帽',
  'belt' => '安全带',
  'watch' => '智能手表',
  _ => '未知类型',
};

String assetStatusLabel(Object? value) => switch (value?.toString()) {
  'unassigned' => '未分配',
  'in_stock' => '在库',
  'issued' => '已领用',
  'maintenance' => '维修中',
  'disabled' => '已停用',
  'scrapped' => '已报废',
  _ => '未知',
};

String taskStatusLabel(Object? value) => switch (value?.toString()) {
  'draft' => '草稿',
  'ready' => '待开始',
  'in_progress' => '进行中',
  'paused' => '已暂停',
  'ended' => '已结束',
  _ => '未知',
};

String taskGroup(Object? value) => switch (value?.toString()) {
  'in_progress' || 'paused' => '进行中',
  'draft' || 'ready' => '待开始',
  'ended' => '已结束',
  _ => '状态未知',
};

String equipmentResultLabel(Object? value) => switch (value?.toString()) {
  'ok' => '符合要求',
  'missing' => '缺少装备',
  'unknown' => '状态未知',
  _ => '状态未知',
};

String eventTypeLabel(Object? value) => switch (value?.toString()) {
  'sos' => 'SOS 求救',
  'fall' => '跌倒告警',
  'realtime' => '实时告警',
  'geofence' => '围栏告警',
  _ => '未知事件',
};

String eventStatusLabel(Object? value) => switch (value?.toString()) {
  'open' => '待处理',
  'claimed' => '待处理',
  'handling' => '处理中',
  'pending_review' => '待复核',
  'closed' => '已关闭',
  _ => '状态未知',
};

String connectionLabel(JsonMap item) {
  return switch (item['connectionQuality']?.toString()) {
    'ok' => switch (devicePresence(item)) {
      'online' => '在线',
      'offline' => '离线',
      _ => '状态未知',
    },
    'stale' => '数据陈旧',
    _ => '状态未知',
  };
}

/// Assignment DTOs carry ownership, while device DTOs carry telemetry.
Future<List<JsonMap>> loadEquipmentWithTelemetry(
  WearApi api,
  String path,
) async {
  final assignments = jsonList(await api.get(path));
  return Future.wait(
    assignments.map((assignment) async {
      final id = idOf(assignment['deviceId']);
      if (id.isEmpty) return assignment;
      try {
        final device = jsonMap(
          await api.get('/api/v1/devices/${Uri.encodeComponent(id)}'),
        );
        return <String, dynamic>{
          ...assignment,
          for (final key in [
            'online',
            'connectionQuality',
            'simulation',
            'simulationStatus',
            'simulationStatusLabel',
            'lastReportedAt',
            'lastTelemetryAt',
            'battery',
            'demo',
          ])
            key: device[key],
        };
      } on StaleSessionException {
        rethrow;
      } catch (_) {
        return <String, dynamic>{
          ...assignment,
          'online': null,
          'connectionQuality': 'unknown',
          'telemetryUnavailable': true,
        };
      }
    }),
  );
}

/// Use server membership; account IDs and personnel IDs are different domains.
Future<List<JsonMap>> loadPersonActiveTasks(
  WearApi api,
  String personId, {
  bool allSite = false,
}) async {
  final rows = <String, JsonMap>{};
  for (final status in allSite ? ['in_progress', 'paused'] : [null]) {
    final seen = <String>{};
    for (var current = 1; ; current++) {
      final page = await api.page(
        allSite ? '/api/v1/work-tasks' : '/api/v1/work-tasks/mine',
        current: current,
        size: 100,
        query: {'status': ?status},
      );
      final before = seen.length;
      for (final row in page.records) {
        seen.add(idOf(row['id']));
        if (row['status'] == 'in_progress' || row['status'] == 'paused') {
          rows[idOf(row['id'])] = row;
        }
      }
      if (!page.hasMore) break;
      if (before == seen.length) throw const FormatException('作业分页未继续返回');
    }
  }
  final tasks = <JsonMap>[];
  final ids = rows.keys.toList();
  for (var offset = 0; offset < ids.length; offset += 6) {
    final details = await Future.wait(
      ids
          .skip(offset)
          .take(6)
          .map((id) async => jsonMap(await api.get('/api/v1/work-tasks/$id'))),
    );
    tasks.addAll(
      details.where(
        (task) =>
            (task['status'] == 'in_progress' || task['status'] == 'paused') &&
            (idOf(task['guardianPersonId']) == personId ||
                jsonList(
                  task['members'],
                ).any((member) => idOf(member['personId']) == personId)),
      ),
    );
  }
  return tasks;
}

String batteryLabel(Object? value) {
  if (value == null) return '未知';
  final number = num.tryParse(value.toString());
  if (number == null) return '未知';
  final percent = number <= 1 ? number * 100 : number;
  return '${percent.round()}%';
}

List<String> stringValues(Object? value) {
  if (value is! List) return const [];
  return value
      .where((item) => item != null)
      .map((item) => item.toString())
      .toList();
}

List<String> deviceActions(JsonMap device) {
  final capabilities = jsonMap(device['capabilities']);
  return stringValues(capabilities['actions']);
}

int nearestPointIndex(List<JsonMap> points, DateTime target) {
  if (points.isEmpty) return -1;
  var best = 0;
  var bestDistance = _distance(points.first['occurredAt'], target);
  for (var index = 1; index < points.length; index++) {
    final distance = _distance(points[index]['occurredAt'], target);
    if (distance < bestDistance) {
      best = index;
      bestDistance = distance;
    }
  }
  return best;
}

Duration _distance(Object? raw, DateTime target) {
  final parsed = DateTime.tryParse(raw?.toString() ?? '');
  if (parsed == null) return const Duration(days: 365000);
  final difference = parsed.difference(target);
  return difference.isNegative ? -difference : difference;
}

Uri communicationUri({String? deviceId, String? personId, String? action}) {
  return Uri(
    path: '/communications',
    queryParameters: {
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      if (personId != null && personId.isNotEmpty) 'personId': personId,
      if (action != null && action.isNotEmpty) 'action': action,
      if (action == 'video') 'video': '1',
    },
  );
}
