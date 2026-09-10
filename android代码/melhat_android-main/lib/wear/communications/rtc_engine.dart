import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models.dart';

class RtcCallbacks {
  const RtcCallbacks({
    required this.onLocalJoined,
    required this.onRemoteJoined,
    required this.onRemoteLeft,
    required this.onTokenExpiring,
    required this.onFailure,
  });

  final void Function() onLocalJoined;
  final void Function(int uid) onRemoteJoined;
  final void Function(int uid) onRemoteLeft;
  final void Function() onTokenExpiring;
  final void Function(String message) onFailure;
}

abstract interface class WearRtcEngine {
  Future<void> join(RtcCredentials credentials, RtcCallbacks callbacks);
  Future<void> renewToken(String token);
  Future<void> setMicrophoneMuted(bool muted);
  Future<void> leave();
  Future<void> dispose();
}

class RtcPermissionDenied implements Exception {
  const RtcPermissionDenied({required this.video});
  final bool video;

  @override
  String toString() => video ? '需要麦克风和摄像头权限' : '需要麦克风权限';
}

class RtcJoinFailure implements Exception {
  const RtcJoinFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

class RtcOperationCancelled implements Exception {
  const RtcOperationCancelled();

  @override
  String toString() => 'RTC 操作已取消';
}

typedef AgoraDriverFactory = AgoraRtcDriver Function();
typedef RtcPermissionRequester = Future<bool> Function(bool video);

abstract interface class AgoraRtcDriver {
  RtcEngine? get nativeEngine;
  Future<void> initialize(String appId);
  Future<void> enableAudio();
  Future<void> enableVideo();
  Future<void> disableVideo();
  Future<void> setSpeakerphoneEnabled();
  void registerCallbacks(RtcCallbacks callbacks);
  Future<void> joinChannel(RtcCredentials credentials);
  Future<void> renewToken(String token);
  Future<void> setMicrophoneMuted(bool muted);
  Future<void> leaveChannel();
  Future<void> release();
}

class AgoraWearRtcEngine implements WearRtcEngine {
  AgoraWearRtcEngine({
    AgoraDriverFactory? driverFactory,
    RtcPermissionRequester? requestPermissions,
  }) : _driverFactory = driverFactory ?? SdkAgoraRtcDriver.new,
       _requestPermissions = requestPermissions ?? _requestSdkPermissions;

  final AgoraDriverFactory _driverFactory;
  final RtcPermissionRequester _requestPermissions;
  final Map<AgoraRtcDriver, Future<void>> _closing = {};
  final Set<AgoraRtcDriver> _closed = {};
  AgoraRtcDriver? _driver;
  int _generation = 0;
  bool _disposed = false;

  RtcEngine? get nativeEngine => _driver?.nativeEngine;

  @override
  Future<void> join(RtcCredentials credentials, RtcCallbacks callbacks) async {
    if (_disposed) throw const RtcOperationCancelled();
    if (credentials.demo) {
      throw const RtcJoinFailure('演示凭证不能初始化 RTC 引擎');
    }
    if (!credentials.isUsable || credentials.isExpired) {
      throw const RtcJoinFailure('通话凭证无效或已过期');
    }

    final operation = ++_generation;
    final previous = _driver;
    _driver = null;
    if (previous != null) {
      await _close(previous);
      await _requireCurrent(operation);
    }

    final granted = await _requestPermissions(credentials.video);
    await _requireCurrent(operation);
    if (!granted) throw RtcPermissionDenied(video: credentials.video);

    final driver = _driverFactory();
    if (!_accepts(operation)) {
      await _close(driver);
      throw const RtcOperationCancelled();
    }
    _driver = driver;
    final guardedCallbacks = RtcCallbacks(
      onLocalJoined: () {
        if (_acceptsDriver(operation, driver)) callbacks.onLocalJoined();
      },
      onRemoteJoined: (uid) {
        if (_acceptsDriver(operation, driver)) callbacks.onRemoteJoined(uid);
      },
      onRemoteLeft: (uid) {
        if (_acceptsDriver(operation, driver)) callbacks.onRemoteLeft(uid);
      },
      onTokenExpiring: () {
        if (_acceptsDriver(operation, driver)) callbacks.onTokenExpiring();
      },
      onFailure: (message) {
        if (_acceptsDriver(operation, driver)) callbacks.onFailure(message);
      },
    );

    try {
      await driver.initialize(credentials.appId);
      await _requireCurrent(operation, driver);
      await driver.enableAudio();
      await _requireCurrent(operation, driver);
      if (credentials.video) {
        await driver.enableVideo();
      } else {
        await driver.disableVideo();
      }
      await _requireCurrent(operation, driver);
      await driver.setSpeakerphoneEnabled();
      await _requireCurrent(operation, driver);
      driver.registerCallbacks(guardedCallbacks);
      if (!_acceptsDriver(operation, driver)) {
        await _closeAndDetach(driver);
        throw const RtcOperationCancelled();
      }
      await driver.joinChannel(credentials);
      await _requireCurrent(operation, driver);
    } catch (error) {
      await _closeAndDetach(driver);
      if (!_accepts(operation) && error is! RtcOperationCancelled) {
        throw const RtcOperationCancelled();
      }
      rethrow;
    }
  }

