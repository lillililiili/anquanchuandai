import '../../components/tech_surface.dart';
import '../../components/field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../hooks/use_chat.dart';
import '../../components/chat_message_bubble.dart';
import '../../components/chat_input_bar.dart';
import '../../components/agent_status_bar.dart';

/// AI 聊天页面
class ChatPage extends HookWidget {
  /// 是否显示 AppBar（false 时只返回 body，不包含 SafeArea）
  final bool showAppBar;

  /// 是否启用输入（false 时禁用发送）
  final bool enabled;

  const ChatPage({super.key, this.showAppBar = true, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final chat = useChat();

    Widget body = Column(
      children: [
        // Agent 状态栏
        AgentStatusBar(
          status: chat.status,
          step: chat.step,
          toolName: chat.currentTool,
        ),
        // 消息列表
        Expanded(
          child: chat.messages.isEmpty
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: _buildEmptyState(context, chat.textController),
                )
              : ListView.builder(
                  reverse: true,
                  controller: chat.scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: chat.messages.length,
                  itemBuilder: (context, index) {
                    final message =
                        chat.messages[chat.messages.length - 1 - index];
                    return ChatMessageBubble(message: message);
                  },
                ),
        ),
        // 输入框
        ChatInputBar(
          controller: chat.textController,
          onSend: chat.sendMessage,
          onStop: chat.stopGeneration,
          isSending: chat.isTyping,
          enabled: enabled,
        ),
      ],
    );

    // 全屏模式：用 SafeArea 包裹
    if (showAppBar) {
      body = SafeArea(child: body);
    }

    // 只返回 body
    if (!showAppBar) {
      return Container(color: Colors.transparent, child: body);
    }

    // 返回完整页面
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'AI 助手',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1F2937),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Color(0xFF6B7280)),
            onPressed: () => _showClearDialog(context, chat.clearMessages),
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    TextEditingController controller,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final prompts = [
      (Icons.health_and_safety_outlined, '告警处置', '跌倒告警如何处理？'),
      (Icons.construction_outlined, '设备排查', '设备离线如何排查？'),
      (Icons.fact_check_outlined, '作业准备', '作业前有哪些安全检查事项？'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primaryContainer, scheme.surface],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '有什么现场问题\n需要帮忙？',
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '从安全常识到设备排查，试着这样问',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(width: 54, height: 64, child: TechAura(orb: true)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final prompt in prompts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TechSurface(
              radius: 16,
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(16),
                child: MotionPress(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      controller.value = TextEditingValue(
                        text: prompt.$3,
                        selection: TextSelection.collapsed(
                          offset: prompt.$3.length,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Icon(
                            prompt.$1,
                            size: 22,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  prompt.$2,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  prompt.$3,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.north_west,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showClearDialog(BuildContext context, VoidCallback onClear) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('确定要清空所有对话记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              onClear();
              Navigator.pop(context);
            },
            child: const Text('确定', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }
}
