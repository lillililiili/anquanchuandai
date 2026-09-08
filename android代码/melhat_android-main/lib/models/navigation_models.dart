import 'package:rolling_intelligence_headband/models/chat_models.dart';

/// 页面状态
/// 由 PageAgentController.getSnapshot() 生成，包含页面完整状态
class PageState {
  final String routeName;
  Map<String, dynamic> data;
  final List<ToolCall> tools;
  final String? greetingMessage;
  final AgentStatus status;
  final DateTime? mountedAt;

  PageState({
    required this.routeName,
    this.data = const {},
    required this.tools,
    this.greetingMessage,
    required this.status,
    this.mountedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'routeName': routeName,
      'data': data,
      'tools': tools.map((t) => t.toJson()).toList(),
      'greetingMessage': greetingMessage,
      'status': status.name,
      'mountedAt': mountedAt?.toIso8601String(),
    };
  }
}
