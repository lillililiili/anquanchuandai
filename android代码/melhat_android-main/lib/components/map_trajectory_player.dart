import 'field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:latlong2/latlong.dart';
import '../../models/hat_location_record.dart';
import '../../models/trajectory_point.dart';
import '../../theme/theme.dart';
import '../../hooks/use_theme.dart';
import '../../controllers/trajectory_player_controller.dart';
import 'trajectory_map_view.dart';
import 'app_map.dart';
import 'trajectory_player_controls.dart';

/// 全屏轨迹回放组件
///
/// 全屏横屏展示，用于在地图上回放轨迹
/// [visible] 是否显示
/// [onClose] 关闭回调
/// [trajectoryData] 轨迹数据
/// [controller] 轨迹播放器控制器
class MapTrajectoryPlayer extends HookWidget {
  final bool visible;
  final VoidCallback? onClose;
  final List<HatLocationRecord>? trajectoryData;
  final TrajectoryPlayerController? controller;

  const MapTrajectoryPlayer({
    super.key,
    this.visible = false,
    this.onClose,
    this.trajectoryData,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();

    // 将轨迹数据转换为 TrajectoryPoint
    final points = useMemoized(() {
      if (trajectoryData == null) return <TrajectoryPoint>[];
      return TrajectoryPoint.fromList(trajectoryData!);
    }, [trajectoryData]);

    // 监听控制器变化以触发重建
    useListenable(controller);

    // 获取控制器当前索引
    final currentIndex = controller?.currentIndex ?? 0;

    // 仅在全屏期间持有横屏；隐藏与卸载都会执行清理。
    useEffect(() {
      if (!visible) return null;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return () {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      };
    }, [visible]);
    final layers = useTrajectoryLayers(
      points: points,
      currentIndex: currentIndex,
    );

    if (!visible) {
      return const SizedBox.shrink();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) onClose?.call();
      },
      child: Material(
        color: theme.background,
        child: SafeArea(
          child: Stack(
            children: [
              // 地图区域（使用 AppMap）
              AppMap(
                initialCenter: points.isNotEmpty
                    ? LatLng(points.first.latitude, points.first.longitude)
                    : null,
                initialZoom: 15.0,
                children: layers,
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton.filledTonal(
                  tooltip: '退出全屏',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
              // 底部控制按钮
              if (controller != null)
                Positioned(
                  bottom: AppSpacing.lg,
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  child: MotionEntrance(
                    child: TrajectoryPlayerControls(
                      controller: controller!,
                      isFullScreen: true,
                      onFullScreen: onClose,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
