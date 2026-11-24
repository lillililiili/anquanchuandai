import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rolling_intelligence_headband/config/backend_config.dart';
import 'package:rolling_intelligence_headband/main.dart' as app;
import 'package:rolling_intelligence_headband/wear/communications/phone_audio.dart';

/// Real handset acceptance using the regular app and its original login.
/// The disposable, debug-only build records counters, never SDP or audio.
void main() {
  if (!kDebugMode ||
      BackendConfig.mock ||
      BackendConfig.baseUrl != 'https://lingzhiaide.com/wear-api') {
    throw StateError(
      'Use the debug acceptance package with the original service.',
    );
  }
  PhoneAudio.connectionFactory = (configuration) async {
    final pc = await createPeerConnection({
      ...configuration,
      'iceTransportPolicy': 'relay',
    });
    var reading = false;
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (reading) return;
      reading = true;
      try {
        if (pc.connectionState ==
            RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
          timer.cancel();
          return;
        }
        final byId = {for (final s in await pc.getStats()) s.id: s};
        StatsReport? first(String type) =>
            byId.values.where((s) => s.type == type).firstOrNull;
        final transport = first('transport');
        final pair =
            byId[transport?.values['selectedCandidatePairId']] ??
            byId.values
                .where(
                  (s) =>
                      s.type == 'candidate-pair' &&
                      s.values['state'] == 'succeeded' &&
                      s.values['nominated'] == true,
                )
                .firstOrNull;
        final incoming = first('inbound-rtp')?.values;
        final outgoing = first('outbound-rtp')?.values;
        final source = first('media-source')?.values;
        final playout = first('media-playout')?.values;
        debugPrint(
          'WEAR_HANDSET_AUDIO ${jsonEncode({'time': DateTime.now().millisecondsSinceEpoch, 'state': pc.connectionState?.name, 'local': byId[pair?.values['localCandidateId']]?.values['candidateType'], 'remote': byId[pair?.values['remoteCandidateId']]?.values['candidateType'], 'tx': outgoing?['packetsSent'], 'rx': incoming?['packetsReceived'], 'rxEnergy': incoming?['totalAudioEnergy'], 'txEnergy': source?['totalAudioEnergy'], 'rxSeconds': incoming?['totalSamplesDuration'], 'playoutSeconds': playout?['totalSamplesDuration']})}',
        );
      } catch (_) {
        timer.cancel();
      } finally {
        reading = false;
      }
    });
    return pc;
  };
  app.main();
}
