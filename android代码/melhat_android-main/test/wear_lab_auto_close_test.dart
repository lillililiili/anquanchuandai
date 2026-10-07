import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_calls.dart';
import 'wear_lab_calls_test.dart' show row, sessionWith;
import 'wear_session_test.dart' show reply;

void main() {
  for (final withSheet in [false, true]) {
    testWidgets('confirmed end returns to previous page, sheet=$withSheet', (
      tester,
    ) async {
      var current = row(state: 'connected');
      final session = sessionWith(
        (_) => reply({
          'calls': [current],
          'devices': [],
        }),
      );
      final model = LabCallsModel(session);
      await tester.runAsync(model.poll);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        WearScope(
          session: session,
          child: LabCallScope(
            model: model,
            child: MaterialApp(
              navigatorKey: navigator,
              home: const Scaffold(body: Text('通讯主页')),
            ),
          ),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const LabCallPage(id: 'call-1'),
        ),
      );
      await tester.pumpAndSettle();
      // One participant leaving must not dismiss an ongoing group call.
      current = {
        ...current,
        'participants': [
          {'deviceId': 'd1', 'state': 'ended'},
          {'deviceId': 'd2', 'state': 'connected'},
        ],
      };
      await tester.runAsync(model.poll);
      await tester.pumpAndSettle();
      expect(find.byType(LabCallPage), findsOneWidget);
      if (withSheet) {
        await tester.ensureVisible(find.text('参与人员'));
        await tester.tap(find.byIcon(Icons.people_outline));
        await tester.pumpAndSettle();
        expect(find.text('参与设备 · 状态联调'), findsOneWidget);
      }
      // A stale ended snapshot is not a confirmed server termination.
      model.calls = [
        {...current, 'state': 'ended'},
      ];
      model.setForeground(false);
      await tester.pumpAndSettle();
      expect(find.byType(LabCallPage), findsOneWidget);
      current = {...current, 'state': 'ended'};
      model.foreground = true;
      await tester.runAsync(model.poll);
      await tester.pumpAndSettle();
      expect(find.byType(LabCallPage), findsNothing);
      expect(find.text('参与设备 · 状态联调'), findsNothing);
      expect(find.text('通讯主页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      model.dispose();
      session.dispose();
    });
  }
}
