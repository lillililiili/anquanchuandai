import '../../components/field_brand.dart';
import '../../components/field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../hooks/use_theme.dart';
import '../../theme/theme.dart';
import '../../theme/theme_signal.dart';

/// 打卡签到页面
class CheckInPage extends HookWidget {
  const CheckInPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final tabIndex = useState(0);
    final checkInTime = useState<DateTime?>(DateTime(2025, 11, 3, 13, 28, 34));

    return Scaffold(
      backgroundColor: theme.background,
      appBar: _buildAppBar(context, tabIndex, theme),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 20),
                  SizedBox(width: 10),
                  Expanded(child: Text('演示页面 · 签到与历史记录为示例，不提交后台。')),
                ],
              ),
            ),
            // 根据 tabIndex 显示不同内容
            if (tabIndex.value == 0) ...[
              // 签到 tab
              _LocationCard(theme: theme),
              _StatisticsCard(theme: theme),
              _RecordsCard(
                theme: theme,
                title: '今日签到记录',
                records: _mockRecords,
              ),
            ] else ...[
              // 历史记录 tab
              _RecordsCard(
                theme: theme,
                title: '签到记录',
                records: _mockHistoryRecords,
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    ValueNotifier<int> tabIndex,
    ThemeColors theme,
  ) {
    return AppBar(
      backgroundColor: theme.background,
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
      title: ValueListenableBuilder<int>(
        valueListenable: tabIndex,
        builder: (context, value, _) {
          return Container(
            width: 200,
            height: 40,
            decoration: BoxDecoration(
              color: theme.divider,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
            ),
            child: Stack(
              children: [
                // 选中背景
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  left: value == 0 ? 0 : 100,
                  child: Container(
                    width: 100,
                    height: 40,
                    decoration: BoxDecoration(
                      color: SpringColors.mintGreen,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                    ),
                  ),
                ),
                // Tab 文字
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => tabIndex.value = 0,
                        child: Center(
                          child: Text(
                            '签到',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: value == 0
                                  ? Colors.white
                                  : theme.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => tabIndex.value = 1,
                        child: Center(
                          child: Text(
                            '历史记录',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: value == 1
                                  ? Colors.white
                                  : theme.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      centerTitle: true,
    );
  }
}

// ==================== 当前位置卡片 ====================
class _LocationCard extends HookWidget {
  final ThemeColors theme;

  const _LocationCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    final isCheckingIn = useState(false);
    final checkInTime = useState<DateTime?>(DateTime(2025, 11, 3, 13, 28, 34));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: AppSpacing.cardPaddingLarge,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, size: 26, color: SpringColors.textPrimaryLight),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('当前位置', style: TextStyle(fontSize: 12, color: theme.textTertiary)),
                  Text('A 区三号机组', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.textPrimary)),
                ],
              )),
            ],
          ),
          const SizedBox(height: 10),
          // 立即签到按钮
          GestureDetector(
            onTap: () {
              isCheckingIn.value = true;
              Future.delayed(const Duration(seconds: 1), () {
                isCheckingIn.value = false;
                checkInTime.value = DateTime.now();
              });
            },
            child: AnimatedScale(
              scale: isCheckingIn.value ? AppSpacing.pressScale : 1,
              duration: AppSpacing.pressDuration,
              child: Container(
                width: double.infinity,
                height: 48,
                decoration: BoxDecoration(
                  color: SpringColors.skyBlue,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMedium),
                  boxShadow: [
                    BoxShadow(
                      color: SpringColors.skyBlue.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: isCheckingIn.value
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      )
                    : const Center(
                        child: Text(
                          '立即签到',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 签到时间显示
          if (checkInTime.value != null)
            Text(
              '签到时间：${_formatDateTime(checkInTime.value!)}',
              style: TextStyle(fontSize: 12, color: theme.textSecondary),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}年${dt.month}月${dt.day}日${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

// ==================== 今日签到统计卡片 ====================
class _StatisticsCard extends StatelessWidget {
  final ThemeColors theme;

  const _StatisticsCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: AppSpacing.cardPaddingLarge,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '今日签到统计',
            style: AppTypography.title.copyWith(color: theme.textPrimary),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, constraints) {
            final count = constraints.maxWidth < 280 ||
                MediaQuery.textScalerOf(context).scale(13) > 17 ? 2 : 4;
            final width = (constraints.maxWidth - (count - 1) * 8) / count;
            return Wrap(spacing: 8, runSpacing: 8, children: [
              for (final stat in _mockStats)
                SizedBox(width: width, child: _StatItem(stat: stat, theme: theme)),
            ]);
          }),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final _StatData stat;
  final ThemeColors theme;

  const _StatItem({required this.stat, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: stat.color.withValues(alpha: AppSpacing.iconBackgroundAlpha),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            stat.value.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: stat.color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.label,
            style: TextStyle(
              fontSize: 13,
              color: theme.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 今日签到记录卡片 ====================
class _RecordsCard extends StatelessWidget {
  final ThemeColors theme;
  final String title;
  final List<_CheckInRecord> records;

  const _RecordsCard({
    required this.theme,
    required this.title,
    required this.records,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: AppSpacing.cardPaddingLarge,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const FieldSceneAccent(scene: 'track-card', size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.title.copyWith(
                    color: theme.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...records.asMap().entries.map((entry) {
            final index = entry.key;
            final record = entry.value;
            return Column(
              children: [
                _RecordItem(record: record, theme: theme),
                if (index < records.length - 1) ...[const SizedBox(height: 10)],
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _RecordItem extends StatelessWidget {
  final _CheckInRecord record;
  final ThemeColors theme;

  const _RecordItem({required this.record, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: record.statusColor.withValues(alpha: .14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态图标
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: record.statusColor.withValues(
                alpha: AppSpacing.iconBackgroundAlpha,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(record.statusIcon, color: record.statusColor, size: 22),
          ),
          const SizedBox(width: 12),
          // 记录详情
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      record.time,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: record.statusBgColor,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSmall,
                        ),
                      ),
                      child: Text(
                        record.statusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: record.statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  record.date,
                  style: TextStyle(fontSize: 13, color: theme.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: theme.textTertiary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        record.location,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 数据模型 ====================
class _StatData {
  final int value;
  final String label;
  final Color color;

  _StatData({required this.value, required this.label, required this.color});
}

class _CheckInRecord {
  final String time;
  final String date;
  final String location;
  final String statusLabel;
  final Color statusColor;
  final Color statusBgColor;
  final IconData statusIcon;

  _CheckInRecord({
    required this.time,
    required this.date,
    required this.location,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBgColor,
    required this.statusIcon,
  });
}

// ==================== 模拟数据 ====================
final List<_StatData> _mockStats = [
  _StatData(value: 1, label: '已签到', color: SpringColors.mintGreen),
  _StatData(value: 0, label: '迟到', color: SpringColors.sproutYellow),
  _StatData(value: 0, label: '缺卡', color: SpringColors.cherryRed),
  _StatData(value: 1, label: '应签到', color: SpringColors.skyBlue),
];

final List<_CheckInRecord> _mockRecords = [
  _CheckInRecord(
    time: '08:25:36',
    date: '2023 年 10 月 15 日',
    location: '公司总部 - A 座 3 楼',
    statusLabel: '正常',
    statusColor: SpringColors.mintGreen,
    statusBgColor: SpringColors.mintGreen.withValues(alpha: 0.15),
    statusIcon: Icons.check_circle,
  ),
  _CheckInRecord(
    time: '--:--:--',
    date: '2023 年 10 月 15 日',
    location: '下班签到',
    statusLabel: '待签到',
    statusColor: SpringColors.sproutYellow,
    statusBgColor: SpringColors.sproutYellow.withValues(alpha: 0.15),
    statusIcon: Icons.access_time,
  ),
];

final List<_CheckInRecord> _mockHistoryRecords = [
  _CheckInRecord(
    time: '08:25:36',
    date: '2023 年 10 月 15 日',
    location: '公司总部 - A 座 3 楼',
    statusLabel: '正常',
    statusColor: SpringColors.mintGreen,
    statusBgColor: SpringColors.mintGreen.withValues(alpha: 0.15),
    statusIcon: Icons.check_circle,
  ),
  _CheckInRecord(
    time: '18:30:22',
    date: '2023 年 10 月 15 日',
    location: '公司总部 - A 座 3 楼',
    statusLabel: '正常',
    statusColor: SpringColors.mintGreen,
    statusBgColor: SpringColors.mintGreen.withValues(alpha: 0.15),
    statusIcon: Icons.check_circle,
  ),
  _CheckInRecord(
    time: '08:35:10',
    date: '2023 年 10 月 14 日',
    location: '公司总部 - A 座 3 楼',
    statusLabel: '迟到',
    statusColor: SpringColors.sproutYellow,
    statusBgColor: SpringColors.sproutYellow.withValues(alpha: 0.15),
    statusIcon: Icons.access_time,
  ),
  _CheckInRecord(
    time: '18:28:45',
    date: '2023 年 10 月 14 日',
    location: '公司总部 - A 座 3 楼',
    statusLabel: '正常',
    statusColor: SpringColors.mintGreen,
    statusBgColor: SpringColors.mintGreen.withValues(alpha: 0.15),
    statusIcon: Icons.check_circle,
  ),
  _CheckInRecord(
    time: '08:20:15',
    date: '2023 年 10 月 13 日',
    location: '公司总部 - A 座 3 楼',
    statusLabel: '正常',
    statusColor: SpringColors.mintGreen,
    statusBgColor: SpringColors.mintGreen.withValues(alpha: 0.15),
    statusIcon: Icons.check_circle,
  ),
  _CheckInRecord(
    time: '--:--:--',
    date: '2023 年 10 月 13 日',
    location: '下班签到',
    statusLabel: '缺卡',
    statusColor: SpringColors.cherryRed,
    statusBgColor: SpringColors.cherryRed.withValues(alpha: 0.15),
    statusIcon: Icons.cancel,
  ),
];
