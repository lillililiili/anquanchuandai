import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rolling_intelligence_headband/models/agora_credentials.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';

/// 远端用户信息
class RemoteUser {
  final int uid;
  final bool hasVideo;
  final bool audioMuted;

  RemoteUser({
    required this.uid,
    this.hasVideo = false,
    this.audioMuted = false,
  });
}

/// Agora RTC Hook 返回值
class AgoraRtcState {
  final RtcEngine? engine;
  final bool joined;
  final String status;
  final Map<int, RemoteUser> remoteUsers;
  final Future<void> Function(AgoraCredentials) joinChannel;
  final Future<void> Function() leaveChannel;
  final Future<void> Function() toggleMic;
  final Future<void> Function(int) toggleRemoteMute;
  final bool micMuted;

  AgoraRtcState({
    this.engine,
    required this.joined,
    required this.status,
    required this.remoteUsers,
    required this.joinChannel,
    required this.leaveChannel,
    required this.toggleMic,
    required this.toggleRemoteMute,
    required this.micMuted,
  });
}

/// Agora RTC Engine Hook
///
/// 管理 RtcEngine 的初始化、频道加入/离开、远端用户状态等
AgoraRtcState useAgoraRtcEngine() {
  final engine = useState<RtcEngine?>(null);
  final joined = useState(false);
  final status = useState('未连接');
  final remoteUsers = useState<Map<int, RemoteUser>>({});
  final micMuted = useState(false);
  final currentCredentials = useState<AgoraCredentials?>(null);

  final context = useContext();

  // 组件卸载时释放引擎
  useEffect(() {
    return () {
      final currentEngine = engine.value;
      if (currentEngine != null) {
        // 同步清理：fire-and-forget 释放引擎
        unawaited(Future.wait([
          currentEngine.leaveChannel(),
          currentEngine.release(),
        ]));
      }
    };
  }, []);

  // 加入频道（同时初始化引擎）
  Future<void> joinChannel(AgoraCredentials credentials) async {
    if (!context.mounted) return;

    // 先离开当前频道并释放旧引擎
    if (engine.value != null) {
      try {
        await engine.value!.leaveChannel();
        await engine.value!.release();
      } catch (e) {
        // 忽略释放时的错误
      }
      if (!context.mounted) return;
      engine.value = null;
      joined.value = false;
      remoteUsers.value = <int, RemoteUser>{};
    }

    if (!context.mounted) return;

    currentCredentials.value = credentials;
    status.value = '正在初始化引擎...';

    try {
      // 请求权限
      await [Permission.microphone, Permission.camera].request();

      if (!context.mounted) return;

      // 创建并初始化引擎
      final newEngine = createAgoraRtcEngine();
      await newEngine.initialize(
        RtcEngineContext(appId: credentials.agoraAppId),
      );

      if (!context.mounted) return;

      await newEngine.enableAudio();
      await newEngine.enableVideo();
      await newEngine.setDefaultAudioRouteToSpeakerphone(true);

      // 注册事件处理器
      newEngine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            if (!context.mounted) return;
            joined.value = true;
            status.value = '已加入频道';
          },
          onUserJoined: (connection, uid, elapsed) {
            if (!context.mounted) return;
            final newUsers = Map<int, RemoteUser>.from(remoteUsers.value);
            newUsers[uid] = RemoteUser(uid: uid);
            remoteUsers.value = newUsers;
            status.value = '设备已接入';
          },
          onUserOffline: (connection, uid, reason) {
            if (!context.mounted) return;
            final newUsers = Map<int, RemoteUser>.from(remoteUsers.value);
            newUsers.remove(uid);
            remoteUsers.value = newUsers;
            if (newUsers.isEmpty) {
              status.value = '等待设备接入...';
            }
          },
          onRemoteVideoStateChanged: (connection, uid, state, reason, elapsed) {
            if (!context.mounted) return;
            if (remoteUsers.value.containsKey(uid)) {
              final newUsers = Map<int, RemoteUser>.from(remoteUsers.value);
              newUsers[uid] = RemoteUser(
                uid: uid,
                hasVideo: state == RemoteVideoState.remoteVideoStateDecoding,
                audioMuted: newUsers[uid]!.audioMuted,
              );
              remoteUsers.value = newUsers;
            }
          },
          onError: (err, msg) {
            if (!context.mounted) return;
            status.value = '错误: $err';
            AppLogger.e('Agora 错误: $err, $msg');
          },
          onConnectionStateChanged: (connection, state, reason) {
            if (!context.mounted) return;
            if (state == ConnectionStateType.connectionStateFailed) {
              status.value = '连接失败';
            }
          },
        ),
      );

      if (!context.mounted) {
        // 如果组件已卸载，释放刚创建的引擎
        await newEngine.release();
        return;
      }

      engine.value = newEngine;
      status.value = '正在加入频道...';

      // 加入频道
      await newEngine.joinChannel(
        token: credentials.agoraToken ?? '',
        channelId: credentials.channelName,
        uid: credentials.agoraUid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileCommunication,
          publishMicrophoneTrack: false,
          publishCameraTrack: false,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
    } on AgoraRtcException catch (e) {
      if (!context.mounted) return;
      status.value = '加入失败: ${e.message}';
      AppLogger.e('Agora 错误码: ${e.code}, 信息: ${e.message}');
    } catch (e) {
      if (!context.mounted) return;
      status.value = '加入失败: $e';
      AppLogger.e('其他错误: $e');
    }
  }

  // 离开频道
  Future<void> leaveChannel() async {
    if (!context.mounted) return;

    final currentEngine = engine.value;
    if (currentEngine != null) {
      try {
        await currentEngine.leaveChannel();
        await currentEngine.release();
      } catch (e) {
        // 忽略释放时的错误
      }
    }

    if (!context.mounted) return;

    engine.value = null;
    joined.value = false;
    remoteUsers.value = <int, RemoteUser>{};
    currentCredentials.value = null;
    status.value = '已离开频道';
  }

  // 切换本地麦克风
  Future<void> toggleMic() async {
    if (!context.mounted || engine.value == null) return;
    final newMuted = !micMuted.value;
    micMuted.value = newMuted;
    await engine.value?.muteLocalAudioStream(newMuted);
  }

  // 切换远端音频静音
  Future<void> toggleRemoteMute(int uid) async {
    if (!context.mounted || engine.value == null) return;

    final user = remoteUsers.value[uid];
    if (user == null) return;

    final newMuted = !user.audioMuted;
    await engine.value?.muteRemoteAudioStream(uid: uid, mute: newMuted);

    if (!context.mounted) return;

    final newUsers = Map<int, RemoteUser>.from(remoteUsers.value);
    newUsers[uid] = RemoteUser(
      uid: uid,
      hasVideo: user.hasVideo,
      audioMuted: newMuted,
    );
    remoteUsers.value = newUsers;
  }

  return AgoraRtcState(
    engine: engine.value,
    joined: joined.value,
    status: status.value,
    remoteUsers: remoteUsers.value,
    joinChannel: joinChannel,
    leaveChannel: leaveChannel,
    toggleMic: toggleMic,
    toggleRemoteMute: toggleRemoteMute,
    micMuted: micMuted.value,
  );
}
