import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:latlong2/latlong.dart';
import '../controllers/trajectory_player_controller.dart';
import '../models/trajectory_point.dart';
import '../theme/theme.dart';
import '../hooks/use_theme.dart';
import 'trajectory_map_view.dart';
import 'app_map.dart';

/// 轨迹播放器视图组件
///
/// 集成 TrajectoryPlayerController，负责轨迹地图的显示和播放状态同步
///
/// 使用示例:
/// ```dart
/// // 方式 1：内部创建控制器
/// TrajectoryPlayerView(
///   points: points,
///   height: 200,
/// )
///
/// // 方式 2：使用外部控制器（与全屏组件共享状态）
/// final controller = useMemoized(() => TrajectoryPlayerController());
/// TrajectoryPlayerView(
///   points: points,
///   controller: controller,
///   height: 200,
/// )
/// ```
class TrajectoryPlayerView extends HookWidget {
  /// 轨迹点数据
  final List<TrajectoryPoint> points;

  /// 播放控制器（可选，不传则内部创建）
  final TrajectoryPlayerController? controller;

  /// 组件高度
  final double? height;

  /// 地图初始缩放级别
  final double initialZoom;

  /// 是否显示已播放点位
  final bool showPastPoints;

  /// 是否显示完整路径
  final bool showFullPath;

  /// 是否显示当前点
  final bool showCurrentPoint;

  /// 是否允许地图交互
  final bool interactive;

  /// 页面自带空态时保持底图实例，不因查询状态切换而取消瓦片请求。
  final bool showEmptyState;

  /// 当前点变化回调
  final ValueChanged<int>? onCurrentIndexChanged;

  const TrajectoryPlayerView({
    super.key,
    required this.points,
    this.controller,
    this.height,
    this.initialZoom = 15.0,
    this.showPastPoints = true,
    this.showFullPath = true,
    this.showCurrentPoint = true,
    this.interactive = true,
    this.showEmptyState = true,
    this.onCurrentIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();

    // 使用传入的 controller 或创建内部的
    final playerController = useMemoized(
      () => controller ?? TrajectoryPlayerController(),
      [controller],
    );

    // 外部控制器由查询发起方管理，视图重建不能重新 setPoints。
    useEffect(() {
      if (controller != null) return null;
      var active = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (active && context.mounted) playerController.setPoints(points);
      });
      return () => active = false;
    }, [playerController, points]);
    useEffect(() {
      return controller == null ? playerController.dispose : null;
    }, [playerController]);

    // 订阅控制器状态变化，并使用 useValueListenable 触发重建
    final _ = useListenable(playerController);
    final currentIndex = playerController.currentIndex;

    // 转换轨迹点为 LatLng
    final latLngPoints = useMemoized(() {
      return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    }, [points]);

    // 地图与请求提供者在查询前后保持同一实例。
    final mapController = useMemoized(() => MapController());
    final hideMap = points.isEmpty && showEmptyState;
    final tileProvider = useMemoized(
      () => hideMap ? null : NetworkTileProvider(),
      [hideMap],
    );
    final mapReady = useState(false);
    final fittedPoints = useRef<List<LatLng>?>(null);
    useEffect(() => mapController.dispose, [mapController]);
    useEffect(() {
      if (hideMap) {
        mapReady.value = false;
        fittedPoints.value = null;
      }
      return null;
    }, [hideMap]);

    // 只由一个 effect 调整相机：新轨迹适配一次，播放时保留用户缩放。
    // 等待 onMapReady，避免首帧 fit 后立刻 move 触发瓦片取消/重订阅。
    useEffect(() {
      if (!mapReady.value || latLngPoints.isEmpty) return null;
      var active = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!active || !context.mounted) return;
        if (!identical(fittedPoints.value, latLngPoints)) {
          mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(latLngPoints),
              padding: const EdgeInsets.all(50),
              maxZoom: initialZoom,
            ),
          );
          fittedPoints.value = latLngPoints;
        } else if (currentIndex >= 0 && currentIndex < latLngPoints.length) {
          mapController.move(
            latLngPoints[currentIndex],
            mapController.camera.zoom,
          );
        }
      });
      return () => active = false;
    }, [latLngPoints, currentIndex, mapReady.value, initialZoom]);

    final layers = useTrajectoryLayers(
      points: points,
      currentIndex: currentIndex,
      showPastPoints: showPastPoints,
      showFullPath: showFullPath,
      showCurrentPoint: showCurrentPoint,
    );

    if (hideMap) {
      return _buildEmptyState(theme);
    }

    return SizedBox(
      height: height ?? 200,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
        child: AppMap(
          mapController: mapController,
          tileProvider: tileProvider,
          onMapReady: () {
            if (context.mounted) mapReady.value = true;
          },
          initialCenter: latLngPoints.isNotEmpty
              ? latLngPoints.first
              : const LatLng(37.2408718814842, 118.81377768291111),
          initialZoom: initialZoom,
          interactionFlags: interactive
              ? InteractiveFlag.pinchZoom | InteractiveFlag.drag
              : InteractiveFlag.none,
          children: [
            // 轨迹图层
            ...layers,
          ],
        ),
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(ThemeColors theme) {
    return Container(
      height: height ?? 200,
      decoration: BoxDecoration(
        color: theme.isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
      ),
      child: const Center(
        child: Text(
          '暂无轨迹数据',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
      ),
    );
  }
}
