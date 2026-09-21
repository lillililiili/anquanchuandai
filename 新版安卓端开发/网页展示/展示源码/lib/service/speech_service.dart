import 'dart:async';
import 'dart:typed_data';

import 'package:voice_recognizer/voice_recognizer.dart';

import '../utils/app_logger.dart';

/// 语音识别服务 — 基于 voice_recognizer 包的离线语音识别
///
/// 使用 Paraformer 模型进行本地离线识别，支持流式识别（边录边识别）
class SpeechService {
  static final SpeechService instance = SpeechService._internal();

  // 录音服务
  final AudioRecorderService _recorder = AudioRecorderService(
    sampleRate: 16000,
    numChannels: 1,
  );

  // 识别器
  SimpleParaformerRecognizer? _recognizer;

  // 注册中心
  final VoiceRecognizerRegistry _registry = VoiceRecognizerRegistry.instance;

  // 识别结果
  String _recognizedText = '';

  SpeechService._internal();

  /// 请求录音权限
  Future<bool> requestPermission() async {
    return await _recorder.checkPermission();
  }

  /// 开始录音
  Future<void> startRecording({
    void Function(double level)? onAudioLevel,
  }) async {
    _recognizedText = '';

    // 确保识别器已初始化
    if (!_registry.isInitialized) {
      AppLogger.i('初始化语音识别服务...');
      final success = await _registry.ensureInitialized();
      if (!success) {
        AppLogger.e('语音识别服务初始化失败: ${_registry.errorMessage}');
        return;
      }
    }

    // 获取识别器实例
    _recognizer = _registry.recognizer;
    if (_recognizer == null) {
      AppLogger.e('无法获取识别器实例');
      return;
    }

    // 开始识别监听
    _recognizer!.startListening();

    // 开始录音并实时处理音频数据
    final success = await _recorder.startRecording(
      onAudioData: _processAudioData,
    );

    if (!success) {
      AppLogger.e('启动录音失败: ${_recorder.errorMessage}');
      return;
    }

    AppLogger.i('录音已开始，实时识别中...');

    // 监听音量变化
    if (onAudioLevel != null) {
      _startAudioLevelStream(onAudioLevel);
    }
  }

  /// 处理实时音频数据
  void _processAudioData(Uint8List pcmData) {
    if (_recognizer != null && _recognizer!.isListening) {
      _recognizer!.processAudioData(pcmData);
    }
  }

  // 音量监听定时器
  Timer? _levelTimer;

  void _startAudioLevelStream(void Function(double level) onLevel) {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) {
        if (_recorder.isRecording) {
          onLevel(_recorder.amplitude);
        }
      },
    );
  }

  /// 停止录音并获取识别结果
  Future<String?> stopRecording() async {
    _levelTimer?.cancel();

    try {
      // 停止录音
      final result = await _recorder.stopRecording();
      AppLogger.i('录音完成，时长: ${result.durationSeconds.toStringAsFixed(2)}s');

      // 获取识别结果
      if (_recognizer != null && _recognizer!.isListening) {
        final recognitionResult = await _recognizer!.stopListening();
        _recognizedText = recognitionResult.text;

        if (_recognizedText.isNotEmpty) {
          AppLogger.i('语音识别完成: $_recognizedText');
          return _recognizedText;
        } else {
          AppLogger.w('未识别到语音内容');
          return null;
        }
      }

      return null;
    } catch (e) {
      AppLogger.e('停止录音失败: $e');
      return null;
    }
  }

  /// 取消录音
  Future<void> cancel() async {
    _levelTimer?.cancel();

    try {
      _recorder.cancelRecording();
      _recognizer?.cancelListening();
      AppLogger.i('录音已取消');
    } catch (e) {
      AppLogger.e('取消录音失败: $e');
    }
  }

  /// 获取当前识别状态
  RecognizerState? get recognizerState => _recognizer?.state;

  /// 获取实时识别文本（边录边识别的中间结果）
  String get partialText => _recognizer?.recognizedText ?? '';

  /// 是否正在录音
  bool get isRecording => _recorder.isRecording;

  /// 当前音量级别
  double get amplitude => _recorder.amplitude;

  void dispose() {
    _levelTimer?.cancel();
    _recorder.dispose();
    // 注意：不要 dispose 识别器，因为它是全局共享的
  }
}
