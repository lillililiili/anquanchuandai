import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_recognizer/voice_recognizer.dart';

/// 语音录入按钮组件
///
/// 长按开始录音，松开结束并自动识别
/// 支持最大录音时长限制和丰富的动画效果
///
/// ## 推荐使用方式
///
/// 为了获得最佳用户体验，建议在应用启动时提前初始化语音识别服务：
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   // 提前初始化，使用时无需等待
///   VoiceRecognizerRegistry.instance.preInitialize();
///   runApp(MyApp());
/// }
/// ```
class VoiceRecordButton extends StatefulWidget {
  /// 识别结果回调
  final void Function(String text)? onResult;

  /// 部分识别结果回调（流式识别）
  final void Function(String text)? onPartialResult;

  /// 录音状态变化回调
  final void Function(bool isRecording)? onRecordingStateChanged;

  /// 错误回调
  final void Function(String error)? onError;

  /// 主题颜色
  final Color? themeColor;

  /// 按钮大小
  final double size;

  /// 最大录音时长（秒）
  final int maxDuration;

  /// 是否显示录音时长
  final bool showDuration;

  /// 是否显示波纹动画
  final bool showRipple;

  /// 是否启用触感反馈
  final bool enableHaptic;

  /// 自定义按钮图标
  final IconData? icon;

  /// 是否使用全局服务（推荐开启）
  ///
  /// 开启后会使用 [VoiceRecognizerRegistry] 管理的全局实例，
  /// 可以提前初始化，避免每次使用时等待。
  final bool useGlobalService;

  const VoiceRecordButton({
    super.key,
    this.onResult,
    this.onPartialResult,
    this.onRecordingStateChanged,
    this.onError,
    this.themeColor,
    this.size = 64,
    this.maxDuration = 10,
    this.showDuration = true,
    this.showRipple = true,
    this.enableHaptic = true,
    this.icon,
    this.useGlobalService = true,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with TickerProviderStateMixin {
  // 服务 - 使用离线识别器，因为 Paraformer 离线模型不支持流式
  SimpleParaformerRecognizer? _recognizer;
  late AudioRecorderService _recorder;

  // 是否使用全局服务
  bool _useGlobalService = false;
  // 是否拥有识别器（需要在 dispose 时释放）
  bool _ownsRecognizer = false;

  // 状态
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isInitialized = false;
  int _recordingDuration = 0;
  String? _errorMessage;

  // 下载状态
  bool _isModelDownloaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  // 动画
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  Timer? _maxDurationTimer;

  Color get _themeColor => widget.themeColor ?? Theme.of(context).primaryColor;

  @override
  void initState() {
    super.initState();
    _initServices();
    _initAnimations();
  }

  void _initServices() {
    _recorder = AudioRecorderService();
    _useGlobalService = widget.useGlobalService;

    if (_useGlobalService) {
      // 使用全局服务注册中心
      final registry = VoiceRecognizerRegistry.instance;
      registry.addListener(_onRegistryChanged);

      // 监听下载服务状态
      registry.downloadService.addListener(_onDownloadStateChanged);

      // 检查模型是否已下载
      _isModelDownloaded = registry.isModelDownloaded;

      if (registry.isInitialized && registry.recognizer != null) {
        // 全局服务已初始化，直接使用
        _recognizer = registry.recognizer;
        _isInitialized = true;
        _isModelDownloaded = true;
        _ownsRecognizer = false;
        debugPrint('VoiceRecordButton: 使用已初始化的全局服务');
      } else if (registry.isInitializing) {
        // 正在初始化，等待完成
        debugPrint('VoiceRecordButton: 等待全局服务初始化完成');
      } else if (_isModelDownloaded) {
        // 模型已下载但未初始化，触发初始化
        debugPrint('VoiceRecordButton: 模型已下载，触发初始化');
        registry.preInitialize();
      } else {
        // 模型未下载，等待用户触发下载
        debugPrint('VoiceRecordButton: 模型未下载，显示下载提示');
      }
    } else {
      // 创建独立实例（兼容旧行为）
      _createOwnRecognizer();
    }
  }

  /// 下载状态变化回调
  void _onDownloadStateChanged() {
    if (!mounted) return;

    final registry = VoiceRecognizerRegistry.instance;
    final downloadService = registry.downloadService;

    setState(() {
      _isDownloading = downloadService.isDownloading;
      _downloadProgress = downloadService.progress;
      _isModelDownloaded = downloadService.isModelReady;

      if (downloadService.state == DownloadState.error) {
        _errorMessage = downloadService.errorMessage;
      }
    });
  }

  /// 开始下载模型
  Future<void> _startDownload() async {
    final registry = VoiceRecognizerRegistry.instance;
    final success = await registry.downloadModel();

    if (success && mounted) {
      setState(() {
        _isModelDownloaded = true;
        _isInitialized = true;
        _recognizer = registry.recognizer;
      });
    }
  }

  void _createOwnRecognizer() async {
    // 独立实例模式需要先获取模型路径
    final downloadService = ModelDownloadService.instance;
    final modelPath = await downloadService.getModelPath();

    if (modelPath == null) {
      setState(() {
        _isModelDownloaded = false;
      });
      return;
    }

    _recognizer = SimpleParaformerRecognizer(
      modelLocalPath: modelPath,
    );
    _ownsRecognizer = true;
    _recognizer!.addListener(_onRecognizerChanged);
    _initializeRecognizer();
  }

  void _onRegistryChanged() {
    if (!mounted) return;

    final registry = VoiceRecognizerRegistry.instance;

    if (registry.isInitialized && registry.recognizer != null) {
      setState(() {
        _recognizer = registry.recognizer;
        _isInitialized = true;
        _errorMessage = null;
      });
      // 添加监听以更新 UI（音量等）
      _recognizer!.addListener(_onRecognizerChanged);
      debugPrint('VoiceRecordButton: 全局服务初始化完成');
    } else if (registry.hasError) {
      setState(() {
        _isInitialized = false;
        _errorMessage = registry.errorMessage;
      });
      debugPrint('VoiceRecordButton: 全局服务初始化失败 - ${registry.errorMessage}');
    }
  }

  void _initAnimations() {
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeRecognizer() async {
    if (_recognizer == null) return;

    final success = await _recognizer!.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = success;
        if (!success) {
          _errorMessage = _recognizer!.errorMessage;
        }
      });
    }
  }

  void _onRecognizerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isProcessing) return;

