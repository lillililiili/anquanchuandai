import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'wear_app_test.dart' show appSession;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('inspector can enter contacts but cannot enter management', (
    tester,
  ) async {
    final session = appSession(authenticated: true);
    session.me = {
      ...session.me!,
      'userId': 'contact-read-inspector',
      'roles': ['wear_readonly'],
      'admin': false,
      'permissions': ['*:*:*'],
    };
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    final bar = find.byType(NavigationBar);
    final destination = tester.widget<NavigationDestination>(
      find.byWidgetPredicate(
        (widget) => widget is NavigationDestination && widget.label == '通讯',
      ),
    );
    expect(destination.enabled, isTrue);
    await tester.tap(find.text('通讯'));
    await tester.pumpAndSettle();
    final router = GoRouter.of(tester.element(bar));
    expect(router.routeInformationProvider.value.uri.path, '/communications');
    expect(bar, findsOneWidget);
    for (final path in ['/people', '/devices', '/duty', '/lab-call/1']) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/workbench');
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test('contact read permissions do not promote legacy wildcard inspector', () {
    final session = appSession(authenticated: true);
    addTearDown(session.dispose);
    session.me = {
      ...session.me!,
      'roles': ['wear_team_lead', 'wear_reviewer'],
      'admin': false,
      'permissions': ['*:*:*'],
    };
    for (final permission in [
      'wear:person:list',
      'wear:person:query',
      'wear:device:list',
      'wear:device:query',
    ]) {
      expect(session.can(permission), isTrue, reason: permission);
    }
    for (final permission in [
      'wear:person:edit',
      'wear:device:edit',
      'wear:task:edit',
      'wear:event:review',
      'wear:event:claim',
      'wear:call:start',
      'wear:command:tts',
      'wear:duty:handover',
    ]) {
      expect(session.can(permission), isFalse, reason: permission);
    }
    expect(session.isAdmin, isFalse);
    expect(session.isDuty, isFalse);
    expect(session.isReviewer, isFalse);
    session.me = {...session.me!, 'permissions': <String>[]};
    expect(session.can('wear:person:list'), isFalse);
  });
}
