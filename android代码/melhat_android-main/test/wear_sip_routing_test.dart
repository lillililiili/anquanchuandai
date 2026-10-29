import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
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
