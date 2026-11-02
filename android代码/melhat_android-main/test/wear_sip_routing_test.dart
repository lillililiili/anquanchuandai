import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rolling_intelligence_headband/wear/communications/media_preparation.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/communications/rtc_engine.dart';
import 'package:rolling_intelligence_headband/wear/communications/sip_rtc_engine.dart';

void main() {
  RtcCredentials credentials(String protocol) => RtcCredentials(
    appId: 'app',
    channelName: 'room',
    uid: 1,
    token: 'test',
    protocol: protocol,
  );
  final callbacks = RtcCallbacks(
    onLocalJoined: () {},
    onRemoteJoined: (_) {},
    onRemoteLeft: (_) {},
    onTokenExpiring: () {},
    onFailure: (_) {},
  );
  test(
    'SIP never initializes Agora; subsequent calls dispose their previous driver',
    () async {
      final sip = _Driver(), agora = _Driver();
      final engine = ProtocolWearRtcEngine(
        sipFactory: (_) => sip,
        agoraFactory: () => agora,
      );
      await engine.join(credentials('SIP'), callbacks);
      expect(sip.joins, 1);
      expect(agora.joins, 0);
      await engine.join(credentials('AGORA'), callbacks);
      expect(sip.disposed, isTrue);
      expect(agora.joins, 1);
      await engine.dispose();
      expect(agora.disposed, isTrue);
    },
  );
  test(
    'leaving during asynchronous join prevents a late session from becoming active',
    () async {
      final pending = Completer<void>(), driver = _Driver();
      driver.wait = pending.future;
      final engine = ProtocolWearRtcEngine(sipFactory: (_) => driver);
      final joining = engine.join(credentials('SIP'), callbacks);
      await Future<void>.delayed(Duration.zero);
      final result = expectLater(
        joining,
        throwsA(isA<RtcOperationCancelled>()),
      );
      await engine.leave();
      pending.complete();
      await result;
      expect(driver.disposed, isTrue);
      await engine.dispose();
    },
  );
  test(
    'unsupported protocols are rejected without creating a native driver',
    () async {
      var created = 0;
      final engine = ProtocolWearRtcEngine(
        agoraFactory: () {
          created++;
          return _Driver();
        },
      );
      await expectLater(
        engine.join(credentials('UNKNOWN'), callbacks),
        throwsA(isA<RtcJoinFailure>()),
      );
      expect(created, 0);
      await engine.dispose();
    },
  );

  test(
    'SIP consumes the exact prepared stream once and owns its cleanup',
    () async {
      final media = _Media(), sip = _PreparedDriver();
      var captures = 0, temporaryReleases = 0;
      final engine = ProtocolWearRtcEngine(
        sipFactory: (_) => sip,
        preparation: RtcMediaPreparation<MediaStream>(
          requestPermission: (_) async => true,
          acquire: (_) async {
            captures++;
            return media;
          },
          release: (_) async {
            temporaryReleases++;
          },
        ),
      );
      await engine.prepare(video: false);
      await engine.join(credentials('SIP'), callbacks);
      expect(identical(sip.media, media), isTrue);
      expect(captures, 1);
      expect(temporaryReleases, 0);
      await engine.leave();
      expect(sip.disposed, isTrue);
      expect(sip.media, isNull);
      await engine.dispose();
      expect(temporaryReleases, 0);
    },
  );
}

class _Media extends Fake implements MediaStream {}

class _PreparedDriver extends _Driver implements WearPreparedRtcMedia {
  MediaStream? media;
  @override
  void usePreparedMedia(MediaStream stream) => media = stream;
  @override
  Future<void> leave() async {
    media = null;
    await super.leave();
  }
}

class _Driver implements WearRtcEngine {
  int joins = 0;
  bool disposed = false;
  Future<void>? wait;
  @override
  Future<void> join(RtcCredentials c, RtcCallbacks callbacks) async {
    joins++;
    await wait;
  }

  @override
  Future<void> renewToken(String token) async {}
  @override
  Future<void> setMicrophoneMuted(bool muted) async {}
  @override
  Future<void> leave() async {
    disposed = true;
  }

  @override
  Future<void> dispose() => leave();
}
