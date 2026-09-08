import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../models/recognition_result.dart';

/// Paraformer 流式语音识别服务
///
/// 基于 sherpa_onnx 实现的流式语音识别，支持边录边识别
class ParaformerRecognizerService extends ChangeNotifier {
  /// 本地模型目录路径（从云端下载后使用）
  final String? modelLocalPath;

  /// 模型文件名
  final String modelFileName;

  /// 词表文件名
  final String tokensFileName;

  /// 采样率
  final int sampleRate;

  /// 识别线程数
  final int numThreads;

  /// 最大录音时长（秒）
  final int maxDurationSeconds;

  // 状态
  RecognizerState _state = RecognizerState.uninitialized;
  String _errorMessage = '';
  String _recognizedText = '';
  String _partialText = '';
  double _soundLevel = 0.0;

  // sherpa_onnx 实例
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;

  // 模型文件路径
  String? _modelDir;

  /// 当前状态
  RecognizerState get state => _state;

  /// 错误信息
  String get errorMessage => _errorMessage;

  /// 最终识别文本
  String get recognizedText => _recognizedText;

  /// 部分识别文本（实时）
  String get partialText => _partialText;

  /// 完整文本（最终 + 部分）
  String get fullText => _recognizedText + _partialText;

  /// 音量级别 (0.0 - 1.0)
  double get soundLevel => _soundLevel;

  /// 是否已初始化
  bool get isInitialized =>
      _state != RecognizerState.uninitialized &&
      _state != RecognizerState.initializing &&
      _state != RecognizerState.error;

  /// 是否正在监听
  bool get isListening => _state == RecognizerState.listening;

  ParaformerRecognizerService({
    required this.modelLocalPath,
    this.modelFileName = 'model.int8.onnx',
    this.tokensFileName = 'tokens.txt',
    this.sampleRate = 16000,
    this.numThreads = 1,
    this.maxDurationSeconds = 10,
  });

  /// 初始化识别器
  Future<bool> initialize() async {
    if (_state == RecognizerState.initializing) return false;
    if (isInitialized) return true;

    _updateState(RecognizerState.initializing);

    try {
      // 初始化 sherpa_onnx 绑定
      sherpa.initBindings();

      // 准备模型文件
      _modelDir = await _prepareModelFiles();
      if (_modelDir == null) {
        _setError('模型文件准备失败');
        return false;
      }

      // 创建流式识别器
      final config = _createOnlineRecognizerConfig();
      _recognizer = sherpa.OnlineRecognizer(config);
      _stream = _recognizer!.createStream();

      _updateState(RecognizerState.ready);
      debugPrint('ParaformerRecognizerService 初始化成功');
      return true;
    } catch (e, stack) {
      debugPrint('ParaformerRecognizerService 初始化错误: $e');
      debugPrint('Stack trace: $stack');
      _setError('初始化失败: $e');
      return false;
    }
  }

  /// 准备模型文件
  Future<String?> _prepareModelFiles() async {
    try {
      if (modelLocalPath == null) {
        debugPrint('模型路径未配置');
        return null;
      }

      // 流式模型需要 encoder 和 decoder，这里使用同一个模型文件
      final modelFile = File('${modelLocalPath!}/$modelFileName');
      final tokensFile = File('${modelLocalPath!}/tokens.txt');

      if (await modelFile.exists() && await tokensFile.exists()) {
        debugPrint('使用本地模型: $modelLocalPath');
        return modelLocalPath;
      }

      debugPrint('模型文件不存在: $modelLocalPath');
      return null;
    } catch (e) {
      debugPrint('准备模型文件失败: $e');
      return null;
    }
  }

