import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wear_acceptance_fixture.dart';

void main() {
  testWidgets(
    'ordinary user observation draft survives leaving detail at enlarged text',
    (t) async {
      final backend = AcceptanceBackend();
      await launchAcceptance(t, backend, account: 'member', scale: 1.5);
      await openAcceptance(t, '/events?eventId=402');
      await enterAcceptance(t, 'event-observation', '已到达安全区域，等待协助');
      await tapAcceptance(t, find.byTooltip('返回事件列表'));
      await openAcceptance(t, '/events?eventId=402');
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('event-observation')))
            .controller!
            .text,
        '已到达安全区域，等待协助',
      );
      expect(find.byKey(const ValueKey('verification-submit')), findsNothing);
      await tapAcceptance(
        t,
        find.byKey(const ValueKey('event-observation-submit')),
      );
      expect(backend.events.last['observations'], hasLength(1));
      expect(backend.events.last['status'], 'open');
      expect(t.takeException(), isNull);
    },
  );
}
