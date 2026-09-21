import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:voice_recognizer/voice_recognizer.dart';

import '../animations/voice_animations.dart';
import '../services/audio_recorder_service.dart';
import '../services/paraformer_recognizer.dart';
import '../services/voice_recognizer_registry.dart';

/// 显示语音录入弹窗
///
/// [context] 上下文
/// [themeColor] 主题颜色
/// [maxDuration] 最大录音时长（秒）
/// [useGlobalService] 是否使用全局服务（推荐开启）
///
/// 返回识别结果文本，如果取消则返回 null
Future<String?> showVoiceRecordOverlay({
  required BuildContext context,
  Color? themeColor,
  int maxDuration = 10,
  String title = '语音输入',
  String hintText = '长按按钮开始录音...',
  bool useGlobalService = true,
}) {
  return Navigator.of(context).push<String>(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      pageBuilder: (context, animation, secondaryAnimation) {
        return VoiceRecordOverlay(
          themeColor: themeColor ?? Theme.of(context).primaryColor,
          maxDuration: maxDuration,
          useGlobalService: useGlobalService,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 200),
    ),
  );
}

/// 语音录入弹窗组件
///
/// 简洁设计：只有背景动画和语音按钮
/// - 没有录音时点击按钮外区域退出
/// - 录音结束后自动识别并返回结果
class VoiceRecordOverlay extends StatefulWidget {
  final Color themeColor;
  final int maxDuration;
  final bool useGlobalService;

  const VoiceRecordOverlay({
    super.key,
    required this.themeColor,
    this.maxDuration = 10,
    this.useGlobalService = true,
  });

  @override
  State<VoiceRecordOverlay> createState() => _VoiceRecordOverlayState();
}

