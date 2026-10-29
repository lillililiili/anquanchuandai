import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/device_features.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/communications/policy.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_action_bar.dart';
import 'package:rolling_intelligence_headband/wear/communications/contact_filters.dart';
import 'package:rolling_intelligence_headband/wear/shared_models.dart';
import 'package:rolling_intelligence_headband/wear/session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wear_session_test.dart' show MemoryCredentials;

void main() {
  test(
    'support is visible but neither old actions nor pending acceptance authorize commands',
    () {
      const policy = CommunicationsPolicy(
        userId: 'u',
        permissions: {'wear:call:start', 'wear:command:tts'},
      );
      final pending = CommunicationDevice.fromJson({
        'id': 'h',
        'capabilities': {
          'actions': ['intercom', 'tts'],
        },
        'featureStates': {
          'voice': {'supported': true, 'verified': false, 'available': true},
          'broadcast': {
            'supported': false,
            'verified': true,
            'available': true,
          },
        },
      });
      expect(pending.supports('intercom'), true);
      expect(pending.supports('tts'), false);
      expect(policy.canStartVoice(pending), false);
      expect(policy.canSendTts(pending), false);
      expect(
        actionFeature({
          'capabilities': ['intercom'],
        }, 'intercom').available,
        false,
      );
      final verified = CommunicationDevice.fromJson({
        'id': 'h',
        'featureStates': {
          'voice': {'supported': true, 'verified': true, 'available': true},
        },
      });
      expect(policy.canStartVoice(verified), true);
      final stale = ContactRoster.unavailableDevices([verified]).single;
      expect(stale.supports('intercom'), true);
      expect(policy.canStartVoice(stale), false);
    },
  );

  testWidgets(
    'unsupported actions disappear and pending actions remain disabled at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const Scaffold(
              body: ContactActionBar(
                onVoice: null,
                onVideo: null,
                onBroadcast: null,
                showVideo: false,
                showBroadcast: false,
                voicePending: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('设备语音 · 待联调'), findsOneWidget);
      expect(find.text('视频通话'), findsNothing);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'watch toggle removes demo equipment, links and vitals but preserves real evidence',
    () {
      final model = SharedModels({
        'businessConfig': {'simulatedWatchVisible': false},
        'devices': [
          {'id': 'h', 'type': 'H', 'source': 'DIRECT_HELMET', 'demo': true},
          {'id': 'b', 'type': 'B', 'source': 'DIRECT_BELT'},
          {
            'id': 'RL-W001',
            'ledgerId': 'w-ledger',
            'type': 'W',
            'source': 'DEMO_WATCH',
          },
        ],
        'assignments': [
          {'deviceId': 'w-ledger'},
        ],
        'bindings': [
          {'deviceId': 'RL-W001'},
        ],
        'vitals': [
          {'deviceId': 'RL-W001'},
          {'deviceId': 'RL-W001', 'source': 'DEMO_WATCH'},
          {'id': 'real', 'source': 'DEVICE'},
        ],
        'events': [
          {'id': 'demo', 'deviceId': 'RL-W001', 'demo': true},
          {'id': 'real-history', 'deviceId': 'RL-W001', 'source': 'DEVICE'},
        ],
      });
      expect(model.rows('devices').map((d) => d['id']), ['h', 'b']);
      expect(model.rows('assignments'), isEmpty);
      expect(model.rows('bindings'), isEmpty);
      expect(model.rows('vitals').single['id'], 'real');
      expect(model.rows('events').single['id'], 'real-history');
    },
  );

  test(
    'business cache cleanup preserves login, scope and unsent drafts',
    () async {
      SharedPreferences.setMockInitialValues({
        'wear.u.events.s.state': 'old view',
        'wear.u.events.s.draft.e': 'unsent evidence',
        'wear.other.events.s.state': 'other account',
      });
      final credentials = MemoryCredentials();
      await credentials.write('token');
      final session = WearSession(credentials: credentials, mock: false)
        ..token = 'token'
        ..siteId = 's'
        ..me = {'userId': 'u'};
      final scope = session.scopeKey;
      await session.clearBusinessCache();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('wear.u.events.s.state'), isNull);
      expect(prefs.getString('wear.u.events.s.draft.e'), 'unsent evidence');
      expect(prefs.getString('wear.other.events.s.state'), 'other account');
      expect(await credentials.read(), 'token');
      expect(session.token, 'token');
      expect(session.siteId, 's');
      expect(session.scopeKey, isNot(scope));
      session.dispose();
    },
  );
}
