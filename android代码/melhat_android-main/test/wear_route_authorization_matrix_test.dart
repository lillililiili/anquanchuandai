import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/auth_pages.dart';
import 'package:rolling_intelligence_headband/wear/communications/communications.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'package:rolling_intelligence_headband/wear/mine_page.dart';
import 'package:rolling_intelligence_headband/wear/mock_backend.dart';
import 'package:rolling_intelligence_headband/wear/queries/queries.dart';
import 'package:rolling_intelligence_headband/wear/queries/person_management.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const routes = <String, Type>{
    '/login': WorkbenchPage,
    '/sites': WearSitesPage,
    '/workbench': WorkbenchPage,
    '/sos-events': EventsPage,
    '/people': PeoplePage,
    '/people-admin/equipment/102': PersonEquipmentPage,
    '/people/102': PersonPage,
    '/devices': DevicesPage,
    '/devices/203': DevicePage,
    '/tasks': TasksPage,
    '/tasks/301': TaskPage,
    '/communications': CommunicationsPage,
    '/events': EventsPage,
    '/me': WearMinePage,
  };
  const restricted = {
    '/people',
    '/people-admin/equipment/102',
    '/people/102',
    '/devices',
  };
  for (final role in ['demo', 'member', 'unauthenticated']) {
    testWidgets('all 14 route declarations enforce $role access', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final backend = MockBackend()
        ..account = role
        ..siteId = '1';
      final session = WearSession(
        mock: true,
        dio: Dio()..httpClientAdapter = backend,
      )..initialized = true;
      if (role != 'unauthenticated') {
        session
          ..token = 'local-test'
          ..siteId = '1'
          ..me = backend.identity;
      }
      addTearDown(session.dispose);
      await t.pumpWidget(WearApp(session: session, enableNotifications: false));
      await t.pumpAndSettle();
      final router = GoRouter.of(
        t.element(
          find.byType(
            role == 'unauthenticated' ? WearLoginPage : WorkbenchPage,
          ),
        ),
      );
      for (final entry in routes.entries) {
        router.go(entry.key);
        await t.pumpAndSettle();
        final expected = role == 'unauthenticated'
            ? WearLoginPage
            : role == 'member' && restricted.contains(entry.key)
            ? WorkbenchPage
            : entry.value;
        expect(find.byType(expected), findsOneWidget, reason: entry.key);
        expect(t.takeException(), isNull, reason: entry.key);
        if (entry.key == '/sos-events' && role != 'unauthenticated') {
          expect(router.routeInformationProvider.value.uri.path, '/events');
          expect(
            router.routeInformationProvider.value.uri.queryParameters['type'],
            'sos',
          );
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
