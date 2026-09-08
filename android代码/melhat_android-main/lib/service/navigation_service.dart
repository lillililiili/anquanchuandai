import 'dart:async';

import '../models/chat_models.dart';
import '../models/navigation_models.dart';
import '../router/app_router.dart';
import '../router/route_tree.dart';
import '../utils/app_logger.dart';

/// 路由服务
/// 提供全局路由操作，供 AI 大模型或其他服务调用
class NavigationService {
  static final NavigationService instance = NavigationService._internal();
  NavigationService._internal();

  // ==================== 路由数据层 ====================

  /// 页面状态存储（用于 system prompt 构建）
  final Map<String, PageState> _pageData = {};

  /// 注册页面状态（页面初始化时调用）
  void registerPageData(PageState state) {
    _pageData[state.routeName] = state;
    AppLogger.i(
      'NavigationService: 页面 ${state.routeName} 已注册，工具数: ${state.tools.length}',
    );
  }

  /// 更新页面状态
  void updatePageData(PageState state) {
    if (_pageData.containsKey(state.routeName)) {
      _pageData[state.routeName] = state;
      AppLogger.i('NavigationService: 页面 ${state.routeName} 状态已更新');
    }
  }

  /// 获取页面可用工具
  List<ToolCall> getPageTools(String routeName) {
    return _pageData[routeName]?.tools ?? [];
  }

  /// 获取页面状态
  PageState? getPageState(String routeName) => _pageData[routeName];

  /// 页面卸载时清理
  void unregisterPageData(String routeName) {
    _pageData.remove(routeName);
    AppLogger.i('NavigationService: 页面 $routeName 已反注册');
  }

  // ==================== ToolCall 相关 ====================

  /// 获取导航工具的 ToolCall 定义
  /// 用于注册到 ToolCallService
  static ToolCall getNavigationToolCall() {
    return ToolCall(
      name: 'navigate_to_page',
      description: '导航到指定页面',
      useWhen: '当用户需要跳转到某个页面时',
      type: ToolCallType.dataFun,
      resultType: 'json',
      paramSchema: {
        'routeName': ToolParam(
          type: ToolParamType.string,
          description: '目标路由名称（如 CheckIn, AlarmDetail）',
          required: true,
        ),
        'params': ToolParam(
          type: ToolParamType.string,
          description: '可选参数，如 {"alarmId": "123"}',
        ),
      },
      applyCall: (args) async {
        final routeName = args?['routeName'] as String;
        final params = args?['params'] != null
            ? Map<String, String>.from(args?['params'] as Map)
            : null;
        return await navigationService.navigateByName(
          routeName,
          params: params,
        );
      },
    );
  }

  /// 根据路由名称导航（用于 ToolCall 调用）
  /// 创建 Completer 通过 extra 传递给目标页面，await 页面初始化完成
  Future<Map<String, dynamic>> navigateByName(
    String routeName, {
    Map<String, String>? params,
  }) async {
    try {
      final route = RouteRegistry.getRouteByName(routeName);
      if (route == null) {
        return {'success': false, 'error': '未知路由: $routeName'};
      }

      // 创建 Completer 用于等待页面初始化完成
      final readyCompleter = Completer<Map<String, dynamic>>();

      // 通过 extra 传递 Completer 给目标页面
      final path = route.url;
      final extra = {'readyCompleter': readyCompleter};

      if (route.isSecondary) {
        // 二级页面使用 push，可以返回
        if (params != null && params.isNotEmpty) {
          final uri = Uri.parse(path).replace(queryParameters: params);
          appRouter.push(uri.toString(), extra: extra);
        } else {
          appRouter.push(path, extra: extra);
        }
      } else {
        // 一级页面使用 go（替换当前页面）
        if (params != null && params.isNotEmpty) {
          final uri = Uri.parse(path).replace(queryParameters: params);
          appRouter.go(uri.toString(), extra: extra);
        } else {
          appRouter.go(path, extra: extra);
        }
      }

      // 等待页面初始化完成（带超时）
      final detail = RouteRegistry.getDetailByNameForAi(routeName);
      try {
        final pageData = await readyCompleter.future.timeout(
          const Duration(seconds: 10),
        );
        return {
          'success': true,
          'detail': detail,
          'pageData': pageData,
          'hint': '请直接使用以上数据回答用户。如需最新数据，请调用查询工具。',
        };
      } on TimeoutException {
        AppLogger.w('导航到 $routeName 后页面初始化超时');
        return {
          'success': true,
          'detail': detail,
          'warning': '页面导航成功但初始化超时',
        };
      }
    } catch (e) {
      AppLogger.e('导航失败: $e');
      return {'success': false, 'error': '导航失败: $e'};
    }
  }

  // ==================== 路由操作 ====================

  /// 跳转到指定路径
  void go(String path) {
    appRouter.go(path);
  }

  /// 跳转到指定路径（带参数）
  void goWithParams(String path, Map<String, String> params) {
    final uri = Uri.parse(path).replace(queryParameters: params);
    appRouter.go(uri.toString());
  }

  /// 返回上一页
  void pop<T>([T? result]) {
    appRouter.pop<T>(result);
  }

  /// 返回到根页面
  void popToRoot() {
    final navigator = homeShellKey.currentState;
    if (navigator != null) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  /// 返回指定次数
  void popTimes(int times) {
    final navigator = homeShellKey.currentState;
    if (navigator != null) {
      int count = 0;
      navigator.popUntil((route) {
        count++;
        return count > times || route.isFirst;
      });
    }
  }

  /// 检查是否可以返回
  bool canPop() {
    return homeShellKey.currentState?.canPop() ?? false;
  }

  /// 获取当前路径
  String? get currentPath {
    return appRouter.routerDelegate.currentConfiguration.uri.toString();
  }

  /// 获取当前路由名称
  String? get currentRouteName {
    final matches = appRouter.routerDelegate.currentConfiguration;
    if (matches.isEmpty) return null;
    final last = matches.last;
    return last.route.name;
  }
}

/// 全局路由服务实例
final navigationService = NavigationService.instance;
