import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_hooks/signals_hooks.dart';
import '../models/chat_models.dart';
import '../utils/app_logger.dart';

/// 聊天 Store - 单会话，支持本地持久化
class ChatStore {
  static final ChatStore instance = ChatStore._internal();
  static const _storageKey = 'chat_messages';
  static const _maxStoredMessages = 100;

  // 消息列表
  final _messagesSignal = Signal<List<ChatMessage>>([]);

  // 状态
  final _isTypingSignal = Signal(false);
  final _isProcessingSignal = Signal(false);
  final _isChatPanelOpenSignal = Signal(false);

  // Computed
  static final messages = computed(() => instance._messagesSignal.value);
  static final isTyping = computed(() => instance._isTypingSignal.value);
  static final isProcessing = computed(
    () => instance._isProcessingSignal.value,
  );
  static final isChatPanelOpen = computed(
    () => instance._isChatPanelOpenSignal.value,
  );

  ChatStore._internal();

  /// 从本地存储加载消息
  Future<void> loadMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_storageKey);
      if (jsonStr == null || jsonStr.isEmpty) return;

      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final loaded = jsonList
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
      _messagesSignal.value = loaded;
      AppLogger.i('已加载 ${loaded.length} 条历史消息');
    } catch (e) {
      AppLogger.e('加载聊天消息失败: $e');
    }
  }

  /// 持久化消息到本地存储
  Future<void> _saveMessages() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 只保存最近 N 条，避免超出 SharedPreferences 限制
      final toSave = _messagesSignal.value;
      final trimmed = toSave.length > _maxStoredMessages
          ? toSave.sublist(toSave.length - _maxStoredMessages)
          : toSave;
      final jsonList = trimmed.map((m) => m.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      AppLogger.e('保存聊天消息失败: $e');
    }
  }

  /// 清空会话
  void clearMessages() {
    _messagesSignal.value = [];
    _saveMessages();
  }

  /// 添加用户消息
  void addUserMessage(String content) {
    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      type: MessageType.text,
      content: [TextContent(content)],
      timestamp: DateTime.now(),
    );
    _messagesSignal.value = [..._messagesSignal.value, message];
    _saveMessages();
  }

  void addMessage(ChatMessage message) {
    _messagesSignal.value = [..._messagesSignal.value, message];
    _saveMessages();
  }

  /// 添加助手消息
  void addAssistantMessage({
    required String content,
    bool isStreaming = false,
  }) {
    final message = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      type: MessageType.text,
      content: content.isEmpty ? [] : [TextContent(content)],
      timestamp: DateTime.now(),
      isStreaming: isStreaming,
    );
    _messagesSignal.value = [..._messagesSignal.value, message];
  }

  /// 添加系统消息
  void addSystemMessage({required ChatMessage message}) {
    _messagesSignal.value = [..._messagesSignal.value, message];
    _saveMessages();
  }

  /// 更新最后一条助手消息（流式响应）
  void updateLastAssistantMessage(ContentItem content) {
    final messages = List<ChatMessage>.from(_messagesSignal.value);
    final lastIndex = messages.lastIndexWhere(
      (m) => m.role == MessageRole.assistant,
    );

    if (lastIndex != -1) {
      final old = messages[lastIndex];
      messages[lastIndex] = ChatMessage(
        id: old.id,
        role: old.role,
        type: old.type,
        content: [...old.content, content],
        timestamp: old.timestamp,
        isStreaming: true,
      );
      _messagesSignal.value = messages;
    }
  }

  /// 完成最后一条消息
  void finishLastMessage() {
    final messages = List<ChatMessage>.from(_messagesSignal.value);
    final lastIndex = messages.lastIndexWhere(
      (m) => m.role == MessageRole.assistant,
    );

    if (lastIndex != -1) {
      final old = messages[lastIndex];
      messages[lastIndex] = ChatMessage(
        id: old.id,
        role: old.role,
        type: old.type,
        content: old.content,
        timestamp: old.timestamp,
        toolCall: old.toolCall,
        isStreaming: false,
      );
      _messagesSignal.value = messages;
      _saveMessages();
    }
  }

  /// 设置最后一条助手消息的 tool call（用于历史重建）
  void setLastAssistantMessageToolCall(ToolCall toolCall) {
    final messages = List<ChatMessage>.from(_messagesSignal.value);
    final lastIndex = messages.lastIndexWhere(
      (m) => m.role == MessageRole.assistant,
    );

    if (lastIndex != -1) {
      final old = messages[lastIndex];
      messages[lastIndex] = ChatMessage(
        id: old.id,
        role: old.role,
        type: MessageType.toolCall,
        content: old.content,
        timestamp: old.timestamp,
        toolCall: toolCall,
        isStreaming: old.isStreaming,
      );
      _messagesSignal.value = messages;
      _saveMessages();
    }
  }

  /// 设置正在输入状态
  void setTyping(bool typing) {
    _isTypingSignal.value = typing;
  }

  /// 设置处理中状态
  void setProcessing(bool processing) {
    _isProcessingSignal.value = processing;
  }

  /// 设置聊天面板展开状态
  void setChatPanelOpen(bool open) {
    _isChatPanelOpenSignal.value = open;
  }
}

// Hooks
List<ChatMessage> useChatMessages() => useSignalValue(ChatStore.messages);
bool useChatIsTyping() => useSignalValue(ChatStore.isTyping);
bool useChatPanelOpen() => useSignalValue(ChatStore.isChatPanelOpen);