  /// 创建在线识别器配置
  sherpa.OnlineRecognizerConfig _createOnlineRecognizerConfig() {
    return sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        paraformer: sherpa.OnlineParaformerModelConfig(
          encoder: '$_modelDir/$modelFileName',
          decoder: '$_modelDir/$modelFileName',
        ),
        tokens: '$_modelDir/tokens.txt',
        numThreads: numThreads,
        provider: 'cpu',
        modelType: 'paraformer',
      ),
      enableEndpoint: true,
      rule1MinTrailingSilence: 2.4,
      rule2MinTrailingSilence: 1.2,
      rule3MinUtteranceLength: 20,
    );
  }

  /// 开始监听
  void startListening() {
    if (!isInitialized || _recognizer == null) {
      debugPrint('识别器未初始化');
      return;
    }

    _recognizedText = '';
    _partialText = '';
    _soundLevel = 0.0;

    // 重新创建 stream
    _stream = _recognizer!.createStream();

    _updateState(RecognizerState.listening);
    notifyListeners();
  }

  /// 处理音频数据
  ///
  /// [pcmData] 16位有符号整数 PCM 数据
  void processAudioData(Uint8List pcmData) {
    if (!isListening || _recognizer == null || _stream == null) return;

    try {
      // 转换为 Float32
      final samples = _pcm16ToFloat32(pcmData);

      // 更新音量
      _updateSoundLevel(samples);

      // 输入到识别器
      _stream!.acceptWaveform(sampleRate: sampleRate, samples: samples);

      // 解码
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }

      // 获取结果
      final result = _recognizer!.getResult(_stream!);
      if (result.text.isNotEmpty) {
        _partialText = result.text;
        notifyListeners();
      }

      // 检查是否检测到端点（说话结束）
      if (_recognizer!.isEndpoint(_stream!)) {
        // 将部分结果移到最终结果
        if (_partialText.isNotEmpty) {
          _recognizedText += _partialText;
          _partialText = '';
        }
        // 重置 stream 以继续识别
        _recognizer!.reset(_stream!);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('处理音频数据错误: $e');
    }
  }

  /// 停止监听并获取最终结果
  RecognitionResult stopListening() {
    if (_stream != null && _recognizer != null) {
      // 标记输入结束
      _stream!.inputFinished();

      // 最后解码
      while (_recognizer!.isReady(_stream!)) {
        _recognizer!.decode(_stream!);
      }

      // 获取最终结果
      final result = _recognizer!.getResult(_stream!);
      if (result.text.isNotEmpty) {
        _recognizedText += result.text;
      }
      _partialText = '';
    }

    final finalResult = RecognitionResult(
      text: _recognizedText.trim(),
      isFinal: true,
    );

    _soundLevel = 0.0;
    _updateState(RecognizerState.ready);

    return finalResult;
  }

  /// 取消监听
  void cancelListening() {
    _recognizedText = '';
    _partialText = '';
    _soundLevel = 0.0;

    if (_recognizer != null) {
      _stream = _recognizer!.createStream();
    }

    _updateState(RecognizerState.ready);
  }

  /// 重置
  void reset() {
    _recognizedText = '';
    _partialText = '';
    _soundLevel = 0.0;
    _errorMessage = '';

    if (_recognizer != null) {
      _stream = _recognizer!.createStream();
    }

    _updateState(RecognizerState.ready);
  }

  /// PCM 16位转 Float32
  Float32List _pcm16ToFloat32(Uint8List pcm16) {
    final length = pcm16.length ~/ 2;
    if (length == 0) return Float32List(0);

    final int16Data = Int16List.view(pcm16.buffer, 0, length);
    final float32Data = Float32List(length);

    for (var i = 0; i < length; i++) {
      float32Data[i] = int16Data[i] / 32768.0;
    }

    return float32Data;
  }

  /// 更新音量级别
  void _updateSoundLevel(Float32List samples) {
    if (samples.isEmpty) return;

    double sum = 0;
    for (var sample in samples) {
      sum += sample.abs();
    }
    final avg = sum / samples.length;

    _soundLevel = (avg * 8).clamp(0.0, 1.0);
    notifyListeners();
  }

  /// 更新状态
  void _updateState(RecognizerState newState) {
    _state = newState;
    notifyListeners();
  }

  /// 设置错误
  void _setError(String message) {
    _errorMessage = message;
    _updateState(RecognizerState.error);
  }

  @override
  void dispose() {
    _stream = null;
    _recognizer = null;
    super.dispose();
  }
}

/// 简化版识别器（离线非流式，用于模型不支持流式的情况）
class SimpleParaformerRecognizer extends ChangeNotifier {
  /// 模型文件名
  final String modelFileName;

