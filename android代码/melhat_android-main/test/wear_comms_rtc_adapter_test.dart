import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolling_intelligence_headband/wear/communications/models.dart';
import 'package:rolling_intelligence_headband/wear/communications/rtc_engine.dart';

void main() {
  const credentials = RtcCredentials(
    appId: 'production-app',
    channelName: 'wear-17',
    uid: 4007,
    token: 'secret',
  );
  final callbacks = RtcCallbacks(
    onLocalJoined: () {},
    onRemoteJoined: (_) {},
    onRemoteLeft: (_) {},
    onTokenExpiring: () {},
    onFailure: (_) {},
  );

  test(
    'dispose while permission is pending never creates an Agora driver',
    () async {
      final permission = Completer<bool>();
      var factories = 0;
      final adapter = AgoraWearRtcEngine(
        driverFactory: () {
          factories++;
          return FakeAgoraDriver();
        },
        requestPermissions: (_) => permission.future,
      );

      final join = adapter.join(credentials, callbacks);
      await Future<void>.delayed(Duration.zero);
      await adapter.dispose();
      permission.complete(true);

      await expectLater(join, throwsA(isA<RtcOperationCancelled>()));
      expect(factories, 0);
    },
  );

  test(
    'leave during initialize releases late driver and never joins channel',
    () async {
      final driver = FakeAgoraDriver()..initializeGate = Completer<void>();
      final adapter = AgoraWearRtcEngine(
        driverFactory: () => driver,
        requestPermissions: (_) async => true,
      );

      final join = adapter.join(credentials, callbacks);
      await driver.initializeStarted.future;
      final leave = adapter.leave();
      driver.initializeGate!.complete();

      await leave;
      await expectLater(join, throwsA(isA<RtcOperationCancelled>()));
      expect(driver.joinCount, 0);
      expect(driver.leaveCount, 1);
      expect(driver.releaseCount, 1);
    },
  );
}

class FakeAgoraDriver implements AgoraRtcDriver {
  final initializeStarted = Completer<void>();
  Completer<void>? initializeGate;
  int joinCount = 0;
  int leaveCount = 0;
  int releaseCount = 0;

  @override
  RtcEngine? get nativeEngine => null;

  @override
  Future<void> initialize(String appId) async {
    if (!initializeStarted.isCompleted) initializeStarted.complete();
    await initializeGate?.future;
  }

  @override
  Future<void> enableAudio() async {}

  @override
  Future<void> enableVideo() async {}

  @override
  Future<void> disableVideo() async {}

  @override
  Future<void> setSpeakerphoneEnabled() async {}

  @override
  void registerCallbacks(RtcCallbacks callbacks) {}

  @override
  Future<void> joinChannel(RtcCredentials credentials) async => joinCount++;

  @override
  Future<void> renewToken(String token) async {}

  @override
  Future<void> setMicrophoneMuted(bool muted) async {}

  @override
  Future<void> leaveChannel() async => leaveCount++;

  @override
  Future<void> release() async => releaseCount++;
}
