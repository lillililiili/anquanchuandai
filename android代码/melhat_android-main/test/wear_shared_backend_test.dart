import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/events/event_repository.dart';
import 'package:rolling_intelligence_headband/wear/events/event_policy.dart';
import 'wear_session_test.dart' show transport, reply, MemoryCredentials;

const root = '/api/guardian/v1';
JsonMap nativeIdentity() => {
  'accountId': 'account-7',
  'personId': 'P1',
  'name': '现场人员',
  'loginName': 'worker',
  'sites': [
    {'id': 'site-1', 'name': '厂站一'},
  ],
  'permissionsBySite': {
    'site-1': ['self:read', 'works:read', 'events:observe', 'sos:create'],
  },
};
JsonMap contextData() => {
  'operator': nativeIdentity(),
  'people': [
    {'id': 'P1', 'ledgerId': 'person-1', 'name': '现场人员', 'version': 7},
  ],
  'devices': [
    {
      'id': 'RL-H001',
      'ledgerId': 'device-1',
      'type': 'H',
      'source': 'SEED',
      'online': true,
      'battery': 99,
      'version': 9,
      'lifecycle': 'IN_USE',
    },
  ],
  'assignments': [
    {
      'id': 'assignment-1',
      'personId': 'person-1',
      'deviceId': 'device-1',
      'active': true,
      'version': 4,
    },
  ],
  'events': [
    {
      'id': 'SOS-1',
      'type': '人员求助',
      'status': '待认领',
      'version': 2,
      'personId': 'P1',
      'source': 'manual_sos',
      'permissions': {'observe': true, 'claim': false},
    },
  ],
  'works': [],
  'media': [],
};
WearApi api(
  FutureOr<ResponseBody> Function(RequestOptions) handle, {
  void Function()? expired,
}) => WearApi(
  mock: false,
  dio: transport(handle),
  token: () => 'mobile-token',
  siteId: () => 'site-1',
  epoch: () => 1,
  onUnauthorized: expired,
);

