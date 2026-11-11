import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/events_page.dart';
import 'package:rolling_intelligence_headband/wear/events/event_reference_view.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, identity, reply, transport;

// Keep the same EventsPage State across identity/site notifications so these
// tests exercise replaceScope, not a conveniently recreated controller.
class ScopeSession extends WearSession {
  ScopeSession(Dio dio)
    : super(dio: dio, credentials: MemoryCredentials(), mock: true);

  void replaceIdentity({required String user, required String site}) {
    token = 'test-$user';
    siteId = site;
    me = {
      ...identity(user: user, site: site, roles: ['wear_member']),
      'permissions': [
        'wear:event:list',
        'wear:event:query',
        'wear:event:report',
      ],
    };
    notifyListeners();
  }
}

Map<String, dynamic> event(String id) => {
  'id': id,
  'type': 'sos',
  'severity': 'emergency',
  'status': 'open',
  'siteId': '1',
  'personId': 'person-$id',
  'personName': 'fixture-person-$id',
  'version': 1,
};

ResponseBody commonReply(RequestOptions request) {
  if (request.path == '/api/v1/events') {
    return reply({'records': [], 'total': 0, 'current': 1, 'size': 20});
  }
  if (request.path.endsWith('/inbox/count')) return reply({'count': 0});
  if (request.path.endsWith('/actions') || request.path.endsWith('/media')) {
    return reply([]);
  }
  return reply({});
}

Future<void> mountRetainedPage(
  WidgetTester tester,
  ScopeSession session,
  ValueNotifier<String> eventId,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    eventId.dispose();
    session.dispose();
  });
  await tester.pumpWidget(
    WearScope(
      session: session,
      child: MaterialApp(
        home: ValueListenableBuilder<String>(
          valueListenable: eventId,
          builder: (context, value, child) => EventsPage(
            key: const ValueKey('retained-event-page'),
            eventId: value,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final changedPart in ['account', 'site']) {
    testWidgets(
      'cache route revalidation rejects old event after $changedPart change',
      (tester) async {
        final detailRequests = <RequestOptions>[];
        var denyOldEvent = false;
        final session = ScopeSession(
          transport((request) {
            if (request.path == '/api/v1/events/A') {
              detailRequests.add(request);
              return denyOldEvent
                  ? reply(null, code: 403, msg: 'fixture scope denied')
                  : reply(event('A'));
            }
            return commonReply(request);
          }),
        )..initialized = true;
        session.replaceIdentity(user: 'user-old-$changedPart', site: '1');
        final route = ValueNotifier('A');
        await mountRetainedPage(tester, session, route);
        expect(find.byType(EventReferenceView), findsOneWidget);
        final oldState = tester.state(find.byType(EventsPage));
        final input = find.byKey(const ValueKey('event-observation'));
        await tester.ensureVisible(input);
        await tester.enterText(input, 'private draft from old $changedPart');
        await tester.pumpAndSettle();

        denyOldEvent = true;
        session.replaceIdentity(
          user: changedPart == 'account' ? 'user-new' : 'user-old-$changedPart',
          site: changedPart == 'site' ? '2' : '1',
        );
        await tester.pumpAndSettle();

        expect(
          identical(tester.state(find.byType(EventsPage)), oldState),
          isTrue,
        );
        expect(detailRequests.length, greaterThanOrEqualTo(2));
        expect(detailRequests.last.headers['X-Site-Id'], session.siteId);
        expect(
          detailRequests.last.headers['Authorization'],
          'Bearer ${session.token}',
        );
        expect(find.byType(EventReferenceView), findsNothing);
        expect(find.byKey(const ValueKey('event-observation')), findsNothing);
        expect(find.textContaining('private draft from old'), findsNothing);
        expect(find.text('事件详情暂不可用'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'late cache-scope detail cannot replace the current route detail',
    (tester) async {
      final pendingA = Completer<ResponseBody>();
      var holdNextA = false;
      var heldA = false;
      final session = ScopeSession(
        transport((request) {
          if (request.path == '/api/v1/events/A') {
            if (holdNextA && !heldA) {
              heldA = true;
              return pendingA.future;
            }
            return reply(event('A'));
          }
          if (request.path == '/api/v1/events/B') return reply(event('B'));
          return commonReply(request);
        }),
      )..initialized = true;
      session.replaceIdentity(user: 'race-user', site: '1');
      final route = ValueNotifier('A');
      await mountRetainedPage(tester, session, route);
      addTearDown(() {
        if (!pendingA.isCompleted) pendingA.complete(reply(event('A')));
      });
      expect(find.byType(EventReferenceView), findsOneWidget);

      holdNextA = true;
      await session.clearBusinessCache();
      for (var i = 0; i < 30 && !heldA; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        heldA,
        isTrue,
        reason: 'The scope restoration must actually request A',
      );
      route.value = 'B';
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EventReferenceView>(find.byType(EventReferenceView))
            .controller
            .selected!
            .id,
        'B',
      );

      pendingA.complete(reply(event('A')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EventReferenceView>(find.byType(EventReferenceView))
            .controller
            .selected!
            .id,
        'B',
      );
      expect(find.text('fixture-person-A'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
