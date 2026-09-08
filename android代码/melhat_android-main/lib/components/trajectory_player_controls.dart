import 'field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../controllers/trajectory_player_controller.dart';

/// 普通地图和全屏地图共享同一个播放器状态。
class TrajectoryPlayerControls extends HookWidget {
  final TrajectoryPlayerController controller;
  final bool showSpeedButton;
  final bool showTimeLabels;
  final VoidCallback? onFullScreen;
  final bool isFullScreen;

  const TrajectoryPlayerControls({
    super.key,
    required this.controller,
    this.showSpeedButton = true,
    this.showTimeLabels = true,
    this.onFullScreen,
    this.isFullScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    final colors = Theme.of(context).colorScheme;
    final hasPoints = controller.totalCount > 0;
    final maxIndex = controller.totalCount > 1 ? controller.totalCount - 1 : 1;
    final current = controller.currentIndex.clamp(0, maxIndex).toDouble();
    return MotionReveal(
      child: Material(
        color: colors.surface.withValues(alpha: isFullScreen ? .96 : 1),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      controller.currentTimestamp ?? '等待轨迹数据',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (showSpeedButton)
                    TextButton.icon(
                      onPressed: hasPoints ? controller.toggleSpeed : null,
                      icon: const Icon(Icons.speed, size: 18),
                      label: Text('${controller.speed.label}x'),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.onSurface,
                      ),
                    ),
                  if (onFullScreen != null)
                    IconButton(
                      tooltip: isFullScreen ? '退出全屏' : '全屏回放',
                      onPressed: onFullScreen,
                      icon: Icon(
                        isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      ),
                    ),
                ],
              ),
              Slider(
                value: current,
                min: 0,
                max: maxIndex.toDouble(),
                semanticFormatterCallback: (value) => controller.points.isEmpty
                    ? '暂无轨迹'
                    : controller
                          .points[value.toInt().clamp(
                            0,
                            controller.totalCount - 1,
                          )]
                          .timestamp,
                onChanged: controller.totalCount > 1
                    ? (value) => controller.seekTo(value.toInt())
                    : null,
              ),
              if (showTimeLabels)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _label(controller.startTimestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _label(controller.endTimestamp),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '上一个轨迹点',
                    onPressed: hasPoints ? controller.stepBackward : null,
                    icon: const Icon(Icons.skip_previous_outlined),
                  ),
                  const SizedBox(width: 16),
                  MotionPress(
                    enabled: hasPoints,
                    child: IconButton.filled(
                      tooltip: controller.isPlaying ? '暂停回放' : '开始回放',
                      onPressed: hasPoints ? controller.togglePlay : null,
                      icon: MotionSwap(
                        value: '${controller.isPlaying}',
                        child: Icon(
                          controller.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    tooltip: '下一个轨迹点',
                    onPressed: hasPoints ? controller.stepForward : null,
                    icon: const Icon(Icons.skip_next_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _label(String? value) => value == null
      ? '--'
      : value.length >= 16
      ? value.substring(5, 16)
      : value;
}
