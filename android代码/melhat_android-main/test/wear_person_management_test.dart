import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/queries/person_management.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('binary export preserves auth scope and rejects JSON errors', () async {
    var denied = false;
    final api = WearApi(
      token: () => 'test',
      siteId: () => '2',
      epoch: () => 1,
      dio: transport((r) {
        expect(r.headers['X-Site-Id'], '2');
        expect(r.headers['Authorization'], 'Bearer test');
        return denied
            ? reply(null, code: 403, msg: '无权限')
            : ResponseBody.fromBytes(
                Uint8List.fromList([80, 75, 3, 4, 1, 2]),
                200,
              );
      }),
    );
    expect(await api.request('POST', '/api/v1/people/export', binary: true), [
      80,
      75,
      3,
      4,
      1,
      2,
    ]);
    denied = true;
    await expectLater(
      api.request('POST', '/api/v1/people/export', binary: true),
      throwsA(isA<WearApiException>().having((e) => e.code, 'code', 403)),
    );
  });
  testWidgets('person edit preserves account department grants and version', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    JsonMap? saved;
    final session =
        WearSession(
            credentials: MemoryCredentials(),
            dio: transport((r) {
              if (r.method == 'PUT') {
                saved = Map<String, dynamic>.from(r.data);
                return reply(saved);
              }
              if (r.path == '/api/v1/people/8')
                return reply({
                  'name': '张三',
                  'personCode': 'P-008',
                  'version': 4,
                  'accountUserId': '19',
                  'orgDeptId': '6',
                  'siteIds': ['1', '2'],
                  'validFrom': '2026-01-01',
                  'validTo': '2027-01-01',
                });
              return reply([]);
            }),
          )
          ..initialized = true
          ..me = identity()
          ..siteId = '1';
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearScope(
        session: session,
        child: MaterialApp(home: const PersonEditorPage(id: '8')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '张三改');
    final save = find.widgetWithText(FilledButton, '保存档案');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(saved?['name'], '张三改');
    expect(saved?['accountUserId'], '19');
    expect(saved?['orgDeptId'], '6');
    expect(saved?['version'], 4);
    expect(saved?['siteIds'], ['1', '2']);
    expect(saved?['validTo'], '2027-01-01');
    expect(tester.takeException(), isNull);
  });
}
