import 'package:rolling_intelligence_headband/service/mcp_tool.dart' as my_mcp;
import 'package:openai_dart/openai_dart.dart';
import 'package:rolling_intelligence_headband/service/navigation_service.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import 'package:rolling_intelligence_headband/service/ai_exceptions.dart';
import 'package:rolling_intelligence_headband/store/ai_config_store.dart';
import 'dart:convert';
import '../models/chat_models.dart' as local;
import '../router/route_tree.dart';

/// AI 服务类
class AIService {
  static final AIService instance = AIService._internal();
  late OpenAIClient _client;

  // 系统提示词静态部分缓存（路由和全局工具不变）
  String? _staticPromptCache;

  /// 构建静态部分的 system prompt（路由、全局工具、指令）
  /// 只在首次调用时构建，后续直接返回缓存
  String _buildStaticPrompt() {
    if (_staticPromptCache != null) return _staticPromptCache!;

    // 一级页面（Tab 页面）- 只保留名称和描述
    final primaryPages = RouteRegistry.getPrimaryRoutes()
        .map((r) => '- ${r.name}: ${r.description}')
        .join('\n');

    // 按 tab 分组的二级页面 - 只保留名称和描述，去掉工具列表
    final secondaryPageList = StringBuffer();

    // 按 tab 顺序展示
    for (final tabName in [
      AppTab.home,
      AppTab.monitor,
      AppTab.intercom,
      AppTab.mine,
    ]) {
      final routes = RouteRegistry.getSecondaryRoutes()
          .where((r) => r.parentTab == tabName && r.isAgentPage)
          .toList();
      if (routes.isEmpty) continue;

      final tabLabel = AppTab.labels[tabName] ?? tabName;
      secondaryPageList.writeln('\n### $tabLabel');
      for (final r in routes) {
        secondaryPageList.writeln('- ${r.name}: ${r.description}');
      }
    }

    // 独立页面（不属于任何 tab）
    final standaloneRoutes = RouteRegistry.getSecondaryRoutes().where(
      (r) => r.parentTab == null && r.isAgentPage,
    );
    if (standaloneRoutes.isNotEmpty) {
      secondaryPageList.writeln('\n### 其他');
      for (final r in standaloneRoutes) {
        secondaryPageList.writeln('- ${r.name}: ${r.description}');
      }
    }

    // 全局工具列表（从 ToolCallService 获取）
    final staticTools = my_mcp.toolCallService.staticTools;
    final toolList = staticTools.values
        .map((tool) {
          final args =
              tool.paramSchema?.entries
                  .map((e) => '${e.key}(${e.value.description})')
                  .join(', ') ??
              '';
          return '- ${tool.name}: ${tool.description}${args.isNotEmpty ? '\n  参数: $args' : ''}';
        })
        .join('\n');

    _staticPromptCache = '''
你是一个智能助手，可以帮助用户查询和控制安全设备系统。

【一级页面 (Tab)】
$primaryPages

【二级页面 (按 Tab 分组)】
$secondaryPageList

【全局工具】
$toolList

当用户请求涉及某个页面功能时，请先导航到对应页面。
导航成功后会返回该页面可用的工具列表和当前数据。
【重要】如果返回的数据已满足用户需求，请直接使用该数据回答，无需再次调用查询工具。
只有当用户明确要求"刷新"、"重新查询"或"获取最新数据"时，才调用查询工具。
每次回复只能调用一个工具。

当你任务执行完成后，可以调用 close_chat_panel 来关闭聊天窗。
''';

    return _staticPromptCache!;
  }

  String _buildSystemPrompt() {
    final staticPart = _buildStaticPrompt();

    // 以下为动态部分（每次请求重建）
    final currentRouteName = navigationService.currentRouteName;
    final currentTools = navigationService.getPageTools(currentRouteName ?? '');
    final currentPageTools = StringBuffer();
    for (final tool in currentTools) {
      if (tool.type != local.ToolCallType.dataFun) continue;
      currentPageTools.writeln('- ${tool.name}');
      currentPageTools.writeln('  描述：${tool.description}');
      currentPageTools.writeln('  触发时机：${tool.useWhen}');
      if (tool.paramSchema != null && tool.paramSchema!.isNotEmpty) {
        currentPageTools.writeln('  参数：');
        for (final entry in tool.paramSchema!.entries) {
          final req = entry.value.required ? ' (必填)' : '';
          currentPageTools.writeln('    - ${entry.key}：${entry.value.description}$req');
        }
      } else {
        currentPageTools.writeln('  参数：无');
      }
    }

    final pageState = navigationService.getPageState(currentRouteName ?? '');

    final currentPageStateStr = pageState?.data != null
        ? jsonEncode(pageState?.data)
        : '未知状态';

    return '''$staticPart
APP 当前所在页面为：${currentRouteName ?? '未知页面'}。
- 当前页面可用工具：
${currentPageTools.isEmpty ? '暂无可用工具' : currentPageTools.toString()}；
- 当前页面数据状态为：
${currentPageStateStr}。

现在时间是：${DateTime.now().toIso8601String()}。
''';
  }

