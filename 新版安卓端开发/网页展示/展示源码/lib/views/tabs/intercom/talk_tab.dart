import '../../../components/tech_surface.dart';
import '../../../components/field_motion.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent_get_data.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import '../../../api/intercom.dart';
import '../../../models/agora_credentials.dart';
import '../../../models/hat.dart';
import '../../../models/intercom_record.dart';
import '../../../utils/app_logger.dart';
import '../../home_children/person_select.dart';
import '../../../theme/theme.dart';
import '../../../components/field_brand.dart';

/// 呼叫类型
enum CallType { none, single, team, group }

/// 呼叫目标状态
class CallTarget {
  final CallType type;
  final String? targetId;
  final String? targetName;
  final List<String>? targetIds;
  final List<String>? targetNames;

  const CallTarget.none()
    : type = CallType.none,
      targetId = null,
      targetName = null,
      targetIds = null,
      targetNames = null;

  const CallTarget.single(this.targetId, this.targetName)
    : type = CallType.single,
      targetIds = null,
      targetNames = null;

  const CallTarget.team(this.targetId, this.targetName)
    : type = CallType.team,
      targetIds = null,
      targetNames = null;

  const CallTarget.group(this.targetIds, this.targetNames)
    : type = CallType.group,
      targetId = null,
      targetName = null;

  /// 获取显示文本
  String get displayText {
    switch (type) {
      case CallType.single:
        return targetName ?? '';
      case CallType.team:
        return targetName ?? '';
      case CallType.group:
        final count = targetIds?.length ?? 0;
        return '选择了$count人';
      case CallType.none:
        return '未选择呼叫对象';
    }
  }

  /// 获取按钮上的简短文本
  String get buttonText {
    switch (type) {
      case CallType.single:
        return targetName ?? '单呼';
      case CallType.team:
        return targetName ?? '组呼';
      case CallType.group:
        final count = targetIds?.length ?? 0;
        return '$count人';
      case CallType.none:
        return '';
    }
  }

  /// 是否已选择
  bool get isSelected => type != CallType.none;

  /// 获取按钮副标题（选中状态下显示）
  String? get subtitle {
    if (!isSelected) return null;
    return buttonText;
  }
}

/// 对讲调度页面
class TalkDispatchTab extends HookWidget {
  final ThemeColors theme;
  final PageAgentController? pageController;

  const TalkDispatchTab({super.key, required this.theme, this.pageController});

