import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_calls.dart';
import 'wear_lab_calls_test.dart' show row, sessionWith;
import 'wear_session_test.dart' show reply;

void main() {
  test(
    'invite preserves current call and connected member, deduplicates new IDs',
    () async {
      var current = row(state: 'connected');
      final connectedAt = current['connectedAt'];
      final requests = <RequestOptions>[];
      final session = sessionWith((r) {
        if (r.method == 'POST') {
          requests.add(r);
          current = {
            ...current,
            'participants': [
              ...jsonList(current['participants']),
              {'deviceId': 'd2', 'personId': 'p2', 'state': 'ringing'},
            ],
          };
          return reply({'call': current});
        }
        return reply({
          'calls': [current],
          'devices': [],
        });
      });
      final model = LabCallsModel(session);
      await model.poll();
      expect(await model.invite('call-1', ['d1', 'd2', 'd2']), isTrue);
      expect(requests.single.path, '/api/v1/lab/calls/call-1/invite');
      expect(requests.single.data, {
        'deviceIds': ['d2'],
      });
      expect(model.call('call-1')?['connectedAt'], connectedAt);
      expect(
        jsonList(model.call('call-1')?['participants']).map((p) => p['state']),
        ['connected', 'ringing'],
      );
      model.dispose();
      session.dispose();
    },
  );

  test(
    'pending invitation blocks duplicates and ignores changed station response',
    () async {
      final pending = Completer<ResponseBody>();
      var posts = 0;
      final session = sessionWith((r) {
        if (r.method == 'POST') {
          posts++;
          return pending.future;
        }
        return reply({
          'calls': [row(state: 'connected')],
          'devices': [],
        });
      });
      final model = LabCallsModel(session);
      await model.poll();
      final inviting = model.invite('call-1', ['d2']);
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        model.invite('call-1', ['d3']),
        throwsA(isA<WearApiException>()),
      );
      session.siteId = '2';
      model.sessionChanged();
      pending.complete(reply(row(state: 'connected')));
      expect(await inviting, isFalse);
      expect(posts, 1);
      expect(model.calls, isEmpty);
      model.dispose();
      session.dispose();
    },
  );

  test('ended or unconfirmed calls cannot invite', () async {
    final session = sessionWith(
      (r) => reply({
        'calls': [row(state: 'ended')],
        'devices': [],
      }),
    );
    final model = LabCallsModel(session);
    await model.poll();
    await expectLater(
      model.invite('call-1', ['d2']),
      throwsA(isA<WearApiException>()),
    );
    model.calls = [row(state: 'connected')];
    model.fresh = false;
    expect(model.canInvite('call-1'), isFalse);
    model.dispose();
    session.dispose();
  });

  testWidgets(
    'participant sheet searches main backend online people and invites into same call',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var current = row(state: 'connected');
      final posts = <RequestOptions>[];
      var inviteeOnline = false;
      final reads = <String>[];
      final session = sessionWith((r) {
        if (r.method == 'POST') {
          posts.add(r);
          current = {
            ...current,
            'participants': [
              ...jsonList(current['participants']),
              {
                'deviceId': 'd2',
                'personName': '李明',
                'sn': 'H002',
                'state': 'ringing',
              },
            ],
          };
          return reply({'call': current});
        }
        reads.add(r.path);
        if (r.path == '/api/v1/lab/state') {
          return reply({
            'calls': [current],
            'devices': [],
          });
        }
        if (r.path == '/api/v1/people') {
          return reply({
            'records': [
              {'id': 'p1', 'name': '当前人员'},
              {'id': 'p2', 'name': '李明'},
              {'id': 'p3', 'name': '离线人员'},
              {'id': 'p4', 'name': '无通话能力'},
            ],
            'total': 4,
          });
        }
        if (r.path == '/api/v1/devices') {
          return reply({
            'records': [
              for (var i = 1; i <= 4; i++) {'id': 'd$i'},
            ],
            'total': 4,
          });
        }
        if (r.path.startsWith('/api/v1/devices/')) {
          final i = int.parse(r.path.substring(r.path.length - 1));
          return reply({
            'id': 'd$i',
            'sn': 'H00$i',
            'online': i == 3 || (i == 2 && !inviteeOnline) ? '0' : '1',
            'connectionQuality': 'ok',
            'currentAssignment': {'personId': 'p$i'},
            'capabilities': {
              'actions': i == 4 ? ['tts'] : ['intercom'],
            },
          });
        }
        if (r.path == '/api/v1/work-tasks') {
          return reply({'records': [], 'total': 0});
        }
        throw StateError('Unexpected API: ${r.path}');
      });
      final model = LabCallsModel(session);
      await tester.runAsync(model.poll);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: MaterialApp(
            home: LabCallScope(
              model: model,
              child: const LabCallPage(id: 'call-1'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('参与人员'));
      await tester.tap(find.byIcon(Icons.people_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('邀请人员'));
      await tester.pumpAndSettle();
      expect(find.text('暂无可邀请的在线人员'), findsOneWidget);
      inviteeOnline = true;
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.text('李明'), findsOneWidget);
      expect(find.text('当前人员'), findsNothing);
      expect(find.text('离线人员'), findsNothing);
      expect(find.text('无通话能力'), findsNothing);
      await tester.enterText(find.byType(TextField), 'H002');
      await tester.pump();
      await tester.tap(find.text('李明'));
      await tester.pump();
      inviteeOnline = false;
      await tester.tap(find.byTooltip('刷新在线人员'));
      await tester.pumpAndSettle();
      expect(find.text('李明'), findsNothing);
      expect(find.text('呼叫并邀请（1 人）'), findsNothing);
      inviteeOnline = true;
      await tester.tap(find.byTooltip('刷新在线人员'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('李明'));
      await tester.pump();
      await tester.tap(find.text('呼叫并邀请（1 人）'));
      await tester.pumpAndSettle();
      expect(posts.single.data, {
        'deviceIds': ['d2'],
      });
      expect(find.text('李明 · H002'), findsOneWidget);
      expect(find.text('等待接听'), findsOneWidget);
      expect(reads, contains('/api/v1/people'));
      expect(reads, isNot(contains('/api/v1/lab/roster')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      session.dispose();
    },
  );
}
