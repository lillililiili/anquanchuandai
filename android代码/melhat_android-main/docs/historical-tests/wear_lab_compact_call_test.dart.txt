import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/core.dart';
import 'package:rolling_intelligence_headband/wear/communications/lab_calls.dart';
import 'wear_lab_calls_test.dart' show row, sessionWith;
import 'wear_session_test.dart' show reply;

void main() {
  testWidgets('three person voice call fits one 360 by 640 screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final call = {
      ...row(state: 'connected'),
      'sos': false,
      'participants': [
        for (var i = 0; i < 3; i++)
          {
            'deviceId': '$i',
            'personName': ['陈建国', '周明', '赵启航'][i],
            'sn': 'QA-H00$i',
            'typeCode': 'helmet',
            'state': 'connected',
          },
      ],
    };
    final session = sessionWith(
      (_) => reply({
        'calls': [call],
        'devices': [],
      }),
    );
    final model = LabCallsModel(session);
    await tester.runAsync(model.poll);
    await tester.pumpWidget(
      WearScope(
        session: session,
        child: MaterialApp(
          home: LabCallScope(
            model: model,
            child: const LabCallPage(id: 'call-1'),
          ),
        ),
      ),
    );
    await tester.pump();
    for (final name in ['陈建国', '周明', '赵启航', '参与人员', '结束通话', '同步状态']) {
      final item = find.text(name);
      expect(item, findsOneWidget);
      expect(tester.getRect(item).bottom, lessThanOrEqualTo(640), reason: name);
    }
    expect(find.byIcon(Icons.graphic_eq), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    model.dispose();
    session.dispose();
  });
}
