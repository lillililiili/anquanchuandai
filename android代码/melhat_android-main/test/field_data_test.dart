import 'package:rolling_intelligence_headband/models/hat.dart';
import 'package:rolling_intelligence_headband/models/alarm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/field/field_data.dart';
import 'package:rolling_intelligence_headband/field/field_session.dart';

void main() {
  test(
    'detail retains null joined labels only for unchanged relations',
    () async {
      var fenceId = '52';
      final repository = FieldRepository(
        request: (_) async => {
          'id': '52',
          'fenceId': fenceId,
          'fenceName': null,
          'userId': '236',
          'userName': null,
          'isHandled': 1,
          'description': '已核查',
        },
      );
      final original = FieldEvent('fence', {
        'id': '52',
        'fenceId': '52',
        'fenceName': '东侧禁入区',
        'userId': '236',
        'userName': '张三',
        'isHandled': 0,
      });
      final detail = await repository.detail(original);
      expect(detail.fenceName, '东侧禁入区');
      expect(detail.userName, '张三');
      expect(detail.handled, isTrue);
      expect(detail.description, '已核查');
      fenceId = '99';
      expect((await repository.detail(original)).fenceName, isEmpty);
    },
  );

  test('missing totals and repeated pages remain visibly incomplete', () async {
    final missing = FieldRepository(request: (_) async => {'records': []});
    expect((await missing.loadSection('/test')).complete, isFalse);
    final repeated = FieldRepository(
      request: (_) async => {
        'records': [
          {'id': '1'},
        ],
        'total': 3,
      },
    );
    final result = await repeated.loadSection('/test');
    expect(result.complete, isFalse);
    expect(result.rows.length, 1);
    expect(result.error, isNotNull);
  });
  test('coordinates are validated and missing severity is explicit', () {
    final valid = FieldEvent('device', {
      'latitude': '37.4',
      'longitude': 118,
      'alarmLevel': '1',
    });
    expect(valid.position!.lat, 37.4);
    expect(valid.levelLabel, '紧急');
    expect(
      FieldEvent('device', {'latitude': 99, 'longitude': 118}).position,
      isNull,
    );
    expect(FieldEvent('fence', {}).levelLabel, '后台未提供');
  });

  test(
    'server string IDs keep device-person relationships and numeric alarm IDs',
    () {
      final hat = Hat.fromJson({
        'id': 103,
        'bindUserId': '236',
        'bindGroupId': '52',
      });
      final alarm = Alarm.fromJson({
        'id': 57,
        'hatId': '103',
        'userId': '236',
        'isHandled': '1',
      });
      expect(hat.id, '103');
      expect(hat.bindUserId, 236);
      expect(hat.bindGroupId, 52);
      expect(alarm.id, '57');
      expect(alarm.hatId, 103);
      expect(alarm.userId, 236);
      expect(alarm.isHandled, 1);
      expect(Alarm.alarmTypeMap['removal'], '脱帽告警');
    },
  );
  const empty = FieldSection([], 0, true);
  test(
    'device and fence with same ID remain distinct and filter by actual hat binding',
    () {
      final s = FieldSnapshot(
        const FieldSection(
          [
            {'id': '103', 'hatNumber': 'H1', 'bindGroup': '东组'},
          ],
          1,
          true,
        ),
        const FieldSection(
          [
            {
              'id': 1,
              'hatId': 103,
              'alarmType': 'sos',
              'isHandled': 0,
              'alarmStartTime': '2026-09-06 09:00:00',
            },
            {
              'id': 2,
              'hatId': 999,
              'alarmType': 'fall',
              'isHandled': 0,
              'alarmStartTime': '2026-09-06 08:00:00',
            },
          ],
          2,
          true,
        ),
        const FieldSection(
          [
            {
              'id': '1',
              'hatNumber': 'H1',
              'alarmType': '1',
              'isHandled': '1',
              'alarmStartTime': '2026-09-05 08:00:00',
            },
          ],
          1,
          true,
        ),
        empty,
      );
      expect(s.events.map((e) => e.key).toSet(), {
        'device:1',
        'device:2',
        'fence:1',
      });
      expect(s.filter(group: '东组').length, 2);
      expect(s.filter(group: '东组', status: '0').single.key, 'device:1');
      expect(s.filter(start: '2026-09-06', end: '2026-09-06').length, 2);
      expect(s.filter(source: 'fence').single.handled, isTrue);
    },
  );
  test(
    'paged loading continues past first page and exposes partial network failure',
    () async {
      final seen = <int>[];
      final repo = FieldRepository(
        request: (o) async {
          final page = o.params!['current'] as int;
          seen.add(page);
          if (page == 1)
            return {
              'records': [
                {'id': '1'},
              ],
              'total': 2,
            };
          throw Exception('offline');
        },
      );
      final result = await repo.loadSection('/hat/alarm/page');
      expect(seen, [1, 2]);
      expect(result.rows.length, 1);
      expect(result.complete, isFalse);
      expect(result.error, isNotNull);
      expect(result.total, 2);
    },
  );
  test(
    'scope changes clear drafts and identical source keys do not overwrite',
    () {
      final session = FieldSession()..scope('alice');
      session.draft('device:1').inquiry = '设备核查';
      session.draft('fence:1').inquiry = '围栏核查';
      session.scope('alice');
      expect(session.draft('device:1').inquiry, '设备核查');
      expect(session.draft('fence:1').inquiry, '围栏核查');
      session.scope('bob');
      expect(session.drafts, isEmpty);
    },
  );
  test(
    'handler uses the matching backend and detail verifies record identity',
    () async {
      final calls = <String>[];
      final repo = FieldRepository(
        request: (o) async {
          calls.add('${o.method} ${o.path}');
          if (o.method == 'PUT') {
            expect(o.data, {'id': '7', 'description': '核查完成'});
            return null;
          }
          return {'id': '8', 'isHandled': 1};
        },
      );
      final event = FieldEvent('fence', {'id': 7});
      await repo.handle(event, '核查完成');
      await expectLater(repo.detail(event), throwsFormatException);
      expect(calls, ['PUT /hat/fence/alarm/handle', 'GET /hat/fence/alarm/7']);
    },
  );
}
