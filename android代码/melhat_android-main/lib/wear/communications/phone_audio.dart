import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core.dart';
import 'prepared_rtc_media.dart';
import 'rtc_engine.dart';

/// Each accepted phone has its own encrypted audio connection to the other accepted phones.
class PhoneAudio {
  @visibleForTesting
  static Future<RTCPeerConnection> Function(Map<String, dynamic>)
  connectionFactory = createPeerConnection;

  PhoneAudio(this.changed);
  final void Function() changed;
  final _preparation = prepareWearMedia();
  final Map<String, _PhonePeer> _peers = {};
  MediaStream? _microphone;
  int _generation = 0;
  bool muted = false, speaker = false;
  bool get prepared => _microphone != null;

  bool connected(String id) => _peers[id]?.connected == true;
  String? failure(String id) => _peers[id]?.error;
  Future<void> prepare() async {
    final generation = _generation;
    await _preparation.prepare(video: false);
    if (generation != _generation) throw const RtcOperationCancelled();
    _microphone = _preparation.take(video: false);
    if (_microphone == null) throw const RtcJoinFailure('麦克风暂不可用');
  }

  void sync(JsonMap call, Future<void> Function(String, String, String) send) {
    final local = _microphone;
    if (local == null) return;
    final self = idOf(call['self']);
    final ids = jsonList(call['members'])
        .where((m) => m['state'] == 'accepted' && m['id'] != self)
        .map((m) => idOf(m['id']))
        .toSet();
    for (final id in _peers.keys.toList()) {
      if (!ids.contains(id)) unawaited(_peers.remove(id)!.close());
    }
    for (final id in ids) {
      final peer = _peers.putIfAbsent(id, () => _PhonePeer(changed));
      final remote = jsonList(
        call['signals'],
      ).where((s) => s['from'] == id && s['to'] == self).firstOrNull;
      unawaited(
        peer.negotiate(
          local,
          jsonList(jsonMap(call['iceByPeer'])[id]),
          self.compareTo(id) < 0,
          remote,
          (type, sdp) => send(id, type, sdp),
        ),
      );
    }
  }

  void setMuted(bool value) {
    for (final track in _microphone?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !value;
    }
    muted = value;
    changed();
  }

  Future<void> setSpeaker(bool value) async {
    await Helper.setSpeakerphoneOn(value);
    speaker = value;
    changed();
  }

  Future<void> close() async {
    _generation++;
    final peers = _peers.values.toList();
    _peers.clear();
    final local = _microphone;
    _microphone = null;
    final restoreRoute = speaker;
    muted = false;
    speaker = false;
    await _preparation.cancel();
    await Future.wait(peers.map((p) => p.close()));
    if (local != null) await releaseWearMedia(local);
    if (restoreRoute) await Helper.setSpeakerphoneOn(false);
  }
}

class _PhonePeer {
  _PhonePeer(this.changed);
  // The Android plugin's defaults also offer video. Phone signalling accepts audio only.
  static const _audioOnly = {
    'mandatory': {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': false},
  };
  final void Function() changed;
  RTCPeerConnection? pc;
  bool working = false, closed = false, remoteSet = false, submitted = false;
  bool transport = false, audio = false;
  bool get connected => transport && audio;
  String? error, localSdp;
  Timer? _deadline;

  Future<void> negotiate(
    MediaStream mic,
    List<JsonMap> ice,
    bool offer,
    JsonMap? remote,
    Future<void> Function(String, String) send,
  ) async {
    if (closed || working || error != null || (!offer && remote == null)) {
      return;
    }
    working = true;
    try {
      var conn = pc;
      if (conn == null) {
        conn = await PhoneAudio.connectionFactory({
          'iceServers': ice,
          'sdpSemantics': 'unified-plan',
        });
        if (closed) {
          await conn.close();
          await conn.dispose();
          return;
        }
        pc = conn;
        conn.onConnectionState = (state) {
          if (closed) return;
          transport =
              state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
          if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            error = '连接失败';
          }
          if (connected) {
            error = null;
            _deadline?.cancel();
          }
          changed();
        };
        conn.onTrack = (event) {
          if (closed || event.track.kind != 'audio') return;
          audio = true;
          if (connected) {
            error = null;
            _deadline?.cancel();
          }
          changed();
        };
        _deadline = Timer(const Duration(seconds: 55), () {
          if (!closed && !connected) {
            error = '连接超时';
            changed();
          }
        });
        for (final track in mic.getAudioTracks()) {
          await conn.addTrack(track, mic);
        }
      }
      if (closed) return;
      if (remote != null && !remoteSet) {
        await conn.setRemoteDescription(
          RTCSessionDescription(idOf(remote['sdp']), idOf(remote['type'])),
        );
        remoteSet = true;
      }
      if (localSdp == null) {
        final done = Completer<void>();
        conn.onIceGatheringState = (state) {
          if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
              !done.isCompleted) {
            done.complete();
          }
        };
        final description = offer
            ? await conn.createOffer(_audioOnly)
            : await conn.createAnswer(_audioOnly);
        if (closed) return;
        await conn.setLocalDescription(description);
        if (conn.iceGatheringState !=
            RTCIceGatheringState.RTCIceGatheringStateComplete) {
          await done.future.timeout(
            const Duration(seconds: 12),
            onTimeout: () {},
          );
        }
        if (closed) return;
        final sdp = (await conn.getLocalDescription())?.sdp;
        if (sdp == null || !sdp.contains('a=candidate:')) {
          throw StateError('No ICE candidates');
        }
        localSdp = sdp;
      }
      if (closed || submitted) return;
      try {
        await send(offer ? 'offer' : 'answer', localSdp!);
        submitted = true;
      } on WearApiException catch (e) {
        if (e.code >= 400 && e.code < 500 && e.code != 429) rethrow;
      }
    } catch (_) {
      if (!closed) {
        error = '语音连接失败';
        changed();
      }
    } finally {
      working = false;
    }
  }

  Future<void> close() async {
    closed = true;
    _deadline?.cancel();
    final conn = pc;
    pc = null;
    if (conn != null) {
      try {
        await conn.close();
      } finally {
        await conn.dispose();
      }
    }
  }
}
