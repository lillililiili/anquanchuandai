import '../../../components/field_motion.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent.dart';
import 'package:rolling_intelligence_headband/hooks/use_page_agent_get_data.dart';
import 'package:rolling_intelligence_headband/router/route_tree.dart';
import '../../../api/tts_broadcast.dart';
import '../../../models/hat.dart';
import '../../../models/tts_broadcast_record.dart';
import '../../../theme/theme.dart';
import '../../../components/field_brand.dart';
import '../../home_children/person_select.dart';

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
        return '未选择播报对象';
    }
  }

  String get buttonText {
    switch (type) {
      case CallType.single:
        return targetName ?? '单播';
      case CallType.team:
        return targetName ?? '组播';
      case CallType.group:
        final count = targetIds?.length ?? 0;
        return '$count人';
      case CallType.none:
        return '';
    }
  }

  bool get isSelected => type != CallType.none;
}

/// TTS 播报页面
class TTSTab extends HookWidget {
  final ThemeColors theme;
  final PageAgentController? pageController;

  const TTSTab({required this.theme, this.pageController, super.key});

  @override
  Widget build(BuildContext context) {
    // 播报状态（提升到 TTSTab 层级，供 AI 工具和 UI 共用）
    final broadcastText = useState<String>('');
    final callTarget = useState<CallTarget>(const CallTarget.none());
    final isSending = useState<bool>(false);

    // 记录列表状态
    final records = useState<List<TtsBroadcastRecord>>([]);
    final isLoading = useState<bool>(false);
    final errorMsg = useState<String?>(null);
    final currentPage = useState<int>(1);
    final hasMore = useState<bool>(true);
    const pageSize = 20;

    final ttsContext = useContext();

    // 加载 TTS 记录
    Future<void> loadRecords({bool isRefresh = false}) async {
      if (isRefresh) {
        currentPage.value = 1;
      }

      try {
        isLoading.value = true;
        errorMsg.value = null;

        final result = await TtsBroadcastApi.getBroadcastPage(
          current: currentPage.value,
          size: pageSize,
        );

        if (!ttsContext.mounted) return;

        if (isRefresh) {
          records.value = result.records ?? [];
        } else {
          records.value = [...records.value, ...?(result.records)];
        }

        hasMore.value = records.value.length < (result.total ?? 0);
      } catch (e) {
        if (!ttsContext.mounted) return;
        errorMsg.value = e.toString();
      } finally {
        if (ttsContext.mounted) {
          isLoading.value = false;
        }
      }
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

    // 发送播报（供 AI 和 UI 共用）
    Future<void> handleSend() async {
      if (isSending.value) return;
      final content = broadcastText.value.trim();
      if (content.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请输入播报内容'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      if (!callTarget.value.isSelected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请先选择播报对象（单播、组播或群播）'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      try {
        isSending.value = true;

        switch (callTarget.value.type) {
          case CallType.single:
            await TtsBroadcastApi.createSingleBroadcast(
              content: content,
              hatNumber: callTarget.value.targetId,
              participant: callTarget.value.targetName,
            );
            break;
          case CallType.team:
            await TtsBroadcastApi.createTeamBroadcast(
              content: content,
              groupId: callTarget.value.targetId,
            );
            break;
          case CallType.group:
            await TtsBroadcastApi.createGroupBroadcast(
              content: content,
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
              content: Text('播报请求已发送'),
              duration: Duration(seconds: 2),
            ),
          );
          broadcastText.value = '';
          callTarget.value = const CallTarget.none();
          loadRecords(isRefresh: true);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('发送失败: $e'),
              duration: const Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (context.mounted) isSending.value = false;
      }
    }

    // 选择播报对象（AI 和 UI 共用）
    Future<void> handleSelectSingle({String? personName}) async {
      if (isSending.value) throw StateError('正在发送，请稍后更换对象');
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
      if (isSending.value) throw StateError('正在发送，请稍后更换对象');
      final isAiCall = groupName != null;
      final result = await context.goto(
        RouteNode.selectGroup,
        extra: {'groupName': groupName, 'autoSelect': isAiCall},
      );
      if (result != null && result is Map<String, dynamic>) {
        callTarget.value = CallTarget.team(
          result['groupId']?.toString(),
          groupName ?? result['groupName']?.toString() ?? '组播',
        );
      } else if (isAiCall) {
        throw Exception('未找到群组"$groupName"，请检查群组名称是否正确');
      }
    }

    Future<void> handleSelectGroup({List<String>? teamNames}) async {
      if (isSending.value) throw StateError('正在发送，请稍后更换对象');
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

    return _AgentScope(
      pageController: pageController,
      broadcastText: broadcastText,
      callTarget: callTarget,
      isSending: isSending,
      records: records,
      handleSend: handleSend,
      loadRecords: loadRecords,
      handleSelectSingle: handleSelectSingle,
      handleSelectTeam: handleSelectTeam,
      handleSelectGroup: handleSelectGroup,
      child: MotionActivity(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 输入卡片
              MotionEntrance(
                child: _InputCard(
                  theme: theme,
                  broadcastText: broadcastText,
                  callTarget: callTarget,
                  isSending: isSending,
                  onBroadcastTextChanged: (v) => broadcastText.value = v,
                  onCallTargetChanged: (v) => callTarget.value = v,
                  onSend: handleSend,
                  onSelectSingle: handleSelectSingle,
                  onSelectTeam: handleSelectTeam,
                  onSelectGroup: handleSelectGroup,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // 列表标题
              _buildSectionHeader('播报记录', Icons.history),
              const SizedBox(height: AppSpacing.md),
              // 播放记录列表
              _RecordList(
                records: records.value,
                isLoading: isLoading.value,
                errorMsg: errorMsg.value,
                hasMore: hasMore.value,
                onRetry: () => loadRecords(isRefresh: true),
                onLoadMore: loadMore,
                theme: theme,
                onRefresh: () => loadRecords(isRefresh: true),
              ),
              // 底部间距
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          width: AppSpacing.sectionTitleDecorationWidth,
          height: AppSpacing.sectionTitleDecorationHeight,
          decoration: BoxDecoration(
            color: SpringColors.mintGreenLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSection),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: AppTypography.title),
      ],
    );
  }
}

/// Agent 作用域 - 桥接 TTSTab 和 Agent 服务
class _AgentScope extends HookWidget {
  final Widget child;
  final PageAgentController? pageController;
  final ValueNotifier<String> broadcastText;
  final ValueNotifier<CallTarget> callTarget;
  final ValueNotifier<bool> isSending;
  final ValueNotifier<List<TtsBroadcastRecord>> records;
  final Future<void> Function() handleSend;
  final Future<void> Function({bool isRefresh}) loadRecords;
  final Future<void> Function({String? personName}) handleSelectSingle;
  final Future<void> Function({String? groupName}) handleSelectTeam;
  final Future<void> Function({List<String>? teamNames}) handleSelectGroup;

  const _AgentScope({
    required this.child,
    this.pageController,
    required this.broadcastText,
    required this.callTarget,
    required this.isSending,
    required this.records,
    required this.handleSend,
    required this.loadRecords,
    required this.handleSelectSingle,
    required this.handleSelectTeam,
    required this.handleSelectGroup,
  });

  @override
  Widget build(BuildContext context) {
    // 使用传入的 pageController，或自己创建
    final controller =
        pageController ??
        useAgentPage(
          meta: RouteNode.homeTab2,
          greetingMessage: '已进入语音播报页面，可设置播报内容、选择播报对象、查询播报记录、发送播报',
        );

    // 工具：设置播报文本
    usePageAgent(
      controller: controller,
      toolName: 'setBroadcastText',
      executeFn: (params) async {
        final content = params?['content'] as String?;
        if (content == null || content.isEmpty) {
          throw Exception('播报内容不能为空');
        }
        broadcastText.value = content;
        return {'success': true, 'message': '播报内容已设置为：$content'};
      },
    );

    // 工具：选择播报对象
    usePageAgent(
      controller: controller,
      toolName: 'selectBroadcastTarget',
      executeFn: (params) async {
        final type = params?['type'] as String?;

        if (type == null || type.isEmpty) {
          throw Exception('请指定播报类型："单播"/"组播"/"群播"');
        }

        switch (type) {
          case '单播':
            final personName = params?['personName'] as String?;
            if (personName == null || personName.isEmpty) {
              throw Exception('单播模式请提供personName参数');
            }
            await handleSelectSingle(personName: personName);
          case '组播':
            final groupName = params?['groupName'] as String?;
            if (groupName == null || groupName.isEmpty) {
              throw Exception('组播模式请提供groupName参数');
            }
            await handleSelectTeam(groupName: groupName);
          case '群播':
            List<String>? teamNames;
            try {
              teamNames = List<String>.from(
                jsonDecode(params?['teamNames']) as List,
              );
            } catch (e) {
              throw Exception(
                '群播模式请提供teamNames参数，格式为JSON数组字符串，例如：["团队A","团队B"]',
              );
            }

            await handleSelectGroup(teamNames: teamNames);
          default:
            throw Exception('无效的播报类型：$type，可选值："单播"/"组播"/"群播"');
        }

        return {
          'success': true,
          'message': '已选择$type对象：${callTarget.value.displayText}',
        };
      },
    );

    // 工具：查询播报记录
    usePageAgent(
      controller: controller,
      toolName: 'queryBroadcastRecords',
      executeFn: (params) async {
        final result = await TtsBroadcastApi.getBroadcastPage(
          broadcastType: params?['broadcastType'] as String?,
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
                  'broadcastType': r.broadcastType,
                  'content': r.content,
                  'recipient': r.recipient,
                  'recipientCount': r.recipientCount,
                  'sendTime': r.sendTime,
                  'operator': r.operator,
                },
              )
              .toList(),
        };
      },
    );

    // 工具：发送播报
    usePageAgent(
      controller: controller,
      toolName: 'sendBroadcast',
      executeFn: (params) async {
        await handleSend();
        return {'success': true, 'message': '播报已发送'};
      },
    );

    usePageAgentGetData(controller, "ttsState", () {
      return {
        'broadcastText': broadcastText.value,
        'broadcastTarget': {
          'type': callTarget.value.type.name,
          'displayText': callTarget.value.displayText,
          'isSelected': callTarget.value.isSelected,
        },
        'recordCount': records.value.length,
        'isSending': isSending.value,
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

// TTS 输入卡片
class _BroadcastKeyboardObserver extends WidgetsBindingObserver {
  _BroadcastKeyboardObserver(this.onMetricsChanged);
  final VoidCallback onMetricsChanged;
  @override
  void didChangeMetrics() => onMetricsChanged();
}

class _InputCard extends HookWidget {
  final ThemeColors theme;
  final ValueNotifier<String> broadcastText;
  final ValueNotifier<CallTarget> callTarget;
  final ValueNotifier<bool> isSending;
  final void Function(String) onBroadcastTextChanged;
  final void Function(CallTarget) onCallTargetChanged;
  final VoidCallback onSend;
  final Future<void> Function() onSelectSingle;
  final Future<void> Function() onSelectTeam;
  final Future<void> Function() onSelectGroup;
  const _InputCard({
    required this.theme,
    required this.broadcastText,
    required this.callTarget,
    required this.isSending,
    required this.onBroadcastTextChanged,
    required this.onCallTargetChanged,
    required this.onSend,
    required this.onSelectSingle,
    required this.onSelectTeam,
    required this.onSelectGroup,
  });
  @override
  Widget build(BuildContext context) {
    final textController = useTextEditingController();
    useEffect(() {
      if (textController.text != broadcastText.value)
        textController.text = broadcastText.value;
      return null;
    }, [broadcastText.value]);
    // Ancestor Scaffolds consume viewInsets when resizing their body.
    // Observe the view only for presentation; do not add a second inset.
    final view = View.of(context);
    final keyboardVisible = useState(view.viewInsets.bottom > 0);
    useEffect(() {
      final observer = _BroadcastKeyboardObserver(() {
        keyboardVisible.value = view.viewInsets.bottom > 0;
      });
      WidgetsBinding.instance.addObserver(observer);
      return () => WidgetsBinding.instance.removeObserver(observer);
    }, [view]);
    final keyboardOpen = keyboardVisible.value;
    final target = callTarget.value;
    final busy = isSending.value;
    final canSend = broadcastText.value.trim().isNotEmpty && target.isSelected;
    final names = target.targetNames?.join('、') ?? target.displayText;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign_outlined, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '播报内容',
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '清空播报内容',
                  visualDensity: VisualDensity.compact,
                  onPressed: busy || broadcastText.value.isEmpty
                      ? null
                      : () {
                          textController.clear();
                          onBroadcastTextChanged('');
                        },
                  icon: const Icon(Icons.backspace_outlined, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: textController,
            enabled: !busy,
            maxLines: 4,
            minLines: keyboardOpen ? 2 : 3,
            onChanged: onBroadcastTextChanged,
            style: TextStyle(
              color: theme.textPrimary,
              fontSize: 15,
              height: 1.5,
            ),
            decoration: const InputDecoration(hintText: '输入需要在设备上播报的内容'),
          ),
          SizedBox(height: keyboardOpen ? 8 : 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '接收对象',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              FieldSceneAccent(
                scene: 'communication-card',
                size: keyboardOpen ? 28 : 36,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BroadcastButton(
                  icon: Icons.person_outline,
                  label: '单人',
                  theme: theme,
                  isActive: target.type == CallType.single,
                  onTap: busy ? null : onSelectSingle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BroadcastButton(
                  icon: Icons.people_outline,
                  label: '分组',
                  theme: theme,
                  isActive: target.type == CallType.team,
                  onTap: busy ? null : onSelectTeam,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _BroadcastButton(
                  icon: Icons.groups_outlined,
                  label: '多人',
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
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.isSelected ? '发送至' : '尚未选择接收对象',
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        target.isSelected ? names : '请选择需要接收播报的人员或分组',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (target.isSelected)
                  IconButton(
                    tooltip: '清除接收对象',
                    onPressed: busy
                        ? null
                        : () => onCallTargetChanged(const CallTarget.none()),
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
              onPressed: busy || !canSend ? null : onSend,
              icon: busy
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    )
                  : const Icon(Icons.send_outlined, size: 20),
              label: Text(busy ? '正在发送…' : '发送语音播报'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '发送前请核对播报内容和接收对象',
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _BroadcastButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeColors theme;
  final VoidCallback? onTap;
  final bool isActive;
  const _BroadcastButton({
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
            MotionSpringValue(
              value: isActive ? 1 : 0,
              builder: (context, value, child) => Transform.scale(
                scale: MotionPolicy.reduced(context) ? 1 : 1 + .08 * value,
                child: child,
              ),
              child: Icon(
                isActive ? Icons.check_circle_outline : icon,
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// 获取广播类型显示文本
String _getBroadcastTypeText(String? type) {
  switch (type) {
    case '01':
      return '单播';
    case '02':
      return '群播';
    case '03':
      return '组播';
    default:
      return '播报';
  }
}

// 记录列表
class _RecordList extends StatelessWidget {
  final List<TtsBroadcastRecord> records;
  final bool isLoading;
  final String? errorMsg;
  final VoidCallback? onRetry;
  final VoidCallback? onLoadMore;
  final VoidCallback? onRefresh;
  final bool hasMore;
  final ThemeColors theme;

  const _RecordList({
    required this.records,
    required this.isLoading,
    this.errorMsg,
    this.onRetry,
    this.onLoadMore,
    this.onRefresh,
    this.hasMore = false,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && records.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: CircularProgressIndicator(),
        ),
      );
    }

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
                '暂无播报记录',
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
            return _RecordCard(
              record: records[index],
              theme: theme,
              onDelete: () => onRefresh?.call(),
            );
          },
        ),
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

class _RecordCard extends HookWidget {
  final TtsBroadcastRecord record;
  final ThemeColors theme;
  final VoidCallback? onDelete;

  const _RecordCard({required this.record, required this.theme, this.onDelete});

  String _formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--:--';
    try {
      final dateTime = DateTime.parse(timeStr);
      return '${dateTime.month}/${dateTime.day} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '--:--';
    }
  }

  Future<void> _handleDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除这条播报记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && record.id != null) {
      try {
        await TtsBroadcastApi.deleteBroadcast(record.id!);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('删除成功')));
          onDelete?.call();
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = SpringColors.getMintColor(theme.isDark);
    final lightGreen = SpringColors.mintGreenLight;

    return Dismissible(
      key: ValueKey(record.id ?? 'record_${record.hashCode}'),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        await _handleDelete(context);
        return false;
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.card,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              backgroundColor: theme.cardBackground,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              builder: (sheetContext) => SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '播报详情',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.groups_outlined, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '接收对象：${record.recipient ?? '未记录'}',
                                style: TextStyle(
                                  color: theme.textPrimary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.background,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '播报内容',
                              style: TextStyle(
                                color: theme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              record.content ?? '暂无播报内容',
                              style: TextStyle(
                                color: theme.textPrimary,
                                fontSize: 16,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('关闭'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: AppSpacing.quickActionIconSize,
                    height: AppSpacing.quickActionIconSize,
                    decoration: BoxDecoration(
                      color: lightGreen.withValues(
                        alpha: SpringColors.iconBackgroundAlphaActive,
                      ),
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusMedium,
                      ),
                    ),
                    child: Icon(
                      Icons.textsms,
                      color: theme.textPrimary,
                      size: AppSpacing.quickActionIconIconSize,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _getBroadcastTypeText(record.broadcastType),
                                style: AppTypography.body,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(
                                  alpha: AppSpacing.iconBackgroundAlpha,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.radiusSmall,
                                ),
                              ),
                              child: Text(
                                record.recipientCount != null &&
                                        record.recipientCount! > 0
                                    ? '${record.recipientCount}人'
                                    : '1人',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          record.content ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${record.operator ?? '未知用户'} • ${_formatTime(record.sendTime ?? record.createTime)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTertiary,
                          ),
                        ),
                      ],
                    ),
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
