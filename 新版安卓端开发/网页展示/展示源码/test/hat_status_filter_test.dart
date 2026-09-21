import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/http/index.dart';
import 'package:rolling_intelligence_headband/theme/app_theme.dart';
import 'package:rolling_intelligence_headband/views/home_children/hat_select.dart';

void main() {
  testWidgets('hat selector sends backend numeric status and restores all', (
    tester,
  ) async {
    final statuses = <String?>[];
    final rows = [
      {'id': '1', 'hatNumber': 'H1', 'bindUserName': '在线人员', 'status': '1'},
      {'id': '2', 'hatNumber': 'H2', 'bindUserName': '离线人员', 'status': '0'},
    ];
    final interceptor = InterceptorsWrapper(
      onRequest: (o, h) {
        final status = o.queryParameters['status'] as String?;
        statuses.add(status);
        final filtered = rows
            .where((r) => status == null || r['status'] == status)
            .toList();
        h.resolve(
          Response(
            requestOptions: o,
            statusCode: 200,
            data: {
              'code': 200,
              'msg': 'ok',
              'data': {'records': filtered, 'total': filtered.length},
            },
          ),
        );
      },
    );
    http.dio.interceptors.insert(0, interceptor);
    addTearDown(() => http.dio.interceptors.remove(interceptor));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const HatSelectPage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部状态').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('在线').last);
    await tester.pumpAndSettle();
    expect(statuses.last, '1');
    expect(find.text('在线人员'), findsOneWidget);
    expect(find.text('离线人员'), findsNothing);
    await tester.tap(find.text('在线').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('离线').last);
    await tester.pumpAndSettle();
    expect(statuses.last, '0');
    expect(find.text('离线人员'), findsOneWidget);
    await tester.tap(find.text('离线').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部状态').last);
    await tester.pumpAndSettle();
    expect(statuses.last, isNull);
    expect(find.text('在线人员'), findsOneWidget);
    expect(find.text('离线人员'), findsOneWidget);
  });
}
