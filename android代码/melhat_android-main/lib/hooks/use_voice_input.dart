import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../service/speech_service.dart';
import '../utils/app_logger.dart';

enum VoiceInputState { idle, recording, processing }

typedef VoiceInputController = ({
  VoiceInputState state,
  double audioLevel,
  Future<void> Function() startRecording,
  Future<void> Function() stopRecording,
  VoidCallback cancelRecording,
});

/// 语音输入 Hook — 管理长按录音的状态机
VoiceInputController useVoiceInput({
  required TextEditingController textController,
}) {
  final state = useState(VoiceInputState.idle);
  final audioLevel = useState(0.0);
  final speechService = useRef(SpeechService.instance);

  // 开始录音
  Future<void> startRecording() async {
    final hasPermission = await speechService.value.requestPermission();
    if (!hasPermission) {
      AppLogger.w('麦克风权限被拒绝');
      return;
    }

    state.value = VoiceInputState.recording;
    audioLevel.value = 0;

    await speechService.value.startRecording(
      onAudioLevel: (level) {
        audioLevel.value = level;
      },
    );
  }

  // 停止录音并识别
  Future<void> stopRecording() async {
    if (state.value != VoiceInputState.recording) return;

    state.value = VoiceInputState.processing;

    try {
      final result = await speechService.value.stopRecording();
      if (result != null && result.isNotEmpty) {
        final currentText = textController.text;
        final newText = currentText.isEmpty ? result : '$currentText$result';
        textController.text = newText;
        textController.selection = TextSelection.fromPosition(
          TextPosition(offset: newText.length),
        );
        AppLogger.i('语音识别完成: $result');
      }
    } catch (e) {
      AppLogger.e('语音识别失败: $e');
    } finally {
      state.value = VoiceInputState.idle;
      audioLevel.value = 0;
    }
  }

  // 取消录音
  void cancelRecording() {
    speechService.value.cancel();
    state.value = VoiceInputState.idle;
    audioLevel.value = 0;
  }

  useEffect(() {
    return () {
      speechService.value.cancel();
    };
  }, []);

  return (
    state: state.value,
    audioLevel: audioLevel.value,
    startRecording: startRecording,
    stopRecording: stopRecording,
    cancelRecording: cancelRecording,
  );
}
