import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/notifications.dart';

class MemoryCredentials implements CredentialStore {
  String? value;
  MemoryCredentials([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? token) async {
    value = token;
  }
}

class ContractAdapter implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  ContractAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody reply(
  Object? data, {
  int code = 200,
  String msg = '成功',
  bool raw = false,
}) => ResponseBody.fromString(
  jsonEncode(raw ? data : {'code': code, 'msg': msg, 'data': data}),
  code,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);
JsonMap identity({
  String user = '12',
  String? site = '1',
  List<String> roles = const ['wear_duty'],
}) => {
  'userId': user,
  'status': '0',
  'roles': roles,
  'permissions': ['wear:event:list'],
  'authorizedSites': [
    {'id': '1', 'status': '0', 'name': '厂站一'},
    {'id': '2', 'status': '0', 'name': '厂站二'},
  ],
  'currentSiteId': site,
};
Dio transport(FutureOr<ResponseBody> Function(RequestOptions) handler) =>
    Dio(BaseOptions(baseUrl: 'https://test.invalid'))
      ..httpClientAdapter = ContractAdapter(handler);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'login uses raw token then verified identity, domain requests carry site',
    () async {
      final requests = <RequestOptions>[];
      final credentials = MemoryCredentials();
      final session = WearSession(
        credentials: credentials,
        dio: transport((request) {
          requests.add(request);
          if (request.path == '/login') {
            return reply({'code': 200, 'token': 'test-token'}, raw: true);
          }
          if (request.path == '/api/v1/me') return reply(identity());
          return reply({'records': [], 'total': 0, 'current': 1, 'size': 20});
        }),
      );
      addTearDown(session.dispose);
      await session.login(' operator ', 'example-password');
      expect(session.userId, '12');
      expect(session.siteId, '1');
      expect(credentials.value, 'test-token');
      await session.api.page('/api/v1/events');
      expect(requests.first.headers.containsKey('Authorization'), false);
      expect(requests[1].headers['Authorization'], 'Bearer test-token');
      expect(requests.last.headers['X-Site-Id'], '1');
      expect(requests[1].headers.containsKey('X-Site-Id'), false);
    },
  );
  test('late old-site response is rejected after changing site', () async {
    final pending = Completer<ResponseBody>();
    final session = WearSession(
      credentials: MemoryCredentials('token'),
      dio: transport((request) {
        if (request.path == '/api/v1/me') return reply(identity());
        if (request.path == '/api/v1/me/current-site') {
          return reply({'currentSiteId': '2'});
        }
        return pending.future;
      }),
    );
    addTearDown(session.dispose);
    await session.initialize();
    final oldRequest = session.api.get('/api/v1/events');
    final rejected = expectLater(
      oldRequest,
      throwsA(isA<StaleSessionException>()),
    );
    await Future<void>.delayed(Duration.zero);
    await session.selectSite('2');
    pending.complete(
      reply({
        'records': [
          {'id': 'old-site-event'},
        ],
      }),
    );
    await rejected;
    expect(session.siteId, '2');
  });
  test(
    '401 expires identity, but 409 preserves identity and status for controller',
    () async {
      var errorCode = 409;
      final session = WearSession(
        credentials: MemoryCredentials('token'),
        dio: transport(
          (request) => request.path == '/api/v1/me'
              ? reply(identity())
              : reply(null, code: errorCode, msg: '当前状态已变化'),
        ),
      );
      addTearDown(session.dispose);
      await session.initialize();
      await expectLater(
        session.api.post('/api/v1/events/1/claim'),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 409)),
      );
      expect(session.userId, '12');
      errorCode = 401;
      await expectLater(
        session.api.get('/api/v1/events'),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 401)),
      );
      expect(session.me, null);
      expect(session.token, null);
      expect(session.siteId, null);
    },
  );
  test(
    'platform admin is reviewer, never automatically a duty claimant',
    () async {
      final session = WearSession(
        credentials: MemoryCredentials('token'),
        dio: transport((_) => reply(identity(roles: ['wear_platform_admin']))),
      );
      addTearDown(session.dispose);
      await session.initialize();
      expect(session.isReviewer, true);
      expect(session.isDuty, false);
    },
  );
  test('active call blocks site changes and logout', () async {
    final session = WearSession(
      credentials: MemoryCredentials('token'),
      dio: transport((_) => reply(identity())),
    );
    addTearDown(session.dispose);
    await session.initialize();
    session.callActive.value = true;
    await expectLater(
      session.selectSite('2'),
      throwsA(isA<WearApiException>().having((e) => e.code, 'code', 409)),
    );
    await expectLater(session.logout(), throwsA(isA<WearApiException>()));
    expect(session.siteId, '1');
    expect(session.token, 'token');
  });
  test(
    'logout clears only this account drafts even if server logout fails',
    () async {
      SharedPreferences.setMockInitialValues({
        'wear.12.1.drafts': 'private',
        'wear.20.1.drafts': 'other',
        'user_token': 'old-token',
      });
      final credentials = MemoryCredentials('token');
      final session = WearSession(
        credentials: credentials,
        dio: transport(
          (request) => request.path == '/api/v1/me'
              ? reply(identity())
              : reply(null, code: 503),
        ),
      );
      addTearDown(session.dispose);
      await session.initialize();
      await session.logout();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('wear.12.1.drafts'), null);
      expect(prefs.getString('wear.20.1.drafts'), 'other');
      expect(prefs.getString('user_token'), null);
      expect(credentials.value, null);
      expect(session.error, contains('未确认'));
    },
  );
  test(
    'notice parser accepts native extras and rejects arbitrary routes or invalid IDs',
    () {
      final notice = WearNotice.parse({
        'extras': jsonEncode({
          'type': 'wear.event',
          'eventId': 'e-1',
          'siteId': '2',
          'eventVersion': 5,
        }),
      });
      expect(notice?.eventId, 'e-1');
      expect(notice?.version, 5);
      expect(WearNotice.parse({'eventId': '../admin', 'siteId': '1'}), null);
      expect(
        WearNotice.parse({'url': 'https://other.invalid', 'eventId': '1'}),
        null,
      );
      expect(
        WearNotice.parse({'type': 'open.url', 'eventId': '1', 'siteId': '2'}),
        null,
      );
    },
  );
  test(
    'notification click is authorized and deduplicated separately from delivery',
    () async {
      final session = WearSession(
        credentials: MemoryCredentials('token'),
        dio: transport((_) => reply(identity())),
      );
      addTearDown(session.dispose);
      await session.initialize();
      final opened = <WearNotice>[];
      final notifications = WearNotifications(
        session: session,
        openEvent: (notice) async => opened.add(notice),
      );
      addTearDown(notifications.dispose);
      final payload = {
        'type': 'wear.event',
        'eventId': '1',
        'siteId': '2',
        'notificationId': 'n-1',
      };
      notifications.receive(payload);
      notifications.receive(payload, opened: true);
      await Future<void>.delayed(Duration.zero);
      notifications.receive(payload, opened: true);
      await Future<void>.delayed(Duration.zero);
      expect(opened.length, 1);
      notifications.receive({
        ...payload,
        'siteId': 'unauthorized',
        'notificationId': 'n-2',
      }, opened: true);
      await Future<void>.delayed(Duration.zero);
      expect(opened.length, 1);
      expect(notifications.error, contains('无权'));
    },
  );
  test(
    'unversioned websocket reminders still reconcile on every delivery',
    () async {
      final session = WearSession(
        credentials: MemoryCredentials('token'),
        dio: transport((_) => reply(identity())),
      );
      addTearDown(session.dispose);
      await session.initialize();
      final notifications = WearNotifications(
        session: session,
        openEvent: (_) async {},
      );
      addTearDown(notifications.dispose);
      final payload = {'type': 'wear.event', 'eventId': '1', 'siteId': '1'};
      expect(WearNotice.parse(payload)!.hasUniqueDelivery, false);
      final before = session.refreshTick.value;
      notifications.receive(payload);
      notifications.receive(payload);
      expect(session.refreshTick.value, before + 2);
      notifications.receive({...payload, 'notificationId': 'n-unique'});
      notifications.receive({...payload, 'notificationId': 'n-unique'});
      expect(session.refreshTick.value, before + 3);
    },
  );
}
