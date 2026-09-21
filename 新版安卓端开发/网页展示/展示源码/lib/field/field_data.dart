import 'package:flutter/foundation.dart';
import '../http/index.dart';
import '../http/request_options.dart';
import '../models/hat.dart';

typedef FieldRequest = Future<dynamic> Function(ReqOptions options);

String fieldText(dynamic value) => value?.toString() ?? '';
int fieldInt(dynamic value) => int.tryParse(fieldText(value)) ?? 0;

class FieldEvent {
  final String source;
  final Map<String, dynamic> raw;
  FieldEvent(this.source, Map<String, dynamic> data)
    : raw = Map.unmodifiable(data);
  String get id => fieldText(raw['id']);
  String get key => '$source:$id';
  String get hatId => fieldText(raw['hatId']);
  String get hatNumber => fieldText(raw['hatNumber']);
  String get userName => fieldText(raw['userName']);
  String get type => fieldText(raw['alarmType']);
  String get time => fieldText(raw['alarmStartTime'] ?? raw['createTime']);
  String get description => fieldText(raw['description']);
  String get handleTime => fieldText(raw['handleTime']);
  String get fenceName => fieldText(raw['fenceName']);
  String get levelLabel =>
      const {'0': '普通', '1': '紧急', '2': '严重'}[fieldText(raw['alarmLevel'])] ??
      '后台未提供';
  ({double lat, double lng})? get position {
    final lat = double.tryParse(fieldText(raw['latitude']));
    final lng = double.tryParse(fieldText(raw['longitude']));
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180)
      return null;
    return (lat: lat, lng: lng);
  }

  String get positionLabel => position == null
      ? '后台未提供有效定位'
      : '纬度 ${position!.lat.toStringAsFixed(6)}，经度 ${position!.lng.toStringAsFixed(6)}';
  bool get handled => fieldInt(raw['isHandled']) == 1;
  bool get isFence => source == 'fence';
  String get title => isFence
      ? (type == '1'
            ? '围栏禁入告警'
            : type == '2'
            ? '围栏禁出告警'
            : '围栏告警')
      : const {
              'sos': 'SOS 求助',
              'removal': '脱帽告警',
              'fall': '跌倒告警',
              'silent': '静默告警',
              'proximity': '近电告警',
            }[type] ??
            '设备告警';
  String get apiPath => isFence ? '/hat/fence/alarm' : '/hat/alarm';
}

class FieldSection {
  final List<Map<String, dynamic>> rows;
  final int total;
  final bool complete;
  final String? error;
  const FieldSection(this.rows, this.total, this.complete, [this.error]);
}

class FieldSnapshot {
  final FieldSection devices, deviceAlarms, fenceAlarms, groups;
  const FieldSnapshot(
    this.devices,
    this.deviceAlarms,
    this.fenceAlarms,
    this.groups,
  );
  List<Hat> get hats => devices.rows.map(Hat.fromJson).toList();
  List<FieldEvent> get events =>
      [
        ...deviceAlarms.rows.map((r) => FieldEvent('device', r)),
        ...fenceAlarms.rows.map((r) => FieldEvent('fence', r)),
      ]..sort((a, b) {
        final priorityA = !a.handled && a.type == 'sos' ? 0 : 1;
        final priorityB = !b.handled && b.type == 'sos' ? 0 : 1;
        return priorityA != priorityB
            ? priorityA.compareTo(priorityB)
            : b.time.compareTo(a.time);
      });
  List<String> get groupNames => {
    ...groups.rows.map((g) => fieldText(g['groupName'])),
    ...devices.rows.map((h) => fieldText(h['bindGroup'])),
  }.where((s) => s.isNotEmpty).toList()..sort();
  bool get complete =>
      devices.complete &&
      deviceAlarms.complete &&
      fenceAlarms.complete &&
      groups.complete;
  List<String> get warnings => [
    if (!devices.complete) '设备数据未完整加载',
    if (!deviceAlarms.complete) '设备告警未完整加载',
    if (!fenceAlarms.complete) '围栏告警未完整加载',
    if (!groups.complete) '分组数据未完整加载',
  ];
  bool inGroup(FieldEvent event, String group) =>
      group.isEmpty ||
      devices.rows.any(
        (h) =>
            fieldText(h['bindGroup']) == group &&
            ((event.hatId.isNotEmpty && fieldText(h['id']) == event.hatId) ||
                (event.hatNumber.isNotEmpty &&
                    fieldText(h['hatNumber']) == event.hatNumber)),
      );
  List<FieldEvent> filter({
    String group = '',
    String search = '',
    String source = '',
    String status = '',
    String type = '',
    String start = '',
    String end = '',
  }) {
    final term = search.trim().toLowerCase();
    return events.where((e) {
      final date = e.time.length >= 10 ? e.time.substring(0, 10) : '';
      return inGroup(e, group) &&
          (source.isEmpty || e.source == source) &&
          (status.isEmpty || e.handled == (status == '1')) &&
          (type.isEmpty || e.type == type) &&
          (start.isEmpty || (date.isNotEmpty && date.compareTo(start) >= 0)) &&
          (end.isEmpty || (date.isNotEmpty && date.compareTo(end) <= 0)) &&
          (term.isEmpty ||
              [
                e.userName,
                e.hatNumber,
                e.title,
                e.fenceName,
              ].join(' ').toLowerCase().contains(term));
    }).toList();
  }

