import 'dart:convert';

import 'package:rolling_intelligence_headband/components/agent_card/agent_form.dart';
import 'package:rolling_intelligence_headband/components/agent_card/user_profile.dart';
import 'package:rolling_intelligence_headband/hooks/use_agent_page.dart';
import 'package:rolling_intelligence_headband/models/chat_models.dart';
import 'package:rolling_intelligence_headband/service/navigation_service.dart';
import 'package:rolling_intelligence_headband/store/chat_store.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart'; // 必须导入

class ToolCallService {
  static final ToolCallService instance = ToolCallService._internal();

  ToolCallService._internal();

  final Map<String, ToolCall> _staticTools = {};
  final Map<String, ToolCall> _dynamicTools = {};

  /// 页面控制器映射表（支持多个页面共存）
  final Map<String, PageAgentController> _controllers = {};

  /// 当前活跃的控制器（最近设置的）
  PageAgentController? _currentController;

  /// 表单提交回调
  Future<void> Function(String toolName, Map<String, dynamic> formData)? onFormSubmit;

  /// 注册静态工具（应用启动时注册）
  void registerStaticTool(ToolCall tool) {
    _staticTools[tool.name] = tool;
  }

  void setCurrentController(PageAgentController controller) {
    _controllers[controller.routeName] = controller;
    _currentController = controller;
  }

  void unsetCurrentController() {
    // 只清空当前活跃标记，保留在映射表中
    _currentController = null;
  }

  /// 移除指定页面的 controller（页面真正销毁时调用）
  void removeController(String routeName) {
    _controllers.remove(routeName);
    if (_currentController?.routeName == routeName) {
      _currentController = _controllers.isNotEmpty ? _controllers.values.last : null;
    }
  }

  /// 注册动态工具（组件生命周期内注册）
  void registerDynamicTool(ToolCall tool) {
    AppLogger.d('注册动态工具：${tool.name}');
    _dynamicTools[tool.name] = tool;
  }

  /// 反注册动态工具
  void unregisterDynamicTool(String toolName) {
    AppLogger.d('反注册动态工具：${toolName}');
    _dynamicTools.remove(toolName);
  }

  /// 获取所有工具（静态 + 动态）
  Map<String, ToolCall> get allTools => {..._staticTools, ..._dynamicTools};

  /// 获取静态工具
  Map<String, ToolCall> get staticTools => _staticTools;

  /// 获取动态工具
  Map<String, ToolCall> get dynamicTools => _dynamicTools;

  String getToolsStruct() {
    return jsonEncode(allTools);
  }

  ToolCall? getTool(String name) {
    AppLogger.d('获取工具：$name');

    // 先从当前 controller 查找
    if (_currentController != null) {
      final tool = _currentController!.toolsByName[name];
      if (tool != null) {
        AppLogger.d('当前页面：${_currentController!.routeName}，工具已找到：$name');
        return tool.copy();
      }
    }

    // 遍历所有 controller 查找
    for (final controller in _controllers.values) {
      if (controller == _currentController) continue;
      final tool = controller.toolsByName[name];
      if (tool != null) {
        AppLogger.d('页面：${controller.routeName}，工具已找到：$name');
        return tool.copy();
      }
    }

    return _dynamicTools[name]?.copy() ?? _staticTools[name]?.copy();
  }

  void registerTools() {
    registerStaticTool(
      ToolCall(
        name: 'user_profile_card',
        description: '显示用户资料卡片',
        useWhen: '当用户请求查看自己的资料时',
        type: ToolCallType.dataCard,
        resultType: 'card',
        applyRender: (args) {
          return buildUserProfile();
        },
      ),
    );

    registerStaticTool(
      ToolCall(
        name: 'get_current_dynamic_tools',
        description: '显示当前动态工具',
        useWhen: '当用户请求查看当前动态工具时',
        type: ToolCallType.dataFun,
        resultType: 'json',
        applyCall: (args) async {
          final tools = _dynamicTools.values.map((e) => e.toJson()).toList();
          AppLogger.d('当前动态工具：$tools');
          return tools;
        },
      ),
    );

    registerStaticTool(NavigationService.getNavigationToolCall());

    registerStaticTool(
      ToolCall(
        name: 'close_chat_panel',
        description: '关闭聊天面板',
        useWhen: '当用户要求关闭聊天窗口、结束对话时，或任务完成后主动关闭面板时',
        type: ToolCallType.dataFun,
        resultType: 'json',
        applyCall: (args) async {
          ChatStore.instance.setChatPanelOpen(false);
          return {'success': true, 'message': '聊天面板已关闭'};
        },
      ),
    );

    registerStaticTool(
      ToolCall(
        name: 'open_chat_panel',
        description: '打开聊天面板',
        useWhen: '当用户要求打开聊天窗口时',
        type: ToolCallType.dataFun,
        resultType: 'json',
        applyCall: (args) async {
          ChatStore.instance.setChatPanelOpen(true);
          return {'success': true, 'message': '聊天面板已打开'};
        },
      ),
    );

    registerStaticTool(
      ToolCall(
        name: 'form_card',
        description: '显示交互式表单卡片，让用户填写数据',
        useWhen: '当需要收集用户输入信息时（如反馈、巡检记录、设备参数等）',
        type: ToolCallType.formCard,
        resultType: 'json',
        applyRender: (args) {
          return AgentForm(
            arguments: args,
            onSubmit: (formData) {
              toolCallService.onFormSubmit?.call('form_card', formData);
            },
          );
        },
      ),
    );

    print('已注册工具：${getToolsStruct()}');
  }
}

/// 全局工具调用服务实例
final toolCallService = ToolCallService.instance;
