import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:latlong2/latlong.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../hooks/use_theme.dart';

/// 至少三个不同的有效坐标，并能形成非零面积区域。
bool isValidFenceArea(List<LatLng> points) {
  if (points.length < 3 ||
      points.any(
        (p) =>
            !p.latitude.isFinite ||
            !p.longitude.isFinite ||
            p.latitude < -90 ||
            p.latitude > 90 ||
            p.longitude < -180 ||
            p.longitude > 180,
      ))
    return false;
  final unique = points.map((p) => (p.latitude, p.longitude)).toSet();
  if (unique.length < 3) return false;
  final origin = points.first;
  var twiceArea = 0.0;
  for (var i = 0; i < points.length; i++) {
    final next = points[(i + 1) % points.length];
    twiceArea +=
        (points[i].longitude - origin.longitude) *
            (next.latitude - origin.latitude) -
        (next.longitude - origin.longitude) *
            (points[i].latitude - origin.latitude);
  }
  return twiceArea.abs() > 1e-12;
}

/// 电子围栏地图编辑器
///
/// 全屏横屏展示，用于在地图上绘制电子围栏
class MapFenceEditor extends HookWidget {
  /// 是否显示
  final bool visible;

  /// 关闭回调
  final VoidCallback? onClose;

  /// 初始点位（编辑模式）
  final List<LatLng>? initialPoints;

  /// 保存回调
  final void Function(List<LatLng>)? onSave;

  const MapFenceEditor({
    super.key,
    this.visible = false,
    this.onClose,
    this.initialPoints,
    this.onSave,
  });

