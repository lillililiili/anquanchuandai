import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../theme/theme.dart';

/// Agent 状态徽章
/// 显示当前步骤、进度、状态
class AgentStatusBadge extends StatelessWidget {
  final AgentStep step;
  final AgentStatus status;
  final int? progress; // 0-100
  final String? error;
  final bool compact;

  const AgentStatusBadge({
    super.key,
    this.step = AgentStep.thinking,
    this.status = AgentStatus.idle,
    this.progress,
    this.error,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (status == AgentStatus.idle) {
      return const SizedBox.shrink();
    }

    if (compact) {
      return _buildCompactBadge(isDark);
    }

    return _buildFullBadge(isDark);
  }

  Widget _buildCompactBadge(bool isDark) {
    Color color;
    IconData icon;

    switch (status) {
      case AgentStatus.loading:
        color = SpringColors.skyBlue;
        icon = Icons.sync;
      case AgentStatus.success:
        color = SpringColors.mintGreen;
        icon = Icons.check_circle;
      case AgentStatus.error:
        color = SpringColors.cherryRed;
        icon = Icons.error;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == AgentStatus.loading)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            _getStepLabel(),
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildFullBadge(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getBorderColor(),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 步骤指示器
          Row(
            children: [
              _buildStepIcon(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getStepLabel(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _getTextColor(isDark),
                  ),
                ),
              ),
              if (status == AgentStatus.loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
                  ),
                ),
            ],
          ),
          // 进度条
          if (progress != null && status == AgentStatus.loading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress! / 100,
                  backgroundColor: _getStatusColor().withAlpha(20),
                  valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
                  minHeight: 6,
                ),
              ),
            ),
          // 错误提示
          if (error != null && status == AgentStatus.error)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: SpringColors.cherryRed,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      error!,
                      style: TextStyle(
                        fontSize: 12,
                        color: SpringColors.cherryRed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepIcon() {
    IconData icon;
    Color color = _getStatusColor();

    switch (step) {
      case AgentStep.thinking:
        icon = Icons.psychology;
      case AgentStep.navigating:
        icon = Icons.navigation;
      case AgentStep.waitingPage:
        icon = Icons.hourglass_empty;
      case AgentStep.executingTool:
        icon = Icons.build;
      case AgentStep.rendering:
        icon = Icons.palette;
    }

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }

  String _getStepLabel() {
    switch (step) {
      case AgentStep.thinking:
        return 'AI 思考中...';
      case AgentStep.navigating:
        return '正在导航...';
      case AgentStep.waitingPage:
        return '等待页面响应...';
      case AgentStep.executingTool:
        return progress != null ? '执行中 $progress%' : '执行工具...';
      case AgentStep.rendering:
        return '渲染结果...';
    }
  }

  Color _getStatusColor() {
    switch (status) {
      case AgentStatus.loading:
        return SpringColors.skyBlue;
      case AgentStatus.success:
        return SpringColors.mintGreen;
      case AgentStatus.error:
        return SpringColors.cherryRed;
      default:
        return Colors.grey;
    }
  }

  Color _getTextColor(bool isDark) {
    return isDark ? Colors.white : const Color(0xFF1F2937);
  }

  Color _getBorderColor() {
    switch (status) {
      case AgentStatus.loading:
        return SpringColors.skyBlue.withAlpha(50);
      case AgentStatus.success:
        return SpringColors.mintGreen.withAlpha(50);
      case AgentStatus.error:
        return SpringColors.cherryRed.withAlpha(50);
      default:
        return Colors.grey.withAlpha(30);
    }
  }
}

/// Agent 步骤时间线
/// 展示完整的执行流程：思考 → 导航 → 页面响应 → 完成
class AgentStepTimeline extends StatelessWidget {
  final AgentStep currentStep;
  final bool showProgress;

  const AgentStepTimeline({
    super.key,
    this.currentStep = AgentStep.thinking,
    this.showProgress = true,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      _StepItem(
        step: AgentStep.thinking,
        label: '思考',
        icon: Icons.psychology,
      ),
      _StepItem(
        step: AgentStep.navigating,
        label: '导航',
        icon: Icons.navigation,
      ),
      _StepItem(
        step: AgentStep.waitingPage,
        label: '等待',
        icon: Icons.hourglass_empty,
      ),
      _StepItem(
        step: AgentStep.executingTool,
        label: '执行',
        icon: Icons.build,
      ),
      _StepItem(
        step: AgentStep.rendering,
        label: '完成',
        icon: Icons.check_circle,
      ),
    ];

    final currentIndex = steps.indexWhere((s) => s.step == currentStep);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final index = entry.key;
          final step = entry.value;
          final isActive = index <= currentIndex;
          final isCurrent = index == currentIndex;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isActive
                              ? (isCurrent
                                  ? SpringColors.skyBlue
                                  : SpringColors.mintGreen)
                              : Colors.grey.withAlpha(30),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          step.icon,
                          size: 16,
                          color: isActive ? Colors.white : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: 11,
                          color: isActive
                              ? (isCurrent
                                  ? SpringColors.skyBlue
                                  : SpringColors.mintGreen)
                              : Colors.grey,
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 16),
                      color: index < currentIndex
                          ? SpringColors.mintGreen
                          : Colors.grey.withAlpha(30),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StepItem {
  final AgentStep step;
  final String label;
  final IconData icon;

  const _StepItem({
    required this.step,
    required this.label,
    required this.icon,
  });
}
