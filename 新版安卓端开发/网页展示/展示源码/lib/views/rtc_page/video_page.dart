import '../../components/field_motion.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../hooks/use_theme.dart';
import '../../models/agora_credentials.dart';
import '../../theme/theme.dart';
import '../../utils/app_logger.dart';

class VideoPage extends HookWidget {
  final AgoraCredentials credentials;

  const VideoPage({super.key, required this.credentials});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final engine = useState<RtcEngine?>(null);
    final joined = useState(false);
    final micMuted = useState(false);
    final status = useState('正在初始化...');
    final remoteUsers = useState<Map<int, _RemoteUser>>({});

    // 初始化引擎
    final videoContext = useContext();
    useEffect(() {
      Future<void> init() async {
        await [Permission.microphone].request();

        final newEngine = createAgoraRtcEngine();
        try {
          await newEngine.initialize(
            RtcEngineContext(appId: credentials.agoraAppId),
          );
        } on AgoraRtcException catch (e) {
          AppLogger.e('声网错误码: ${e.code}');
          AppLogger.e('声网错误信息: ${e.message}');
        } catch (e) {
          AppLogger.e('其他错误: $e');
        }

        await newEngine.enableAudio();
        await newEngine.enableVideo();
        await newEngine.setDefaultAudioRouteToSpeakerphone(true);

        newEngine.registerEventHandler(
          RtcEngineEventHandler(
            onJoinChannelSuccess: (connection, elapsed) {
              if (!videoContext.mounted) return;
              joined.value = true;
              status.value = '已加入频道：${credentials.channelName}';
            },
            onUserJoined: (connection, uid, elapsed) {
              if (!videoContext.mounted) return;
              final newUsers = Map<int, _RemoteUser>.from(remoteUsers.value);
              newUsers[uid] = _RemoteUser(uid: uid);
              remoteUsers.value = newUsers;
              status.value = '设备接入，等待推流...';
            },
            onUserOffline: (connection, uid, reason) {
              if (!videoContext.mounted) return;
              final newUsers = Map<int, _RemoteUser>.from(remoteUsers.value);
              newUsers.remove(uid);
              remoteUsers.value = newUsers;
            },
            onRemoteVideoStateChanged:
                (connection, uid, state, reason, elapsed) {
                  if (!videoContext.mounted) return;
                  if (remoteUsers.value.containsKey(uid)) {
                    final newUsers = Map<int, _RemoteUser>.from(
                      remoteUsers.value,
                    );
                    newUsers[uid] = _RemoteUser(
                      uid: uid,
                      hasVideo:
                          state == RemoteVideoState.remoteVideoStateDecoding,
                      audioMuted: newUsers[uid]!.audioMuted,
                    );
                    remoteUsers.value = newUsers;
                  }
                },
            onError: (err, msg) {
              if (!videoContext.mounted) return;
              status.value = '错误：$err';
            },
            onConnectionStateChanged: (connection, state, reason) {
              if (!videoContext.mounted) return;
              if (state == ConnectionStateType.connectionStateFailed) {
                status.value = '连接失败: $reason';
              }
            },
          ),
        );

        await newEngine.joinChannel(
          token: credentials.agoraToken ?? '',
          channelId: credentials.channelName,
          uid: credentials.agoraUid,
          options: const ChannelMediaOptions(
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
            channelProfile: ChannelProfileType.channelProfileCommunication,
            publishMicrophoneTrack: true,
            publishCameraTrack: false,
            autoSubscribeAudio: true,
            autoSubscribeVideo: true,
          ),
        );

        if (!videoContext.mounted) return;
        engine.value = newEngine;
        status.value = '正在加入频道...';
      }

      init();

      return () {
        unawaited(engine.value?.leaveChannel());
        unawaited(engine.value?.release());
      };
    }, []);

    // 切换麦克风
    Future<void> toggleMic() async {
      micMuted.value = !micMuted.value;
      await engine.value?.muteLocalAudioStream(micMuted.value);
    }

    // 切换远端音频静音
    Future<void> toggleRemoteMute(int uid) async {
      final user = remoteUsers.value[uid];
      if (user == null) return;

      final newMuted = !user.audioMuted;
      await engine.value?.muteRemoteAudioStream(uid: uid, mute: newMuted);

      final newUsers = Map<int, _RemoteUser>.from(remoteUsers.value);
      newUsers[uid] = _RemoteUser(
        uid: uid,
        hasVideo: user.hasVideo,
        audioMuted: newMuted,
      );
      remoteUsers.value = newUsers;
    }

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '实时监控',
          style: AppTypography.headlineMedium.copyWith(
            color: theme.textPrimary,
          ),
        ),
        actions: [
          // 本地麦克风开关
          _MicButton(
            joined: joined.value,
            micMuted: micMuted.value,
            onPressed: toggleMic,
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态栏
          MotionSwap(
            value: status.value,
            child: _StatusBar(status: status.value),
          ),

          // 视频网格
          Expanded(
            child: remoteUsers.value.isEmpty
                ? _EmptyState(theme: theme)
                : _VideoGrid(
                    engine: engine.value!,
                    remoteUsers: remoteUsers.value.values.toList(),
                    channelId: credentials.channelName,
                    onToggleMute: toggleRemoteMute,
                    theme: theme,
                  ),
          ),
        ],
      ),
    );
  }
}

// 远端用户信息
class _RemoteUser {
  final int uid;
  final bool hasVideo;
  final bool audioMuted;

  _RemoteUser({
    required this.uid,
    this.hasVideo = false,
    this.audioMuted = false,
  });
}

// 麦克风按钮
class _MicButton extends StatefulWidget {
  final bool joined;
  final bool micMuted;
  final VoidCallback onPressed;

