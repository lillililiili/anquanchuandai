import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/mock_backend.dart';
import 'package:rolling_intelligence_headband/wear/notifications.dart';
import 'package:rolling_intelligence_headband/wear/events/event_repository.dart';
import 'package:rolling_intelligence_headband/wear/events/event_models.dart';
import 'package:rolling_intelligence_headband/wear/communications/api_gateway.dart';

class NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Mock mode must never open an HTTP client');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WearSession session;
  late NoNetwork network;
  HttpOverrides? previous;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    previous = HttpOverrides.current;
    network = NoNetwork();
    HttpOverrides.global = network;
    session = WearSession(
      dio: Dio(BaseOptions(baseUrl: 'https://mock.invalid'))
        ..httpClientAdapter = MockBackend(),
    );
    await session.login('demo', '123456');
    await session.selectSite('1');
  });
  tearDown(() {
    session.dispose();
    HttpOverrides.global = previous;
    expect(network.attempts, 0);
  });
  Matcher status(int code) =>
      throwsA(isA<WearApiException>().having((e) => e.code, 'code', code));
  Future<JsonMap> event(String id) async =>
      jsonMap(await session.api.get('/api/v1/events/$id'));
  Future<JsonMap> write(String id, String action, JsonMap body) async =>
      jsonMap(await session.api.post('/api/v1/events/$id/$action', data: body));

  test(
    'default clients, notifications and unknown URLs stay offline',
    () async {
      final local = WearSession();
      addTearDown(local.dispose);
      await local.login('demo', '123456');
      await local.selectSite('1');
      expect(local.api.isMock, isTrue);
      final notifications = WearNotifications(
        session: local,
        openEvent: (_) async {},
      );
      addTearDown(notifications.dispose);
      await notifications.start();
      expect(notifications.socketConnected, isFalse);
      expect(notifications.status, contains('本地模拟'));
      await expectLater(
        local.api.get('http://127.0.0.1:18084/unknown'),
        status(404),
      );
    },
  );

  test(
    'unknown accounts and wrong passwords cannot enter as administrator',
    () async {
      await session.logout();
      await expectLater(session.login('anyone', '123456'), throwsA(anything));
      expect(session.me, isNull);
      await expectLater(session.login('demo', 'wrong'), throwsA(anything));
      expect(session.me, isNull);
      await session.login('member', '123456');
      expect(session.isAdmin, isFalse);
      expect(session.sites.map((s) => s['id']), ['1']);
      expect(session.can('wear:event:report'), isTrue);
      expect(session.can('wear:task:edit'), isFalse);
      expect(session.can('wear:inspection:report'), isFalse);
      expect(session.canHandover, isFalse);
    },
  );

  test(
    'work membership is read only and retired APIs are unavailable',
    () async {
      await expectLater(
        session.api.post(
          '/api/v1/work-tasks/301/members',
          data: {
            'personIds': ['103'],
          },
        ),
        status(403),
      );
      expect(
        jsonList(
          jsonMap(await session.api.get('/api/v1/work-tasks/301'))['members'],
        ).length,
        2,
      );
      for (final path in [
        '/api/v1/work-tasks/301/inspection',
        '/api/v1/duty/handovers',
        '/api/v1/account-recovery/requests',
        '/api/v1/lab/state',
      ]) {
        await expectLater(session.api.get(path), status(404));
      }
      await expectLater(write('402', 'review', {'version': 1}), status(404));
      await expectLater(write('402', 'reopen', {'version': 1}), status(404));
    },
  );

  test(
    'observation, draft and final verification have separate effects and photos',
    () async {
      final report = jsonMap(
        await session.api.post(
          '/api/v1/events/402/report',
          data: FormData.fromMap({
            'version': 1,
            'comment': '已到现场',
            'files': [
              MultipartFile.fromBytes([1, 2, 3], filename: 'scene.jpg'),
            ],
          }),
        ),
      );
      expect(report['status'], 'open');
      expect(jsonList(report['observations']).single['actor'], '陈建国');
      expect(
        base64Decode(
          jsonList(
            jsonList(report['observations']).single['photos'],
          ).single['localData'],
        ),
        [1, 2, 3],
      );
      final draft = await write('402', 'verification-draft', {
        'version': 2,
        'situation': '现场已确认',
        'conclusion': '需现场处理',
      });
      expect(draft['status'], 'open');
      expect(jsonMap(draft['verificationDraft'])['situation'], '现场已确认');
      await expectLater(
        write('402', 'verify', {'version': 3, 'situation': ''}),
        status(400),
      );
      final verified = await write('402', 'verify', {
        'version': 3,
        'situation': '已到场协助',
        'conclusion': '需现场处理',
        'measures': '安排陪同',
      });
      expect(verified['status'], 'verified');
      expect(jsonMap(verified['verification'])['actor'], '陈建国');
      expect(verified['externalClosureStatus'], 'unknown');
      expect(jsonMap(verified['verification'])['photos'], isEmpty);
      await expectLater(
        write('402', 'report', {'version': 4, 'comment': '再修改'}),
        status(409),
      );
      expect(
        (await ApiEventGateway(session.api).fetchActions('402')).length,
        3,
      );
      final filtered = await ApiEventGateway(
        session.api,
      ).fetchPage(const EventFilters(statuses: ['verified']), 1, 20);
      expect(filtered.records.single.id, '402');
    },
  );

  test('parallel writes and stale versions cannot overwrite records', () async {
    final results = await Future.wait([
      for (final comment in ['记录一', '记录二'])
        write('401', 'report', {
          'version': 1,
          'comment': comment,
        }).then<Object>((v) => v, onError: (Object e) => e),
    ]);
    expect(results.whereType<WearApiException>().single.code, 409);
    expect(jsonList((await event('401'))['observations']).length, 1);
    expect((await event('401'))['version'], 2);
  });

  test(
    'mobile SOS needs no helmet/location; retries and assistance stay per event',
    () async {
      Future<JsonMap> sos(String key) async => jsonMap(
        await session.api.post(
          '/api/v1/events/manual-sos',
          data: {'requestId': key},
        ),
      );
      final first = await sos('first');
      final second = await sos('second');
      expect((await sos('first'))['id'], first['id']);
      expect(second['id'], isNot(first['id']));
      expect(first['source'], 'manual_sos');
      expect(first['deviceId'], '');
      expect(first['taskId'], '');
      expect(first['status'], 'open');
      final joined = await write(idOf(first['id']), 'assistance/join', {
        'version': 1,
      });
      expect(joined['status'], 'handling');
      expect(jsonMap(joined['assistance'])['members'], ['12']);
      final ended = await write(idOf(first['id']), 'assistance/end', {
        'version': 2,
      });
      expect(ended['status'], 'handling');
      expect(jsonMap(ended['assistance'])['state'], 'ended');
      expect(
        jsonMap((await event(idOf(second['id'])))['assistance'])['state'],
        'waiting',
      );
      expect(
        jsonList(await session.api.get('/api/v1/events/${first['id']}/calls')),
        isEmpty,
      );
      await session.selectSite('2');
      expect((await session.api.page('/api/v1/events')).total, 2);
      await session.selectSite('1');
      expect((await session.api.page('/api/v1/events')).total, 4);
    },
  );

  test(
    'member scope prevents other people, private SOS, admin writes and other sites',
    () async {
      final private = jsonMap(
        await session.api.post(
          '/api/v1/events/manual-sos',
          data: {'requestId': 'private'},
        ),
      );
      await session.logout();
      await session.login('member', '123456');
      await session.selectSite('1');
      await expectLater(session.api.get('/api/v1/people/101'), status(403));
      await expectLater(session.api.get('/api/v1/devices/201'), status(403));
      await expectLater(event(idOf(private['id'])), status(403));
      await expectLater(session.selectSite('2'), throwsA(anything));
      await session.selectSite('1');
      await expectLater(write('402', 'claim', {'version': 1}), status(403));
      await expectLater(write('402', 'verify', {'version': 1}), status(403));
      final observed = await write('402', 'report', {
        'version': 1,
        'comment': '已看到求助',
      });
      expect(observed['status'], 'open');
      expect(jsonList(observed['observations']).single['actor'], '周明');
      expect(
        jsonList(
          await session.api.get('/api/v1/me/equipment'),
        ).single['deviceId'],
        '203',
      );
    },
  );

  test('invalid photos leave event and version unchanged', () async {
    for (final file in [
      MultipartFile.fromBytes([1], filename: 'clip.mp4'),
      MultipartFile.fromBytes(
        List.filled(10 * 1024 * 1024 + 1, 1),
        filename: 'large.png',
      ),
    ]) {
      await expectLater(
        session.api.post(
          '/api/v1/events/401/report',
          data: FormData.fromMap({
            'version': 1,
            'comment': '附件',
            'files': [file],
          }),
        ),
        status(400),
      );
    }
    expect((await event('401'))['version'], 1);
    expect(jsonList((await event('401'))['observations']), isEmpty);
  });

  test('equipment allocation and return preserve ownership', () async {
    final assigned = jsonMap(
      await session.api.post(
        '/api/v1/assignments',
        data: {'deviceId': '204', 'personId': '102'},
      ),
    );
    expect(
      jsonList(
        await session.api.get('/api/v1/people/102/equipment'),
      ).map((d) => d['deviceId']),
      contains('204'),
    );
    await session.api.post(
      '/api/v1/assignments/${assigned['id']}/return',
      data: {},
    );
    expect(
      jsonList(
        await session.api.get('/api/v1/people/102/equipment'),
      ).single['deviceId'],
      '203',
    );
    expect(
      (await session.api.page(
        '/api/v1/devices',
        query: {'assetStatus': 'in_stock'},
      )).total,
      1,
    );
  });

  test('voice and broadcast results explicitly remain simulated', () async {
    final gateway = WearCommunicationsGateway(session.api);
    final started = await gateway.startCall(
      deviceId: '201',
      kind: 'single',
      video: false,
      idempotencyKey: 'call',
    );
    expect(started.session.demo, isTrue);
    expect(started.credentials, isNull);
    expect((await gateway.endCall(started.session.id)).isTerminal, isTrue);
    final commands = await gateway.sendTts(
      deviceIds: ['201'],
      text: '本地播报',
      idempotencyKey: 'tts',
    );
    expect(commands.single.vendorMessage, contains('本地模拟'));
    await expectLater(
      session.api.post(
        '/api/v1/calls',
        data: {'deviceId': '201', 'video': true},
      ),
      status(400),
    );
  });
}