  /// 词表文件名
  final String tokensFileName;

  /// 采样率
  final int sampleRate;

  /// 识别推理线程数。移动端建议设为 1 以减轻发热与耗电，桌面端可用 2。
  final int numThreads;

  // 注意：Paraformer 模型不支持热词功能
  // 热词纠错请使用 GlobalTextCorrector 进行后处理

  // 状态
  RecognizerState _state = RecognizerState.uninitialized;
  String _errorMessage = '';
  String _recognizedText = '';
  double _soundLevel = 0.0;

  // 音频缓存
  final List<Float32List> _audioChunks = [];

  // sherpa_onnx 离线识别器
  sherpa.OfflineRecognizer? _recognizer;
  String? _modelDir;

  /// 当前状态
  RecognizerState get state => _state;

  /// 错误信息
  String get errorMessage => _errorMessage;

  /// 识别文本
  String get recognizedText => _recognizedText;

  /// 音量级别
  double get soundLevel => _soundLevel;

  /// 是否已初始化
  bool get isInitialized =>
      _state != RecognizerState.uninitialized &&
      _state != RecognizerState.initializing &&
      _state != RecognizerState.error;

  /// 是否正在监听
  bool get isListening => _state == RecognizerState.listening;

  /// 本地模型目录路径（从云端下载后使用）
  final String? modelLocalPath;

  SimpleParaformerRecognizer({
    required this.modelLocalPath,
    this.modelFileName = 'model.int8.onnx',
    this.tokensFileName = 'tokens.txt',
    this.sampleRate = 16000,
    int? numThreads,
  }) : numThreads =
            numThreads ?? (Platform.isIOS || Platform.isAndroid ? 1 : 2);

  /// 初始化
  Future<bool> initialize() async {
    if (_state == RecognizerState.initializing) return false;
    if (isInitialized) return true;

    _updateState(RecognizerState.initializing);

    try {
      // 初始化 sherpa_onnx 绑定
      sherpa.initBindings();

      _modelDir = await _prepareModelFiles();
      if (_modelDir == null) {
        _setError('模型文件准备失败');
        return false;
      }

      // Paraformer 只支持 greedy_search，不支持热词
      // numThreads 移动端默认 1 以减轻发热
      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          paraformer: sherpa.OfflineParaformerModelConfig(
            model: '$_modelDir/$modelFileName',
          ),
          tokens: '$_modelDir/tokens.txt',
          numThreads: numThreads,
          provider: 'cpu',
          debug: false,
        ),
        decodingMethod: 'greedy_search',
      );

      debugPrint('Paraformer 配置:');
      debugPrint('  model: $_modelDir/$modelFileName');
      debugPrint('  tokens: $_modelDir/tokens.txt');
      debugPrint('  numThreads: $numThreads (移动端建议 1 以减轻发热)');

      // 检查文件是否存在
      final modelFile = File('$_modelDir/$modelFileName');
      final tokensFile = File('$_modelDir/tokens.txt');
      debugPrint(
          '  model文件存在: ${await modelFile.exists()}, 大小: ${await modelFile.length()} bytes');
      debugPrint(
          '  tokens文件存在: ${await tokensFile.exists()}, 大小: ${await tokensFile.length()} bytes');