  AIService._internal() {
    my_mcp.toolCallService.registerTools();
    _initClient();
  }

  /// 初始化客户端
  void _initClient() {
    final config = AIConfigStore.instance;
    _client = OpenAIClient.withApiKey(
      config.apiKey,
      baseUrl: config.baseUrl,
    );
  }

  /// 重新初始化客户端（配置变更时调用）
  void reinit() {
    _initClient();
  }

  /// 将本地工具转换为 OpenAI API 工具列表
  List<Tool> _buildApiTools() {
    final tools = <Tool>[];

    // 静态工具（跳过 dataCard/formCard）
    final staticTools = my_mcp.toolCallService.staticTools;
    for (final tool in staticTools.values) {
      if (tool.type == local.ToolCallType.dataCard ||
          tool.type == local.ToolCallType.formCard) {
        continue;
      }
      tools.add(_convertToApiTool(tool));
    }

    // 当前页面动态工具（跳过 dataCard/formCard，去重）
    final currentRouteName = navigationService.currentRouteName;
    final currentTools = navigationService.getPageTools(currentRouteName ?? '');
    for (final tool in currentTools) {
      if (tool.type == local.ToolCallType.dataCard ||
          tool.type == local.ToolCallType.formCard) {
        continue;
      }
      if (!tools.any((t) => t.function.name == tool.name)) {
        tools.add(_convertToApiTool(tool));
      }
    }

    return tools;
  }

  /// 将单个本地 ToolCall 转换为 OpenAI Tool
  Tool _convertToApiTool(local.ToolCall localTool) {
    final properties = <String, dynamic>{};
    final requiredFields = <String>[];

    if (localTool.paramSchema != null && localTool.paramSchema!.isNotEmpty) {
      for (final entry in localTool.paramSchema!.entries) {
        final param = entry.value;
        String jsonType;
        switch (param.type) {
          case local.ToolParamType.integer:
            jsonType = 'integer';
          case local.ToolParamType.number:
            jsonType = 'number';
          case local.ToolParamType.boolean:
            jsonType = 'boolean';
          case local.ToolParamType.string:
            jsonType = 'string';
        }
        properties[entry.key] = {
          'type': jsonType,
          'description': param.description,
        };
        if (param.required) {
          requiredFields.add(entry.key);
        }
      }
    }

    return Tool.function(
      name: localTool.name,
      description: '${localTool.description}\n触发时机：${localTool.useWhen}',
      parameters: properties.isNotEmpty
          ? {
              'type': 'object',
              'properties': properties,
              if (requiredFields.isNotEmpty) 'required': requiredFields,
            }
          : null,
    );
  }

  /// 发送对话（流式）- 接收本地消息类型
  /// 使用 OpenAI 原生 tool calling 格式
  Stream<dynamic> chatStream({
    required List<local.ChatMessage> messages,
    bool useTools = true,
  }) async* {
    final compacted = _compactMessages(messages);
    final convertMessages = _convertMessages(compacted);
    final systemPrompt = _buildSystemPrompt();
    final apiTools = useTools ? _buildApiTools() : null;

    AppLogger.d('systemPrompt: $systemPrompt');

    for (final msg in convertMessages) {
      AppLogger.d(msg.toJson());
    }

    try {
      final stream = _client.chat.completions.createStream(
        ChatCompletionCreateRequest(
          model: AIConfigStore.instance.model,
          messages: [ChatMessage.system(systemPrompt), ...convertMessages],
          maxTokens: 1000,
          temperature: 0.3,
          tools: apiTools,
          parallelToolCalls: false,
        ),
      );

      final accumulator = ChatStreamAccumulator();

      await for (final event in stream) {
        accumulator.add(event);
        // 文本内容实时 yield（用于 UI 渐进显示）
        final text = event.textDelta;
        if (text != null && text.isNotEmpty) {
          yield text;
        }
      }

      // 流结束后处理 tool calls
      if (accumulator.hasToolCalls && accumulator.toolCalls.isNotEmpty) {
        final apiToolCall = accumulator.toolCalls.first;
        final localTool = my_mcp.toolCallService.getTool(
          apiToolCall.function.name,
        );

        if (localTool != null) {
          try {
            localTool.updateArguments(apiToolCall.function.argumentsMap);
          } catch (e) {
            yield AIServiceException(
              type: AIServiceErrorType.invalidRequest,
              message: '工具参数解析失败',
              details: e.toString(),
              originalError: e,
            );
            return;
          }
          localTool.id = apiToolCall.id;
          localTool.rawContent = jsonEncode({
            'id': apiToolCall.id,
            'name': apiToolCall.function.name,
            'arguments': apiToolCall.function.arguments,
          });
          yield localTool;
        } else {
          yield AIServiceException(
            type: AIServiceErrorType.invalidRequest,
            message: '工具 ${apiToolCall.function.name} 不存在',
            details: 'Tool not registered',
            originalError: null,
          );
        }
      }
    } catch (e) {
      // 捕获所有异常并转换为用户友好的 AIServiceException
      AppLogger.e('AI 服务调用异常: ', e);
      yield AIErrorHandler.handle(e);
    }
  }

