import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_calls.dart';
import 'wear_lab_calls_test.dart' show sessionWith, row;
import 'wear_session_test.dart' show reply;

void main() {
  for (final label in ['语音群聊', '视频群聊']) {
    testWidgets(
      '$label sends both selected targets through main backend',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final posts = <RequestOptions>[];
        JsonMap? current;
        final session = sessionWith((request) {
          if (request.method == 'POST') {
            posts.add(request);
            current = {
              ...row(),
              'direction': 'outgoing',
              'sos': false,
              'participants': [
                for (final id in request.data['deviceIds'])
                  {'deviceId': id, 'state': 'ringing'},
              ],
            };
            return reply({'call': current});
          }
          if (request.path == '/api/v1/lab/state') {
            return reply({
              'calls': [?current],
              'devices': [],
            });
          }
          if (request.path == '/api/v1/people') {
            return reply({
              'records': [
                for (var i = 1; i <= 2; i++) {'id': 'p$i', 'name': '测试人员$i'},
              ],
              'total': 2,
            });
          }
          if (request.path == '/api/v1/devices') {
            return reply({
              'records': [
                for (var i = 1; i <= 2; i++) {'id': 'd$i'},
              ],
              'total': 2,
            });
          }
          if (request.path.startsWith('/api/v1/devices/')) {
            final i = request.path.substring(request.path.length - 1);
            return reply({
              'id': 'd$i',
              'sn': 'H00$i',
              'typeCode': 'helmet',
              'online': '1',
              'connectionQuality': 'ok',
              'currentAssignment': {'personId': 'p$i'},
              'capabilities': {
                'actions': ['intercom', 'video', 'tts'],
              },
            });
          }
          return reply({'records': [], 'total': 0});
        });
        session.me = {
          ...session.me!,
          'roles': ['wear_platform_admin'],
        };
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        GoRouter.of(
          tester.element(find.byType(NavigationBar)),
        ).go('/communications');
        await tester.pumpAndSettle();
        for (final name in ['测试人员1', '测试人员2']) {
          await tester.ensureVisible(find.text(name));
          await tester.pumpAndSettle();
          await tester.tap(find.text(name));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(posts, hasLength(1));
        expect(posts.single.path, '/api/v1/lab/calls');
        expect(posts.single.data, {
          'deviceIds': ['d1', 'd2'],
          'video': false,
        });
        expect(find.byType(LabCallPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: !callLabEnabled,
    );
  }
}
