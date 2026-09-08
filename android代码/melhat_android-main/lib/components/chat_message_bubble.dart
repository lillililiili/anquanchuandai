import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../models/chat_models.dart';

/// 可展开/收起的工具结果组件
class _ExpandableToolResult extends StatefulWidget {
  final ToolResult result;

  const _ExpandableToolResult({required this.result});

  @override
  State<_ExpandableToolResult> createState() => _ExpandableToolResultState();
}

class _ExpandableToolResultState extends State<_ExpandableToolResult> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final isSuccess = result.error == null;
    final themeColor = isSuccess
        ? const Color(0xFF10B981)
        : const Color(0xFFDC2626);
    final iconData = isSuccess ? Icons.check_circle : Icons.error;
    final hasContent = result.error != null || result.result != null;

    return GestureDetector(
      onTap: hasContent
          ? () => setState(() => _isExpanded = !_isExpanded)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: themeColor.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: themeColor.withAlpha(50)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconData, size: 14, color: themeColor),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    isSuccess
                        ? '${result.toolName}执行成功'
                        : '${result.toolName}执行失败',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: themeColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasContent) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: themeColor,
                  ),
                ],
              ],
            ),
            if (_isExpanded && result.error != null) ...[
              const SizedBox(height: 4),
              Text(
                result.error!,
                style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)),
              ),
            ],
            if (_isExpanded && result.result != null) ...[
              const SizedBox(height: 4),
              Text(
                '${result.result}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 聊天消息气泡组件
class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    // system 消息：居中显示，小字，灰底白字
    if (message.role == MessageRole.tool ||
        message.role == MessageRole.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Container(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildContentWidgets(false, isSystem: true),
            ),
          ),
        ),
      );
    }

    final isUser = message.role == MessageRole.user;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            // AI 头像
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0x1410B981),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.smart_toy_outlined,
                size: 20,
                color: Color(0xFF10B981),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // 消息内容
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? const Color(0xFF10B981) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ..._buildContentWidgets(isUser),
                  if (message.isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isUser
                                    ? Colors.white.withOpacity(0.6)
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '正在输入...',
                            style: TextStyle(
                              fontSize: 12,
                              color: isUser
                                  ? Colors.white.withOpacity(0.8)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            // 用户头像
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0x143B82F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.person_outline,
                size: 20,
                color: Color(0xFF3B82F6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 构建 content 列表的 Widget
  /// 将连续的 String 合并渲染，ToolCall/ToolResult 单独渲染
  List<Widget> _buildContentWidgets(bool isUser, {bool isSystem = false}) {
    final widgets = <Widget>[];
    final stringBuffer = StringBuffer();

    /// 主要针对系统消息，存在toolResult时，直接显示
    if (message.toolResult != null) {
      // 如果消息中包含 toolResult，优先渲染 toolResult
      widgets.add(
        _buildToolResultWidget(message.toolResult!, isSystem: isSystem),
      );
      return widgets;
    }

    for (final item in message.content) {
      switch (item) {
        case TextContent(:final text):
          stringBuffer.write(text);
        case ToolCallContent(:final toolCall):
          // 先处理之前累积的文本
          if (stringBuffer.isNotEmpty) {
            widgets.add(
              _buildTextWidget(
                stringBuffer.toString(),
                isUser,
                isSystem: isSystem,
              ),
            );
            stringBuffer.clear();
          }
          widgets.add(_buildToolCallWidget(toolCall, isSystem: isSystem));
        case ToolResultContent(:final toolResult):
          // 先处理之前累积的文本
          if (stringBuffer.isNotEmpty) {
            widgets.add(
              _buildTextWidget(
                stringBuffer.toString(),
                isUser,
                isSystem: isSystem,
              ),
            );
            stringBuffer.clear();
          }
          widgets.add(_buildToolResultWidget(toolResult, isSystem: isSystem));
      }
    }

    // 处理最后剩余的 String
    if (stringBuffer.isNotEmpty) {
      widgets.add(
        _buildTextWidget(stringBuffer.toString(), isUser, isSystem: isSystem),
      );
    }

    return widgets;
  }

  /// 构建文本 Widget
  /// isUser=true 时直接用 Text 渲染，否则用 Markdown 渲染
  Widget _buildTextWidget(String text, bool isUser, {bool isSystem = false}) {
    if (isUser) {
      return Text(
        text,
        style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.5),
      );
    }

    if (isSystem) {
      return Text(
        text,
        style: const TextStyle(fontSize: 12, color: Colors.white, height: 1.4),
      );
    }

    return MarkdownBody(data: text);
  }

  /// 构建 ToolResult Widget
  Widget _buildToolResultWidget(ToolResult result, {bool isSystem = false}) {
    return _ExpandableToolResult(result: result);
  }

  /// 构建 ToolCall Widget
  Widget _buildToolCallWidget(ToolCall toolCall, {bool isSystem = false}) {
    if (toolCall.applyRender != null) {
      return toolCall.applyRender!.call(toolCall.arguments);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.build, size: 16, color: Color(0xFF3B82F6)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  toolCall.description,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),
          if (toolCall.arguments != null && toolCall.arguments!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${toolCall.arguments}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
