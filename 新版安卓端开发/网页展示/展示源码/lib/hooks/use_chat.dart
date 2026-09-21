import 'dart:async';
import 'dart:convert';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:rolling_intelligence_headband/models/chat_models.dart';
import 'package:rolling_intelligence_headband/service/mcp_tool.dart';
import 'package:rolling_intelligence_headband/service/ai_exceptions.dart';
import 'package:rolling_intelligence_headband/utils/app_logger.dart';
import 'package:signals_hooks/signals_hooks.dart';
import 'package:flutter/material.dart';
import '../store/chat_store.dart';
import '../service/ai_agent.dart';
import '../models/chat_models.dart' as local;

/// 聊天控制器
typedef ChatController = ({
  List<local.ChatMessage> messages,
  bool isTyping,
  TextEditingController textController,
  ScrollController scrollController,
  Future<void> Function({String? content, local.ChatMessage? message})
  sendMessage,
  void Function() stopGeneration,
  void Function() clearMessages,
  AgentStatus status,
  AgentStep? step,
  String? currentTool,
});

/// 聊天 Hook
ChatController useChat() {
  final store = ChatStore.instance;

  // Signals
  final messages = useSignalValue(ChatStore.messages);
  final isTyping = useSignalValue(ChatStore.isTyping);

  // Controllers
  final textController = useTextEditingController();
  final scrollController = useScrollController();

  // 本地状态
  final isSending = useState(false);

  final status = useState(AgentStatus.idle);
  final step = useState<AgentStep?>(null);
  final currentToolName = useState<String?>(null);

  final context = useContext();

  // 流式订阅引用（用于取消）
  final streamSub = useRef<StreamSubscription<dynamic>?>(null);

  // 递归深度追踪（防止工具调用无限循环）
  final toolRoundCount = useRef(0);
  const maxToolRounds = 5;

  // 停止生成
  void stopGeneration() {
    streamSub.value?.cancel();
    streamSub.value = null;
    store.finishLastMessage();
    store.setTyping(false);
    isSending.value = false;
    toolRoundCount.value = 0;
    status.value = AgentStatus.idle;
    step.value = null;
    currentToolName.value = null;
  }

  // 发送消息
  Future<void> sendMessage({
    String? content,
    local.ChatMessage? message,
  }) async {
    isSending.value = true;
    status.value = AgentStatus.loading;
    step.value = AgentStep.thinking;

    try {
      // 添加用户消息
      if (content != null) {
        store.addUserMessage(content);
      }
      if (message != null) {
        AppLogger.i("发送消息：${message.toJson()}");
        store.addMessage(message);
      }
      store.setTyping(true);

      local.ToolCall? toolCall;
      Exception? streamError;

      // 调用 AI 服务
      final service = AIService.instance;
      final stream = service.chatStream(messages: ChatStore.messages.value);

      // 添加空的助手消息
      store.addAssistantMessage(content: '', isStreaming: true);

      // 处理流式响应（可取消）
      final completer = Completer<void>();
      streamSub.value = stream.listen(
        (chunk) {
          if (chunk is String && chunk.isNotEmpty) {
            store.updateLastAssistantMessage(local.TextContent(chunk));
          }
          if (chunk is AIServiceException) {
            AppLogger.e('AI 服务返回错误: ', chunk);
            streamError = chunk;
            store.updateLastAssistantMessage(
              local.TextContent('\n\n⚠️ ${chunk.message}'),
            );
          } else if (chunk is Exception) {
            AppLogger.e('AI 服务返回错误: ', chunk);
            streamError = chunk;
            store.updateLastAssistantMessage(
              local.TextContent('\n\n⚠️ 发生未知错误，请稍后重试'),
            );
          }
          if (chunk is local.ToolCall) {
            if (chunk.type != local.ToolCallType.dataCard &&
                chunk.type != local.ToolCallType.formCard) {
              toolCall = chunk;
              step.value = AgentStep.executingTool;
              currentToolName.value = chunk.description;
            }
            store.updateLastAssistantMessage(local.ToolCallContent(chunk));
            store.setLastAssistantMessageToolCall(chunk);
          }
          if (scrollController.hasClients) {
            scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          }
        },
        onDone: () => completer.complete(),
        onError: (e) => completer.completeError(e),
      );
      await completer.future;

      store.finishLastMessage();
      store.setTyping(false);
      step.value = AgentStep.rendering;

      // AI 无工具调用，重置轮次计数
      if (toolCall == null) {
        toolRoundCount.value = 0;
        status.value = AgentStatus.idle;
        step.value = null;
        currentToolName.value = null;
      }

      // 处理流式错误
      if (streamError != null) {
        if (!context.mounted) return;
        final error = streamError!;

        // 对于不可恢复的错误（额度、网络、认证等），直接停止，不再重试
        if (error is AIServiceException) {
          AppLogger.e('AI 服务错误 (${error.type.name}): ${error.message}');
          // 错误已在流式输出时展示给用户，这里只需停止
          return;
        }

        // 其他未知错误，发送给 AI 让其感知
        final errorMessage = local.ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: local.MessageRole.tool,
          type: local.MessageType.toolResult,
          content: [local.TextContent('AI 服务返回错误，请稍后重试')],
          timestamp: DateTime.now(),
        );
        sendMessage(message: errorMessage);
        return;
      }

      if (toolCall != null) {
        // 检查递归深度
        toolRoundCount.value++;
        if (toolRoundCount.value > maxToolRounds) {
          AppLogger.w('工具调用轮次已达上限 ($maxToolRounds)，强制终止');
          store.addAssistantMessage(
            content: '工具调用轮次过多，已自动停止。请简化您的请求后重试。',
          );
          toolRoundCount.value = 0;
          return;
        }

        final tc = toolCall!;
        dynamic toolResult;
        try {
          toolResult = await tc.applyCall?.call(tc.arguments);
        } catch (toolError) {
          AppLogger.e('工具 ${tc.name} 执行失败: ', toolError);
          if (!context.mounted) return;
          final errorMessage = local.ChatMessage(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            role: local.MessageRole.tool,
            type: local.MessageType.toolResult,
            content: [local.TextContent('执行出错：$toolError，请根据错误信息调整后重试')],
            timestamp: DateTime.now(),
            toolResult: local.ToolResult(
              toolCallId: tc.id ?? tc.name,
              toolName: tc.name,
              result: {'error': toolError.toString()},
              error: toolError.toString(),
            ),
          );
          sendMessage(message: errorMessage);
          status.value = AgentStatus.idle;
          return;
        }
        if (!context.mounted) return;
        final toolResultMessage = local.ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: local.MessageRole.tool,
          type: local.MessageType.toolResult,
          content: [local.TextContent(jsonEncode(toolResult))],
          timestamp: DateTime.now(),
          toolResult: local.ToolResult(
            toolCallId: tc.id ?? tc.name,
            toolName: tc.name,
            result: toolResult,
          ),
        );

        sendMessage(message: toolResultMessage);
        status.value = AgentStatus.idle;
        step.value = null;
        currentToolName.value = null;
      }
    } catch (e, t) {
      AppLogger.e('发送消息失败: ', e, t);
      if (context.mounted) {
        final aiError = AIErrorHandler.handle(e);
        store.updateLastAssistantMessage(local.TextContent('\n\n⚠️ ${aiError.message}'));
        store.finishLastMessage();
        store.setTyping(false);
      }
    } finally {
      if (context.mounted) {
        isSending.value = false;
        textController.clear();
      }
    }
  }

  // 清空消息
  void clearMessages() {
    store.clearMessages();
  }

  // 绑定表单提交回调
  useEffect(() {
    toolCallService.onFormSubmit = (toolName, formData) async {
      final toolResultMessage = local.ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: local.MessageRole.tool,
        type: local.MessageType.toolResult,
        content: [local.TextContent(jsonEncode(formData))],
        timestamp: DateTime.now(),
        toolResult: local.ToolResult(toolName: toolName, result: formData),
      );
      sendMessage(message: toolResultMessage);
    };
    return () {
      toolCallService.onFormSubmit = null;
    };
  }, []);

  // 滚动到底部
  useEffect(() {
    if (messages.isNotEmpty && scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
    return null;
  }, [messages.length]);

  return (
    messages: messages,
    isTyping: isTyping,
    textController: textController,
    scrollController: scrollController,
    sendMessage: sendMessage,
    stopGeneration: stopGeneration,
    clearMessages: clearMessages,
    status: status.value,
    step: step.value,
    currentTool: currentToolName.value,
  );
}
