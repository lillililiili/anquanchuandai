import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_repository.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  test(
    'multiple statuses and alarm kinds reach the same paginated request',
    () async {
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                expect(r.path, '/api/v1/events');
                expect(r.queryParameters['statuses'], 'open,closed');
                expect(r.queryParameters['types'], 'fall,impact');
                expect(
                  r.queryParameters['alarmCodes'],
                  'helmet.removal,belt.unhooked',
                );
                expect(r.queryParameters['deviceTypes'], 'helmet,belt');
                expect(r.queryParameters['taskId'], '9');
                return reply({
                  'records': [],
                  'total': 0,
                  'current': 1,
                  'size': 20,
                });
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity(user: '7');
      addTearDown(session.dispose);
      const filters = EventFilters(
        status: 'all',
        statuses: ['open', 'closed'],
        types: ['fall', 'impact'],
        alarmCodes: ['helmet.removal', 'belt.unhooked'],
        deviceTypes: ['helmet', 'belt'],
        taskId: '9',
      );
      await ApiEventGateway(
        session.api,
      ).fetchPage(EventFilters.fromJson(filters.toJson()), 1, 20);
    },
  );
  test(
    'alarm and multi-device filters persist and reach server pagination with task scope',
    () async {
      const filters = EventFilters(
        alarmCode: 'helmet.removal',
        alarmLabel: '脱帽',
        deviceTypes: ['helmet', 'belt'],
        taskId: '9',
      );
      final restored = EventFilters.fromJson(
        filters.toJson(),
      ).copyWith(status: 'closed');
      expect(restored.alarmCode, 'helmet.removal');
      expect(restored.deviceTypes, ['helmet', 'belt']);
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((request) {
                expect(request.path, '/api/v1/events');
                expect(request.queryParameters['taskId'], '9');
                expect(request.queryParameters['alarmCode'], 'helmet.removal');
                expect(request.queryParameters['deviceTypes'], 'helmet,belt');
                expect(request.queryParameters['status'], 'closed');
                expect(request.queryParameters['current'], 2);
                return reply({
                  'records': [],
                  'total': 25,
                  'current': 2,
                  'size': 20,
                });
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity(user: '7');
      addTearDown(session.dispose);
      final page = await ApiEventGateway(
        session.api,
      ).fetchPage(restored, 2, 20);
      expect(page.total, 25);
      expect(page.current, 2);
    },
  );
}