  FieldSnapshot replace(FieldEvent event) {
    FieldSection changed(FieldSection section) => FieldSection(
      section.rows
          .map((r) => fieldText(r['id']) == event.id ? event.raw : r)
          .toList(),
      section.total,
      section.complete,
      section.error,
    );
    return FieldSnapshot(
      devices,
      event.isFence ? deviceAlarms : changed(deviceAlarms),
      event.isFence ? changed(fenceAlarms) : fenceAlarms,
      groups,
    );
  }
}

class FieldRepository {
  final FieldRequest request;
  FieldRepository({FieldRequest? request}) : request = request ?? http.request;
  static final revision = ValueNotifier<int>(0);

  Future<FieldSection> loadSection(String path) async {
    final rows = <Map<String, dynamic>>[];
    var total = 0;
    final seen = <String>{};
    try {
      for (var page = 1; page <= 25; page++) {
        final result = await request(
          ReqOptions(
            path: path,
            method: 'GET',
            params: {'current': page, 'size': 200},
          ),
        );
        if (result is! Map || result['records'] is! List) {
          throw const FormatException('分页响应不完整');
        }
        final batch = (result['records'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        final count = int.tryParse(fieldText(result['total']));
        if (count == null || count < 0) throw const FormatException('缺少有效总数');
        total = count;
        for (final row in batch) {
          final id = fieldText(row['id']);
          if (id.isEmpty || !seen.add(id))
            throw const FormatException('分页编号缺失或重复，请刷新');
          rows.add(row);
        }
        if (rows.length >= total) return FieldSection(rows, total, true);
        if (batch.isEmpty) break;
      }
      return FieldSection(rows, total, false);
    } catch (e) {
      return FieldSection(rows, total, false, e.toString());
    }
  }

  Future<FieldSnapshot> load() async {
    final parts = await Future.wait([
      loadSection('/hat/safety/info/page'),
      loadSection('/hat/alarm/page'),
      loadSection('/hat/fence/alarm/page'),
      loadSection('/hat/group/info'),
    ]);
    return FieldSnapshot(parts[0], parts[1], parts[2], parts[3]);
  }

  Future<FieldEvent> detail(FieldEvent event) async {
    if (event.id.isEmpty) throw const FormatException('告警缺少有效编号');
    final result = await request(
      ReqOptions(path: '${event.apiPath}/${event.id}', method: 'GET'),
    );
    if (result is! Map || fieldText(result['id']) != event.id) {
      throw const FormatException('告警已不存在或详情不完整');
    }
    final merged = {...event.raw, ...Map<String, dynamic>.from(result)};
    // Detail returns an unjoined entity: retain a list label only for the same relation.
    for (final relation in {
      'fenceName': 'fenceId',
      'userName': 'userId',
      'hatNumber': 'hatId',
    }.entries) {
      final originalId = fieldText(event.raw[relation.value]);
      final currentId = fieldText(merged[relation.value]);
      if (fieldText(result[relation.key]).isEmpty) {
        merged[relation.key] = originalId == currentId
            ? event.raw[relation.key]
            : null;
      }
    }
    return FieldEvent(event.source, merged);
  }

  Future<void> handle(FieldEvent event, String description) async {
    if (event.id.isEmpty || description.trim().isEmpty)
      throw const FormatException('请填写完整处理说明');
    await request(
      ReqOptions(
        path: '${event.apiPath}/handle',
        method: 'PUT',
        data: {'id': event.id, 'description': description.trim()},
      ),
    );
  }
}
