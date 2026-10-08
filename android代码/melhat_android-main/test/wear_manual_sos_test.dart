import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wear_acceptance_fixture.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
      'empty SOS confirms immediately and opens its own event at $scale',
      (t) async {
        final backend = AcceptanceBackend();
        await launchAcceptance(t, backend, account: 'member', scale: scale);
        await tapAcceptance(t, find.byKey(const ValueKey('home-manual-sos')));
        await tapAcceptance(t, find.byKey(const ValueKey('manual-sos-submit')));
        expect(backend.events, hasLength(2));
        expect(find.text('请填写报警位置'), findsNothing);
        await tapAcceptance(t, find.text('确认求助'));
        expect(backend.events, hasLength(3));
        final created = backend.events.firstWhere(
          (e) => e['source'] == 'manual_sos',
        );
        expect(created['status'], 'open');
        expect(created['assistance']['state'], 'waiting');
        expect(find.text('手机手动求助'), findsOneWidget);
        expect(find.text('提交待审批'), findsNothing);
        expect(find.byKey(const ValueKey('verification-submit')), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('cancel SOS confirmation creates no event', (t) async {
    final backend = AcceptanceBackend();
    await launchAcceptance(t, backend, account: 'member');
    await tapAcceptance(t, find.byKey(const ValueKey('home-manual-sos')));
    await tapAcceptance(t, find.byKey(const ValueKey('manual-sos-submit')));
    await tapAcceptance(t, find.text('取消'));
    expect(backend.events, hasLength(2));
    expect(backend.writes, isEmpty);
    expect(find.byKey(const ValueKey('manual-sos-submit')), findsOneWidget);
  });
}
