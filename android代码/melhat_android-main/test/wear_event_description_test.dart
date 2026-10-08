import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';

void main() {
  test('displays every core scenario without an Android alarm dictionary', () {
    final state = Map<String, dynamic>.from(
      jsonDecode(
            File(
              '../../后端代码/melhat_server-dev/ruoyi-admin/src/main/resources/guardian-seed.json',
            ).readAsStringSync(),
          )
          as Map,
    );
    final models = SharedModels(state);
    for (final scenario in state['events'] as List) {
      final event = WearEvent.fromJson(
        models.event(Map<String, dynamic>.from(scenario)),
      );
      expect(event.id, scenario['id']);
      expect(event.alarmLabel, scenario['title']);
      expect(event.statusLabel, scenario['status']);
      expect(event.personName, scenario['snapshot']['personName']);
    }
  });

  test('new or changed server names do not require a client release', () {
    final event = WearEvent.fromJson({
      'id': '1',
      'type': 'realtime',
      'alarmCode': 'belt.new_code',
      'alarmName': '核心系统新告警名称',
      'alarmDescription': '实际测量值与描述',
    });
    expect(event.alarmLabel, '核心系统新告警名称');
    expect(event.descriptionLabel, '实际测量值与描述');
  });

  test('missing metadata is explicit and never inferred from an opaque id', () {
    final event = WearEvent.fromJson({
      'id': '1',
      'type': 'geofence',
      'sourceEventId': 'call-lab:helmet.fence_exit:opaque',
    });
    expect(event.alarmLabel, '告警名称未提供');
    expect(event.descriptionLabel, '核心系统暂未提供告警描述');
    final coded = WearEvent.fromJson({
      'id': '2',
      'alarmCode': 'vendor.new_alarm',
    });
    expect(coded.alarmLabel, 'vendor.new_alarm');
    expect(coded.descriptionLabel, '核心系统暂未提供告警描述');
  });
}
