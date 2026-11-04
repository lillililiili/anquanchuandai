import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_controller.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'package:rolling_intelligence_headband/wear/work_business.dart';
import 'wear_acceptance_fixture.dart';
import 'wear_comms_entry_test.dart' show openDevice;
import 'wear_events_controller_test.dart'
    show FakeEventGateway, MemoryEventStateStore;
import 'wear_session_test.dart'
    show MemoryCredentials, transport, reply, identity;

class _ImmediateGateway extends FakeEventGateway {
  final filtersSeen = <EventFilters>[];
  @override
  Future<EventPageData> fetchPage(
    EventFilters filters,
    int current,
    int size,
  ) async {
    filtersSeen.add(filters);
    return EventPageData(
      records: [detail],
      total: 1,
      current: current,
      size: size,
    );
  }
}

const _reviewer = EventActor(
  userId: '12',
  roles: {'wear_duty'},
  permissions: {'wear:event:list', 'wear:event:review', 'wear:event:report'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'late context cannot roll back mode; projection preserves original history and source',
    () async {
      final pending = Completer<dynamic>();
      final backend = SharedBackend(
        (method, path, {data, query, contentType}) => pending.future,
        () => 'site-1',
        () => 1,
        testSiteMode: false,
      );
      backend.applyBusinessConfig({
        'version': 2,
        'workBusinessEnabled': true,
        'simulatedWatchVisible': false,
      });
      final reading = backend.context();
      backend.applyBusinessConfig({
        'version': 3,
        'workBusinessEnabled': false,
        'simulatedWatchVisible': false,
      });
      final storedEvent = <String, dynamic>{
        'id': 'event-1',
        'source': 'device',
        'protocol': 'direct-belt',
        'workId': 'work-1',
        'externalId': 'external-1',
        'type': '安全带告警',
        'status': '待认领',
        'snapshot': {
          'workId': 'work-1',
          'supervisor': 'person-2',
          'supervisorId': 'person-2',
          'leaderId': 'person-3',
          'personName': '工人一',
        },
      };
      pending.complete({
        'businessConfig': {'version': 2, 'workBusinessEnabled': true},
        'works': [
          {'id': 'work-1', 'status': '进行中'},
        ],
        'events': [storedEvent],
      });
      final model = await reading;
      expect(backend.businessConfig['version'], 3);
      expect(model.rows('works'), isEmpty);
      final mapped = model.event(model.rows('events').single);
      expect(mapped['taskId'], anyOf(isNull, isEmpty));
      expect(mapped['sourceEventId'], anyOf(isNull, isEmpty));
      expect(mapped['deviceType'], 'belt');
      expect(mapped['source'], 'device');
      expect(jsonMap(mapped['snapshot']).containsKey('workId'), isFalse);
      expect(jsonMap(mapped['snapshot']).containsKey('leaderId'), isFalse);
      expect(jsonMap(mapped['snapshot']).containsKey('supervisorId'), isFalse);
      expect(storedEvent['workId'], 'work-1');
      expect(jsonMap(storedEvent['snapshot'])['supervisor'], 'person-2');
      expect(
        backend.applyBusinessConfig({
          'version': 3,
          'workBusinessEnabled': true,
        }),
        isFalse,
      );
      expect(
        backend.applyBusinessConfig({
          'version': 4,
          'workBusinessEnabled': true,
        }),
        isTrue,
      );
      expect(
        SharedModels({
          'businessConfig': backend.businessConfig,
          'events': [storedEvent],
        }).event(storedEvent)['taskId'],
        'work-1',
      );
    },
  );

  test(
    'local work exposes registration number, cross-day dates and cancelled status',
    () {
      final model = SharedModels({});
      final work = model.work({
        'id': 'LOCAL-20261103-001',
        'source': 'LOCAL',
        'name': '跨日检修',
        'status': '已取消',
        'plannedStartAt': '2026-11-03T23:00:00+08:00',
        'plannedEndAt': '2026-11-04T03:00:00+08:00',
      });
      expect(work['ticketRequired'], isFalse);
      expect(work['ticketNo'], isEmpty);
      expect(work['sourceStatus'], isEmpty);
      expect(work['sourceName'], '本地登记');
      expect(work['status'], 'cancelled');
      expect(
        currentWorkTime(work, now: DateTime.parse('2026-11-04T01:00:00+08:00')),
        isTrue,
      );
      expect(
        currentWorkTime(work, now: DateTime.parse('2026-11-04T03:00:00+08:00')),
        isFalse,
      );
      expect(
        currentWorkTime(work, now: DateTime.parse('2026-11-03T22:59:00+08:00')),
        isFalse,
      );
      expect(model.work({'status': '监护中'})['status'], 'in_progress');
    },
  );

  test(
    'closing clears restored task filter while preserving draft, photos and selected event',
    () async {
      var enabled = false;
      final gateway = _ImmediateGateway()
        ..detail = WearEvent.fromJson({
          'id': 'event-1',
          'type': 'sos',
          'status': 'handling',
          'version': 3,
          'sourceEventId': 'external-1',
          'taskId': 'work-1',
        });
      final store = MemoryEventStateStore()
        ..value = const EventWorkspaceState(
          filters: EventFilters(
            status: 'all',
            taskId: 'work-1',
            personId: 'person-1',
          ),
          selectedEventId: 'event-1',
          drafts: {
            'event-1': EventDraft(
              baseVersion: 3,
              taskId: 'work-1',
              situation: '已到现场，人员安全',
              measures: '保持观察',
              conclusion: '暂无法确认',
              photoPaths: ['photo-local.jpg'],
              handleComment: '现场补充',
            ),
          },
        );
      final controller = EventController(
        gateway: gateway,
        store: store,
        scopeKey: 'test',
        actor: _reviewer,
        initialTaskId: 'old-deep-link',
        workBusinessEnabled: () => enabled,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(gateway.filtersSeen.every((f) => f.taskId.isEmpty), isTrue);
      expect(controller.filters.personId, 'person-1');
      expect(controller.selected?.id, 'event-1');
      expect(controller.draftFor('event-1').situation, '已到现场，人员安全');
      expect(controller.draftFor('event-1').photoPaths, ['photo-local.jpg']);
      expect(controller.draftFor('event-1').taskId, isEmpty);
      enabled = true;
      await controller.updateDraft(
        'event-1',
        controller.draftFor('event-1').copyWith(taskId: 'work-1'),
      );
      enabled = false;
      await controller.clearWorkContext();
      expect(store.value!.drafts['event-1']!.taskId, isEmpty);
      expect(store.value!.drafts['event-1']!.handleComment, '现场补充');
      expect(await controller.execute(EventCommand.verify), isTrue);
      expect(controller.successMessage, '核验记录已提交');
    },
  );

  testWidgets(
    'runtime close removes work UI and deep links without ending communication',
    (tester) async {
      final session = await launchAcceptance(tester, AcceptanceBackend());
      session.api.shared.applyBusinessConfig({
        'version': 1,
        'workBusinessEnabled': true,
      });
      await tester.pumpAndSettle();
      expect(find.text('当前作业'), findsOneWidget);
      var terminations = 0;
      session.terminateCall = () async {
        terminations++;
      };
      session.callActive.value = true;
      session.api.shared.applyBusinessConfig({
        'version': 2,
        'workBusinessEnabled': false,
      });
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('view-current-work')), findsNothing);
      expect(find.text('当前作业'), findsNothing);
      expect(find.text('全部作业'), findsNothing);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(session.callActive.value, isTrue);
      expect(terminations, 0);
      final router = GoRouter.of(tester.element(find.byType(NavigationBar)));
      router.go('/tasks/41');
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/workbench');
      router.go('/events?taskId=41&status=all');
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.queryParameters.containsKey(
          'taskId',
        ),
        isFalse,
      );
      expect(find.text('关联作业'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real app is hidden before config and refreshes every five seconds and resume',
    (tester) async {
      var configReads = 0;
      final session =
          WearSession(
              mock: false,
              credentials: MemoryCredentials(),
              dio: transport((r) {
                if (r.path.endsWith('/business-config')) {
                  configReads++;
                  return reply({
                    'version': configReads,
                    'workBusinessEnabled': configReads == 1,
                  }, raw: true);
                }
                if (r.path.endsWith('/mobile/context')) {
                  return reply({
                    'operator': {},
                    'people': [],
                    'devices': [],
                    'events': [],
                    'works': [],
                  }, raw: true);
                }
                return reply({}, raw: true);
              }),
            )
            ..initialized = true
            ..token = 'token'
            ..siteId = 'site-1'
            ..me = identity();
      addTearDown(session.dispose);
      expect(session.workBusinessEnabled, isFalse);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(configReads, 1);
      expect(session.workBusinessEnabled, isTrue);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(configReads, 2);
      expect(session.workBusinessEnabled, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(configReads, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(configReads, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'switch while editing retains verification fields and completes device event',
    (tester) async {
      final backend = AcceptanceBackend();
      final session = await launchAcceptance(tester, backend);
      await openAcceptance(tester, '/events?eventId=401');
      await fillVerification(tester);
      session.api.shared.applyBusinessConfig({
        'version': 2,
        'workBusinessEnabled': false,
      });
      await tester.pumpAndSettle();
      expect(find.text('关联作业'), findsNothing);
      expect(find.textContaining('外部结案'), findsNothing);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('verification-situation')),
            )
            .controller!
            .text,
        '已到现场，人员安全',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('verification-measures')),
            )
            .controller!
            .text,
        '安排人员陪同并检查装备',
      );
      await tapAcceptance(
        tester,
        find.byKey(const ValueKey('verification-submit')),
      );
      await tapAcceptance(tester, find.text('确认'));
      expect(
        backend.events.firstWhere((e) => e['id'] == '401')['status'],
        'verified',
      );
      expect(find.text('核验结果（只读）'), findsOneWidget);
      expect(find.textContaining('外部结案'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('closing work mode keeps restored call on communications page', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final router = await openDevice(
      tester,
      requests,
      restoredStatus: 'unknown',
    );
    router.go('/communications?deviceId=42');
    await tester.pumpAndSettle();
    expect(find.text('结束原通话').hitTestable(), findsOneWidget);
    final session = WearScope.of(tester.element(find.byType(NavigationBar)));
    session.api.shared.applyBusinessConfig({
      'version': 2,
      'workBusinessEnabled': false,
    });
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/communications');
    expect(find.text('结束原通话').hitTestable(), findsOneWidget);
    expect(
      requests.where((r) => r.method == 'POST' && r.path.contains('/calls')),
      isEmpty,
    );
    expect(find.text('作业'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'closing during task filter debounce drops hidden condition and task wording',
    (tester) async {
      final session = await launchAcceptance(tester, AcceptanceBackend());
      await openAcceptance(tester, '/events?status=all');
      final toggle = find.byKey(const ValueKey('inline-filter-toggle'));
      if (toggle.evaluate().isNotEmpty) await tapAcceptance(tester, toggle);
      await tapAcceptance(tester, find.byKey(const ValueKey('filter-more')));
      final taskField = find.byKey(const ValueKey('filter-field-task-0'));
      await tester.ensureVisible(taskField);
      await tester.enterText(taskField, '987654321');
      session.api.shared.applyBusinessConfig({
        'version': 2,
        'workBusinessEnabled': false,
      });
      await tester.pumpAndSettle();
      expect(taskField, findsNothing);
      expect(find.textContaining('987654321'), findsNothing);
      expect(find.textContaining('人员、任务'), findsNothing);
      final newToggle = find.byKey(const ValueKey('inline-filter-toggle'));
      if (newToggle.evaluate().isNotEmpty) {
        await tapAcceptance(tester, newToggle);
      }
      expect(find.textContaining('人员、任务'), findsNothing);
      expect(find.text('补充筛选条件'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
