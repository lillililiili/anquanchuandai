import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:latlong2/latlong.dart';
import '../models/trajectory_point.dart';
import '../theme/theme.dart';

/// 轨迹图层 Hook
///
/// 返回轨迹相关的地图图层列表，可直接展开到 FlutterMap.children 中
///
/// 使用示例:
/// ```dart
/// FlutterMap(
///   children: [
///     TileLayer(...),
///     ...useTrajectoryLayers(
///       points: points,
///       currentIndex: currentIndex,
///     ),
///   ],
/// )
/// ```
List<Widget> useTrajectoryLayers({
  required List<TrajectoryPoint> points,
  required int currentIndex,
  bool showPastPoints = true,
  bool showFullPath = true,
  bool showCurrentPoint = true,
}) {
  // 转换轨迹点为 LatLng（使用 useMemoized 缓存）
  final latLngPoints = useMemoized(() {
    return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
  }, [points]);

  // 计算已播放的点
  final pastPoints = useMemoized(() {
    if (currentIndex < 0) return <LatLng>[];
    return latLngPoints.take(currentIndex + 1).toList();
  }, [latLngPoints, currentIndex]);

  // 当前点
  final currentPoint = useMemoized(() {
    if (currentIndex < 0 || currentIndex >= latLngPoints.length) return null;
    return latLngPoints[currentIndex];
  }, [latLngPoints, currentIndex]);

  // 返回图层列表
  return [
    // 完整路径线
    if (showFullPath && latLngPoints.length >= 2)
      PolylineLayer(
        polylines: [
          Polyline(
            points: latLngPoints,
            color: SpringColors.alarmLowBattery.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ],
      ),

    // 已播放路径线
    if (pastPoints.length >= 2)
      PolylineLayer(
        polylines: [
          Polyline(
            points: pastPoints,
            color: SpringColors.mintGreen.withValues(alpha: 0.7),
            strokeWidth: 3,
          ),
        ],
      ),

    // 过去点位
    if (showPastPoints && pastPoints.length > 1)
      MarkerLayer(
        markers: pastPoints.take(pastPoints.length - 1).map((point) {
          return Marker(
            point: point,
            width: 14,
            height: 14,
            child: Container(
              decoration: BoxDecoration(
                color: SpringColors.skyBlue.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          );
        }).toList(),
      ),

    // 当前点
    if (showCurrentPoint && currentPoint != null)
      MarkerLayer(
        markers: [
          Marker(
            point: currentPoint,
            width: 15,
            height: 15,
            child: _buildCurrentPointMarker(),
          ),
        ],
      ),
  ];
}

/// 构建当前点标记（带脉冲效果）
Widget _buildCurrentPointMarker() {
  return Container(
    decoration: BoxDecoration(
      color: SpringColors.sproutYellowDark.withValues(alpha: 0.8),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
    ),
  );
}
