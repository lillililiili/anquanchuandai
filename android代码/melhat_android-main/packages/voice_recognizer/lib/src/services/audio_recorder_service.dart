import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 录音状态
enum RecordingState {
  /// 空闲
  idle,

  /// 正在录音
  recording,

  /// 暂停
  paused,

  /// 错误
  error,
}

/// 录音结果
class RecordingResult {
  /// WAV 文件路径
  final String? wavFilePath;

  /// PCM 音频数据
  final Uint8List pcmData;

  /// 录音时长（秒）
  final double durationSeconds;

  RecordingResult({
    this.wavFilePath,
    required this.pcmData,
    required this.durationSeconds,
  });

  /// 是否有录音数据
  bool get hasData => pcmData.isNotEmpty;

  /// 空结果
  static RecordingResult get empty => RecordingResult(
        pcmData: Uint8List(0),
        durationSeconds: 0,
      );
}

/// 音频录制服务
///
/// 封装 record 包，提供音频流录制功能
/// 支持缓存录音数据，录音结束后一次性获取完整音频
class AudioRecorderService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();

  RecordingState _state = RecordingState.idle;
  String _errorMessage = '';
  double _amplitude = 0.0;
  int _recordingDuration = 0;

  StreamSubscription<Uint8List>? _audioSubscription;
  Timer? _durationTimer;

  /// 录音数据缓存
  final List<Uint8List> _audioChunks = [];

  /// 录音配置
  final int sampleRate;
  final int numChannels;

  /// 当前状态
  RecordingState get state => _state;

  /// 错误信息
  String get errorMessage => _errorMessage;

  /// 当前振幅 (0.0 - 1.0)
  double get amplitude => _amplitude;

  /// 录音时长（秒）
  int get recordingDuration => _recordingDuration;

  /// 是否正在录音
  bool get isRecording => _state == RecordingState.recording;

  AudioRecorderService({
    this.sampleRate = 16000,
    this.numChannels = 1,
  });

  /// 获取缓存的所有音频数据（PCM 格式）
  Uint8List get audioData {
    if (_audioChunks.isEmpty) return Uint8List(0);

    int totalLength = 0;
    for (var chunk in _audioChunks) {
      totalLength += chunk.length;
    }

    final result = Uint8List(totalLength);
    int offset = 0;
    for (var chunk in _audioChunks) {
      result.setAll(offset, chunk);
      offset += chunk.length;
    }

    return result;
  }

  /// 获取音频时长（秒）
  double get audioDurationSeconds {
    final totalBytes =
        _audioChunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    // 16位 PCM，每个采样 2 字节
    final totalSamples = totalBytes ~/ 2;
    return totalSamples / sampleRate;
  }

  /// 检查并请求麦克风权限
  Future<bool> checkPermission() async {
    final status = await Permission.microphone.status;
    debugPrint('麦克风权限状态: $status');

    if (status.isGranted) {
      debugPrint('麦克风权限已授予');
      return true;
    }

    debugPrint('请求麦克风权限...');
    final result = await Permission.microphone.request();
    debugPrint('权限请求结果: $result');

    if (result.isGranted) {
      return true;
    }

    if (result.isPermanentlyDenied) {
      _setError('麦克风权限被永久拒绝，请在设置中开启');
    } else {
      _setError('请授予麦克风权限');
    }

    return false;
  }

  /// 开始录音并缓存音频数据
  ///
  /// [onAudioData] 音频数据回调，每次接收到新数据时调用（可选）
  /// [maxDuration] 最大录音时长（秒），达到后自动停止
  /// [onMaxDurationReached] 达到最大时长时的回调
  Future<bool> startRecording({
    void Function(Uint8List data)? onAudioData,
    int? maxDuration,
    VoidCallback? onMaxDurationReached,
  }) async {
    if (_state == RecordingState.recording) {
      debugPrint('已经在录音中');
      return false;
    }

    // 检查权限
    if (!await checkPermission()) {
      return false;
    }

    try {
      // 清空之前的录音数据
      _audioChunks.clear();

      // 开始录音流
      debugPrint('开始录音: sampleRate=$sampleRate, numChannels=$numChannels');
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: numChannels,
        ),
      );
      debugPrint('录音流已启动');

      _recordingDuration = 0;
      _updateState(RecordingState.recording);

      int dataCount = 0;
      // 监听音频数据并缓存
      _audioSubscription = stream.listen(
        (data) {
          dataCount++;
          if (dataCount <= 3 || dataCount % 20 == 0) {
            debugPrint('收到音频数据 #$dataCount: ${data.length} bytes');
          }

          // 缓存音频数据
          _audioChunks.add(Uint8List.fromList(data));

          // 回调（可选）
          onAudioData?.call(data);
          _updateAmplitude(data);
        },
        onError: (error) {
          debugPrint('录音流错误: $error');
          _setError('录音错误: $error');
          stopRecording();
        },
      );

      // 录音时长计时器
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingDuration++;
        notifyListeners();

        // 检查是否达到最大时长
        if (maxDuration != null && _recordingDuration >= maxDuration) {
          timer.cancel();
          onMaxDurationReached?.call();
        }
      });

      return true;
    } catch (e) {
      debugPrint('启动录音失败: $e');
      _setError('启动录音失败: $e');
      return false;
    }
  }

  /// 停止录音并返回录音结果
  ///
  /// 返回 [RecordingResult]，包含 PCM 数据和 WAV 文件路径
  Future<RecordingResult> stopRecording() async {
    _durationTimer?.cancel();
    _durationTimer = null;

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('停止录音错误: $e');
    }

    // 获取完整的音频数据
    final completeAudioData = audioData;
    final duration = audioDurationSeconds;
    debugPrint(
        '录音完成: ${completeAudioData.length} bytes, 时长: ${duration.toStringAsFixed(2)}s');

    // 保存为 WAV 文件
    String? wavPath;
    if (completeAudioData.isNotEmpty) {
      wavPath = await _saveToWavFile(completeAudioData);
    }

    _amplitude = 0.0;
    _updateState(RecordingState.idle);

    return RecordingResult(
      wavFilePath: wavPath,
      pcmData: completeAudioData,
      durationSeconds: duration,
    );
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    _durationTimer?.cancel();
    _durationTimer = null;

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    try {
      await _recorder.stop();
    } catch (e) {
      debugPrint('停止录音错误: $e');
    }

    _audioChunks.clear();
    _recordingDuration = 0;
    _amplitude = 0.0;
    _updateState(RecordingState.idle);
  }

  /// 保存为 WAV 文件（调试用）
  Future<String?> _saveToWavFile(Uint8List pcmData) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${tempDir.path}/recording_$timestamp.wav';

      // 创建 WAV 文件头
      final wavHeader = _createWavHeader(pcmData.length);
      final wavData = Uint8List(wavHeader.length + pcmData.length);
      wavData.setAll(0, wavHeader);
      wavData.setAll(wavHeader.length, pcmData);

      final file = File(filePath);
      await file.writeAsBytes(wavData);
      debugPrint('录音文件已保存: $filePath');

      return filePath;
    } catch (e) {
      debugPrint('保存录音文件失败: $e');
      return null;
    }
  }

  /// 创建 WAV 文件头
  Uint8List _createWavHeader(int dataSize) {
    final header = ByteData(44);

    // RIFF chunk
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, 36 + dataSize, Endian.little); // file size - 8
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt chunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // fmt chunk size
    header.setUint16(20, 1, Endian.little); // audio format (1 = PCM)
    header.setUint16(22, numChannels, Endian.little); // channels
    header.setUint32(24, sampleRate, Endian.little); // sample rate
    header.setUint32(
        28, sampleRate * numChannels * 2, Endian.little); // byte rate
    header.setUint16(32, numChannels * 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample

    // data chunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little); // data size

    return header.buffer.asUint8List();
  }

  /// 从 PCM 数据计算振幅
  void _updateAmplitude(Uint8List pcmData) {
    if (pcmData.isEmpty) return;

    final length = pcmData.length ~/ 2;
    if (length == 0) return;

    final int16Data = Int16List.view(pcmData.buffer, 0, length);

    double sum = 0;
    for (var sample in int16Data) {
      sum += sample.abs();
    }

    final avg = sum / int16Data.length / 32768.0;
    _amplitude = (avg * 8).clamp(0.0, 1.0);
    notifyListeners();
  }

  void _updateState(RecordingState newState) {
    _state = newState;
    notifyListeners();
  }

  void _setError(String message) {
    _errorMessage = message;
    _updateState(RecordingState.error);
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _audioSubscription?.cancel();
    _audioChunks.clear();
    _recorder.dispose();
    super.dispose();
  }
}
