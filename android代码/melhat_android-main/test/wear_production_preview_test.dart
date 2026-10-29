import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/tasks.dart';
import 'wear_session_test.dart' show MemoryCredentials;

void main() {
  testWidgets(
    'production never opens fabricated work after a missing external record',
    (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: 200,
                data: {
                  'code': 200,
                  'data': {
                    'operator': {},
                    'works': [],
                    'devices': [],
                    'people': [],
                    'events': [],
                  },
                },
              ),
            );
          },
        ),
      );
      final session =
          WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
            ..token = 'test'
            ..siteId = 'site-1'
            ..me = {'userId': 'u'};
      addTearDown(session.dispose);
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: const MaterialApp(home: TaskPage(id: 'ui-preview')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('查看界面示例'), findsNothing);
      expect(find.text('锅炉平台检修'), findsNothing);
      expect(find.text('陈建国'), findsNothing);
      expect(find.text('作业详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    skip: BackendConfig.mock,
  );
}
