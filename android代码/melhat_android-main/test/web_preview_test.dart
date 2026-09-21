import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/web_preview/preview_data.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/communications/policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('preview equipment supports the current communication policy', () async {
    final session = createPreviewSession();
    addTearDown(session.dispose);
    await session.login('demo', 'preview', code: 'demo');
    await session.selectSite('1');
    final policy = CommunicationsPolicy(
      userId: session.userId,
      permissions: session.permissions,
    );
    final device = CommunicationDevice.fromJson(
      jsonMap(await session.api.get('/api/v1/devices/201')),
    );
    expect(policy.canStartVoice(device), isTrue);
    expect(policy.canStartVideo(device), isTrue);
    expect(policy.canSendTts(device), isTrue);
    final call = jsonMap(await session.api.post('/api/v1/calls', data: {
      'deviceId': device.id, 'kind': 'single', 'video': true,
    }));
    expect(call['demo'], isTrue);
    expect(call['requesterUserId'], session.userId);
  });
  test('preview login, site selection and actions are local', () async {
    final session = createPreviewSession();
    addTearDown(session.dispose);
    await session.login('any-account', 'any-password', code: 'any-code');
    expect(session.me?['userName'], 'any-account');
    expect(session.siteId, isNull);
    await session.selectSite('1');
    expect(session.siteName, '演示厂站A');
    expect((await session.api.page('/api/v1/events')).records.length, 2);
    await session.api.post(
      '/api/v1/events/401/handle',
      data: {'comment': '演示核验', 'version': 1},
    );
    final event = jsonMap(await session.api.get('/api/v1/events/401'));
    expect(event['status'], 'handled');
    await session.logout();
    expect(session.me, isNull);
  });
  testWidgets('phone preview keeps login, four tabs and event routing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 616);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = createPreviewSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      WearApp(session: session, enableNotifications: false),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'random');
    await tester.enterText(fields.at(1), '1');
    await tester.enterText(fields.at(2), 'arbitrary');
    await tester.ensureVisible(find.text('登录'));
    await tester.tap(find.text('登录'));
    await tester.pumpAndSettle();
    expect(session.me, isNotNull);
    await tester.tap(find.text('演示厂站A'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('sites-enter')));
    await tester.tap(find.byKey(const ValueKey('sites-enter')));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('东区巡检'), findsWidgets);
    await tester.tap(find.text('消息').last);
    await tester.pumpAndSettle();
    // Preview events omit the core alarm name; retain the explicit fallback.
    final eventTitle = find.text('告警名称未提供').first;
    await tester.ensureVisible(eventTitle);
    await tester.tap(eventTitle);
    await tester.pumpAndSettle();
    expect(find.text('事件详情'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
