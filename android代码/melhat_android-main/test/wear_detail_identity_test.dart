import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/devices.dart';
import 'package:rolling_intelligence_headband/wear/queries/person_management.dart';
import 'package:rolling_intelligence_headband/wear/queries/tasks.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, transport, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final kind in ['device', 'task', 'equipment']) {
    testWidgets('$kind detail reloads when the route identity changes', (
      t,
    ) async {
      final reads = <String>[];
      final session =
          WearSession(
              mock: true,
              credentials: MemoryCredentials(),
              dio: transport((r) {
                reads.add(r.path);
                if (r.path.endsWith('/assignments') ||
                    r.path.endsWith('/events') ||
                    r.path.endsWith('/equipment-check')) {
                  return reply([]);
                }
                if (r.path.endsWith('/equipment')) {
                  final id = r.path.split('/')[4];
                  return reply([
                    {
                      'id': 'assigned-$id',
                      'sn': 'equipment-$id',
                      'typeCode': 'belt',
                    },
                  ]);
                }
                if (r.path == '/api/v1/devices') {
                  return reply({
                    'records': [],
                    'total': 0,
                    'current': 1,
                    'size': 20,
                  });
                }
                final id = r.path.split('/').last;
                return reply({
                  'id': id,
                  'sn': 'device-$id',
                  'name': 'task-$id',
                  'title': 'task-$id',
                  'typeCode': 'belt',
                  'version': 1,
                  'members': [],
                });
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = {...identity(), 'admin': true};
      addTearDown(session.dispose);
      Widget page(String id) => WearScope(
        session: session,
        child: MaterialApp(
          home: switch (kind) {
            'device' => DevicePage(id: id),
            'task' => TaskPage(id: id),
            _ => PersonEquipmentPage(id: id),
          },
        ),
      );
      await t.pumpWidget(page('first'));
      await t.pumpAndSettle();
      expect(find.text('$kind-first'), findsWidgets);
      reads.clear();
      await t.pumpWidget(page('second'));
      await t.pumpAndSettle();
      expect(reads.any((path) => path.contains('/second')), isTrue);
      expect(find.text('$kind-second'), findsWidgets);
      expect(find.text('$kind-first'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