      _recognizer = sherpa.OfflineRecognizer(config);
      debugPrint('Paraformer 识别器创建成功');
      _updateState(RecognizerState.ready);
      return true;
    } catch (e) {
      debugPrint('SimpleParaformerRecognizer 初始化错误: $e');
      _setError('初始化失败: $e');
      return false;
    }
  }

  Future<String?> _prepareModelFiles() async {
    try {
      if (modelLocalPath == null) {
        debugPrint('模型路径未配置');
        return null;
      }

      final modelFile = File('${modelLocalPath!}/$modelFileName');
      final tokensFile = File('${modelLocalPath!}/tokens.txt');

      if (await modelFile.exists() && await tokensFile.exists()) {
        debugPrint('使用本地模型: $modelLocalPath');
        return modelLocalPath;
      }

      debugPrint('模型文件不存在: $modelLocalPath');
      return null;
    } catch (e) {
      debugPrint('准备模型文件失败: $e');
      return null;
    }
  }

  /// 开始监听
  void startListening() {
    _audioChunks.clear();
    _recognizedText = '';
    _updateState(RecognizerState.listening);
  }

  /// 处理音频数据
  void processAudioData(Uint8List pcmData) {
    if (!isListening) {
      debugPrint('processAudioData: 不在监听状态');
      return;
    }

    final samples = _pcm16ToFloat32(pcmData);
    if (samples.isNotEmpty) {
      _audioChunks.add(samples);
      _updateSoundLevel(samples);
    }
  }

  /// 停止监听并识别
  Future<RecognitionResult> stopListening() async {
    debugPrint(
        'stopListening: _recognizer=${_recognizer != null}, chunks=${_audioChunks.length}');

    if (_recognizer == null) {
      debugPrint('识别器未初始化');
      reset();
      return RecognitionResult.empty;
    }

    if (_audioChunks.isEmpty) {
      debugPrint('没有录制到音频数据');
      reset();
      return RecognitionResult.empty;
    }

    _updateState(RecognizerState.processing);

    try {
      // 合并音频
      int totalLength = 0;
      for (var chunk in _audioChunks) {
        totalLength += chunk.length;
      }

      debugPrint('总音频样本数: $totalLength, 时长约 ${totalLength / sampleRate} 秒');

      final allSamples = Float32List(totalLength);
      int offset = 0;
      for (var chunk in _audioChunks) {
        allSamples.setAll(offset, chunk);
        offset += chunk.length;
      }

      // 检查音频数据范围
      double minVal = 0, maxVal = 0;
      for (var sample in allSamples) {
        if (sample < minVal) minVal = sample;
        if (sample > maxVal) maxVal = sample;
      }
      debugPrint('音频数据范围: min=$minVal, max=$maxVal');

      // 识别
      final stream = _recognizer!.createStream();
      debugPrint('Stream 创建成功');
      stream.acceptWaveform(sampleRate: sampleRate, samples: allSamples);
      debugPrint('acceptWaveform 完成');
      _recognizer!.decode(stream);
      debugPrint('decode 完成');

      // 通过 recognizer 获取结果
      final result = _recognizer!.getResult(stream);
      debugPrint('原始结果对象: $result');
      debugPrint('result.text: "${result.text}"');
      debugPrint('result.tokens: ${result.tokens}');
      debugPrint('result.timestamps: ${result.timestamps}');
      _recognizedText = result.text.trim();

      debugPrint('识别结果: "$_recognizedText"');

      final finalText = _recognizedText;
      reset();
      return RecognitionResult(text: finalText, isFinal: true);
    } catch (e, stack) {
      debugPrint('识别错误: $e');
      debugPrint('Stack: $stack');
      _setError('识别失败: $e');
      return RecognitionResult.empty;
    }
  }

  /// 取消
  void cancelListening() {
    _audioChunks.clear();
    _recognizedText = '';
    _soundLevel = 0.0;
    _updateState(RecognizerState.ready);
  }

  /// 重置
  void reset() {
    _audioChunks.clear();
    _soundLevel = 0.0;
    _updateState(RecognizerState.ready);
  }

  Float32List _pcm16ToFloat32(Uint8List pcm16) {
    final length = pcm16.length ~/ 2;
    if (length == 0) return Float32List(0);

    final int16Data = Int16List.view(pcm16.buffer, 0, length);
    final float32Data = Float32List(length);

    for (var i = 0; i < length; i++) {
      float32Data[i] = int16Data[i] / 32768.0;
    }

    return float32Data;
  }

  void _updateSoundLevel(Float32List samples) {
    if (samples.isEmpty) return;

    double sum = 0;
    for (var sample in samples) {
      sum += sample.abs();
    }
    final avg = sum / samples.length;

    _soundLevel = (avg * 8).clamp(0.0, 1.0);
    notifyListeners();
  }

  void _updateState(RecognizerState newState) {
    _state = newState;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _updateState(RecognizerState.error);
  }

  @override
  void dispose() {
    _audioChunks.clear();
    _recognizer = null;
    super.dispose();
  }
}
