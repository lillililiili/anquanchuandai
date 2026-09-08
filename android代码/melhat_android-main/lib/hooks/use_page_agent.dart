import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../models/chat_models.dart';
import 'use_agent_page.dart';

/// 页面 Agent 操作封装
/// 将页面内的业务操作统一封装，供 AI 和用户共同使用
///
/// 使用示例：
/// ```dart
/// final queryAgent = usePageAgent<AlarmPageData>(
///   controller: pageController,
///   toolName: 'queryAlarmRecord',
///   executeFn: (params) => _loadAlarmData(params),
/// );
///
/// // UI 使用
/// ElevatedButton(
///   onPressed: () => queryAgent.execute({'pageNum': 1}),
///   child: Text('查询'),
/// )
/// ```
PageAgent<T> usePageAgent<T>({
  required PageAgentController controller,
  required String toolName,
  required Future<T> Function(Map<String, dynamic>? params) executeFn,
}) {
  // 执行状态
  final status = useState(AgentStatus.idle);
  final currentData = useState<T?>(null);
  final error = useState<String?>(null);
  final progress = useState<int?>(null);
  final context = useContext();

  // 执行操作（AI 和用户共用）
  Future<T?> execute(Map<String, dynamic>? params) async {
    if (status.value == AgentStatus.loading) return null;

    status.value = AgentStatus.loading;
    error.value = null;

    try {
      final result = await executeFn(params);
      if (!context.mounted) return result;
      currentData.value = result;
      status.value = AgentStatus.success;
      return result;
    } catch (e) {
      if (!context.mounted) rethrow;
      error.value = e.toString();
      status.value = AgentStatus.error;
      if (kDebugMode) {
        print('PageAgent execute error: $e');
      }
      rethrow;
    }
  }

  // 通过 controller 注册工具执行器，生命周期由 controller 管理
  useEffect(() {
    controller.registerToolExecutor(toolName, (args) => execute(args));
    return () {
      controller.unregisterToolExecutor(toolName);
    };
  }, [controller, toolName]);

  return PageAgent<T>(
    execute: execute,
    currentData: currentData.value,
    status: status.value,
    error: error.value,
    progress: progress.value,
  );
}

/// 页面 Agent 封装类
class PageAgent<T> {
  /// 执行操作（AI 和用户共用）
  final Future<T?> Function(Map<String, dynamic>? params) execute;

  /// 获取当前状态/数据
  final T? currentData;

  /// 执行状态
  final AgentStatus status;

  /// 错误信息
  final String? error;

  /// 进度（0-100）
  final int? progress;

  const PageAgent({
    required this.execute,
    this.currentData,
    required this.status,
    this.error,
    this.progress,
  });

  /// 是否正在加载
  bool get isLoading => status == AgentStatus.loading;

  /// 是否成功
  bool get isSuccess => status == AgentStatus.success;

  /// 是否有错误
  bool get hasError => status == AgentStatus.error;
}
