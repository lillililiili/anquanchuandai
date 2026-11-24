import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_action_bar.dart';
import 'wear_comms_entry_test.dart' show openDevice, confirmHelmetCall;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'each contact has independent phone and helmet selectors and no checkbox',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'wear.contact-favorites.v1.["https://test.invalid","12","1"]': ['p:2'],
      });
      final requests = <RequestOptions>[];
      final router = await openDevice(tester, requests, phoneContacts: ['7']);
      router.go('/communications');
      await tester.pumpAndSettle();
      expect(find.byTooltip('收藏并置顶'), findsNothing);
      expect(find.byTooltip('取消收藏'), findsNothing);
      expect(find.text('星标联系人优先显示'), findsNothing);
      expect(find.text('相关会话'), findsNothing);
      expect(find.text('暂无相关通话记录'), findsNothing);
      expect(find.text('设备语音消息（非实时通话）'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('联系人00')).dy,
        lessThan(tester.getTopLeft(find.text('联系人02')).dy),
      );
      final unassignedHat = find.byKey(const ValueKey('contact-helmet-p:2'));
      await tester.ensureVisible(unassignedHat);
      await tester.tapAt(tester.getCenter(unassignedHat));
      await tester.pumpAndSettle();
      expect(find.text('0 项'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('contact-call-p:2')))
            .onPressed,
        isNull,
      );
      expect(tester.widget<IconButton>(unassignedHat).onPressed, isNull);
      expect(find.byType(Checkbox), findsNothing);

      final hat = find.byKey(const ValueKey('contact-helmet-p:7'));
      final phone = find.byKey(const ValueKey('contact-call-p:7'));
      await tester.ensureVisible(hat);
      expect(
        tester.getRect(phone).right,
        lessThanOrEqualTo(tester.getRect(hat).left),
      );
      expect(tester.widget<IconButton>(phone).onPressed, isNotNull);
      await tester.tap(hat);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(hat).isSelected, true);
      expect(tester.widget<IconButton>(phone).isSelected, false);
      await tester.tap(phone);
      await tester.pumpAndSettle();
      expect(find.text('2 项'), findsOneWidget);
      await tester.tap(hat);
      await tester.pumpAndSettle();
      expect(find.text('1 项'), findsOneWidget);
      expect(tester.widget<IconButton>(phone).isSelected, true);
      expect(
        requests.where(
          (r) => r.method == 'POST' && !r.path.endsWith('/presence'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('helmet video call keeps the explicitly selected device', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final router = await openDevice(tester, requests);
    router.go('/communications?deviceId=42&personId=7');
    await tester.pumpAndSettle();
    expect(find.text('视频群聊'), findsNothing);
    await confirmHelmetCall(tester);
    final call = requests
        .where((r) => r.method == 'POST' && r.path == '/api/v1/calls')
        .single;
    expect(call.data['deviceId'], '42');
    expect(call.data['video'], true);
    expect(find.text('结束通话').hitTestable(), findsOneWidget);
    await tester.tap(find.text('结束通话'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'broadcast opens editor without sending; draft survives closing',
    (tester) async {
      final requests = <RequestOptions>[];
      final router = await openDevice(tester, requests);
      router.go('/communications?deviceId=42');
      await tester.pumpAndSettle();
      await tester.tap(find.text('文字播报'));
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.maxLength == 200,
      );
      await tester.enterText(input, '请到集合点');
      await tester.tap(find.byTooltip('收起文字播报'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文字播报'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, '请到集合点');
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      await tester.ensureVisible(find.text('提交播报指令'));
      await tester.tap(find.text('提交播报指令'));
      await tester.pumpAndSettle();
      final command = requests.where((r) => r.method == 'POST').single;
      expect(command.path, '/api/v1/commands/tts');
      expect(command.data['deviceIds'], ['42']);
      expect(command.data['text'], '请到集合点');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('voice video and broadcast fit small screens and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ContactActionBar(
                onPhone: () {},
                onHelmet: () {},
                onBroadcast: () {},
              ),
            ),
          ),
        ),
      ),
    );
    for (final label in ['手机呼叫', '安全帽呼叫', '文字播报']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    expect(find.text('清空'), findsNothing);
    final buttons = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(buttons, hasLength(3));
    expect(find.text('视频群聊'), findsNothing);
    final widths = find
        .byType(TextButton)
        .evaluate()
        .map((e) => tester.getSize(find.byWidget(e.widget)).width)
        .toList();
    expect(widths[0], closeTo(widths[1], .01));
    expect(tester.takeException(), isNull);
  });
}
