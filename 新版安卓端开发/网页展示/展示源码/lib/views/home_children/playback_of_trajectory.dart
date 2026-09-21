import '../../components/field_motion.dart';
import '../../components/field_brand.dart';
import '../../components/field_assistant_action.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../api/hat.dart';
import '../../components/map_trajectory_player.dart';
import '../../components/trajectory_player_view.dart';
import '../../components/trajectory_player_controls.dart';
import '../../controllers/trajectory_player_controller.dart';
import '../../hooks/use_skeleton.dart';
import '../../hooks/use_theme.dart';
import '../../models/hat.dart';
import '../../models/hat_location_file_record.dart';
import '../../models/hat_location_record.dart';
import '../../models/trajectory_point.dart';
import '../../theme/theme.dart';
import '../../components/skeleton_view.dart';
import 'person_select.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

({String start, String end}) _trajectoryRangeForDate(
  DateTime date, {
  bool allDay = false,
}) {
  final day =
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  return allDay
      ? (start: '$day 00:00', end: '$day 23:59:59')
      : (start: '$day 08:00', end: '$day 18:00');
}

String _formatRangeLabel(String start, String end) {
  String compact(String value) =>
      value.length >= 16 ? value.substring(5) : value;
  return '${compact(start)} 至 ${compact(end)}';
}

class _TrajectoryRequest {
  const _TrajectoryRequest({
    required this.generation,
    required this.hatId,
    required this.hatNumber,
    required this.startTime,
    required this.endTime,
  });

  final int generation;
  final String hatId;
  final String? hatNumber;
  final String startTime;
  final String endTime;
}

/// 轨迹回放页面
class PlaybackOfTrajectoryPage extends HookWidget {
  final String? initialHatId;
  final String? initialHatNumber;
  final String? initialUserName;
  final DateTime? initialDate;