void main() {
  test(
    'native verification preserves operator, time and attached photo IDs',
    () {
      final projected = SharedModels({}).event({
        'id': 'E1',
        'status': '已核验',
        'verification': {
          'actorName': 'PC 值守',
          'submittedAt': '2026-10-07T10:00:00Z',
          'photoIds': ['upload-one'],
          'situation': '完成',
        },
      });
      expect(projected['verification']['actor'], 'PC 值守');
      expect(projected['verification']['createdAt'], '2026-10-07T10:00:00Z');
      expect(projected['verification']['photoIds'], ['upload-one']);
    },
  );
  test('per-event server permission overrides broad UI role permissions', () {
    final event = WearEvent.fromJson({
      'id': 'E1',
      'status': 'open',
      'permissions': {
        'events:claim': false,
        'events:verify': false,
        'events:observe': true,
      },
    });
    const actor = EventActor(
      userId: 'operator',
      roles: {'admin'},
      permissions: {'*:*:*'},
    );
    expect(EventPolicy.can(EventCommand.claim, event, actor), false);
    expect(EventPolicy.can(EventCommand.verify, event, actor), false);
    expect(EventPolicy.can(EventCommand.handle, event, actor), true);
  });
  test(
    'real login uses native protocol and permissions, never wildcard or fake admin',
    () async {
      final seen = <RequestOptions>[];
      final session = WearSession(
        mock: false,
        credentials: MemoryCredentials(),
        dio: transport((r) {
          seen.add(r);
          if (r.path == '$root/mobile/login') {
            expect(r.data, {'account': 'worker', 'password': 'password'});
            return reply({
              'token': 'native-token',
              'identity': nativeIdentity(),
            }, raw: true);
          }
          expect(r.path, '$root/mobile/identity');
          expect(r.headers['X-Wearable-Token'], 'native-token');
          expect(r.headers.containsKey('Authorization'), false);
          return reply(nativeIdentity(), raw: true);
        }),
      );
      addTearDown(session.dispose);
      await session.login('worker', 'password');
      expect(session.isAdmin, false);
      expect(session.personId, 'P1');
      expect(session.siteId, 'site-1');
      expect(session.can('wear:event:report'), true);
      expect(session.can('wear:event:review'), false);
      expect(session.canRequestSos, true);
      expect(session.permissions.contains('*:*:*'), false);
      expect(seen.length, 2);
    },
  );
  test(
    'failed native query never becomes a mock success and expiry revokes session',
    () async {
      var expired = false;
      final client = api(
        (r) => reply({'message': '会话已失效'}, code: 401, raw: true),
        expired: () => expired = true,
      );
      await expectLater(
        client.get('/api/v1/me/equipment'),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 401)),
      );
      expect(client.isMock, false);
      expect(expired, true);
    },
  );
  test(
    'context retains PC identifiers, versions and unknown sample telemetry',
    () async {
      final client = api((r) {
        expect(r.path, '$root/mobile/context');
        expect(r.queryParameters['siteId'], 'site-1');
        return reply(contextData(), raw: true);
      });
      final devices = await client.page('/api/v1/devices');
      final device = devices.records.single;
      expect(device['id'], 'RL-H001');
      expect(device['version'], 9);
      expect(device['online'], null);
      expect(device['battery'], null);
      expect(device['capabilities']['actions'], isEmpty);
      final equipment = jsonList(await client.get('/api/v1/me/equipment'));
      expect(equipment.single['deviceId'], 'RL-H001');
      expect(equipment.single['personId'], 'P1');
      expect(equipment.single['deviceVersion'], 9);
      expect(equipment.single['version'], 4);
      final event = jsonMap(await client.get('/api/v1/events/SOS-1'));
      expect(event['source'], 'manual_sos');
      expect(event['permissions']['claim'], false);
      expect(event['deviceId'], isNull);
    },
  );
  test(
    'events retry same operation and base version after ambiguous response',
    () async {
      final commands = <JsonMap>[];
      var fail = true;
      final client = api((r) {
        commands.add(Map<String, dynamic>.from(r.data));
        if (fail) {
          fail = false;
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.receiveTimeout,
          );
        }
        return reply({
          'id': 'SOS-1',
          'type': '人员求助',
          'status': '处理中',
          'version': 5,
        }, raw: true);
      });
      final gateway = ApiEventGateway(client),
          event = WearEvent.fromJson({'id': 'SOS-1', 'version': 9});
      const draft = EventDraft(
        baseVersion: 4,
        situation: '现场已确认',
        conclusion: '需现场处理',
        measures: '隔离现场',
      );
      await expectLater(
        gateway.execute(EventCommand.saveVerification, event, draft),
        throwsA(isA<WearApiException>()),
      );
      await gateway.execute(EventCommand.saveVerification, event, draft);
      expect(commands[0], commands[1]);
      expect(commands[1]['expectedVersion'], 4);
      expect(commands[1]['requestId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    },
  );
  test(
    'photos upload as native binary and bind only to their observation',
    () async {
      final sent = <String>[];
      JsonMap? command;
      final backend = SharedBackend(
        (method, path, {data, query, contentType}) async {
          sent.add(path);
          if (method == 'PUT') {
            expect(path, matches(RegExp(r'/files/upload-[0-9a-f-]{36}$')));
            expect(contentType, 'image/png');
            final bytes = await (data as Stream<List<int>>)
                .expand((b) => b)
                .toList();
            expect(bytes, [137, 80, 78, 71]);
            return {};
          }
          command = data as JsonMap;
          return {'id': 'SOS-1', 'status': '处理中', 'version': 3};
        },
        () => 'site-1',
        () => 1,
      );
      await backend.route(
        'POST',
        '/api/v1/events/SOS-1/report',
        data: FormData.fromMap({
          'version': 2,
          'comment': '现场补充',
          'files': [
            MultipartFile.fromBytes([137, 80, 78, 71], filename: 'scene.png'),
          ],
        }),
      );
      expect(sent.length, 2);
      expect(sent.last, '$root/events/SOS-1/observations');
      expect(command!['situation'], '现场补充');
      expect(command!['photoIds'], [sent.first.split('/').last]);
    },
  );
  test('concurrent click submits once and conflict stays an error', () async {
    final held = Completer<ResponseBody>();
    var writes = 0;
    final client = api((r) {
      writes++;
      return held.future;
    });
    final one = client.post('/api/v1/events/SOS-1/claim', data: {'version': 2});
    final two = client.post('/api/v1/events/SOS-1/claim', data: {'version': 2});
    final checks = [
      expectLater(
        one,
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 409)),
      ),
      expectLater(
        two,
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 409)),
      ),
    ];
    held.complete(reply({'message': '记录已更新'}, code: 409, raw: true));
    await Future.wait(checks);
    expect(writes, 1);
  });
  test(
    'assignment uses displayed versions and preserves ambiguous command on retry',
    () async {
      final writes = <JsonMap>[];
      var fail = true;
      final client = api((r) {
        if (r.method == 'GET') return reply(contextData(), raw: true);
        expect(r.path, '$root/mobile/assignments/return');
        writes.add(Map<String, dynamic>.from(r.data));
        if (fail) {
          fail = false;
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          );
        }
        return reply({'ok': true}, raw: true);
      });
      final body = {
        'idempotencyKey': 'stable-operation',
        'personVersion': 6,
        'deviceVersion': 8,
        'assignmentVersion': 3,
      };
      await expectLater(
        client.post('/api/v1/assignments/assignment-1/return', data: body),
        throwsA(isA<WearApiException>()),
      );
      await client.post('/api/v1/assignments/assignment-1/return', data: body);
      expect(writes.first, writes.last);
      expect(writes.last['personId'], 'person-1');
      expect(writes.last['personVersion'], 6);
      expect(writes.last['items'][0], {
        'deviceId': 'device-1',
        'deviceVersion': 8,
        'assignmentId': 'assignment-1',
        'assignmentVersion': 3,
        'condition': 'GOOD',
      });
    },
  );
  test(
    'broadcast retry retains ID even when UI makes another click key',
    () async {
      final writes = <JsonMap>[];
      final client = api((r) {
        writes.add(Map<String, dynamic>.from(r.data));
        return reply({'message': '平台结果未知'}, code: 502, raw: true);
      });
      for (final key in ['click-1', 'click-2']) {
        await expectLater(
          client.post(
            '/api/v1/commands/tts',
            data: {
              'deviceIds': ['RL-H001'],
              'text': '现场确认',
              'idempotencyKey': key,
            },
          ),
          throwsA(isA<WearApiException>()),
        );
      }
      expect(writes.first['idempotencyKey'], writes.last['idempotencyKey']);
    },
  );
  test('persisted old draft is stale until explicitly reloaded', () {
    expect(EventDraft.fromJson({'situation': '旧草稿'}).baseVersion, -1);
    expect(
      EventDraft.fromJson(
        const EventDraft(baseVersion: 4).toJson(),
      ).baseVersion,
      4,
    );
  });
  test('site identity maps only its granted operations', () {
    final native = nativeIdentity();
    native['sites'] = [
      {'id': 'site-1'},
      {'id': 'site-2'},
    ];
    native['permissionsBySite']['site-2'] = ['events:read', 'events:verify'];
    final first = SharedModels.identity(native, 'site-1'),
        second = SharedModels.identity(native, 'site-2');
    expect(first['admin'], false);
    expect(second['admin'], true);
    expect(second['permissions'], contains('wear:event:review'));
    expect(second['permissions'], isNot(contains('wear:assignment:issue')));
  });
}