  /// 会话压缩：保留 system 消息 + 最近 N 轮对话
  /// 一轮对话 = 1 条 user + 后续所有 assistant/tool 直到下一个 user
  List<local.ChatMessage> _compactMessages(
    List<local.ChatMessage> messages, {
    int maxTurns = 20,
  }) {
    final systemMsgs = <local.ChatMessage>[];
    final nonSystemMsgs = <local.ChatMessage>[];

    for (final msg in messages) {
      if (msg.role == local.MessageRole.system) {
        systemMsgs.add(msg);
      } else {
        nonSystemMsgs.add(msg);
      }
    }

    if (nonSystemMsgs.length <= maxTurns * 2) return messages;

    // 从后往前，按"对话轮次"分组：遇到 user 时计数+1
    final kept = <local.ChatMessage>[];
    int turnCount = 0;

    for (var i = nonSystemMsgs.length - 1; i >= 0; i--) {
      kept.insert(0, nonSystemMsgs[i]);
      if (nonSystemMsgs[i].role == local.MessageRole.user) {
        turnCount++;
        if (turnCount >= maxTurns) break;
      }
    }

    AppLogger.d(
      '消息压缩: ${messages.length} -> ${systemMsgs.length + kept.length} 条',
    );

    return [...systemMsgs, ...kept];
  }

  /// 将本地消息转换为 OpenAI 消息格式
  List<ChatMessage> _convertMessages(List<local.ChatMessage> localMessages) {
    return localMessages.map((m) {
      if (m.role == local.MessageRole.user) {
        final contentStr = m.content.map((e) => switch (e) {
          local.TextContent(:final text) => text,
          _ => e.toString(),
        }).join();
        return UserMessage(content: UserMessageContent.text(contentStr));
      } else if (m.role == local.MessageRole.tool) {
        final contentStr = m.content.map((e) => switch (e) {
          local.TextContent(:final text) => text,
          _ => e.toString(),
        }).join();
        return ToolMessage(
          content: contentStr,
          toolCallId: m.toolResult?.toolCallId ?? m.toolResult?.toolName ?? '',
        );
      } else if (m.role == local.MessageRole.system) {
        final contentStr = m.content.map((e) => switch (e) {
          local.TextContent(:final text) => text,
          _ => e.toString(),
        }).join();
        return SystemMessage(content: contentStr);
      } else {
        // assistant 消息：检查是否携带 tool call
        if (m.toolCall != null && m.toolCall!.id != null) {
          final contentStr = m.content
              .whereType<local.TextContent>()
              .map((e) => e.text)
              .where((s) => s.isNotEmpty)
              .join();
          return AssistantMessage(
            content: contentStr.isNotEmpty ? contentStr : null,
            toolCalls: [
              ToolCall.functionCall(
                id: m.toolCall!.id!,
                call: FunctionCall.fromMap(
                  name: m.toolCall!.name,
                  arguments: m.toolCall!.arguments ?? {},
                ),
              ),
            ],
          );
        }
        // 普通 assistant 消息（含 dataCard/formCard 序列化为文本）
        final contentList = m.content.map((e) {
          return switch (e) {
            local.TextContent(:final text) => text,
            local.ToolCallContent(:final toolCall) => switch (toolCall.type) {
              local.ToolCallType.dataCard =>
                "[数据卡片：${toolCall.name}, 参数：${jsonEncode(toolCall.arguments)}]",
              local.ToolCallType.formCard =>
                "[表单卡片：${toolCall.name}, 参数：${jsonEncode(toolCall.arguments)}]",
              _ => '',
            },
            _ => e.toString(),
          };
        }).toList();
        return AssistantMessage(content: contentList.join(''));
      }
    }).toList();
  }
}
