import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// 地图组件
///
/// 基于 flutter_map 封装，默认使用高德地图瓦片
///
/// [mapController] 地图控制器，用于外部控制地图
/// [initialCenter] 初始中心点
/// [initialZoom] 初始缩放级别
/// [interactionFlags] 交互标志，默认启用拖拽和缩放
/// [children] 自定义图层，会添加在 TileLayer 之后
Widget AppMap({
  MapController? mapController,
  LatLng? initialCenter,
  double? initialZoom,
  int? interactionFlags,
  VoidCallback? onMapReady,
  TileProvider? tileProvider,
  List<Widget> children = const [],
}) {
  return FlutterMap(
    mapController: mapController,
    options: MapOptions(
      onMapReady: onMapReady,
      initialCenter:
          initialCenter ?? const LatLng(37.2408718814842, 118.81377768291111),
      initialZoom: initialZoom ?? 15.0,
      interactionOptions: InteractionOptions(
        flags:
            interactionFlags ??
            InteractiveFlag.pinchZoom | InteractiveFlag.drag,
      ),
    ),
    children: [
      TileLayer(
        tileProvider: tileProvider,
        urlTemplate:
            'https://webst01.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
      ),
      ...children,
    ],
  );
}
