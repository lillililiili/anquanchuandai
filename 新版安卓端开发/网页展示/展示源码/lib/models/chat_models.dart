import 'dart:convert';

import 'package:flutter/widgets.dart';

/// 消息角色
enum MessageRole { user, assistant, system, tool }

/// 消息类型
enum MessageType { text, toolCall, toolResult, system }

/// 消息内容项（类型安全的 sealed class）
sealed class ContentItem {
  const ContentItem();

  /// 序列化为 JSON 兼容的动态值
  dynamic toJsonValue();

  /// 从 JSON 值反序列化
  static ContentItem fromJsonValue(dynamic value) {
    if (value is String) return TextContent(value);
    if (value is Map<String, dynamic>) {
      if (value.containsKey('toolName')) {
        return ToolResultContent(ToolResult.fromJson(value));
      }
    }
    return TextContent(value.toString());
  }
}

/// 文本内容
class TextContent extends ContentItem {
  final String text;
  const TextContent(this.text);

  @override
  dynamic toJsonValue() => text;

  @override
  String toString() => text;
}

/// 工具调用内容
class ToolCallContent extends ContentItem {
  final ToolCall toolCall;
  const ToolCallContent(this.toolCall);

  @override
  dynamic toJsonValue() => toolCall.toJson();
}

/// 工具结果内容
class ToolResultContent extends ContentItem {
  final ToolResult toolResult;
  const ToolResultContent(this.toolResult);

  @override
  dynamic toJsonValue() => toolResult.toJson();
}

/// 对话消息
class ChatMessage {
  final String id;
  final MessageRole role;
  final MessageType type;
  final List<ContentItem> content;
  final DateTime timestamp;
  final ToolCall? toolCall;
  final ToolResult? toolResult;
  final bool isStreaming;

  ChatMessage({
    required this.id,
    required this.role,
    required this.type,
    required this.content,
    required this.timestamp,
    this.toolCall,
    this.toolResult,
    this.isStreaming = false,
  });

  /// 从 JSON 创建
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final contentList = (json['content'] as List<dynamic>)
        .map((e) => ContentItem.fromJsonValue(e))
        .toList();
    return ChatMessage(
      id: json['id'] as String,
      role: MessageRole.values.firstWhere((r) => r.name == json['role']),
      type: MessageType.values.firstWhere((t) => t.name == json['type']),
      content: contentList,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isStreaming: json['isStreaming'] as bool? ?? false,
    );
  }

  /// 转为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'type': type.name,
      'content': content.map((e) => e.toJsonValue()).toList(),
      'timestamp': timestamp.toIso8601String(),
      'isStreaming': isStreaming,
    };
  }

  @override
  String toString() {
    return 'ChatMessage(role: $role, type: $type, content: $content)';
  }
}

/// 工具调用
enum ToolCallType { dataFun, dataCard, formCard, action }

/// Agent 执行状态
enum AgentStatus { idle, loading, ready, success, error }

/// Agent 执行步骤
enum AgentStep {
  thinking, // AI 思考中
  navigating, // 正在导航
  waitingPage, // 等待页面响应
  executingTool, // 执行工具
  rendering, // 渲染结果
}

/// Agent 执行状态实体
class AgentExecutionState {
  final AgentStep step;
  final AgentStatus status;
  final int? progress; // 0-100
  final String? error;

  const AgentExecutionState({
    required this.step,
    this.status = AgentStatus.idle,
    this.progress,
    this.error,
  });

  AgentExecutionState copyWith({
    AgentStep? step,
    AgentStatus? status,
    int? progress,
    String? error,
  }) {
    return AgentExecutionState(
      step: step ?? this.step,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}

enum McpToolResultType { text, json, card }

/// 工具参数类型
enum ToolParamType { string, integer, number, boolean }

/// 工具参数定义
class ToolParam {
  final ToolParamType type;
  final String description;
  final bool required;

  const ToolParam({
    this.type = ToolParamType.string,
    required this.description,
    this.required = false,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'description': description,
    'required': required,
  };
}

class ToolCall {
  String? id;
  final String name;
  final String description;
  final String useWhen;
  final ToolCallType type;
  final String resultType;
  String? rawContent;
  Future<dynamic> Function(Map<String, dynamic>?)? applyCall;
  Widget Function(Map<String, dynamic>?)? applyRender;

  /// 参数定义（不可变，用于 AI prompt 构建和 API 工具转换）
  final Map<String, ToolParam>? paramSchema;

  /// 运行时参数值（由 AI 返回或手动设置，每次调用后更新）
  Map<String, dynamic>? arguments;

  ToolCall({
    this.id,
    required this.name,
    required this.description,
    required this.useWhen,
    required this.type,
    required this.resultType,
    this.rawContent,
    this.applyCall,
    this.applyRender,
    this.paramSchema,
    this.arguments,
  });

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'description': description,
      'useWhen': useWhen,
      'type': type.toString().split('.').last,
      'resultType': resultType,
      'paramSchema': paramSchema?.map((k, v) => MapEntry(k, v.toJson())),
      'arguments': arguments,
    };
  }

  String toMessage() {
    if (rawContent != null) {
      return rawContent!;
    }

    return '''<toolcall> {"name": "$name", "arguments": ${jsonEncode(arguments ?? {})} } </toolcall>''';
  }

  void updateArguments(Map<String, dynamic> newArgs) {
    arguments = newArgs;
  }

  ToolCall copy() {
    return ToolCall(
      id: id,
      name: name,
      description: description,
      useWhen: useWhen,
      type: type,
      resultType: resultType,
      rawContent: rawContent,
      applyCall: applyCall,
      applyRender: applyRender,
      paramSchema: paramSchema != null
          ? Map<String, ToolParam>.from(paramSchema!)
          : null,
      arguments: arguments != null
          ? Map<String, dynamic>.from(arguments!)
          : null,
    );
  }
}

/// 工具返回结果
class ToolResult {
  final String toolName;
  final String toolCallId;
  final dynamic result;
  final String? error;

  ToolResult({
    required this.toolName,
    String? toolCallId,
    required this.result,
    this.error,
  }) : toolCallId = toolCallId ?? toolName;

  factory ToolResult.fromJson(Map<String, dynamic> json) {
    return ToolResult(
      toolName: json['toolName'] as String,
      toolCallId: json['toolCallId'] as String?,
      result: json['result'],
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'toolName': toolName,
      'toolCallId': toolCallId,
      'result': result,
      'error': error,
    };
  }
}

/// 对话会话
class ChatSession {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
  });

  ChatSession copyWith({List<ChatMessage>? messages, String? title}) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// 从 JSON 创建
  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: (json['messages'] as List)
          .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// 转为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((m) => m.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
