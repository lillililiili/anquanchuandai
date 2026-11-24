import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/wear/app.dart';
import 'wear_acceptance_fixture.dart';

void main() {
  testWidgets('business cache cleanup permits reopening the same event draft', (
    t,
  ) async {
    final backend = AcceptanceBackend();
    await launchAcceptance(t, backend, account: 'member');
    final router = GoRouter.of(t.element(find.byType(WearShell)));
    router.go('/events?eventId=402');
    await t.pumpAndSettle();
    await tapAcceptance(
      t,
      find.byKey(const ValueKey('event-open-observation')),
    );
    await enterAcceptance(t, 'event-observation', 'unsubmitted cache draft');
    FocusManager.instance.primaryFocus?.unfocus();
    router.go('/me');
    await t.pumpAndSettle();
    await tapAcceptance(t, find.text('清理业务缓存'));
    expect(find.text('已清理业务缓存，保留登录与未提交草稿'), findsOneWidget);
    router.go('/events?eventId=402');
    await t.pumpAndSettle();
    final field = find.byKey(const ValueKey('event-observation'));
    expect(field, findsOneWidget);
    expect(
      t.widget<TextField>(field).controller!.text,
      'unsubmitted cache draft',
    );
  });
}
