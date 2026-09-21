import 'tech_surface.dart';
import 'field_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:voice_recognizer/voice_recognizer.dart';
import 'package:rolling_intelligence_headband/models/chat_models.dart';

/// 输入与语音共用草稿；语音模型在用户展开入口后按需准备。
class ChatInputBar extends HookWidget {
  final TextEditingController controller;
  final Future<void> Function({String? content, ChatMessage? message}) onSend;
  final VoidCallback? onStop;
  final bool isSending;
  final bool enabled;
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.onStop,
    this.isSending = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    useListenable(controller);
    final voiceOpen = useState(false);
    final scheme = Theme.of(context).colorScheme;
    final canSend = enabled && controller.text.trim().isNotEmpty;
    void onVoiceResult(String result) {
      if (result.isEmpty) return;
      final text = '${controller.text}$result';
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      color: scheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TechSurface(
            radius: 20,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    enabled: true,
                    minLines: 1,
                    maxLines: 3,
                    style: TextStyle(fontSize: 14, color: scheme.onSurface),
                    decoration: InputDecoration(
                      hintText: enabled ? '输入你的问题…' : '可先编辑问题，配置后发送',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onSubmitted: (_) {
                      if (canSend && !isSending)
                        onSend(content: controller.text.trim());
                    },
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: enabled
                                ? () => voiceOpen.value = !voiceOpen.value
                                : null,
                            icon: Icon(
                              voiceOpen.value
                                  ? Icons.keyboard_outlined
                                  : Icons.mic_none,
                              size: 19,
                            ),
                            label: Text(voiceOpen.value ? '键盘输入' : '语音输入'),
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.onSurfaceVariant,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (controller.text.isNotEmpty)
                        IconButton(
                          tooltip: '清空输入',
                          onPressed: controller.clear,
                          icon: const Icon(Icons.close, size: 19),
                        ),
                      IconButton.filled(
                        tooltip: isSending ? '停止生成' : '发送消息',
                        onPressed: isSending
                            ? onStop
                            : canSend
                            ? () => onSend(content: controller.text.trim())
                            : null,
                        style: IconButton.styleFrom(
                          backgroundColor: isSending
                              ? scheme.error
                              : scheme.primary,
                          foregroundColor: isSending
                              ? scheme.onError
                              : scheme.onSurface,
                        ),
                        icon: Icon(
                          isSending
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (voiceOpen.value && enabled)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: VoiceRecordButton(
                onResult: onVoiceResult,
                themeColor: scheme.primary,
                size: 40,
                maxDuration: 30,
                showDuration: true,
                showRipple: !MotionPolicy.reduced(context),
              ),
            ),
        ],
      ),
    );
  }
}