  const PlaybackOfTrajectoryPage({
    super.key,
    this.initialHatId,
    this.initialHatNumber,
    this.initialUserName,
    this.initialDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = useTheme();
    final initialRange = useMemoized(
      () => _trajectoryRangeForDate(
        initialDate ?? DateTime.now(),
        allDay: initialDate != null,
      ),
      [initialDate],
    );
    final selectedHatId = useState<String?>(initialHatId);
    final selectedHatNumber = useState<String?>(initialHatNumber);
    final selectedUserName = useState<String?>(initialUserName);
    final startTime = useState<String>(initialRange.start);
    final endTime = useState<String>(initialRange.end);
    final showFullPlayer = useState<bool>(false);
    final lastQueryLabel = useState<String?>(null);

    final agentController = useAgentPage(
      meta: RouteNode.playbackOfTrajectory,
      greetingMessage:
          "当前页面是轨迹回放页面，你可以查询特定安全帽在指定时间范围内的轨迹数据，并查看关联的视频。要求先选择人员、时间范围，然后执行executeQuery。查询结果会显示轨迹地图和关联视频。",
    );

    // 创建轨迹播放器控制器
    final playerController = useMemoized(() => TrajectoryPlayerController());
    final queryGeneration = useMemoized(() => TrajectoryQueryGeneration());
    final pendingTrajectoryRequest = useRef<_TrajectoryRequest?>(null);
    final pendingVideoRequest = useRef<_TrajectoryRequest?>(null);
    useEffect(
      () => () {
        queryGeneration.invalidate();
        playerController.dispose();
      },
      [playerController],
    );

    // 检查查询条件是否有效
    final isValidQuery =
        selectedHatId.value != null &&
        startTime.value.isNotEmpty &&
        endTime.value.isNotEmpty;

    // 轨迹数据请求
    final trajectorySkeleton = useSkeleton<List<HatLocationRecord>>(
      emptyMsg: '暂无轨迹数据',
      immediate: false,
      isEmpty: (data) => data.isEmpty,
      commitToken: () => queryGeneration.current,
      request: () async {
        final request = pendingTrajectoryRequest.value;
        if (request == null) return [];
        AppLogger.i(
          '执行轨迹数据请求: hatId=${request.hatId}, startTime=${request.startTime}, endTime=${request.endTime}',
        );
        final records = await HatApi.queryHatLocationRecord(
          hatIds: [request.hatId],
          startTime: request.startTime,
          endTime: request.endTime,
        );
        return queryGeneration.isCurrent(request.generation) ? records : [];
      },
    );

    // 视频数据请求（基于选择的 hatNumber 和时间范围）
    final videoSkeleton = useSkeleton<List<HatLocationFileRecord>>(
      emptyMsg: '暂无关联视频',
      isEmpty: (data) => data.isEmpty,
      commitToken: () => queryGeneration.current,
      request: () async {
        final request = pendingVideoRequest.value;
        if (request == null) return [];
        final hatNumber = request.hatNumber;
        if (hatNumber == null || hatNumber.isEmpty) {
          return [];
        }
        // 调用 getRelatedFiles 获取关联视频文件
        final files = await HatApi.getRelatedFiles(
          hatNumber: hatNumber,
          startTime: request.startTime,
          endTime: request.endTime,
          fileType: 'video',
        );
        return queryGeneration.isCurrent(request.generation) ? files : [];
      },
      immediate: false, // 不立即执行，等待轨迹数据加载完成
    );

    void clearQueryResults({bool invalidate = true}) {
      if (invalidate) queryGeneration.invalidate();
      pendingTrajectoryRequest.value = null;
      pendingVideoRequest.value = null;
      playerController.setPoints(const []);
      trajectorySkeleton.data.value = null;
      trajectorySkeleton.status.value = SkeletonStatus.idle;
      videoSkeleton.data.value = null;
      videoSkeleton.status.value = SkeletonStatus.idle;
      lastQueryLabel.value = null;
      showFullPlayer.value = false;
    }

    Future<List<HatLocationRecord>> executeTrajectoryQuery() async {
      final hatId = selectedHatId.value;
      if (hatId == null || startTime.value.isEmpty || endTime.value.isEmpty) {
        return [];
      }
      final generation = queryGeneration.next();
      final request = _TrajectoryRequest(
        generation: generation,
        hatId: hatId,
        hatNumber: selectedHatNumber.value,
        startTime: startTime.value,
        endTime: endTime.value,
      );
      clearQueryResults(invalidate: false);
      pendingTrajectoryRequest.value = request;
      lastQueryLabel.value =
          '${selectedUserName.value ?? request.hatNumber ?? request.hatId} · '
          '${_formatRangeLabel(request.startTime, request.endTime)}';
      final records = await trajectorySkeleton.execute();
      if (!context.mounted || !queryGeneration.isCurrent(generation))
        return records;

      playerController.setPoints(TrajectoryPoint.fromList(records));
      pendingVideoRequest.value = request;
      await videoSkeleton.execute();
      return records;
    }

    useEffect(() {
      agentController.completeEmptyInit();
      return null;
    }, []);

    usePageAgent(
      controller: agentController,
      toolName: 'executeQuery',
      executeFn: (params) async {
        // 这里可以根据 params 来执行不同的查询逻辑
        return executeTrajectoryQuery();
      },
    );

    // useSkeleton 的 success 表示请求成功，零记录需要页面派生为空状态。
    final trajectoryStatus =
        trajectorySkeleton.status.value == SkeletonStatus.success &&
            (trajectorySkeleton.data.value?.isEmpty ?? true)
        ? SkeletonStatus.empty
        : trajectorySkeleton.status.value;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: theme.background,
          appBar: _buildAppBar(context, theme),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final hasQuery = isValidQuery && lastQueryLabel.value != null;
              return Stack(
                children: [
                  Positioned.fill(
                    child: _TrajectoryMapCard(
                      theme: theme,
                      skeleton: trajectorySkeleton,
                      controller: playerController,
                      onFullScreen: () => showFullPlayer.value = true,
                      onRetry: () => executeTrajectoryQuery().ignore(),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .58,
                      ),
                      child: SingleChildScrollView(
                        child: _QueryConditionCard(
                          theme: theme,
                          agentController: agentController,
                          context: context,
                          selectedHatId: selectedHatId,
                          selectedHatNumber: selectedHatNumber,
                          selectedUserName: selectedUserName,
                          startTime: startTime,
                          endTime: endTime,
                          onConditionsChanged: clearQueryResults,
                          status: trajectoryStatus,
                          lastQueryLabel: lastQueryLabel.value,
                          onQuery: () => executeTrajectoryQuery().ignore(),
                        ),
                      ),
                    ),
                  ),
                  if (hasQuery &&
                      trajectorySkeleton.status.value == SkeletonStatus.success)
                    DraggableScrollableSheet(
                      initialChildSize: .34,
                      minChildSize: .12,
                      maxChildSize: .76,
                      snap: true,
                      snapAnimationDuration: MotionPolicy.reduced(context)
                          ? const Duration(milliseconds: 1)
                          : const Duration(milliseconds: MotionPolicy.panelMs),
                      snapSizes: const [.12, .34, .76],
                      builder: (context, scrollController) => Container(
                        decoration: BoxDecoration(
                          color: theme.cardBackground,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                          boxShadow: const [
                            BoxShadow(color: Color(0x1A202B46), blurRadius: 12),
                          ],
                        ),
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.only(top: 8, bottom: 20),
                          children: [
                            Center(
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: theme.divider,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            _PlaybackControlCard(
                              theme: theme,
                              controller: playerController,
                              onFullScreen: () => showFullPlayer.value = true,
                            ),
                            _RelatedVideoCard(
                              theme: theme,
                              skeleton: videoSkeleton,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (!hasQuery)
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 32,
                      child: Material(
                        color: theme.cardBackground,
                        borderRadius: BorderRadius.circular(16),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            '选择人员与日期后查询轨迹',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        // 全屏轨迹回放播放器（使用同一个控制器）
        MapTrajectoryPlayer(
          visible: showFullPlayer.value,
          onClose: () => showFullPlayer.value = false,
          trajectoryData: trajectorySkeleton.data.value ?? [],
          controller: playerController,
        ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ThemeColors theme) {
    return AppBar(
      backgroundColor: theme.background,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        tooltip: '返回',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(
        '轨迹回放',
        style: AppTypography.headlineMedium.copyWith(color: theme.textPrimary),
      ),
      centerTitle: true,
      actions: const [FieldAssistantAction()],
    );
  }
}

// ==================== 查询条件卡片 ====================
class _QueryConditionCard extends HookWidget {
  final ThemeColors theme;
  final BuildContext context;
  final ValueNotifier<String?> selectedHatId;
  final ValueNotifier<String?> selectedHatNumber;
  final ValueNotifier<String?> selectedUserName;
  final ValueNotifier<String> startTime;
  final ValueNotifier<String> endTime;
  final VoidCallback onQuery;
  final VoidCallback onConditionsChanged;
  final SkeletonStatus status;
  final String? lastQueryLabel;
  final PageAgentController agentController;

  const _QueryConditionCard({
    required this.theme,
    required this.context,
    required this.selectedHatId,
    required this.selectedHatNumber,
    required this.selectedUserName,
    required this.startTime,
    required this.endTime,
    required this.onQuery,
    required this.onConditionsChanged,
    required this.status,
    required this.lastQueryLabel,
    required this.agentController,
  });

  @override
  Widget build(BuildContext context) {
    // 监听状态变化以触发重建
    final userName = useValueListenable(selectedUserName);
    final hatNumber = useValueListenable(selectedHatNumber);

    final selectPerson = useCallback((String? personName) async {
      final result = await context.goto<dynamic>(
        RouteNode.hatSelect,
        extra: {
          'mode': SelectionMode.single,
          'personName': personName,
          'autoSelect': true,
        },
      );

      if (result is Hat) {
        final hat = result;
        AppLogger.i('选择安全帽成功: hatId=${hat.id}, hatNumber=${hat.hatNumber}');
        onConditionsChanged();
        selectedHatId.value = hat.id;
        selectedHatNumber.value = hat.hatNumber;
        selectedUserName.value = hat.bindUserName ?? hat.hatNumber ?? '未知用户';
      }
      return result;
    }, [context]);

    usePageAgent(
      controller: agentController,
      toolName: 'selectPerson',
      executeFn: (params) async {
        // 这里可以根据 params 来执行不同的查询逻辑
        String? personName = params?['name'] as String?;
        return selectPerson(personName);
      },
    );

    usePageAgent(
      controller: agentController,
      toolName: 'selectDateRange',
      executeFn: (params) async {
        String start = params?['startTime'] as String? ?? '';
        String end = params?['endTime'] as String? ?? '';

        onConditionsChanged();
        startTime.value = start;
        endTime.value = end;

        return true;
      },
    );

    // 检查查询条件是否有效
    final isValidQuery =
        selectedHatId.value != null &&
        startTime.value.isNotEmpty &&
        endTime.value.isNotEmpty;

    return Container(
      margin: AppSpacing.cardMargin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primaryContainer,
            theme.cardBackground,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: MotionEntrance(
                  child: Row(
                    children: [
                      const FieldSceneAccent(scene: 'track-card', size: 40),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          userName ?? hatNumber ?? '人员与日期',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.title.copyWith(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: isValidQuery && status != SkeletonStatus.loading
                    ? onQuery
                    : null,
                icon: status == SkeletonStatus.loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 18),
                label: const Text('查询'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 人员选择（单选）- 改为选择安全帽
          _buildQueryRow(
            label: '人员：',
            value: userName ?? '未选择',
            theme: theme,
            onTap: () async {
              selectPerson(null);
            },
          ),
          const SizedBox(height: 4),
          // 时间选择
          _buildQueryRow(
            label: '时间：',
            value: startTime.value.isNotEmpty
                ? _formatDisplayTime(startTime.value, endTime.value)
                : '选择时间范围',
            theme: theme,
            onTap: () => _selectDateRange(
              context,
              theme,
              startTime,
              endTime,
              onConditionsChanged,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final offset in [0, 1])
                ActionChip(
                  label: Text(offset == 0 ? '今天全天' : '昨天全天'),
                  onPressed: () {
                    final now = DateTime.now();
                    final day = DateTime(now.year, now.month, now.day - offset);
                    final range = _trajectoryRangeForDate(day, allDay: true);
                    if (startTime.value == range.start &&
                        endTime.value == range.end) {
                      return;
                    }
                    onConditionsChanged();
                    startTime.value = range.start;
                    endTime.value = range.end;
                  },
                ),
            ],
          ),
          _buildRangeFeedback(theme),
        ],
      ),
    );
  }

  Widget _buildRangeFeedback(ThemeColors theme) {
    final label = lastQueryLabel;
    final message = label == null
        ? '当前范围：${_formatRangeLabel(startTime.value, endTime.value)}'
        : switch (status) {
            SkeletonStatus.loading => '正在查询 $label',
            SkeletonStatus.success => '已查询 $label',
            SkeletonStatus.empty => '该查询范围内暂无轨迹数据',
            SkeletonStatus.error => '查询失败，可调整人员或时间后重试',
            SkeletonStatus.idle =>
              '当前范围：${_formatRangeLabel(startTime.value, endTime.value)}',
          };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: SpringColors.skyBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: theme.textSecondary),
      ),
    );
  }

  Widget _buildQueryRow({
    required String label,
    required String value,
    required ThemeColors theme,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 14, color: theme.textSecondary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: theme.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right, size: 18, color: theme.textTertiary),
          ],
        ),
      ),
    );
  }

  /// 选择日期范围
  Future<void> _selectDateRange(
    BuildContext context,
    ThemeColors theme,
    ValueNotifier<String> startTime,
    ValueNotifier<String> endTime,
    VoidCallback onConditionsChanged,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 解析现有值，如果有的话
    PickerDateRange? initialSelectedRange;
    if (startTime.value.isNotEmpty && endTime.value.isNotEmpty) {
      try {
        final startDate = DateTime.tryParse(startTime.value.split(' ').first);
        final endDate = DateTime.tryParse(endTime.value.split(' ').first);
        if (startDate != null && endDate != null) {
          initialSelectedRange = PickerDateRange(startDate, endDate);
        }
      } catch (_) {
        // 忽略解析错误
      }
    }

    final selectedRange = await showDialog<PickerDateRange>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
            child: Container(
              width: 360,
              color: theme.cardBackground,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(Icons.date_range_outlined, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '选择日期范围',
                            style: AppTypography.title.copyWith(
                              color: theme.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Icon(
                            Icons.close,
                            size: 24,
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 日期选择器
                  SfDateRangePicker(
                    view: DateRangePickerView.month,
                    selectionMode: DateRangePickerSelectionMode.range,
                    initialSelectedRange: initialSelectedRange,
                    minDate: DateTime(2020),
                    maxDate: today.add(const Duration(days: 1)),
                    todayHighlightColor: SpringColors.skyBlue,
                    startRangeSelectionColor: SpringColors.skyBlue,
                    endRangeSelectionColor: SpringColors.skyBlue,
                    rangeSelectionColor: SpringColors.skyBlue.withValues(
                      alpha: 0.2,
                    ),
                    selectionColor: SpringColors.skyBlue,
                    selectionTextStyle: TextStyle(color: theme.textPrimary),
                    backgroundColor: theme.cardBackground,
                    headerStyle: DateRangePickerHeaderStyle(
                      backgroundColor: theme.cardBackground,
                      textStyle: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    monthViewSettings: DateRangePickerMonthViewSettings(
                      dayFormat: 'EEE',
                      viewHeaderStyle: DateRangePickerViewHeaderStyle(
                        backgroundColor: theme.cardBackground,
                        textStyle: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    monthCellStyle: DateRangePickerMonthCellStyle(
                      textStyle: TextStyle(color: theme.textPrimary),
                      todayTextStyle: TextStyle(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                      disabledDatesTextStyle: TextStyle(
                        color: theme.textTertiary.withValues(alpha: 0.5),
                      ),
                    ),
                    yearCellStyle: DateRangePickerYearCellStyle(
                      textStyle: TextStyle(color: theme.textPrimary),
                      todayTextStyle: TextStyle(
                        color: theme.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onSubmit: (Object? value) {
                      Navigator.of(context).pop(value as PickerDateRange?);
                    },
                    onCancel: () {
                      Navigator.of(context).pop(null);
                    },
                    showActionButtons: true,
                    confirmText: '确定',
                    cancelText: '取消',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selectedRange == null || !context.mounted) return;

    // 获取选中的开始和结束日期
    final startDate = selectedRange.startDate;
    final endDate = selectedRange.endDate ?? startDate;

    if (startDate == null) return;

    // 格式化日期：MM-DD（不显示年份）
    final startStr = _formatDate(startDate);
    final endStr = _formatDate(endDate!);

    // 日历只修改日期；保留已应用的全天或自定义时段。
    final startClock = startTime.value.split(' ').skip(1).join(' ');
    final endClock = endTime.value.split(' ').skip(1).join(' ');
    final newStart = '$startStr ${startClock.isEmpty ? '00:00' : startClock}';
    final newEnd = '$endStr ${endClock.isEmpty ? '23:59:59' : endClock}';
    if (newStart == startTime.value && newEnd == endTime.value) return;
    onConditionsChanged();
    startTime.value = newStart;
    endTime.value = newEnd;
  }

  /// 格式化日期为 YYYY-MM-DD
  String _formatDate(DateTime date) {
    final year = date.year;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  /// 格式化显示时间（截掉年份，避免溢出）
  /// 输入格式: "YYYY-MM-DD HH:mm"
  /// 输出格式: "MM-DD HH:mm"
  String _formatDisplayTime(String startTime, String endTime) {
    // 去掉年份部分，只保留 MM-DD HH:mm
    final startDisplay = startTime.length >= 14
        ? startTime.substring(5)
        : startTime;
    final endDisplay = endTime.length >= 14 ? endTime.substring(5) : endTime;
    return '$startDisplay - $endDisplay';
  }
}

// ==================== 轨迹回放地图卡片 ====================
/// 使用 TrajectoryPlayerView 组件
class _TrajectoryMapCard extends HookWidget {
  final ThemeColors theme;
  final SkeletonBind<List<HatLocationRecord>> skeleton;
  final TrajectoryPlayerController controller;
  final VoidCallback onFullScreen, onRetry;

  const _TrajectoryMapCard({
    required this.theme,
    required this.skeleton,
    required this.controller,
    required this.onFullScreen,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final points = useMemoized(
      () => TrajectoryPoint.fromList(skeleton.data.value ?? []),
      [skeleton.data.value],
    );
    final viewStatus =
        skeleton.status.value == SkeletonStatus.success && points.isEmpty
        ? SkeletonStatus.empty
        : skeleton.status.value;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: TrajectoryPlayerView(
              points: points,
              controller: controller,
              height: constraints.maxHeight,
              showEmptyState: false,
            ),
          ),
          if (viewStatus != SkeletonStatus.idle &&
              viewStatus != SkeletonStatus.success)
            Positioned(
              left: 16,
              right: 16,
              top: constraints.maxHeight * .40,
              child: Material(
                color: theme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                child: SkeletonView<List<HatLocationRecord>>(
                  status: viewStatus,
                  data: skeleton.data.value,
                  emptyMsg: skeleton.emptyMsg.value,
                  errorMsg: skeleton.errorMsg.value,
                  isEmpty: skeleton.isEmpty,
                  minHeight: 160,
                  onRetry: onRetry,
                  builder: (_) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (points.isNotEmpty)
            Positioned(
              right: 16,
              top: constraints.maxHeight * .38,
              child: IconButton.filledTonal(
                tooltip: '全屏回放',
                onPressed: onFullScreen,
                icon: const Icon(Icons.fullscreen),
              ),
            ),
        ],
      ),
    );
  }
}

// ==================== 轨迹回放控制卡片 ====================
/// 使用新的 TrajectoryPlayerControls 组件
class _PlaybackControlCard extends HookWidget {
  final ThemeColors theme;
  final TrajectoryPlayerController controller;

  final VoidCallback? onFullScreen;
  const _PlaybackControlCard({
    required this.theme,
    required this.controller,
    this.onFullScreen,
  });

  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    return Container(
      margin: AppSpacing.cardMargin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TrajectoryPlayerControls(
            controller: controller,
            onFullScreen: onFullScreen,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: controller.points.isEmpty
                ? null
                : () => _selectTrajectoryTime(context, controller),
            icon: const Icon(Icons.schedule, size: 18),
            label: Text(
              controller.currentTimestamp == null
                  ? '定位时间点'
                  : '定位时间点 · ${controller.currentTimestamp}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTrajectoryTime(
    BuildContext context,
    TrajectoryPlayerController controller,
  ) async {
    final current = controller.currentIndex >= 0
        ? controller.points[controller.currentIndex].dateTime
        : controller.points.first.dateTime;
    final first = controller.points.first.dateTime;
    final last = controller.points.last.dateTime;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateUtils.dateOnly(first),
      lastDate: DateUtils.dateOnly(last),
      helpText: '选择轨迹日期',
      confirmText: '下一步',
      cancelText: '取消',
    );
    if (date == null || !context.mounted) return;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: '${date.month}月${date.day}日 · 定位轨迹时间',
      confirmText: '定位',
      cancelText: '取消',
    );
    if (selected == null || !context.mounted) return;
    controller.seekToTimestamp(
      DateTime(date.year, date.month, date.day, selected.hour, selected.minute),
    );
  }
}

// ==================== 轨迹点关联视频卡片 ====================
class _RelatedVideoCard extends HookWidget {
  final ThemeColors theme;
  final SkeletonBind<List<HatLocationFileRecord>> skeleton;

  const _RelatedVideoCard({required this.theme, required this.skeleton});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: AppSpacing.cardMargin,
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLarge),
        border: Border.all(color: theme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '轨迹点关联视频',
              style: AppTypography.title.copyWith(
                color: theme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 视频列表（使用骨架屏）
          SkeletonView.fromHook(
            skeleton,
            (videos) => Column(
              children: videos
                  .map((video) => _VideoItem(video: video, theme: theme))
                  .toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _VideoItem extends StatelessWidget {
  final HatLocationFileRecord video;
  final ThemeColors theme;

  const _VideoItem({required this.video, required this.theme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (video.fileUrl != null && video.fileUrl!.isNotEmpty) {
          context.goto(
            RouteNode.videoPlayer,
            extra: {'url': video.fileUrl!, 'title': video.fileName ?? '视频播放'},
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            // 视频缩略图
            Stack(
              children: [
                Container(
                  width: 120,
                  height: 90,
                  decoration: BoxDecoration(
                    color: theme.isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(
                      AppSpacing.radiusMedium,
                    ),
                  ),
                  child: Icon(
                    Icons.videocam,
                    size: 32,
                    color: theme.textTertiary,
                  ),
                ),
                // 播放按钮
                Positioned.fill(
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: SpringColors.skyBlue.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        size: 24,
                        color: const Color(0xFF202B46),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.lg),
            // 视频信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.fileName ?? '未命名视频',
                    style: AppTypography.body.copyWith(
                      color: theme.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    video.hatNumber ?? '未知设备',
                    style: TextStyle(fontSize: 13, color: theme.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    video.uploadTime ?? '',
                    style: TextStyle(fontSize: 13, color: theme.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
