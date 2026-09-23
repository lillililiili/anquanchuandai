import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_policy.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('manual SOS approval is offered only to another administrator', () {
    final event = WearEvent.fromJson({
      'id': '90',
      'type': 'sos',
      'source': 'manual_sos',
      'reporterUserId': '12',
      'status': 'pending_review',
      'severity': 'emergency',
    });
    EventActor actor(String id, bool admin) => EventActor(
      userId: id,
      roles: {if (admin) 'admin'},
      permissions: {'*:*:*'},
    );
    expect(
      EventPolicy.can(EventCommand.close, event, actor('12', false)),
      isFalse,
    );
    expect(
      EventPolicy.can(EventCommand.close, event, actor('12', true)),
      isFalse,
    );
    expect(
      EventPolicy.can(EventCommand.close, event, actor('1', true)),
      isTrue,
    );
    expect(
      EventPolicy.can(EventCommand.handle, event, actor('1', true)),
      isFalse,
    );
  });
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'manual SOS validates, preserves retry and opens approval at $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final writes = <RequestOptions>[];
        final pending = Completer<ResponseBody>();
        var submitted = false;
        final event = <String, dynamic>{
          'id': '90',
          'type': 'sos',
          'source': 'manual_sos',
          'status': 'pending_review',
          'severity': 'emergency',
          'siteId': '1',
          'version': 1,
          'alarmName': '手动 SOS 报警',
          'alarmDescription': '锅炉平台：需要协助',
        };
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (r.method == 'POST') {
                    writes.add(r);
                    if (writes.length == 1) {
                      return reply(null, code: 503, msg: '测试连接中断');
                    }
                    return pending.future;
                  }
                  if (r.path == '/api/v1/events/90') return reply(event);
                  if (r.path == '/api/v1/events') {
                    return reply({
                      'records': submitted ? [event] : [],
                      'total': submitted ? 1 : 0,
                    });
                  }
                  if (r.path.endsWith('/inbox/count')) {
                    return reply({'count': submitted ? 1 : 0});
                  }
                  if (r.path == '/api/v1/duty/summary') {
                    return reply({'activeTasks': []});
                  }
                  return reply([]);
                }),
              )
              ..initialized = true
              ..token = 'test'
              ..siteId = '1'
              ..me = identity(user: 'manual-sos-$scale');
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(const ValueKey('home-manual-sos'));
        await tester.scrollUntilVisible(
          entry,
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.pumpAndSettle();
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        final button = find.byKey(const ValueKey('manual-sos-submit'));
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(writes, isEmpty);
        expect(find.text('请填写报警位置'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('manual-sos-location')),
          '锅炉平台',
        );
        await tester.enterText(
          find.byKey(const ValueKey('manual-sos-description')),
          '需要协助',
        );
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.textContaining('填写内容已保留'), findsOneWidget);
        expect(find.text('需要协助'), findsOneWidget);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        expect(writes.length, 2);
        expect(writes[0].data, writes[1].data);
        expect(writes[1].path, '/api/v1/events/manual-sos');
        expect(writes[1].headers['X-Site-Id'], '1');
        expect((writes[1].data as Map).keys.toSet(), {
          'requestId',
          'location',
          'description',
        });
        submitted = true;
        pending.complete(reply(event));
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.textContaining('无需一级审查'), findsOneWidget);
        expect(find.text('审批通过并结束'), findsNothing);
        expect(
          find.byKey(const ValueKey('event-handle-submit-90')),
          findsNothing,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'ordinary equipment detail opens and returns without privileged history requests',
    (tester) async {
      final reads = <String>[];
      final session =
          WearSession(
              credentials: MemoryCredentials(),
              dio: transport((r) {
                reads.add(r.path);
                if (r.path == '/api/v1/me/equipment') {
                  return reply([
                    {'deviceId': '42', 'sn': 'QA-H009', 'typeCode': 'helmet'},
                  ]);
                }
                if (r.path == '/api/v1/devices/42') {
                  return reply({
                    'id': '42',
                    'sn': 'QA-H009',
                    'typeCode': 'helmet',
                    'modelName': '真实设备型号',
                    'battery': 46,
                  });
                }
                if (r.path.endsWith('/assignments')) {
                  return reply(null, code: 403);
                }
                if (r.path.endsWith('/inbox/count')) return reply({'count': 0});
                if (r.path == '/api/v1/duty/summary') {
                  return reply({'activeTasks': []});
                }
                return reply([]);
              }),
            )
            ..initialized = true
            ..token = 'test'
            ..siteId = '1'
            ..me = identity();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearApp(session: session, enableNotifications: false),
      );
      await tester.pumpAndSettle();
      final equipment = find.byKey(const ValueKey('home-my-equipment'));
      await tester.scrollUntilVisible(
        equipment,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(equipment);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('equipment-card-42')));
      await tester.pumpAndSettle();
      expect(find.text('真实设备型号'), findsOneWidget);
      expect(reads, isNot(contains('/api/v1/devices/42/assignments')));
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('equipment-card-42')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
