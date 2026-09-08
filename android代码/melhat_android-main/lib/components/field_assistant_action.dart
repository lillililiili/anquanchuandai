import 'package:flutter/material.dart';
import '../store/chat_store.dart';

/// An inline entry keeps device figures and playback controls unobstructed.
class FieldAssistantAction extends StatelessWidget {
  const FieldAssistantAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '打开 AI 助手',
    onPressed: () => ChatStore.instance.setChatPanelOpen(true),
    icon: const Icon(Icons.smart_toy_outlined),
  );
}