    if (widget.enableHaptic) {
      HapticFeedback.mediumImpact();
    }

    setState(() {
      _isRecording = true;
      _recordingDuration = 0;
      _errorMessage = null;
    });

    _scaleController.forward();
    widget.onRecordingStateChanged?.call(true);

    // 步骤1: 开始录音（只录音，不处理）
    debugPrint('=== 开始录音 ===');
    final success = await _recorder.startRecording(
      onAudioData: (data) {
        // 实时更新音量显示
        _recognizer?.processAudioData(data);
      },
      maxDuration: widget.maxDuration,
      onMaxDurationReached: () {
        debugPrint('达到最大录音时长，自动停止');
        _stopRecording();
      },
    );

    if (!success && mounted) {
      _showError(_recorder.errorMessage);
      _stopRecording();
      return;
    }

    // 更新录音时长
    _maxDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingDuration = _recorder.recordingDuration;
        });
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    if (widget.enableHaptic) {
      HapticFeedback.lightImpact();
    }

    _maxDurationTimer?.cancel();
    _scaleController.reverse();

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    widget.onRecordingStateChanged?.call(false);

    // 步骤2: 停止录音，获取完整的音频数据（自动保存为 WAV 文件）
    debugPrint('=== 停止录音，获取音频数据 ===');
    final recordingResult = await _recorder.stopRecording();

    if (!recordingResult.hasData) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showError('未录制到音频数据');
      }
      return;
    }

    debugPrint('录音数据大小: ${recordingResult.pcmData.length} bytes');
    debugPrint('录音时长: ${recordingResult.durationSeconds.toStringAsFixed(2)}s');
    if (recordingResult.wavFilePath != null) {
      debugPrint('WAV 文件路径: ${recordingResult.wavFilePath}');
    }

    // 步骤3: 将完整音频发送给模型进行识别
    if (_recognizer == null) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showError('识别服务未初始化');
      }
      return;
    }

    debugPrint('=== 开始语音识别 ===');
    _recognizer!.startListening();
    _recognizer!.processAudioData(recordingResult.pcmData);
    final result = await _recognizer!.stopListening();

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (result.isNotEmpty) {
        debugPrint('识别结果: ${result.text}');
        final correctedText =
            await GlobalTextCorrector.instance.correct(result.text);
        widget.onResult?.call(correctedText);
      } else {
        _showError('未识别到语音内容');
      }
    }
  }

  void _cancelRecording() {
    if (!_isRecording) return;

    if (widget.enableHaptic) {
      HapticFeedback.heavyImpact();
    }

    _maxDurationTimer?.cancel();
    _scaleController.reverse();

    _recorder.cancelRecording();
    _recognizer?.cancelListening();

    setState(() {
      _isRecording = false;
      _isProcessing = false;
    });

    widget.onRecordingStateChanged?.call(false);
  }

  void _showError(String message) {
    setState(() {
      _errorMessage = message;
    });
    widget.onError?.call(message);
  }

  @override
  void dispose() {
    _maxDurationTimer?.cancel();
    _scaleController.dispose();

    if (_useGlobalService) {
      // 移除全局服务监听
      VoiceRecognizerRegistry.instance.removeListener(_onRegistryChanged);
      // 移除下载服务监听
      VoiceRecognizerRegistry.instance.downloadService
          .removeListener(_onDownloadStateChanged);
    }

    if (_recognizer != null) {
      _recognizer!.removeListener(_onRecognizerChanged);
      // 只有自己创建的实例才需要 dispose
      if (_ownsRecognizer) {
        _recognizer!.dispose();
      }
    }

    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 如果模型未下载，显示下载提示
    if (!_isModelDownloaded) {
      return _buildDownloadUI();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 录音时长显示
        if (widget.showDuration && _isRecording) _buildDurationIndicator(),
        if (widget.showDuration && _isRecording) const SizedBox(height: 8),

        // 主按钮区域
        SizedBox(
          width: widget.size * 2.2,
          height: widget.size * 2.2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 波纹效果
              if (widget.showRipple)
                RippleAnimation(
                  isAnimating: _isRecording,
                  color: _themeColor,
                  size: widget.size * 2,
                ),

              // 音量指示环
              if (_isRecording)
                SoundLevelIndicator(
                  level: _recognizer?.soundLevel ?? 0.0,
                  color: _themeColor,
                  size: widget.size * 1.5,
                ),

              // 进度环
              if (_isRecording)
                ProgressRing(
                  progress: _recordingDuration / widget.maxDuration,
                  color: _themeColor,
                  size: widget.size * 1.2,
                ),

              // 主按钮
              _buildMainButton(),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 状态提示
        _buildStatusText(),
      ],
    );
  }

  Widget _buildDurationIndicator() {
    final remaining = widget.maxDuration - _recordingDuration;
    final isWarning = remaining <= 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isWarning ? Colors.red.shade50 : _themeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RecordingDot(color: isWarning ? Colors.red : _themeColor),
          const SizedBox(width: 6),
          Text(
            '$_recordingDuration s / ${widget.maxDuration} s',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isWarning ? Colors.red : _themeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainButton() {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      onLongPressCancel: () => _cancelRecording(),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return PulseAnimation(
            isAnimating: _isRecording,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: _buildButtonContent(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildButtonContent() {
    if (_isProcessing) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade200,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade200,
        ),
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _isRecording
              ? [_themeColor, _themeColor.withOpacity(0.8)]
              : [_themeColor.withOpacity(0.9), _themeColor.withOpacity(0.7)],
        ),
        boxShadow: [
          BoxShadow(
            color: _themeColor.withOpacity(_isRecording ? 0.5 : 0.3),
            blurRadius: _isRecording ? 20 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        _isRecording ? Icons.mic : (widget.icon ?? Icons.mic_none),
        size: widget.size * 0.45,
        color: Colors.white,
      ),
    );
  }

  /// 构建下载提示 UI
  Widget _buildDownloadUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 下载按钮或进度
        GestureDetector(
          onTap: _isDownloading ? null : _startDownload,
          child: Container(
            width: widget.size * 1.4,
            height: widget.size * 1.4,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isDownloading
                  ? Colors.grey.shade200
                  : _themeColor.withOpacity(0.1),
              border: Border.all(
                color: _isDownloading
                    ? Colors.grey.shade300
                    : _themeColor.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: _isDownloading
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      // 进度环
                      SizedBox(
                        width: widget.size * 1.1,
                        height: widget.size * 1.1,
                        child: CircularProgressIndicator(
                          value: _downloadProgress,
                          strokeWidth: 3,
                          color: _themeColor,
                          backgroundColor: Colors.grey.shade300,
                        ),
                      ),
                      // 进度百分比
                      Text(
                        '${(_downloadProgress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _themeColor,
                        ),
                      ),
                    ],
                  )
                : Icon(
                    Icons.cloud_download,
                    size: widget.size * 0.4,
                    color: _themeColor,
                  ),
          ),
        ),

        const SizedBox(height: 12),

        // 状态文字
        Text(
          _isDownloading ? '下载中...' : '点击下载语音模型',
          style: TextStyle(
            fontSize: 12,
            color: _isDownloading ? Colors.grey.shade600 : _themeColor,
            fontWeight: FontWeight.w500,
          ),
        ),

        // 错误信息
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: TextStyle(
              fontSize: 11,
              color: Colors.red.shade400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _buildStatusText() {
    String text;
    Color color;

    if (_errorMessage != null) {
      text = _errorMessage!;
      color = Colors.red;
    } else if (_isProcessing) {
      text = '识别中...';
      color = Colors.grey.shade600;
    } else if (_isRecording) {
      text = '松开结束录音';
      color = _themeColor;
    } else if (!_isInitialized) {
      text = '初始化中...';
      color = Colors.grey.shade500;
    } else {
      text = '长按开始录音';
      color = Colors.grey.shade500;
    }

    return FadeInText(
      text: text,
      style: TextStyle(
        fontSize: 12,
        color: color,
        fontWeight: _isRecording ? FontWeight.w500 : FontWeight.normal,
      ),
    );
  }
}
