/// 语音识别结果模型

/// 识别状态
enum RecognizerState {
  /// 未初始化
  uninitialized,

  /// 初始化中
  initializing,

  /// 就绪（空闲）
  ready,

  /// 正在录音识别
  listening,

  /// 处理中
  processing,

  /// 错误
  error,
}

/// 语音识别结果
class RecognitionResult {
  /// 识别到的文本
  final String text;

  /// 是否为最终结果
  final bool isFinal;

  /// 是否为部分结果（流式识别中间结果）
  final bool isPartial;

  /// 识别耗时（毫秒）
  final int? durationMs;

  /// 音频时长（毫秒）
  final int? audioDurationMs;

  const RecognitionResult({
    required this.text,
    this.isFinal = false,
    this.isPartial = false,
    this.durationMs,
    this.audioDurationMs,
  });

  /// 空结果
  static const empty = RecognitionResult(text: '', isFinal: true);

  /// 是否为空
  bool get isEmpty => text.trim().isEmpty;

  /// 是否不为空
  bool get isNotEmpty => text.trim().isNotEmpty;

  @override
  String toString() => 'RecognitionResult(text: $text, isFinal: $isFinal)';

  RecognitionResult copyWith({
    String? text,
    bool? isFinal,
    bool? isPartial,
    int? durationMs,
    int? audioDurationMs,
  }) {
    return RecognitionResult(
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
      isPartial: isPartial ?? this.isPartial,
      durationMs: durationMs ?? this.durationMs,
      audioDurationMs: audioDurationMs ?? this.audioDurationMs,
    );
  }
}

/// 识别回调类型
typedef RecognitionCallback = void Function(RecognitionResult result);

/// 音量级别回调
typedef SoundLevelCallback = void Function(double level);

/// 状态变化回调
typedef StateCallback = void Function(RecognizerState state);
