import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';

// Run only against the disposable Docker QA instance, with adb reverse tcp:18085.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('WEAR_CAPTURE');
  testWidgets(
    'real shared backend: member and manager, SOS, photos, conflicts and assignments',
    (t) async {
      expect(BackendConfig.mock, false);
      expect(
        Uri.parse(BackendConfig.baseUrl).port,
        18085,
        reason: 'Never mutate the live database from this test',
      );
      final pc = Dio(BaseOptions(baseUrl: BackendConfig.baseUrl));
      final admin = jsonMap(
        (await pc.post(
          '/api/admin/v1/login',
          data: {'username': 'admin', 'password': 'Admin@2026'},
        )).data,
      );
      pc.options.headers['X-Wearable-Token'] = admin['token'];
      final portal = Dio(BaseOptions(baseUrl: BackendConfig.baseUrl));
      final duty = jsonMap(
        (await portal.post(
          '/api/guardian/v1/login',
          data: {'account': 'duty', 'password': '123456'},
        )).data,
      );
      portal.options.headers['X-Wearable-Token'] = duty['token'];
      Future<dynamic> query(String path, {Object? body}) async =>
          (body == null
                  ? await (path.startsWith('/api/guardian/') ? portal : pc).get(
                      path,
                    )
                  : await (path.startsWith('/api/guardian/') ? portal : pc)
                        .post(path, data: body))
              .data;
      const login = 'phase3-android';
      final initialLedger = jsonMap(
        jsonMap(await query('/api/admin/v1/state'))['state'],
      );
      final existing = jsonList(
        initialLedger['accounts'],
      ).where((a) => a['loginName'] == login).firstOrNull;
      final data = <String, dynamic>{
        'name': '安卓联调人员',
        'loginName': login,
        'personId': 'person-1-2',
        'password': 'Phase3@Test2026',
        'bindings': [],
      };
      final created =
          existing ??
          jsonMap(
            jsonMap(
              await query(
                '/api/admin/v1/execute',
                body: {
                  'type': 'accounts.create',
                  'input': {
                    'siteId': 'site-1',
                    'operationId': SharedBackend.requestId(),
                    'data': data,
                  },
                },
              ),
            )['data'],
          );
      data.remove('password');
      data['bindings'] = [
        {
          'roleId': 'mobile-user',
          'siteIds': ['site-1'],
          'areaIds': '*',
        },
      ];
      final update = <String, dynamic>{
        'siteId': 'site-1',
        'id': created['id'],
        'expectedVersion': created['version'],
        'operationId': SharedBackend.requestId(),
        'data': data,
      };
      final preview = jsonMap(
        jsonMap(
          await query(
            '/api/admin/v1/query',
            body: {
              'kind': 'authorizationPreview',
              'input': {
                'siteId': 'site-1',
                'type': 'accounts.update',
                'command': update,
              },
            },
          ),
        )['data'],
      );
      update['previewId'] = preview['previewId'];
      await query(
        '/api/admin/v1/execute',
        body: {'type': 'accounts.update', 'input': update},
      );
      final member = WearSession(
        mock: false,
        credentials: MockCredentialStore(),
      );
      await member.initialize();
      await t.pumpWidget(WearApp(session: member, enableNotifications: false));
      Future<void> settle() async {
        await t.pumpAndSettle(
          const Duration(milliseconds: 150),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 30),
        );
      }

      Future<void> click(Finder finder) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await t.pump(const Duration(milliseconds: 150));
        }
        expect(finder, findsOneWidget, reason: '操作入口应已加载');
        while (DateTime.now().isBefore(deadline)) {
          final widget = t.widget(finder);
          if (widget is! ButtonStyleButton || widget.onPressed != null) break;
          await t.pump(const Duration(milliseconds: 150));
        }
        await t.ensureVisible(finder);
        await settle();
        await t.tap(finder);
        await settle();
      }

      Future<void> enter(String key, String text) async {
        final f = find.byKey(ValueKey(key));
        await t.ensureVisible(f);
        await t.enterText(f, text);
        await settle();
      }

      Future<void> awaitText(String text) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (find.text(text).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await t.pump(const Duration(milliseconds: 150));
        }
        expect(
          find.text(text),
          findsOneWidget,
          reason: find
              .byType(Text)
              .evaluate()
              .map((e) => (e.widget as Text).data)
              .whereType<String>()
              .take(40)
              .join(' | '),
        );
      }

      Future<void> open(String path) async {
        unawaited(
          GoRouter.of(t.element(find.byType(NavigationBar))).push(path),
        );
        await settle();
      }

      var surfaceConverted = false;
      Future<void> screenshot(String name) async {
        if (!capture) return;
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await settle();
        await binding.takeScreenshot(name);
      }

      await settle();
      await t.enterText(find.byType(TextFormField).at(0), login);
      await t.enterText(find.byType(TextFormField).at(1), 'Phase3@Test2026');
      await click(find.widgetWithText(FilledButton, '登录'));
      expect(member.personId, 'P3');
      expect(member.isAdmin, false);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.text('发起值班交接'), findsNothing);
      await screenshot('01-member-home');
      await expectLater(
        member.api.get('/api/v1/people/P2'),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 404)),
      );
      await expectLater(
        member.selectSite('site-2'),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 403)),
      );
      final equipment = jsonList(await member.api.get('/api/v1/me/equipment'));
      expect(equipment, isNotEmpty);
      await open('/devices/${equipment.first['deviceId']}');
      expect(find.text(idOf(equipment.first['deviceId'])), findsWidgets);
      GoRouter.of(t.element(find.byType(NavigationBar))).pop();
      await settle();
      final works = await member.api.page('/api/v1/work-tasks/mine');
      expect(works.records, isNotEmpty);
      await open('/tasks/${works.records.first['id']}');
      expect(find.text('调整人员'), findsNothing);
      await click(find.byKey(const ValueKey('task-event-records')));
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );
      await click(find.byType(NavigationDestination).at(1));
      expect(find.text('设备语音'), findsOneWidget);
      await screenshot('02-member-communications');
      expect(find.text('视频群聊'), findsNothing);
      await click(find.byType(NavigationDestination).at(3));
      expect(find.text('重试绑定'), findsNothing);
      await click(find.byType(NavigationDestination).at(0));
      expect(member.canRequestSos, true);
      expect(
        GoRouter.of(
          t.element(find.byType(NavigationBar)),
        ).routerDelegate.currentConfiguration.uri.path,
        '/workbench',
      );
      await click(find.byKey(const ValueKey('home-manual-sos')));
      await click(find.byKey(const ValueKey('manual-sos-submit')));
      await click(find.text('确认求助'));
      await awaitText('手机手动求助');
      expect(find.textContaining('模拟 SOS 已创建'), findsNothing);
      expect(find.text('最终核验'), findsNothing);
      await enter('event-observation', '模拟器真实接口联调：人员已在安全区域');
      await click(find.byKey(const ValueKey('event-observation-submit')));
      var snapshot = jsonMap(
        jsonMap(await query('/api/guardian/v1/snapshot'))['state'],
      );
      var event = jsonList(snapshot['events']).firstWhere(
        (e) => jsonList(
          e['observations'],
        ).any((o) => idOf(o['situation']).contains('模拟器真实接口联调')),
      );
      expect(event['source'], 'manual_sos');
      expect(event['deviceId'] ?? '', isEmpty);
      expect(
        jsonList(event['observations']).last['situation'],
        contains('安全区域'),
      );
      final id = idOf(event['id']);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII=',
      );
      await member.api.post(
        '/api/v1/events/$id/report',
        data: FormData.fromMap({
          'version': event['version'],
          'comment': '现场照片补充',
          'files': [MultipartFile.fromBytes(png, filename: 'site.png')],
        }),
      );
      snapshot = jsonMap(
        jsonMap(await query('/api/guardian/v1/snapshot'))['state'],
      );
      expect(
        jsonList(snapshot['media']).where((m) => m['eventId'] == id),
        isNotEmpty,
      );
      final photo = jsonList(
        snapshot['media'],
      ).firstWhere((m) => m['eventId'] == id);
      final bytes = await portal.get<List<int>>(
        '/api/guardian/v1/files/${photo['blobId']}',
        options: Options(responseType: ResponseType.bytes),
      );
      expect(bytes.data, png);
      final sosBody = {'requestId': SharedBackend.requestId()};
      final second = jsonMap(
        await member.api.post('/api/v1/events/manual-sos', data: sosBody),
      );
      expect(
        jsonMap(
          await member.api.post('/api/v1/events/manual-sos', data: sosBody),
        )['id'],
        second['id'],
      );
      expect(second['id'], isNot(id));
      await t.pumpWidget(const SizedBox.shrink());
      await settle();
      final manager = WearSession(
        mock: false,
        credentials: MockCredentialStore(),
      );
      await manager.login('admin', 'Admin@2026');
      await manager.selectSite('site-1');
      await t.pumpWidget(
        WearApp(
          key: const ValueKey('manager'),
          session: manager,
          enableNotifications: false,
        ),
      );
      await settle();
      expect(manager.isAdmin, true);
      expect(find.byKey(const ValueKey('home-manual-sos')), findsNothing);
      await screenshot('03-manager-home');
      await click(find.byType(NavigationDestination).at(1));
      await awaitText('当前范围内暂无支持语音或广播的设备；手机求助和事件文字跟进仍可使用。');
      expect(
        t.widget<TextButton>(find.widgetWithText(TextButton, '设备语音')).onPressed,
        isNull,
      );
      await screenshot('04-manager-communications');
      await open('/events?eventId=$id');
      await click(find.byKey(const ValueKey('event-claim')));
      await click(find.byKey(const ValueKey('sos-join')));
      await click(find.byKey(const ValueKey('sos-end')));
      await click(find.text('确认'));
      event = jsonMap(await member.api.get('/api/v1/events/$id'));
      expect(event['status'], 'handling');
      expect(event['assistance']['state'], 'ended');
      expect(
        jsonMap(
          await member.api.get('/api/v1/events/${second['id']}'),
        )['assistance']['state'],
        'waiting',
      );
      await click(find.byKey(const ValueKey('verification-conclusion')));
      await click(find.text('需现场处理').last);
      await enter('verification-situation', '联调现场复核完成');
      await enter('verification-measures', '安排人员陪同');
      await click(find.byKey(const ValueKey('verification-save')));
      await click(find.byKey(const ValueKey('verification-submit')));
      await click(find.text('确认'));
      await awaitText('核验结果（只读）');
      await screenshot('05-verification-complete');
      expect(
        jsonMap(await member.api.get('/api/v1/events/$id'))['status'],
        'verified',
      );
      await expectLater(
        member.api.post(
          '/api/v1/events/$id/report',
          data: {'version': event['version'], 'comment': '过期覆盖'},
        ),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 409)),
      );
      // The other direction: PC duty writes the same event services, Android observes completion.
      var pcEvent = jsonMap(
        await query('/api/guardian/v1/events/${second['id']}'),
      );
      for (final action in [
        'claim',
        'assist-join',
        'assist-end',
        'verification',
      ]) {
        pcEvent = jsonMap(
          await query(
            '/api/guardian/v1/events/${second['id']}/$action',
            body: {
              'requestId': SharedBackend.requestId(),
              'expectedVersion': pcEvent['version'],
              if (action == 'verification') ...{
                'conclusion': '需现场处理',
                'situation': 'PC 值守复核完成',
                'measures': '现场已确认',
              },
            },
          ),
        );
      }
      expect(
        jsonMap(
          await member.api.get('/api/v1/events/${second['id']}'),
        )['status'],
        'verified',
      );
      // Existing PC ledger and Android read exactly the same assignment records.
      var person = jsonMap(await manager.api.get('/api/v1/people/P3'));
      final assigned = jsonList(
        await manager.api.get('/api/v1/people/P3/equipment'),
      ).firstWhere((a) => a['typeCode'] == 'watch');
      await manager.api.post(
        '/api/v1/assignments/${assigned['id']}/return',
        data: {
          'idempotencyKey': SharedBackend.requestId(),
          'personVersion': person['version'],
          'deviceVersion': assigned['deviceVersion'],
          'assignmentVersion': assigned['version'],
        },
      );
      expect(
        jsonList(
          await member.api.get('/api/v1/me/equipment'),
        ).any((a) => a['deviceId'] == assigned['deviceId']),
        false,
      );
      person = jsonMap(await manager.api.get('/api/v1/people/P3'));
      final device = jsonMap(
        await manager.api.get('/api/v1/devices/${assigned['deviceId']}'),
      );
      await manager.api.post(
        '/api/v1/assignments',
        data: {
          'idempotencyKey': SharedBackend.requestId(),
          'personId': 'P3',
          'deviceId': device['id'],
          'personVersion': person['version'],
          'deviceVersion': device['version'],
        },
      );
      expect(
        jsonList(
          await member.api.get('/api/v1/me/equipment'),
        ).any((a) => a['deviceId'] == device['id']),
        true,
      );
      final ledger = jsonMap(
        jsonMap(await query('/api/admin/v1/state'))['state'],
      );
      expect(
        jsonList(ledger['assignments']).any(
          (a) =>
              a['active'] == true &&
              a['personId'] == 'person-1-2' &&
              a['deviceId'] == device['ledgerId'],
        ),
        true,
      );

      // No helmet, watch, location or voice is required for phone SOS.
      final allEquipment = jsonList(
        await manager.api.get('/api/v1/people/P3/equipment'),
      );
      for (final row in allEquipment) {
        final currentPerson = jsonMap(
          await manager.api.get('/api/v1/people/P3'),
        );
        await manager.api.post(
          '/api/v1/assignments/${row['id']}/return',
          data: {
            'idempotencyKey': SharedBackend.requestId(),
            'personVersion': currentPerson['version'],
            'deviceVersion': row['deviceVersion'],
            'assignmentVersion': row['version'],
          },
        );
      }
      expect(jsonList(await member.api.get('/api/v1/me/equipment')), isEmpty);
      await t.pumpWidget(const SizedBox.shrink());
      await settle();
      await t.pumpWidget(
        WearApp(
          key: const ValueKey('member-no-device'),
          session: member,
          enableNotifications: false,
        ),
      );
      await settle();
      await click(find.byType(NavigationDestination).at(3));
      await click(find.text('我的装备'));
      await awaitText('暂无领用装备');
      await screenshot('06-no-device-equipment');
      await click(find.text('绑定历史'));
      final historyDeadline = DateTime.now().add(const Duration(seconds: 20));
      while (find.textContaining('归还 ').evaluate().isEmpty &&
          DateTime.now().isBefore(historyDeadline)) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(find.textContaining('归还 '), findsWidgets);
      expect(find.textContaining('未知类型'), findsNothing);
      expect(find.textContaining('领用 时间未知'), findsNothing);
      await screenshot('07-returned-history');
      await click(find.text('关闭'));
      await click(find.byTooltip('返回我的'));
      await click(find.byType(NavigationDestination).at(0));
      await click(find.byKey(const ValueKey('home-manual-sos')));
      await screenshot('08-no-device-sos-form');
      await click(find.byKey(const ValueKey('manual-sos-submit')));
      await click(find.text('确认求助'));
      await awaitText('手机手动求助');
      await enter('event-observation', '无装备验收：人在东门，使用文字跟进');
      await click(find.byKey(const ValueKey('event-observation-submit')));
      await screenshot('09-no-device-sos-observation');
      final finalSnapshot = jsonMap(
        jsonMap(await query('/api/guardian/v1/snapshot'))['state'],
      );
      final noDeviceEvent = jsonList(finalSnapshot['events']).singleWhere(
        (e) => jsonList(
          e['observations'],
        ).any((o) => idOf(o['situation']).contains('无装备验收')),
      );
      expect(noDeviceEvent['deviceId'] ?? '', isEmpty);
      expect(noDeviceEvent['source'], 'manual_sos');
      expect(noDeviceEvent['status'], '待认领');
      final finalLedger = jsonMap(
        jsonMap(await query('/api/admin/v1/state'))['state'],
      );
      expect(
        jsonList(
          finalLedger['assignments'],
        ).where((a) => a['active'] == true && a['personId'] == 'person-1-2'),
        isEmpty,
      );

      // Account disable must invalidate a previously working mobile session.
      final account = jsonList(
        finalLedger['accounts'],
      ).singleWhere((a) => a['loginName'] == login);
      await query(
        '/api/admin/v1/execute',
        body: {
          'type': 'accounts.status',
          'input': {
            'siteId': 'site-1',
            'id': account['id'],
            'expectedVersion': account['version'],
            'enabled': false,
            'reason': '隔离无设备验收',
            'confirm': true,
            'operationId': SharedBackend.requestId(),
          },
        },
      );
      await member.refreshIdentity();
      await settle();
      expect(member.me, isNull);
      expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
      await screenshot('10-disabled-account-login');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await settle();
      await manager.logout();
      await member.logout();
      manager.dispose();
      member.dispose();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
