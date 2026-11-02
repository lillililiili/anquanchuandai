import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/location_history.dart';
import 'wear_session_test.dart' show MemoryCredentials;

Widget historyPage(WearSession session, String person) => WearScope(
  session: session,
  child: MaterialApp(home: LocationHistoryPage(personId: person)),
);

void main() {
  testWidgets('changing personnel discards late history from previous wearer', (
    tester,
  ) async {
    final gate = Completer<void>();
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, handler) async {
          requests.add(r);
          final person = r.queryParameters['personId'];
          if (person == 'p1') await gate.future;
          handler.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: {
                'rows': [
                  {
                    'deviceId': 'device-$person',
                    'latitude': 31.2,
                    'longitude': 121.4,
                    'coordinateSystem': 'UNKNOWN',
                    'locationQuality': 'unknown',
                    'reportedAt': '2026-11-02T01:00:00Z',
                  },
                ],
                'nextCursor': null,
              },
            ),
          );
        },
      ),
    );
    final session =
        WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
          ..token = 'test-token'
          ..siteId = 's';
    addTearDown(session.dispose);
    await tester.pumpWidget(historyPage(session, 'p1'));
    await tester.pump();
    await tester.pumpWidget(historyPage(session, 'p2'));
    await tester.pumpAndSettle();
    expect(requests.map((r) => r.queryParameters['personId']), ['p1', 'p2']);
    expect(find.textContaining('device-p2'), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('device-p1'), findsNothing);
    expect(find.textContaining('device-p2'), findsOneWidget);
  });
  testWidgets(
    'permission revoked on next page clears previously shown history',
    (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, handler) {
            final more = r.queryParameters['cursor'] != null;
            handler.resolve(
              Response(
                requestOptions: r,
                statusCode: more ? 403 : 200,
                data: more
                    ? {'code': 403, 'message': '当前账号无轨迹访问权限'}
                    : {
                        'rows': [
                          {
                            'deviceId': 'previous-visible-device',
                            'coordinateSystem': 'UNKNOWN',
                          },
                        ],
                        'nextCursor': 'next',
                      },
              ),
            );
          },
        ),
      );
      final session =
          WearSession(dio: dio, mock: false, credentials: MemoryCredentials())
            ..token = 'test-token'
            ..siteId = 's';
      addTearDown(session.dispose);
      await tester.pumpWidget(historyPage(session, 'p1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('previous-visible-device'), findsOneWidget);
      await tester.tap(find.text('读取后续轨迹'));
      await tester.pumpAndSettle();
      expect(find.textContaining('previous-visible-device'), findsNothing);
      expect(find.textContaining('当前账号无轨迹访问权限'), findsOneWidget);
    },
  );
}
