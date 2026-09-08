import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:rolling_intelligence_headband/service/mcp_tool.dart';
import '../models/chat_models.dart';
import '../models/navigation_models.dart';
import '../router/route_tree.dart';
import '../service/navigation_service.dart';
import '../utils/app_logger.dart';

/// 页面 Agent 控制器
/// 管理页面状态、多组件初始化聚合、执行状态流转
class PageAgentController {
  final String routeName;
  final String? greetingMessage;
  final ValueNotifier<AgentStatus> _status;
  final ValueNotifier<String?> _currentAction;
  final ValueNotifier<dynamic> _lastResult;
  final ValueNotifier<String?> _error;
  final Set<String> _completedComponents = {};
  final Set<String>? _expectedComponents;
  final DateTime _mountedAt;

  /// Completer 用于通知导航方页面初始化完成
  Completer<Map<String, dynamic>>? _readyCompleter;

  /// 数据获取回调注册表
  /// key: 数据标识, value: 获取数据的回调函数
  final Map<String, Map<String, dynamic> Function()> _dataCallbacks = {};

  /// 工具执行器注册表
  /// key: toolName, value: 已注册的 ToolCall 引用（用于清理 applyCall）
  final Map<String, ToolCall> _toolExecutors = {};

  /// name -> ToolCall 映射（来自 RouteMeta.tools）
  final Map<String, ToolCall> _toolsByName;

  /// 工具映射（供 ToolCallService 查询，已绑定 applyCall）
  Map<String, ToolCall> get toolsByName => _toolsByName;

  /// 设置 Completer（由 useAgentPage hook 从 extra 中提取并调用）
  void setReadyCompleter(Completer<Map<String, dynamic>> completer) {
    _readyCompleter = completer;
  }

  PageAgentController({
    required this.routeName,
    required Map<String, ToolCall> toolsByName,
    this.greetingMessage,
    required ValueNotifier<AgentStatus> status,
    required ValueNotifier<String?> currentAction,
    required ValueNotifier<dynamic> lastResult,
    required ValueNotifier<String?> error,
    Set<String>? expectedComponents,
  }) : _toolsByName = toolsByName,
       _status = status,
       _currentAction = currentAction,
       _lastResult = lastResult,
       _error = error,
       _expectedComponents = expectedComponents,
       _mountedAt = DateTime.now();

  /// 当前页面状态
  AgentStatus get status => _status.value;

  /// 状态变化通知器（供 UI 监听）
  ValueNotifier<AgentStatus> get statusNotifier => _status;

  /// 当前执行的操作名称
  String? get currentAction => _currentAction.value;

  /// 最后一次执行结果
  dynamic get lastResult => _lastResult.value;

  /// 错误信息
  String? get error => _error.value;

  /// 是否已完成初始化（至少一个组件就绪）
  bool get isReady =>
      _status.value == AgentStatus.ready ||
      _status.value == AgentStatus.success ||
      _status.value == AgentStatus.error;

  /// 是否完全就绪（所有预期组件都就绪）
  bool get isFullyReady => _expectedComponents != null
      ? _completedComponents.containsAll(_expectedComponents!)
      : isReady;

  /// 已就绪的组件数
  int get readyComponentCount => _completedComponents.length;

  /// 完成初始化（由子组件调用）
  /// [componentId] 组件标识（必传）
  void completeInit({required String componentId}) {
    if (_completedComponents.contains(componentId)) {
      // 重复调用，触发数据更新通知
      _notifyPageUpdate();
      return;
    }

    // 标记组件完成
    _completedComponents.add(componentId);

    // 确定新状态
    final newStatus = _determineStatus();

    _status.value = newStatus;

    // 更新页面数据（用于 system prompt）
    navigationService.updatePageData(getSnapshot());

    // 当所有预期组件就绪时，complete Completer 通知导航方
    if (newStatus == AgentStatus.ready &&
        _readyCompleter != null &&
        !_readyCompleter!.isCompleted) {
      final snapshot = getSnapshot();
      _readyCompleter!.complete({
        'greeting': snapshot.greetingMessage ?? '',
        'data': snapshot.data,
      });
    }

    AppLogger.i(
      'PageAgent[$routeName]: 组件 $componentId 就绪，'
      '状态: $newStatus, 已就绪: ${_completedComponents.length}/'
      '${_expectedComponents?.length ?? "?"}',
    );
  }