class _VoiceRecordOverlayState extends State<VoiceRecordOverlay>
    with TickerProviderStateMixin {
  // 服务
  SimpleParaformerRecognizer? _recognizer;
  late AudioRecorderService _recorder;

  // 服务管理
  bool _useGlobalService = false;
  bool _ownsRecognizer = false;

  // 状态
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isInitialized = false;
  int _recordingDuration = 0;

  // 动画
  late AnimationController _backgroundAnimController;
  late Animation<double> _backgroundAnimation;

  Timer? _maxDurationTimer;

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
      final registry = VoiceRecognizerRegistry.instance;
      registry.addListener(_onRegistryChanged);

      if (registry.isInitialized && registry.recognizer != null) {
        _recognizer = registry.recognizer;
        _isInitialized = true;
        _ownsRecognizer = false;
      } else if (!registry.isInitializing) {
        registry.preInitialize();
      }
    } else {
      _createOwnRecognizer();
    }
  }

  void _createOwnRecognizer() async {
    final downloadService = ModelDownloadService.instance;
    final modelPath = await downloadService.getModelPath();

    if (modelPath == null) {
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
      }
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
      });
      _recognizer!.addListener(_onRecognizerChanged);
    }
  }

  void _initAnimations() {
    _backgroundAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _backgroundAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _backgroundAnimController, curve: Curves.easeOut),
    );
    _backgroundAnimController.forward();
  }

  Future<void> _initializeRecognizer() async {
    if (_recognizer == null) return;

    final success = await _recognizer!.initialize();
    if (mounted) {
      setState(() {
        _isInitialized = success;
      });
    }
  }

  void _onRecognizerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _startRecording() async {
    if (_isRecording || _isProcessing || !_isInitialized) return;
    if (_recognizer == null) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isRecording = true;
      _recordingDuration = 0;
    });

    final success = await _recorder.startRecording(
      onAudioData: (data) {
        _recognizer?.processAudioData(data);
      },
      maxDuration: widget.maxDuration,
      onMaxDurationReached: () {
        _stopRecording();
      },
    );

    if (!success && mounted) {
      _stopRecording();
      return;
    }

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

    HapticFeedback.lightImpact();
    _maxDurationTimer?.cancel();

    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    final recordingResult = await _recorder.stopRecording();

    if (!recordingResult.hasData || _recognizer == null) {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      return;
    }

    _recognizer!.startListening();
    _recognizer!.processAudioData(recordingResult.pcmData);
    final result = await _recognizer!.stopListening();

    if (mounted) {
      setState(() => _isProcessing = false);

      if (result.text.isNotEmpty) {
        // 识别成功，自动返回结果
        final correctedText =
            await GlobalTextCorrector.instance.correct(result.text);
        Navigator.of(context).pop(correctedText);
      }
    }
  }

  void _cancelRecording() {
    if (!_isRecording) return;

    HapticFeedback.heavyImpact();

    _maxDurationTimer?.cancel();
    _recorder.cancelRecording();
    _recognizer?.cancelListening();

    setState(() {
      _isRecording = false;
      _isProcessing = false;
    });
  }

  void _onBackgroundTap() {
    // 录音中或处理中不允许退出
    if (_isRecording || _isProcessing) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _maxDurationTimer?.cancel();
    _backgroundAnimController.dispose();

    if (_useGlobalService) {
      VoiceRecognizerRegistry.instance.removeListener(_onRegistryChanged);
    }

    if (_recognizer != null) {
      _recognizer!.removeListener(_onRecognizerChanged);
      if (_ownsRecognizer) {
        _recognizer!.dispose();
      }
    }

    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnimatedBuilder(
      animation: _backgroundAnimation,
      builder: (context, child) {
        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onBackgroundTap,
            child: Container(
              color: Colors.black.withOpacity(0.6 * _backgroundAnimation.value),
              child: Stack(
                children: [
                  // 背景动画层（放在按钮位置）
                  Positioned(
                    bottom: 80 + bottomPadding,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _buildBackgroundAnimation(),
                    ),
                  ),
                  // 按钮层（底部居中）
                  Positioned(
                    bottom: 80 + bottomPadding,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _buildVoiceButton(),
                    ),
                  ),
                  // 状态提示（按钮上方）
                  Positioned(
                    bottom: 200 + bottomPadding,
                    left: 0,
                    right: 0,
                    child: _buildStatusHint(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackgroundAnimation() {
    final size = MediaQuery.of(context).size.width * 0.8;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外层波纹
          if (_isRecording)
            RippleAnimation(
              isAnimating: true,
              color: widget.themeColor,
              size: size * 0.9,
            ),
          // 音量环
          if (_isRecording)
            SoundLevelIndicator(
              level: _recognizer?.soundLevel ?? 0.0,
              color: widget.themeColor,
              size: 160,
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // 阻止点击穿透到背景
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      onLongPressCancel: () => _cancelRecording(),
      child: PulseAnimation(
        isAnimating: _isRecording,
        child: _buildButtonContent(),
      ),
    );
  }

  Widget _buildButtonContent() {
    // 处理中
    if (_isProcessing) {
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.15),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    // 初始化中
    if (!_isInitialized) {
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 2,
          ),
        ),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white54,
            ),
          ),
        ),
      );
    }

    // 正常状态 / 录音中
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.themeColor,
            widget.themeColor.withOpacity(0.7),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: widget.themeColor.withOpacity(_isRecording ? 0.6 : 0.4),
            blurRadius: _isRecording ? 40 : 20,
            spreadRadius: _isRecording ? 10 : 0,
          ),
        ],
      ),
      child: Icon(
        _isRecording ? Icons.mic : Icons.mic_none,
        size: 44,
        color: Colors.white,
      ),
    );
  }

  Widget _buildStatusHint() {
    String text;
    if (_isProcessing) {
      text = '识别中...';
    } else if (_isRecording) {
      final remaining = widget.maxDuration - _recordingDuration;
      text = '松开结束 · ${remaining}s';
    } else if (!_isInitialized) {
      text = '初始化中...';
    } else {
      text = '长按说话';
    }

    return Opacity(
      opacity: _backgroundAnimation.value,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 16,
          color: Colors.white.withOpacity(0.9),
          fontWeight: _isRecording ? FontWeight.w600 : FontWeight.normal,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
