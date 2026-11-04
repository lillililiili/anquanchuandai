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
              ),
            ),
          ),
        ),
      );
      expect(find.text('设备语音'), findsOneWidget);
      expect(find.text('视频通话'), findsNothing);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'connected helmet services honor runtime availability independently of acceptance evidence',
    () {
      for (final key in [
        'voice',
        'video',
        'videoCall',
        'photo',
        'recording',
        'broadcast',
      ]) {
        final device = <String, dynamic>{
          'source': 'DIRECT_HELMET',
          'featureStates': {
            key: {
              'supported': true,
              'verified': false,
              'available': true,
              'integrationStatus': 'CONNECTED',
            },
          },
        };
        final ready = deviceFeature(device, key);
        expect(ready.available, true, reason: key);
        expect(
          ready.verified,
          false,
          reason: 'do not invent acceptance evidence',
        );
        expect(ready.toJson()['integrationStatus'], 'CONNECTED');
        expect(
          deviceFeature({...device, 'source': 'DIRECT_BELT'}, key).available,
          false,
        );
        expect(
          deviceFeature({...device, 'source': 'UNKNOWN'}, key).available,
          false,
        );
        for (final patch in [
          {'available': false},
          {'supported': false},
          {'integrationStatus': 'NOT_CONNECTED'},
        ]) {
          expect(
            deviceFeature({
              ...device,
              'featureStates': {
                key: {
                  ...Map<String, dynamic>.from(
                    (device['featureStates'] as Map)[key],
                  ),
                  ...patch,
                },
              },
            }, key).available,
            false,
            reason: '$key $patch',
          );
        }
      }
    },
  );

  test(
    'real helmet calls require a current wearer, online device, runtime ready service and permission',
    () {
      const policy = CommunicationsPolicy(
        userId: 'u',
        permissions: {'wear:call:start'},
      );
      final raw = <String, dynamic>{
        'id': 'h',
        'source': 'DIRECT_HELMET',
        'typeCode': 'helmet',
        'online': 1,
        'currentAssignment': {'personId': 'p'},
        'equipmentContext': {
          'deviceId': 'h',
          'personId': 'p',
          'assignmentId': 'a',
          'assignmentVersion': 2,
        },
        'featureStates': {
          'voice': {
            'supported': true,
            'verified': false,
            'available': true,
            'integrationStatus': 'CONNECTED',
          },
        },
      };
      final ready = CommunicationDevice.fromJson(raw);
      expect(policy.canStartVoice(ready), true);
      expect(ready.feature('intercom').verified, false);
      expect(
        const CommunicationsPolicy(
          userId: 'u',
          permissions: {},
        ).canStartVoice(ready),
        false,
      );
      for (final patch in [
        {'online': 0},
        {'connectionQuality': 'stale'},
        {'typeCode': 'belt'},
        {'equipmentContext': <String, dynamic>{}},
        {
          'currentAssignment': {'personId': 'other-person'},
        },
        {
          'equipmentContext': {
            ...raw['equipmentContext'] as Map,
            'deviceId': 'other-device',
          },
        },
      ]) {
        final unavailable = CommunicationDevice.fromJson({...raw, ...patch});
        expect(policy.canStartVoice(unavailable), false, reason: '$patch');
        expect(unavailable.feature('intercom').reason, isNotEmpty);
      }
      final stale = ContactRoster.unavailableDevices([ready]).single;
      expect(stale.source, 'DIRECT_HELMET');
      expect(policy.canStartVoice(stale), false);
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
    'shared snapshot projection preserves runtime-ready service and issuance identity through the contact model',
    () {
      final ready = {
        'supported': true,
        'verified': false,
        'available': true,
        'integrationStatus': 'CONNECTED',
      };
      final device = <String, dynamic>{
        'id': 'h',
        'ledgerId': 'LH',
        'type': 'H',
        'source': 'DIRECT_HELMET',
        'active': true,
        'online': true,
        'freshness': 'CURRENT',
        'sourceTime': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
        'communicationProtocol': 'SIP',
        'capabilities': ['intercom'],
        'featureStates': {'voice': ready},
      };
      final identity = {
        'deviceId': 'h',
        'personId': 'p',
        'assignmentId': 'a',
        'assignmentVersion': 2,
      };
      final projection = SharedModels({
        'devices': [device],
        'personEquipmentContext': {
          'p': {
            'personId': 'p',
            'devices': [identity],
            'features': {
              'voice': {...ready, ...identity},
            },
          },
        },
      }).device(device);
      expect(projection['capabilities']['actions'], ['intercom']);
      expect(projection['featureStates']['voice']['verified'], false);
      expect(
        projection['featureStates']['voice']['integrationStatus'],
        'CONNECTED',
      );
      final contact = CommunicationDevice.fromJson(projection);
      expect(contact.source, 'DIRECT_HELMET');
      expect(contact.personId, 'p');
      expect(
        const CommunicationsPolicy(
          userId: 'u',
          permissions: {'wear:call:start'},
        ).canStartVoice(contact),
        true,
      );
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