  @override
  Widget build(BuildContext context) {
    // 呼叫状态（提升到 TalkDispatchTab 层级，供 AI 工具和 UI 共用）
    final callTarget = useState<CallTarget>(const CallTarget.none());
    final isCalling = useState<bool>(false);

    // 对讲记录列表数据
    final records = useState<List<IntercomRecord>>([]);
    final isLoading = useState<bool>(false);
    final errorMsg = useState<String?>(null);

    // 筛选状态
    final selectedFilter = useState<String?>('');
    final currentPage = useState<int>(1);
    final hasMore = useState<bool>(true);
    const pageSize = 20;

    final talkContext = useContext();

    // 加载对讲记录
    Future<void> loadRecords({bool isRefresh = false}) async {
      if (isRefresh) {
        currentPage.value = 1;
      }

      try {
        isLoading.value = true;
        errorMsg.value = null;

        final result = await IntercomApi.getRecordPage(
          current: currentPage.value,
          size: pageSize,
          intercomType: selectedFilter.value?.isNotEmpty == true
              ? selectedFilter.value
              : null,
        );

        if (!talkContext.mounted) return;

        if (isRefresh) {
          records.value = result.records ?? [];
        } else {
          records.value = [...records.value, ...?(result.records)];
        }

        hasMore.value = records.value.length < (result.total ?? 0);
      } catch (e) {
        if (!talkContext.mounted) return;
        errorMsg.value = e.toString();
      } finally {
        if (talkContext.mounted) {
          isLoading.value = false;
        }
      }
    }

    // 筛选处理
    void handleFilter(String value) {
      selectedFilter.value = value.isEmpty ? null : value;
      loadRecords(isRefresh: true);
    }

    // 加载更多
    Future<void> loadMore() async {
      if (hasMore.value && !isLoading.value) {
        currentPage.value++;
        await loadRecords();
      }
    }

    // 首次加载
    useEffect(() {
      loadRecords(isRefresh: true);
      return null;
    }, []);

    // 选择呼叫对象（AI 和 UI 共用）
    Future<void> handleSelectSingle({String? personName}) async {
      if (isCalling.value) throw StateError('正在呼叫，请稍后更换对象');
      final isAiCall = personName != null;
      final result = await context.goto<Hat>(
        RouteNode.hatSelect,
        extra: {
          'mode': SelectionMode.single,
          'personName': personName,
          'autoSelect': isAiCall,
        },
      );
      if (result is Hat) {
        callTarget.value = CallTarget.single(
          result.hatNumber,
          result.bindUserName ?? result.hatNumber ?? '未知用户',
        );
      } else if (isAiCall) {
        throw Exception('未找到人员"$personName"，请检查姓名是否正确');
      }
    }

    Future<void> handleSelectTeam({String? groupName}) async {
      if (isCalling.value) throw StateError('正在呼叫，请稍后更换对象');
      final isAiCall = groupName != null;
      final result = await context.goto(
        RouteNode.selectGroup,
        extra: {'groupName': groupName, 'autoSelect': isAiCall},
      );
      if (result != null && result is Map<String, dynamic>) {
        callTarget.value = CallTarget.team(
          result['groupId']?.toString(),
          groupName ?? result['groupName']?.toString() ?? '组呼',
        );
      } else if (isAiCall) {
        throw Exception('未找到群组"$groupName"，请检查群组名称是否正确');
      }
    }

    Future<void> handleSelectGroup({List<String>? teamNames}) async {
      if (isCalling.value) throw StateError('正在呼叫，请稍后更换对象');
      final isAiCall = teamNames != null && teamNames.isNotEmpty;
      final result = await context.goto(
        RouteNode.hatSelect,
        extra: {
          'mode': SelectionMode.multiple,
          'teamNames': teamNames,
          'autoSelect': isAiCall,
        },
      );
      if (result is List<Hat> && result.isNotEmpty) {
        final hatNumbers = result
            .map((h) => h.hatNumber)
            .where((n) => n != null)
            .cast<String>()
            .toList();
        final userNames = result
            .map((h) => h.bindUserName ?? h.hatNumber ?? '未知用户')
            .toList();
        callTarget.value = CallTarget.group(hatNumbers, userNames);
      } else if (isAiCall) {
        throw Exception('未找到指定的人员，请检查姓名列表是否正确');
      }
    }

    // 发起对讲呼叫（AI 和 UI 共用）
    Future<void> handleIntercom() async {
      if (isCalling.value) return;
      if (!callTarget.value.isSelected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先选择呼叫对象（单呼、组呼或群呼）'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      try {
        isCalling.value = true;
        AgoraCredentials? cre;

        switch (callTarget.value.type) {
          case CallType.single:
            cre = await IntercomApi.singleCall(
              clientId: 'app_123',
              hatNumber: callTarget.value.targetId,
              participant: callTarget.value.targetName,
            );
            break;
          case CallType.team:
            cre = await IntercomApi.teamCall(
              clientId: 'app_123',
              groupId: callTarget.value.targetId,
            );
            break;
          case CallType.group:
            cre = await IntercomApi.groupCall(
              clientId: 'app_123',
              hatNumber: callTarget.value.targetIds?.join(','),
              participant: callTarget.value.targetNames?.join(','),
            );
            break;
          case CallType.none:
            break;
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('对讲呼叫已发起'),
              duration: Duration(seconds: 2),
            ),
          );
          if (cre != null) {
            context.goto(RouteNode.rtcVideo, extra: cre.toJson());
          }
        }
      } catch (e, t) {
        AppLogger.e('对讲呼叫失败: ', e, t);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('对讲呼叫失败: $e'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (context.mounted) isCalling.value = false;
      }
    }

