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
          expect(
            find.byKey(const ValueKey('verification-situation')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('event-observation')), findsNothing);
          expect(
            find.byKey(const ValueKey('event-capture-photo')),
            findsNothing,
          );
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

  testWidgets(
    'changing forms preserves separate drafts and opens just one editor',
    (t) async {
      await launchAcceptance(t, AcceptanceBackend(), scale: 1.5);
      await openAcceptance(t, '/events?eventId=401');
      final observation = find.byKey(const ValueKey('event-open-observation'));
      await tapAcceptance(t, observation);
      await enterAcceptance(t, 'event-observation', '人员已联系');
      await fillVerification(t);
      expect(find.byKey(const ValueKey('event-observation')), findsNothing);
      await tapAcceptance(t, observation);
      expect(
        find.byKey(const ValueKey('verification-situation')),
        findsNothing,
      );
      expect(
        t
            .widget<TextField>(find.byKey(const ValueKey('event-observation')))
            .controller!
            .text,
        '人员已联系',
      );
      expect(find.byKey(const ValueKey('event-capture-photo')), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('event coordinates and handling records open on demand', (
    t,
  ) async {
    final backend = AcceptanceBackend();
    backend.events.first.addAll({
      'locationLat': '31.21',
      'locationLng': '121.44',
      'coordinateSystem': 'UNKNOWN',
      'locationQuality': 'unknown',
      'observations': [
        {'comment': '已检查现场', 'actor': '值班员'},
      ],
    });
    await launchAcceptance(t, backend);
    await openAcceptance(t, '/events?eventId=401');
    final position = find.byKey(const ValueKey('event-position'));
    expect(find.byKey(const ValueKey('event-location-card')), findsNothing);
    expect(find.text('已检查现场'), findsNothing);
    await tapAcceptance(t, position);
    expect(
      find.byKey(const ValueKey('event-location-unavailable')),
      findsOneWidget,
    );
    expect(find.textContaining('原始纬度 31.21'), findsOneWidget);
    await tapAcceptance(t, position);
    expect(find.byKey(const ValueKey('event-location-card')), findsNothing);
    await tapAcceptance(t, find.byKey(const ValueKey('event-history')));
    expect(find.text('已检查现场'), findsOneWidget);
    expect(backend.writes, isEmpty);
  });

  for (final status in {'closed': '历史已处理', 'confirmed': '已确认'}.entries) {
    testWidgets(
      'a completed ${status.key} event displays its actual status without a pending form',
      (t) async {
        final backend = AcceptanceBackend();
        final event = backend.events.first;
        event['status'] = status.key;
        event['alarmDescription'] = event['alarmName'];
        await launchAcceptance(t, backend);
        await openAcceptance(t, '/events?eventId=${event['id']}');
        expect(find.text(status.value), findsOneWidget);
        expect(find.text(event['alarmName'].toString()), findsOneWidget);
        expect(find.text('待值守人员核验'), findsNothing);
        expect(
          find.byKey(const ValueKey('event-open-verification')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('event-open-observation')),
          findsNothing,
        );
        expect(find.text('暂无已提交附件'), findsNothing);
        expect(find.text('暂无补充记录'), findsNothing);
      },
    );
  }
}
