import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:video_player/video_player.dart';

import '../../hooks/use_theme.dart';
import '../../theme/theme.dart';

/// 视频播放页面
///
/// 参数:
/// - [url]: 视频 URL
/// - [title]: 页面标题
class VideoPlayerView extends HookWidget {
  final String url;
  final String title;

  const VideoPlayerView({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final isFullScreen = useState(false);
    final chewieController = useState<ChewieController?>(null);
    final videoPlayerController = useState<VideoPlayerController?>(null);
    final isInitialized = useState(false);
    final hasError = useState<String?>(null);

    // 初始化视频控制器
    final playerContext = useContext();
    useEffect(() {
      VoidCallback listener = () {};
      void initializeVideo() async {
        try {
          final vpc = VideoPlayerController.networkUrl(Uri.parse(url));
          videoPlayerController.value = vpc;

          await vpc.initialize();

          if (!playerContext.mounted) return;

          final cc = ChewieController(
            videoPlayerController: vpc,
            autoPlay: true,
            looping: false,
            aspectRatio: vpc.value.aspectRatio,
            showControls: true,
            showControlsOnInitialize: false,
            allowFullScreen: true,
            allowMuting: true,
            allowPlaybackSpeedChanging: true,
            placeholder: Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(SpringColors.mintGreen),
                ),
              ),
            ),
            materialProgressColors: ChewieProgressColors(
              playedColor: SpringColors.mintGreen,
              handleColor: SpringColors.mintGreen,
              bufferedColor: Colors.white.withValues(alpha: 0.3),
              backgroundColor: Colors.white.withValues(alpha: 0.2),
            ),
            errorBuilder: (context, errorMessage) {
              return _buildErrorWidget(theme, errorMessage);
            },
          );

          chewieController.value = cc;
          isInitialized.value = true;

          // 监听全屏状态变化
          listener = () {
            if (!playerContext.mounted) return;
            final isNowFullScreen = cc.isFullScreen;
            if (isFullScreen.value != isNowFullScreen) {
              isFullScreen.value = isNowFullScreen;
              if (isNowFullScreen) {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              } else {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.portraitUp,
                  DeviceOrientation.portraitDown,
                ]);
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              }
            }
          };
          cc.addListener(listener);
        } catch (e) {
          if (!playerContext.mounted) return;
          hasError.value = '视频加载失败: $e';
        }
      }

      initializeVideo();

      return () {
        // 清理资源
        chewieController.value?.removeListener(listener);
        chewieController.value?.dispose();
        videoPlayerController.value?.dispose();
        // 恢复默认方向
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      };
    }, [url]);

    // 手动切换屏幕方向
    void toggleOrientation() {
      if (isFullScreen.value) {
        // 当前是横屏，切换回竖屏
        chewieController.value?.exitFullScreen();
      } else {
        // 当前是竖屏，切换为横屏
        chewieController.value?.enterFullScreen();
      }
    }

    return PopScope(
      canPop: !isFullScreen.value,
      onPopInvokedWithResult: (didPop, result) {
        if (isFullScreen.value) {
          // 如果处于全屏，先退出全屏
          chewieController.value?.toggleFullScreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: isFullScreen.value
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                leading: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    margin: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: SpringColors.mintGreen.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: SpringColors.mintGreen,
                    ),
                  ),
                ),
                title: Text(
                  title,
                  style: AppTypography.headlineMedium.copyWith(
                    color: Colors.white,
                  ),
                ),
                centerTitle: true,
                actions: [
                  // 手动切换横屏按钮
                  GestureDetector(
                    onTap: toggleOrientation,
                    child: Container(
                      margin: const EdgeInsets.only(right: AppSpacing.md),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: SpringColors.skyBlue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                      ),
                      child: Icon(
                        isFullScreen.value
                            ? Icons.screen_rotation
                            : Icons.screen_lock_landscape,
                        size: 20,
                        color: SpringColors.skyBlue,
                      ),
                    ),
                  ),
                ],
              ),
        body: hasError.value != null
            ? _buildErrorWidget(theme, hasError.value!)
            : !isInitialized.value
                ? _buildLoadingWidget()
                : Center(
                    child: AspectRatio(
                      aspectRatio: videoPlayerController.value!.value.aspectRatio,
                      child: Chewie(controller: chewieController.value!),
                    ),
                  ),
      ),
    );
  }

  /// 加载中视图
  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(SpringColors.mintGreen),
            ),
            SizedBox(height: AppSpacing.lg),
            Text(
              '视频加载中...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 错误视图
  Widget _buildErrorWidget(ThemeColors theme, String errorMessage) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: SpringColors.cherryRed.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                size: 32,
                color: SpringColors.cherryRed,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '播放失败',
              style: AppTypography.title.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              errorMessage,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () {
                // 重新加载
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: SpringColors.mintGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                ),
              ),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
