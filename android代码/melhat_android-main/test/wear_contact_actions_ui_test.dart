import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_action_bar.dart';
import 'wear_comms_entry_test.dart' show openDevice;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'favorite star pins without selecting or calling and survives reentry',
    (tester) async {
      final requests = <RequestOptions>[];
      final router = await openDevice(tester, requests);
      router.go('/communications');
      await tester.pumpAndSettle();
      final star = find.byKey(const ValueKey('favorite-p:2'));
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(star).isSelected, isTrue);
      expect(
        tester.getTopLeft(find.text('联系人02')).dy,
        lessThan(tester.getTopLeft(find.text('联系人00')).dy),
      );
      expect(find.text('0 项'), findsOneWidget);
      router.go('/devices/42');
      await tester.pumpAndSettle();
      router.go('/communications');
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(star).isSelected, isTrue);
      // The shell restores the previous scroll offset on reentry.
      tester
          .widget<ListView>(
            find.byKey(const ValueKey('wear-communications-list')),
          )
          .controller!
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('联系人02').hitTestable(), findsOneWidget);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('联系人00')).dy,
        lessThan(tester.getTopLeft(find.text('联系人02')).dy),
      );
      expect(requests.where((r) => r.method != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'video button keeps explicit device and uses existing video contract',
    (tester) async {
      final requests = <RequestOptions>[];
      final router = await openDevice(tester, requests);
      router.go('/communications?deviceId=42&personId=7');
      await tester.pumpAndSettle();
      await tester.tap(find.text('视频群聊'));
      await tester.pumpAndSettle();
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
    },
  );

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
        (w) => w is TextField && w.maxLength == 300,
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
    },
  );

  testWidgets('three actions fit small screens and large text', (tester) async {
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
                onVoice: () {},
                onVideo: () {},
                onBroadcast: () {},
              ),
            ),
          ),
        ),
      ),
    );
    for (final label in ['语音群聊', '视频群聊', '文字播报']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    expect(find.text('清空'), findsNothing);
    final buttons = tester.widgetList<TextButton>(find.byType(TextButton));
    expect(buttons, hasLength(3));
    final widths = find
        .byType(TextButton)
        .evaluate()
        .map((e) => tester.getSize(find.byWidget(e.widget)).width)
        .toList();
    expect(widths[0], closeTo(widths[1], .01));
    expect(widths[1], closeTo(widths[2], .01));
    expect(tester.takeException(), isNull);
  });
}