    return _AgentScope(
      pageController: pageController,
      callTarget: callTarget,
      isCalling: isCalling,
      records: records,
      handleSelectSingle: handleSelectSingle,
      handleSelectTeam: handleSelectTeam,
      handleSelectGroup: handleSelectGroup,
      handleIntercom: handleIntercom,
      loadRecords: loadRecords,
      child: MotionActivity(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 快捷操作卡片
              MotionEntrance(
                child: _QuickActionCard(
                  theme: theme,
                  callTarget: callTarget,
                  isCalling: isCalling,
                  onSelectSingle: handleSelectSingle,
                  onSelectTeam: handleSelectTeam,
                  onSelectGroup: handleSelectGroup,
                  onIntercom: handleIntercom,
                ),
              ),
              const SizedBox(height: 12),
              // 列表标题（带类型筛选）
              _buildSectionHeaderWithFilter(
                '对讲记录',
                Icons.history,
                selectedFilter: selectedFilter.value,
                onFilterSelected: handleFilter,
              ),
              const SizedBox(height: AppSpacing.md),
              // 对讲记录列表
              _RecordList(
                records: records.value,
                isLoading: isLoading.value,
                errorMsg: errorMsg.value,
                hasMore: hasMore.value,
                onRetry: () => loadRecords(isRefresh: true),
                onLoadMore: loadMore,
                theme: theme,
              ),
              // 底部间距（避免被悬浮导航栏遮挡）
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeaderWithFilter(
    String title,
    IconData icon, {
    String? selectedFilter,
    ValueChanged<String>? onFilterSelected,
  }) {
    final primaryColor = SpringColors.getMintColor(theme.isDark);

    return Row(
      children: [
        Container(
          width: AppSpacing.sectionTitleDecorationWidth,
          height: AppSpacing.sectionTitleDecorationHeight,
          decoration: BoxDecoration(
            color: SpringColors.mintGreen,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSection),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: AppTypography.title),
        const Spacer(),
        // 类型筛选下拉框
        Container(
          decoration: BoxDecoration(
            color: selectedFilter != null && selectedFilter.isNotEmpty
                ? primaryColor.withValues(
                    alpha: SpringColors.iconBackgroundAlpha,
                  )
                : (theme.isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xFFF3F4F6)),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          ),
          child: PopupMenuButton<String>(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.filter_list,
                  color: selectedFilter != null && selectedFilter.isNotEmpty
                      ? theme.textPrimary
                      : theme.textTertiary,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  _getFilterText(selectedFilter),
                  style: TextStyle(
                    fontSize: 13,
                    color: selectedFilter != null && selectedFilter.isNotEmpty
                        ? theme.textPrimary
                        : theme.textTertiary,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            tooltip: '按类型筛选',
            onSelected: onFilterSelected,
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(value: '', child: Text('全部类型')),
              const PopupMenuItem<String>(value: '01', child: Text('单呼')),
              const PopupMenuItem<String>(value: '02', child: Text('群呼')),
              const PopupMenuItem<String>(value: '03', child: Text('组呼')),
            ],
          ),
        ),
      ],
    );
  }

  String _getFilterText(String? filter) {
    switch (filter) {
      case '01':
        return '单呼';
      case '02':
        return '群呼';
      case '03':
        return '组呼';
      default:
        return '全部';
    }
  }
}

// 快捷操作卡片
class _QuickActionCard extends StatelessWidget {
  final ThemeColors theme;
  final ValueNotifier<CallTarget> callTarget;
  final ValueNotifier<bool> isCalling;
  final Future<void> Function() onSelectSingle;
  final Future<void> Function() onSelectTeam;
  final Future<void> Function() onSelectGroup;
  final Future<void> Function() onIntercom;
  const _QuickActionCard({
    required this.theme,
    required this.callTarget,
    required this.isCalling,
    required this.onSelectSingle,
    required this.onSelectTeam,
    required this.onSelectGroup,
    required this.onIntercom,
  });
  @override
  Widget build(BuildContext context) {
    final target = callTarget.value;
    final busy = isCalling.value;
    final names = target.targetNames?.join('、') ?? target.displayText;
    return MotionReveal(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '呼叫对象',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const FieldSceneAccent(scene: 'communication-card', size: 48),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CallTypeButton(
                    icon: Icons.person_outline,
                    label: '单呼',
                    theme: theme,
                    isActive: target.type == CallType.single,
                    onTap: busy ? null : onSelectSingle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CallTypeButton(
                    icon: Icons.people_outline,
                    label: '组呼',
                    theme: theme,
                    isActive: target.type == CallType.team,
                    onTap: busy ? null : onSelectTeam,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CallTypeButton(
                    icon: Icons.groups_outlined,
                    label: '群呼',
                    theme: theme,
                    isActive: target.type == CallType.group,
                    onTap: busy ? null : onSelectGroup,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MotionSwap(
                          value: '${target.type}:${target.isSelected}',
                          child: Text(
                            target.isSelected
                                ? '已选${target.type == CallType.group ? target.displayText : '呼叫对象'}'
                                : '尚未选择对象',
                            style: TextStyle(
                              color: theme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        MotionSwap(
                          value: target.isSelected ? names : '',
                          child: Text(
                            target.isSelected ? names : '选择单人、分组或多位人员',
                            style: TextStyle(
                              color: theme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (target.isSelected)
                    IconButton(
                      tooltip: '清除呼叫对象',
                      onPressed: busy
                          ? null
                          : () => callTarget.value = const CallTarget.none(),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: SpringColors.mintGreen,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: busy || !target.isSelected ? null : onIntercom,
                icon: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      )
                    : const Icon(Icons.call_outlined, size: 20),
                label: MotionSwap(
                  value: '$busy',
                  child: Text(busy ? '正在呼叫…' : '发起对讲'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Agent 作用域 - 桥接 TalkDispatchTab 和 Agent 服务
class _AgentScope extends HookWidget {
  final Widget child;
  final PageAgentController? pageController;
  final ValueNotifier<CallTarget> callTarget;
  final ValueNotifier<bool> isCalling;
  final ValueNotifier<List<IntercomRecord>> records;
  final Future<void> Function({String? personName}) handleSelectSingle;
  final Future<void> Function({String? groupName}) handleSelectTeam;
  final Future<void> Function({List<String>? teamNames}) handleSelectGroup;
  final Future<void> Function() handleIntercom;
  final Future<void> Function({bool isRefresh}) loadRecords;

  const _AgentScope({
    required this.child,
    this.pageController,
    required this.callTarget,
    required this.isCalling,
    required this.records,
    required this.handleSelectSingle,
    required this.handleSelectTeam,
    required this.handleSelectGroup,
    required this.handleIntercom,
    required this.loadRecords,
  });

  @override
  Widget build(BuildContext context) {
    // 使用传入的 pageController，或自己创建
    final controller =
        pageController ??
        useAgentPage(
          meta: RouteNode.homeTab2,
          greetingMessage: '已进入对讲调度页面，可选择呼叫对象、发起对讲呼叫、查询对讲记录',
        );

    // 工具：选择呼叫对象
    usePageAgent(
      controller: controller,
      toolName: 'selectCallTarget',
      executeFn: (params) async {
        final type = params?['type'] as String?;

        if (type == null || type.isEmpty) {
          throw Exception('请指定对讲类型："单呼"/"组呼"/"群呼"');
        }

        switch (type) {
          case '单呼':
            final personName = params?['personName'] as String?;
            if (personName == null || personName.isEmpty) {
              throw Exception('单呼模式请提供personName参数');
            }
            await handleSelectSingle(personName: personName);
          case '组呼':
            final groupName = params?['groupName'] as String?;
            if (groupName == null || groupName.isEmpty) {
              throw Exception('组呼模式请提供groupName参数');
            }
            await handleSelectTeam(groupName: groupName);
          case '群呼':
            List<String>? teamNames;
            try {
              teamNames = List<String>.from(
                jsonDecode(params?['teamNames']) as List,
              );
            } catch (e) {
              throw Exception(
                '群呼模式请提供teamNames参数，格式为JSON数组字符串，例如：["团队A","团队B"]',
              );
            }

            await handleSelectGroup(teamNames: teamNames);
          default:
            throw Exception('无效的对讲类型：$type，可选值："单呼"/"组呼"/"群呼"');
        }

        return {
          'success': true,
          'message': '已选择$type对象：${callTarget.value.displayText}',
        };
      },
    );

    // 工具：发起对讲呼叫
    usePageAgent(
      controller: controller,
      toolName: 'startIntercomCall',
      executeFn: (params) async {
        await handleIntercom();
        return {'success': true, 'message': '对讲呼叫已发起'};
      },
    );

    // 工具：查询对讲记录
    usePageAgent(
      controller: controller,
      toolName: 'queryIntercomRecords',
      executeFn: (params) async {
        final result = await IntercomApi.getRecordPage(
          intercomType: params?['intercomType'] as String?,
          current: params?['pageNum'] as int? ?? 1,
          size: params?['pageSize'] as int? ?? 20,
        );
        records.value = result.records ?? [];
        return {
          'total': result.total,
          'records': records.value
              .map(
                (r) => {
                  'id': r.id,
                  'intercomType': r.intercomType,
                  'participant': r.participant,
                  'duration': r.duration,
                  'startTime': r.startTime,
                },
              )
              .toList(),
        };
      },
    );

    // 工具：删除对讲记录
    usePageAgent(
      controller: controller,
      toolName: 'deleteIntercomRecord',
      executeFn: (params) async {
        final id = params?['id'] as int?;
        if (id == null) {
          throw Exception('请提供要删除的记录ID');
        }
        await IntercomApi.deleteRecord(id);
        await loadRecords(isRefresh: true);
        return {'success': true, 'message': '对讲记录已删除'};
      },
    );

    usePageAgentGetData(controller, "talkState", () {
      return {
        'callTarget': {
          'type': callTarget.value.type.name,
          'displayText': callTarget.value.displayText,
          'isSelected': callTarget.value.isSelected,
        },
        'recordCount': records.value.length,
        'isCalling': isCalling.value,
      };
    });

    // 通知 AI 页面就绪（仅当自己创建 controller 时）
    if (pageController == null) {
      useEffect(() {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            controller.completeEmptyInit();
          }
        });
        return null;
      }, []);
    }

    return child;
  }
}

class _CallTypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeColors theme;
  final VoidCallback? onTap;
  final bool isActive;
  const _CallTypeButton({
    required this.icon,
    required this.label,
    required this.theme,
    this.onTap,
    this.isActive = false,
  });
  @override
  Widget build(BuildContext context) {
    return MotionPress(
      enabled: onTap != null,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(58),
          padding: const EdgeInsets.symmetric(vertical: 8),
          foregroundColor: theme.textPrimary,
          backgroundColor: isActive
              ? SpringColors.mintGreen.withValues(alpha: 0.18)
              : theme.cardBackground,
          side: BorderSide(
            color: isActive ? SpringColors.mintGreen : theme.divider,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _RecordList extends StatelessWidget {
  final List<IntercomRecord> records;
  final bool isLoading;
  final String? errorMsg;
  final VoidCallback? onRetry;
  final VoidCallback? onLoadMore;
  final bool hasMore;
  final ThemeColors theme;

  const _RecordList({
    required this.records,
    required this.isLoading,
    this.errorMsg,
    this.onRetry,
    this.onLoadMore,
    this.hasMore = false,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // 加载中
    if (isLoading && records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // 错误
    if (errorMsg != null && records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 60, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                '加载失败: $errorMsg',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    // 空数据
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 60, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                '暂无对讲记录',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: records.length,
          separatorBuilder: (context, index) =>
              const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            return _RecordCard(record: records[index], theme: theme);
          },
        ),
        // 加载更多
        if (hasMore) ...[
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: isLoading ? null : onLoadMore,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              alignment: Alignment.center,
              child: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          SpringColors.getMintColor(theme.isDark),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.expand_more,
                          size: 18,
                          color: theme.textTertiary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '加载更多',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTertiary,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  final IntercomRecord record;
  final ThemeColors theme;
  const _RecordCard({required this.record, required this.theme});
  String _formatTime(String? value) {
    final date = DateTime.tryParse(value ?? '');
    if (date == null) return '时间未知';
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final type = switch (record.intercomType) {
      '01' => '单呼',
      '02' => '群呼',
      '03' => '组呼',
      _ => '对讲',
    };
    final hasRecord = record.recordPath?.isNotEmpty == true;
    return TechSurface(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.call_outlined, size: 20, color: theme.textPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$type通话',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  record.duration ?? '时长未知',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              record.participant ?? '参与人员未知',
              style: TextStyle(color: theme.textPrimary, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  _formatTime(record.startTime),
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
                Text(
                  hasRecord ? '录音暂不可播放' : '无录音',
                  style: TextStyle(color: theme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