  @override
  Future<void> renewToken(String token) async {
    final driver = _driver;
    final operation = _generation;
    if (_disposed || token.isEmpty || driver == null) {
      throw const RtcJoinFailure('无法更新已过期的通话凭证');
    }
    await driver.renewToken(token);
    await _requireCurrent(operation, driver);
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    final driver = _driver;
    final operation = _generation;
    if (_disposed || driver == null) throw const RtcOperationCancelled();
    await driver.setMicrophoneMuted(muted);
    await _requireCurrent(operation, driver);
  }

  @override
  Future<void> leave() async {
    ++_generation;
    final driver = _driver;
    _driver = null;
    if (driver != null) await _close(driver);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    final driver = _driver;
    _driver = null;
    if (driver != null) await _close(driver);
  }

  bool _accepts(int operation) => !_disposed && operation == _generation;

  bool _acceptsDriver(int operation, AgoraRtcDriver driver) =>
      _accepts(operation) && identical(_driver, driver);

  Future<void> _requireCurrent(int operation, [AgoraRtcDriver? driver]) async {
    final valid = driver == null
        ? _accepts(operation)
        : _acceptsDriver(operation, driver);
    if (valid) return;
    if (driver != null) await _closeAndDetach(driver);
    throw const RtcOperationCancelled();
  }

  Future<void> _closeAndDetach(AgoraRtcDriver driver) async {
    if (identical(_driver, driver)) _driver = null;
    await _close(driver);
  }

  Future<void> _close(AgoraRtcDriver driver) {
    if (_closed.contains(driver)) return Future<void>.value();
    final existing = _closing[driver];
    if (existing != null) return existing;
    final future = _closeOnce(driver);
    _closing[driver] = future;
    return future.whenComplete(() => _closing.remove(driver));
  }

  Future<void> _closeOnce(AgoraRtcDriver driver) async {
    try {
      await driver.leaveChannel();
    } finally {
      try {
        await driver.release();
      } finally {
        _closed.add(driver);
      }
    }
  }

  static Future<bool> _requestSdkPermissions(bool video) async {
    final permissions = <Permission>[Permission.microphone];
    if (video) permissions.add(Permission.camera);
    final results = await permissions.request();
    return results.values.every((status) => status.isGranted);
  }
}

class SdkAgoraRtcDriver implements AgoraRtcDriver {
  SdkAgoraRtcDriver() : _engine = createAgoraRtcEngine();

  final RtcEngine _engine;

  @override
  RtcEngine get nativeEngine => _engine;

  @override
  Future<void> initialize(String appId) =>
      _engine.initialize(RtcEngineContext(appId: appId));

  @override
  Future<void> enableAudio() => _engine.enableAudio();

  @override
  Future<void> enableVideo() => _engine.enableVideo();

  @override
  Future<void> disableVideo() => _engine.disableVideo();

  @override
  Future<void> setSpeakerphoneEnabled() =>
      _engine.setDefaultAudioRouteToSpeakerphone(true);

  @override
  void registerCallbacks(RtcCallbacks callbacks) {
    _engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (_, _) => callbacks.onLocalJoined(),
        onUserJoined: (_, uid, _) => callbacks.onRemoteJoined(uid),
        onUserOffline: (_, uid, _) => callbacks.onRemoteLeft(uid),
        onTokenPrivilegeWillExpire: (_, _) => callbacks.onTokenExpiring(),
        onRequestToken: (_) => callbacks.onTokenExpiring(),
        onConnectionLost: (_) => callbacks.onFailure('RTC 连接已断开'),
        onError: (code, message) =>
            callbacks.onFailure(message.isNotEmpty ? message : 'RTC 错误：$code'),
        onConnectionStateChanged: (_, state, reason) {
          if (state == ConnectionStateType.connectionStateFailed) {
            callbacks.onFailure('RTC 连接失败：$reason');
          }
        },
      ),
    );
  }

  @override
  Future<void> joinChannel(RtcCredentials credentials) => _engine.joinChannel(
    token: credentials.token,
    channelId: credentials.channelName,
    uid: credentials.uid,
    options: ChannelMediaOptions(
      clientRoleType: ClientRoleType.clientRoleBroadcaster,
      channelProfile: ChannelProfileType.channelProfileCommunication,
      publishMicrophoneTrack: true,
      publishCameraTrack: credentials.video,
      autoSubscribeAudio: true,
      autoSubscribeVideo: credentials.video,
    ),
  );

  @override
  Future<void> renewToken(String token) => _engine.renewToken(token);

  @override
  Future<void> setMicrophoneMuted(bool muted) =>
      _engine.muteLocalAudioStream(muted);

  @override
  Future<void> leaveChannel() => _engine.leaveChannel();

  @override
  Future<void> release() => _engine.release();
}
