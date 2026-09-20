import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'wear_session_test.dart'
    show MemoryCredentials, transport, identity, reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final telemetryFailure in [false, true]) {
    testWidgets(
      'real equipment and history retain endpoints; telemetry failure $telemetryFailure',
      (tester) async {
        final reads = <String>[];
        final writes = <String>[];
        const assignment = <String, dynamic>{
          'id': '8',
          'deviceId': '42',
          'personId': '7',
          'personName': '实际人员',
          'sn': 'REAL-H042',
          'typeCode': 'helmet',
          'issuedAt': '2026-09-18T08:10:00+08:00',
        };
        var equipmentFailed = true;
        var historyFailed = true;
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  reads.add(r.path);
                  if (r.method != 'GET') writes.add(r.path);
                  if (r.path == '/api/v1/me/equipment') {
                    return equipmentFailed
                        ? reply(null, code: 500, msg: '测试网络失败')
                        : reply([assignment]);
                  }
                  if (r.path == '/api/v1/devices/42') {
                    return telemetryFailure
                        ? reply(null, code: 403)
                        : reply({
                            'id': '42',
                            'sn': 'REAL-H042',
                            'typeCode': 'helmet',
                            'online': '1',
                            'connectionQuality': 'ok',
                            'lastReportedAt': '2026-09-18T09:00:00+08:00',
                          });
                  }
                  if (r.path == '/api/v1/people/7/assignments') {
                    return historyFailed
                        ? reply(null, code: 500)
                        : reply([
                            assignment,
                            {
                              ...assignment,
                              'id': '6',
                              'returnedAt': '2026-09-17T18:00:00+08:00',
                              'returnReason': '检修',
                            },
                          ]);
                  }
                  if (r.path.endsWith('/assignments') ||
                      r.path.endsWith('/handovers')) {
                    return reply([]);
                  }
                  if (r.path.endsWith('/inbox/count')) {
                    return reply({'count': 0});
                  }
                  return reply({
                    'records': [],
                    'total': 0,
                    'current': 1,
                    'size': 20,
                  });
                }),
              )
              ..initialized = true
              ..me = identity(user: 'real-equipment-$telemetryFailure')
              ..siteId = '1'
              ..token = 'test-only';
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NavigationDestination).at(3));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('我的装备'));
        await tester.tap(find.text('我的装备'));
        await tester.pumpAndSettle();
        expect(find.text('装备信息暂不可用'), findsOneWidget);
        expect(find.text('RL-H001'), findsNothing);
        equipmentFailed = false;
        await tester.tap(find.text('重新加载'));
        await tester.pumpAndSettle();
        expect(find.text('REAL-H042'), findsOneWidget);
        expect(find.text('实际人员'), findsOneWidget);
        expect(find.text(telemetryFailure ? '状态未知' : '在线'), findsOneWidget);
        await tester.ensureVisible(find.text('绑定历史'));
        await tester.tap(find.text('绑定历史'));
        await tester.pumpAndSettle();
        expect(find.text('绑定历史暂不可用'), findsOneWidget);
        historyFailed = false;
        await tester.tap(find.text('重新加载'));
        await tester.pumpAndSettle();
        expect(find.textContaining('原因 检修'), findsOneWidget);
        expect(reads, contains('/api/v1/people/7/assignments'));
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('equipment-card-42')),
        );
        await tester.tap(find.byKey(const ValueKey('equipment-card-42')));
        await tester.pumpAndSettle();
        expect(reads, contains('/api/v1/devices/42/assignments'));
        if (!telemetryFailure) expect(find.text('产品型号'), findsOneWidget);
        expect(writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'empty backend equipment preserves navigation without local fixtures $scale',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final writes = <String>[];
        final session =
            WearSession(
                credentials: MemoryCredentials(),
                dio: transport((r) {
                  if (r.method != 'GET') writes.add(r.path);
                  if (r.path.endsWith('/inbox/count')) {
                    return reply({'count': 0});
                  }
                  if (r.path.endsWith('/equipment') ||
                      r.path.endsWith('/handovers')) {
                    return reply([]);
                  }
                  return reply({
                    'records': [],
                    'total': 0,
                    'current': 1,
                    'size': 20,
                  });
                }),
              )
              ..initialized = true
              ..me = identity(user: 'equipment-$scale')
              ..siteId = '1'
              ..token = 'test-only';
        addTearDown(session.dispose);
        await tester.pumpWidget(
          WearApp(session: session, enableNotifications: false),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NavigationDestination).at(3));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('我的装备'));
        await tester.tap(find.text('我的装备'));
        await tester.pumpAndSettle();
        expect(find.text('暂无领用装备'), findsOneWidget);
        expect(find.text('RL-H001'), findsNothing);
        expect(find.text('设计预览 · 示例数据'), findsNothing);
        expect(
          tester
              .widget<WearRollingWordmark>(find.byType(WearRollingWordmark))
              .height,
          23,
        );
        expect(tester.getSize(find.byType(NavigationBar)).height, 60);
        await tester.ensureVisible(find.byTooltip('返回我的'));
        await tester.tap(find.byTooltip('返回我的'));
        await tester.pumpAndSettle();
        expect(find.text('通讯服务'), findsOneWidget);
        expect(tester.getSize(find.byType(NavigationBar)).height, 60);
        expect(writes, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
