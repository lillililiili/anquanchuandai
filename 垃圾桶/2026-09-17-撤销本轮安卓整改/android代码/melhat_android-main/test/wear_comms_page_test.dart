import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/communications_page.dart';

void main() {
  testWidgets(
    'device search resolves current holder from detail before counting people',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.session.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('按设备查找'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MH-001'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 人 · 1 台终端'), findsOneWidget);
      expect(fixture.callRequests, 0);
    },
  );
  testWidgets('station change clears the previous station selection', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.session.dispose);
    await tester.pumpWidget(fixture.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('张三'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 人 · 1 台终端'), findsOneWidget);
    final switching = fixture.session.selectSite('site2');
    await tester.pumpAndSettle();
    await switching;
    await tester.pumpAndSettle();
    expect(find.text('已选 0 人 · 0 台终端'), findsOneWidget);
    expect(fixture.callRequests, 0);
  });

  testWidgets('preparation remains usable at phone width with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final fixture = _Fixture();
    addTearDown(fixture.session.dispose);
    await tester.pumpWidget(
      fixture.app(intent: 'voice', personId: 'p1', dark: true),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('发起通话'), 300);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '发起通话'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'contacts start with people instead of counting their equipment again',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.session.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('李四'), findsOneWidget);
      expect(find.textContaining('MH-001'), findsNothing);
    },
  );

  testWidgets(
    'multiple people remain a group preparation and never become a first-target call',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.session.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('多选'));
      await tester.tap(find.text('张三'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('李四'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('呼叫准备'));
      await tester.tap(find.text('呼叫准备'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('发起通话'), 300);
      expect(find.textContaining('多人组呼暂未开通'), findsOneWidget);
      expect(fixture.callRequests, 0);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '发起通话'),
      );
      expect(button.onPressed, isNull);
    },
  );

  testWidgets(
    'a persons equipment selection keeps one person and never starts on entry',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.session.dispose);
      await tester.pumpWidget(fixture.app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('多选'));
      await tester.tap(find.text('张三'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('按设备查找'));
      await tester.pumpAndSettle();
      // Selecting a different terminal for an already selected person replaces
      // that person's terminal; it must not add a second contact.
      await tester.tap(find.text('MH-001'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MH-001'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 人 · 1 台终端'), findsOneWidget);
      expect(fixture.callRequests, 0);
    },
  );

  testWidgets('helmet origin stays unavailable even with a bound helmet', (
    tester,
  ) async {
    final fixture = _Fixture();
    addTearDown(fixture.session.dispose);
    await tester.pumpWidget(fixture.app(intent: 'voice', personId: 'p1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('本人安全帽'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('发起通话'), 300);
    expect(find.textContaining('帽端发起暂未开通，可切换'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '发起通话'))
          .onPressed,
      isNull,
    );
    expect(fixture.callRequests, 0);
  });

  testWidgets(
    'tts draft and explicit target survive theme changes and child navigation',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.session.dispose);
      await tester.pumpWidget(fixture.app(intent: 'tts', personId: 'p1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '请撤离当前作业区域');
      await tester.pumpWidget(
        fixture.app(intent: 'tts', personId: 'p1', dark: true),
      );
      await tester.pumpAndSettle();
      expect(find.text('请撤离当前作业区域'), findsOneWidget);
      expect(find.text('已选 1 人 · 1 台终端'), findsOneWidget);
      await tester.tap(find.byTooltip('返回通讯'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文字播报'));
      await tester.pumpAndSettle();
      expect(find.text('请撤离当前作业区域'), findsOneWidget);
      expect(fixture.ttsPayloads, isEmpty);
      expect(fixture.callRequests, 0);
    },
  );

  testWidgets(
    'tts submits selected terminal IDs and shows actual per-device status',
    (tester) async {
      final fixture = _Fixture();
      addTearDown(fixture.session.dispose);
      await tester.pumpWidget(fixture.app(intent: 'tts', personId: 'p1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '请注意安全');
      await tester.scrollUntilVisible(
        find.text('确认目标并提交播报'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('确认目标并提交播报'));
      await tester.pumpAndSettle();
      expect(fixture.ttsPayloads.single['deviceIds'], ['d1']);
      expect(fixture.ttsPayloads.single['text'], '请注意安全');
      await tester.scrollUntilVisible(
        find.text('服务端已受理（未确认现场播放）'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('服务端已受理（未确认现场播放）'), findsOneWidget);
      expect(fixture.callRequests, 0);
    },
  );

  testWidgets(
    'multiple valid terminals require an explicit choice before a single call',
    (tester) async {
      final fixture = _Fixture(multipleTerminals: true);
      addTearDown(fixture.session.dispose);
      await tester.pumpWidget(fixture.app(intent: 'voice', personId: 'p1'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('发起通话'), 300);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '发起通话'))
            .onPressed,
        isNull,
      );
      expect(fixture.callRequests, 0);
      await tester.scrollUntilVisible(find.text('MH-003'), -300);
      await tester.tap(find.text('MH-003'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('发起通话'), 300);
      await tester.tap(find.text('发起通话'));
      await tester.pumpAndSettle();
      expect(fixture.callPayloads.single['deviceId'], 'd3');
      expect(fixture.callPayloads.single['video'], false);
      expect(find.text('当前通话'), findsOneWidget);
      expect(find.text('已接通'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

class _Fixture {
  _Fixture({bool multipleTerminals = false}) {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          Object? data;
          switch (options.path) {
            case '/api/v1/me/current-site':
              data = {'currentSiteId': 'site2'};
            case '/api/v1/people/options':
              data = [
                {'id': 'p1', 'name': '张三', 'personCode': 'P001'},
                {'id': 'p2', 'name': '李四', 'personCode': 'P002'},
              ];
            case '/api/v1/devices':
              data = {
                'records': [
                  _device('d1')..remove('currentAssignment'),
                  _device('d2')..remove('currentAssignment'),
                ],
                'total': 2,
                'current': 1,
                'size': 50,
              };
            case '/api/v1/me/equipment':
              data = [
                {'deviceId': 'own', 'typeCode': 'helmet', 'sn': 'OWN-1'},
              ];
            case '/api/v1/people/p1/equipment':
              data = [
                {'deviceId': 'd1', 'personId': 'p1', 'personName': '张三'},
                if (multipleTerminals)
                  {'deviceId': 'd3', 'personId': 'p1', 'personName': '张三'},
              ];
            case '/api/v1/people/p2/equipment':
              data = [
                {'deviceId': 'd2', 'personId': 'p2', 'personName': '李四'},
              ];
            case '/api/v1/devices/d1':
              data = _device('d1');
            case '/api/v1/devices/d2':
              data = _device('d2');
            case '/api/v1/devices/d3':
              data = _device('d3');
            case '/api/v1/calls':
              callRequests++;
              callPayloads.add(Map<String, dynamic>.from(options.data as Map));
              data = {
                'id': 'call',
                'deviceId': 'd1',
                'requesterUserId': 'u1',
                'status': 'failed',
              };
            case '/api/v1/commands/tts':
              ttsPayloads.add(Map<String, dynamic>.from(options.data as Map));
              data = [
                {'id': 'cmd', 'deviceId': 'd1', 'status': 'accepted'},
              ];
            default:
              data = [];
          }
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'code': 200, 'msg': 'ok', 'data': data},
            ),
          );
        },
      ),
    );
    session = WearSession(dio: dio, credentials: _Credentials())
      ..token = 'token'
      ..siteId = 'site'
      ..me = {
        'userId': 'u1',
        'authorizedSites': [
          {'id': 'site'},
          {'id': 'site2'},
        ],
        'permissions': ['wear:call:start', 'wear:command:tts'],
      };
  }

  late final WearSession session;
  int callRequests = 0;
  final ttsPayloads = <Map<String, dynamic>>[];
  final callPayloads = <Map<String, dynamic>>[];
  Map<String, dynamic> _device(String id) => {
    'id': id,
    'sn': id == 'd1'
        ? 'MH-001'
        : id == 'd2'
        ? 'MH-002'
        : 'MH-003',
    'typeCode': 'helmet',
    'capabilities': {
      'actions': ['intercom', 'video', 'tts'],
    },
    'currentAssignment': {
      'personId': id == 'd1' ? 'p1' : 'p2',
      'personName': id == 'd1' ? '张三' : '李四',
    },
  };

  Widget app({String? intent, String? personId, bool dark = false}) =>
      MaterialApp(
        theme: ThemeData.light(),
        darkTheme: ThemeData.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: WearScope(
          session: session,
          child: Scaffold(
            body: CommunicationsPage(actionIntent: intent, personId: personId),
          ),
        ),
      );
}

class _Credentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String? token) async {}
}
