import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rolling_intelligence_headband/wear/communications/phone_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wear_comms_entry_test.dart' show openDevice;
import 'wear_session_test.dart' show reply;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final offer in [true, false]) {
    testWidgets('phone ${offer ? 'offer' : 'answer'} negotiates audio only', (
      t,
    ) async {
      await openDevice(t, []);
      final peer = _AudioPeer();
      final originalFactory = PhoneAudio.connectionFactory;
      PhoneAudio.connectionFactory = (_) async => peer;
      addTearDown(() => PhoneAudio.connectionFactory = originalFactory);
      final audio = PhoneAudio(() {});
      await audio.prepare();
      final self = offer ? 'a' : 'b';
      final other = offer ? 'b' : 'a';
      String? submitted;
      audio.sync({
        'self': self,
        'members': [
          {'id': other, 'state': 'accepted'},
        ],
        'signals': [
          if (!offer)
            {'from': other, 'to': self, 'type': 'offer', 'sdp': 'fixture'},
        ],
      }, (to, type, sdp) async => submitted = type);
      await t.pump();
      expect(submitted, offer ? 'offer' : 'answer');
      expect(peer.constraints?['mandatory'], {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': false,
      });
      await audio.close();
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    });
  }

  testWidgets(
    'dial sends only selected phones once and hangup uses the same room',
    (t) async {
      final requests = <RequestOptions>[];
      Map<String, dynamic>? call;
      final router = await openDevice(
        t,
        requests,
        phoneReply: (r) async {
          if (r.path.endsWith('/start')) {
            call = {
              'id': 'room-1',
              'self': 'local',
              'caller': 'local',
              'members': [
                {'id': 'local', 'name': '调度员', 'state': 'accepted'},
                {'id': 'remote', 'name': '联系人00', 'state': 'ringing'},
              ],
            };
          }
          if (r.path.endsWith('/leave')) call = null;
          return reply({
            'ready': true,
            'contacts': ['0', '1'],
            'call': call,
          });
        },
      );
      router.go('/communications');
      await t.pumpAndSettle();
      for (final id in ['0', '1']) {
        await t.tap(find.byKey(ValueKey('contact-call-p:$id')));
        await t.pumpAndSettle();
      }
      expect(requests.where((r) => r.path.endsWith('/start')), isEmpty);
      await t.tap(find.widgetWithText(TextButton, '手机呼叫'));
      await t.pumpAndSettle();
      final create = requests.singleWhere((r) => r.path.endsWith('/start'));
      expect(create.data['personIds'], ['0', '1']);
      expect(
        requests.where((r) => r.path == '/api/v1/calls' && r.method == 'POST'),
        isEmpty,
      );
      await t.tap(find.text('挂断'));
      await t.pumpAndSettle();
      expect(
        requests.singleWhere((r) => r.path.endsWith('/leave')).data['callId'],
        'room-1',
      );
      expect(find.text('挂断'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );

  testWidgets(
    'incoming call is visible on another page and microphone waits for acceptance',
    (t) async {
      final requests = <RequestOptions>[];
      var arrived = false, accepted = false, ended = false, permissions = 0;
      await openDevice(
        t,
        requests,
        onPermissionRequest: () => permissions++,
        phoneReply: (r) async {
          if (r.path.endsWith('/accept')) accepted = true;
          if (r.path.endsWith('/leave')) ended = true;
          return reply({
            'ready': true,
            'contacts': [],
            'call': arrived && !ended
                ? {
                    'id': 'incoming-1',
                    'self': 'local',
                    'caller': 'remote',
                    'members': [
                      {
                        'id': 'local',
                        'name': '值守人员',
                        'state': accepted ? 'accepted' : 'ringing',
                      },
                      {
                        'id': 'remote',
                        'name': '测试调度员',
                        'state': accepted ? 'left' : 'accepted',
                      },
                    ],
                  }
                : null,
          });
        },
      );
      arrived = true;
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(find.text('接听'), findsOneWidget);
      expect(permissions, 0);
      await t.tap(find.text('接听'));
      await t.pumpAndSettle();
      expect(permissions, 1);
      expect(
        requests.singleWhere((r) => r.path.endsWith('/accept')).data['callId'],
        'incoming-1',
      );
      await t.tap(find.text('挂断'));
      await t.pumpAndSettle();
      expect(find.text('接听'), findsNothing);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
}

class _AudioPeer extends RTCPeerConnection {
  Map<String, dynamic>? constraints;
  RTCSessionDescription? local;

  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async => _Sender();
  @override
  RTCIceGatheringState get iceGatheringState =>
      RTCIceGatheringState.RTCIceGatheringStateComplete;
  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? options,
  ]) async {
    constraints = options;
    return RTCSessionDescription('a=candidate:fixture', 'offer');
  }

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic>? options,
  ]) async {
    constraints = options;
    return RTCSessionDescription('a=candidate:fixture', 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    local = description;
  }

  @override
  Future<RTCSessionDescription?> getLocalDescription() async => local;
  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sender extends Fake implements RTCRtpSender {}