  /// 过滤有效的点位
  List<LatLng> get _validInitialPoints {
    return initialPoints?.where((p) {
          return p.latitude >= -90 &&
              p.latitude <= 90 &&
              p.longitude >= -180 &&
              p.longitude <= 180;
        }).toList() ??
        [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final mapController = useMemoized(() => MapController());

    // 绘制状态
    final isDrawing = useState(false);
    final points = useState<List<LatLng>>(_validInitialPoints);

    useEffect(() {
      points.value = _validInitialPoints;
      return null;
    }, [initialPoints]);
    useEffect(() => mapController.dispose, [mapController]);

    // 收起地图保留尚未应用的草稿；重新打开不重置点位。
    useEffect(() {
      if (visible) {
        isDrawing.value = false;
        // 强制横屏
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        // 全屏模式
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        // 如果有初始点位，自动调整地图视图
        if (points.value.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              mapController.fitCamera(
                CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(points.value),
                  padding: const EdgeInsets.all(50),
                ),
              );
            } catch (_) {}
          });
        }
      }
      if (!visible) return null;
      return () {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      };
    }, [visible]);

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
          child: Column(
            children: [
              // 顶部工具栏
              _buildToolbar(context, theme, isDrawing, points),
              // 地图区域
              Expanded(
                child: Stack(
                  children: [
                    // 地图
                    FlutterMap(
                      mapController: mapController,
                      options: MapOptions(
                        initialCenter: const LatLng(
                          37.2408718814842,
                          118.81377768291111,
                        ),
                        initialZoom: 15.0,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        ),
                        onTap: (tapPosition, latLng) {
                          // 使用 MapOptions 的 onTap 回调，直接获取 LatLng
                          if (isDrawing.value) {
                            points.value = [...points.value, latLng];
                          }
                        },
                      ),
                      children: [
                        // 底图
                        TileLayer(
                          urlTemplate:
                              'https://webst01.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
                        ),
                        // 多边形填充（3个点以上）
                        if (points.value.length >= 3)
                          PolygonLayer(
                            polygons: [
                              Polygon(
                                points: points.value,
                                color: SpringColors.skyBlue.withValues(
                                  alpha: 0.25,
                                ),
                                borderColor: SpringColors.skyBlue,
                                borderStrokeWidth: 2,
                              ),
                            ],
                          ),
                        // 线段图层
                        if (points.value.length >= 2)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: points.value,
                                color: SpringColors.skyBlue,
                                strokeWidth: 3,
                              ),
                              // 闭合线（如果超过2个点）
                              if (points.value.length >= 3)
                                Polyline(
                                  points: [
                                    points.value.last,
                                    points.value.first,
                                  ],
                                  color: SpringColors.skyBlue.withValues(
                                    alpha: 0.5,
                                  ),
                                  strokeWidth: 2,
                                  pattern: StrokePattern.dashed(
                                    segments: [10.0, 10.0],
                                  ),
                                ),
                            ],
                          ),
                        // 点位标记
                        if (points.value.isNotEmpty)
                          MarkerLayer(
                            markers: points.value.asMap().entries.map((entry) {
                              final index = entry.key;
                              final point = entry.value;
                              return Marker(
                                point: point,
                                width: 28,
                                height: 28,
                                child: _buildPointMarker(
                                  context,
                                  index,
                                  points,
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                    // 绘制提示
                    if (isDrawing.value)
                      Positioned(
                        top: AppSpacing.md,
                        left: AppSpacing.lg,
                        child: _buildDrawingHint(theme),
                      ),
                    // 点位数量提示
                    if (points.value.isNotEmpty)
                      Positioned(
                        bottom: AppSpacing.lg,
                        right: AppSpacing.lg,
                        child: _buildPointsCountBadge(
                          theme,
                          points.value.length,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建顶部工具栏
  Widget _buildToolbar(
    BuildContext context,
    dynamic theme,
    ValueNotifier<bool> isDrawing,
    ValueNotifier<List<LatLng>> points,
  ) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // 退出按钮
            _buildToolButton(icon: Icons.close, label: '收起地图', onTap: onClose),
            const SizedBox(width: AppSpacing.md),
            // 开始/结束绘制按钮
            ValueListenableBuilder<bool>(
              valueListenable: isDrawing,
              builder: (context, drawing, _) {
                return _buildToolButton(
                  icon: drawing ? Icons.stop : Icons.edit_location_alt,
                  label: drawing ? '结束绘制' : '开始绘制',
                  onTap: () => isDrawing.value = !isDrawing.value,
                  isActive: drawing,
                );
              },
            ),
            const SizedBox(width: AppSpacing.lg),
            // 删除上一个点位
            ValueListenableBuilder<List<LatLng>>(
              valueListenable: points,
              builder: (context, pts, _) {
                return _buildToolButton(
                  icon: Icons.undo,
                  label: '撤销',
                  onTap: pts.isNotEmpty
                      ? () => points.value = pts.sublist(0, pts.length - 1)
                      : null,
                );
              },
            ),
            const SizedBox(width: AppSpacing.sm),
            // 清空按钮
            ValueListenableBuilder<List<LatLng>>(
              valueListenable: points,
              builder: (context, pts, _) {
                return _buildToolButton(
                  icon: Icons.delete_outline,
                  label: '清空',
                  onTap: pts.isNotEmpty ? () => points.value = [] : null,
                  isDestructive: true,
                );
              },
            ),
            const SizedBox(width: AppSpacing.lg),
            // 保存按钮
            ValueListenableBuilder<List<LatLng>>(
              valueListenable: points,
              builder: (context, pts, _) {
                return _buildToolButton(
                  icon: Icons.save,
                  label: '应用区域',
                  onTap: isValidFenceArea(pts)
                      ? () {
                          isDrawing.value = false;
                          onSave?.call(pts);
                        }
                      : null,
                  isPrimary: true,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建工具按钮
  Widget _buildToolButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    bool isActive = false,
    bool isPrimary = false,
    bool isDestructive = false,
  }) {
    Color bgColor;
    Color iconColor;
    Color textColor;

    if (isPrimary) {
      bgColor = SpringColors.skyBlue;
      iconColor = const Color(0xFF202B46);
      textColor = const Color(0xFF202B46);
    } else if (isDestructive) {
      bgColor = onTap != null
          ? SpringColors.cherryRed.withValues(alpha: 0.1)
          : Colors.grey.withValues(alpha: 0.1);
      iconColor = onTap != null
          ? SpringColors.cherryRed
          : Colors.grey.withValues(alpha: 0.5);
      textColor = iconColor;
    } else if (isActive) {
      bgColor = SpringColors.mintGreen;
      iconColor = const Color(0xFF202B46);
      textColor = const Color(0xFF202B46);
    } else {
      bgColor = onTap != null
          ? SpringColors.skyBlue.withValues(alpha: 0.1)
          : Colors.grey.withValues(alpha: 0.1);
      iconColor = onTap != null
          ? const Color(0xFF202B46)
          : Colors.grey.withValues(alpha: 0.5);
      textColor = iconColor;
    }

    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(
        icon,
        size: 18,
        color: onTap == null ? Colors.grey : iconColor,
      ),
      label: Text(
        label,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      style: TextButton.styleFrom(
        backgroundColor: bgColor,
        foregroundColor: textColor,
        disabledBackgroundColor: Colors.grey.withValues(alpha: .12),
        disabledForegroundColor: Colors.grey,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// 构建点位标记
  Widget _buildPointMarker(
    BuildContext context,
    int index,
    ValueNotifier<List<LatLng>> points,
  ) {
    return GestureDetector(
      onTap: () {
        // 点击删除该点
        _showDeletePointDialog(context, index, points);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: SpringColors.skyBlue, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF202B46),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建绘制提示
  Widget _buildDrawingHint(dynamic theme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.cardBackground.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.touch_app, size: 16, color: const Color(0xFF202B46)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '点击地图绘制区域 · 至少3个不同的点',
            style: TextStyle(fontSize: 13, color: theme.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 构建点位数量徽章
  Widget _buildPointsCountBadge(dynamic theme, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.cardBackground.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, size: 16, color: const Color(0xFF202B46)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '草稿 $count 个点 · 应用后返回表单',
            style: TextStyle(fontSize: 13, color: theme.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 显示删除点位对话框
  void _showDeletePointDialog(
    BuildContext context,
    int index,
    ValueNotifier<List<LatLng>> points,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除点位'),
        content: Text('确定要删除第 ${index + 1} 个点位吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final newPoints = [...points.value];
              newPoints.removeAt(index);
              points.value = newPoints;
              Navigator.pop(ctx);
            },
            child: const Text(
              '删除',
              style: TextStyle(color: SpringColors.cherryRed),
            ),
          ),
        ],
      ),
    );
  }
}
