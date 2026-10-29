import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/shared_backend.dart';

JsonMap identity({bool authorized = true, bool enabled = true}) => {
  'accountId': 'operator',
  'name': '值班员',
  'roleIds': ['worker', 'reviewer'],
  'sites': [
    if (authorized) {'id': 'site-1', 'name': '旧厂站名', 'enabled': enabled},
    {'id': 'site-2', 'name': '另一个厂站', 'enabled': true},
  ],
  'permissionsBySite': {
    'site-1': ['self:read'],
    'site-2': ['events:read', 'events:verify'],
  },
};

SharedBackend backend(
  JsonMap native, {
  String? selected = 'site-2',
  bool testMode = true,
}) => SharedBackend(
  (method, path, {data, query, contentType}) async {
    expect(path, '/api/guardian/v1/mobile/identity');
    return native;
  },
  () => selected,
  () => 1,
  testSiteMode: testMode,
);

void main() {
  test(
    'test site view narrows existing authorization without modifying grants',
    () async {
      final native = identity();
      final client = backend(native);
      final result = jsonMap(await client.route('GET', '/api/v1/me'));
      expect(result['currentSiteId'], 'site-1');
      expect(result['authorizedSites'], [
        {'id': 'site-1', 'name': '测试厂区', 'enabled': true, 'status': '0'},
      ]);
      expect(result['siteSelectionLocked'], true);
      expect(result['sharedOperations'], ['self:read']);
      expect(result['permissions'], isNot(contains('wear:event:review')));
      expect(result['admin'], false);
      expect(result['permissionsBySite'], native['permissionsBySite']);
      expect(result['roleIds'], native['roleIds']);
      expect(native['sites'][0]['name'], '旧厂站名');
      expect(native['sites'], hasLength(2));
      final sites = jsonList(await client.route('GET', '/api/v1/sites'));
      expect(sites.map((site) => site['id']), ['site-1']);
      await expectLater(
        client.route(
          'PUT',
          '/api/v1/me/current-site',
          data: {'siteId': 'site-2'},
        ),
        throwsA(isA<WearApiException>().having((e) => e.code, 'code', 403)),
      );
      await expectLater(client.context(), throwsA(isA<WearApiException>()));
    },
  );

  test(
    'missing or disabled site-1 never grants access through a display alias',
    () async {
      for (final native in [
        identity(authorized: false),
        identity(enabled: false),
      ]) {
        final client = backend(native);
        final result = jsonMap(await client.route('GET', '/api/v1/me'));
        expect(result['authorizedSites'], isEmpty);
        expect(result['currentSiteId'], '');
        expect(result['sharedOperations'], isEmpty);
        expect(result['admin'], false);
        expect(result['permissions'], everyElement(startsWith('wear:site:')));
        await expectLater(
          client.route(
            'PUT',
            '/api/v1/me/current-site',
            data: {'siteId': 'site-1'},
          ),
          throwsA(isA<WearApiException>().having((e) => e.code, 'code', 403)),
        );
      }
    },
  );

  test(
    'disabled test-site mode retains multi-site business behavior',
    () async {
      final result = jsonMap(
        await backend(identity(), testMode: false).route('GET', '/api/v1/me'),
      );
      expect(result['authorizedSites'], hasLength(2));
      expect(result['currentSiteId'], 'site-2');
      expect(result['permissions'], contains('wear:event:review'));
      expect(result['siteSelectionLocked'], isNull);
    },
  );

  test(
    'explicit offline mock still exposes its original multi-site fixtures',
    () async {
      final api = WearApi(
        mock: true,
        token: () => 'local-mock-only',
        siteId: () => '1',
        epoch: () => 1,
      );
      final result = jsonMap(await api.get('/api/v1/me'));
      expect(result['authorizedSites'], hasLength(2));
      expect(result['authorizedSites'][0]['name'], '演示厂站A');
      expect(result['siteSelectionLocked'], isNull);
    },
  );

  testWidgets('locked test site is displayed without a site-switch arrow', (
    tester,
  ) async {
    final session = WearSession(mock: true)
      ..me = jsonMap(await backend(identity()).route('GET', '/api/v1/me'))
      ..siteId = 'site-1';
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearScope(
        session: session,
        child: const MaterialApp(home: Scaffold(body: WearSiteSwitcher())),
      ),
    );
    expect(find.text('测试厂区'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsNothing);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    await expectLater(
      session.selectSite('site-2'),
      throwsA(isA<WearApiException>()),
    );
  });
}