  void completeEmptyInit() {
    // 确定新状态
    final newStatus = _determineStatus();

    _status.value = newStatus;

    // 更新页面数据（用于 system prompt）
    navigationService.updatePageData(getSnapshot());

    // complete Completer 通知导航方
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      final snapshot = getSnapshot();
      _readyCompleter!.complete({
        'greeting': snapshot.greetingMessage ?? '',
        'data': snapshot.data,
      });
    }
  }

  /// 完成操作（非初始加载）
  void completeAction({dynamic result}) {
    _lastResult.value = result;
    _status.value = AgentStatus.success;
    _currentAction.value = null;

    AppLogger.i('PageAgent[$routeName]: 执行成功');
  }

  /// 操作失败（非初始加载）
  void failAction(String error) {
    _error.value = error;
    _status.value = AgentStatus.error;
    _currentAction.value = null;

    AppLogger.e('PageAgent[$routeName]: 执行失败 - $error');
  }

  /// 初始加载失败
  void failInit(String error, {String? componentId}) {
    _error.value = error;
    _status.value = AgentStatus.error;

    AppLogger.e(
      'PageAgent[$routeName]: 组件 ${componentId ?? "unknown"} 初始加载失败 - $error',
    );
  }

  /// 注册数据获取回调（由子组件调用）
  /// [key] 数据标识
  /// [callback] 获取数据的回调函数
  void onGetData(String key, Map<String, dynamic> Function() callback) {
    _dataCallbacks[key] = callback;

    AppLogger.i('PageAgent[$routeName]: 注册数据回调 $key');
  }

  /// 注销数据获取回调
  void offGetData(String key) {
    _dataCallbacks.remove(key);

    AppLogger.i('PageAgent[$routeName]: 注销数据回调 $key');
  }

  /// 注册工具执行器（由 usePageAgent 调用）
  void registerToolExecutor(
    String toolName,
    Future<dynamic> Function(Map<String, dynamic>?) executeFn,
  ) {
    final tool = _toolsByName[toolName];
    if (tool == null) {
      AppLogger.w('PageAgent[$routeName]: 工具 $toolName 未找到，跳过注册');
      return;
    }

    tool.applyCall = executeFn;
    _toolExecutors[toolName] = tool;

    AppLogger.i('PageAgent[$routeName]: 注册工具执行器 $toolName');
  }

  /// 注销工具执行器
  void unregisterToolExecutor(String toolName) {
    final tool = _toolExecutors.remove(toolName);
    if (tool != null) {
      tool.applyCall = null;
      AppLogger.i('PageAgent[$routeName]: 注销工具执行器 $toolName');
    }
  }

  /// 清除所有工具执行器（页面销毁时调用）
  void clearAllToolExecutors() {
    for (final tool in _toolExecutors.values) {
      tool.applyCall = null;
    }
    _toolExecutors.clear();

    AppLogger.i('PageAgent[$routeName]: 清除所有工具执行器');
  }

  /// 获取页面状态快照
  PageState getSnapshot() {
    // 遍历回调获取最新数据
    final dynamicData = <String, dynamic>{};
    for (final entry in _dataCallbacks.entries) {
      try {
        dynamicData[entry.key] = entry.value.call();
      } catch (e) {
        AppLogger.e('PageAgent[$routeName]: 获取数据 ${entry.key} 失败: $e');
      }
    }

    final toolsList = _toolsByName.values.toList();

    AppLogger.i(
      'PageAgent[$routeName]: 生成页面快照，工具数: ${toolsList.length}, 数据项: ${dynamicData.toString()}',
    );

    return PageState(
      routeName: routeName,
      data: dynamicData,
      tools: toolsList,
      greetingMessage: greetingMessage,
      status: _status.value,
      mountedAt: _mountedAt,
    );
  }

  /// 确定当前状态
  AgentStatus _determineStatus() {
    if (_expectedComponents != null) {
      if (_completedComponents.containsAll(_expectedComponents!)) {
        return AgentStatus.ready;
      }
      return AgentStatus.loading; // 还有组件未就绪
    }
    return AgentStatus.ready;
  }

  /// 通知页面数据更新（非初始化）
  void _notifyPageUpdate() {
    navigationService.updatePageData(getSnapshot());
  }
}

