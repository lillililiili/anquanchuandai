import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wear_acceptance_fixture.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    for (final id in ['401', '402']) {
      testWidgets(
        'event $id retains shared verification draft and navigation at $scale',
        (t) async {
          final backend = AcceptanceBackend();
          await launchAcceptance(t, backend, scale: scale);
          await openAcceptance(t, '/events?eventId=$id');
          expect(find.text('事件详情'), findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);
          expect(find.text('提交待审批'), findsNothing);
          await fillVerification(t);
          await tapAcceptance(
            t,
            find.byKey(const ValueKey('verification-save')),
          );
          final event = backend.events.firstWhere((e) => e['id'] == id);
          expect(event['verificationDraft']['situation'], '已到现场，人员安全');
          expect(event['status'], isNot('verified'));
          await tapAcceptance(t, find.byTooltip('返回事件列表'));
          expect(find.byType(NavigationBar), findsOneWidget);
          await openAcceptance(t, '/events?eventId=$id');
          expect(
            t
                .widget<TextField>(
                  find.byKey(const ValueKey('verification-situation')),
                )
                .controller!
                .text,
            '已到现场，人员安全',
          );
          await tapAcceptance(
            t,
            find.byKey(const ValueKey('verification-submit')),
          );
          await tapAcceptance(t, find.text('确认'));
          expect(event['status'], 'verified');
          expect(find.text('核验结果（只读）'), findsOneWidget);
          expect(find.byKey(const ValueKey('event-observation')), findsNothing);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
