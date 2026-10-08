import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wear_acceptance_fixture.dart';

void main() {
  for (final mode in [
    'success',
    'network',
    'conflict',
    'empty',
    'whitespace',
  ]) {
    testWidgets(
      'observation $mode preserves editable notes and never verifies',
      (t) async {
        final backend = AcceptanceBackend();
        await launchAcceptance(t, backend, account: 'member');
        await openAcceptance(t, '/events?eventId=402');
        final originalStatus = backend.events.last['status'];
        final text = mode == 'empty'
            ? ''
            : mode == 'whitespace'
            ? '   '
            : '现场需要协助';
        await enterAcceptance(t, 'event-observation', text);
        if (['network', 'conflict'].contains(mode)) {
          backend
            ..failSuffix = '/report'
            ..networkFailure = mode == 'network'
            ..failCode = 409;
        }
        await tapAcceptance(
          t,
          find.byKey(const ValueKey('event-observation-submit')),
        );
        final posts = backend.writes.where((r) => r.path.endsWith('/report'));
        if (['empty', 'whitespace'].contains(mode)) {
          expect(posts, isEmpty);
          expect(find.textContaining('请填写现场情况'), findsWidgets);
        } else if (mode != 'success') {
          expect(posts, hasLength(1));
          expect(
            t
                .widget<TextField>(
                  find.byKey(const ValueKey('event-observation')),
                )
                .controller!
                .text,
            text,
          );
          expect(backend.events.last['observations'], isEmpty);
          backend.failSuffix = null;
          await tapAcceptance(
            t,
            find.byKey(const ValueKey('event-observation-submit')),
          );
          expect(backend.events.last['observations'], hasLength(1));
        } else {
          expect(posts, hasLength(1));
          expect(backend.events.last['observations'], hasLength(1));
        }
        expect(backend.events.last['status'], originalStatus);
        expect(backend.events.last['verification'], isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final mode in ['network', 'conflict', 'invalid', 'success']) {
    testWidgets(
      'final verification $mode preserves draft or completes read-only',
      (t) async {
        final backend = AcceptanceBackend();
        await launchAcceptance(t, backend);
        await openAcceptance(t, '/events?eventId=401');
        if (mode != 'invalid') await fillVerification(t);
        if (['network', 'conflict'].contains(mode)) {
          backend
            ..failSuffix = '/verify'
            ..networkFailure = mode == 'network'
            ..failCode = 409;
        }
        await tapAcceptance(
          t,
          find.byKey(const ValueKey('verification-submit')),
        );
        await tapAcceptance(t, find.text('确认'));
        if (mode == 'success') {
          expect(backend.events.first['status'], 'verified');
          expect(find.text('核验结果（只读）'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('verification-submit')),
            findsNothing,
          );
        } else {
          expect(backend.events.first['status'], isNot('verified'));
          expect(
            find.byKey(const ValueKey('verification-submit')),
            findsOneWidget,
          );
          if (mode == 'invalid') {
            expect(
              backend.writes.where((r) => r.path.endsWith('/verify')),
              isEmpty,
            );
            expect(find.textContaining('请选择核验结论'), findsWidgets);
          } else {
            expect(
              t
                  .widget<TextField>(
                    find.byKey(const ValueKey('verification-situation')),
                  )
                  .controller!
                  .text,
              '已到现场，人员安全',
            );
            expect(
              backend.writes.where((r) => r.path.endsWith('/verify')),
              hasLength(1),
            );
          }
        }
        expect(t.takeException(), isNull);
      },
    );
  }
}