  const _MicButton({
    required this.joined,
    required this.micMuted,
    required this.onPressed,
  });

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.joined
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.joined
          ? (_) {
              setState(() => _isPressed = false);
              widget.onPressed();
            }
          : null,
      onTapCancel: widget.joined
          ? () => setState(() => _isPressed = false)
          : null,
      child: AnimatedScale(
        scale: _isPressed && !MotionPolicy.reduced(context) ? .98 : 1.0,
        duration: MotionPolicy.duration(context, 120),
        child: Container(
          margin: const EdgeInsets.only(right: AppSpacing.md),
          width: AppSpacing.smallButtonSize,
          height: AppSpacing.smallButtonSize,
          decoration: BoxDecoration(
            color: widget.micMuted
                ? SpringColors.cherryRed.withAlpha(
                    (AppSpacing.iconBackgroundAlpha * 255).toInt(),
                  )
                : SpringColors.mintGreen.withAlpha(
                    (AppSpacing.iconBackgroundAlpha * 255).toInt(),
                  ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
          ),
          child: Icon(
            widget.micMuted ? Icons.mic_off : Icons.mic,
            color: widget.micMuted
                ? SpringColors.cherryRed
                : SpringColors.mintGreen,
            size: AppSpacing.smallButtonIconSize,
          ),
        ),
      ),
    );
  }
}

// 状态栏
class _StatusBar extends HookWidget {
  final String status;

  const _StatusBar({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();

    return Container(
      width: double.infinity,
      margin: AppSpacing.cardMargin,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        boxShadow: AppShadows.light,
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: status.contains('已加入')
                  ? SpringColors.mintGreen
                  : status.contains('错误') || status.contains('失败')
                  ? SpringColors.cherryRed
                  : SpringColors.sproutYellow,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              status,
              style: AppTypography.caption.copyWith(color: theme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// 空状态
class _EmptyState extends StatelessWidget {
  final ThemeColors theme;

  const _EmptyState({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: SpringColors.skyBlue.withAlpha(
                (AppSpacing.iconBackgroundAlpha * 255).toInt(),
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            ),
            child: Icon(
              Icons.videocam_outlined,
              size: 40,
              color: SpringColors.skyBlue,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '等待设备接入...',
            style: AppTypography.body.copyWith(color: theme.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '请确保设备已上线并开启视频推流',
            style: AppTypography.caption.copyWith(color: theme.textTertiary),
          ),
        ],
      ),
    );
  }
}

// 视频网格
class _VideoGrid extends StatelessWidget {
  final RtcEngine engine;
  final List<_RemoteUser> remoteUsers;
  final String channelId;
  final Function(int) onToggleMute;
  final ThemeColors theme;

  const _VideoGrid({
    required this.engine,
    required this.remoteUsers,
    required this.channelId,
    required this.onToggleMute,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: remoteUsers.length == 1 ? 1 : 2,
        childAspectRatio: 4 / 3,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      itemCount: remoteUsers.length,
      itemBuilder: (_, i) => _VideoCard(
        engine: engine,
        user: remoteUsers[i],
        channelId: channelId,
        onToggleMute: () => onToggleMute(remoteUsers[i].uid),
        theme: theme,
      ),
    );
  }
}

// 视频卡片
class _VideoCard extends StatefulWidget {
  final RtcEngine engine;
  final _RemoteUser user;
  final String channelId;
  final VoidCallback onToggleMute;
  final ThemeColors theme;

  const _VideoCard({
    required this.engine,
    required this.user,
    required this.channelId,
    required this.onToggleMute,
    required this.theme,
  });

  @override
  State<_VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<_VideoCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 远端视频或等待状态
          Positioned.fill(
            child: widget.user.hasVideo
                ? AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: widget.engine,
                      canvas: VideoCanvas(uid: widget.user.uid),
                      connection: RtcConnection(channelId: widget.channelId),
                    ),
                  )
                : Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_off_outlined,
                            size: 48,
                            color: widget.theme.textTertiary.withAlpha(128),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            '等待视频流...',
                            style: AppTypography.caption.copyWith(
                              color: widget.theme.textTertiary.withAlpha(128),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

          // UID 标签
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
              ),
              child: Text(
                'UID: ${widget.user.uid}',
                style: AppTypography.caption.copyWith(color: Colors.white),
              ),
            ),
          ),

          // 底部控制栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: MotionEntrance(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withAlpha(180)],
                  ),
                ),
                child: Row(
                  children: [
                    // 视频状态指示
                    Icon(
                      widget.user.hasVideo
                          ? Icons.videocam
                          : Icons.videocam_off,
                      color: widget.user.hasVideo
                          ? SpringColors.mintGreen
                          : SpringColors.cherryRed,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      widget.user.hasVideo ? '视频已连接' : '等待视频',
                      style: AppTypography.caption.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    // 远端音频静音按钮
                    GestureDetector(
                      onTapDown: (_) => setState(() => _isPressed = true),
                      onTapUp: (_) {
                        setState(() => _isPressed = false);
                        widget.onToggleMute();
                      },
                      onTapCancel: () => setState(() => _isPressed = false),
                      child: AnimatedScale(
                        scale: _isPressed && !MotionPolicy.reduced(context)
                            ? .98
                            : 1.0,
                        duration: MotionPolicy.duration(context, 120),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: widget.user.audioMuted
                                ? SpringColors.cherryRed.withAlpha(200)
                                : Colors.white.withAlpha(40),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSmall,
                            ),
                          ),
                          child: Icon(
                            widget.user.audioMuted
                                ? Icons.volume_off
                                : Icons.volume_up,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
