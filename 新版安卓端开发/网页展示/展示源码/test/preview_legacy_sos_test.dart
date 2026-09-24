import 'dart:io';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/web_preview/preview_data.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';

void main() {
  test(
    'audit event 159 keeps identity through list, detail and ending assistance',
    () async {
      final snapshot =
          jsonDecode(File('assets/preview/snapshot.json').readAsStringSync())
              as Map<String, dynamic>;
      final adapter = PreviewAdapter(snapshot);
      final dio = Dio(BaseOptions(baseUrl: 'https://preview.invalid'))
        ..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final list =
          (await dio.get(
                '/api/v1/events',
                queryParameters: {
                  'severity': 'emergency',
                  'status': 'all',
                  'size': 1000,
                },
              )).data['data']['records']
              as List;
      expect(
        list.every(
          (row) =>
              WearEvent.fromJson(Map<String, dynamic>.from(row)).isEmergency,
        ),
        isTrue,
      );
      final listed = list.singleWhere((row) => row['id'] == '159');
      final before = (await dio.get('/api/v1/events/159')).data['data'];
      expect(before['severity'], 'emergency');
      expect(before['alarmName'], 'SOS 求助');
      for (final key in [
        'id',
        'type',
        'severity',
        'alarmName',
        'personName',
        'sn',
        'occurredAt',
        'escalated',
      ]) {
        expect(before[key], listed[key], reason: key);
      }
      expect(before['personName'], '陈建国');
      expect(before['sn'], 'RL-H001');
      adapter.labCalls.add({
        'id': 'sos-159',
        'eventId': '159',
        'sos': true,
        'state': 'connected',
      });
      await dio.post('/api/v1/lab/calls/sos-159/end', data: {});
      expect(adapter.labCalls.single['state'], 'ended');
      expect(
        (await dio.get('/api/v1/events/159')).data['data'],
        before,
        reason: 'Ending assistance must not verify or close the linked event',
      );
      final report = await dio.post(
        '/api/v1/events/159/report',
        data: FormData.fromMap({
          'comment': '演示现场记录',
          'version': before['version'],
        }),
      );
      expect(report.data['data']['status'], 'pending_review');
      expect(
        report.data['data']['externalClosureStatus'],
        before['externalClosureStatus'],
      );
    },
  );
}
