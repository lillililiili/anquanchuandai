import 'package:flutter/material.dart';
import 'field_motion.dart';

/// A single compact tool section complements bottom navigation.
class FieldToolsSection extends StatelessWidget {
  const FieldToolsSection({
    super.key,
    required this.onTrack,
    required this.onDevices,
    required this.onFence,
    required this.onMyHelmet,
    required this.onCheckIn,
    required this.onAiConfig,
  });

  final VoidCallback onTrack,
      onDevices,
      onFence,
      onMyHelmet,
      onCheckIn,
      onAiConfig;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tools = [
      _FieldTool(
        '人员轨迹',
        '查看人员历史轨迹',
        'track-tool',
        const Color(0xFFE9F5FF),
        Icons.route_outlined,
        onTrack,
      ),
      _FieldTool(
        '设备状态',
        '查看设备状态与电量',
        'device-tool',
        const Color(0xFFE9F5FF),
        Icons.construction_outlined,
        onDevices,
      ),
      _FieldTool(
        '电子围栏',
        '查看与管理电子围栏',
        'fence-tool',
        const Color(0xFFE9F5FF),
        Icons.shield_outlined,
        onFence,
      ),
      _FieldTool(
        '我的安全帽',
        '查看个人绑定设备',
        'helmet-tool',
        const Color(0xFFE8F9FC),
        Icons.construction_outlined,
        onMyHelmet,
      ),
      _FieldTool(
        '现场签到',
        '演示功能，不提交签到',
        'checkin-tool',
        const Color(0xFFF4F5FC),
        Icons.fact_check_outlined,
        onCheckIn,
        badge: '演示',
      ),
      _FieldTool(
        'AI 服务配置',
        '设置模型与连接参数',
        'ai-tool',
        const Color(0xFFEDF2FF),
        Icons.smart_toy_outlined,
        onAiConfig,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '现场工具',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final singleColumn = scale > 1.8;
            final columns = constraints.maxWidth < 300 || scale > 1.3 ? 2 : 3;
            if (singleColumn) {
              return Column(
                children: [
                  for (var i = 0; i < tools.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    _ToolCard(tool: tools[i], horizontal: true),
                  ],
                ],
              );
            }
            return Column(
              children: [
                for (var i = 0; i < tools.length; i += columns) ...[
                  if (i > 0) const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = 0; j < columns; j++) ...[
                          if (j > 0) const SizedBox(width: 10),
                          Expanded(child: _ToolCard(tool: tools[i + j])),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FieldTool {
  const _FieldTool(
    this.title,
    this.description,
    this.image,
    this.tint,
    this.fallback,
    this.onTap, {
    this.badge,
  });
  final String title, description, image;
  final Color tint;
  final IconData fallback;
  final VoidCallback onTap;
  final String? badge;
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool, this.horizontal = false});
  final _FieldTool tool;
  final bool horizontal;

  Widget _artwork() => ExcludeSemantics(
    child: Image.asset(
      'assets/field-brand/cargo-tools/${tool.image}.png',
      width: 52,
      height: 52,
      fit: BoxFit.contain,
      cacheWidth: 256,
      errorBuilder: (_, _, _) =>
          SizedBox.square(dimension: 52, child: Icon(tool.fallback, size: 40)),
    ),
  );

  Widget _copy(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: horizontal
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tool.title,
          textAlign: horizontal ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (horizontal && tool.badge != null)
          Text(tool.description, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = theme.brightness == Brightness.dark
        ? scheme.primaryContainer
        : tool.tint;
    return Semantics(
      label: tool.description,
      child: Tooltip(
        message: tool.description,
        child: MotionPress(
          child: Material(
            color: scheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: .5),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: tool.onTap,
              child: horizontal
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          SizedBox(width: 52, child: _artwork()),
                          const SizedBox(width: 12),
                          Expanded(child: _copy(context)),
                          const SizedBox(width: 8),
                          const ExcludeSemantics(
                            child: Icon(Icons.chevron_right, size: 18),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 62,
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [tint, scheme.surface],
                              ),
                            ),
                            child: Stack(
                              children: [
                                Center(child: _artwork()),
                                if (tool.badge != null)
                                  Positioned(
                                    top: 10,
                                    left: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surface,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        tool.badge!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                          child: _copy(context),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
