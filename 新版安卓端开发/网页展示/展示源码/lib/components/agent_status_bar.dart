import 'field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/models/chat_models.dart';
import 'package:rolling_intelligence_headband/theme/app_colors.dart';

/// Agent 状态栏组件
///
/// 显示 AI 执行状态，包括思考中、执行工具、导航等
class AgentStatusBar extends HookWidget {
  final AgentStatus status;
  final AgentStep? step;
  final String? toolName;

  const AgentStatusBar({
    super.key,
    required this.status,
    this.step,
    this.toolName,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 空闲状态不显示
    if (status == AgentStatus.idle) {
      return const SizedBox.shrink();
    }

    // 获取状态信息
    final (icon, text, color) = _getStatusInfo(isDark);

    return AnimatedSize(
      duration: MotionPolicy.duration(context, 200),
      curve: Curves.easeInOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border(
            bottom: BorderSide(color: color.withValues(alpha: 0.2), width: 1),
          ),
        ),
        child: Row(
          children: [
            // 状态图标（带脉冲动画）
            if (status == AgentStatus.loading && !MotionPolicy.reduced(context))
              _AnimatedIcon(icon: icon, color: color)
            else
              Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            // 状态文本
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 获取状态信息
  (IconData, String, Color) _getStatusInfo(bool isDark) {
    final primaryColor = isDark ? SpringColors.mintGreen : SpringColors.skyBlue;

    return switch (status) {
      AgentStatus.loading => _getLoadingInfo(primaryColor),
      AgentStatus.success => (
        Icons.check_circle_outline,
        '完成',
        SpringColors.mintGreen,
      ),
      AgentStatus.error => (Icons.error_outline, '出错了', SpringColors.cherryRed),
      _ => (Icons.info_outline, '', primaryColor),
    };
  }

  /// 获取加载状态信息
  (IconData, String, Color) _getLoadingInfo(Color defaultColor) {
    return switch (step) {
      AgentStep.thinking => (Icons.psychology, '思考中...', defaultColor),
      AgentStep.navigating => (Icons.navigation, '导航中...', defaultColor),
      AgentStep.waitingPage => (
        Icons.hourglass_empty,
        '等待页面加载...',
        defaultColor,
      ),
      AgentStep.executingTool => (
        Icons.build_circle,
        '执行：${toolName ?? '工具'}',
        SpringColors.sproutYellow,
      ),
      AgentStep.rendering => (Icons.edit_note, '生成回复...', defaultColor),
      _ => (Icons.sync, '处理中...', defaultColor),
    };
  }
}

/// 带脉冲动画的图标
class _AnimatedIcon extends HookWidget {
  final IconData icon;
  final Color color;

  const _AnimatedIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final animationController = useAnimationController(
      duration: const Duration(milliseconds: 1500),
    );

    useEffect(() {
      animationController.repeat(reverse: true);
      return null;
    }, []);

    return AnimatedBuilder(
      animation: animationController,
      builder: (context, child) {
        return Opacity(
          opacity: 0.5 + (animationController.value * 0.5),
          child: child,
        );
      },
      child: Icon(icon, size: 16, color: color),
    );
  }
}
