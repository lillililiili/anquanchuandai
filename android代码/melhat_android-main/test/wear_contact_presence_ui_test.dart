import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/communications_page.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_calls.dart'
    show callLabEnabled;
import 'wear_lab_calls_test.dart' show sessionWith;
import 'wear_session_test.dart' show reply;

void main() {
  for (final withBroadcast in [false, true]) {
    testWidgets(
      withBroadcast
          ? 'failed broadcast receipts cannot discard main device refresh'
          : 'returning to foreground refreshes contacts immediately without resetting scroll',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var online = true;
        var reads = 0;
        var broadcasts = 0;
        var receiptReads = 0;
        final session = sessionWith((r) {
          if (r.path == '/api/v1/lab/tts' && r.method == 'POST') {
            broadcasts++;
            return reply({'id': 'broadcast-1', 'receipts': []});
          }
          if (r.path == '/api/v1/lab/state') {
            receiptReads++;
            return reply(null, code: 503);
          }
          if (r.path == '/api/v1/people') {
            return reply({
              'records': [
                for (var i = 1; i <= 20; i++) {'id': 'p$i', 'name': '在线测试$i'},
              ],
              'total': 20,
            });
          }
          if (r.path == '/api/v1/devices') {
            return reply({
              'records': [
                for (var i = 1; i <= 20; i++) {'id': 'd$i'},
              ],
              'total': 20,
            });
          }
          if (r.path.startsWith('/api/v1/devices/')) {
            reads++;
            final id = r.path.split('/').last;
            return reply({
              'id': id,
              'sn': id,
              'typeCode': 'helmet',
              'online': online ? '1' : '0',
              'connectionQuality': 'ok',
              'currentAssignment': {'personId': id.replaceFirst('d', 'p')},
              'capabilities': {
                'actions': ['intercom'],
              },
            });
          }
          return reply({'records': [], 'total': 0});
        });
        addTearDown(session.dispose);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: CommunicationsPage()),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          WearScope(
            session: session,
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('在线测试1'), findsOneWidget);
        if (withBroadcast) {
          await tester.ensureVisible(find.text('在线测试1'));
          await tester.tap(find.text('在线测试1'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('文字播报'));
          await tester.pumpAndSettle();
          final input = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.hintText == '输入要播报的内容',
          );
          await tester.ensureVisible(input);
          await tester.enterText(input, '请注意安全');
          await tester.ensureVisible(find.text('提交播报指令'));
          await tester.tap(find.text('提交播报指令'));
          await tester.pumpAndSettle();
          expect(broadcasts, 1);
          await tester.ensureVisible(find.byTooltip('收起文字播报'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('收起文字播报'));
          await tester.pumpAndSettle();
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        final offset = scroll.pixels;
        final before = reads;
        online = false;
        if (withBroadcast) {
          await tester.pump(const Duration(seconds: 10));
        } else {
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
        }
        await tester.pumpAndSettle();
        expect(reads, greaterThan(before));
        if (withBroadcast) expect(receiptReads, greaterThan(0));
        expect(find.text('安全帽离线'), findsWidgets);
        expect(scroll.pixels, closeTo(offset, 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
      skip: withBroadcast && !callLabEnabled,
    );
  }
}
