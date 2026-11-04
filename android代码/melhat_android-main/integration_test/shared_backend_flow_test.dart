import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/auth_pages.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';

// Credentials are supplied only through an ignored --dart-define-from-file file.
// This test intentionally refuses every host/port except the disposable QA clone.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const rawConfig = String.fromEnvironment('WEAR_QA_CONFIG');
  testWidgets('isolated real backend: routes, roles, SOS, photos and assignments', (
    t,
  ) async {
    expect(BackendConfig.mock, false);
    final base = Uri.parse(BackendConfig.baseUrl);
    expect(base.host, '127.0.0.1');
    expect(base.port, 18085);
    expect(
      rawConfig.isNotEmpty,
      true,
      reason: 'Supply the ignored QA configuration',
    );
    final config = jsonMap(jsonDecode(rawConfig));
    final checks = <String>[];
    final shots = <String>[];
    binding.reportData = {'passedChecks': checks, 'captureNames': shots};
    final site = idOf(config['siteId']);
    final fixture = jsonMap(config['fixture']);
    expect(idOf(fixture['deviceCode']).isNotEmpty, true);
    expect(idOf(fixture['workId']).isNotEmpty, true);
    final memberAccount = jsonMap(config['member']);
    final adminAccount = jsonMap(config['admin']);
    final dutyAccount = jsonMap(config['duty']);
    final runId = idOf(config['runId']);
    expect(runId.isNotEmpty && site.isNotEmpty, true);
    final pc = Dio(BaseOptions(baseUrl: BackendConfig.baseUrl));
    final portal = Dio(BaseOptions(baseUrl: BackendConfig.baseUrl));
    Object? unwrap(Object? value) {
      final map = jsonMap(value);
      return map.containsKey('code') && map.containsKey('data')
          ? map['data']
          : value;
    }

    Future<JsonMap> adminRequest(
      String method,
      String path, [
      Object? body,
    ]) async => jsonMap(
      unwrap(
        (await pc.request(
          '/api/admin/v1/$path',
          data: body,
          options: Options(method: method),
        )).data,
      ),
    );
    Future<JsonMap> portalRequest(
      String method,
      String path, [
      Object? body,
    ]) async => jsonMap(
      unwrap(
        (await portal.request(
          '/api/guardian/v1/$path',
          data: body,
          options: Options(method: method),
        )).data,
      ),
    );
    final adminLogin = await adminRequest('POST', 'login', {
      'username': adminAccount['username'],
      'password': adminAccount['password'],
    });
    pc.options.headers['X-Wearable-Token'] = adminLogin['token'];
    final dutyLogin = await portalRequest('POST', 'login', {
      'account': dutyAccount['username'],
      'password': dutyAccount['password'],
    });
    portal.options.headers['X-Wearable-Token'] = dutyLogin['token'];
    final originalConfig = await adminRequest('GET', 'business-config');
    Future<void> workMode(bool enabled) async {
      final current = await adminRequest('GET', 'business-config');
      if (current['workBusinessEnabled'] != enabled) {
        await adminRequest('PATCH', 'business-config', {
          'workBusinessEnabled': enabled,
          'expectedVersion': current['version'],
        });
      }
    }

    final member = WearSession(mock: false, credentials: MockCredentialStore());
    final manager = WearSession(
      mock: false,
      credentials: MockCredentialStore(),
    );
    var converted = false;
    GoRouter? router;
    Future<void> settle() => t.pumpAndSettle(
      const Duration(milliseconds: 150),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 30),
    );
    Future<void> waitFor(
      Finder finder, {
      String reason = 'Expected real backend page',
    }) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await t.pump(const Duration(milliseconds: 150));
      }
      expect(finder, findsWidgets, reason: reason);
    }

    Future<void> click(Finder finder) async {
      await waitFor(finder);
      await t.ensureVisible(finder.first);
      await settle();
      await t.tap(finder.first);
      await settle();
    }

    Future<void> enter(String key, String text) async {
      final finder = find.byKey(ValueKey(key));
      await waitFor(finder);
      await t.ensureVisible(finder);
      await t.enterText(finder, text);
      await settle();
    }

    Future<void> shot(String name) async {
      if (!converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
      }
      await settle();
      await binding.takeScreenshot(name);
      shots.add(name);
    }

    Future<void> mount(WearSession session, String key) async {
      await t.pumpWidget(const SizedBox.shrink());
      await settle();
      await t.pumpWidget(
        WearApp(
          key: ValueKey(key),
          session: session,
          enableNotifications: false,
        ),
      );
      await settle();
      final anchor = session.me == null
          ? find.byType(WearLoginPage)
          : find.byType(NavigationBar);
      await waitFor(anchor);
      router = GoRouter.of(t.element(anchor.first));
    }

    Future<void> open(String path) async {
      router!.go(path);
      await settle();
    }

    Future<void> awaitWorkMode(WearSession session, bool enabled) async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      do {
        await session.refreshBusinessConfig();
        if (session.workBusinessEnabled == enabled) break;
        await t.pump(const Duration(milliseconds: 300));
      } while (DateTime.now().isBefore(deadline));
      expect(session.workBusinessEnabled, enabled);
      await settle();
    }

    Future<JsonMap> eventOf(String id) async {
      member.api.shared.clearReadCache();
      return jsonMap(await member.api.get('/api/v1/events/$id'));
    }

    String? returnedDevice;
    String? originalAssignmentDevice;
    try {
      await member.initialize();
      await mount(member, 'member');
      final unauthenticatedRoutes = [
        '/login',
        '/sites',
        '/workbench',
        '/sos-events',
        '/people',
        '/people-admin/equipment/unknown',
        '/people/unknown',
        '/devices',
        '/devices/unknown',
        '/tasks',
        '/tasks/unknown',
        '/communications',
        '/events',
        '/me',
      ];
      for (final path in unauthenticatedRoutes) {
        await open(path);
        expect(find.byType(WearLoginPage), findsOneWidget);
      }
      checks.add('14 unauthenticated route redirects');
      await shot('01-login');
      await t.enterText(
        find.byType(TextFormField).at(0),
        idOf(memberAccount['username']),
      );
      await t.enterText(
        find.byType(TextFormField).at(1),
        idOf(memberAccount['password']),
      );
      await click(find.widgetWithText(FilledButton, '登录'));
      await waitFor(find.byType(NavigationBar));
      expect(member.isAdmin, false);
      expect(member.personId.isNotEmpty, true);
      expect(member.canRequestSos, true);
      checks.add('member login and real identity');
      await shot('02-member-home');
      await expectLater(
        member.selectSite('site-2'),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 403)),
      );
      await workMode(false);
      await awaitWorkMode(member, false);
      await open('/tasks/${fixture['workId']}');
      expect(router!.routeInformationProvider.value.uri.path, '/workbench');
      checks.add('disabled work route redirects without fabricated content');
      await workMode(true);
      await awaitWorkMode(member, true);
      final works = await member.api.page('/api/v1/work-tasks/mine');
      expect(
        works.records.any((w) => idOf(w['id']) == idOf(fixture['workId'])),
        true,
      );
      final equipment = jsonList(await member.api.get('/api/v1/me/equipment'));
      expect(equipment, isNotEmpty);
      final ownDevice = equipment.firstWhere(
        (d) => idOf(d['sn']) == idOf(fixture['deviceCode']),
      );
      originalAssignmentDevice = idOf(ownDevice['deviceId']);
      final routes = <String>[
        '/login',
        '/sites',
        '/workbench',
        '/sos-events',
        '/people',
        '/people-admin/equipment/${member.personId}',
        '/people/${member.personId}',
        '/devices',
        '/devices/$originalAssignmentDevice',
        '/tasks',
        '/tasks/${fixture['workId']}',
        '/communications',
        '/events',
        '/me',
      ];
      for (var i = 0; i < routes.length; i++) {
        await open(routes[i]);
        expect(t.takeException(), isNull, reason: 'member route $i');
        if ([4, 5, 6, 7].contains(i)) {
          expect(router!.routeInformationProvider.value.uri.path, '/workbench');
        }
        await shot('member-route-${i + 1}');
      }
      checks.add('14 member routes and restricted management redirects');
      await open('/workbench');
      await click(find.byKey(const ValueKey('home-manual-sos')));
      await shot('03-sos-form');
      await click(find.byKey(const ValueKey('manual-sos-submit')));
      await click(find.text('确认求助'));
      await waitFor(find.text('手机手动求助'));
      expect(find.byKey(const ValueKey('event-claim')), findsNothing);
      await enter('event-observation', '$runId Android 实际接口现场补充');
      await click(find.byKey(const ValueKey('event-observation-submit')));
      await waitFor(find.textContaining('现场情况已补充'));
      var snapshot = jsonMap((await portalRequest('GET', 'snapshot'))['state']);
      var event = jsonList(snapshot['events']).firstWhere(
        (e) => jsonList(
          e['observations'],
        ).any((o) => idOf(o['situation']).contains(runId)),
      );
      final eventId = idOf(event['id']);
      expect(event['source'], 'manual_sos');
      expect(event['deviceId'] ?? '', isEmpty);
      checks.add('member SOS and observation persisted in shared snapshot');
      await shot('04-sos-observation');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jWZkAAAAASUVORK5CYII=',
      );
      await member.api.post(
        '/api/v1/events/$eventId/report',
        data: FormData.fromMap({
          'version': event['version'],
          'comment': '$runId attachment',
          'files': [MultipartFile.fromBytes(png, filename: 'qa.png')],
        }),
      );
      snapshot = jsonMap((await portalRequest('GET', 'snapshot'))['state']);
      final photo = jsonList(
        snapshot['media'],
      ).firstWhere((m) => m['eventId'] == eventId);
      final downloaded = await portal.get<List<int>>(
        '/api/guardian/v1/files/${photo['blobId']}',
        options: Options(responseType: ResponseType.bytes),
      );
      expect(downloaded.data, png);
      checks.add('multipart photo persisted and downloaded byte-for-byte');
      final body = {'requestId': SharedBackend.requestId()};
      final second = jsonMap(
        await member.api.post('/api/v1/events/manual-sos', data: body),
      );
      expect(
        jsonMap(
          await member.api.post('/api/v1/events/manual-sos', data: body),
        )['id'],
        second['id'],
      );
      checks.add('SOS request idempotency');
      await manager.login(
        idOf(adminAccount['username']),
        idOf(adminAccount['password']),
      );
      await manager.selectSite(site);
      await manager.refreshBusinessConfig();
      expect(manager.isAdmin, true);
      await mount(manager, 'manager');
      for (var i = 0; i < routes.length; i++) {
        await open(routes[i]);
        expect(t.takeException(), isNull, reason: 'manager route $i');
        if (i == 3) {
          expect(
            router!.routeInformationProvider.value.uri.queryParameters['type'],
            'sos',
          );
        }
        if ([4, 5, 6, 7, 8, 9, 10, 11, 12, 13].contains(i)) {
          expect(
            router!.routeInformationProvider.value.uri.path,
            routes[i].split('?').first,
          );
        }
        await shot('manager-route-${i + 1}');
      }
      checks.add('14 manager routes using actual person device work IDs');
      await open('/events?eventId=$eventId');
      await click(find.byKey(const ValueKey('event-claim')));
      await click(find.byKey(const ValueKey('sos-join')));
      await click(find.byKey(const ValueKey('sos-end')));
      await click(find.text('确认'));
      event = await eventOf(eventId);
      expect(event['status'], 'handling');
      expect(jsonMap(event['assistance'])['state'], 'ended');
      expect(
        jsonMap((await eventOf(idOf(second['id'])))['assistance'])['state'],
        'waiting',
      );
      await shot('05-assistance-ended');
      await click(find.byKey(const ValueKey('verification-conclusion')));
      await click(find.text('需现场处理').last);
      await enter('verification-situation', '$runId Android 核验完成');
      await enter('verification-measures', '隔离测试确认现场安全');
      await click(find.byKey(const ValueKey('verification-save')));
      await click(find.byKey(const ValueKey('verification-submit')));
      await click(find.text('确认'));
      await waitFor(find.text('核验结果（只读）'));
      expect((await eventOf(eventId))['status'], 'verified');
      await shot('06-verification-complete');
      await expectLater(
        member.api.post(
          '/api/v1/events/$eventId/report',
          data: {'version': event['version'], 'comment': 'stale version'},
        ),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 409)),
      );
      checks.add(
        'UI claim assist join/end draft/final verification and stale-write rejection',
      );
      var pcEvent = await portalRequest('GET', 'events/${second['id']}');
      for (final action in [
        'claim',
        'assist-join',
        'assist-end',
        'verification',
      ]) {
        pcEvent = await portalRequest(
          'POST',
          'events/${second['id']}/$action',
          {
            'requestId': SharedBackend.requestId(),
            'expectedVersion': pcEvent['version'],
            if (action == 'verification') ...{
              'conclusion': '需现场处理',
              'situation': '$runId PC 完成',
              'measures': '隔离验证',
            },
          },
        );
      }
      expect((await eventOf(idOf(second['id'])))['status'], 'verified');
      checks.add('PC write observed by Android');
      manager.api.shared.clearReadCache();
      Future<void> awaitAssignment(bool expected) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        var actual = !expected;
        do {
          member.api.shared.clearReadCache();
          actual = jsonList(
            await member.api.get('/api/v1/me/equipment'),
          ).any((d) => idOf(d['deviceId']) == originalAssignmentDevice);
          if (actual == expected) break;
          await t.pump(const Duration(milliseconds: 300));
        } while (DateTime.now().isBefore(deadline));
        expect(
          actual,
          expected,
          reason: 'Assignment must persist in the real shared backend',
        );
      }

      Finder fixtureRow() => find.ancestor(
        of: find.text(idOf(fixture['deviceCode'])),
        matching: find.byType(ListTile),
      );
      await open('/people-admin/equipment/${member.personId}');
      await waitFor(fixtureRow());
      await click(
        find.descendant(
          of: fixtureRow(),
          matching: find.widgetWithText(TextButton, '归还'),
        ),
      );
      await click(find.widgetWithText(FilledButton, '确认'));
      await awaitAssignment(false);
      returnedDevice = originalAssignmentDevice;
      await shot('07-manager-returned');
      await mount(member, 'member-returned');
      await open('/me');
      await click(find.text('我的装备'));
      await shot('07-equipment-returned');
      await click(find.text('绑定历史'));
      await waitFor(find.textContaining('归还 '));
      await shot('08-equipment-history');
      manager.api.shared.clearReadCache();
      await mount(manager, 'manager-reissue');
      await open('/people-admin/equipment/${member.personId}');
      await waitFor(find.byType(TextField));
      await t.enterText(
        find.byType(TextField).first,
        idOf(fixture['deviceCode']),
      );
      await t.testTextInput.receiveAction(TextInputAction.done);
      await settle();
      await waitFor(fixtureRow());
      await click(
        find.descendant(
          of: fixtureRow(),
          matching: find.widgetWithText(OutlinedButton, '分配'),
        ),
      );
      await click(find.widgetWithText(FilledButton, '确认'));
      await awaitAssignment(true);
      returnedDevice = null;
      await shot('09-manager-reissued');
      checks.add(
        'UI QA-only equipment return/history/reissue observed across manager/member',
      );
      expect(t.takeException(), isNull);
      binding.reportData = {
        ...?binding.reportData,
        'passedChecks': checks,
        'captureNames': shots,
        'eventIds': [eventId, second['id']],
        'siteId': site,
        'workId': fixture['workId'],
        'deviceId': originalAssignmentDevice,
      };
    } finally {
      if (returnedDevice != null && manager.me != null) {
        manager.api.shared.clearReadCache();
        final person = jsonMap(
          await manager.api.get('/api/v1/people/${member.personId}'),
        );
        final device = jsonMap(
          await manager.api.get('/api/v1/devices/$returnedDevice'),
        );
        await manager.api.post(
          '/api/v1/assignments',
          data: {
            'idempotencyKey': SharedBackend.requestId(),
            'personId': member.personId,
            'deviceId': returnedDevice,
            'personVersion': person['version'],
            'deviceVersion': device['version'],
          },
        );
      }
      await workMode(originalConfig['workBusinessEnabled'] == true);
      await t.pumpWidget(const SizedBox.shrink());
      await settle();
      await manager.logout();
      await member.logout();
      manager.dispose();
      member.dispose();
      pc.close();
      portal.close();
    }
  }, timeout: const Timeout(Duration(minutes: 18)));
}
