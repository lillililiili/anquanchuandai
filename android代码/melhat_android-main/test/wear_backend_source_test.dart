import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/my_equipment_page.dart';
import 'package:rolling_intelligence_headband/wear/queries/query_utils.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_filters.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  test(
    'equipment ownership uses assignment and online uses device detail',
    () async {
      final api = WearApi(
        token: () => null,
        siteId: () => '1',
        epoch: () => 0,
        dio: transport((r) {
          if (r.path == '/api/v1/people/7/equipment') {
            return reply([
              {
                'id': 'assignment-9',
                'deviceId': '42',
                'personId': '7',
                'online': '1',
              },
            ]);
          }
          expect(r.path, '/api/v1/devices/42');
          return reply({'id': '42', 'online': '0', 'connectionQuality': 'ok'});
        }),
      );
      final rows = await loadEquipmentWithTelemetry(
        api,
        '/api/v1/people/7/equipment',
      );
      expect(rows.single['id'], 'assignment-9');
      expect(rows.single['personId'], '7');
      expect(connectionLabel(rows.single), '离线');
    },
  );
  test(
    'current work resolves actual person membership not owner account ID',
    () async {
      final api = WearApi(
        token: () => null,
        siteId: () => '1',
        epoch: () => 0,
        dio: transport((r) {
          if (r.path == '/api/v1/work-tasks/mine') {
            return reply({
              'records': r.queryParameters['status'] == 'paused'
                  ? []
                  : [
                      {'id': '10', 'status': 'in_progress'},
                      {'id': '11', 'status': 'in_progress'},
                    ],
              'total': r.queryParameters['status'] == 'paused' ? 0 : 2,
              'current': 1,
              'size': 100,
            });
          }
          if (r.path.endsWith('/10')) {
            return reply({
              'id': '10',
              'title': '后端巡检',
              'status': 'in_progress',
              'members': [
                {'personId': '7'},
              ],
            });
          }
          return reply({
            'id': '11',
            'title': '其他作业',
            'status': 'in_progress',
            'ownerUserId': '7',
            'members': [
              {'personId': '8'},
            ],
          });
        }),
      );
      final tasks = await loadPersonActiveTasks(api, '7');
      expect(tasks.map((t) => t['id']), ['10']);
    },
  );
  test('real backend numeric online status participates in online filters', () {
    for (final value in ['1', 1, true]) {
      final device = CommunicationDevice.fromJson({
        'id': '1',
        'online': value,
        'connectionQuality': 'ok',
      });
      expect(
        const ContactFilters(presence: 'online').matchesDevice(device),
        isTrue,
      );
    }
    final offline = CommunicationDevice.fromJson({
      'id': '2',
      'online': '0',
      'connectionQuality': 'ok',
    });
    expect(
      const ContactFilters(presence: 'offline').matchesDevice(offline),
      isTrue,
    );
    final stale = CommunicationDevice.fromJson({
      'id': '3',
      'online': '1',
      'connectionQuality': 'stale',
    });
    expect(
      const ContactFilters(presence: 'online').matchesDevice(stale),
      isFalse,
    );
  });
  testWidgets(
    'empty backend equipment never invents local helmet belt or watch',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) => reply([])),
            )
            ..initialized = true
            ..me = identity()
            ..siteId = '1'
            ..token = 'test';
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: const MaterialApp(home: MyEquipmentPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('RL-H001'), findsNothing);
      expect(find.text('RL-B001'), findsNothing);
      expect(find.text('RL-W001'), findsNothing);
      expect(find.text('暂无领用装备'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