/// 页面 Agent Hook（页面总控中心）
/// 管理页面状态、多组件初始化聚合、执行状态流转
///
/// 使用示例：
/// ```dart
/// class AlarmRecordPage extends HookWidget {
///   @override
///   Widget build(BuildContext context) {
///     final pageController = useAgentPage(
///       meta: RouteNode.alarmRecord,
///       greetingMessage: '已进入告警记录页面',
///       expectedComponents: {'statCard', 'listSection'}, // 可选：预期组件
///     );
///
///     return Column(
///       children: [
///         _StatCard(controller: pageController),
///         _AlarmListSection(controller: pageController),
///       ],
///     );
///   }
/// }
///
/// // 子组件中
/// class _AlarmListSection extends HookWidget {
///   final PageAgentController controller;
///
///   @override
///   Widget build(BuildContext context) {
///     final pagination = usePaginationTable<Alarm>(...);
///
///     // 通知初始化完成
///     useEffect(() {
///       if (pagination.data.isNotEmpty) {
///         controller.completeInit(
///           componentId: 'listSection',
///           data: {'total': pagination.total},
///         );
///       }
///       return null;
///     }, [pagination.data]);
///
///     return ...;
///   }
/// }
/// ```
PageAgentController useAgentPage({
  required RouteMeta meta,
  String? greetingMessage,
  Set<String>? expectedComponents,
}) {
  // 状态管理
  final status = useState(AgentStatus.idle);
  final currentAction = useState<String?>(null);
  final lastResult = useState<dynamic>(null);
  final error = useState<String?>(null);

  // 创建控制器（使用 useMemoized 确保单例）
  final controller = useMemoized(
    () => PageAgentController(
      routeName: meta.name,
      toolsByName: meta.tools,
      greetingMessage: greetingMessage ?? '已进入 ${meta.description}',
      status: status,
      currentAction: currentAction,
      lastResult: lastResult,
      error: error,
      expectedComponents: expectedComponents,
    ),
    [meta.name],
  );

  // 在 build 阶段获取 extra（不能在 useEffect 中获取 InheritedWidget）
  final context = useContext();
  final extra = GoRouterState.of(context).extra;

  // 从 extra 中提取 Completer（用于通知导航方页面就绪）
  useEffect(() {
    if (extra is Map<String, dynamic>) {
      final completer = extra['readyCompleter'];
      if (completer is Completer<Map<String, dynamic>>) {
        controller.setReadyCompleter(completer);
        AppLogger.i('PageAgent[${meta.name}]: 从 extra 获取到 Completer');
      }
    }
    return null;
  }, [meta.name]);

  // 初始注册页面
  useEffect(() {
    status.value = AgentStatus.loading;

    // 注册页面基础数据
    navigationService.registerPageData(controller.getSnapshot());

    toolCallService.setCurrentController(controller);

    AppLogger.i('PageAgent[${meta.name}]: 页面注册，等待组件初始化...');

    return () {
      controller.clearAllToolExecutors();
      navigationService.unregisterPageData(meta.name);
      toolCallService.unsetCurrentController();
    };
  }, [meta.name]);

  return controller;
}
